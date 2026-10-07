# Investigation — 20260824_pos-wasm-logging-graylog-review

**Status:** in progress

## Context

Pre-ticket architecture review, requested before any incident: developers are adding operational logging to the Cloud POS (Blazor WASM) that forwards to a central Azure Function relay, ultimately landing in Graylog. Questions raised: client-side bandwidth efficiency, risk of disrupting business operations (POS is WASM, single-threaded in the browser), whether a mass kill switch exists for a connectivity incident, and browser-storage semantics/persistence for undelivered logs.

Reviewed against the local `cloud/repo/SmartFran.Cloud` clone. Two independent logging paths exist in this codebase — do not conflate them.

## Confirmed facts

**Path 1 — `ProcessLogger` (tracked on `main`, unrelated to Graylog)**
- `HttpLoggerProvider` (`Source/Common/Providers/SmartFran.Cloud.Provider.Logger.Http/HttpLoggerProvider.cs`) sends structured business `LogBody` payloads (`Source/Common/Providers/SmartFran.Cloud.Provider.Contracts/Models/Logging/LogBody.cs`) to an Azure Function (`Source/Common/Functions/SmartFran.Cloud.Functions.ScheduledJobs/Functions/LogEndpoints.cs`) which persists them to **CosmosDB `BusinessLog`** — no Graylog involvement.
- Call site confirmed non-blocking: `Sale.razor.cs:715` uses `RegisterLogFireAndForget`.
- `EnableOfflineStorage` defaults `false`; even when `true`, `StoreOfflineAsync` (`HttpLoggerProvider.cs:244-257`) is an unimplemented stub (`// TODO`) — no LocalStorage/SessionStorage persistence actually happens on this path.
- Last touched by commit `cefb0a5cb` ("Logueo de apertura de turno", author `maurop-png`, 2026-04-20), identical on `main` and `origin/dev`.

**Path 2 — GSFC-839 dual logging pipeline (`origin/dev` only, NOT yet in `main`/PRO)**
- PR **#1781 "GSFC-839"** (branches `GSFC-839`, `GSFC-839-A`), author `gasparc@smartfran.com` / `gasparcsf`, merged into `origin/dev` 2026-08-21 (`6ea4bceab`). `origin/dev` HEAD as of this review: `e90670d0d` (2026-08-21), which does not touch this pipeline further.
- Flow: `ILogger.LogX` (Serilog) → `WasmForwardingSink` (`Source/Common/Providers/SmartFran.Cloud.Provider.Logger.Wasm/WasmForwardingSink.cs`) → batched POST to Azure Function `IngestLogs` (`Source/Common/Functions/SmartFran.Cloud.Pos.Wasm.Relay/IngestLogs.cs`, route `internal/log-ingest`) → re-emitted via the existing Console JSON → EventHub → consumer → **Graylog** pipeline (per code comments citing plan doc `Migracion-Estandarizacion-Logging-Graylog.md` §4.5.3/§5.5 — doc not found in this repo, likely external/Confluence).
- Client batching: `BatchSize`=50 entries or `FlushIntervalMs`=5000ms, whichever first (`WasmLoggingOptions.cs`). `Emit()` only enqueues to an in-memory `ConcurrentQueue`; the POST always runs via `Task.Run` inside `FlushAsync` — never inline with a business action, so no UI-thread stall risk from logging itself.
- Server hardening (`IngestLogs.cs`): `MaxBatchBytes` cap, default 256KB (413 if exceeded); rate limit 60 req/min/user (`RateLimitMiddleware`); Auth0 bearer required (`AuthMiddleware`).
- `DedupEnabled` (coalesces repeated error signatures within a window) defaults **`false`** — the main defense against a misbehaving JS library flooding Graylog is off by default.
- PII redaction on client before serialization: `LogRedactor.Scrub` applied to message/properties/exception message (`WasmForwardingSink.cs`, `Serialize`).
- **Kill switch exists but isn't live:** `WasmLoggingOptions.RemoteEnabled` (default `true`, public setter, `WasmLoggingOptions.cs:44`) gates `Emit()` (`WasmForwardingSink.cs:82`, read fresh on every call, not cached). Bound once at WASM boot via `IOptions<WasmLoggingOptions>.Value` (singleton) from a runtime-fetched, per-environment JSON file (confirmed `wwwroot/SmartFran.Cloud.Pos.Wasm_DEV.json` on `dev`, `"RemoteEnabled": true`) — separate from the compiled WASM binary, so editable without a full app redeploy. No `IOptionsMonitor`, no re-fetch after boot, and no JS-callable hook found (`[JSInvokable]` only exists on `BlazorErrorHandler.cs`, JS→C# direction for reporting uncaught errors, not a toggle) — confirmed no way to flip it for a terminal already open mid-shift without a page reload.
- **Feasibility of a live, no-reload kill switch:** structurally cheap. `RemoteEnabled` already has a public setter and is read fresh per call; `IOptions<WasmLoggingOptions>.Value` is a DI singleton, so any other singleton service resolving it shares the same instance. The app already keeps two live channels open per POS terminal — `SignalRService` (push, used today for KDS/cash-alert/sale-order updates) and `HeartBeatService` (poll, ~50s interval with backoff, `HeartbeatOptions.cs`) — either could be extended to call `.RemoteEnabled = false` on receipt. Not implemented today.
- **Storage is `sessionStorage`, not `localStorage`** — deliberate choice, explicit in code comment: `BrowserSessionStorage.cs` ("usamos sessionStorage (no localStorage) a propósito: el `_session_id` debe ser estable dentro de la pestaña y cambiar al cerrarla"). Consequence: undelivered batches queued for retry do **not** survive a real tab/browser close — only an in-tab reload (replayed via `ReplayPersistedAsync` in `WasmForwardingSink.cs`). Queue bounded to `MaxQueueBytes` (default 4MB) with drop-oldest eviction (`SessionStorageQueue.cs`).
- Storage access is fully async via `IJSRuntime.InvokeAsync` (`BrowserSessionStorage.cs`) — explicit comment notes sync-over-async was deliberately avoided to not deadlock the browser thread. Mitigates the naive-localStorage main-thread-blocking concern.
- Minor bug (not yet reported upstream): `WasmForwardingSink.FlushBeforeUnloadAsync` creates a `CancellationTokenSource(500ms)` but never passes it into the inner `FlushAsync()` call — the intended 500ms budget for the final flush-on-tab-close isn't actually enforced; a slow relay could stretch that unload flush toward the full `HttpTimeoutMs` (default 15s).
- Minor cost note: `SessionStorageQueue.SaveAsync` re-serializes the entire pending list on every save just to estimate size (`EstimatedSize`) — could get CPU-costly on a low-end POS device if the queue grows toward the 4MB cap during a sustained outage.
- **Zone-wide outage / recovery scenario (many terminals, mostly Error-level logs, sustained connectivity loss):** during the outage the sessionStorage backlog grows safely (bounded to 4MB, drop-oldest) — no issue there. The problem is on recovery: `ReplayPersistedAsync` (`WasmForwardingSink.cs:440`) is only invoked once, from the sink's constructor — i.e. only at WASM app boot (`WasmForwardingSink.cs:70`). It is **not** wired to `HeartBeatService.OnConnectivityChanged` (`HeartBeatService.cs:26,111,132`), which already fires on reconnect and would be the natural trigger — that event is unused by the logging pipeline entirely. So nothing auto-retries the backlog when internet actually returns mid-shift; it sits dormant until that terminal happens to reload. Worse, when a reload does eventually trigger replay, `ReplayPersistedAsync` flattens **every** eligible pending batch into a **single POST** with no re-chunking to `BatchSize` or to the relay's `MaxBatchBytes` (256KB) cap — a backlog accumulated over a real outage will very plausibly exceed 256KB, get `413`'d by `IngestLogs.cs`, and be re-queued as the same oversized single batch (`PersistWithBackoffAsync` wraps the whole failed list as one new `PendingBatch`) — repeating on every subsequent reload until enough *new* activity pushes total queue size over 4MB and drop-oldest evicts it. Net effect: not a relay/Graylog flood (one request per terminal per retry, nowhere near the 60 req/min cap) — instead, the outage's own diagnostic data is the data most likely to silently never reach Graylog.

## Current working theory

GSFC-839 (dev-only) is a materially more mature design than the old `ProcessLogger` path — batched, size-capped, rate-limited, PII-redacted, non-blocking for business flows, with a working (if not yet live-reachable) kill switch. The main residual operational gap before this ships to `main`/PRO is the lack of a fleet-wide, no-reload kill switch for an active connectivity/volume incident — structurally cheap to add via the existing `SignalRService` or `HeartBeatService` channel, but not built.

## Ruled out

- "Logs are stored in LocalStorage" (original premise) — ruled out. It's `sessionStorage` by deliberate design (`BrowserSessionStorage.cs` comment); undelivered logs do not persist across a real browser/tab close.
- Graylog forwarding via the old `main`-branch `ProcessLogger`/`HttpLoggerProvider` path — ruled out; that path only ever wrote to CosmosDB `BusinessLog`. The Graylog-bound pipeline is exclusively the separate, `dev`-only GSFC-839 work.
- A JavaScript-reachable live toggle for `RemoteEnabled` — ruled out as *existing today*; only `[JSInvokable]` hooks found are JS→C# for error reporting, none write to `WasmLoggingOptions`.

## Open questions / next steps

- Confirm with `gasparc@smartfran.com` whether the external plan doc (`Migracion-Estandarizacion-Logging-Graylog.md` §5.5) specifies a live/no-reload kill-switch requirement, or whether that's an open gap to raise.
- Ask whether `DedupEnabled` should default `true` before production rollout.
- Report the `FlushBeforeUnloadAsync` unused-`CancellationTokenSource` bug upstream.
- Decide whether a live kill switch (via `SignalRService` push, preferred over `HeartBeatService` poll for latency) is required before GSFC-839 promotes from `dev` to `main`/PRO — not yet built as of this review.
- Report to gasparc: `ReplayPersistedAsync` should (a) hook `HeartBeatService.OnConnectivityChanged` to retry on actual reconnect instead of only on next page load, and (b) chunk its outgoing payload to `BatchSize`/`MaxBatchBytes` instead of sending the full backlog as one POST, to avoid the 413-retry-loop / silent-data-loss failure mode described above.
- No Jira ticket opened yet — this stays an investigation until the user decides to formalize it.

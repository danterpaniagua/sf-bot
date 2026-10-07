# SmartFran Cloud — Graylog Log Fields Reference

**Last updated:** 2026-09-23 (GITIN-2098 — `TraceId`/`SpanId`/`ParentId` promoted to bare top-level fields. Confirmed in application source (`Provider.Logger.Core/W3CAndAmbientTraceEnricher.cs`, registered in `SerilogBootstrap.cs` alongside `Service`/`Environment`/`Version`) that these W3C distributed-tracing ids are stamped from `Activity.Current` onto **every log line**, for every service on the shared bootstrap — same universal reach as `TraceKey`, not confined to one specific log line. Never targeted by any prior promotion ticket (GITIN-1883/1892/1940 promoted `TraceKey` and other fields, but not this triplet) and never listed in `devs-log-structure.md` as its own schema key (only as `TraceKey`'s W3C fallback source — see that doc's own correction below). Same two-branch pattern as GITIN-1883/1892: Event Hub apps via `resultDescription`-nested `Properties`, Sales/PosWasmRelay via top-level `Properties`. Deployed and confirmed live same day: Sales-PRO (138 hits/5min, 10/10 sampled with `TraceId`+`SpanId`, `ParentId` on 6/10) and Business-PRO (106 hits/5min, 10/10 with all 3). Full detail in `cloud/events/20260923_gitin2098-traceid-not-promoted-graylog/`)

**2026-09-15 (GITIN-2050 — `FunctionAppLogs` field promotion — first time this category has had any field promotion at all; previously every Function App message landed with the generic `message` fallback `"Microsoft.Web/sites/functions/log"`, unsearchable. Covers the 4 Function Apps onboarded to Graylog the same day: `SFC-CodeGenerator-PRO`, `SFC-ScheduledJobs-PRO`, `SFC-PosWasmRelay-PRO`, `SFC-TicketProcess-PRO`, each its own dedicated stream/index set. Full detail in `cloud/events/20260915_functionapp-onboarding/` (migrated into this repo 2026-09-15) — see new section below)

**2026-09-14 (GITIN-2034 — fixed a real regression-shaped gap in GITIN-1940's `AppServiceHTTPLogs` branch: it only handled `properties` arriving pre-stringified by Azure, silently promoting nothing for the flat/unwrapped ingestion shape where this pipeline's own initial parse leaves `properties` as a live Hash instead. Confirmed via a real Sales-PRO message with all 5 fields missing. Fixed and reverified live. Separately, the `Service:"Sales"` direct-GELF branch's `ElapsedMilliseconds` specifically remains unexplained-missing on some live messages even though `StatusCode`/`Path`/`Method` from the same source work — not the same bug, not resolved by this ticket, still open. See updated section below)

**2026-08-26 (GITIN-1940 — `StatusCode`/`Path`/`Method`/`ElapsedMilliseconds`/`ClientIP` promoted from the built-in ASP.NET Core "Request finished" hosting-diagnostics log line and from Azure's own `AppServiceHTTPLogs` category. Motivated by Sales `WsFeAr/CaeRequest` 408s having no structured field to query on. Deployed and confirmed live at the time — see GITIN-2034 correction above for a gap found later)

**2026-08-24 (GITIN-1924 — `SFC-PosWasmRelay-PRO`/`-DEV` added as a confirmed live source, previously undocumented/marked out of scope. Not a new promotion ticket — Logstash's existing GITIN-1883/1892 Sales-branch logic already promotes 7 fields for this source with zero pipeline changes, since the relay's raw shape happens to present `Properties` as a top-level Hash just like Sales does. `TraceKey`/`SourceContext` are the one confirmed gap — nested one level deeper than this pipeline's promotion logic reaches, see new section below)

**2026-08-19 (GITIN-1892):** 13 more fields promoted: `Version`, `UserId`, `ProcessType`, `Component`, `RequestId`, `SourceContext`, `Category`, `ErrorCode`, `Operation`, `Recovered`, `Handled`, `AuditAction`, `AuditOutcome`. 5 confirmed active on real traffic (`Version`/`ProcessType`/`Component`/`RequestId`/`SourceContext`), `UserId` confirmed correctly inactive by design (always empty in practice, guard skips it), 7 deployed but not yet observed on real traffic (`Category` + the 6 helper-conditional fields)

Tracks the application-level fields (from Serilog's CLEF `Properties` object) that are expected to be searchable as flat, top-level Graylog fields — across the `AppServiceConsoleLogs` Event Hub ingestion path and Sales' separate direct-GELF path. Update whenever a ticket confirms a new field's location or promotes one to top-level.

**See `docs/devs-log-structure.md`** for the full canonical log schema as designed by the dev team (all 6 logging helpers, `Properties` composition layers, PII redaction, exception formatting, anti-patterns) — that document is the source of truth for what the app *should* emit. This document is narrower: it tracks specifically what's confirmed to actually reach Graylog as a flat, searchable field on the SRE/pipeline side, including gaps between the two where they're been found.

## Scope

- **Event Hub path** (`cloud-graylog/docs/azure-eventhub-to-graylog.conf`, via Logstash): `Business`, `Admin`, `Platform`, `Person`, `Catalog`, `Orders`. Each app's `AppServiceConsoleLogs` record carries a Serilog CLEF payload (`Timestamp`/`Level`/`MessageTemplate`/`Properties`) as a JSON **string** inside `resultDescription` — one layer of nesting deeper than Sales.
- **Sales**: separate direct Serilog→Event-Hub CLEF sink (GITIN-1811/1835), bypassing Diagnostic Settings' `records` envelope entirely. Its CLEF payload arrives as the message's own top-level body, so GELF auto-flattens any nested `Properties` object into `Properties_<Key>` fields automatically — no pipeline rule needed for that flattening itself (confirmed via `_exists_:Properties` = 0 hits everywhere, GITIN-1835).
- **Pos** (the `SmartFran-Cloud-Pos-PRO`/`-DEV` Windows App Service itself): still out of scope. `AppServiceConsoleLogs` is structurally unsupported for .NET apps on Windows App Service (GITIN-1811, Microsoft-confirmed) — confirmed 0 messages in this category for both Sales and Pos (both Windows-hosted) before Sales' GITIN-1811 workaround. Pos has not adopted the same direct-GELF workaround.
- **`SFC-PosWasmRelay-PRO`/`-DEV`** (added 2026-08-24, GITIN-1924): a separate Linux Function App, not the Pos App Service above — receives the POS Blazor WASM client's own operational/HTTP-call logs (batched client-side, `WasmForwardingSink`) and re-emits them via `IngestLogs.cs`'s own Serilog pipeline → `FunctionAppLogs` (not `AppServiceConsoleLogs`) → same shared Event Hub → Graylog. See "SFC-PosWasmRelay traffic" section below — a genuinely different raw shape from both the Event Hub apps and Sales, confirmed to reuse the Sales-branch promotion logic incidentally, not by any pipeline change made for it.
- **`FunctionAppLogs` category, all 4 Function Apps** (`SFC-CodeGenerator-PRO`, `SFC-ScheduledJobs-PRO`, `SFC-PosWasmRelay-PRO`, `SFC-TicketProcess-PRO`, added 2026-09-15): a structurally different raw shape from every category above — `properties` arrives as a Python dict-repr **string** (single-quoted keys/values), not JSON, so none of the `JSON.parse` guards used elsewhere in the pipeline ever match it. Dedicated Ruby parser added 2026-09-15 (see new section below) — first field promotion this category has ever had.

## Tracked fields

All fields below are **bare, identically-named top-level fields across every service** — Event Hub apps and Sales alike, no `Properties_` prefix anywhere (unified 2026-08-18, GITIN-1883, at explicit request). GITIN-1892 (2026-08-19) extended the same unified-naming pattern to 13 more fields.

### Always-present when scoped (GITIN-1883 + part of GITIN-1892)

| Field | Event Hub apps (Business/Admin/Platform/Person/Catalog/Orders) | Sales (direct GELF) | CLEF source | Ticket |
|---|---|---|---|---|
| `TraceKey` | Top-level `TraceKey` | Top-level `TraceKey` | `Properties.TraceKey` | GITIN-1883 |
| `AppLevel` | Top-level `AppLevel` | Top-level `AppLevel` | `Level` — nested inside `resultDescription` for Event Hub apps, top-level for Sales | GITIN-1835 |
| `TenantId` | Top-level `TenantId` | Top-level `TenantId` | `Properties.TenantId` — opaque 12-char alphanumeric id, matches `Organization.tenantId` in `docs/infrastructure.md` (e.g. `d3186bc6d7b2`, confirmed same literal value in a real GITIN-1883 sample) | GITIN-1883 |
| `Service` | Top-level `Service` | Top-level `Service` | `Properties.Service` | GITIN-1883 |
| `Environment` | Top-level `Environment` | Top-level `Environment` | `Properties.Environment` | GITIN-1883 |
| `Version` | Top-level `Version` | Top-level `Version` | `Properties.Version` — confirmed live 2026-08-19 (10,686 hits, 9 services PRO/DEV incl. Sales, 30-min window) | GITIN-1892 |
| `UserId` | Top-level `UserId`, when non-empty | Top-level `UserId`, when non-empty | `Properties.UserId` — **legitimately always empty in every real sample seen so far** (Auth0 `sub` claim absent on every observed request); guard correctly skips promoting it, 0 live hits is the expected/correct state, not a bug | GITIN-1892 |
| `ProcessType` | Top-level `ProcessType` | Top-level `ProcessType` | `Properties.ProcessType` — confirmed live 2026-08-19 (104,527 hits) | GITIN-1892 |
| `Component` | Top-level `Component` | Top-level `Component` | `Properties.Component` — confirmed live 2026-08-19 (104,875 hits). **Value discrepancy, unresolved:** real observed values are `Api`/`Web`, not the business-domain name (`Sales`, `Catalog`, ...) that current source code (`dev` and `main`, confirmed 2026-08-19) actually passes via `UseSmartFranLogEnrichment(component: "<Domain>")`. Root cause not confirmed — see `devs-log-structure.md` §3.2 note and `cloud/events/20260819_promote-remaining-clef-fields/` H2 | GITIN-1892 |
| `RequestId` | Top-level `RequestId` | Top-level `RequestId` | Automatic ASP.NET Core MEL field (`HttpContext.TraceIdentifier`), not `EnrichmentMiddleware` — confirmed live 2026-08-19 (109,213 hits) | GITIN-1892 |
| `SourceContext` | Top-level `SourceContext`, when present | Top-level `SourceContext`, when present | Automatic MEL field (`ILogger<T>` name) — confirmed live 2026-08-19 (103,101 hits), but **inconsistent even within the same service**: present on repository/controller-class logs, absent on `RequestHandlingMiddleware`-originated logs. Genuinely varies by call site, not a bug | GITIN-1892 |
| `TraceId` | Top-level `TraceId` | Top-level `TraceId` | `Properties.TraceId` — W3C distributed-tracing id, stamped by `W3CAndAmbientTraceEnricher` from `Activity.Current` on every log line, distinct from the app's own `TraceKey`. Confirmed live 2026-09-23 (Sales 138 hits/5min, Business 106 hits/5min) | GITIN-2098 |
| `SpanId` | Top-level `SpanId` | Top-level `SpanId` | `Properties.SpanId` — same enricher as `TraceId`, always present alongside it in the samples checked | GITIN-2098 |
| `ParentId` | Top-level `ParentId`, when present | Top-level `ParentId`, when present | `Properties.ParentId` — same enricher; **not always present alongside `TraceId`/`SpanId`** (6/10 on the Sales sample, same "not always present" behavior already documented for `FunctionAppLogs`' copy of this field) | GITIN-2098 |

`TenantId`/`UserId` are legitimately empty on system/background messages with no active tenant/user context — not a bug, don't treat an empty value as a pipeline failure.

### Conditional on a specific `SmartFranLogExtensions` helper (GITIN-1892)

Only appear when the log was raised through one of `LogBusinessEvent`/`LogSystemEvent`/`LogDomainError`/`LogTransientFailure`/`LogUnrecoverableFailure`/`LogSecurityAudit` — absent on plain `ILogger` or middleware-originated logs, confirmed on every sample checked. **Not yet observed on real live traffic** as of 2026-08-19 (0 hits, both a 7-day pre-deploy window and a 30-min post-deploy window) — none of these 6 helpers fired in the sampled windows. Logic validated in isolation (5 test scenarios), deployment confirmed structurally sound; live confirmation is a standing follow-up whenever one of these helpers actually fires.

| Field | CLEF source key (confirmed against `SmartFranLogExtensions.cs`, not the same as the promoted name) | Helper | Ticket |
|---|---|---|---|
| `Category` | `Properties.Category` — matches promoted name exactly | All 6 helpers | GITIN-1892 |
| `ErrorCode` | `Properties._error_code` — **note the `_` prefix**, does not match promoted name | `LogDomainError` | GITIN-1892 |
| `Operation` | `Properties.Operation` — matches promoted name exactly (arrives via message-template placeholder, not the helper's scope dict) | `LogTransientFailure`, `LogUnrecoverableFailure` | GITIN-1892 |
| `Recovered` | `Properties._recovered` (boolean) — **note the `_` prefix** | `LogTransientFailure` | GITIN-1892 |
| `Handled` | `Properties._handled` (boolean) — **note the `_` prefix** | `LogUnrecoverableFailure` | GITIN-1892 |
| `AuditAction` | `Properties._audit_action` — **note the `_` prefix**; a separate `Properties.Action` (bare, from message-template placeholder) also exists but is not promoted | `LogSecurityAudit` | GITIN-1892 |
| `AuditOutcome` | `Properties._audit_outcome` — **note the `_` prefix**; a separate `Properties.Outcome` (bare) also exists but is not promoted | `LogSecurityAudit` | GITIN-1892 |

**Why the `_` prefix matters here:** `devs-log-structure.md` originally documented all 6 of these as plain PascalCase (`ErrorCode`, `Recovered`, etc.) — that was wrong for 5 of them, discovered only after a first deploy of this exact pipeline promoted the wrong source key and silently produced zero data. Corrected in both the doc and the pipeline the same day (2026-08-19) — see `devs-log-structure.md` §3.3/§3.6 and `cloud/events/20260819_promote-remaining-clef-fields/` H9 for the full incident.

### Per-service confirmation (2026-08-19)

One real message per service, last 30 minutes, no category filter — the 6 Event Hub apps plus Sales:

```
┌───────────┬──────────┬──────────┬───────────┬───────────┬───────────────┬─────────┐
│  Service  │ TenantId │ Version  │ ProcessTy │ Component │ SourceContext │ Category│
├───────────┼──────────┼──────────┼───────────┼───────────┼───────────────┼─────────┤
│ Sales     │ ✅       │ ✅       │ ✅ Api    │ ✅ Api    │ ✅            │ —       │
│ Business  │ ✅       │ ✅       │ ✅ Api    │ ✅ Api    │ ✅            │ —       │
│ Admin     │ —        │ ✅       │ ✅ Api    │ ✅ Web    │ ✅            │ —       │
│ Platform  │ —        │ ✅       │ ✅ Api    │ ✅ Api    │ —             │ —       │
│ Person    │ ✅       │ ✅       │ ✅ Api    │ ✅ Api    │ —             │ —       │
│ Catalog   │ ✅       │ ✅       │ ✅ Api    │ ✅ Api    │ ✅            │ —       │
│ Orders    │ ✅       │ ✅       │ ✅ Api    │ ✅ Api    │ —             │ —       │
└───────────┴──────────┴──────────┴───────────┴───────────┴───────────────┴─────────┘
```

`AppLevel`/`TraceKey`/`Service`/`Environment`/`RequestId` present in all 7, omitted from the table for brevity. `TenantId` absent on Admin/Platform in this sample — system/background messages, consistent with the known empty-value behavior, not a gap. `SourceContext` present on 4/7 — genuinely varies by call site (repository/controller class vs. generic middleware), not a bug. `Component` confirms the value discrepancy above with fleet-wide data: 6/7 show `Api`, none show a business-domain name. `Category` and the 6 conditional fields: 0/7, consistent with "not yet observed on real live traffic" above. Full detail: `cloud/events/20260819_promote-remaining-clef-fields/` C11.

### Conditional on the ASP.NET Core "Request finished" hosting-diagnostics line, or Azure's own AppServiceHTTPLogs (GITIN-1940)

Not a `SmartFranLogExtensions` helper — this is the built-in ASP.NET Core hosting-diagnostics request logger (`SourceContext: Microsoft.AspNetCore.Hosting.Diagnostics`), present on every HTTP request regardless of app-level enrichment. Motivated by Sales `WsFeAr/CaeRequest` returning `408`s — before this, endpoint/status-code queries had no structured field to filter on, only full-text search over `message`. Deployed 2026-08-26 and confirmed live at the time via a handful of samples — but see the GITIN-2034 correction below, found 2026-09-14, for a real gap that slipped past that initial verification.

Unified into the same 4 field names from a second source shape (added 2026-08-26): Azure's own `AppServiceHTTPLogs` diagnostic category (Windows Event Hub apps' infra-level HTTP access log, distinct from the app-level Request-finished line above), which carries the same request/response metadata under Azure's own key names. `ScStatus`/`TimeTaken` are cast (String→Integer, Integer→Float respectively) to match the types already used by the other source.

| Field | Source key(s) | Type | Ticket |
|---|---|---|---|
| `StatusCode` | `Properties.StatusCode` (Request-finished, Integer) or `properties.ScStatus` (AppServiceHTTPLogs, String **or** Integer — see GITIN-2034 below) | Integer | GITIN-1940 |
| `Path` | `Properties.Path` (Request-finished — `RequestPath` duplicates this, not separately promoted) or `properties.CsUriStem` (AppServiceHTTPLogs) | String | GITIN-1940 |
| `Method` | `Properties.Method` (Request-finished) or `properties.CsMethod` (AppServiceHTTPLogs) | String | GITIN-1940 |
| `ElapsedMilliseconds` | `Properties.ElapsedMilliseconds` (Request-finished, Float) or `properties.TimeTaken` (AppServiceHTTPLogs, Integer cast to Float) | Float | GITIN-1940 |
| `ClientIP` | `properties.CIp` (AppServiceHTTPLogs only — the Request-finished line has no equivalent property) | String | GITIN-1940 |

AppServiceHTTPLogs scope **confirmed for Sales** (GITIN-2034, 2026-09-14) — still unconfirmed for Pos specifically. Pos's known `AppServiceConsoleLogs` gap (GITIN-1811, unsupported on Windows/.NET) is a different diagnostic category; whether Pos emits `AppServiceHTTPLogs` at all still hasn't been checked.

**Correction (2026-09-14, GITIN-2034):** the `AppServiceHTTPLogs` branch's original guard (`props_json.is_a?(String)`) only handled one of two raw ingestion shapes Azure actually sends for this category — a `"records"`-array-wrapped shape (where Azure pre-stringifies `properties`) and a flat/unwrapped shape (where this pipeline's own initial `json` filter leaves `properties` as a live Hash instead, since no `records` key exists to trigger the wrapping logic). For the flat shape, the guard silently failed and **none** of the 5 fields above promoted — not a partial gap, the whole branch no-op'd. Confirmed via a real Sales-PRO message (`_id: b4966b92-b038-11f1-be92-7c1e52beabec`, `/api/v1/Status/Health`) with all 5 fields absent. Also fixed in the same change: `ScStatus` arrives as a bare Integer in the flat shape (not the numeric String the original cast expected). Fixed, deployed, and reconfirmed live both on Sales-PRO-specific samples and fleet-wide 24h counts (`StatusCode` 1.04M, `Path`/`Method` ~1.1M each, `ElapsedMilliseconds` 921K, `ClientIP` 848K hits). Full detail: `cloud/events/20260914_gitin2034-timetaken-elapsedms-promotion/`.

**Separate, still-open issue found in the same investigation (not resolved by GITIN-2034):** on the `Service:"Sales"` **direct-GELF** branch (not `AppServiceHTTPLogs` — the plain "Request finished" line via Sales' own Serilog→Event-Hub sink), real live messages have been observed with `StatusCode`/`Path`/`Method` correctly promoted but `ElapsedMilliseconds` specifically absent, despite reading from the exact same `Properties` hash with the same guard pattern. Traced through the pipeline — the Ruby logic itself looks correct and unchanged from its original working state, so the cause isn't understood yet. Not the same bug as the `AppServiceHTTPLogs` issue above (different branch, different failure shape — partial not total). Flagged as an open follow-up, not yet filed as its own ticket.

### `SFC-PosWasmRelay-PRO`/`-DEV` traffic (GITIN-1924, 2026-08-24)

One real PROD message audited in full (`_id: c23310a3-9fcb-11f1-8f28-7c1e52beabec`, 2026-08-24T14:54:50Z, an HTTP-call log the POS client's own `HttpLoggingHandler` forwarded through the relay).

**Confirmed promoted (bare top-level), no pipeline change needed:**

| Field | Value in sample | Note |
|---|---|---|
| `Service` | `smartfran-pos-wasm` | Relay's own override (`batch.SourceKey`), **not** the client's own `Service` (`SmartFran.Cloud.Pos.Wasm` — buried in `EntryProperties`, see below) |
| `Environment` | `Production` | Relay process's own `ASPNETCORE_ENVIRONMENT` |
| `TenantId` | `org_g4qPlLbxcJZx5e7U` | **Format discrepancy** — an Auth0 `org_id`-shaped string, not the 12-char opaque hash every other service's `TenantId` uses (e.g. `d3186bc6d7b2`). Not yet raised with dev — flagged here, not confirmed intentional. |
| `ProcessType` | `PosWasm` | New value, not in the existing `Api`/`Web`/`Function` set |
| `Component` | `Pos` | |
| `Version` | `1.0.0.0` | |
| `AppLevel`/`Level` | `Information` | Standard `AppLevel` block, unaffected |
| `TraceId`/`SpanId`/`ParentId` | Expected top-level, **not independently verified on this source** | GITIN-2098's new Ruby block reads `top_props["TraceId"]` etc. directly, unconditional on `top_props.is_a?(Hash)`, same as the 7 fields above — should fire for this traffic incidentally by the same mechanism, but GITIN-2098 only verified live on Sales-PRO and Business-PRO, not PosWasmRelay specifically |

**Confirmed NOT promoted — nested one level deeper than this pipeline's logic reaches:**

| Field | Where it actually lives | Why the guard misses it |
|---|---|---|
| `TraceKey` | `Properties.EntryProperties.TraceKey` | GITIN-1883's Sales-branch guard reads `top_props["TraceKey"]` directly — the relay nests all client-supplied per-entry properties one level deeper, under `EntryProperties`, to avoid colliding with the relay's own canonical fields |
| `SourceContext` | `Properties.EntryProperties.SourceContext` | Same reason |
| `Category` | `Properties.Category`, present but empty (`""`) | Correctly skipped by the empty-string guard — not a nesting issue, just genuinely empty on this message shape (an HTTP-call log, not one of the 6 canonical helpers) |

**Mechanism — why this worked without any pipeline change:** the relay's raw event shape presents `Properties` as a live top-level Hash directly on the Logstash event (same as Sales' direct-GELF shape), **not** nested inside `resultDescription` (the Event Hub apps' shape) — despite the relay going through the same Diagnostic-Settings-via-shared-Event-Hub path as the Event Hub apps, not a direct-GELF sink like Sales. Root cause not investigated (would require comparing `FunctionAppLogs`' raw Azure record schema against `AppServiceConsoleLogs`' — out of scope for this ticket). Practical effect: GITIN-1883/1892's Sales-branch Ruby block (`azure-eventhub-to-graylog.conf`, unconditional on `top_props.is_a?(Hash)`, no per-app check) fires for this traffic incidentally and promotes the 7 fields above for free.

**Fields this doc has never tracked, present only nested (not promoted, not in scope for any prior ticket):** `CorrelationId`, `SessionId` (both `Properties.*`, relay-set via `IngestLogs.cs`'s own `LogContext.PushProperty`), `AzureFunctions_InvocationId`/`AzureFunctions_FunctionName` (`Properties.*`, Azure Functions runtime-injected). W3C `TraceId`/`SpanId`/`ParentId` (`Properties.*`, lowercase-hex form) were in this list until GITIN-2098 (2026-09-23) — now promoted, see the confirmed-promoted table above (verification pending specifically on this source, see note there).

**If `TraceKey`/`SourceContext` promotion is needed for this source**, it requires an actual Logstash filter change (a new `EntryProperties`-aware fallback in the Sales-branch Ruby block, or a Graylog-side Pipeline Rule parsing the already-present stringified `Properties`/`event_original` field) — not attempted in this ticket, flagged as an open follow-up.

**Mechanism note (why unification required more than adding fields):** Sales previously had these same fields accessible, but under `Properties_`-prefixed names (`Properties_TraceKey`, etc.) — an artifact of GELF's own automatic flattening of any nested JSON object it receives, not something Logstash controlled. Achieving true bare-name unification required the Logstash pipeline to also read Sales' top-level `Properties` object directly, then **stringify** it afterward so GELF stops auto-flattening it into `Properties_*` duplicates (same technique already used for Azure's own lowercase `properties` field). That stringification silently broke 2 Graylog Pipeline Rules from GITIN-1835 that keyed on the literal `Properties_Service`/`Properties_Environment` field names (Sales' `source` formatting and its Stage 1 stream-routing rule) — both updated in the same change to read the new bare `Service`/`Environment` fields instead. Confirmed on live traffic post-deploy: no regression in Sales' `source`/`name`/stream routing.

### What `smartfran-pos-wasm` forwards — errors only (GITIN-2134, 2026-09-30)

An aggregation over 7 days (`Service:smartfran-pos-wasm AND StatusCode:*`, grouped by `StatusCode`) returned only 404 (4,123), 500 (1,012), 408 (432), 400 (194) and 403 (70) — **no 2xx at all**. This source therefore cannot show which calls/tenants/users succeed or give a "worked before" baseline; use the receiving service's own logs for that. `UserId` is empty on this source and the client's `PosCode`/`ShiftCode` are nested in `EntryProperties` (not searchable). A single client HTTP log also arrives a second time as a raw `FunctionAppLogs` line from the relay (no promoted fields), so message counts can be ≈ doubled.

**Cross-service lookups work:** `SmartFran.Cloud.Platform.API`, `Client.Web`, `Business.API` and the Functions log `/api/Tenant/…` calls too (24 h sample: Platform.API 200 ×504, Client.Web 200 ×6,156, Business.API 200 ×8). The client's `TraceKey` is propagated: `TraceKey:"<key>"` across all services returns the related messages (sample: 1 Platform.API line, a `RequestHandlingMiddleware` `LogOriginalRequest` warning with no status).

**Graylog REST usage that worked on the SmartCloud instance** (`https://sfcloud-monitoreo.smartfran.com/graylog/api/`): `POST /search/aggregate` (JSON body with `query`, `timerange`, `group_by:[{field,limit}]`, `metrics:[{function:"count"}]`, header `X-Requested-By`), and `GET /search/universal/relative` for raw messages; auth `curl -u "$GRAYLOG_API_KEY:token"`. A token from the other Graylog instance (`sf-monitoreo.smartfran.com`, SmartPedidos/SmartLoyalty stack) returns 401 here — the two instances do not share tokens.

### `FunctionAppLogs` — 4 Function Apps (GITIN-2050, 2026-09-15)

First field promotion this category has ever had. Root cause of the prior gap: `properties` arrives as a **Python dict-repr string** (single-quoted keys/values, e.g. `{'functionName': 'RegisterBusinessLog', ...}`), not JSON — every `JSON.parse`-based guard elsewhere in the pipeline silently rescues and skips it, so every Function App message fell back to the generic `message` value `"Microsoft.Web/sites/functions/log"` (the `operationName` fallback), unsearchable. Fixed with a dedicated hand-rolled Python-literal parser (`azure-eventhub-to-graylog.conf`, the `if [category] == "FunctionAppLogs"` block) — verified against real captured messages from all 4 apps via a standalone Ruby test script before touching the live pipeline, not guessed from the shape alone.

**Two distinct `properties.message` shapes**, both handled:

| Shape | `properties.category` example | `message` content |
|---|---|---|
| `Host.Function.Console` | Function runtime's own structured log | `properties.message` is itself a **nested** Python dict-repr string — `Timestamp`/`Level`/`MessageTemplate`/`Properties`, the latter holding `SourceContext`/`Service`/`Environment`/`Version`/`TraceId`/`SpanId`/`ParentId`, and (PosWasmRelay only) a further-nested `EntryProperties` hash with the original POS client request's own `Method`/`Path`/`StatusCode`/`ElapsedMs`/`TraceKey`/etc. |
| `Function.<name>` / `Function.<name>.User` | Execution lifecycle / app-level log line | `properties.message` is a **plain string** (e.g. `"Executed Functions.X (Succeeded, Id=.., Duration=3ms)"`) — `functionInvocationId`/`functionName`/`eventId`/`eventName` arrive as flat sibling keys of `properties` itself, not nested |

**Promoted fields:**

| Field | Source | Note | 
|---|---|---|
| `FunctionName` | `properties.functionName`, or `Properties.AzureFunctions_FunctionName` (Host.Function.Console shape, when the flat key is absent) | Which function fired — the field that makes it possible to separate, e.g., a ScheduledJobs HTTP endpoint from its timer-triggered siblings |
| `FunctionInvocationId` | `properties.functionInvocationId`, or `Properties.AzureFunctions_InvocationId` fallback | |
| `FunctionEventName` | `properties.eventName` | Literal string `"0"` on `Function.<name>.User` lines (real app log statements, not a lifecycle marker) — a meaningless placeholder, not promoted when equal to `"0"` |
| `message` | `nested.MessageTemplate` (Host.Function.Console) or the plain string directly (`Function.<name>`) | |
| `AppLevel` | `nested.Level` (Host.Function.Console) or `properties.level` (`Function.<name>`) | Same universal field as every other category, just a different source path here |
| `Service` | `inner_props.Service` | The Function App's own identity (e.g. `smartfran-pos-wasm` for the relay) |
| `Environment`, `Version`, `SourceContext`, `TraceId`, `SpanId`, `ParentId` | `inner_props.*` | `ParentId` not always present alongside `TraceId`/`SpanId` — confirmed absent on PosWasmRelay samples, present on CodeGenerator/ScheduledJobs |
| `PosCode`, `ShiftCode` | `inner_props.*` or `ep.*` (whichever level has it) | |
| `Method`, `Path`, `StatusCode`, `ElapsedMilliseconds`, `TraceKey`, `SourceContext`, `ClientService` | `ep.*` (`EntryProperties`, **PosWasmRelay only** — the original POS client's own request data, one level deeper than the relay's own fields) | Same field names as `AppServiceHTTPLogs` (GITIN-1940) by design — a PosWasmRelay query can reuse the exact same query shape as the 8 App Services |

**`ep`/`EntryProperties` quoting quirk (verified, not assumed):** every string value inside `EntryProperties` — `Method`, `Path`, `TraceKey`, `SourceContext`, `Service`, `Environment`, `Version`, `PosCode`, `ShiftCode`, but **not** `StatusCode`/`ElapsedMs` — carries a literal wrapping `"` character as part of the value itself (e.g. `Path` arrives as `"\"/api/v1/...\""`, not the clean path alone). Same class of quirk already documented for Sales/PosWasmRelay's `TraceKey`/`SourceContext` (GITIN-1924, see below) but confirmed here to hit every other `EntryProperties` string field too — stripped uniformly by the new parser.

**`Service`/`ClientService` collision, resolved by design:** `Properties.Service` (the relay Function App's own identity) and `Properties.EntryProperties.Service` (the original POS client's own declared identity) are two different values at two nesting depths — promoting both to the same flat `Service` field would silently let one overwrite the other. Resolved: the outer one stays `Service` (consistent with every other category in this pipeline, where `Service` means "the thing doing the logging"), the inner one promotes to a distinct `ClientService` field.

**Known gap, not fixed in this change:** the `name` field (used for stream routing) is indexed **uppercase** (comes from `resourceId`) — a query using Azure's exact casing for a Function App name returns 0 results silently, no error. Caused a real false negative during this onboarding's own verification. Not specific to `FunctionAppLogs` — same mechanism likely affects every category, just newly hit here.

**Scoped out of this change, flagged as follow-up:** `Duration=Xms`/`Succeeded`/`Failed` on `Function.<name>` completion lines remain free text inside `message`, not extracted to structured fields — real but moderate-effort follow-up.

**Streams/index sets** (one dedicated pair per app, same convention as GITIN-1940's `AppServiceHTTPLogs` split — see `cloud-appservice-perf-report` skill for that pattern): `SFC-CodeGenerator-prod`, `SFC-ScheduledJobs-prod`, `SFC-PosWasmRelay-prod`, `SFC-TicketProcess-prod`. Raw Graylog stream-id hex values not captured in either repo as of this writing — pull via `GET /streams` before scripting against them, same as any other stream referenced by name only.

**Verification status:** end-to-end delivery and field promotion confirmed live for all 4 apps (re-verified 2026-09-15 against real messages on each dedicated stream, `category:"FunctionAppLogs" AND name:"<APP>"` — `name` queried uppercase per the gotcha above). `SFC-TicketProcess-PRO` had no live run during the original onboarding session; confirmed separately afterward (`ProcessTicketsHourly`, `Service: SmartFran.Cloud.Functions.Sales.TicketProcessAsync`). Live config re-pulled from the VM and diffed against this repo's copy at the same time — identical except the two connection-string fields this repo redacts by design; the `FunctionAppLogs` parser block matches exactly. `SFC-CodeGenerator-PRO`'s `Service` field confirms the deployed source is `LiteEditionV2`, resolving the ambiguity between the two CodeGenerator projects noted below. `SFC-ScheduledJobs-PRO`'s `FunctionName` cleanly distinguishes `RegisterBusinessLog` (real HTTP traffic) from its other timer-triggered jobs — closes the estimation gap flagged in `cloud/events/20260915_gitin2042-waf-cost-estimate/investigation.md` (H6), not yet re-run against this ticket's cost model.

## Where they come from (application source)

Confirmed 2026-08-18 against `cloud/repo/SmartFran.Cloud` (`origin/dev`, pulled fresh this session) and cross-checked against `docs/devs-log-structure.md` (dev-team-authored, cites the same source files independently). All 7 web-facing services (Business, Catalog, Platform, Orders, Security, Person, Sales) — plus `SmartFran.Cloud.Client.Web`, the actual project behind the `SmartFran-Cloud-Admin-PRO` App Service (see naming note below) — build on the **same shared providers** in `Source/Common/Providers/`.

`Properties` is composed in **layers**, each able to add or overwrite keys from the one before (`devs-log-structure.md` §3, fuller detail there):

1. **Process-level enrichers** (`Provider.Logger.Core/SerilogBootstrap.cs`, `.Enrich.WithProperty(...)`, applied once at logger construction) — set `Service`, `Environment`, `Version` on **every** log line for the process, including ones outside any HTTP request (startup, Kestrel hosting events). `Service` here is whatever string each `Program.cs` passes to `SerilogBootstrap.Configure(cfg, serviceName)` — confirmed for Business: `"SmartFran.Cloud.Business.API"` (the long assembly-style form, read directly from `Program.cs:47`).
2. **`EnrichmentMiddleware`** (`Provider.Logging.AspNetCore/Middleware/EnrichmentMiddleware.cs`), registered per-service via `app.UseSmartFranLogEnrichment(component: "<Name>")` near the start of the HTTP pipeline — overwrites the process-level scope, per request, with `Service`, `Environment`, `Version`, `TraceKey`, `TenantId`, `UserId`, `ProcessType`, `Component`. This is the intended source of `TraceKey`/`TenantId` for HTTP-request-driven logs:
   - `TraceKey` = incoming `TraceKey` HTTP header if the caller sent one, else falls back to the W3C `Activity.TraceId`. Cross-service calls propagate it via each service's `Application`-layer `Proxy.cs` (seen in a `grep`, not read in detail this session).
   - `TenantId` = incoming `X-Tenant-Id` header, else `HttpContext.Items["tenantId"]` (set upstream by each API's own `TenantHandlingMiddleware`, which resolves `org_id` → `tenant_id` via App Configuration's `OrgTenant:{orgId}` section) — **never** from the Auth0 token's claims directly, per the middleware's own doc comment.
   - `Service` here should, per the code's constructor overload (`serviceName: env.ApplicationName`) and per `devs-log-structure.md`'s own §3.2/§6.1/§9 examples, also resolve to the long assembly-style name (e.g. `"SmartFran.Cloud.Sales.API"`). **Confirmed discrepancy:** every real GITIN-1883 production sample instead shows a **short** name — `Business`, `Platform`, `Person`, `Catalog`, `Orders`, and `Client` for the Admin-PRO app (source project `SmartFran.Cloud.Client.Web`). No override of `ApplicationName`/`AssemblyName` was found anywhere in the repo (Program.cs, appsettings, .csproj) to explain this — the mechanism is unconfirmed (possibly an App Service-level setting outside the repo), only the fact that observed behavior doesn't match either the code-as-read or the devs' own documented example. Worth a direct question to the dev team rather than further guessing from source alone.
- **`LogContextPushPropertyMiddleware`** (`Middleware/LogContextPushPropertyMiddleware.cs`) — the equivalent for Service Bus / Event Grid **consumers** (not HTTP requests), used by background/queue processing code. Pushes `TraceKey`, `Service`, `Component`, `ProcessType` (`"Function"`) via `Serilog.Context.LogContext.PushProperty`. `TraceKey` here comes from the message's own `TraceKey` `ApplicationProperty` (set by the publisher via `TenantScopedMessagingProvider`), falling back to the current `Activity.TraceId`, then a fresh GUID if neither exists.
- **`AppLevel` has no application-level source at all** — confirmed via `grep -rn "AppLevel"` across `Source/`, zero matches, and absent from `devs-log-structure.md`'s own schema. It is purely a Logstash/Graylog-side derived field (GITIN-1835): the Serilog CLEF `Level` a log call already carries by virtue of which method was called (`_logger.LogWarning(...)`, `LogError(...)`, etc.) — standard Serilog/`ILogger` behavior, not a custom enrichment.

## Where they live in the Graylog JSON

**Event Hub apps** (Business/Catalog/Platform/Orders/Person/Admin) — nested three layers deep in the raw message:

```
event_original (string)
  → JSON.parse → records[0].resultDescription (string, Serilog CLEF)
      → JSON.parse → .Properties.TraceKey / .Properties.TenantId / .Properties.Service
      → .Level  (→ becomes top-level AppLevel)
```

After the Logstash pipeline (`azure-eventhub-to-graylog.conf`) runs, the actual top-level Graylog message JSON has `TraceKey`, `TenantId`, `Service`, `Environment`, `AppLevel` as flat sibling fields alongside `resultDescription` itself (still present, unmodified, for anyone who needs the full raw CLEF blob) — confirmed via a real Business-PRO sample (GITIN-1883, 2026-08-18):

```json
{
  "resultDescription": "{\"Timestamp\":\"...\",\"Level\":\"Error\",\"MessageTemplate\":\"...\",\"Properties\":{\"Service\":\"Business\",\"Environment\":\"Production\",\"TraceKey\":\"SFCADMWEB.POS:19.2026-08-18T21:22:47.7880000+00:00\",\"TenantId\":\"d3186bc6d7b2\", ...}}",
  "AppLevel": "Error",
  "TraceKey": "SFCADMWEB.POS:19.2026-08-18T21:22:47.7880000+00:00",
  "TenantId": "d3186bc6d7b2",
  "Service": "Business",
  "Environment": "Production"
}
```

**After GITIN-1892** (2026-08-19), the same Event Hub apps additionally carry `Version`, `ProcessType`, `Component`, `RequestId`, `SourceContext` as flat siblings (and `UserId`/`Category`/the 6 conditional fields, when non-empty/present) — confirmed via a real Business-PRO sample:

```json
{
  "resultDescription": "{...same as before, plus Properties.Version/.UserId/.ProcessType/.Component/.RequestId/.SourceContext, all still nested and unsearchable here...}",
  "AppLevel": "Information",
  "TraceKey": "SFCADMWEB.POS:14.2026-08-19T14:20:19.6120000+00:00",
  "TenantId": "d3186bc6d7b2",
  "Service": "Business",
  "Environment": "Production",
  "Version": "1.0.0+c6668229d20569923c2854855bc06bad8185dbfc",
  "ProcessType": "Api",
  "Component": "Api",
  "RequestId": "0HNNTTQ6EU0I1:00000058",
  "SourceContext": "SmartFran.Cloud.Business.Infrastructure.Repositories.Domain.Entities.Movement.POSMovementType"
}
```

`UserId` is absent here — it arrived empty (`""`) in this real message, and the guard correctly skips promoting empty strings.

**Sales** (direct-GELF CLEF sink) — one layer shallower, no `resultDescription`/`records` envelope at all; the CLEF payload **is** the message body. Before GITIN-1883's unification pass, GELF's own automatic flattening handled this with no Logstash involvement, producing `Properties_*`-prefixed fields; now Logstash explicitly reads the top-level `Properties` object, promotes the 4 fields to bare names, then **stringifies** the leftover `Properties` object so GELF stops auto-flattening it:

```
(top-level message body, Serilog CLEF)
  .Level                → top-level AppLevel (Logstash AppLevel block's priority-1 branch, unchanged since GITIN-1835)
  .Properties.TraceKey    → top-level TraceKey     (GITIN-1883, explicit — no longer Properties_TraceKey)
  .Properties.TenantId    → top-level TenantId     (GITIN-1883, explicit — no longer Properties_TenantId)
  .Properties.Service     → top-level Service      (GITIN-1883, explicit — no longer Properties_Service)
  .Properties.Environment → top-level Environment  (GITIN-1883, explicit — no longer Properties_Environment)
  .Properties (leftover)  → stringified to JSON, no longer a live Hash — prevents GELF from re-flattening it
```

Confirmed on real live Sales-PROD traffic post-deploy (GITIN-1883, 2026-08-18): a genuine post-deploy message shows `Service: "Sales"`, `Environment: "Production"`, `TraceKey`, `TenantId: "d3186bc6d7b2"` all bare, and **zero** `Properties_*` fields remaining.

## Full field list (Graylog query reference)

Every field this doc tracks, as a `_exists_:<field>` query would find it — mirrors `devs-log-structure.md` §9, but scoped to what's actually confirmed reaching Graylog (not just what the app emits):

```
_exists_:Service            // always present
_exists_:Environment         // always present
_exists_:Version              // confirmed live 2026-08-19 (GITIN-1892)
_exists_:TraceKey             // always present
_exists_:TenantId             // present except system/background messages
_exists_:UserId                // present only when the Auth0 "sub" claim resolves — not seen in any real sample yet
_exists_:ProcessType          // confirmed live 2026-08-19 (GITIN-1892)
_exists_:Component            // confirmed live 2026-08-19 (GITIN-1892) — value discrepancy, see H2 above
_exists_:AppLevel             // always present (Logstash-derived, GITIN-1835)
_exists_:RequestId            // confirmed live 2026-08-19 (GITIN-1892)
_exists_:SourceContext        // confirmed live 2026-08-19 (GITIN-1892) — varies by call site
_exists_:Category             // confirmed live 2026-09-14 (638 hits/24h) — a helper has now fired; not observed live as of 2026-08-19, corrected here
_exists_:ErrorCode            // still 0 hits as of 2026-09-14 — LogDomainError only
_exists_:Operation            // still 0 hits as of 2026-09-14 — LogTransientFailure/LogUnrecoverableFailure only
_exists_:Recovered            // still 0 hits as of 2026-09-14 — LogTransientFailure only
_exists_:Handled              // still 0 hits as of 2026-09-14 — LogUnrecoverableFailure only
_exists_:AuditAction          // still 0 hits as of 2026-09-14 — LogSecurityAudit only
_exists_:AuditOutcome         // still 0 hits as of 2026-09-14 — LogSecurityAudit only
_exists_:StatusCode           // confirmed live 2026-08-26, both branches (GITIN-1940); AppServiceHTTPLogs branch had a real gap fixed 2026-09-14 (GITIN-2034) — 1.04M hits/24h post-fix
_exists_:Path                 // confirmed live 2026-08-26, both branches (GITIN-1940); AppServiceHTTPLogs branch gap fixed 2026-09-14 (GITIN-2034) — ~1.1M hits/24h post-fix
_exists_:Method                // confirmed live 2026-08-26, both branches (GITIN-1940); AppServiceHTTPLogs branch gap fixed 2026-09-14 (GITIN-2034) — ~1.1M hits/24h post-fix
_exists_:ElapsedMilliseconds   // confirmed live 2026-08-26, both branches (GITIN-1940); AppServiceHTTPLogs branch gap fixed 2026-09-14 (GITIN-2034) — 921K hits/24h post-fix. Separate open issue: sometimes absent on Service:"Sales" direct-GELF specifically, unexplained, see GITIN-1940 section above
_exists_:ClientIP              // confirmed live 2026-08-26, AppServiceHTTPLogs (GITIN-1940); branch gap fixed 2026-09-14 (GITIN-2034) — 848K hits/24h post-fix
_exists_:FunctionName          // FunctionAppLogs only (GITIN-2050, 2026-09-15) — which function/endpoint fired
_exists_:FunctionInvocationId  // FunctionAppLogs only (GITIN-2050)
_exists_:FunctionEventName     // FunctionAppLogs only (GITIN-2050) — excludes the meaningless "0" placeholder value
_exists_:ClientService         // FunctionAppLogs, SFC-PosWasmRelay-PRO only (GITIN-2050) — the POS client's own declared Service, distinct from the relay's own Service
_exists_:TraceId               // confirmed live 2026-09-23 (GITIN-2098) — Sales 138 hits/5min, Business 106 hits/5min
_exists_:SpanId                // confirmed live 2026-09-23 (GITIN-2098) — same enricher as TraceId, always present alongside it in samples checked
_exists_:ParentId              // confirmed live 2026-09-23 (GITIN-2098) — not always present alongside TraceId/SpanId (6/10 on the Sales sample)
```

`Attempt`/`Action`/`Outcome` (the message-template-derived PascalCase companions to `_recovered`/`_audit_action`/`_audit_outcome` — see `devs-log-structure.md` §9) are **not promoted to top-level Graylog fields** — they exist in the app's `Properties`, but no ticket has flattened them. Not currently in scope for any open ticket.

## `name` resolution for Sales (GITIN-1835 open item, field names updated by GITIN-1883)

The Stage 1 Graylog Pipeline Rule that resolves `name`/`resource_group`/`resource_path`/etc. and routes into `PROD-Sales-AppServicePlan` is scoped **only** to `Service: "Sales"` + `Environment: "Production"` (originally `Properties_Service`/`Properties_Environment` under GITIN-1835's naming; migrated to the bare field names as part of GITIN-1883's unification — see rule `GITIN-1835: CLEF Azure resource fields for Sales PRO`, id `6a7f2cb84814bcaed30c8de3`). Confirmed live pre-migration (GITIN-1883, 2026-08-18, 30-min window): 150 messages `Sales`/`Development` and 2 `SmartFran.Cloud.Sales.API`/*(empty)* had the Service field populated but no `name` resolved — this specific gap (other Service/Environment combinations besides Sales+Production) is **not fixed**, still flagged for whoever picks up GITIN-1835's open item #3.

## Related tickets

- GITIN-1811 (closed) — `AppServiceConsoleLogs` unsupported on Windows/.NET; Sales' direct-GELF sink workaround.
- GITIN-1835 (closed) — universal `AppLevel`; Sales CLEF `message`/`full_message`/`source`/resource-fields formatting. 3 of its Graylog Pipeline Rules updated by GITIN-1883 (field names only, same logic) to track the new bare `Service`/`Environment` names.
- GITIN-1883 (closed) — promoted `TraceKey`/`TenantId`/`Service`/`Environment` to top-level fields for the 6 Event Hub apps, then unified Sales onto the same bare names (removing `Properties_` prefix), updating GITIN-1835's dependent Pipeline Rules in the same change.
- GITIN-1892 (closed, 2026-08-19, parent GITIN-1835) — promoted the remaining 13 fields from `devs-log-structure.md` §3.2/§3.3 (`Version`/`UserId`/`ProcessType`/`Component`/`RequestId`/`SourceContext`/`Category`/`ErrorCode`/`Operation`/`Recovered`/`Handled`/`AuditAction`/`AuditOutcome`) for the same 6 Event Hub apps and Sales. Deployed across 3 incremental patches the same day: initial promotion (wrong source keys for 5 helper-conditional fields, caught by validating against `SmartFranLogExtensions.cs` directly), a corrective patch fixing those 5 keys, and a third patch adding `Version` after a §3.2 coverage audit found it had never been promoted. Full detail in `cloud/events/20260819_promote-remaining-clef-fields/`.
- GITIN-1940 (2026-08-25, extended 2026-08-26) — promoted `StatusCode`/`Path`/`Method`/`ElapsedMilliseconds` from the built-in ASP.NET Core "Request finished" hosting-diagnostics log line (not a `SmartFranLogExtensions` helper), for both Event Hub apps and Sales; extended 2026-08-26 to also promote the same 4 fields from Azure's own `AppServiceHTTPLogs` category (`CsMethod`/`CsUriStem`/`ScStatus`/`TimeTaken`, cast to matching types), plus `ClientIP` (`properties.CIp`, AppServiceHTTPLogs only, no equivalent in the other source). Motivated by Sales `WsFeAr/CaeRequest` 408s having no structured field to query on. Full detail in `cloud/events/20260825_sales-caerequest-408-timeout/`.
- GITIN-2034 (2026-09-14) — fixed a real gap in GITIN-1940's `AppServiceHTTPLogs` branch: it only handled one of two raw ingestion shapes Azure sends for this category, silently promoting nothing for the other (flat/unwrapped) shape. Found via a real Sales-PRO message with all 5 fields missing; fixed to accept `properties` as either Hash or String, and to cast `ScStatus` from either Integer or numeric-String. Deployed (one failed attempt first — a stray apostrophe broke the Logstash config string, caught by syntax validation before restart, reverted with no service impact) and reconfirmed live fleet-wide. Also found, separately: 64,866 unrelated Graylog indexing failures on a `time`/`date` field mismatch (out of scope, flagged for its own ticket), and a still-unexplained `ElapsedMilliseconds`-only gap on the `Service:"Sales"` direct-GELF branch (not resolved by this ticket). Full detail in `cloud/events/20260914_gitin2034-timetaken-elapsedms-promotion/`.
- GITIN-2098 (2026-09-23) — promoted `TraceId`/`SpanId`/`ParentId` (W3C distributed-tracing triplet, stamped by a dedicated Serilog enricher on every log line, same universal reach as `TraceKey`) for the 6 Event Hub apps and Sales. Never targeted by any prior ticket despite being present since before GITIN-1883. Deployed with no rollback needed (syntax validated clean on the first attempt). Confirmed live on Sales-PRO and Business-PRO; not independently verified on PosWasmRelay's legacy shape, though the same unconditional-Hash mechanism that already promotes `TraceKey`/`TenantId`/`Service`/`Environment` there should apply. Full detail in `cloud/events/20260923_gitin2098-traceid-not-promoted-graylog/`.

## Related docs

- `docs/devs-log-structure.md` — canonical log schema, dev-authored, source of truth for intended behavior.
- `docs/infrastructure.md` — `Organization.tenantId`, the same value that ends up in `TenantId`.

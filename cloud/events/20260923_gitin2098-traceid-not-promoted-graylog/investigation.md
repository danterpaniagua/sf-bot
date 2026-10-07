# Investigation — TraceId not promoted in Graylog (GITIN-2098)

Jira: https://smartit-ar.atlassian.net/browse/GITIN-2098 — "[OPE] TraceID no promovido en Graylog"

## Trigger

A real Sales-PRO message (ASP.NET Core hosting-diagnostics "Request starting" line, `SourceContext: Microsoft.AspNetCore.Hosting.Diagnostics`, `_id: f1d12131-b74f-11f1-be92-7c1e52beabec`, stream `PROD-Sales-AppServicePlan`) was checked and `TraceId` only exists nested inside the `Properties`/`event_original` JSON-string fields, not as a bare top-level field.

## What `TraceId` is (and isn't)

- Not part of the dev team's designed log schema doc (`cloud/docs/devs-log-structure.md`) — that doc never lists `TraceId` as its own `Properties` key, only as the fallback source value for `TraceKey` ("`TraceKey` = incoming `TraceKey` header, else falls back to W3C `Activity.TraceId`" — `devs-log-structure.md:142,651`). The doc is stale on this point (see source-code finding below) — a doc gap, not a code gap.
- **Confirmed in source (`cloud/repo/SmartFran.Cloud`, `main`, checked out at `e6ad6fa9`, 2026-09-21 — pull to latest requested, not yet re-verified after pull):** `TraceId`/`SpanId`/`ParentId` are **not** an ASP.NET Core framework side-effect confined to one hosting-diagnostics log line. They're a deliberate, universal Serilog enricher:
  - `Source/Common/Providers/SmartFran.Cloud.Provider.Logger.Core/W3CAndAmbientTraceEnricher.cs` — reads `Activity.Current.TraceId`/`.SpanId`/`.ParentSpanId` and stamps them onto the `LogEvent` via `AddOrUpdateProperty`.
  - Registered in `SerilogBootstrap.cs:275` (`.Enrich.With<W3CAndAmbientTraceEnricher>()`), in the same process-level enrichment chain as `Service`/`Environment`/`Version` (`SerilogBootstrap.cs:274-279`) — i.e. applied once at logger construction, for every service that builds on this shared bootstrap (all 7 web APIs + Sales).
  - Practical effect: `Properties.TraceId` is present on **every log line**, not just the "Request starting"/"Request finished" line, for the full duration of any HTTP request or Service Bus/Event Grid message being processed — same universal reach as `TraceKey`/`Service`/`Environment`. This raises the actual promotion value substantially above what the doc-only pass below implied (near-100% of request-scoped log volume, not just one line per request).
  - Not new: this enricher (commit `c1236d50c`, 2026-08-19, same day as GITIN-1892's Graylog-side promotion work) replaced an even older `W3CTraceEnricher.cs` — so `TraceId`/`SpanId`/`ParentId` enrichment predates every Graylog promotion ticket to date. It was simply never picked up on the Graylog side.
- Already promoted in exactly one place: `FunctionAppLogs`' `Host.Function.Console` shape (`inner_props.TraceId`, GITIN-2050, `cloud/docs/graylog-log-fields.md:156`) — a structurally unrelated pipeline branch.

## Where it's nested but NOT promoted (confirmed from `cloud/docs/graylog-log-fields.md` + `docs/sales-direct-gelf-clef-format.rule`, not yet re-verified live this session)

| Source | Log shape | Nesting | Stream (PROD) | Promoted? |
|---|---|---|---|---|
| Sales (direct-GELF CLEF) | **Every log line** during a request (per `W3CAndAmbientTraceEnricher`, not just "Request starting/finished") | `Properties.TraceId` (stringified) | `PROD-Sales-AppServicePlan` | No |
| Business, Admin, Platform, Person, Catalog, Orders (Event Hub apps) | Same universal enrichment — GITIN-1940 promoted `StatusCode`/`Path`/`Method`/`ElapsedMilliseconds` from the "Request finished" line specifically, but `TraceId`/`SpanId`/`ParentId` were never targeted despite riding on every line | `event_original → resultDescription → Properties.TraceId` | `PROD-Business-AppServicePlan`, `PROD-Admin-AppServicePlan`, `PROD-Platform-AppServicePlan`, `PROD-Person-AppServicePlan`, `PROD-Catalog-AppServicePlan`, `PROD-Orders-AppServicePlan` | No |
| SFC-PosWasmRelay (GITIN-1924 incidental Sales-branch shape — the older ingestion path, NOT `FunctionAppLogs`) | Same top-level `Properties` Hash shape as Sales | `Properties.TraceId` | `PROD-Pos-AppServicePlan` | No — explicitly documented gap (`graylog-log-fields.md:129`) |
| Pos App Service itself | N/A — `AppServiceConsoleLogs` unsupported on Windows/.NET (GITIN-1811) | — | — | Not applicable, doesn't emit this shape |
| `FunctionAppLogs`, `Host.Function.Console` (CodeGenerator, ScheduledJobs, PosWasmRelay, TicketProcess) | Already handled (GITIN-2050, 2026-09-15) | `inner_props.TraceId` | `SFC-CodeGenerator-prod`, `SFC-ScheduledJobs-prod`, `SFC-PosWasmRelay-prod`, `SFC-TicketProcess-prod` | Yes — already promoted, no work needed |

Net: candidate gap covers 8 PROD streams (Sales + 6 Event Hub apps' `PROD-{App}-AppServicePlan` + `PROD-Pos-AppServicePlan` for the PosWasmRelay legacy shape).

## Fix (drafted, not yet deployed)

**Live conf pulled and confirmed in sync with the `cloud-graylog/docs/` mirror** (`data/live-azure-eventhub-to-graylog.conf`, 765 lines, byte-identical to the mirror once its 2 real secrets — `event_hub_connections`/`storage_connection` — were redacted to the same `"NO"` placeholder every other committed live-conf pull in this repo uses). **Security note:** the raw pull contained a live Event Hub SAS connection string and a live Storage account key; redacted immediately, values never repeated beyond that one redaction step, file was untracked (never staged/committed) at the time.

Patch: `gitin-2098.patch` — a new Ruby filter block inserted right after the GITIN-1883 block (`azure-eventhub-to-graylog.conf` line 199), promoting `Properties.TraceId`/`.SpanId`/`.ParentId` to bare top-level fields, same two-branch split (Event Hub apps' `resultDescription`-nested `Properties` Hash; Sales/PosWasmRelay's stringified top-level `Properties`, re-parsed the same way GITIN-1892 does) as every prior promotion ticket. Verified before touching the live pipeline:

- No apostrophes anywhere inside the new `code => '...'` single-quoted block (the exact failure mode that broke GITIN-2034's first deploy attempt) — grep-checked.
- Extracted Ruby code passes `ruby -c` (Syntax OK).
- Patch applies cleanly with `patch -p0 --dry-run` against a copy of the confirmed-live file and produces the intended result byte-for-byte.

Deploy sequence (fetch → patch → dry-run → apply → syntax validate → restart → verify) written to `scripts.sh`, same convention as GITIN-2034.

**Deployed and verified live, 2026-09-23:**
- D4 syntax validation: `Configuration OK` (`data/d4_logstash_syntax_validation.txt`).
- D5/D6: `systemctl restart logstash` succeeded; `active (running)`, Event Hub client reconnected, receiver opened cleanly, no errors (`data/d6_logstash_status.txt`).
- V1 (Sales-PRO, `data/graylog_verify_sales_post_deploy.json`): 138 hits/5min with `_exists_:TraceId`. Sampled 10/10 messages have `TraceId`+`SpanId`; `ParentId` present on 6/10 (matches the already-documented "not always present alongside TraceId/SpanId" behavior).
- V2 (Business-PRO, `data/graylog_verify_business_post_deploy.json`): 106 hits/5min. Sampled 10/10 messages have all three fields.
- Cross-check: on the Sales sample, `TraceKey` == `TraceId` (no caller-supplied `TraceKey` header, fell back to `Activity.TraceId` per the documented fallback). On Business, `TraceKey` is a distinct real business key, different from `TraceId` — confirms the two fields are independent, not duplicates, matching the source-code trace above.

No rollback needed — D4 passed clean on the first attempt (unlike GITIN-2034's first attempt).

`SpanId`/`ParentId` included alongside `TraceId` per this session's decision — they're stamped by the same enricher on the same log line, and `FunctionAppLogs` already promotes all three together (GITIN-2050), so this keeps the fields consistent across categories.

## Remaining open items

- DEV-side streams not checked — unconfirmed whether the same gap applies symmetrically to DEV (`cloud-appservice-perf-report` skill notes DEV uses a different, shared-stream layout, not per-app `PROD-{App}-AppServicePlan`). Out of scope for this patch (mirrors GITIN-1883/1892/1940, all PROD+DEV-agnostic at the Ruby-filter level since the filter doesn't branch on `Environment`, but the DEV stream-routing side hasn't been checked).
- SFC-PosWasmRelay's legacy (non-`FunctionAppLogs`) shape not independently verified — the new filter block should fire incidentally for it by the same unconditional-Hash mechanism that already promotes `TraceKey`/`TenantId`/`Service`/`Environment` there, but this wasn't checked on real traffic.

## Documentation updated (2026-09-23)

- `cloud/docs/graylog-log-fields.md`: added `TraceId`/`SpanId`/`ParentId` to the confirmed-promoted fields table, the `_exists_` reference list, the PosWasmRelay section, and `Related tickets`; corrected the stale "never tracked" line that used to list these as unpromoted.
- `cloud/docs/devs-log-structure.md`: added `TraceId`/`SpanId`/`ParentId` to §3.1's process-enrichers table (not §3.2 — they're not set by `EnrichmentMiddleware`, confirmed against `W3CAndAmbientTraceEnricher`'s actual registration point) and to §9's consumer field list; added a top-level correction note alongside the existing GITIN-1892 one.

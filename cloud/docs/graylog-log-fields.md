# SmartFran Cloud — Graylog Log Fields Reference

Which application-level fields (from Serilog's CLEF `Properties`) actually reach SmartCloud Graylog as flat, top-level, searchable fields, per source, and the known gaps. `docs/devs-log-structure.md` is the dev-authored schema of what the app *should* emit; this file is the narrower SRE-side view of what is confirmed to arrive. Keep it in step with what is live.

## Sources and raw shapes

| Source | Path | Raw shape | Handling |
|---|---|---|---|
| Event Hub apps: Business, Admin (`SmartFran.Cloud.Client.Web`), Platform, Person, Catalog, Orders | `AppServiceConsoleLogs` via Diagnostic Settings → Event Hub → Logstash (`cloud-graylog/docs/azure-eventhub-to-graylog.conf`) | CLEF payload is a JSON **string** in `records[0].resultDescription` (one level deeper than Sales) | Logstash parses and promotes fields to bare names |
| Sales | Direct Serilog→Event-Hub CLEF sink (GITIN-1811/1835), no Diagnostic Settings envelope | CLEF is the message body; `Properties` is a live Hash | Logstash promotes bare names, then **stringifies** the leftover `Properties` so GELF stops auto-flattening it into `Properties_*` duplicates |
| Pos (`SmartFran-Cloud-Pos-PRO`/`-DEV`, Windows App Service) | none | `AppServiceConsoleLogs` is unsupported for .NET on Windows (GITIN-1811, Microsoft-confirmed) | Out of scope; Pos has not adopted the direct-GELF workaround |
| `SFC-PosWasmRelay-PRO`/`-DEV` (Linux Function App receiving the POS Blazor WASM client's logs) | `FunctionAppLogs` → shared Event Hub | `Properties` is a live top-level Hash, like Sales | Reuses the Sales-branch promotion logic incidentally (7 fields); `EntryProperties` handled by the `FunctionAppLogs` parser |
| 4 Function Apps (`SFC-CodeGenerator-PRO`, `SFC-ScheduledJobs-PRO`, `SFC-PosWasmRelay-PRO`, `SFC-TicketProcess-PRO`) | `FunctionAppLogs` | `properties` is a **Python dict-repr string** (single-quoted), not JSON: every `JSON.parse` guard in the pipeline silently skips it | Dedicated hand-rolled Ruby parser (`if [category] == "FunctionAppLogs"` block) |
| Azure `AppServiceHTTPLogs` (Windows apps' infra-level HTTP access log) | Diagnostic Settings | Two shapes: `records`-wrapped with `properties` pre-stringified, and flat with `properties` as a live Hash | Branch accepts both |

Sales' `_exists_:Properties` returns 0 everywhere (GITIN-1835): no `Properties_*` fields remain after promotion.

## Fields promoted to bare top-level (identical name on every source)

### Always present when the source carries them (GITIN-1883, GITIN-1892, GITIN-2098)

| Field | CLEF source | Notes |
|---|---|---|
| `TraceKey` | `Properties.TraceKey` | Incoming `TraceKey` header, else W3C `Activity.TraceId`; propagated across services, so `TraceKey:"<key>"` finds the related lines in every service |
| `AppLevel` | `Level` (nested in `resultDescription` for Event Hub apps, top-level for Sales) | Logstash-derived (GITIN-1835); no application-level source exists. `Unknown` is a real value when no level is parsed |
| `TenantId` | `Properties.TenantId` | Opaque 12-char id matching `Organization.tenantId` in `docs/infrastructure.md` (`org_...`-shaped on PosWasmRelay: unresolved format discrepancy). Empty on system/background messages: not a pipeline failure |
| `Service` | `Properties.Service` | See "Service values". Meaning: the thing doing the logging |
| `Environment` | `Properties.Environment` | |
| `Version` | `Properties.Version` | |
| `UserId` | `Properties.UserId` | Always empty in every real sample (Auth0 `sub` claim absent); the guard skips empty strings, so 0 hits is the correct state |
| `ProcessType` | `Properties.ProcessType` | `Api`, `Web`, `Function`, `PosWasm` |
| `Component` | `Properties.Component` | **Unresolved discrepancy:** real values are `Api`/`Web`, not the domain name the source passes via `UseSmartFranLogEnrichment(component: "<Domain>")` (see `devs-log-structure.md` §3.2 and `cloud/events/20260819_promote-remaining-clef-fields/` H2) |
| `RequestId` | automatic ASP.NET Core MEL field (`HttpContext.TraceIdentifier`) | |
| `SourceContext` | automatic MEL field (`ILogger<T>` name) | Varies by call site: present on repository/controller logs, absent on `RequestHandlingMiddleware` logs |
| `TraceId`, `SpanId`, `ParentId` | `Properties.TraceId`/`SpanId`/`ParentId` | W3C ids stamped from `Activity.Current` on every line by `W3CAndAmbientTraceEnricher`; distinct from `TraceKey`. `ParentId` is not always present (6/10 on a Sales sample, absent on PosWasmRelay). Confirmed live on Sales-PRO and Business-PRO; not verified on PosWasmRelay. Detail: `cloud/events/20260923_gitin2098-traceid-not-promoted-graylog/` |

### Only when the log came through a `SmartFranLogExtensions` helper (GITIN-1892)

Absent on plain `ILogger` or middleware logs. As of 2026-09-14 only `Category` has been seen live (638 hits/24 h); the other six had 0 hits (the helpers had not fired in the windows checked, not a pipeline fault).

| Field | CLEF source key (not always the promoted name) | Helper |
|---|---|---|
| `Category` | `Properties.Category` | all 6 helpers (`LogBusinessEvent`, `LogSystemEvent`, `LogDomainError`, `LogTransientFailure`, `LogUnrecoverableFailure`, `LogSecurityAudit`) |
| `ErrorCode` | `Properties._error_code` | `LogDomainError` |
| `Operation` | `Properties.Operation` (message-template placeholder) | `LogTransientFailure`, `LogUnrecoverableFailure` |
| `Recovered` | `Properties._recovered` (bool) | `LogTransientFailure` |
| `Handled` | `Properties._handled` (bool) | `LogUnrecoverableFailure` |
| `AuditAction` | `Properties._audit_action` (bare `Properties.Action` exists, not promoted) | `LogSecurityAudit` |
| `AuditOutcome` | `Properties._audit_outcome` (bare `Properties.Outcome` exists, not promoted) | `LogSecurityAudit` |

**Pitfall:** the `_` prefix. `devs-log-structure.md` first documented these as plain PascalCase, which was wrong for 5 of them; the first deploy promoted the wrong keys and silently produced zero data (`cloud/events/20260819_promote-remaining-clef-fields/` H9). Always validate a promotion against `SmartFranLogExtensions.cs`. `Attempt`/`Action`/`Outcome` are not promoted by any ticket.

### HTTP request fields (GITIN-1940, GITIN-2034)

Two sources, same four names: the built-in ASP.NET Core "Request finished" line (`SourceContext: Microsoft.AspNetCore.Hosting.Diagnostics`, every HTTP request) and Azure's `AppServiceHTTPLogs`.

| Field | "Request finished" key | `AppServiceHTTPLogs` key | Type |
|---|---|---|---|
| `StatusCode` | `Properties.StatusCode` | `properties.ScStatus` (String or Integer) | Integer |
| `Path` | `Properties.Path` (`RequestPath` not promoted) | `properties.CsUriStem` | String |
| `Method` | `Properties.Method` | `properties.CsMethod` | String |
| `ElapsedMilliseconds` | `Properties.ElapsedMilliseconds` | `properties.TimeTaken` (Integer → Float) | Float |
| `ClientIP` | none | `properties.CIp` | String |

- Confirmed for Sales (24 h: `StatusCode` 1.04M, `Path`/`Method` ~1.1M, `ElapsedMilliseconds` 921K, `ClientIP` 848K). Whether Pos emits `AppServiceHTTPLogs` at all has not been checked.
- `AppServiceHTTPLogs` lines carry no `Service` value (`NOT category:AppServiceHTTPLogs` removes exactly the lines with an empty `Service`).
- **Sales `ElapsedMilliseconds` gap:** on the Sales direct-GELF branch the field is mostly absent because `Properties` carries it as an exponent-notation string (`"0.453886e2"`) and the filter only sets it for a `Numeric` (1 of 6,640 Sales lines with `StatusCode` in an hour had it). Why it becomes a string is unverified (hypothesis: decimal re-serialized as BigDecimal). Workaround (GITIN-2221): the Sales branch also converts the string and writes a new float field **`ElapsedMillisecondsOpe`**; only Sales fills it, `ElapsedMilliseconds` is unchanged. Checked 44 s on live traffic (30/30 lines, avg 434 ms); only messages indexed after the restart have it. The Operations dashboard's Sales Endpoints table uses it.
- `StatusCode` is on about half of the application-log lines that have `Method` (probably two lines per request, one being "Request finished"; unverified): counting by `Method` likely overstates requests, counting with `_exists_:StatusCode` does not. `Path` is on all of them.

### `NormalizedPath` — derived field (GITIN-2221)

The HTTP `Path` with route parameters removed and the remaining segments joined with `_`: `/api/v1/WalletCredentials/2024771231` → `api_v1_WalletCredentials`; `/api/Tenant/<hash>` → `api_Tenant`; `/` → `root`. Lets endpoint tables and terms aggregations group one route into one row.

- **Built by** a Ruby filter in the live Logstash config (`/etc/logstash/conf.d/azure-eventhub-to-graylog.conf` on the SmartCloud Graylog VM), right before the final `properties`-stringify step, after all blocks that set `Path`; runs on every event with `Path`. Not retroactive (live since 2026-10-13 19:31 UTC).
- **Route table** `/etc/logstash/normalized-paths.json`, read once in `init` (changing it needs a Logstash restart): 921 templates from the `SmartFran.Cloud` controller `[Route]`/`[Http*]` attributes (`origin/main` @ f88d6d743, 2026-10-07: 128 controller files, 792 distinct templates), 4 hand-added extras (root, `_blazor/{*rest}`, `health`, `notificationsCloud/{*rest}`), 120 Razor/Blazor `@page` routes, 6 SignalR hubs (`notificationsCloud`, `notifications`, `kdsordershub`, `hubs/saleorder`, `hubs/cash-alerts`, `hubs/walletnotifications`), `_content/{*}` and `_framework/{*}` (value `static`). Most specific template wins (most literal segments).
- **Fallbacks:** no template but a `static_suffixes` match (`.css .js .json .map .png .jpg .jpeg .gif .svg .ico .webmanifest .woff .woff2 .ttf .wasm .dll .pdf`) → `static`; anything else → `unmatched`. Routes defined other than by those attributes are missing. First check before the second pass: 6.7% `unmatched` (static files, Blazor pages, SignalR hubs); the `unmatched` share after the second pass is not measured (rerun GITIN-2218 C4 after ~24 h). Throughput and per-index-set mapping not verified.
- **Operating notes:** regenerate the table when controller routes change. The pre-change config is `azure-eventhub-to-graylog.conf.bak-GITIN-2221` (a backup name must not end in `.conf`). Patch, generator, tests and `deploy.sh` (`stage`, `apply`, `test`, `rollback`): `operations/events/20261013_gitin2221-normalizar-http-paths/`.

## `FunctionAppLogs` (GITIN-2050)

Before the parser every Function App message fell back to `message = "Microsoft.Web/sites/functions/log"` (the `operationName` fallback), unsearchable. Parser verified against real captured messages of all 4 apps. Detail: `cloud/events/20260915_functionapp-onboarding/`.

Two `properties.message` shapes, both handled:

| Shape | Content |
|---|---|
| `Host.Function.Console` | `properties.message` is itself a nested Python dict-repr string: `Timestamp`/`Level`/`MessageTemplate`/`Properties` (`SourceContext`/`Service`/`Environment`/`Version`/`TraceId`/`SpanId`/`ParentId`; PosWasmRelay also a nested `EntryProperties` hash with the POS client's own `Method`/`Path`/`StatusCode`/`ElapsedMs`/`TraceKey`) |
| `Function.<name>` / `Function.<name>.User` | `properties.message` is a plain string (`Executed Functions.X (Succeeded, Id=.., Duration=3ms)`); `functionInvocationId`/`functionName`/`eventId`/`eventName` are flat siblings |

| Promoted field | Source |
|---|---|
| `FunctionName` | `properties.functionName`, else `Properties.AzureFunctions_FunctionName` (separates e.g. ScheduledJobs' `RegisterBusinessLog` HTTP endpoint from its timer jobs) |
| `FunctionInvocationId` | `properties.functionInvocationId`, else `Properties.AzureFunctions_InvocationId` |
| `FunctionEventName` | `properties.eventName` (not promoted when the placeholder `"0"` on `.User` lines) |
| `message` | `nested.MessageTemplate`, or the plain string |
| `AppLevel` | `nested.Level`, or `properties.level` |
| `Service`, `Environment`, `Version`, `SourceContext`, `TraceId`, `SpanId`, `ParentId` | `inner_props.*` (`ParentId` absent on PosWasmRelay, present on CodeGenerator/ScheduledJobs) |
| `PosCode`, `ShiftCode` | `inner_props.*` or `ep.*` |
| `Method`, `Path`, `StatusCode`, `ElapsedMilliseconds`, `TraceKey`, `SourceContext`, `ClientService` | `ep.*` (`EntryProperties`, **PosWasmRelay only**); same names as `AppServiceHTTPLogs`, so the same query shape works |

- **Quoting quirk:** every string inside `EntryProperties` (`Method`, `Path`, `TraceKey`, `SourceContext`, `Service`, `Environment`, `Version`, `PosCode`, `ShiftCode`; not `StatusCode`/`ElapsedMs`) carries a literal wrapping `"`; the parser strips them.
- **`Service` vs `ClientService`:** the relay's own `Properties.Service` stays `Service`; the POS client's `EntryProperties.Service` (`SmartFran.Cloud.Pos.Wasm`) becomes `ClientService`, so neither overwrites the other.
- **`name` casing gotcha:** `name` (used for stream routing, from `resourceId`) is indexed **uppercase**; a query with Azure's casing returns 0 silently. Likely affects every category. Query `category:"FunctionAppLogs" AND name:"<APP>"` in uppercase.
- **Not extracted:** `Duration=Xms`/`Succeeded`/`Failed` on completion lines stay free text in `message`. Unpromoted nested fields: `CorrelationId`, `SessionId`.
- **Streams/index sets** (one pair per app): `SFC-CodeGenerator-prod`, `SFC-ScheduledJobs-prod`, `SFC-PosWasmRelay-prod`, `SFC-TicketProcess-prod`. Stream-id hex values of these streams are not recorded anywhere: pull via `GET /streams` before scripting. (The stream ids of the 8 `PROD-<App>-AppServiceHTTPLogs` streams are in the `cloud-appservice-perf-report` skill.) All 4 apps verified live; `SFC-CodeGenerator-PRO`'s `Service` shows the deployed source is `LiteEditionV2`; `SFC-TicketProcess-PRO` runs `ProcessTicketsHourly` (`Service: SmartFran.Cloud.Functions.Sales.TicketProcessAsync`).

## `SFC-PosWasmRelay-PRO`/`-DEV` traffic (GITIN-1924, GITIN-2134)

- **Promoted without a pipeline change** (Sales-branch logic fires incidentally): `Service` = `smartfran-pos-wasm` (the relay's `batch.SourceKey`, not the client's own), `Environment` (`Production`), `TenantId` (`org_...`-shaped, unlike other services; not raised with dev), `ProcessType` = `PosWasm`, `Component` = `Pos`, `Version`, `AppLevel`.
- **Not promoted at top level** (nested one level deeper under `Properties.EntryProperties`): `TraceKey`, `SourceContext`. Promoting them needs a Logstash change (an `EntryProperties`-aware fallback in the Sales-branch block, or a Graylog Pipeline Rule on the stringified `Properties`/`event_original`). `Category` is present but empty (HTTP-call log, not a helper), correctly skipped. (The `FunctionAppLogs` parser above does read `ep.*` for the fields it lists.)
- **Errors only:** over 7 days `Service:smartfran-pos-wasm AND StatusCode:*` returned only 404 (4,123), 500 (1,012), 408 (432), 400 (194), 403 (70) — **no 2xx**. This source cannot give a "worked before" baseline; use the receiving service's logs. `UserId` is empty; `PosCode`/`ShiftCode` live in `EntryProperties`. A client HTTP log also arrives a second time as a raw `FunctionAppLogs` line without promoted fields, so message counts can be about doubled.
- **Cross-service lookups work** (`SmartFran.Cloud.Platform.API`, `Client.Web`, `Business.API`, Functions log `/api/Tenant/…`; the client's `TraceKey` is propagated).
- **REST usage that worked** on `https://sfcloud-monitoreo.smartfran.com/graylog/api/`: `POST /search/aggregate` (JSON body with `query`, `timerange`, `group_by:[{field,limit}]`, `metrics:[{function:"count"}]`, header `X-Requested-By`) and `GET /search/universal/relative`; auth `curl -u "$GRAYLOG_API_KEY:token"`. The token of `sf-monitoreo.smartfran.com` (SmartPedidos/SmartLoyalty stack) returns 401 here.

## Service values, streams and the Operations dashboard (GITIN-2218)

- **`Service` values** on application logs with `Method` (1-hour window, Graylog 7.1.3): `SmartFran.Cloud.Orders.API`, `SmartFran.Cloud.Catalog.API`, `SmartFran.Cloud.Business.API`, `Sales`, `SmartFran.Cloud.Platform.API`, `SmartFran.Cloud.Client.Web`, `SmartFran.Cloud.Person.API`, `smartfran-pos-wasm`. `SmartFran.Cloud.Security.API` returned 0. These are the long assembly-style names; the 2026-08-18 GITIN-1883 samples showed short names (`Business`, `Platform`, `Person`, `Catalog`, `Orders`, `Client`). Why they differ is unknown, and the source predicts the long form (`SerilogBootstrap.Configure(cfg, serviceName)`; `EnrichmentMiddleware` uses `serviceName: env.ApplicationName`); no `ApplicationName`/`AssemblyName` override was found in the repo. Ask the dev team rather than guessing from source. Do not hardcode either form in a filter; check what is live. A `Service:Orders` filter returning 0 (reported in `cloud/CLAUDE.md`) is probably this: the live value is `SmartFran.Cloud.Orders.API`; not verified.
- **Streams:** application logs in `PROD-<X>-AppServicePlan`, HTTP logs in `PROD-<X>-AppServiceHTTPLogs`; `Client.Web` is the Admin app (`PROD-Admin-AppServicePlan`); pos-wasm is `PROD-PosWasmRelay-FunctionApp`. For application-log charts filter on `Service` or scope the widget to the application stream.
- **Query syntax confirmed:** `_exists_:("Method" AND "StatusCode")` and the unquoted form match the same messages as `_exists_:Method AND _exists_:StatusCode`; `_exists_:` on a nonexistent field returns 0 without error.
- **Operations dashboard** (id `6ace703e41759be0a237ff89`), tab "HTTP": 8 services (Sales, Business, Catalog, Orders, Person, Platform, Client, POS WASM) × 3 widgets (line chart by `Method`, line chart by `StatusCode`, Data Table of the top 10-20 `Path`), 24 h, each widget scoped to the service's application stream. Query pattern: `_exists_:Method AND NOT Method: ("OPTIONS") AND Service:<service>` (status widgets add `_exists_:("Method" AND "StatusCode")`, table widgets `_exists_:("Method" AND "Path")`).
- **Dashboard API quirks (Graylog 7.1.3):** `PUT /api/views/{id}` needs `{"entity": <view>}`; `state` is keyed by tab id; widget titles are in `state.<tab>.titles.widget` (not `config.title`); each widget's data comes from a search type in the view's saved search (`search_id`, linked by `state.<tab>.widget_mapping`), so a new widget needs a new saved search (`POST /api/views/search`) whose id goes into `search_id`; each widget has its own `streams`, `timerange`, `query`.

## Where the fields come from (application source)

Checked 2026-08-18 against `cloud/repo/SmartFran.Cloud` (`origin/dev`) and `devs-log-structure.md`. All web-facing services (Business, Catalog, Platform, Orders, Security, Person, Sales, plus `SmartFran.Cloud.Client.Web` behind `SmartFran-Cloud-Admin-PRO`) share the providers in `Source/Common/Providers/`. `Properties` is composed in layers (fuller detail in `devs-log-structure.md` §3):

1. **Process-level enrichers** (`Provider.Logger.Core/SerilogBootstrap.cs`): `Service`, `Environment`, `Version` on every line of the process, including outside HTTP requests.
2. **`EnrichmentMiddleware`** (`Provider.Logging.AspNetCore/Middleware/`, `app.UseSmartFranLogEnrichment(component: "<Name>")`): per request, overwrites with `Service`, `Environment`, `Version`, `TraceKey`, `TenantId`, `UserId`, `ProcessType`, `Component`. `TenantId` = `X-Tenant-Id` header, else `HttpContext.Items["tenantId"]` (set by each API's `TenantHandlingMiddleware`, resolving `org_id` → `tenant_id` via App Configuration `OrgTenant:{orgId}`), never straight from the Auth0 claims.
3. **`LogContextPushPropertyMiddleware`**: the equivalent for Service Bus / Event Grid consumers; pushes `TraceKey` (message `ApplicationProperty`, else `Activity.TraceId`, else a new GUID), `Service`, `Component`, `ProcessType` = `Function`.

## Where they sit in the Graylog JSON

- **Event Hub apps:** `event_original` → `records[0].resultDescription` (CLEF string) → `.Properties.*` and `.Level`. After Logstash the promoted fields are flat siblings of `resultDescription`, which stays unmodified for the full raw CLEF blob.
- **Sales:** the CLEF body is the message; `.Level` → `AppLevel`, `.Properties.{TraceKey,TenantId,Service,Environment}` (and the later fields) → bare top-level fields, leftover `Properties` stringified.
- **Why Sales' unification needed more than adding fields:** Sales' fields used to be `Properties_*`-prefixed by GELF's automatic flattening. Stringifying `Properties` stopped that and silently broke two Graylog Pipeline Rules from GITIN-1835 that keyed on `Properties_Service`/`Properties_Environment` (Sales `source` formatting and its stage-1 stream routing); both now read the bare fields.
- **Open gap:** the stage-1 rule that resolves `name`/`resource_group`/`resource_path` and routes into `PROD-Sales-AppServicePlan` (`GITIN-1835: CLEF Azure resource fields for Sales PRO`, id `6a7f2cb84814bcaed30c8de3`) only matches `Service:"Sales"` + `Environment:"Production"`. Other combinations (150 messages `Sales`/`Development`, 2 `SmartFran.Cloud.Sales.API`/empty on 2026-08-18) have `Service` but no resolved `name`; not fixed (GITIN-1835 open item 3).

## Query reference

Every promoted field is searchable with `_exists_:<field>`:

- **Always present:** `Service`, `Environment`, `TraceKey`, `AppLevel`, `Version`, `ProcessType`, `Component`, `RequestId`, `TraceId`, `SpanId`.
- **Conditional:** `TenantId` (not on system/background messages), `SourceContext` (varies by call site), `ParentId`, `UserId` (never seen), `Category` (seen live).
- **Helper-only, 0 hits as of 2026-09-14:** `ErrorCode`, `Operation`, `Recovered`, `Handled`, `AuditAction`, `AuditOutcome`.
- **HTTP:** `StatusCode`, `Path`, `Method`, `ElapsedMilliseconds` (often absent on Sales, see `ElapsedMillisecondsOpe`), `ClientIP` (`AppServiceHTTPLogs` only), `NormalizedPath`.
- **`FunctionAppLogs` only:** `FunctionName`, `FunctionInvocationId`, `FunctionEventName`, `ClientService` (PosWasmRelay).

## Detail per ticket (event folders under `cloud/events/` unless noted)

- GITIN-1883 / GITIN-1892: `20260819_promote-remaining-clef-fields/`
- GITIN-1940: `20260825_sales-caerequest-408-timeout/`
- GITIN-2034: `20260914_gitin2034-timetaken-elapsedms-promotion/`
- GITIN-2050: `20260915_functionapp-onboarding/`
- GITIN-2098: `20260923_gitin2098-traceid-not-promoted-graylog/`
- GITIN-2221: `operations/events/20261013_gitin2221-normalizar-http-paths/`
- Related docs: `docs/devs-log-structure.md` (intended schema), `docs/infrastructure.md` (`Organization.tenantId`, Graylog retention and index sets).

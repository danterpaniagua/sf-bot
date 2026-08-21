# SmartFran Cloud — Graylog Log Fields Reference

**Last updated:** 2026-08-19 (GITIN-1892 — 13 more fields promoted: `Version`, `UserId`, `ProcessType`, `Component`, `RequestId`, `SourceContext`, `Category`, `ErrorCode`, `Operation`, `Recovered`, `Handled`, `AuditAction`, `AuditOutcome`. 5 confirmed active on real traffic (`Version`/`ProcessType`/`Component`/`RequestId`/`SourceContext`), `UserId` confirmed correctly inactive by design (always empty in practice, guard skips it), 7 deployed but not yet observed on real traffic (`Category` + the 6 helper-conditional fields))

Tracks the application-level fields (from Serilog's CLEF `Properties` object) that are expected to be searchable as flat, top-level Graylog fields — across the `AppServiceConsoleLogs` Event Hub ingestion path and Sales' separate direct-GELF path. Update whenever a ticket confirms a new field's location or promotes one to top-level.

**See `docs/devs-log-structure.md`** for the full canonical log schema as designed by the dev team (all 6 logging helpers, `Properties` composition layers, PII redaction, exception formatting, anti-patterns) — that document is the source of truth for what the app *should* emit. This document is narrower: it tracks specifically what's confirmed to actually reach Graylog as a flat, searchable field on the SRE/pipeline side, including gaps between the two where they're been found.

## Scope

- **Event Hub path** (`cloud-graylog/docs/azure-eventhub-to-graylog.conf`, via Logstash): `Business`, `Admin`, `Platform`, `Person`, `Catalog`, `Orders`. Each app's `AppServiceConsoleLogs` record carries a Serilog CLEF payload (`Timestamp`/`Level`/`MessageTemplate`/`Properties`) as a JSON **string** inside `resultDescription` — one layer of nesting deeper than Sales.
- **Sales**: separate direct Serilog→Event-Hub CLEF sink (GITIN-1811/1835), bypassing Diagnostic Settings' `records` envelope entirely. Its CLEF payload arrives as the message's own top-level body, so GELF auto-flattens any nested `Properties` object into `Properties_<Key>` fields automatically — no pipeline rule needed for that flattening itself (confirmed via `_exists_:Properties` = 0 hits everywhere, GITIN-1835).
- **Pos**: out of scope. `AppServiceConsoleLogs` is structurally unsupported for .NET apps on Windows App Service (GITIN-1811, Microsoft-confirmed) — confirmed 0 messages in this category for both Sales and Pos (both Windows-hosted) before Sales' GITIN-1811 workaround. Pos has not adopted the same direct-GELF workaround.

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

**Mechanism note (why unification required more than adding fields):** Sales previously had these same fields accessible, but under `Properties_`-prefixed names (`Properties_TraceKey`, etc.) — an artifact of GELF's own automatic flattening of any nested JSON object it receives, not something Logstash controlled. Achieving true bare-name unification required the Logstash pipeline to also read Sales' top-level `Properties` object directly, then **stringify** it afterward so GELF stops auto-flattening it into `Properties_*` duplicates (same technique already used for Azure's own lowercase `properties` field). That stringification silently broke 2 Graylog Pipeline Rules from GITIN-1835 that keyed on the literal `Properties_Service`/`Properties_Environment` field names (Sales' `source` formatting and its Stage 1 stream-routing rule) — both updated in the same change to read the new bare `Service`/`Environment` fields instead. Confirmed on live traffic post-deploy: no regression in Sales' `source`/`name`/stream routing.

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
_exists_:Category             // deployed, not yet observed live — needs a helper-emitted log
_exists_:ErrorCode            // deployed, not yet observed live — LogDomainError only
_exists_:Operation            // deployed, not yet observed live — LogTransientFailure/LogUnrecoverableFailure only
_exists_:Recovered            // deployed, not yet observed live — LogTransientFailure only
_exists_:Handled              // deployed, not yet observed live — LogUnrecoverableFailure only
_exists_:AuditAction          // deployed, not yet observed live — LogSecurityAudit only
_exists_:AuditOutcome         // deployed, not yet observed live — LogSecurityAudit only
```

`Attempt`/`Action`/`Outcome` (the message-template-derived PascalCase companions to `_recovered`/`_audit_action`/`_audit_outcome` — see `devs-log-structure.md` §9) are **not promoted to top-level Graylog fields** — they exist in the app's `Properties`, but no ticket has flattened them. Not currently in scope for any open ticket.

## `name` resolution for Sales (GITIN-1835 open item, field names updated by GITIN-1883)

The Stage 1 Graylog Pipeline Rule that resolves `name`/`resource_group`/`resource_path`/etc. and routes into `PROD-Sales-AppServicePlan` is scoped **only** to `Service: "Sales"` + `Environment: "Production"` (originally `Properties_Service`/`Properties_Environment` under GITIN-1835's naming; migrated to the bare field names as part of GITIN-1883's unification — see rule `GITIN-1835: CLEF Azure resource fields for Sales PRO`, id `6a7f2cb84814bcaed30c8de3`). Confirmed live pre-migration (GITIN-1883, 2026-08-18, 30-min window): 150 messages `Sales`/`Development` and 2 `SmartFran.Cloud.Sales.API`/*(empty)* had the Service field populated but no `name` resolved — this specific gap (other Service/Environment combinations besides Sales+Production) is **not fixed**, still flagged for whoever picks up GITIN-1835's open item #3.

## Related tickets

- GITIN-1811 (closed) — `AppServiceConsoleLogs` unsupported on Windows/.NET; Sales' direct-GELF sink workaround.
- GITIN-1835 (closed) — universal `AppLevel`; Sales CLEF `message`/`full_message`/`source`/resource-fields formatting. 3 of its Graylog Pipeline Rules updated by GITIN-1883 (field names only, same logic) to track the new bare `Service`/`Environment` names.
- GITIN-1883 (closed) — promoted `TraceKey`/`TenantId`/`Service`/`Environment` to top-level fields for the 6 Event Hub apps, then unified Sales onto the same bare names (removing `Properties_` prefix), updating GITIN-1835's dependent Pipeline Rules in the same change.
- GITIN-1892 (closed, 2026-08-19, parent GITIN-1835) — promoted the remaining 13 fields from `devs-log-structure.md` §3.2/§3.3 (`Version`/`UserId`/`ProcessType`/`Component`/`RequestId`/`SourceContext`/`Category`/`ErrorCode`/`Operation`/`Recovered`/`Handled`/`AuditAction`/`AuditOutcome`) for the same 6 Event Hub apps and Sales. Deployed across 3 incremental patches the same day: initial promotion (wrong source keys for 5 helper-conditional fields, caught by validating against `SmartFranLogExtensions.cs` directly), a corrective patch fixing those 5 keys, and a third patch adding `Version` after a §3.2 coverage audit found it had never been promoted. Full detail in `cloud/events/20260819_promote-remaining-clef-fields/`.

## Related docs

- `docs/devs-log-structure.md` — canonical log schema, dev-authored, source of truth for intended behavior.
- `docs/infrastructure.md` — `Organization.tenantId`, the same value that ends up in `TenantId`.

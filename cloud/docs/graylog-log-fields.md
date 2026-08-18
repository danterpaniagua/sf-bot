# SmartFran Cloud — Graylog Log Fields Reference

**Last updated:** 2026-08-18 (naming unified across all services)

Tracks the application-level fields (from Serilog's CLEF `Properties` object) that are expected to be searchable as flat, top-level Graylog fields — across the `AppServiceConsoleLogs` Event Hub ingestion path and Sales' separate direct-GELF path. Update whenever a ticket confirms a new field's location or promotes one to top-level.

**See `docs/devs-log-structure.md`** for the full canonical log schema as designed by the dev team (all 6 logging helpers, `Properties` composition layers, PII redaction, exception formatting, anti-patterns) — that document is the source of truth for what the app *should* emit. This document is narrower: it tracks specifically what's confirmed to actually reach Graylog as a flat, searchable field on the SRE/pipeline side, including gaps between the two where they're been found.

## Scope

- **Event Hub path** (`cloud-graylog/docs/azure-eventhub-to-graylog.conf`, via Logstash): `Business`, `Admin`, `Platform`, `Person`, `Catalog`, `Orders`. Each app's `AppServiceConsoleLogs` record carries a Serilog CLEF payload (`Timestamp`/`Level`/`MessageTemplate`/`Properties`) as a JSON **string** inside `resultDescription` — one layer of nesting deeper than Sales.
- **Sales**: separate direct Serilog→Event-Hub CLEF sink (GITIN-1811/1835), bypassing Diagnostic Settings' `records` envelope entirely. Its CLEF payload arrives as the message's own top-level body, so GELF auto-flattens any nested `Properties` object into `Properties_<Key>` fields automatically — no pipeline rule needed for that flattening itself (confirmed via `_exists_:Properties` = 0 hits everywhere, GITIN-1835).
- **Pos**: out of scope. `AppServiceConsoleLogs` is structurally unsupported for .NET apps on Windows App Service (GITIN-1811, Microsoft-confirmed) — confirmed 0 messages in this category for both Sales and Pos (both Windows-hosted) before Sales' GITIN-1811 workaround. Pos has not adopted the same direct-GELF workaround.

## Tracked fields

All 5 fields below are now **bare, identically-named top-level fields across every service** — Event Hub apps and Sales alike, no `Properties_` prefix anywhere (unified 2026-08-18, GITIN-1883, at explicit request).

| Field | Event Hub apps (Business/Admin/Platform/Person/Catalog/Orders) | Sales (direct GELF) | CLEF source | Ticket |
|---|---|---|---|---|
| `TraceKey` | Top-level `TraceKey` | Top-level `TraceKey` | `Properties.TraceKey` | GITIN-1883 |
| `AppLevel` | Top-level `AppLevel` | Top-level `AppLevel` | `Level` — nested inside `resultDescription` for Event Hub apps, top-level for Sales | GITIN-1835 |
| `TenantId` | Top-level `TenantId` | Top-level `TenantId` | `Properties.TenantId` — opaque 12-char alphanumeric id, matches `Organization.tenantId` in `docs/infrastructure.md` (e.g. `d3186bc6d7b2`, confirmed same literal value in a real GITIN-1883 sample) | GITIN-1883 |
| `Service` | Top-level `Service` | Top-level `Service` | `Properties.Service` | GITIN-1883 |
| `Environment` | Top-level `Environment` | Top-level `Environment` | `Properties.Environment` | GITIN-1883 |

`TenantId` is legitimately empty on system/background messages with no active tenant context (confirmed GITIN-1883, 3 of 6 sampled apps) — not a bug, don't treat an empty value as a pipeline failure. Same empty-value guard applied to the Sales branch for consistency, though not independently confirmed empty there.

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

## `name` resolution for Sales (GITIN-1835 open item, field names updated by GITIN-1883)

The Stage 1 Graylog Pipeline Rule that resolves `name`/`resource_group`/`resource_path`/etc. and routes into `PROD-Sales-AppServicePlan` is scoped **only** to `Service: "Sales"` + `Environment: "Production"` (originally `Properties_Service`/`Properties_Environment` under GITIN-1835's naming; migrated to the bare field names as part of GITIN-1883's unification — see rule `GITIN-1835: CLEF Azure resource fields for Sales PRO`, id `6a7f2cb84814bcaed30c8de3`). Confirmed live pre-migration (GITIN-1883, 2026-08-18, 30-min window): 150 messages `Sales`/`Development` and 2 `SmartFran.Cloud.Sales.API`/*(empty)* had the Service field populated but no `name` resolved — this specific gap (other Service/Environment combinations besides Sales+Production) is **not fixed**, still flagged for whoever picks up GITIN-1835's open item #3.

## Related tickets

- GITIN-1811 (closed) — `AppServiceConsoleLogs` unsupported on Windows/.NET; Sales' direct-GELF sink workaround.
- GITIN-1835 (closed) — universal `AppLevel`; Sales CLEF `message`/`full_message`/`source`/resource-fields formatting. 3 of its Graylog Pipeline Rules updated by GITIN-1883 (field names only, same logic) to track the new bare `Service`/`Environment` names.
- GITIN-1883 (closed) — promoted `TraceKey`/`TenantId`/`Service`/`Environment` to top-level fields for the 6 Event Hub apps, then unified Sales onto the same bare names (removing `Properties_` prefix), updating GITIN-1835's dependent Pipeline Rules in the same change.

## Related docs

- `docs/devs-log-structure.md` — canonical log schema, dev-authored, source of truth for intended behavior.
- `docs/infrastructure.md` — `Organization.tenantId`, the same value that ends up in `TenantId`.

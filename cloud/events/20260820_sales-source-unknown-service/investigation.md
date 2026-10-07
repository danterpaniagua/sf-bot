# Investigation — messages with source:unknown-service (GITIN-1908)

**Status:** converged — ready for ticket (pending PM decision on the `WalletNotificationService` tier, see Next steps). Original working theory (stale `Properties_Service` field name, same class as GITIN-1905) **refuted** by live rule source — see below; root cause identified as a three-tier breakdown of legitimate/expected `Service`-absence, not a pipeline bug.

## Objective

New bug report: some Graylog messages show `source: "unknown-service"`. Distinct symptom from GITIN-1905 (Default Stream duplication). Initially suspected same root cause family — a field-name drift between `Properties_Service` (stale, per the local reference file) and `Service` (live, per GITIN-1905) — but this is now ruled out for these two rules specifically.

## Confirmed facts

Live source pulled 2026-08-21 via `GET /api/system/pipelines/rule` (filtered `title contains "CLEF source"`):

```
rule "GITIN-1835: CLEF source from Properties.Service"
when
  has_field("MessageTemplate") AND has_field("Service")
then
  set_field("source", $message.Service);
end

rule "GITIN-1835: CLEF source fallback"
when
  has_field("MessageTemplate") AND NOT has_field("Service")
then
  set_field("source", "unknown-service");
end
```

Both rules already reference bare `Service`, not `Properties_Service` — they were migrated at the same time as the rule GITIN-1905 checked. (The local `.rule` reference file is stale here too, still showing `Properties_Service` in the title/body text, but that's a docs-lag issue, not a live-pipeline bug — same class of doc drift as GITIN-1905, not the message-tagging bug itself.)

**This refutes the original theory.** The fallback rule firing `source: "unknown-service"` is therefore only happening on messages that genuinely lack a `Service` field at the time this rule runs — not a systemic misfire from a stale field-name reference. Need to determine: which message shape(s) lack `Service`, how many, and why (e.g. a specific app/service not emitting it, a pipeline-stage-ordering issue where this rule runs before `Service` is set, etc.).

## Relevant documentation found (cloud-graylog repo, external to bots/)

`~/Documentos/git/cloud-graylog/docs/azure-eventhub-to-graylog.conf`, GITIN-1883 section (lines 159–226), documents the Logstash-side promotion logic that feeds the `Service` field these Graylog rules key on:

- For Sales' direct-GELF path, bare `Service` is only promoted from the event's top-level `Properties` hash when non-empty: `event.set("Service", top_props["Service"]) if top_props["Service"].is_a?(String) && !top_props["Service"].empty?` (line 219). If a message's `Properties` lacks `Service`, no bare `Service` field is set — so the "CLEF source fallback" rule correctly fires `unknown-service`. That part of the pipeline is working as designed, not a bug, assuming the absence is legitimate.
- The doc itself flags this as **unconfirmed for Sales**: "TenantId is legitimately empty on system/background messages with no active tenant context (confirmed on 3 of 6 sampled Event Hub apps)... same guard applied to the Sales branch for consistency, even though not independently confirmed empty there." The confirmed 6/6 sample covers only the 6 Event Hub apps (Business/Admin/Platform/Person/Catalog/Orders) — Sales' `Service`/`TenantId` absence behavior was never independently verified against real traffic.

**Updated working theory:** `source: "unknown-service"` likely reflects real Sales messages whose `Properties` hash legitimately lacks `Service` (e.g. system/background messages with no active service context, mirroring the confirmed `TenantId` pattern) — an assumed-safe fallback that was never checked against live Sales data. Needs confirmation either way: legitimate-absence (no fix needed, maybe just docs) vs. some other gap (actual bug).

## Confirmed against real data (2026-08-21)

Queried Graylog (Views Search API, `source:"unknown-service"`, relative 24h) — **223,916 total matching messages** in the last 24h alone, all streams. Sampled 20 (API default page, not random, but 20/20 consistent):

- All 20 are from Sales PRO (`Host: smartfran-cloud-sales-pro.azurewebsites.net`).
- All 20 are ASP.NET Core **built-in framework/middleware diagnostics**, not app-level business logs:
  - `"Request starting/finished HTTP/1.1 ..."` — `SourceContext: Microsoft.AspNetCore.Hosting.Diagnostics`
  - `"CORS policy execution successful."` — `SourceContext: Microsoft.AspNetCore.Cors.Infrastructure.CorsService`
- None of the 20 have a `Service` key anywhere in `Properties` — only framework-native fields (`Protocol`, `Method`, `Host`, `Path`, `EventId`, `RequestId`, `ElapsedMilliseconds`, `StatusCode`, etc.).

**Conclusion: `unknown-service` is correct, expected fallback behavior for these messages, not a bug.** These are plain ASP.NET Core framework logs (request-in/request-out, CORS middleware) that never pass through the app's own custom logging helpers (`SmartFranLogExtensions`, per `devs-log-structure.md` — the layer that sets `Service`/`TenantId`/`Environment`). They never had a `Service` value to promote in the first place. This is a stronger, more specific version of the "legitimate absence" theory from the cloud-graylog doc — not the `TenantId`-on-background-message pattern exactly, but the same underlying class: messages genuinely outside the app's own logging context.

**Follow-up query (2026-08-21):** re-ran excluding `SourceContext:Microsoft.AspNetCore.*` — **1,268 of the 223,916 (0.6%)** remain, over the same 24h window. Sampled 20 of these 1,268; they split into two distinct `SourceContext` groups, no other shapes seen:

- **12/20 (60%) — `SmartFran.Cloud.Sales.Application.Services.VirtualWallet.SignalR.WalletNotificationService`**, message `"Notificación enviada: Orden creada ORD..."`. This is **Sales' own application code** (not a framework/SDK namespace), logging a real business event (wallet notification on order creation, carrying the order ID) — but apparently via plain `ILogger`, not through the app's `SmartFranLogExtensions` helpers that set `Service`/`TenantId`/`Environment`. Unlike the ASP.NET Core framework noise, this is a case where `unknown-service` genuinely loses attribution on a traceable business event.
- **8/20 (40%) — `Microsoft.Azure.SignalR.ServiceConnection`** (`"Connection ... ended."`) and **`Microsoft.Azure.SignalR.DefaultServiceEventHandler`** (`"... received service event for Group(...) is NotExisted..."`) — Azure SignalR SDK's own internal logging (connection lifecycle, group management). Same class as the ASP.NET Core framework noise: third-party library logs never enriched by the app.

**Revised picture:** `source: "unknown-service"` volume breaks into three tiers — (1) ASP.NET Core framework diagnostics (222,648/24h, ~99.4%) — legitimate, no fix needed; (2) Azure SignalR SDK internals (a portion of the 1,268) — same class, legitimate; (3) `WalletNotificationService` app-level logs (the other portion of the 1,268) — a real gap: business-relevant events not going through the standard enrichment path, worth a decision on whether to fix.

## Next steps

1. Get an exact count split within the 1,268 (e.g. query each `SourceContext` separately) to size tier (3) precisely rather than extrapolating from the 20-message sample.
2. Decide scope for GITIN-1908 with PM, now with three tiers instead of one: (a) framework/SDK tiers — leave as-is, document as intended; (b) `WalletNotificationService` tier — consider routing through the standard `SmartFranLogExtensions` helpers so these get `Service`/`TenantId`, since they carry real order-notification data worth attributing; (c) broader "derive `source` from `Host` when `Service` is absent" as a fallback improvement covering all three tiers at once, still worth weighing against scope/cost.
3. Update the cloud-graylog doc's "not independently confirmed empty there" note for Sales, now that this is confirmed against real traffic.

Jira: `https://smartit-ar.atlassian.net/browse/GITIN-1908` (per user; parent not specified).

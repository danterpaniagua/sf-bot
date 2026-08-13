# Investigation — 20260728_logging-verbosity-ef-core-cors

**Status:** converged — ready for ticket

## Confirmed facts
- Real OpenSearch data (`business__6`, `sales__2` — the newest/currently-filling index per app, best available proxy for "current" ingest) shows Business's `AppServiceConsoleLogs` category is very much active (8,459,208 docs, 48.4% of the two apps' combined current volume) — contradicts the `cloud-graylog/CLAUDE.md` (2026-07-02) note that Business's console logs were disabled via manual drift. Either that drift was already fixed, or the original finding was wrong/stale (Q5, this event's scripts.sh).
- New, previously-unflagged fact: Sales has **zero** `AppServiceConsoleLogs` docs in its current index — only `AppServiceAppLogs` and `AppServiceHTTPLogs` (Q5).
- `operationName` is uninformative for message-level analysis — it's a generic Azure operation tag (`Microsoft.Web/sites/log`) that just happens to numerically match whichever category dominates each app; not real message granularity (Q7).
- `message` field is analyzed `text` (standard analyzer), not aggregatable as exact strings. `resultDescription` is `keyword`-typed and is the useful field for top-message analysis (Q8).
- Business's top-20 `resultDescription` values account for 33.2% of its current volume (4,374,288 / 13,165,348 docs) — 19 of the 20 are Entity Framework Core debug-level tracing (`dbug: Microsoft.EntityFrameworkCore.*`, DbCommand lifecycle, connection open/close, context init/dispose) plus one ASP.NET Core MVC debug line (Q9).
- Sales's top-20 `resultDescription` values account for 34.6% of its current volume (1,489,355 / 4,301,202). Breakdown: 406,094 have no `resultDescription` (raw `AppServiceHTTPLogs`, legitimate — matches the HTTPLogs category count exactly). 193,002 are `CORS policy execution successful` (ASP.NET Core CORS middleware, pure noise). The rest are ASP.NET Core MVC pipeline lines (`Start processing HTTP request` → `Route matched` → `Executing action method` → `Executing endpoint` → `Executed endpoint` → `Executing OkObjectResult`) — each real request (e.g. `SaleController.CreateAsync`, ~46,500 calls) produces ~6 separate framework log lines (Q9).

## Current working theory
The dominant driver of current Business+Sales log volume is not application business logic — it's **framework/ORM debug-level logging left enabled in production**: `Microsoft.EntityFrameworkCore` category logged at `Debug` level in Business, and ASP.NET Core's MVC pipeline + CORS middleware logged at Info/Debug level in both apps, multiplying each real business event into multiple log lines. Setting these logging categories to `Warning` in both apps' production config (`appsettings.json` → `Logging:LogLevel`) would plausibly cut ingest volume by 30-50%+, independent of any infrastructure or platform (Datadog/Graylog) decision — and this reduction would compound across every franchise-scaling tier discussed in `20260723_franchise-scaling-costs`, not just today's baseline.

## Ruled out
- Business's `AppServiceConsoleLogs`-disabled-via-drift theory (from `cloud-graylog/CLAUDE.md`, 2026-07-02) as an explanation for low current Sales+Business volume vs. older fleet-wide baselines — ruled out by live data (Q5): Console Logs are Business's single largest current category, not absent.

## Open questions / next steps
- Confirm with dev whether `Microsoft.EntityFrameworkCore` debug logging in Business is intentional (recent troubleshooting left on) or an oversight.
- Quantify the long tail (66.8% of Business's volume, 65.4% of Sales's) beyond the top-20 buckets — likely more of the same EF Core/MVC-pipeline pattern at lower per-message frequency, not yet confirmed.
- Re-open the still-unresolved 12.1M/day vs. ~27.5M/day expected-volume gap from `20260723_franchise-scaling-costs` — the drift theory that explained it is now ruled out, so that gap is unexplained again (belongs to that ticket, not this one, but flagging the dependency).

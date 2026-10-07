# Investigation — 20260915_gitin2042-waf-cost-estimate

**Jira:** GITIN-2042
**Related:** GITIN-1938 (`cloud/events/20260825_wholesale-service-infra-proposal/`) — this ticket estimates cost for that investigation's **Option B**.
**Status:** converged — ready for ticket (`ops.md`, `email_ops.md` written 2026-09-15)

## Context

GITIN-1938 evaluated three architecture options for fronting the new wholesale service (and optionally retail) with a WAF:

- **A** — proposal as written: dedicated APIM (wholesale-only) + WAF extended to all of cloud infra in Phase 2.
- **B** — DNS direct (no APIM) + WAF still extended to retail. Same WAF-becomes-shared trade-off as A, without APIM cost/complexity.
- **C** — wholesale-exclusive WAF, never extended to retail.

This ticket (GITIN-2042) needs a cost estimate specifically for **Option B**: WAF only, no APIM, scope extended to cover retail traffic (both tenants' POS/Admin/etc. App Services), not just wholesale.

Per GITIN-1938's open questions, the estimate must cover **two full environment sets** — PROD and non-prod (non-prod lives in a separate subscription, `SmartFran.Cloud` under Smart IT - Grido, DEV/DEV2/STG/TEST/POC — see `cloud/docs/infrastructure.md`).

## Input received — cloud dev responsible (email, 2026-09-15)

Traffic-volume data for the WAF sizing, provided by the cloud dev responsible via email. Source: read from POS (Blazor WASM) code, **not** a production measurement — dev's own caveat, needs cross-checking against real access logs before the estimate is finalized.

**Per-sale request count** (1-step typical counter sale, Argentina, e-invoicing on, no loyalty/coupon/MercadoPago/KDS): **8 requests** to own APIs + **1** to the external Loyalty host.
- 4 for the sale itself: SaleCreate, CaeRequest (e-invoicing), SaleClose, business-log write.
- 4 post-sale reset: 3 are a repeated favorites query (dev flagged as an optimization opportunity, separate from this ticket), 1 Loyalty validation.
- Cart size (products/combos/optionals) does **not** add requests — resolved in-memory against a cached price list.

**Add-ons on top of the floor, by config:**
| Factor | Delta |
|---|---|
| KDS enabled | +1 |
| Tenant ≠ Grido (cloud promos) | +2 |
| Cupón Pedigrido | +2 to +4 |
| Club Grido member (external host) | +3 to +4 |
| MercadoPago QR | +2 to +4 |
| 2-step / 3-step flow | +3 / +5 |
| E-invoicing by country | AR 1 · PE 1 · UY 2 · PY 3 |

Realistic floor: **8–10 requests/sale**. Ceiling with everything enabled (3-step + KDS + MP + coupon + Paraguay): **~20 requests/sale**.

**Background traffic, per open POS terminal regardless of sales** — this is what the dev expects to dominate the estimate:
- Heartbeat every 50s → **72 req/h per POS**.
- Promo/combo sync every 15 min → **4 req/h per POS** (non-Grido tenants only).
- Log relay: up to 1 POST every 5s when there are lines to send.
- SignalR: 1 HTTP `negotiate` + 1 persistent WebSocket per hub (orders, KDS, cash-register alerts).

Dev's own sizing example: at 20 sales/hour, one POS generates ~180 sale-related requests vs. ~76 heartbeat/sync requests per hour — **~30% of traffic is sale-volume-independent** and is paid for on every open-but-idle register. Dev flagged this as something to resolve **before** WAF adoption (cost driver, not a one-time sizing input).

**Two design notes from the dev, relevant to WAF scope/architecture:**
1. Printing does **not** go through the WAF — JSPrintManager talks to `localhost` on the register via WebSocket, out of scope entirely.
2. POS today hits **separate App Service hostnames per domain** (Sales, Business, Catalog, Person) plus Azure Functions plus the external Loyalty host. A single WAF requires putting all of these origins behind the same front door — the proposal needs to account for that (multi-origin backend pool / multiple listeners, not a single backend).

## Confirmed facts (inherited from GITIN-1938 / infrastructure.md)

- No WAF or APIM exists today in front of retail or wholesale — both hit App Services directly via per-tenant hostname/SNI binding (`cloud/docs/infrastructure.md` line 178-179).
- WAF product/tier for GITIN-1938 was left **unconfirmed** — Application Gateway WAF_v2 vs. Azure Front Door Premium, per the 1938 investigation. This directly gates the cost model (Application Gateway WAF_v2 bills on Capacity Units/throughput; Azure Front Door WAF bills on requests processed + data transfer + a fixed base fee) and is the first blocking question for this estimate.
- Retail has 8 shared production App Services (Pos, Admin, Business, Sales, Orders, Platform, Person, Catalog) plus 3 Function Apps, all in `SmartFran.Cloud.PRO`. 4 tenants confirmed onboarded (Grido, Weiss, lodejacinto, ultracai) as of 2026-07-11 — no confirmed total POS-terminal count.

## Decision

User confirmed (2026-09-15): estimate **both** products in parallel rather than committing to one — Azure Front Door Premium and Application Gateway WAF_v2 — so the ticket/email presents a comparison.

## Pricing data (confirmed via Azure Retail Prices API, 2026-09-15)

Public API, no auth. Full raw responses saved: `data/pricing_frontdoor.json` (389 items, unfiltered — Front Door is a global/zone-priced service, not region-scoped), `data/pricing_appgw.json` (27 items, `armRegionName eq 'eastus2'`).

**Azure Front Door Premium** (Zone 1 — includes North America; WAF managed/custom rules included in Premium at no extra charge, confirmed no separate WAF meter exists under this service):

| Meter | Price |
|---|---|
| Base Fee | $330 / month (fixed, per Front Door profile) |
| Requests | $0.015 / 10K = **$1.50 / million** (base tier; cheaper at >250K·10K volume tiers) |
| Data Transfer Out | $0.0825 / GB (base tier) |
| Data Transfer In | $0.02 / GB |

**Application Gateway WAF_v2** (`eastus2`, Standard/non-discounted meters):

| Meter | Price |
|---|---|
| Fixed Cost | $0.36 / hour ≈ **$262.80/month** (per gateway deployment) |
| Capacity Units | $0.008 / CU-hour (autoscales with throughput/connections/compute; minimum instance count not yet modeled — see below) |

## Cost model (built, needs 3 inputs to finalize)

Both environments (PROD + non-prod) multiply every fixed cost by 2 per GITIN-1938's confirmed requirement.

Both products need one deployment covering all consolidated origins (Sales/Business/Catalog/Person/Functions + external Loyalty host) per the dev's "single front door" design note — Front Door natively via multiple origin groups; App Gateway via multiple listeners/backend pools on one instance (assumed, not yet confirmed against a real multi-site AppGW config).

Request volume formula, per POS-hour (open register, all tenants except where noted):
- Background floor: 72 (heartbeat) + 4×[tenant≠Grido] (sync) = **76–80 req/h**, independent of sales.
- Sale-driven: (sales/hour) × (8–20 req/sale, config-dependent).
- Log relay: **not usable yet** — dev gave only a ceiling ("up to 1 POST/5s = up to 720/h when there are lines to send"), no typical/average rate. At the ceiling this alone would 9x the background floor, so this is the single largest source of uncertainty in the whole estimate — needs either a real average from the dev or a log sampled from Graylog.

## Real production traffic data (2026-09-15)

User pointed at `cloud/events/20260913_pos-net-http-timeout/data/timetaken_by_path_aggregated.csv` — real `AppServiceHTTPLogs`/`ElapsedMilliseconds` data pulled from Graylog during that incident's investigation (10-min buckets, `2026-09-11T18:20Z`–`2026-09-15T13:50Z`, 91.5h span, 698,431 total requests). Per user: this volume corresponds to **200 franchises** currently live.

**Scope caveat — this is Sales-API traffic only**, not the full request surface. Paths are all Sales.API domain (`Sale/Create`, `Sale/Close`, `WsFeAr/CaeRequest`, `Shift/*`, `Movement/*`, `Kds/*`, `PaymentMethod/GetAll`, etc.) — none of Business/Catalog/Person/Orders/Platform/Admin/Pos-static/Functions/external-Loyalty, which would also sit behind the same consolidated WAF per the dev's design note. Treat all numbers below as a **partial, real lower bound**, not the total.

Referer breakdown: 94.8% `grido.pos.smartfran.com`, 2.7% `weiss.pos.smartfran.com`, 2.3% no-referer (server-to-server/health), 0.3% MercadoPago webhook — so the "200 franchises" figure is a blended Grido-dominant rate, not a clean per-tenant unit.

**Unit mismatch flag:** this rate is per *franchise location*, not per *POS terminal* (register) like the dev's email. A franchise commonly runs multiple POS terminals, so this can't be directly cross-checked against the dev's per-POS-terminal background-traffic numbers without knowing average terminals/franchise — noting, not resolving, since that number isn't available yet either.

**Measured rate:** 7,633 req/h @ 200 franchises → **38.17 req/franchise/hour** (Sales-API surface, current blended tenant mix).

**Linear scaling to target franchise counts** (PROD, Sales-API surface only, Front Door Requests meter @ $1.50/million, base tier no volume discount applied):

| Franchises | req/hour | req/month (×730h) | Front Door Requests cost/mo |
|---|---|---|---|
| 1,500 | 57,248 | 41,791,363 | $62.69 |
| 2,000 | 76,331 | 55,721,817 | $83.58 |
| 2,600 | 99,231 | 72,438,363 | $108.66 |

Data transfer (in/out) and Application Gateway CU cost still need average request/response payload size — not in this CSV (only `avg_ms`/`max_ms`/`count`, no bytes).

## Pulling remaining 7 App Services (2026-09-15)

Same source/method as the Sales-only data above (`cloud-appservice-perf-report` skill, `PROD-{App}-AppServiceHTTPLogs` Graylog streams, raw `properties` export + local aggregation), same window (`2026-09-11T18:20:00.000Z`–`2026-09-15T14:00:00.000Z`, matching Sales' actual data cutoff) — Admin, Business, Catalog, Orders, Person, Platform, Pos. Stream IDs from `.claude/commands/cloud-appservice-perf-report.md`. Output per app: `data/<app>/httplogs_raw_export.csv` + `data/<app>/timetaken_by_path_aggregated.csv`. Functions and the external Loyalty host are **not** covered by this skill/stream table — still an open gap, not fabricated.

## Pos-PRO is not API traffic — confirmed 2026-09-15

User asked whether Pos-PRO's count is correct to include, or whether it's actually client-side (static asset) download traffic. Checked the pulled data directly (`data/pos/timetaken_by_path_aggregated.csv`, 9,926 requests over the same window, default path filter = versioned `/api/v<N>/...` routes only — static files/Kudu/SignalR negotiate excluded by the script's default, per the `cloud-appservice-perf-report` skill).

**Finding: it's neither business API traffic nor client-asset downloads — it's dominated by health-check polling.** 99.7% (9,899/9,926) is `/api/v1/Status/Health`. No `Sale/Create`, `CaeRequest`, or any business endpoint appears — confirms `docs/infrastructure.md`'s framing: Pos-PRO is the Blazor WASM static-content host + tenant-hostname entry point (`<tenant>.pos.smartfran.com`), not where business API calls land (those go to Sales/Business/Catalog/Person, already captured separately).

**Side finding, relevant to the WAF business case (not a tangent):** 15 hits total across `/api/v1/.env`, `/api/v2/.env`, `/api/v3/.env` (5 each) — external bot/scanner probes looking for exposed environment files, hitting the origin directly today with no WAF in front. Small volume, but a concrete example of exactly the exposure GITIN-1938's core justification (retail has no WAF protection today) describes.

**Real client-side download volume (WASM bundle/JS/CSS/manifest) is not yet captured** — the script's default filter excludes static files entirely; would need `--all-paths` on a Pos-PRO re-pull to see it. This *is* WAF-relevant (Front Door's Requests meter bills all edge-level requests, static or API), just a different traffic class from the dev's per-sale API model — should not be combined with it without re-pulling.

## Pull status — all 8 services complete (2026-09-15)

All 7 remaining apps finished on the second run. Per-app totals, same window (`2026-09-11T18:20Z`–`2026-09-15T14:00Z`, 91.667h), default path filter (versioned `/api/v<N>/...` only — excludes static assets/Kudu/SignalR negotiate):

| App | Total requests | req/h | Dominant endpoints |
|---|---|---|---|
| Admin | 21 | 0.2 | negligible — back-office portal, staff-driven, not POS-traffic-shaped |
| Business | 583,054 | 6,360.6 | `Oversale/GetLastUpdate` (168,756), `Stock/Create` (82,885), `Stock/ExistStockAddForSale` (81,163) |
| Catalog | 310,206 | 3,384.1 | `CostPriceList/GetItemsCosts/*` (28,020+24,800), `Items/GetCacheByIdAsync` (16,343) |
| Orders | 1,390,676 | 15,171.0 | `Queue/Heartbeat` (1,251,110 — 90% of Orders' own traffic) |
| Person | 36,967 | 403.3 | `LegalEntity/Get/{id}` (11,365), `PersonEntity/GetListByCode` (5,925) |
| Platform | 201,779 | 2,201.2 | `Integration/GetAfipTicketCached` (107,214), `UpdateAfipQrCached` (52,219) — AFIP e-invoicing |
| Pos | 9,926 | 108.3 | 99.7% `Status/Health` — see "Pos-PRO is not API traffic" above |
| Sales | 698,431 | 7,619.2 | `Sale/Create` (163,589), `Sale/Close` (162,416), `WsFeAr/CaeRequest` (106,708) |
| **Total** | **3,231,060** | **35,247.9** | |

**Heartbeat cross-check against the dev's email:** `Orders/Queue/Heartbeat` lands the dev's "heartbeat every 50s" at **68.24 req/franchise/h** measured — dev's email estimated 72/h per POS terminal. Close agreement (~5% off, plausibly explained by franchise vs. POS-terminal unit mismatch, already flagged) — real telemetry corroborates the dev's code-reading estimate for this one component.

**Discrepancy worth flagging, not yet reconciled:** the dev's email states cart additions (products/combos/optionals) resolve in-memory against a cached price list "without hitting any API." Real data shows Business-PRO's `Stock/ExistStockAddForSale` (81,163 hits) and `Oversale/GetLastUpdate` (168,756 hits) as its top two endpoints — high-volume, plausibly per-cart-item stock/oversale checks, which would contradict the "pure in-memory" description. Not confirmed either way (could be polling rather than per-item) — worth a direct question back to the dev rather than assuming.

## Layering real data onto the dev's email, per-endpoint (2026-09-15)

User asked whether real data adds anything to the dev's endpoint estimation. Checked the specific numbers against measured counts, using `Sale/Create` (163,589) as a proxy for total sales in the window — the dev's email was built by reading code, so real telemetry is complementary information, not a grading of that work:

| Dev's estimate | Measured | Note |
|---|---|---|
| `Sale/Create` ≈ `Sale/Close`, 1 each per sale | ratio 0.993 | Matches well |
| Heartbeat 72/h per POS terminal | 68.24/franchise/h | Close match (unit caveat already noted) |
| CaeRequest, 1x when FE(AR) active | ratio 0.65 vs `Sale/Create` | Consistent with a mixed fleet (FE-eligible/ineligible sales) — the dev's number was for one specific scenario, real traffic is a fleet average |
| **3x repeated favorites query, every sale reset** | `Favourites/Franchise/*` (Business-PRO) totals **3,400** hits fleet-wide in 91.67h — ratio to `Sale/Create` = **0.02** | Real traffic is much lower than the code path alone would suggest. Most likely explanation (not confirmed): a client-side cache intercepts repeat calls within a session, so the code fires 3x logically but only reaches the network once per some longer interval — worth asking the dev directly rather than assuming |
| Business-log write (1 of the "4 sale" requests) | not found on any of the 8 App Services' top paths | Located since via source as `RegisterBusinessLog` (Anonymous `[HttpTrigger]`) on `SFC-ScheduledJobs-PRO`, see "Function Apps identified" below. Still no request-volume data — Functions aren't covered by the `cloud-appservice-perf-report` skill/stream table |

**New data point, not from the dev's email:** `WsFePe/GeneratePending` (56,586) and `WsFePe/GetMaxAmountCustomerRequired` (51,501) run at 31-35% of `Sale/Create` volume — high for an endpoint whose name suggests Peru-specific e-invoicing (`Pe`), given the referer breakdown shows AR-dominant traffic (94.8% Grido + 2.7% Weiss, both `.ar` tenants). Either `WsFePe` isn't actually country-scoped the way its name implies, or something else explains the volume — not guessing further, flag for the dev.

**Bottom line: the dev's code-reading model and the real telemetry complement each other** — several components line up closely (heartbeat, create/close pairing), and the real measured combined rate (176.24 req/franchise/h, all 8 services) adds the parts that are hard to derive from code alone (favorites' real network frequency, background-traffic mix, WsFePe volume). The cost estimate uses the measured combined rate as its basis precisely because it already incorporates both sources.

**Combined rate, all 8 services, API routes only:** 176.24 req/franchise/hour.

**Linear scaling, PROD, Front Door Requests meter ($1.50/million, base tier):**

| Franchises | req/hour | req/month | Front Door Requests cost/mo |
|---|---|---|---|
| 1,500 | 264,359 | 192,982,332 | $289.47 |
| 2,000 | 352,479 | 257,309,776 | $385.96 |
| 2,600 | 458,223 | 334,502,708 | $501.75 |

Still excludes: static asset delivery (WASM bundle/JS/CSS, needs `--all-paths` on Pos-PRO), Azure Functions, external Loyalty host, and non-prod.

## H6 re-run attempt (2026-09-15) — cannot be resolved for this window

`FunctionAppLogs` field promotion (GITIN-2050, see `cloud/docs/graylog-log-fields.md`) went live 2026-09-15, after almost all of this ticket's measurement window (`2026-09-11T18:20Z`–`2026-09-15T14:00Z`) had already happened. Confirmed via two independent queries against the same historical window: 600,837 real `FunctionAppLogs` messages exist for `SFC-ScheduledJobs-PRO` in that window, but 0 of them have `FunctionName` populated — the promotion isn't retroactive, same pattern as the earlier `AppServiceHTTPLogs`/GITIN-2034 gap. **H6 stays an upper bound for this ticket's numbers** — the new capability only works for traffic from today onward, not for reproducing this specific estimate's window.

Not attempted: re-running H6 against a *current* (post-deploy) window and applying that ratio to the historical 155,145 total as a scaling assumption — would require explicitly flagging the assumption that today's RegisterBusinessLog-vs-timers ratio holds for the measured window too, not attempted without confirming that's wanted.

## Peak-hour traffic (2026-09-15) — the cost model uses average, not peak

All cost figures so far use the average confirmed rate (221.25 req/franchise/h). For capacity/CU sizing specifically, peak hour is what matters, not average. Measured from the hourly stacked dataset (8 App Services + 4 Function Apps, 92 buckets): peak hour was **130,040 req/h at 2026-09-13 19:20 UTC** (N=200, current) — **2.94x the average hourly rate** (44,250 req/h).

Scaled to 1,500/2,000/2,600 franchises using the same peak/average ratio (**projection, not a re-measurement at that scale**):

| Franchises | Avg req/h | Peak req/h (×2.94, projected) |
|---|---|---|
| 200 (measured) | 44,250 | 130,040 (measured) |
| 1,500 | 331,875 | 975,300 |
| 2,000 | 442,500 | 1,300,400 |
| 2,600 | 575,250 | 1,690,520 |

**Cost implication:** Front Door's Requests meter bills on actual requests regardless of when they land, so the average-based cost figures already presented are correct regardless of peak shape. Application Gateway's Capacity Units, by contrast, need to be provisioned for peak load — the CU range presented earlier (based on the average rate) likely understates what AppGW would need to provision for the peak hour specifically. Not recomputed against peak here — flagged as a real gap in the AppGW numbers, not resolved.

## Warning — heartbeat is a self-inflicted cost, not sales-driven demand

`Orders/Queue/Heartbeat` alone is **38.7% of all measured API traffic** (1,251,110 of 3,231,060 requests) — larger than Sales' entire endpoint set (Create+Close+CaeRequest combined). It carries zero business value per call (no sale, no customer interaction) — it exists purely to keep an open-but-idle POS terminal's connection alive, currently implemented as a discrete HTTP request every 50s.

**Dollar impact, Front Door Requests meter alone:**

| Franchises | Heartbeat cost/mo | Total Requests cost/mo | Heartbeat's share |
|---|---|---|---|
| 1,500 | $112.09 | $289.47 | 38.7% |
| 2,000 | $149.45 | $385.96 | 38.7% |
| 2,600 | $194.29 | $501.75 | 38.7% |

This directly confirms — with real measured numbers, not the dev's code-reading estimate — the concern the dev already flagged in their email ("cerca del 30% del tráfico no depende del volumen de negocio... Claramente esto lo tenemos que resolver previa adopción del WAF"). The real figure (38.7%) is higher than their own ballpark (30%).

**Why this matters beyond the Requests-meter dollar figure:**
- It's flat, 24/7, independent of store hours or sales volume — every open-but-idle register pays this whether or not the store made a single sale that hour.
- On **Application Gateway WAF_v2** specifically, this is worse than the Front Door number suggests: CU-based billing scales off continuous throughput/connection rate, so a constant background hum never lets billed capacity drop, even overnight with zero sales — heartbeat traffic keeps the CU floor elevated around the clock, not just adding a flat per-request line item.
- Fixing this (lower frequency, batching, or reusing the SignalR WebSocket already open per POS session for a lightweight ping instead of a separate HTTP round-trip) is cheaper than paying a WAF to shield the current design, and the saving scales with the same franchise-count multiplier as the cost itself — this is worth raising as a recommendation alongside the estimate, not just a footnote.

## Function Apps identified (2026-09-15, user pasted Azure Portal listing)

Fills part of the "Functions not covered" gap noted above — resolves *which* Function Apps exist, not yet their request volume. All 4 are Linux Function Apps sharing **one** App Service Plan (`P0v3`, 1 instance, RG `SmartFran.Cloud.PRO`): `SFC-CodeGenerator-PRO`, `SFC-PosWasmRelay-PRO` (log relay — already known live from the OOM investigation), `SFC-ScheduledJobs-PRO`, `SFC-TicketProcess-PRO`. `cloud/docs/infrastructure.md` corrected — previously documented 3 Function Apps under an entirely different, stale naming convention (`SmartFranCloudBusinessFunPro`, `SmartFranCloudTicketProcessAsync-pro`, `SmartFranCloudFunctionsScheduledJobs-pro`), source/date unknown.

Sharing one small (`P0v3`, 1 instance) plan across all 4 suggests lower aggregate load than the 8 main App Services (each on its own dedicated plan) — a plausible signal, not a measurement.

**Resolved via source (2026-09-15, `cloud/repo/SmartFran.Cloud`, `dev` branch) — user's hypothesis that Function Apps expose no APIs (batch-only) is contradicted.** Checked trigger attributes directly:

| Function App | Source project | Endpoints | Auth level | POS-facing? |
|---|---|---|---|---|
| `SFC-CodeGenerator-PRO` | `SmartFran.Cloud.Functions.Business.CodeGenerator.LiteEdition(V2)` | **All 8 are `[HttpTrigger]`**, no timers at all | Anonymous (7), Function-key (1: `SetNextCodeAsync`) | **Yes** — matches the `SFC.CodeGeneratorFunction` HttpClient already documented as called by `Pos.Wasm`/`Business.API`/`Catalog.API`/`Sales.API` |
| `SFC-ScheduledJobs-PRO` | `SmartFran.Cloud.Functions.ScheduledJobs` | Mixed: 4 `[TimerTrigger]` (StockConsistency, Reconciliation, SynchronizeReasonsReject, **FavoritesRanking**) + 5 `[HttpTrigger]` (`RegisterBusinessLog`, `processlog/register`, `processlog/health`, StockConsistency-manual, Reconciliation-manual) | Anonymous (`RegisterBusinessLog`, `processlog/*`, SynchronizeReasonsReject-manual); Function-key (StockConsistency-manual) | **`RegisterBusinessLog` (Anonymous POST) is the dev's "business-log write"** — resolves the earlier "not located" gap. Other HTTP endpoints here read like ops/manual-trigger, not POS traffic |
| `SFC-TicketProcess-PRO` | `SmartFran.Cloud.Functions.Sales.TicketProcessAsync` | 1 `[TimerTrigger]` (every 30 min) + 1 `[HttpTrigger]` (`RunManual`, Anonymous) | mostly batch | Primarily scheduled; the HTTP endpoint looks like a manual/ops trigger, not confirmed as POS-facing |
| `SFC-PosWasmRelay-PRO` | `SmartFran.Cloud.Pos.Wasm.Relay` | 1 `[HttpTrigger]` (`internal/log-ingest`) | Anonymous | **Yes** — already known live (log relay) |

**Notable side finding:** `FavoritesRankingTimerTrigger` (scheduled, not per-request) is a strong candidate explanation for the favorites traffic being much lower than the code path alone suggests — if the ranking is precomputed on a schedule and the POS just reads the cached result, that would explain why the 3 network calls the code describes rarely reach the network. Not confirmed as *the* explanation, but consistent with the measured near-zero request volume — worth raising with the dev alongside that observation.

## Application Gateway WAF_v2 — Capacity Unit (CU) model (2026-09-15)

**Fixed Cost — confirmed, solid.** $0.36/hour × 730h/month = **$262.80/month per gateway deployment**. ×2 environments (PROD + non-prod, per GITIN-1938's confirmed requirement) = **$525.60/month**, before any CU consumption. This is the dominant, deterministic part of AppGW's total cost at the traffic volumes measured here (see below).

**Variable CU cost — cannot be precisely computed from the data gathered so far, and this is a real finding, not just a gap.** Azure's own CU model is `CU = max(Compute Units, Persistent Connection Units, Throughput Units)`, each independently metered:

- **Throughput Units** (1 CU ≈ 2.22 Mbps): needs average request/response payload size in bytes. Not available — the Graylog exports only carry `avg_ms`/`max_ms`/`count`, no byte sizes (already flagged earlier in this file).
- **Persistent Connection Units** (1 CU ≈ 2,500 concurrent connections): **resolved as effectively N/A for this design** — `cloud/docs/infrastructure.md` confirms a dedicated `SmartFran-Cloud-SignalR-PRO` resource exists (Azure SignalR Service, managed). This means the dev's "1 persistent WebSocket per hub" traffic connects **directly to the SignalR Service, bypassing Application Gateway entirely** — only the initial `negotiate` HTTP call (1 per hub per session, low volume) would ever touch a WAF sitting in front of the App Services. AppGW's persistent-connection load is therefore just ordinary HTTP client connections, not the SignalR fleet.
- **Compute Units**: no published Microsoft formula ties this to request count — it depends on TLS negotiation cost and WAF managed-rule evaluation overhead, both workload-specific. Microsoft's own guidance is to measure this empirically (the `CapacityUnits`/`ComputeUnits` Azure Monitor metrics on a **running** gateway), not calculate it in advance. There is no AppGW deployed today (GITIN-1938 confirmed WAF doesn't exist yet) — so there's nothing to measure from, a genuine chicken-and-egg gap, not something more data-gathering here would resolve.

**Two separate WAF deployments, not one shared instance:** PROD and non-prod are two distinct WAF_v2 gateways in two different subscriptions (non-prod under Smart IT - Grido, per `cloud/docs/infrastructure.md`) — the Fixed Cost ×2 above reflects two real, separately-running gateways, not a single gateway billed twice.

**Correction (2026-09-15) — the CU/variable cost below is PROD-only, not ×2.** An earlier pass in this file doubled the CU cost the same way as the Fixed Cost, which overstates it: non-prod (DEV/DEV2/STG/TEST/POC) doesn't carry real franchise-scale traffic, so its CU consumption is not meaningfully modeled by doubling PROD's. Front Door's Requests-meter cost was never doubled for the same reason — this fixes AppGW to match that same treatment (fixed cost ×2 for two real deployments, variable/request cost ×1 off the PROD-measured rate only).

**Rough order-of-magnitude bracket, explicitly unofficial** (a commonly-cited but not Microsoft-published planning heuristic: ~10-30 requests/sec per Compute Unit for a typical WAF_v2 listener) — given only to bound expectations, not as a number to quote with confidence:

| Franchises | Avg req/sec (confirmed rate, 221.25/franchise/h, PROD only) | CU range | CU cost/mo (PROD only, ×1) | **Total AppGW/mo (Fixed ×2 + CU ×1)** |
|---|---|---|---|---|
| 1,500 | 92.2 | 3.1–9.2 | $18–$54 | **$544–$579** |
| 2,000 | 122.9 | 4.1–12.3 | $24–$72 | **$550–$597** |
| 2,600 | 159.8 | 5.3–16.0 | $31–$93 | **$557–$619** |

**Fixed Cost dominates the total regardless of the CU uncertainty** — even at the pessimistic end, CU consumption is a modest fraction (~15-25%) of AppGW's total at these traffic volumes. That conclusion is robust even though the exact CU number isn't.

**Correction needed for a fair comparison against Front Door:** every Front Door number presented earlier in this file was the **Requests meter only** — it does **not** include Front Door's own $330/month base fee ×2 environments = $660/month. Front Door's true total needs that added before comparing side-by-side against AppGW's Fixed+CU total above.

## Final cost comparison (corrected, both products) and pros/cons

Rate: 221.25 req/franchise/h (confirmed — 8 App Services + `CodeGenerator` + `PosWasmRelay`, excludes ScheduledJobs' unresolved split, static assets, external Loyalty host, `TicketProcess`).

Split by environment, since PROD and non-prod have different cost profiles (PROD's variable cost grows with franchise count; non-prod is fixed-only, no real franchise traffic to drive a variable component):

**PROD** (fixed + variable):

| Franchises | req/month (PROD) | Front Door/mo | App Gateway/mo |
|---|---|---|---|
| 200 (current) | 32.3M | $378.45 | $265.19–$269.98 |
| 1,500 | 242.3M | $693.40 | $280.75–$316.64 |
| 2,000 | 323.0M | $814.54 | $286.73–$334.58 |
| 2,600 | 419.9M | $959.90 | $293.91–$356.12 |

**Non-prod** (fixed only — flat regardless of franchise scenario):

| | Front Door/mo | App Gateway/mo |
|---|---|---|
| DEV/STG/TEST | $330.00 | $262.80 |

**Total (PROD + non-prod)**:

| Franchises | req/month (PROD) | Front Door total/mo | App Gateway total/mo |
|---|---|---|---|
| 200 (current) | 32.3M | $708.45 | $527.99–$532.78 |
| 1,500 | 242.3M | $1,023.40 | $543.55–$579.44 |
| 2,000 | 323.0M | $1,144.54 | $549.53–$597.38 |
| 2,600 | 419.9M | $1,289.90 | $556.71–$618.92 |

**Finding: Application Gateway is cheaper than Front Door at every measured scenario**, driven mainly by Front Door's $660/mo fixed base fee (2 environments) outweighing its per-request savings at this traffic volume. Not a clean win either way, though — see below.

**Azure Front Door Premium**
- Pros: native multi-origin support — matches the dev's "single front door over separate per-service hostnames" design note with no extra config; WAF (managed + custom rules) included at no additional charge; edge caching benefits static asset delivery (WASM bundle/JS/CSS), which AppGW cannot do at all (pure L7 proxy, no CDN layer); fully transparent, precisely computable pricing (fixed + $/request + $/GB) — no estimation uncertainty.
- Cons: higher total cost at every scenario measured, mainly the fixed base fee; global/DNS-based routing model, less directly integrated with the existing VNet-based Azure setup than AppGW.

**Application Gateway WAF_v2**
- Pros: cheaper at every scenario measured (confirmed real pricing); native VNet integration, fits directly into the existing regional (`eastus2`) Azure network model with no separate global layer to reason about; known technology in the org, already running in production for SmartLoyalty (`WAF_APPs`) — not a new product to learn from scratch.
- Cons: **fronting 8 App Services + Functions on one instance is more scale than we've validated** — real precedent exists in the org (SmartLoyalty's `WAF_APPs`, `DefaultGroup01`, already runs Application Gateway WAF_v2 in production with multi-site listeners fronting multiple backend pools — `Back_ClubSite`, `Back_ClubSite_PY`, `Back_WebSite`, confirmed 2026-07-21 via `loyalty/docs/infrastructure.md` and the `loyalty-azure-waf` skill), so the pattern itself is proven, just at a much smaller scale (3 listeners/2 services) than Cloud's 8+Functions; no CDN/edge caching for static assets; **variable CU cost is not reliably estimable in advance** — Microsoft's own guidance is empirical measurement on a live gateway. `WAF_APPs` is exactly that: a live production WAF_v2 gateway in the same tenant whose `CapacityUnits`/`ComputeUnits` Azure Monitor metrics could replace the unofficial 10-30 req/sec/CU guess with a real number, without standing up a pilot — not pulled yet, offered to the user, not done unprompted; regional only, no global points-of-presence.

## Function App real volume — pulled via Azure Monitor (2026-09-15)

Same window as the App Service pulls (`2026-09-11T18:20Z`–`2026-09-15T14:00Z`, 91.667h). Function Apps are regular `Microsoft.Web/sites` resources — no Graylog plumbing needed, pulled `FunctionExecutionCount` (Total, PT1H) directly via `az monitor metrics`, same mechanism already used for App Service Plan CPU/RAM.

| Function App | Total executions | req/h | Note |
|---|---|---|---|
| `SFC-CodeGenerator-PRO` | 112,951 | 1,232.2 | 100% HTTP-triggered (confirmed via source) — safe to treat as WAF-relevant traffic at face value |
| `SFC-PosWasmRelay-PRO` | 712,172 | 7,769.1 | 100% HTTP-triggered (single endpoint, log relay) — safe at face value |
| `SFC-TicketProcess-PRO` | 183 | 2.0 | **Sanity check: matches 91.667h / 0.5h = 183.3 expected TimerTrigger runs almost exactly** — confirms ~0 real external HTTP traffic in this window despite having an HTTP endpoint on paper |
| `SFC-ScheduledJobs-PRO` | 155,145 | 1,692.5 | **Mixed — this metric can't be split.** Combines the real POS-facing `RegisterBusinessLog`/`processlog/*` (Anonymous HTTP) with 4 internal `[TimerTrigger]` jobs (StockConsistency/Reconciliation/SynchronizeReasonsReject/FavoritesRanking) that never traverse a WAF at all (invoked internally by the Functions runtime, no external URL). Treat as an **upper bound**, not a confirmed WAF-relevant figure — actual HTTP share is smaller, degree unknown without pulling the timer schedule App Settings to estimate each job's expected run count and subtract it out (not done yet). |

**Updated combined confirmed rate:** 176.24 (8 App Services) + 45.01 (CodeGenerator + PosWasmRelay, both 100% HTTP) = **221.25 req/franchise/h**. Adding ScheduledJobs' full total as a ceiling would push this to 229.71 — the true number sits somewhere between, closer to the low end since 3 of its 4 background jobs are almost certainly low-frequency (`SynchronizeReasonsReject` is a fixed once/weekday cron, ~2 runs expected in this window).

**Linear scaling, PROD, Front Door Requests meter (confirmed rate, 221.25 req/franchise/h, excludes ScheduledJobs' unresolved HTTP/timer split):**

| Franchises | req/month | Front Door Requests cost/mo |
|---|---|---|
| 1,500 | 242.3M | $363.40 |
| 2,000 | 323.0M | $484.53 |
| 2,600 | 419.9M | $629.89 |

Still excludes: `SFC-TicketProcess-PRO`'s HTTP manual-run (near-zero, already established), static asset delivery (needs `--all-paths` Pos-PRO re-pull), the external Loyalty host, and non-prod.

## Open questions / blocking this estimate

1. **Active POS terminal count in production** (fleet size, ideally per tenant) — hard blocker, total volume scales directly off this. Not documented anywhere in this repo.
2. **Average operating hours/day the fleet is open** (or equivalent: average concurrently-open POS-hours/month across the fleet) — needed to turn per-POS-hour rates into a monthly total.
3. **Average log-relay POST rate**, not just the dev's stated ceiling — biggest single lever on the final number.
4. Whether a per-tenant or aggregate breakdown is wanted in the final ticket/email output.

## Ruled out

(none yet)

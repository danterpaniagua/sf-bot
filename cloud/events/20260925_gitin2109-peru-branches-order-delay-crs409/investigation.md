# Investigation — 20260925_gitin2109-peru-branches-order-delay-crs409

**Jira ticket:** [GITIN-2109](https://smartit-ar.atlassian.net/browse/GITIN-2109)

**Reported via:** WhatsApp channel (Sol Fernandez), 2026-09-25, ~16:47-16:49.

**Opened as a separate event from GITIN-2084** (`cloud/events/20260919_grido-order-delay-peru-5396-5481/`) per explicit user decision, despite branch/symptom overlap — do not assume same root cause without independent confirmation.

## Reported symptoms (raw, translated context added in brackets, original Spanish preserved for exact wording)

1. Recurring error with PedidosYa (Peya): a delay surcharge is charged even when the order is already prepared in-store. When trying to mark the order "ready," error **`CRS: 409`** appears. Franchise **5470**.
2. Separate complaint: orders take too long to "integrate into the system," causing courier problems — the order only enters "the system" after the courier has already arrived at the store. No franchise given for this specific line (appears in the same message batch as #1, franchise 5470 named once for the group).
3. Separate report of claims from Peru branches, "apparently an integration issue" — branches **5470** and **5424** specifically flagged for review, not confirmed whether isolated or general.

## Prior-art check (branch/symptom overlap, not yet confirmed as same mechanism)

- Branches **5470** and **5424** are both among the 35 confirmed Peru/Grido `cloud: true` branches identified in GITIN-2068's investigation (`smartpedidos/events/20260917_smartcloud-peru-orders-pending/data/mongo_peru_orders.txt:317`).
- Branch **5470** specifically already appeared twice in the confirmed-stuck-order list pulled 2026-09-17 (`smartpedidos/events/20260917_smartcloud-peru-orders-pending/data/mongo_peru_currently_stuck.txt:128,135`).
- `GITIN-2084` (`cloud/events/20260919_grido-order-delay-peru-5396-5481/investigation.md`) is an open, not-marked-converged investigation into a recurring, systemic (branch-agnostic per that file's synthesis) SQS-to-POS delay on Peru branches 5396/5481/5523, last updated 2026-09-20. Root cause there was still unresolved as of that date, with a correlated-but-unconfirmed lead pointing at `SmartFran-Cloud-Sales-Plan-PRO` CPU saturation / an HTTP-timeout cascade.
- `GITIN-2068` (fixed ~16:10 ART 2026-09-17): a `TimeZoneNotFoundException` in `MessageProcessor.SetTimeZones` (Orders API SQS consumer) for any country outside a 4-entry dictionary — Peru was affected. Fix deployed and user-confirmed same day, **not independently re-verified since**.
- `CRS: 409` has no hits in either `smartpedidos/repo` or `cloud/repo/SmartFran.Cloud/Source/Services/Orders` — not an internal error code as far as source shows. Working hypothesis, **not confirmed**: this is PedidosYa's own API error code, surfaced when the POS tries to confirm "ready" after a state/timing mismatch — which would make it a downstream symptom of the same order-delay class documented in GITIN-2068/2084, not a separate bug. Alternative possibility: unrelated to the delay entirely (e.g. a genuine integration/auth conflict on the "ready" endpoint specific to PedidosYa).

## Open questions

1. Is franchise 5470's `CRS: 409` symptom mechanistically connected to the "orders slow to integrate" complaint (same batch, same franchise), or coincidental?
2. Are 5470/5424 currently showing the same `ApproximateAgeOfOldestMessage` delay signature found on 5396/5481/5523 in GITIN-2084?
3. What does `CRS: 409` actually mean — need either a screenshot/raw response from the POS or PedidosYa API documentation confirming the code.
4. Original technical ask this event grew out of: **time elapsed between an order being pushed to the branch's SQS queue (SmartPedidos/`platforms-service`) and that same order landing in SmartCloud's Orders API / Cosmos** (`MessageProcessor.PollOnceAsync` consumer, per `cloud/docs/infrastructure.md` → "SmartPedidos Bridge") — this is the direct latency metric needed to confirm or rule out the "arrives after the courier" complaint. Not yet computed for any specific order.

## Real data, 2026-09-25 — SmartPedidos `orders.timestamp` vs. Cosmos `orders.createdAt`, 87 orders

Dev-provided Cosmos `orders` query (`OrderId`, `createdAt`, `branchId` — 87 rows, window 16:05:41–20:11:04 UTC, all 35-branch Peru/Grido fleet, not filtered to any specific complaint) — `data/cosmos_orders_createdAt_20260925.csv`. Joined against SmartPedidos' `orders.originalId` (confirmed field: platform-native order code, set in `smartpedidos/repo/.../platforms/interfaces/{pedidosYa,rappi,mercadoPago}.js` and `platform/uberEats.js`) via `mongo_orders_by_originalid.js` — **87/87 matched**, output `data/mongo_orders_by_originalid_20260925.txt`. Delta computed as `cosmos.createdAt - mongo.timestamp`, full join in `data/sqs_to_cosmos_latency_20260925.csv`.

**Caveat, not fully resolved:** `orders.timestamp`/`createdAt` on the SmartPedidos side is order-receipt/persist time in `platforms-service`, not a confirmed exact "pushed to SQS" instant — treated here as the closest available proxy, per the architecture (`pushNewToQueue` follows shortly after `saveNewOrders`). The true delta could run slightly higher if there's meaningful time between persist and actual SQS `SendMessage`, not measured here.

**Result: this specific leg (SmartPedidos persist → SmartCloud Cosmos arrival) is fast for all 87 sampled orders today.** Min 0.019s, median 0.055s, p90 12.1s, p95 16.8s, max 62.0s (single outlier, branch 5522, order `2298474926`, `PedidosYa`). Zero negative deltas (Cosmos always after Mongo, as causally expected).

**Branches 5470 and 5424 specifically** (11 orders total in this sample, spanning 16:05–20:02 UTC — covers the ~19:47-19:49 UTC WhatsApp report window): max delta **20.1s** (`2298291181`, branch 5470, PedidosYa), next highest 16.1s (`2298195497`, branch 5424, PedidosYa), everything else sub-5s, most Rappi orders on these two branches sub-100ms. **No order on either branch shows anything close to a multi-minute delay in this window.**

**What this does and doesn't tell us:**
- **Doesn't support** "the SQS→Cosmos bridge itself is slow" as the mechanism behind "recién entra el pedido cuando el repartidor ya llegó al local" — a courier already at the store implies a delay of many minutes, not the ≤20s seen here for these branches today.
- **Doesn't rule out** the complaint either: this is an unfiltered recent-orders sample, not selected for being the specific delayed order(s) Sol Fernandez referenced — the actual problem order(s) may not be in this 87-row window at all (wrong day/time, or already excluded if e.g. the delay causes a document to never reach Cosmos rather than reach it late).
- **Shifts the leading hypothesis downstream**, similar in spirit to GITIN-2084's pivot away from the SQS/Orders-API leg: if a real multi-minute delay exists for these branches, this data points toward it living **after** Cosmos — i.e. between the Orders API/Cosmos write and the order actually appearing on the branch's POS terminal — rather than in the AWS SQS→Azure ingestion leg. Not yet checked at all.
- Says nothing about `CRS: 409` — separate mechanism, not addressed by this leg's timing.

## Not yet done

- Get a **specific** affected order (id, branch, approximate time) directly from Sol Fernandez / the branch — needed to test the actual complaint rather than an unfiltered sample.
- If a specific order is obtained: trace it past Cosmos — POS terminal delivery mechanism (per `cloud/docs/infrastructure.md` → "SmartPedidos Bridge," check both the direct SQS `MessageProcessor` path and the separate `/api/v1/Queue/Heartbeat` pull path, precedence between them still an open question in that doc) — to see where the actual multi-minute gap (if any) occurs.
- Pull `ApproximateAgeOfOldestMessage` (CloudWatch, AWS SQS) for branches 5470 and 5424 over a wider window, same pattern as GITIN-2084's 5396/5481/5523 pull, to check for intermittent spikes outside today's 87-order sample.
- Confirm with user whether `CRS: 409` is reproducible/ongoing right now or an intermittent report; get a raw screenshot or API response showing the actual error if possible.

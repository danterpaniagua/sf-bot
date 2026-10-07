# Investigation — 20260917_smartcloud-peru-orders-pending

**Jira:** [GITIN-2068](https://smartit-ar.atlassian.net/browse/GITIN-2068)

**Cross-project:** this incident spans SmartPedidos (this file) and SmartCloud (`cloud/events/20260917_smartpedidos-peru-orders-pending/investigation.md`) — both sides track their own work here; check both when resuming, don't duplicate findings across them.

## Reported symptom

SmartCloud is not receiving orders from SmartPedidos. Narrowed: orders from Peru specifically are stuck in "Pending" status.

## Architecture context

Per `smartpedidos/CLAUDE.md`: `platforms-service` receives orders from delivery platforms, persists to MongoDB, pushes accepted orders to **AWS SQS**, routed to branch POS terminals via SmartCloud. **The exact bridge mechanism from SmartPedidos' SQS to SmartCloud's Azure-side ingestion is not yet documented in either project** — needs to be established, not assumed, before diagnosing further.

## Open questions — still waiting on answers (asked 2026-09-17, not yet answered)

1. Where exactly is "Pending" observed (SmartCloud UI, POS terminal, a SmartPedidos-side status)?
2. Peru-only, or first-noticed instance of a broader issue?
3. Is Peru newly onboarded, or previously working?
4. When did this start?
5. Any alert already fired (SQS DLQ, CloudWatch, Azure Monitor, Zabbix)?

## Real data, 2026-09-17 — 35 Peru branches found, all Grido, all `cloud: true`

`branches.address.country` matches `Perú` (accented) for 35 branches, all in Lima/Callao, all Grido-named, all with `cloud: true` (routed through SmartCloud). Full list + branchIds in `data/mongo_peru_orders.txt`.

**Order state distribution, these 35 branches, last 7 days:** DELIVERED 2851, REJECTED 39, PENDING 26, `null` (no state field) 16, READY 4, CONFIRMED 2. Out of ~2938 total orders, PENDING is a small fraction — the most recent 20 orders sample shows all `PENDING` ones are minutes old (normal in-flight, not necessarily "stuck").

### Confirmed root cause candidate: Rappi orders never get `state` set at all (source-confirmed, not just inferred from data)

The most recent-20 sample shows every `PedidosYa`/`PediGrido` order has `state: 'PENDING'`, but **every `Rappi` order has no `state` field at all** (not `null` in the doc — the key is simply absent, which is exactly the `_id: null` bucket, 16 hits/7d, in the aggregation above).

Traced and confirmed in `smartpedidos/repo/dev-scr-smartPedidos-platformsService`:

- The shared `Platform.saveNewOrders()` (`api/src/platforms/management/platform.js:825-835`) builds the Mongo `orders` document as `orderCreator = { ..., state: order.state, ... }` — it copies `state` from the incoming `order` object **as already set by the caller**. It does *not* derive it from the `stateCod` local variable (`'pend'`/`'rej'`) it computes two lines earlier (line 810) — that variable is only ever passed on to `newsFromOrders(...)` for the separate `news` collection, never back into the persisted `orders.state` field. This looks like a real gap in the shared function, not platform-specific by design.
- **Webhook-based platforms stamp `order.state = "PENDING"` themselves, in their controller, before the order ever reaches `saveNewOrders`:** confirmed for `mercadoPago.js:115`, `uberEats.js:88`, `peya.js:51` (`order.state = "PENDING"` / `req.body.state = "PENDING"`).
- **Rappi has no equivalent controller step** — `api/src/controllers/rappi.js` has no `.state =` assignment anywhere (confirmed via grep). Rappi doesn't even use a webhook path: `Rappi.getOrders()` (`api/src/platforms/management/platform/rappi.js:174-200`) **polls** Rappi's own API directly (`axios.get`) and passes the raw response object straight into `this.saveNewOrders(data, this._platform)` — `Rappi extends Platform` and does not override `saveNewOrders`, so it's the exact same shared function above, just fed an `order` object that never had `.state` set by anything upstream.
- **Net effect, confirmed against real data:** every Rappi order for these 35 Peru branches is persisted with **no `state` field**, not `"PENDING"` — a different, more silent failure mode than the reported "stuck in Pending" wording, but very plausibly what a dashboard/report reads as broken/blank status for Rappi orders specifically.

**Not yet confirmed:**
- Whether this is Peru-specific or a **global Rappi-integration bug** unrelated to country — nothing in the traced code path branches on country/tenant. Worth checking Rappi order state for non-Peru (e.g. Argentina) branches to see if the same gap exists there too, which would mean "Peru" is coincidental (maybe Peru just has more/newer Rappi-integrated branches) rather than causal.
- Whether any of the 26 literal `PENDING` (not missing-state) orders are actually *aged/stuck*, vs. just normal recent in-flight orders — the top-20 sample only shows recent ones. A separate query filtering `state: 'PENDING' AND timestamp < now-1h` for these branchIds would confirm or rule out a second, distinct "genuinely stuck" symptom.
- Whether "missing `state`" on the `orders` collection doc actually blocks the order from being routed/displayed correctly downstream (in `news`, in SmartCloud) — `newsFromOrders` uses the separately-computed `stateCod` variable, not the `orders.state` field, so the `news` collection (which drives POS terminal delivery) may be unaffected by this specific gap. Needs tracing `newsFromOrders`/the `news` document for a real Rappi order to confirm whether the customer-facing symptom (order not reaching the branch) is actually caused by this, or whether this is a separate, cosmetic/reporting-only gap.

## Real data, 2026-09-17 — live snapshot, all 35 Peru branches, any platform

User reported "all Peru [orders] are stuck" — checked directly against a live snapshot (not the 7-day historical aggregate above). Total orders, all Peru branches, last 24h: 349. Currently open (PENDING or missing `state`): 48. Full detail in `data/mongo_peru_currently_stuck.txt`.

These 48 split cleanly into two groups with a hard gap between them — nothing between 1h45m and 2.8 days old:

- **36 orders, all <2h old** — most likely normal in-flight orders not yet confirmed, not evidence of "stuck."
- **12 orders, 2.8–13.7 days old — genuinely stuck.** Spread across all three platforms: PedidosYa (6), Rappi (4), PediGrido (2).

**This changes the leading hypothesis.** The 6 PedidosYa/PediGrido orders in the stuck-12 all have `state: 'PENDING'` set correctly (per the controller-level `order.state = "PENDING"` stamp confirmed earlier) and are *still* stuck for 5-14 days — so whatever is actually causing "stuck" orders is **downstream of the initial state-setting step, and platform-agnostic**, not the Rappi missing-`state` gap found earlier. That gap is very likely a separate, more cosmetic issue (most Rappi orders in the 7-day aggregate still reach DELIVERED despite lacking `state`) — real, but probably not the reported symptom.

**Correction to the earlier claim "all Peru stuck":** not literally true — 337 of 349 orders (24h) are not stuck; the real rate is ~12 stuck orders accumulated over roughly 14 days, well under 1/day out of ~349/day volume. Still a real, reproducible bug — just far narrower than "all."

**Next step:** pull full identifiers (`_id`, `originalId`, `order.id`, `internalCode`) for these 12 specific stuck orders (script `mongo_peru_stuck_ids.js`, not yet run) and trace at least one of them directly against the SmartCloud Orders API / Graylog (`cloud/events/20260917_smartpedidos-peru-orders-pending/`) to see whether it ever reached the AWS SQS bridge at all, or arrived and failed there. A targeted trace on a real stuck order ID will be far more conclusive than either side's aggregate/hypothesis-driven checks so far.

## Real data, 2026-09-17 — baseline: normal time-to-state-change vs. the 12 stuck orders

Requested to quantify how anomalous the stuck orders really are. For 2891 Peru orders (all 35 branches, last 7 days) that *did* move off `PENDING`, time from creation to last update (`updatedAt - timestamp`, a proxy for time-to-last-state-change since the `orders` collection only stores current state, not full history):

- Overall: median **3.8 min**, p90 **12.8 min**, p95 **19.6 min**, p99 **90.7 min**, max **2817 min (~47h, a single slow `REJECTED` case)**.
- By final state: `DELIVERED` (2836/2891, the overwhelming majority) median 3.8 min, p95 18.2 min. `REJECTED` (43) median 7.7 min but p95 1052 min (~17.5h) — the one genuinely slow legitimate outlier lives here.
- By platform: Rappi/PedidosYa both median ~3.5-3.9 min; PediGrido slightly slower (median 11.4 min, p95 115.7 min) but still well under a day.

**The 12 genuinely-stuck orders (2.8-13.7 days) exceed the overall p99 by roughly 4,000x to 20,000x**, and exceed even the single slowest normal case observed in 7 days (~47h) by a factor of ~1.4x to ~7x. This is a clean, quantified anomaly — not a matter of "some orders are just slow," these are categorically different from anything that completes normally.

## Real data, 2026-09-17 (post-swap) — exhaustive re-check, no age cutoff, and monitoring status

Re-ran the stuck-orders query with no age cutoff at all (earlier list used a >24h-old filter) to confirm the 12-order count is genuinely complete, not a boundary artifact — result: **identical 12 orders, same IDs**. Confirms the list is exhaustive as of this check. Full detail: `data/mongo_peru_all_blocked_orders.csv`.

**No new stuck order has appeared yet since the swap (16:13 ART).** The youngest entry is still the 2026-09-14 one (~2.97 days old at check time). Given the swap is confirmed to have made the underlying bug deterministic going forward, this most likely means insufficient new Peru order volume has come through since 16:13 to produce a fresh casualty yet — not that the bug is inactive. **Do not read this as the issue having stopped** — re-run this same no-cutoff query periodically to catch the first post-swap casualty, which would be the strongest possible confirmation (or, if it never appears despite real volume, a reason to revisit the deterministic-failure theory).

## Not yet done

- Confirm whether the missing-`state` Rappi gap is Peru-specific or global (query non-Peru branches' Rappi order states).
- Check for genuinely aged/stuck `PENDING` orders (not just recently-created ones) among these 35 branches.
- Trace one real Rappi order's `news` document end-to-end to confirm whether the missing `orders.state` field actually blocks delivery to the branch POS terminal, or is a separate/cosmetic gap from the reported symptom.
- Still waiting on open questions 2-6 above (where exactly "Pending" is observed, whether Peru is the only country affected, onboarding history, start time, prior alerts) to confirm this is even the same issue the reporter meant.

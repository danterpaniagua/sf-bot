# Investigation — 20260908_gitin2013-query-insights-slow-queries

**Jira:** [GITIN-2013](https://smartit-ar.atlassian.net/browse/GITIN-2013), parent [GITIN-1857](https://smartit-ar.atlassian.net/browse/GITIN-1857) — same parent epic as [GITIN-2006](https://smartit-ar.atlassian.net/browse/GITIN-2006) (index review) and [GITIN-2011](https://smartit-ar.atlassian.net/browse/GITIN-2011) (Jenkins `ope` scope). **Related: [GITIN-2062](https://smartit-ar.atlassian.net/browse/GITIN-2062)** ("[SP] Índice en smartfran.branches") — tracks the `branches` index work (Rappi pattern applied 2026-09-17, Uber pattern still pending) surfaced during this investigation.

## Purpose

Atlas **Query Insights** (the query-level slow-query profiler, distinct from Performance Advisor's Unused/Create Indexes panels already used in GITIN-2006) is reporting slow queries on the `PedidosSmartfran` cluster. Investigate which queries, on which collections, and whether they're addressed by — or independent of — the index work already done in GITIN-2006.

## Confirmed facts

- Cluster is the same one covered in GITIN-2006/GITIN-1744: `PedidosSmartfran`, MongoDB Atlas, `us-east-1`, database `smartfran`.
- GITIN-2006 already surfaced one candidate overlap: the `ordertimes` latency-metrics query (6-field `latencyTimestamp.*` compound) had an avg execution time of 2778 ms as of the 2026-09-08 Atlas Advisor pull — worsening across all 3 pulls (393 ms → 2778 ms). If Query Insights is flagging the same query, that's not a new finding, it's the same one already tracked (index now applied 2026-09-08 in GITIN-2006 — worth checking whether Query Insights shows improvement post-application, or whether these are different queries entirely).
- **No mongosh route to slow-query data with the current account (2026-09-08, `data/slow-queries-20260908.txt`).** `getProfilingStatus()`, `system.profile` reads, and `currentOp()` all returned `Unauthorized`. Consistent with the account's known restrictions from GITIN-2006 (no admin-db access, `$indexStats` denied account-wide). **Atlas Query Insights (UI) is the only viable source for this ticket** — there is no CLI/query fallback this time, unlike GITIN-2006 where the size-only `.stats()` inventory at least gave a partial picture without Advisor.
- Not yet confirmed: which specific queries/collections Query Insights is flagging, execution times, frequency, or whether they predate or postdate the GITIN-2006 index changes.

## Current working theory

**Three queries flagged so far (2026-09-08) — two distinct issues, neither fixable by adding an index the way GITIN-2006's findings were.**

### 1, 2 & 3. `smartfran.news` — repeated full-collection count (`data/query-insights-news-count-20260908.txt`, `-2-`, `-3-`)

Same query shape, **three occurrences**, two of them only ~4.5 seconds apart: 12:13:17.213 (1.89s, 394,970 docs), 12:13:21.747 (1.99s, 394,971 docs), 12:23:12.842 (925ms, 395,019 docs) — doc count growing steadily between calls, consistent with normal collection growth, not a data anomaly. Pipeline: `aggregate([{ $match: {} }, { $group: { _id: 1, n: { $sum: 1 } } }])`. Docs Examined ≈ entire collection each time, Docs Returned: 1, Keys Examined: 0, Uses Index: No.

The 4.5-second gap between two of the three occurrences is a stronger signal than "runs periodically" — that's tight enough to suggest either a retry/rapid-succession call pattern, or a single logical request that ends up issuing this count more than once (e.g. once for the response, once for a duplicate/parallel call). Worth asking Dev about call frequency and whether it's expected to fire that close together, not just about switching the count method.

**Not an indexing gap.** An empty `$match` means every document must be visited regardless of what index exists. This exact pipeline shape (`{$match:{}}, {$group:{_id, n:{$sum:1}}}`) is what MongoDB's Node.js driver/Mongoose generates internally for an unfiltered `.countDocuments()` call.

**Confirmed against real source, `develop` branch (pulled 2026-09-08 — both service clones were on `ope`, switched to `develop` and pulled fresh: concentradorService fast-forwarded `9704315b..01733d90`, platformsService already up to date):** `dev-src-smartPedidos-concentradorService/api/src/controllers/news.js`, the `search` function (`POST /news/search`, line 71 onward). Its filter object `data` (lines 103-146) is built entirely from conditional spreads — `...(param != '' ? {field: ...} : {})` — every single condition collapses to `{}` when the corresponding request param is empty or default (`search`, `platform`, `chain`, `status`, `branch`, `rejectedMessage`, `country`, `dateSelected`, `searchSKU`, `turboBoolean`, `exchangeBoolean`, `pickedUpBoolean`, `deliveryType`, `orderTotalAmount`, and `cloudBoolean === undefined` skips the block entirely). When called with no search criteria — the default "browse all news" view — `data` resolves to a literal `{}`, and line 193-195's `.find(data, {'order.id': true}).countDocuments()` becomes exactly the unfiltered count Query Insights captured. This is now a confirmed exact match, not an inferred candidate. **Recommendation: switch to `estimatedDocumentCount()` for the no-filter case** (near-O(1), reads collection metadata instead of scanning) — this is a Dev action item, not an SRE/index one.

The repetition (2 occurrences, 10 min apart, growing doc count) suggests this runs periodically or on a common "list all" request path, not a one-off — worth asking Dev how often/from where this gets called before treating it as low-priority.

### 3b. Second capture (2026-09-17) — same pipeline, no search term: the plain "browse all branches" call has the same cost

A second raw pipeline capture of `branches.js`'s search function, this time with **no real search term** — the second `$match` after `$project` just re-checks `{deletedAt: null}` again (redundant, already filtered before the `$lookup`s), not a `branchReference`/`branchIdReference` filter like the original capture below. `$skip: 0, $limit: 20` pagination happens only inside the trailing `$facet`. **This generalizes finding #3 (below) beyond filtered searches** — even the default unfiltered "list branches" view runs both `$lookup`s against the entire `deletedAt: null` population before pagination trims it to 20 rows. Confirms the restructure recommendation (filter before `$lookup`) matters for the common browse case, not just specific search terms — and flags a small extra redundancy (checking `deletedAt: null` twice with nothing in between that could change it).

### 3. `smartfran.branches` — `$lookup`-heavy search pipeline, Atlas's own warning (`data/query-insights-branches-lookup-20260908.txt`)

500 ms, `aggregate` pipeline: `$match({deletedAt: null})` → `$lookup` into `chains` → `$lookup` into `clients` → `$project` (reshapes ~18 fields) → **second** `$match` (the actual search filter: `branchReference`/`branchIdReference` regex-matching a code, "4079" in this sample) → `$sort` → `$facet` (pagination). Atlas flagged it directly: *"$lookup usage detected. This operation can be resource-intensive. Consider creating indexes or restructuring your schema."*

**Real inefficiency, matches Atlas's own hint:** the actual search filter (`branchReference`/`branchIdReference` match) is applied via a **second** `$match`, positioned *after* both `$lookup`s and the `$project` — meaning both joins run against every document matching the broad first `$match` (`deletedAt: null`) before the real search narrows anything down. Docs Examined: 7,047, Keys Examined: 7,047 (Uses Index: Yes, but the index only supports the broad `deletedAt: null` filter, not the actual search term).

**Confirmed against real source, `develop` branch (same pull as above):** `dev-src-smartPedidos-concentradorService/api/src/controllers/branch.js`, the `search` function (`POST /branches/search`, line 4138-4259). Line-for-line match with the captured pipeline: `$match({deletedAt:null})` (line 4208) → `$lookup` into `chains` (4209-4216) → `$lookup` into `clients` (4217-4224) → `$project` (4225-4247, field names identical to the captured query's output) → **second** `$match: dataSearch` (4248 — `dataSearch` built at lines 4165-4204, this is the real filter including `branchReference`/`branchIdReference`) → `$sort` (4249) → `.facet()` (4251-4254). Confirmed exact match, not inferred. Restructuring to apply the `branchReference`/`branchIdReference` filter *before* the `$lookup`s (or as part of the initial `$match` via an indexed field, if the search target isn't inside the joined data) would let both lookups run against a handful of documents instead of thousands.

**Tangential, unrelated to this ticket — noted, not chased:** pulling `develop` surfaced a just-merged commit (`01733d90`, PR #72) touching this same file's `login` function — it now logs `branchSecret: req.body?.branchSecret[0]` on failed logins (`Log.saveError` call). Possible partial-credential logging; out of scope for GITIN-2013, flagged once for awareness rather than expanding this ticket's scope.

### 4. "Top namespace operations" panel (`data/query-insights-top-namespaces-20260908.txt`) — cross-checks the above and surfaces a new, more concerning signal: slow writes

This panel aggregates op counts/mean/sum per namespace over some window (window length not specified by the UI, not yet confirmed). Two things line up with findings above, one is new:

- **`smartfran.ordertimes` read: 1 op, 2.78s** — matches the `latencyTimestamp.*` query already tracked in GITIN-2006 (2778 ms as of that ticket's 2026-09-08 Advisor pull) almost exactly. Same query, cross-confirmed by a second Atlas panel.
- **`smartfran.news` read: 23 ops, mean 997ms, sum 22.93s** — consistent with the repeated full-collection count found above (3 occurrences captured individually, this panel shows 23 in whatever window it covers — same pattern, higher volume than what got individually sampled).
- **`smartfran.branches` read: 1.11k ops, mean 144ms** — the $lookup-heavy search query (500ms) is an outlier within this larger population of much faster branch reads, not the typical case.
- **New and more concerning: `smartfran.orders` write, 2 ops, mean 8.88s (sum 17.76s); `smartfran.ordertimes` write, 2 ops, mean 5.73s (sum 11.47s).** These are write latencies far worse than anything on the read side. Sample size is tiny (n=2 each) — not enough to treat as a confirmed trend — but the timing is suspicious: **3 new indexes were applied to `branches` and `ordertimes` earlier today in GITIN-2006**, and GITIN-2006's own `ops.md` already flagged an open, unchecked risk (H7) that the index-build's resource impact on the cluster (running the downsized M20 tier) was never verified. A slow write on `ordertimes` right after adding a 6-field compound index to that same collection is consistent with normal write-amplification from a new index — but `orders` didn't get any index changes in GITIN-2006, so its 8.88s write mean isn't explained by that alone if it's real and not sampling noise. **Not concluding causation from n=2 — flagging as the concrete data point GITIN-2006's monitoring follow-up was watching for**, and recommending against treating index-related write cost as ruled out just because reads look fine.

**Unresolved discrepancy, not chased yet:** 7,047 docs examined here vs. `branches`' recorded count of 2,361 docs in GITIN-2006's `.stats()` inventory from earlier the same day (09:30). A ~3x gap in a few hours seems unlikely for a franchise-branch collection under normal operation — not yet explained (bulk onboarding event? `Keys Examined` reflecting multikey index entries rather than distinct documents, given `branches` has multikey indexes on the `platforms` array? Different point-in-time reality?). Flagged, not investigated further — out of this ticket's immediate scope unless it turns out to matter for the `$lookup` fix.

### 5. `news` doc-count fluctuation, resolved: a previously undocumented Atlas App Services Trigger (`data/query-insights-news-count-4-20260908.txt`, `data/query-insights-news-trigger-cleanup-20260908.txt`)

A 4th `news`-count occurrence, timestamped **earlier** than the other 3 (10:00:13, 11.01s) but examining **432,123 docs — ~37K more** than the 09:30 GITIN-2006 baseline (395,076) or the ~12:1x noon counts (~395K). This contradicted the "steady growth" read from the 3 closer-together samples — the collection isn't monotonically growing, it spiked and came back down within ~2 hours.

**Resolved by a 5th entry, 8 minutes later (10:08:18):** a query from `appName: app-services|triggers_stitchapp-ydkmc` — a **native MongoDB Atlas App Services Trigger** (the `stitchapp-` prefix is the legacy Stitch/App Services naming), invisible to source-code grep since it's configured in Atlas's cloud console, not in either Node service's repo. Query: `{ createdAt: { $lte: 2026-08-24T13:08:00Z } }` (a rolling ~2-week-old cutoff relative to today, 2026-09-08), no limit — **37,372 docs examined and returned**, 18.24s, `Uses Index: Yes` (efficient, Keys Examined = Docs Examined = Docs Returned, no over-scanning).

**The arithmetic matches:** 432,123 − 37,372 ≈ 394,751, close to the ~395,000 seen in the noon samples (small residual gap consistent with new docs created in between). This strongly suggests the trigger fetches (and very likely then deletes or archives, based on the age cutoff) `news` docs older than ~2 weeks on a schedule — explaining both the spike-and-return doc count and adding its own 18s query to the slow-query list. **Not confirmed as the same mechanism as the known S3 ETL work** (`20260818_grido-news-etl-s3`, `20260901_grido-redacted-etl-lambda`) — those are a separate AWS Lambda pipeline reading from an S3 backup bucket (`smartfranbkp`), not a MongoDB-native trigger; this is a genuinely different, previously undocumented piece of infrastructure specific to this repo.

**Correction:** the earlier read of this entry as a `find()` fetching 37,372 full documents was wrong. `{ "operation": { "q": {...}, "limit": 0 } }` is the internal shape MongoDB logs for **one entry in a `deleteMany`'s delete-statement array** (`limit: 0` = "delete all matching", not "no limit on a find"). `Docs Returned: 37,372` in this context means **37,372 documents removed**, not fetched. This is now fully confirmed by the actual trigger source below — no inference needed.

**Confirmed via the Atlas App Services Triggers list** (`data/app-services-triggers-list-20260908.txt`) and the trigger's actual source (`data/clearCollection-trigger-source-20260908.txt`): the trigger is named **`clearCollection`**, cron `08 13 * * *` — daily at **13:08 UTC**, exactly `10:08:18.717` local (Argentina, UTC-3) — matching the observed timestamp precisely. `Enabled`, recent heartbeat. A second trigger, `sendMailBranchReject`, exists but is `Disabled` (irrelevant to current load).

**The function is a single scheduled job running 7 sequential, unbatched `deleteMany()` calls, not just on `news`:**

| Collection | Cutoff | Notes |
|---|---|---|
| `orders` | `createdAt` ≤ now − 15 days | |
| `news` | `createdAt` ≤ now − 15 days | the one directly observed in Query Insights (37,372 removed, 18.24s) |
| `ordersFaileds` | `createdAt` ≤ now − 2 days | shorter window than the rest |
| `logerrors` | `createdAt` ≤ now − 15 days | collection is currently empty per GITIN-2006 (Graylog migration) — this delete is a harmless no-op today |
| `openclosedlogs` | `createdAt` ≤ now − 15 days | |
| `rejectpeyas` | `createdAt` ≤ now − 15 days | |
| `ordertimes` | `createdAt` ≤ now − 15 days | **reuses the `openclosedlogs` date variable instead of its own** — functionally identical (both are −15 days) but a naming/maintainability smell, not a bug |

**This directly explains the slow writes flagged in finding #4** (`orders` write mean 8.88s/n=2, `ordertimes` write mean 5.73s/n=2, `news` write mean 2.72s/n=7 in the Top Namespace panel) — those aren't mysterious write-amplification from GITIN-2006's new indexes, they're very likely **this same daily `clearCollection` run**, each `deleteMany` counted as a slow write against its respective collection. This substantially weakens (doesn't fully rule out, small sample size either way) the earlier concern that today's 3 new indexes on `branches`/`ordertimes` were responsible for the slow `ordertimes` write — a scheduled bulk delete on the same collection, same rough time window, is a far more direct explanation. GITIN-2006's resource-monitoring follow-up is still worth doing, but this specific data point shouldn't be read as evidence of index-related write cost.

**New, independent finding worth its own follow-up:** none of these 7 `deleteMany()` calls are batched, throttled, or run with any visible concurrency control — a single trigger invocation deletes across 7 collections back-to-back, unconditionally, every day. This is a reasonable candidate root cause for recurring daily write-latency spikes on whichever of these collections has accumulated the most stale data since the last run, independent of anything found in GITIN-2006.

**Action taken (2026-09-08, `data/app-services-triggers-list-2-20260908.txt`):** the `clearCollection` schedule was changed from `08 13 * * *` to `08 10 * * *` — 3 hours earlier (13:08 UTC / 10:08 ART → 10:08 UTC / 07:08 ART).

**Motivation confirmed by user:** 10:08 ART (the old schedule) risked overlapping with other sources of load/noise — the Concentrador cron and open POS front-end (branch) sessions/deploys. At 07:08 ART (the new schedule), there's no chance of an active deploy or an open branch POS terminal, so the daily `deleteMany()` run has no contention to worry about. This is a real, stated reason — not inference.

## Ruled out

- Nothing ruled out yet.

## Open questions / next steps

1. ~~Need Query Insights data~~ — done, 9 entries captured across 5 findings (2 code-level, 1 infra trigger, 2 cross-confirmations/discrepancies).
2. ~~Cross-check against GITIN-2006~~ — done: the `ordertimes` read (2.78s) matches GITIN-2006's tracked query; the slow-write signal initially suspected to be write-amplification from GITIN-2006's new indexes is now better explained by the `clearCollection` trigger instead (see finding #5) — not fully ruled out, but a materially more likely cause.
3. ~~Determine whether findings predate/postdate GITIN-2006's index changes~~ — not resolved on a strict timeline basis, but superseded: findings #1 and #2 (the two code-level issues) are independent of indexing entirely, and finding #5 (the trigger) is now understood well enough that the timing question no longer matters for it.
4. ~~Confirm exact source-code locations for findings #1/#2~~ — done, both confirmed against real `develop`-branch source (see above): `news.js` `search` function and `branch.js` `search` function, both in `dev-src-smartPedidos-concentradorService`.
5. **Still open:** the `branches` doc-count discrepancy (7,047 examined vs. 2,361 in GITIN-2006's inventory) — not investigated further.
6. **Still open:** confirm with the user the actual motivation behind the `clearCollection` schedule change (currently recorded as inferred, not confirmed).
7. **Still open:** whether to open a separate item for the unbatched multi-collection `deleteMany()` pattern in `clearCollection`, and for the tangential `branchSecret[0]` logging noted above — both flagged, neither actioned.

## Fresh cluster-wide inventory + Atlas Advisor pull (2026-09-16) — cross-checks GITIN-1744/2006, doesn't yet resolve the block

**Confirmed: all 3 of GITIN-2006's applied indexes are live** — `branches.alreadyClosedPediGrido_1_lastGetNews_1` (1.84 MB), `branches.address.country_1_alreadyClosedPeya_1_platforms.StateAPI_1_platforms.platform_1` (0.15 MB), and `ordertimes`'s 6-field `latencyTimestamp.*` compound (37.05 MB) — all three were "suggested/missing" in the original 2026-08-03 pull, all three now genuinely present in a real `.stats()` inventory.

**New Atlas Suggested Indexes pull (2026-09-16), 4 suggestions, none yet applied (confirmed absent from the fresh inventory):**

| Namespace | Suggested index | Avg exec | Freq | Scanned/Returned |
|---|---|---|---|---|
| `news` | `order.tenant.name: 1, order.observations: 1` | 1914 ms | 0.04/hr | 381,523 / 20 |
| `branches` | `alreadyClosedRappi: 1, lastGetNews: 1` | 66 ms | 4.5/hr | 782 / 1 |
| `ordertimesavgcrons` | `avg_calculatedAt: 1` | 137 ms | 0.04/hr | 44,496 / 0 |
| `branches` | `address.country: 1, alreadyClosedUber: 1` | 91 ms | 0.17/hr | 919 / 2 |

- **`ordertimesavgcrons.avg_calculatedAt` is the exact same suggestion flagged on 2026-08-03** — still unaddressed 6+ weeks later, still a full scan returning zero results every time.
- **`branches` suggestions shifted from PediGrido/Peya to Rappi/Uber** — consistent with H4's existing framing (missing coverage for new platform flags, not over-indexing), not a new problem, just the next platforms in the same pattern.
  - **Source traced for the Rappi suggestion (2026-09-16):** `checkOfflinePOSrappi()` (`concentradorService/api/src/controllers/branch.js:448`) — a real POS-heartbeat monitor, not an edge case. Finds branches with a stale `lastGetNews` (>3 min) among active-Rappi branches and auto-closes them via Rappi's API so orders stop routing to a dead terminal; reopens them once polling resumes. Runs **every minute** via in-process `node-cron` (`scheduleRappiOffline = '*/1 * * * *'`, `branch.js:1746,1770`) — Atlas's `4.5/hr` is not the invocation rate, only the subset of runs hitting the slow scan. Genuinely worth the index given this protects real order-routing correctness at high frequency, not just a minor perf nit. **Applied 2026-09-17 (via Atlas UI, not mongosh) and confirmed live** — `db.branches.getIndexes().length` went from 9 to 10. A follow-up Advisor pull just before applying showed frequency had risen to `15.08/hr` (from `4.5/hr` initially), reinforcing this was worth prioritizing.
- **`news` — genuinely new finding, top-ranked by Atlas ("Top Suggestion," up to 934 MB disk-read savings).** `order.tenant.name` + `order.observations` compound. Confirmed absent from the real index list (14 existing `news` indexes checked, none match). **Traced (2026-09-16) — very likely our own ad-hoc validation query, not a production code path.** Grepped both `concentradorService` and `platformsService` source for any query building `{"order.tenant.name": ..., "order.observations": ...}` as a filter — none exists. Every `tenant.name` occurrence in both repos is either an in-memory JS field reference/comparison or a literal write into a new order document, never a MongoDB query filter shaped like this. This exact field pair and low frequency (`0.04/hr`) match `GITIN-1880`'s own `scripts.js` second query (corrected 2026-09-16 to filter `order.tenant.name: "grido"` while checking `order.observations`), run manually via `mongosh` as part of that ticket's PII-validation sampling. **Confirmed (2026-09-16) — exact match, not circumstantial.** Atlas's query-shape detail for this suggestion shows `$match: {"order.tenant.name": "grido", "order.observations": {$exists: true, $ne: ...}}` → `$sample: {size: 20}` → `$project: {_id: 0, "order.observations": 1}` — structurally identical to `GITIN-1880`'s `scripts.js` second query. **No index fix needed.** This is our own PII-validation query from that ticket's investigation, not a real application query pattern — closed, not a finding for this ticket.

**Two long-open discrepancies get supporting, not conclusive, evidence:**
- `branches` doc count: 2,367 now (fresh `.stats()`), essentially unchanged from GITIN-2006's 2,361 — not the 7,047 "docs examined" this ticket's Query Insights pull showed. Supports (doesn't confirm) the multikey-index-entries theory over a real document-count spike.
- `ordertimes.branch_1` size: 7.17 MB now, close to the earlier `.stats()` figure (8.01 MB) — not Atlas Advisor's 46.1 MB. Second data point favoring the `.stats()` number.

**`logerrors` cross-check confirms GITIN-2006's H6 exactly**: 0 docs, only `_id_` remains (23.87 MB, down from 247.86 MB seen mid-investigation earlier — some compaction likely happened since). The "re-add `createdAt_1`" recommendation stays correctly moot.

**Does not yet explain the current Jira "Bloqueado" status** — none of this pull's findings are framed as a blocker; still needs the user to confirm what's actually blocking this ticket right now.

## `ordertimesavgcrons` reclassified: unindexed daily delete, source not yet identified (2026-09-16)

Raw slow-query log entry (user-provided) reclassifies the `ordertimesavgcrons.avg_calculatedAt` Advisor suggestion — it's not a read returning 0 results, it's a **`remove` (delete) operation**: `{avg_calculatedAt: {$gte: 2026-09-15T00:00:00Z, $lte: 2026-09-15T23:59:59Z}}`, `limit: 0` (delete all matching), run `2026-09-16T08:00:07 UTC`. `planSummary: COLLSCAN`, `docsExamined: 44496`, **`ndeleted: 0`** — scanned the entire collection, deleted nothing. `remote: 52.20.61.149` (AWS).

**More interesting than the missing index: this delete is scanning the full collection daily and matching zero documents.** Either the job's date-matching logic doesn't line up with how `avg_calculatedAt` actually gets written, or this collection has been silently accumulating without ever being cleaned by whatever this job intends to do.

**Checked Atlas App Services Triggers — confirmed NOT the source.** Only 2 triggers exist total: `clearCollection` (scheduled, still on the corrected `08:10 UTC` daily schedule from earlier — confirmed via `Latest Heartbeat: 09/16/2026 17:14:12 ART`) and `sendMailBranchReject` (disabled). Neither targets `ordertimesavgcrons`. **This delete originates from something external to Atlas's native trigger mechanism** — most likely an AWS Lambda or EC2 cron job not yet mapped in this investigation. **Checked and ruled out (2026-09-16): all AWS Lambda functions in the account, and the previously-unmapped `mongoAllCollections-to-s3-CFN-ScheduledMongoToS3-MRO2H3EOSN6E` specifically.** Full `list-functions` pull found no name matching "avgcron"/"average", and the one plausible new candidate (`mongoAllCollections-to-s3...`, distinct from the already-known `mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO`) was downloaded and inspected directly — its source has zero `deleteMany`/`deleteOne`/`remove` calls anywhere, and its fixed model set (`activeSoftware`, `branch`, `chain`, `client`, `country`, `deliveryTime`, `news`, `newsState`, `newsType`, `platform`, `region`, `rejectedMessage`, `user`) doesn't include `ordertimesavgcrons` despite the "AllCollections" name — it's a fixed export set, not a generic loop. **Both candidate mechanisms (Atlas native triggers, AWS Lambda) ruled out. EventBridge rules also checked — nothing unaccounted for** (`data/eventbridge_rules_list_20260916.txt`; everything scheduled is already known: `grido-redacted-etl-daily`, both `mongo-to-s3`/`mongoAllCollections-to-s3` Lambdas, disabled EC2 power toggles, third-party `MontyCloud`).

**Source found (2026-09-16) — an in-process `node-cron` job inside `concentradorService` itself, not any external AWS/Atlas mechanism.** `dev-src-smartPedidos-concentradorService/api/src/controllers/branch.js:1754,1775`:
```js
const scheduleOrerTimesAvg = '0 8 * * *';  // [sic] typo in the actual source variable name
cron.schedule(scheduleOrerTimesAvg, async () => await initialData.ordertimesAvgCron());
```
Daily at `08:00`, matching the observed `08:00:07 UTC` execution almost exactly. `InitialData.ordertimesAvgCron()` (`api/src/utils/initialData.js:26-135`) computes hourly order-time averages, then does exactly the **delete-then-recompute-and-insert** pattern seen in the slow-query log: `ordertimesAvgCronModel.deleteMany({avg_calculatedAt: {$gte: start, $lte: end}})` (line 132) immediately followed by `insertMany(docs)` (line 135). **This fully explains `ndeleted: 0`** — it's not a bug, it's the delete-before-insert half of a normal recompute cycle; whether it actually deletes anything depends on whether that window was already cleared earlier in the same run or never had data for it, not a sign of malfunction.

**Real, low-priority fix candidate confirmed:** the `deleteMany` filter (`avg_calculatedAt`) has no supporting index — matches Atlas's original suggestion exactly, genuinely a full `COLLSCAN` on every run. Low impact (`0.04/hr`, single daily internal job, not customer-facing), but a legitimate one-line index add if anyone wants to action it — same recommendation as before, just now with a fully understood mechanism instead of an open mystery.

## Ticket status

`ops.md` written (2026-09-08), `Resuelto: Parcial`. Per user instruction, the H1/H2 code excerpts (the `news.js` conditional-filter/`countDocuments()` snippet and the full `branch.js` aggregate pipeline) were placed directly in `ops.md` under a "Código relevante" section, not in a separate findings file — a deliberate deviation from `sp-sre-output`'s default "no inline code in Hallazgos, reference a findings file" convention for this ticket.

**Updated 2026-09-17 — current actual state of every open item:**

| Item | Status |
|---|---|
| Tier 2 Dev fixes (`news.js` countDocuments→estimatedDocumentCount; `branches.js` $lookup reordering) | Still open — Dev action, not SRE, not confirmed done |
| `clearCollection` schedule-change motivation | **Resolved 2026-08-31** — real, user-stated reason (avoid deploy/POS-session overlap), not inference. Stale in this summary until now. |
| `clearCollection` unbatched multi-collection `deleteMany` pattern | Still open — flagged, not actioned |
| `branches` doc-count discrepancy (7,047 vs. 2,367) | Still open, informational — supporting (not conclusive) evidence gathered 2026-09-16 favoring "multikey index entries, not a real spike" |
| `ordertimes.branch_1` size discrepancy (46.1 MB vs. ~7-8 MB) | Still open, informational — same status |
| `branches`/`ordertimesavgcrons` Advisor suggestions (2026-09-16 fresh pull) | Rappi index: **done**, spun off + closed under [GITIN-2062](https://smartit-ar.atlassian.net/browse/GITIN-2062). Uber index: open, tracked under GITIN-2062, not this ticket. `ordertimesavgcrons`: real but low-priority, not yet applied, no separate ticket. |
| `news` Advisor "Top Suggestion" | **Closed as false positive** — confirmed to be `GITIN-1880`'s own validation query, not application traffic |
| Jira "Bloqueado" status | **Fully resolved (2026-09-17).** `GITIN-1744` confirmed closed by the user. `GITIN-2013` now shows `Finalizada` in Jira, no longer `Bloqueado`. |

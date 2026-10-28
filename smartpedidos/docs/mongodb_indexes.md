# MongoDB Indexes — Reference

Consolidated knowledge from index/query-performance investigations on `PedidosSmartfran` (Atlas, `us-east-1`, database `smartfran`). Source tickets: [GITIN-1744](https://smartit-ar.atlassian.net/browse/GITIN-1744) (2026-08-03, paused, superseded), [GITIN-2006](https://smartit-ar.atlassian.net/browse/GITIN-2006) (2026-09-08, closed, formal continuation), [GITIN-2013](https://smartit-ar.atlassian.net/browse/GITIN-2013) (2026-09-08 onward, Query Insights follow-up; `Finalizada` in Jira 2026-09-17), [GITIN-2062](https://smartit-ar.atlassian.net/browse/GITIN-2062) (`branches` Rappi/Uber indexes, 2026-09-17). Full derivation lives in those tickets' `investigation.md`/`ops.md` — this file is the durable summary, not a replacement.

## Account access constraints

- **`$indexStats` is denied account-wide** — confirmed across all 34 collections, no exceptions, not a per-collection gap (`GITIN-1744`, 2026-08-03). No real-usage-ops data is obtainable via `mongosh` with the current account.
- **`.stats()` (size-based inventory) works fine.** Use the reusable inventory script below for a size baseline.
- **Atlas Performance Advisor (Unused Indexes / Suggested Indexes panels) is the only source of real usage data** given the above — UI-only, no CLI/API equivalent used so far.
- **No `mongosh` route to slow-query data either** (2026-09-08): `getProfilingStatus()`, `system.profile` reads and `currentOp()` return `Unauthorized`. Query Insights (UI) is the only slow-query source; the Advisor panels are now labelled "Drop Indexes" / "Create Indexes".
- **Atlas Query Insights** (distinct from Performance Advisor) gives per-query execution detail, including exact aggregation/filter shape and sample raw slow-query log lines — useful for tracing a suggestion back to its actual source (see "Tracing a query to its source" below).

## Reusable cluster-wide inventory script

```javascript
db.getCollectionNames().sort().forEach(name => {
  let stats;
  try {
    stats = db.getCollection(name).stats();
  } catch (e) {
    print(`\n=== ${name} === stats() error: ${e.codeName || e.message}`);
    return;
  }
  const indexSizes = stats.indexSizes || {};
  print(`\n=== ${name} === docs: ${stats.count}, dataSize: ${(stats.size/1024/1024).toFixed(2)} MB, totalIndexSize: ${(stats.totalIndexSize/1024/1024).toFixed(2)} MB`);
  try {
    db.getCollection(name).aggregate([{ $indexStats: {} }]).forEach(u => {
      const sizeMB = ((indexSizes[u.name] || 0) / 1024 / 1024).toFixed(2);
      print(`  ${u.name} | key: ${JSON.stringify(u.key)} | size: ${sizeMB} MB | ops: ${u.accesses.ops} | since: ${u.accesses.since}`);
    });
  } catch (e) {
    print(`  $indexStats unauthorized — falling back to size-only from indexSizes:`);
    Object.keys(indexSizes).forEach(idxName => {
      print(`  ${idxName} | size: ${(indexSizes[idxName]/1024/1024).toFixed(2)} MB | ops: unavailable (no $indexStats privilege)`);
    });
  }
});
```

## Known scheduled jobs that touch these collections (easy to re-discover the hard way — check here first)

Query Insights will periodically flag slow operations from jobs that aren't obvious from the collection name alone. Three confirmed sources so far, spanning three different mechanisms — don't assume one without checking:

| Job | Mechanism | Collections touched | Schedule |
|---|---|---|---|
| `clearCollection` | **Atlas App Services Trigger** (native, not AWS) | `orders`, `news`, `ordersFaileds`, `logerrors`, `openclosedlogs`, `rejectpeyas`, `ordertimes` — 7 unbatched sequential `deleteMany()` calls, all `createdAt` ≤ now − 15 days (`ordersFaileds` is −2 days) | Daily, `08:10 UTC` (changed from `13:08 UTC` on 2026-09-08 to avoid deploy/POS-session overlap) |
| `ordertimesAvgCron` | **In-process `node-cron`**, inside `concentradorService` itself (`api/src/controllers/branch.js:1754,1775`) — not Atlas, not a separate AWS Lambda | `ordertimesAvgCron` (delete-then-recompute-and-insert for the prior day's hourly latency averages) | Daily, `'0 8 * * *'` (server-local, observed as `08:00 UTC`) |
| `grido-redacted-etl-daily` | **AWS EventBridge → Lambda** (`grido-redacted-etl`, Python) | Reads `smartfranbkp/news/*-3.json` from S3 (not MongoDB directly), writes filtered/redacted output to `smartpedidos-orders` S3 bucket | Daily, `cron(0 4 * * ? *)` (`04:00 UTC`) |

**What `clearCollection` does to the numbers you see (`GITIN-2013`, `events/20260908_gitin2013-query-insights-slow-queries/`):** it is the mechanism behind the 15-day retention of `news` (not a TTL index). Its `deleteMany` appears in Query Insights as an operation with `limit: 0` and `Docs Returned` equal to the number of documents **removed** (37,372 `news` documents in 18.24 s on 2026-09-08, `Uses Index: Yes`); `news` therefore spikes by that amount before the run (432,123 against ~395,000 on 2026-09-08) and falls back, so a count taken before 08:10 UTC is not the steady size. It also explains the slow writes seen right after GITIN-2006's index builds (`orders` 8.88 s, `ordertimes` 5.73 s, `news` 2.72 s mean, n = 2 to 7): the daily bulk delete, not write amplification of the new indexes (the small sample does not rule the latter out). Native Atlas App Services triggers: `clearCollection` (enabled; cron `08 10 * * *`) and `sendMailBranchReject` (disabled); the source names a delete variable of `openclosedlogs` reused for `ordertimes` (both −15 days, a smell, not a bug). The 7 deletes are unbatched and back to back every day: a candidate for a later latency fix, not actioned. An `appName` of `app-services|triggers_stitchapp-...` in a slow-query entry identifies it.

Other known scheduled AWS jobs (not MongoDB-write-heavy, listed for completeness): `mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO` (Node.js, `news`/`orders` export, `cron(30 3 * * ? *)`), `mongoAllCollections-to-s3-CFN-ScheduledMongoToS3-MRO2H3EOSN6E` (Node.js, fixed-model export set — `activeSoftware`/`branch`/`chain`/`client`/`country`/`deliveryTime`/`news`/`newsState`/`newsType`/`platform`/`region`/`rejectedMessage`/`user` — no deletes despite the "AllCollections" name, `cron(30 3 * * ? *)`).

## Verify with `explain()` before trusting an Advisor suggestion helped anything

**Confirmed pitfall (2026-09-17, `branches.alreadyClosedRappi_1_lastGetNews_1`):** applying an Atlas Suggested Index and confirming it exists (`getIndexes()` count went up) is not the same as confirming it's actually *used*. Atlas's suggestion was based on a 2-field query shape (`alreadyClosedRappi`, `lastGetNews`); the real application query (`checkOfflinePOSrappi()`) also filters on `platforms.$elemMatch({platform, isActive})`. Running `explain("executionStats")` against the *real* query showed MongoDB's planner picking the pre-existing `platforms.platform_1_platforms.branchReference_1` index instead — the new index appeared only in `rejectedPlans`. Reason: `platforms.platform` (an exact `ObjectId` match) is far more selective than `alreadyClosedRappi` (only 2-3 possible values, poor as a leading index field). Real execution was already fast (7ms) using the old index alone.

**Rule going forward: after applying any Atlas-suggested index, run `explain("executionStats")` against the actual application query (not Atlas's simplified sample shape) before considering it resolved.** An index that exists but isn't chosen by the planner is pure downside — write cost, no read benefit.

**Second rule — even a verified-useful index isn't automatically worth creating: quantify the aggregate impact first.** The `branches.address.country_1_alreadyClosedUber_1` suggestion (2026-09-17, `sendStatusUberEats()`) checked out on `explain()` — the planner would genuinely use it, and the existing indexes serve that query poorly (187ms, 1,047 keys examined for 66 results). But at `0.17/hr` real frequency, the aggregate savings work out to under 1 second/day cluster-wide. **Decision: skip it** — this cluster runs on an **Atlas M20** tier (limited RAM/resources), where every index has a real storage and write-amplification cost regardless of whether reads ever benefit meaningfully. Low-frequency queries, even measurably slow ones, may not clear that bar. Multiply `avg execution time saved × real frequency` (not Atlas's per-execution ms alone) before deciding an index is worth its ongoing cost — this matters more on a constrained tier than it would on a larger one.

## Tracing a query to its source — method that works

1. Pull the query's exact shape from Atlas Query Insights (the `$match`/`$sort`/`$project` pipeline detail, or the raw slow-query log JSON if available).
2. Check the three mechanisms above first (Atlas Triggers UI, `aws lambda list-functions`, `aws events list-rules`) before assuming it's a mystery — all three have turned out to be the answer before.
3. If none of those match, grep both service repos directly for the collection/field names — `grep -rn "<collectionOrFieldName>" repo/ --include="*.js" | grep -v node_modules`. In-process `node-cron` jobs (like `ordertimesAvgCron`) won't show up in any AWS/Atlas scheduling surface at all — only in source.
4. **Don't assume a query is a real application pattern just because it's frequent-looking in Atlas.** One "Top Suggestion" (`news`: `order.tenant.name`+`order.observations`, 934 MB potential savings) turned out to be our own ad-hoc PII-validation `mongosh` query from `GITIN-1880`'s investigation, not application traffic at all — confirmed via exact pipeline-shape match. Low frequency (≤0.1/hr) plus an exact match to a known investigation script is a strong tell.

## Collection notes

- **`branches`**: not over-indexed (a `GITIN-1744` hypothesis, ruled out) — the real pattern is *missing* coverage for new platform-specific query flags as they get added (`alreadyClosedX`/`lastGetNews` per platform). `GITIN-2006` (2026-09-08) created three indexes, all verified with `getIndexes()`: `branches` `{alreadyClosedPediGrido, lastGetNews}` (1.84 MB; its Advisor frequency rose 0.21/hr → 5.25/hr → 19.04/hr over three pulls, a real sustained trend), `branches` `{address.country, alreadyClosedPeya, platforms.StateAPI, platforms.platform}` (0.15 MB) and `ordertimes` `{latencyTimestamp.finalResponseDate, platformDate, receiveSqsDate, responseDate, sendSqsDate, entryDate}` (37.05 MB; the query it serves took 393 ms → 2,778 ms across three pulls). Not applied from that list: `branches` Rappi/Uber compounds (then handled in `GITIN-2062`: Rappi created, found unused; Uber decided against) and `ordertimesavgcrons.avg_calculatedAt`. The build's effect on cluster resources (M20) was never measured: an early "no impact on order flow" statement was an inference. Expect this to keep recurring — check Atlas Suggested Indexes for the next platform before assuming the collection needs a redesign.
  - **Source confirmed for the Rappi pattern (2026-09-16):** `checkOfflinePOSrappi()` (`concentradorService/api/src/controllers/branch.js:448`), a **real POS-heartbeat monitor** — finds branches whose `lastGetNews` (last poll/heartbeat) has gone stale (>3 min) among active-Rappi branches and auto-closes them on Rappi's side (calls Rappi's disable-store API) so orders don't route to a dead terminal; reopens them once polling resumes. **Scheduled via in-process `node-cron`, every minute** (`scheduleRappiOffline = '*/1 * * * *'`, `branch.js:1746,1770`) — Atlas's `4.5/hr` figure is not the invocation rate (1,440/day), only the subset of runs that hit the slow-scan pattern. Each platform almost certainly has its own analogous `checkOfflinePOS<Platform>()` job (same `alreadyClosedX`/`lastGetNews` shape seen for Uber/Peya/PediGrido too) — check for the same pattern before assuming a new platform's missing index is a one-off.
- **`logerrors`**: **0 documents as of `GITIN-2006`/`2013`** — logging migrated to Graylog, this collection is now inert. Don't act on any `logerrors`-related index suggestion without confirming current document count first; old findings (e.g. "re-add `createdAt_1`") are moot post-migration.
- **`ordertimes.branch_1` index size**: Atlas Advisor says 46.1 MB (2026-08-03); `.stats()` read 8.01 MB (2026-08-03), **46.10 MB (2026-09-08)** and 7.17 MB (2026-09-16), so `.stats()` itself is not stable and neither source can be trusted yet; unresolved, so quote none of the three as the size. If a later pull shows 46 MB and the index unused it would be the largest drop candidate in the cluster.
- **Drop list of `GITIN-1744` is stale:** its 16 "confirmed unused" indexes (≈145 MB, 7-day Advisor window under M30) are not flagged any more (the 2026-09-08 pull shows 0 drop recommendations). Whether they are being used again or the usage window reset after a node restart was never settled: do not act on that list without a fresh pull.
- **`ubercheckorders`**: 161,973 documents, 20 MB, a single `token_1` index of 8.47 MB (about 42 % of the data size): small and low priority, outside the original audit.
- **`news` and the application's own queries (`GITIN-2013`, Dev actions, not index fixes; still open as of 2026-09-17):** (1) `POST /news/search` (`api/src/controllers/news.js`, `search`) turns the default unfiltered view into `find({}).countDocuments()`, a full-collection scan (1-2 s on ~395,000 documents, 23 operations of mean 997 ms in the Top Namespaces panel, two calls 4.5 s apart): use `estimatedDocumentCount()` for the no-filter case and ask Development how often it is called; (2) `POST /branches/search` (`api/src/controllers/branch.js`, `search`) runs both `$lookup`s (`chains`, `clients`) over every `deletedAt: null` branch before the second `$match` that holds the real search term (500 ms, 7,047 keys examined, Atlas's own `$lookup` warning; the default browse view re-checks `deletedAt: null` twice): apply the filter before the `$lookup`s. Query Insights examined 7,047 documents on `branches` against a `.stats()` count of ~2,361-2,367, probably multikey index entries.
- **`news` retention** is the daily `clearCollection` delete above, not a TTL index.
- **`branches` doc-count discrepancy**: Query Insights once showed "7,047 docs examined" against a collection whose `.stats()` count is consistently ~2,360-2,370 across multiple pulls weeks apart. Not fully resolved, but the stable `.stats()` count across time argues for "Keys Examined reflecting multikey index entries" (branches has multikey indexes on the `platforms` array) over an actual document-count spike.
- **`ordertimesavgcrons`**: real collection, real cron job (`ordertimesAvgCron`, see table above; the source variable is spelled `scheduleOrerTimesAvg`). The Advisor suggestion for `avg_calculatedAt` looks like a read returning 0 rows, but the slow-query log shows it is the job's **delete** before re-inserting (`limit: 0`, `COLLSCAN` over 44,496 documents, `ndeleted: 0`, from the concentrador's address), which is normal for a recompute cycle. The field has no supporting index — a genuine but low-priority (`0.04/hr`, internal-only) one-line fix candidate. Not urgent.

## Open, unresolved as of this writing

- Dev fixes of `GITIN-2013` (`news.js` count, `branch.js` `$lookup` order), the unbatched `clearCollection` deletes, and a log line in the concentrador `login` function that writes `branchSecret[0]` on a failed login (commit `01733d90`, PR #72; a possible partial-credential log, flagged once and not actioned).
- `branches.alreadyClosedRappi_1_lastGetNews_1` — created 2026-09-17, but `explain()` confirms the planner doesn't use it for the real query (see below) — pending a decision on whether to drop it.
- `branches.address.country_1_alreadyClosedUber_1` — investigated fully (2026-09-17), verified useful via `explain()`, but **deliberately not created** — negligible aggregate impact (<1s/day) doesn't justify the cost on this cluster's M20 tier. See `GITIN-2062` for full detail.
- `ordertimesavgcrons.avg_calculatedAt` — real, low-priority, not yet applied, not chased further.
- `ordertimes.branch_1` size discrepancy (see above).
- `branches` doc-count discrepancy (see above).

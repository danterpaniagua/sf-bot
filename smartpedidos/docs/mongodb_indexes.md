# MongoDB Indexes — Reference

Consolidated knowledge from index/query-performance investigations on `PedidosSmartfran` (Atlas, `us-east-1`, database `smartfran`). Source tickets: [GITIN-1744](https://smartit-ar.atlassian.net/browse/GITIN-1744) (2026-08-03, paused, superseded), [GITIN-2006](https://smartit-ar.atlassian.net/browse/GITIN-2006) (2026-09-08, closed, formal continuation), [GITIN-2013](https://smartit-ar.atlassian.net/browse/GITIN-2013) (2026-09-08 onward, Query Insights follow-up). Full derivation lives in those tickets' `investigation.md`/`ops.md` — this file is the durable summary, not a replacement.

## Account access constraints

- **`$indexStats` is denied account-wide** — confirmed across all 34 collections, no exceptions, not a per-collection gap (`GITIN-1744`, 2026-08-03). No real-usage-ops data is obtainable via `mongosh` with the current account.
- **`.stats()` (size-based inventory) works fine.** Use the reusable inventory script below for a size baseline.
- **Atlas Performance Advisor (Unused Indexes / Suggested Indexes panels) is the only source of real usage data** given the above — UI-only, no CLI/API equivalent used so far.
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

- **`branches`**: not over-indexed (a `GITIN-1744` hypothesis, ruled out) — the real pattern is *missing* coverage for new platform-specific query flags as they get added (`alreadyClosedX`/`lastGetNews` per platform). Confirmed indexed for PediGrido/Peya as of `GITIN-2006`; Rappi/Uber patterns flagged as the next round, not yet applied (`GITIN-2013`, 2026-09-16). Expect this to keep recurring — check Atlas Suggested Indexes for the next platform before assuming the collection needs a redesign.
  - **Source confirmed for the Rappi pattern (2026-09-16):** `checkOfflinePOSrappi()` (`concentradorService/api/src/controllers/branch.js:448`), a **real POS-heartbeat monitor** — finds branches whose `lastGetNews` (last poll/heartbeat) has gone stale (>3 min) among active-Rappi branches and auto-closes them on Rappi's side (calls Rappi's disable-store API) so orders don't route to a dead terminal; reopens them once polling resumes. **Scheduled via in-process `node-cron`, every minute** (`scheduleRappiOffline = '*/1 * * * *'`, `branch.js:1746,1770`) — Atlas's `4.5/hr` figure is not the invocation rate (1,440/day), only the subset of runs that hit the slow-scan pattern. Each platform almost certainly has its own analogous `checkOfflinePOS<Platform>()` job (same `alreadyClosedX`/`lastGetNews` shape seen for Uber/Peya/PediGrido too) — check for the same pattern before assuming a new platform's missing index is a one-off.
- **`logerrors`**: **0 documents as of `GITIN-2006`/`2013`** — logging migrated to Graylog, this collection is now inert. Don't act on any `logerrors`-related index suggestion without confirming current document count first; old findings (e.g. "re-add `createdAt_1`") are moot post-migration.
- **`ordertimes.branch_1` index size**: Atlas Advisor and `.stats()` disagree by ~5-7x (46.1 MB vs. 7-8 MB across two separate pulls) — unresolved measurement-basis discrepancy, likely cluster/replica-aggregate vs. single-node. Trust the `.stats()`/`indexSizes` figure until reconciled.
- **`branches` doc-count discrepancy**: Query Insights once showed "7,047 docs examined" against a collection whose `.stats()` count is consistently ~2,360-2,370 across multiple pulls weeks apart. Not fully resolved, but the stable `.stats()` count across time argues for "Keys Examined reflecting multikey index entries" (branches has multikey indexes on the `platforms` array) over an actual document-count spike.
- **`ordertimesavgcrons`**: real collection, real cron job (`ordertimesAvgCron`, see table above), the `avg_calculatedAt` field has no supporting index — a genuine but low-priority (`0.04/hr`, internal-only) fix candidate. Not urgent.

## Open, unresolved as of this writing

- What's actually blocking `GITIN-2013` in Jira ("Bloqueado") — not explained by anything found in the investigation itself.
- `branches.alreadyClosedRappi_1_lastGetNews_1` — created 2026-09-17, but `explain()` confirms the planner doesn't use it for the real query (see below) — pending a decision on whether to drop it.
- `branches.address.country_1_alreadyClosedUber_1` — investigated fully (2026-09-17), verified useful via `explain()`, but **deliberately not created** — negligible aggregate impact (<1s/day) doesn't justify the cost on this cluster's M20 tier. See `GITIN-2062` for full detail.
- `ordertimesavgcrons.avg_calculatedAt` — real, low-priority, not yet applied, not chased further.
- `ordertimes.branch_1` size discrepancy (see above).
- `branches` doc-count discrepancy (see above).

# Investigation — 20260908_gitin2006-mongo-index-review

**Status:** converged — ticket written and closed (`ops.md`). Remaining Tier 2 indexes, the `ordertimesavgcrons` Dev question, and post-change resource monitoring under M20 stay as explicit follow-up, not blocking closure.

**Jira:** [GITIN-2006](https://smartit-ar.atlassian.net/browse/GITIN-2006) "[SP] Revisión de índices de mongo", parent [GITIN-1857](https://smartit-ar.atlassian.net/browse/GITIN-1857).

## Purpose

Index health review of the `PedidosSmartfran` MongoDB Atlas cluster (`us-east-1`, database `smartfran`).

**Confirmed with user (2026-09-08):** GITIN-2006 is the formal re-ticketing of the paused `smartpedidos/events/20260803_analisis-indices-mongodb` audit (tracked there under [GITIN-1744](https://smartit-ar.atlassian.net/browse/GITIN-1744)), which paused waiting for the M20 downsize ([GITIN-1741](https://smartit-ar.atlassian.net/browse/GITIN-1741)) to stabilize before re-pulling usage data. Same cluster, same scope — linked tickets, not a separate ask.

## Carried over from GITIN-1744 (paused state, full detail in that investigation)

- Full 34-collection size inventory pulled 2026-08-03 (post M30, pre-M20). `$indexStats` (usage ops/since) is **denied account-wide** on every collection — size-only via `.stats()` is the only direct `mongosh` route; Atlas Performance Advisor (UI, "Unused Indexes" + "Suggested Indexes" panels) was the working fallback for real usage data.
- **16 confirmed-unused indexes** (7-day Advisor window, M30-era) across `orderrejcloseds`, `openclosedlogs`, `orders`, `ordertimes`, `news` — ≈145.2 MB. Full table in the prior investigation.
- **`logerrors.createdAt_1` — confirmed load-bearing, not yet re-added.** Dropped mid-session in the M20 ticket without query verification; Advisor then showed a query doing a 352,943-doc full scan (~13s avg) that matches the drop exactly. Standalone recommendation, independent of the M20-wait — still open.
- **`branches` — zero unused indexes, but 6 suggested (missing) indexes** as of the M20 re-pull (up from 2 at M30): a `<platformFlag>_1_lastGetNews_1` and an `address.country_1_<platformFlag>_1[...]` compound per platform flag (Uber, Peya, Rappi, PediGrido). Reframe: `branches` isn't over-indexed, it's missing coverage for query shapes added after its original indexes were built.
- **`ordertimes.latencyTimestamp.*` suggested index** — stable across both M30/M20 pulls, scans ~317-327K of ~337K docs to return 101 rows.
- **`ordertimesavgcrons.avg_calculatedAt`** suggested — every execution full-scans and returns 0 rows; likely dead/obsolete query, worth asking Dev, or add the index.
- Size-based redundancy candidates (same-field-prefix standalone + compound) flagged across `ordertimes`, `orders`, `news`, `branches` — usage data confirmed some, refuted others; don't re-trust the shape-only heuristic without a fresh Advisor cross-check.

## Unresolved from GITIN-1744 (carry into this ticket)

1. `ordertimes.branch_1` size discrepancy: 46.1 MB (Advisor) vs. 8.01 MB (`.stats()`/`indexSizes`) — unreconciled, don't use either figure until resolved.
2. `branches.alreadyClosedPediGrido_1_lastGetNews_1` frequency jump (0.21/hr M30 → 5.25/hr M20 pull, ~25x) — not explained; don't quote Advisor's disk-read-savings estimate as validated until checked.
3. Whether Advisor's "7-day unused" window itself resets on the cluster's periodic node-restart pattern (same caveat as raw `$indexStats.accesses.since`) — if so, "unused for 7 days" may just mean "unused since last restart," not truly dead. Never confirmed either way.
4. `logerrors` doc-count nearly halved same-day mid-investigation (352,943 → 178,486) — flagged, not chased, tangential to index scope.

## Current working theory

Same as GITIN-1744's conclusion: this is not a "too many indexes" problem in isolation — it's a **paired add/drop** situation. Confirmed-unused indexes (~145 MB) are real drop candidates, but `branches` and `ordertimes` also have confirmed missing-index gaps causing near-full-collection scans. `logerrors.createdAt_1` re-add is the one item that isn't a judgment call — it's reverting a proven regression.

## Ruled out

- Nothing ruled out yet in this ticket specifically.

## Fresh data pull (2026-09-08, `data/index-inventory-20260908.txt`)

- **`$indexStats` still denied account-wide** — unchanged since 2026-08-03, same `Unauthorized` on every collection. Size-only inventory remains the only direct `mongosh` route; Atlas Advisor still needed for usage data.
- **`logerrors` is now empty** — 0 docs, 0.00 MB data, only `_id_` index (0.05 MB) remains; `createdAt_1` etc. were never re-added. This ties to `[[project_smartpedidos_logging_migrated_to_graylog]]`: platforms-service's Mongo logging was already known dead (`mongoLogEnabled:false`, logs now go stdout → Event Hub → Graylog) — the collection being empty is consistent with that, not a new incident. **This moots the standalone "re-add `logerrors.createdAt_1`" recommendation carried over from GITIN-1744** — there's no live query path left to protect on a 0-doc collection. Drop that action item rather than act on it.
- **`ordertimes.branch_1` discrepancy — resolved, in Advisor's favor.** Fresh `.stats()` now shows 46.10 MB, matching Atlas Advisor's 46.1 MB figure from the 2026-08-03 pull almost exactly. The earlier 8.01 MB `.stats()` reading (logged as conflicting in GITIN-1744) looks like it was the stale/wrong one. `ordertimes` total index size grew from ~52 MB (Aug baseline) to 93.17 MB now, almost entirely attributable to this one index. If Advisor's fresh pull still shows `branch_1` as unused, this is now the single highest-value drop candidate in the whole cluster (46 MB, no compound counterpart).
- **`branches`' previously-suggested missing indexes not added** — none of the 6 suggested compounds from the M20-era Advisor pull (PediGrido/Rappi/address.country-led) appear in the current 7-index list (`_id_`, `branchId_1`, `platforms.platform_1_platforms.branchReference_1`, `platforms.StateAPI_1_platforms.branchName_1_platforms.platform_1`, `alreadyClosedUber_1_lastGetNews_1`, `alreadyClosedPeya_1_...`, `deletedAt_-1`). Total index size ~39.95 MB, roughly flat vs. the ~42-44 MB baseline range — no structural change besides the two known large compounds shrinking slightly (9.98 MB / 29.26 MB vs. 10.63-11.6 MB / 29.26-33.6 MB across earlier pulls, likely just data churn).
- **`news` and `orders` — structurally unchanged.** Same 14 indexes on `news` (docs 360,510 → 395,076, index size 178.52 → 190.43 MB, proportional growth) and same 13 on `orders` (index size ~112 → 123.24 MB, still ~9% of data) as the GITIN-1744 baseline. The same redundancy candidates (standalone fields duplicated as compound prefixes) still stand, still unconfirmed without fresh Advisor data.
- **Not previously in audit scope, worth a look:** `ubercheckorders` — 161,973 docs, 20.08 MB data, single `token_1` index at 8.47 MB (~42% of collection size). Small collection overall, low priority, but flagged since it wasn't covered in GITIN-1744's collection-by-collection detail.
- `ordertimesavgcrons` still has only `_id_` (0.47 MB) — the suggested `avg_calculatedAt: 1` index (full-scan-every-time, 0 rows returned) still not added.
- Collection count in this pull: 33 (vs. 34 in the 2026-08-03 baseline) — not chased, tangential.

## Fresh Atlas Advisor pull (2026-09-08, panel labels now "Drop Indexes" / "Create Indexes" — renamed from "Unused Indexes" / "Suggested Indexes")

- **Drop Indexes: 0 recommendations.** Directly contradicts the GITIN-1744 baseline's 16 confirmed-unused indexes (~145.2 MB, table above) — none currently flagged by live Atlas data. **The 16-index drop list is now stale — do not act on it.** Two possible explanations, not distinguished yet: (a) those indexes are genuinely being hit again (real usage), or (b) the usage-tracking window reset (node restart / new monitoring period) and hasn't accumulated enough "unused" history yet to re-flag them. Either way, current live signal says zero safe drops.
- **Create Indexes: 6 recommendations, full table pulled** (raw in `data/create-indexes-20260908.txt`), ranked by Atlas's own impact ordering:

| # | Collection | Suggested keys | Avg exec | Freq | Scanned/Returned | vs. M20 pull (2026-08-04) |
|---|---|---|---|---|---|---|
| 1 (Top) | `branches` | `alreadyClosedPediGrido:1, lastGetNews:1` | 120 ms | **19.04/hr** | 2318/3 | Same shape, 3rd consecutive pull. Frequency keeps climbing: 0.21/hr (M30) → 5.25/hr (M20) → 19.04/hr (now) — ~90x over 5 weeks. Genuine traffic growth, not sampling noise; impact quantified at 121.6 MB disk reads saved/exec. |
| 2 | `branches` | `alreadyClosedRappi:1, lastGetNews:1` | 118 ms | 4.58/hr | 782/1 | Was 1.46/hr in M20 pull — ~3x growth, consistent shape. |
| 3 | `ordertimes` | `latencyTimestamp.{finalResponseDate,platformDate,receiveSqsDate,responseDate,sendSqsDate,entryDate}:1` (6-field compound) | **2778 ms** | 0.04/hr | 384027/101 | Exec time jumped ~7x (393 ms M20 → 2778 ms now) while freq/returned held flat; docs scanned grew with collection (327,727 → 384,027, tracks doc-count growth 372,277 docs from today's `.stats()`). Consistently reproduced across 3 pulls — real, worsening access pattern. |
| 4 | `branches` | `address.country:1, alreadyClosedPeya:1, platforms.StateAPI:1, platforms.platform:1` | 110 ms | 0.5/hr | 1066/54 | Was 0.17/hr in M20 pull — ~3x growth, same shape across all 3 pulls. |
| 5 | `branches` | `address.country:1, alreadyClosedUber:1` | 156 ms | 0.38/hr | 935/4 | Was 0.29/hr in M20 pull — roughly flat. |
| 6 | `ordertimesavgcrons` | `avg_calculatedAt:1` | 141 ms | 0.04/hr | 42816/0 | Was 35,856/0 in M20 pull — docs-scanned tracks collection growth (43,056 docs from today's `.stats()`), **still always returns 0 rows after a full scan, now confirmed stable across 3 pulls over 5+ weeks** — strengthens the "dead/obsolete query, ask Dev before indexing" read rather than assuming it just needs an index. |

- **Two M20-era `branches` suggestions dropped off this list**: `address.country:1, alreadyClosedPediGrido:1` and `address.country:1, alreadyClosedRappi:1` are no longer surfaced (M20 pull had 8 total, now 6). Not investigated — could mean that query shape stopped occurring, or fell below Advisor's current sampling threshold. Not chased further, tangential to this ticket's add/drop deliverable.
- **Reconciles an open item:** the `branches.alreadyClosedPediGrido_1_lastGetNews_1` frequency-jump question (open item 4 in GITIN-1744) is resolved as a real, sustained trend, not a one-off artifact — it kept climbing across all 3 independent pulls (0.21 → 5.25 → 19.04/hr). Safe to treat the 121.6 MB impact estimate as credible.

## Open questions / next steps

1. ~~Fresh `$indexStats`/`.stats()` cluster-wide pull~~ — done 2026-09-08.
2. ~~Fresh Atlas Advisor pull (Drop + Create Indexes)~~ — done 2026-09-08, both panels captured above.
3. ~~Decision on re-adding `logerrors.createdAt_1`~~ — moot, collection is now empty (Graylog migration). Dropped.
4. ~~`branches.alreadyClosedPediGrido_1_lastGetNews_1` frequency-jump~~ — resolved, confirmed real sustained growth across 3 pulls.
5. ~~`ordertimes.branch_1` size discrepancy~~ — resolved.
6. **Decision needed from user:** the drop side of the deliverable is currently **empty** — live Atlas data shows 0 Drop Indexes recommendations, contradicting the aged 16-index/145 MB list from GITIN-1744. Confirm whether to (a) report "no drops recommended right now" as the ticket's conclusion on that side, or (b) treat the 16-index list as still worth a manual look given it's suspicious that all 16 flipped to "in use" at once (could indicate a monitoring-window reset rather than genuine usage — see explanation above, unresolved).
7. **Add-list ready to hand over** — the 6-index table above, pending user confirmation before writing the `createIndex` commands (production cluster, needs the destructive-command banner + explicit confirmation per repo policy). Suggest excluding #6 (`ordertimesavgcrons.avg_calculatedAt`) from the immediate batch and asking Dev first, since it consistently returns 0 rows — possible dead query, not clearly worth indexing.
8. Once the drop-side decision (item 6) is made, this ticket is ready to close with the paired add/drop list as its output artifact.

## Indexes applied (2026-09-08)

User created and verified (via `getIndexes()`, `data/verify-new-indexes-20260908.txt`) the 3 Tier-1 "really needed" indexes:
- `branches`: `{alreadyClosedPediGrido:1, lastGetNews:1}` ✅
- `branches`: `{address.country:1, alreadyClosedPeya:1, platforms.StateAPI:1, platforms.platform:1}` ✅
- `ordertimes`: `{latencyTimestamp.finalResponseDate:1, platformDate:1, receiveSqsDate:1, responseDate:1, sendSqsDate:1, entryDate:1}` ✅

Remaining from the recommended add-list, not yet applied:
- Tier 2: `branches.{alreadyClosedRappi:1, lastGetNews:1}`, `branches.{address.country:1, alreadyClosedUber:1}`
- Tier 3 (hold, ask Dev first): `ordertimesavgcrons.{avg_calculatedAt:1}` — always returns 0 docs, likely dead/obsolete query.

**Correction (2026-09-08):** initial PM/Ops drafts stated "no impact on order flow" from these 3 index creations — that was an unverified inference, not a checked outcome. Only `getIndexes()` was run to confirm the indexes exist; no CPU/cache/disk-IOPS check was done during or after the builds. This matters specifically because `branches` and `ordertimes` (>370K docs each) just had structural changes made while the cluster runs the downsized M20 tier from GITIN-1741 — the same tier that showed cache-pressure symptoms (CPU >30-35%, rising disk read IOPS) during its January trial. Both outbound emails corrected to recommend resource monitoring instead of claiming no impact.

## Data-gathering query

Same cluster-wide inventory query used in GITIN-1744 (per-collection `.stats()` + `$indexStats` with fallback to size-only on denial):

```js
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

Notes for running this:
- Paste back the full run in one block, not split by collection.
- If `$indexStats` is no longer denied (permissions may have changed since 2026-08-03), that upgrades this from a size-only inventory to a direct usage-ops source — flag it clearly if so, since it would supersede the Atlas Advisor UI workaround for future runs.
- For the Atlas Performance Advisor panels (Unused Indexes, Suggested Indexes) — these are UI-only, no query to hand over; ask the user to pull fresh screenshots/exports of both panels from the Atlas console for the `PedidosSmartfran` cluster.

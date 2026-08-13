# Investigation — 20260803_analisis-indices-mongodb

**Status:** paused for the full cluster-wide re-pull (target resume window ~2026-08-10 to 2026-08-17, to give Advisor's usage window fully clear of the M30→M20 cutover) — but a fresh Suggested Indexes pull came in 2026-08-04, confirmed by user to already reflect **M20** (not a mixed/transitional window), and is logged below as real M20 data, though still only ~1 day in.

**Why paused:** all data gathered so far (Unused Indexes, Suggested Indexes, size inventory) was captured while the cluster was still on M30, before the M20 downsize decided in `20260803_mongodb-downsize-m20` ([GITIN-1741](https://smartit-ar.atlassian.net/browse/GITIN-1741)) is rolled out and stabilized. Re-analyzing after 1-2 weeks on M20 gives: (1) Advisor's 7-day "unused" window fully inside the new tier rather than spanning the M30→M20 cutover, (2) a chance to see whether the smaller cache changes which indexes actually get exercised under real M20 query patterns, and (3) time for the M20 ticket's own post-downsize monitoring window to run its course first — no point acting on an index list that might need re-deriving anyway.

## Purpose

Full index inventory and usage analysis across the `PedidosSmartfran` MongoDB Atlas cluster (`us-east-1`, database `smartfran`), tracked as **[GITIN-1744](https://smartit-ar.atlassian.net/browse/GITIN-1744)**.

Follow-up to the secondary findings in `20260803_mongodb-downsize-m20` (see that investigation's H3 and "Hallazgos secundarios"): `branches` (~10x index-to-data ratio) and `logerrors` (~6.2x, before its secondary indexes were dropped mid-session) both showed index bloat far exceeding data size, and the M20 ticket flagged a need to confirm — with real `$indexStats` usage data, not inference — which indexes across the main collections are actually load-bearing before peak season. This ticket is that follow-up, scoped cluster-wide rather than to the two collections already sampled.

## Confirmed facts (carried over from `20260803_mongodb-downsize-m20`)

- `branches`: 7 indexes, `totalIndexSize` ≈ 43.8 MB vs. `dataSize` ≈ 4.35 MB (~10x). Two compound multikey indexes on the `platforms` array account for most of it (`alreadyClosedUber_1_lastGetNews_1` 11.6 MB, `alreadyClosedPeya_1_platforms.StateAPI_1_platforms.platform_1_lastGetNews_1` 33.6 MB). Not yet checked against `$indexStats` — redundancy is flagged, not confirmed.
- `logerrors`: had 5 indexes (`_id_`, `createdAt_1`, `updatedAt_-1`, `message_1_updatedAt_-1`, `message_1_createdAt_-1`) totaling ~1.16 GB before the 4 secondary indexes were dropped mid-session on 2026-08-03 (down to `_id_` only, ~906 MB freed). Dropped without confirming query-plan dependency first — this ticket's `$indexStats` pull is also the retroactive check for whether that was safe (though usage history since the drop won't show pre-drop ops counts; only forward-looking from here).
- `orders`: 13 indexes, `totalIndexSize` ≈ 115.81 MB vs. `dataSize` ≈ 1.41 GB (~8%, not disproportionate).
- `ordertimes`: 8 indexes, `totalIndexSize` ≈ 52.58 MB vs. `dataSize` ≈ 123.20 MB (~43%) — down from 220 MB in January per a cleanup policy; specific indexes not itemized.
- Whole-db (`db.stats()`, 2026-08-03, pre-`logerrors`-drop): 34 collections, 92 indexes, `indexSize` ≈ 648 MB total. **Flagged inconsistency, unresolved:** this is smaller than `logerrors`' own 1.16 GB of indexes captured in the same session — the two calls weren't verified against the same target/moment. Re-run cleanly as part of this ticket's data pull.
- **✅ Resolved — full 34-collection inventory pulled (2026-08-03).** `.stats()` succeeded everywhere; `$indexStats` was **denied on all 34 collections without exception** (`Unauthorized`, e.g. `activeSoftware`, `branches`, `logerrors`, `orders`, `news` all failed the same way) — this is a **full account-level restriction, not a per-collection gap**. Usage-ops data (`accesses.ops`/`accesses.since`) is not obtainable via this account at all; only size-based inventory is available going forward unless credentials change or an alternate method is found (see Open questions).
- **`news` and `deadletters` now pulled.** `deadletters`: 1,377 docs, `dataSize` 3.26 MB, `totalIndexSize` 0.06 MB (`_id_` only) — no bloat, nothing to flag. `news`: 360,510 docs, `dataSize` 886.17 MB, `totalIndexSize` 178.52 MB (~20%, not disproportionate like `branches`/`logerrors`), but 14 indexes — see redundancy pattern below.
- **Size-based redundancy candidates (key-prefix overlap), found across 3 collections — same shape as the `logerrors` pattern already flagged in the M20 ticket (standalone single-field index coexisting with a compound index that has that field as a prefix):**
  - `ordertimes` (8 indexes, 51.77 MB total): `order_-1` (9.39 MB) alongside `order_1_entryDate_-1` (9.31 MB); `platform_-1` (3.06 MB) alongside `platform_1_entryDate_-1` (3.09 MB). Same field, same near-identical size, twice.
  - `orders` (13 indexes, 112.04 MB total): three separate compounds all keyed off `internalCode_1` (`internalCode_1_originalId_-1`, `internalCode_1_order.id_1`, `internalCode_1_createdAt_-1`); `originalId_1` standalone (10.53 MB) alongside `order.originalId_1` standalone (2.93 MB) and `internalCode_1_originalId_-1` compound; `order.id_1` standalone alongside `internalCode_1_order.id_1` compound.
  - `news` (14 indexes, 178.52 MB total): `createdAt_-1` (6.98 MB) and `updatedAt_-1` (36.27 MB) both exist standalone *and* as suffixes/prefixes inside multiple `order.platformId_1_*` / `order.id_1_*` / `order.originalId_1_*` / `branchId_1_*` / `extraData.branch_1_*` compounds — six different compound indexes combining `order.platformId`/`order.id`/`order.originalId` pairwise in different orders.
  - `branches` — same two large multikey compounds already known from the M20 ticket (`alreadyClosedUber_1_lastGetNews_1` 10.63 MB, `alreadyClosedPeya_1_platforms.StateAPI_1_platforms.platform_1_lastGetNews_1` 30.83 MB — 98% of the collection's 42.11 MB index total), confirmed still present, unchanged in shape.
  - None of this is confirmable as *actually* redundant without query-pattern data — `$indexStats` denial (above) blocks the direct route. Flagged as candidates only.
- **Flagged, not chased (out of scope for this ticket):** `logerrors` now shows 178,486 docs / 89.99 MB data (down from 352,943 docs / 188 MB recorded mid-session in the M20 investigation, same day) while its single remaining `_id_` index is 247.86 MB — larger than the data it indexes. Something removed roughly half the documents between that session and this one; not investigated here since it's tangential to the index-audit purpose of this ticket, but worth a one-line mention if anyone revisits `logerrors` sizing.

## Atlas Performance Advisor pulls (2026-08-03) — real usage data, independent of the `$indexStats` block

Atlas's control-plane advisor surfaces usage-based recommendations without needing the blocked `mongosh` privilege — this is the option-2 fallback from the list above, and it worked. Two panels pulled: **Unused Indexes** and **Suggested (missing) Indexes**.

### Unused Indexes (7-day window)

16 indexes across 5 collections, confirmed unused for 7 days, **≈145.2 MB total**:

| Collection | Index | Size |
|---|---|---|
| `orderrejcloseds` | `send_1_newId_1_createdAt_1` | 1.16 MB |
| `openclosedlogs` | `timestampField_1` | 0.45 MB |
| `orders` | `internalCode_1_order.id_1` | 4.01 MB |
| `orders` | `order.originalId_1` | 3.09 MB |
| `orders` | `thirdParty_1` | 3.32 MB |
| `orders` | `internalCode_1_createdAt_-1` | 9.26 MB |
| `orders` | `updatedAt_-1` | 26.09 MB |
| `ordertimes` | `branch_1` | 46.1 MB |
| `ordertimes` | `platform_-1` | 3.16 MB |
| `ordertimes` | `order_1_entryDate_-1` | 9.31 MB |
| `ordertimes` | `platform_1_entryDate_-1` | 3.11 MB |
| `ordertimes` | `responseDate_1` | 2.98 MB |
| `news` | `extraData.branch_1_createdAt_-1` | 17.21 MB |
| `news` | `platformId_1` | 2.27 MB |
| `news` | `order.platformId_1_order.originalId_-1` | 11.07 MB |
| `news` | `plaformId_1_orderPickedUp_1` (note: `plaformId`, typo preserved from the actual field name) | 2.57 MB |

**Reconciling against the size/shape "candidates" flagged above — mixed results, usage data overrides guesses where they disagree:**
- Confirmed as guessed: `ordertimes.platform_-1` and `platform_1_entryDate_-1` (both unused — the whole `platform`-keyed pair is dead weight); `ordertimes.order_1_entryDate_-1` (unused); `orders.internalCode_1_createdAt_-1`; `news.order.platformId_1_order.originalId_-1`.
- **Guessed wrong:** `ordertimes.order_-1` is **not** on the unused list — it's in active use even though its compound sibling (`order_1_entryDate_-1`) isn't. `orders.internalCode_1_originalId_-1` and `orders.originalId_1`/`order.id_1` (standalone) are **not** flagged unused either — the "same-prefix implies redundant" heuristic didn't hold uniformly.
- **New finds, not previously flagged by shape:** `ordertimes.branch_1` (46.1 MB — the single largest unused index found, no compound counterpart, just outright unused), `orders.thirdParty_1`, `orders.order.originalId_1`, `orderrejcloseds.send_1_newId_1_createdAt_1`, `openclosedlogs.timestampField_1`, `news.extraData.branch_1_createdAt_-1`, `news.platformId_1`, `news.plaformId_1_orderPickedUp_1`.
- **`branches` — zero indexes flagged unused**, including the two large multikey compounds (`alreadyClosedUber_1_lastGetNews_1`, `alreadyClosedPeya_1_...`) that drove the "10x bloat" framing in the M20 ticket. **This matters: Atlas's own usage data says those two indexes are actively used, not dead weight** — the M20 ticket's H3 finding (`branches` over-indexed) stands as a size observation but should not be read as "safe to drop." See the Suggested Indexes section below — `branches` actually needs *more* indexing, not less.
- **Data-quality flag:** `ordertimes.branch_1` shows 46.1 MB here vs. 8.01 MB in the raw `.stats()`/`indexSizes` pull earlier this session — a ~5.7x discrepancy, unresolved. Possibly a different measurement basis (Advisor may report a cluster/replica-aggregate or a different size metric than the single-node `indexSizes` field). Don't trust either figure standalone for `ordertimes.branch_1` until reconciled; this also means "% of collection index size that's unused" math for `ordertimes` (which would otherwise imply more unused-index size than the collection's recorded total) shouldn't be quoted without flagging this gap.

### Suggested (missing) Indexes

Atlas also surfaces query patterns currently doing large collection scans that a new index would fix:

| Collection | Suggested index | Avg exec time | Freq | Docs scanned / returned |
|---|---|---|---|---|
| `logerrors` | `createdAt: 1` | **12,946 ms** | 0.04/hr | 352,943 / 174,457 |
| `ordertimes` | `latencyTimestamp.finalResponseDate/platformDate/receiveSqsDate/responseDate/sendSqsDate/entryDate` (all `1`) | 408 ms | 0.04/hr | 317,275 / 101 |
| `branches` | `alreadyClosedPediGrido: 1, lastGetNews: 1` | 41 ms | 0.21/hr | 2,304 / 4 |
| `branches` | `address.country: 1, alreadyClosedPeya: 1, platforms.StateAPI: 1, platforms.platform: 1` | 39 ms | 0.08/hr | 1,021 / 29 |
| `ordertimesavgcrons` | `avg_calculatedAt: 1` | 44 ms | 0.04/hr | 35,616 / 0 |

**Critical finding — `logerrors.createdAt: 1` directly confirms the unverified risk from the M20 ticket.** `createdAt_1` is one of the four `logerrors` secondary indexes dropped mid-session in `20260803_mongodb-downsize-m20` (that ticket's action item 4 flagged this as "no verificado contra patrones de query reales antes del drop"). It is now verified — and the answer is **it broke a real query path**: a query relying on `createdAt` now does a full collection scan (352,943 docs scanned, matching the pre-drop document count) averaging **~13 seconds** per execution. Low frequency (0.04/hr, ~once/day) but a genuine regression, not a hypothetical one. **Recommend re-adding `createdAt_1` to `logerrors`** regardless of what else this ticket concludes — this isn't a judgment call, it's restoring a query path that demonstrably broke.

**`branches` reframed:** combined with zero unused indexes above, these two suggestions mean `branches`' problem isn't excess indexing — it's *missing* coverage for query shapes the app added since the existing indexes were built (`alreadyClosedPediGrido` looks like a newer platform flag alongside the already-indexed `alreadyClosedUber`/`alreadyClosedPeya`; the `address.country`-led compound is a different access pattern than the existing `platforms.*`-led ones). Both current suggested-index queries near-fully scan the collection (2,304/2,346 and 1,021/2,346 docs) for low returns — worth adding, though frequency is low enough (0.08–0.21/hr) that this isn't urgent on its own.

**`ordertimes.latencyTimestamp.*` suggestion** — very low frequency (0.04/hr) but each execution scans 317,275 of ~337,833 docs to return 101; Atlas estimates up to 100.4 MB of disk reads avoided per addition. Worth adding given the collection is already under scrutiny for both bloat and (per `branch_1` above) at least one confirmed-unused index — this is a chance to net-neutral the change (drop `branch_1`, add the `latencyTimestamp` compound) rather than only adding.

**`ordertimesavgcrons.avg_calculatedAt`** — every execution (0.04/hr) scans the entire collection (35,616 docs) and returns 0 results. Worth adding for that reason alone, independent of frequency — a query that always returns nothing after a full scan is either a dead/obsolete query (worth asking Dev) or missing its index; either way it's low-risk to add.

### Suggested (missing) Indexes — M20 re-pull (2026-08-04, confirmed M20 by user, ~1 day post-downsize)

8 suggestions total ("Create Indexes8" panel header), vs. 5 in the M30 baseline above. Logged as a diff, not a replacement — the M30 table stays as the pre-downsize reference point.

| Collection | Suggested index | Avg exec time | Freq | Docs scanned / returned | vs. M30 |
|---|---|---|---|---|---|
| `branches` | `alreadyClosedPediGrido: 1, lastGetNews: 1` | 134 ms | **5.25/hr** | 2,305 / 2 | Same shape as M30's 0.21/hr entry — frequency ~25x higher, unreconciled. Now Atlas's **Top Suggestion**, quantified impact "up to 103.7 MB disk reads/execution" |
| `ordertimes` | `latencyTimestamp.*` (6 fields, same set) | 393 ms | 0.04/hr | 327,727 / 101 | Consistent with M30 (408 ms, 317,275/101) — same real access pattern, not noise |
| `branches` | `alreadyClosedRappi: 1, lastGetNews: 1` | 124 ms | 1.46/hr | 775 / 1 | New — not in M30 list |
| `branches` | `address.country: 1, alreadyClosedPediGrido: 1` | 144 ms | 0.13/hr | 2,348 / 9 | New combo — different from M30's `alreadyClosedPediGrido_1_lastGetNews_1` |
| `ordertimesavgcrons` | `avg_calculatedAt: 1` | 44 ms | 0.04/hr | 35,856 / 0 | Consistent with M30 (44 ms, 35,616/0) |
| `branches` | `address.country: 1, alreadyClosedUber: 1` | 208 ms | 0.29/hr | 973 / 4 | New |
| `branches` | `address.country: 1, alreadyClosedPeya: 1, platforms.StateAPI: 1, platforms.platform: 1` | 124 ms | 0.17/hr | 1,212 / 21 | Same shape as M30 (39 ms, 0.08/hr, 1,021/29) — present in both pulls |
| `branches` | `address.country: 1, alreadyClosedRappi: 1` | 159 ms | 0.04/hr | 775 / 1 | New |
| `logerrors` | `createdAt: 1` | — | — | — | **Absent from this pull.** At ~0.04/hr (once/day) in M30, this is far more likely a sampling-window gap in Advisor's rolling slow-query sample than evidence the regression resolved — the finding that this index is load-bearing is already independently confirmed (dropped-index doc count matched the drop event exactly). Recommendation to re-add stands unchanged. |

**Reading this diff:**
- `branches` suggestions expanded from 2 to 6, and now form a clean systematic pattern: a `<platformFlag>_1_lastGetNews_1` compound *and* an `address.country_1_<platformFlag>_1[...]` compound, one pair per platform flag (Uber, Peya, Rappi, PediGrido). This strengthens the working theory below — `branches` is missing coverage for query shapes added after its original indexes were built, not simply over-indexed.
- `ordertimes.latencyTimestamp.*` and `ordertimesavgcrons.avg_calculatedAt` are stable across both pulls (near-identical timing/scan/return numbers) — good signal these are real, consistent access patterns rather than one-off sampling noise.
- The ~25x frequency jump on the `branches` top suggestion (0.21/hr → 5.25/hr) is the one number here not yet explained — could be a genuine M20 traffic-pattern change, a difference in this pull's time-range filter vs. the M30 pull's, or something else. Not enough information yet to pick between those; don't quote the 103.7 MB/execution impact figure as validated until this is understood.

## Current working theory

The `branches`/`logerrors` index-bloat pattern that motivated this ticket is **not isolated** — `ordertimes`, `orders`, and `news` all show the same structural signature: standalone single-field indexes coexisting with compound indexes that share the same leading field, and usage data now confirms real (if partial) redundancy in that pattern (~145 MB genuinely unused, though not every size-based guess panned out). The bigger correction: this isn't purely a "too many indexes" problem. `logerrors` already proved that removing indexes without query verification breaks things, and `branches` shows the opposite failure mode — actively missing indexes for newer query shapes (`alreadyClosedPediGrido`, `address.country`-led lookups) causing near-full-collection scans. **The real deliverable here is a paired add/drop list, not just a drop list.**

## Ruled out

- Nothing ruled out yet.

## Open questions / next steps

**Resume checklist (once M20 has run ~1-2 weeks):**
- Re-pull Atlas Performance Advisor's Unused Indexes and Suggested Indexes panels fresh — do not reuse the M30-era tables above as final; treat them as a baseline to diff against, not the answer.
- Check whether the 16 unused indexes flagged under M30 are still unused under M20 (expected: yes, tier change doesn't affect query shape — but confirm rather than assume, per the same "size-based guesses were wrong for some" lesson from the first pass).
- Resolve the `ordertimes.branch_1` size discrepancy (46.1 MB Advisor vs. 8.01 MB `.stats()`) — still open, independent of the M20 wait.
- Re-add `logerrors.createdAt_1` remains a standalone recommendation, not contingent on the M20 wait — the regression it fixes is real today, not something the downsize changes. Still not actioned; confirm with user before running the write command whenever they're ready, doesn't need to wait for the 1-2 week window.


- ~~Run the full-cluster index inventory query~~ — done, full size-based inventory captured above.
- ~~Itemize `ordertimes`'s indexes~~ / ~~pull `news` and `deadletters`~~ — done, see above.
- ~~`$indexStats` blocked — find an alternate usage-data source~~ — resolved via Atlas Performance Advisor (Unused Indexes + Suggested Indexes panels), no credential change needed.
- ~~Confirm whether the `logerrors` indexes dropped mid-session in the M20 ticket broke any query path~~ — **confirmed yes**, `createdAt_1` was load-bearing; see critical finding above. This resolves `20260803_mongodb-downsize-m20` action item 4 ([GITIN-1741](https://smartit-ar.atlassian.net/browse/GITIN-1741)) — referenced here by link per event-scope isolation, not appended into that ticket's own log since this finding belongs to this ticket ([GITIN-1744](https://smartit-ar.atlassian.net/browse/GITIN-1744)).
- **Decision needed:** re-add `logerrors.createdAt_1` — recommended regardless of downsize outcome, given the confirmed ~13s-query regression. Not yet actioned; ask user before running any index-creation command (write operation on prod cluster).
- **Draft the paired add/drop list as this ticket's actual output:** drop candidates = the 16 confirmed-unused indexes (~145.2 MB, table above, minus `ordertimes.branch_1` pending the size-discrepancy resolution below); add candidates = the 5 suggested indexes (table above), with `logerrors.createdAt_1` prioritized separately as a regression fix rather than an optimization.
- **Unresolved: `ordertimes.branch_1` size discrepancy** (46.1 MB Advisor vs. 8.01 MB `.stats()`) — reconcile before finalizing the drop list total or treating this as the single biggest win; don't drop based on the larger figure until it's understood.
- Before dropping any of the 16 unused indexes: same caution as `logerrors` — confirm the 7-day "unused" window isn't itself an artifact of the periodic node-restart pattern already observed in the M20 investigation (if Advisor's usage tracking resets on failover/restart like raw `$indexStats` accesses do, 7 days of "unused" could just mean "unused since the last restart," not truly dead). Not confirmed either way; worth one clarifying check (e.g. does Advisor's window predate the most recent visible restart marker) before treating the list as final.
- `logerrors` doc-count drop (352,943 → 178,486 docs, same day) — flagged above, not chased; revisit only if `logerrors` sizing becomes relevant again.
- Re-run `db.stats()` cleanly to resolve the flagged indexSize inconsistency noted in the M20 investigation, if still needed once the redundancy analysis is done.
- **New (2026-08-04):** reconcile the ~25x frequency jump on `branches.alreadyClosedPediGrido_1_lastGetNews_1` (0.21/hr M30 → 5.25/hr M20 pull) before quoting Atlas's "103.7 MB disk reads/execution" impact figure as validated — check whether the two pulls used the same time-range filter before concluding this is a real M20 traffic change.
- **New (2026-08-04):** `branches` now has 6 suggested indexes (up from 2), one `lastGetNews`-paired and one `address.country`-led compound per platform flag (Uber, Peya, Rappi, PediGrido) — the paired add-list for `branches` should include all 6 if the pattern holds through the full resume-window re-pull, not just the original 2.

## Data-gathering query

Cluster-wide index inventory: for every collection, size per index (from `.stats()`) plus usage counters (from `$indexStats`, ops count and since-date per index — the key signal for "is this index actually used"). Single paste-back covers the whole database in one pass. Each collection is wrapped in its own try/catch so a permission denial on one doesn't abort the rest:

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
- **Confirmed 2026-08-03:** the app-scoped credentials in use can run `.stats()` on all collections but are **not authorized for `$indexStats` on at least some collections** (`activeSoftware` denied). Scope of the restriction (all collections vs. a subset) not yet known — this run will show which. Falls back to size-only (from `indexSizes`, already present in `.stats()` output) when denied, so the run still completes and size data isn't lost even where usage counters are unavailable.
- Where `$indexStats` *is* authorized: `accesses.ops` and `accesses.since` are **per-node, reset on restart** — given the periodic-restart pattern already observed in the M20 investigation's RAM chart, ops counts reflect usage only since the last restart of whichever node `mongosh` is connected to, not lifetime usage.
- Output is per-collection; paste back the full run in one block rather than splitting by collection.

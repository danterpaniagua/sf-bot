# Investigation — 20260917_gitin2062_branches_index

**Jira:** [GITIN-2062](https://smartit-ar.atlassian.net/browse/GITIN-2062) — "[SP] Índice en smartfran.branches"

**Status:** converged for the Rappi index (applied and confirmed live); Uber index still open, not yet applied.

## Origin

Surfaced during [GITIN-2013](https://smartit-ar.atlassian.net/browse/GITIN-2013) (`smartpedidos/events/20260908_gitin2013-query-insights-slow-queries/`), a fresh Atlas Performance Advisor pull on 2026-09-16 flagged two missing indexes on `smartfran.branches`, continuing an already-established pattern from `GITIN-1744`/`GITIN-2006`: `branches` isn't over-indexed, it's missing coverage for new platform-specific query flags (`alreadyClosedX`/`lastGetNews`) as new platform integrations ship. PediGrido/Peya were already fixed under `GITIN-2006`; this ticket covers the next two platforms, Rappi and Uber.

## Confirmed facts

**Suggestion 1 — `{alreadyClosedRappi: 1, lastGetNews: 1}` — applied.**
- Atlas metrics (2026-09-16 pull): 66ms avg, 4.5/hr, 782 docs scanned → 1 returned. A follow-up pull just before applying (2026-09-17) showed frequency had risen to **15.08/hr** — over 3x higher in roughly a day.
- **Source traced to real, functioning application code**, not an edge case: `checkOfflinePOSrappi()` (`dev-src-smartPedidos-concentradorService/api/src/controllers/branch.js:448`) — a POS-heartbeat monitor. Finds branches whose `lastGetNews` (last poll/heartbeat) has gone stale (>3 min) among active-Rappi branches and auto-closes them via Rappi's disable-store API, so orders stop routing to a dead terminal; reopens them once polling resumes.
- **Runs every minute** via in-process `node-cron` (`scheduleRappiOffline = '*/1 * * * *'`, `branch.js:1746,1770`) — not a rare job. Atlas's `4.5/hr`→`15.08/hr` figures are not the invocation rate (1,440/day); they reflect only the subset of runs that hit the slow-scan pattern.
- **Applied 2026-09-17 via the Atlas UI** (Performance Advisor's own "Create Index" action, not a manual `createIndex` command). Confirmed live: `db.branches.getIndexes().length` went from 9 to 10.
- Each platform (`Uber`, `Peya`, `PediGrido`, `Rappi`) has an analogous field pair on `branches` — the same `checkOfflinePOS<Platform>()` pattern almost certainly exists per platform in source, though only Rappi's specific function was directly confirmed this session.

**CORRECTION (2026-09-17) — the applied index is not actually used by the real query.** `explain("executionStats")` against the real 3-condition `checkOfflinePOSrappi()` query (`platforms.$elemMatch({platform: rappiId, isActive: true})` + `lastGetNews` + `alreadyClosedRappi`) shows the winning plan uses the **pre-existing** `platforms.platform_1_platforms.branchReference_1` index — `alreadyClosedRappi_1_lastGetNews_1` (the one applied 2026-09-17) appears only in `rejectedPlans`. Query planner reasoning: `platforms.platform` is highly selective (exact `ObjectId` match), while `alreadyClosedRappi` has poor selectivity as a leading field (only `null`/`true`/`false`). Real execution: **7ms**, 782 keys / 738 docs examined, 202 returned — already fast using the existing index. Atlas's suggestion was evidently modeled on a narrower 2-field query shape that doesn't match how the real application calls it (no `platforms` filter in Atlas's captured sample).

**Net effect: the applied index is currently unused — real write cost, zero query benefit for this code path.** Not yet decided whether to drop it (worth a quick grep first for any other code path querying `branches` on just `alreadyClosedRappi`/`lastGetNews` without a platform filter, in case Atlas's sample came from somewhere else entirely, e.g. an admin/reporting query not yet found).

**Suggestion 2 — `{"address.country": 1, alreadyClosedUber: 1}` — traced, verified via `explain()`, decided against applying for now.**
- **Traced to source (2026-09-17):** not `checkOfflinePOSuber()` (which uses the same 3-condition shape as Rappi's cron: `platforms.$elemMatch` + `lastGetNews` + `alreadyClosedUber`, runs every minute). The actual match is `sendStatusUberEats(country)` (`branch.js:2298`), a **per-country, per-configured-check-in-time cron** (dynamically scheduled from `platforms.checkIns` in the DB via `sincroCheckIns()`, `branch.js:1861`) — filters `platforms.$elemMatch` + `address.country` + `alreadyClosedUber`, no `lastGetNews` at all.
- **`explain("executionStats")` against the real query** (Uber, Argentina): winning plan uses the **pre-existing** `alreadyClosedUber_1_lastGetNews_1` index (already in the cluster before this session, missed in the earlier inventory review) — but poorly: 1,047 keys/docs examined → 66 returned (~6% selectivity), **187ms**. Neither existing index serves this query well, unlike the Rappi case.
- **Impact quantified, then decided against applying:** frequency is only `0.17/hr` (≈4 executions/day total, not continuous like Rappi). Aggregate cluster-wide cost today: `187ms × 0.17/hr ≈ 32ms/hour`, under 1 second/day. Best-case savings from the new index: also under 1 second/day. **Decision (2026-09-17, user): do not apply — negligible aggregate impact, and the cluster runs on Atlas M20 (limited RAM/resources), where an index's storage/write-amplification cost isn't justified for this little benefit.** Different reasoning than the Rappi case (which was skipped because it wasn't used at all) — here the index would likely work as intended, it's just not worth the M20-tier cost for the volume involved.

## Current working theory

Each platform integration (Rappi, Uber, Peya, PediGrido, and presumably future ones) ships its own POS-heartbeat-monitor cron following the same `alreadyClosedX`/`lastGetNews` (or `address.country`/`alreadyClosedX`) query shape, and none of them get an index at integration time — Atlas only surfaces the gap weeks later once real traffic accumulates. This is a recurring structural pattern, not a one-off oversight each time.

## Ruled out

- `branches` being over-indexed (the original `GITIN-1744` hypothesis) — confirmed wrong; the problem is consistently missing coverage, not excess.

## Open questions / next steps

1. ~~Apply the Uber index~~ — **decided against, for now** (2026-09-17). Verified it would likely work, but negligible impact (<1s/day) doesn't justify the cost on an M20 cluster. Revisit if `sendStatusUberEats`'s frequency or per-call cost changes materially (e.g., more countries/check-in slots added, or cluster tier upgraded).
2. ~~Trace the Uber suggestion to its actual source function~~ — done, see above (`sendStatusUberEats`, not `checkOfflinePOSuber`).
3. Consider whether this recurring pattern (new platform → missing index → weeks-later Advisor discovery) warrants a standing checklist item for future platform integrations, rather than being caught reactively each time — a broader process question, not just a per-index fix.
4. **New, broader pattern worth tracking**: this ticket found *two* different index-decision outcomes from what looked like the same class of suggestion — Rappi's (verified unused, skip) and Uber's (verified would work, skip anyway for cost/benefit on M20). Both required tracing past the field names alone to the real query and cluster tier before deciding — Atlas's suggestion text alone was insufficient evidence in both cases.

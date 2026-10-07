# Investigation: [SML] Spike CPU Loyalty

**Jira:** [GITIN-2087](https://smartit-ar.atlassian.net/browse/GITIN-2087)

## Status

**Converged — ops.md written 2026-09-23.** Original lead confirmed: this is the same `ASYNC_NETWORK_IO`/WebService-v1-LINQ mechanism first flagged in `events/20260518_cpu_spikes/` (evento E2, never ticketed then), now recurring fleet-wide (all 3 WEBS hosts, not just one) and root-caused to source-code level (`PromotionService.QueryPromotionApply`). See sections below for the full chain. Other prior CPU-spike folders checked for a repeat pattern at the time: `events/20260530_cpu_spikes/`, `events/20260715_cpu_spikes/`, `events/20260727_cpu_peaks_loadtest/`, `events/20260803_cpu_peaks_loadtest/`, `events/20260920_cpu-spikes/` (that last one's root cause was unrelated — `Query101`'s `OR`/`LOWER()` pattern — Dev fix still pending there per its own `ops.md`).

## Confirmed (2026-09-22)

**New occurrence, not the old ticket** — user confirmed: spike happened 2026-09-21, ~17:00 UTC-3 (= ~20:00 UTC, server timezone is GMT per project convention). User independently described it as "wsv1 spike, SOAP" — matching the signature of the old, never-ticketed `ASYNC_NETWORK_IO`/`SFCG-WEBS-03` finding from `events/20260518_cpu_spikes/` (E2, 2026-05-18), but this is a fresh event, not that one. Possible recurrence of the same underlying pattern — not yet confirmed.

## Confirmed recurrence (2026-09-22)

**`ASYNC_NETWORK_IO` confirmed as the dominant pattern, now fleet-wide.** Aggregate of `PNSSRL_AuditSysprocesses` for 2026-09-21 19:30-20:30 UTC (`data/webs_asyncnetworkio_20260921.txt`): `ASYNC_NETWORK_IO` totals ~101,717 CPU across **all three** WebService hosts (WEBS-01, 02, and 03) — broader than the original 2026-05-18 finding, which only implicated WEBS-03. Next-largest contributor (`SOS_WORK_DISPATCHER`, WEBS-02, 26053) is much smaller by comparison.

One sample row (WEBS-03, `suspended`, cpu=10053) confirms an EF/LINQ-generated query against what appears to be `Sml.Promotion` (fields: `ValidSinceDate`, `ValidToDate`, weekday flags, `ExclusiveWeb`, `ExclusiveApp`, `ConsumptionLimitType`) — same mechanism as before (client not consuming result rows fast enough) and similar query shape (LINQ-generated, moderately large result set), not yet confirmed as the exact same query across all matched sessions.

## Confirmed root cause (2026-09-23, via `events/20260922_cpu_spike_mobile_requests/`)

A separate same-signature spike the following night (2026-09-22, unticketed at the time — investigating a "high mobile requests" hypothesis, since ruled out) isolated the exact two recurring queries and traced them to source:

1. **`Sml.Promotion` full-catalog pull** — `Core/Domain/Domain/PromotionContext/PromotionService.cs:3089-3098`, `SpecPromotionByAvailable()`, invoked via `QueryPromotionApply(int pageIndex, int pageSize, ...)` (`PromotionService.cs:1606`). That method takes real paging parameters, but when called with `preFiltredPromotions=false` it deliberately skips them (comment references a historical ticket `SML-6455`, trading correctness for performance) and instead does an in-memory filter pass (`AddMultipleFilterInfo`) over the full unpaginated result — this is the source of the unbounded fetch.
2. **`Sml.Article`/`Sml.Product` (`ForSale=1`) full-catalog pull** — traced to `ProductApplicationService.GetAllProduct()` (`Core/Application/Service/ProductContext/ProductApplicationService.cs:149`) → `ProductService.GetAllProduct()`. Exact inherited LINQ predicate not pinned down (likely a generic base-repository `GetAll`), lower confidence than finding #1.

**Fix is code-level, not infra-level**: either pass `preFiltredPromotions=true` for this call site (accepting whatever perf tradeoff the original `SML-6455` change was avoding), or push the extra business-rule filtering into the SQL query itself instead of an in-memory pass — same pattern already used elsewhere in `PromotionService.cs` (the `_specByCountry` cache).

Confirmed via CPU-delta breakdown that the mobile-requests hypothesis tested that night was **not** the driver — Mobile accounted for ~1.3% of total CPU delta despite the highest session count of any host. Not relevant to GITIN-2087 itself, recorded here only to close out that this ticket's queries are confirmed unrelated to mobile traffic.

## Proposed fix (for Dev — not yet implemented, needs Dev verification of details marked below)

**The problem, precisely:** `QueryPromotionApply(pageIndex, pageSize, sortInfo, filterInfo, preFiltredPromotions)` (`PromotionService.cs:1606`) already calls `this.ViewPromotions.Query(pageIndex, pageSize, ...)` with real paging parameters at line 1621 — so pagination is *structurally* available at this call site. The actual unbounded fetch (`OFFSET 0 ROWS FETCH NEXT 2147483647 ROWS ONLY` in the captured SQL) must come from how this method is being **invoked** for the affected call site (i.e., whatever caller passes `preFiltredPromotions=false` is likely also passing an effectively-unbounded `pageSize`, or `AddMultipleFilterInfo`'s 3-argument overload — called only in the `!preFiltredPromotions` branch, taking the already-paginated `promotions` as input — internally does its own additional unpaginated fetch to compute `result` before filtering). **Not independently confirmed**: the body of `AddMultipleFilterInfo`, and the exact `pageSize` value the affected caller passes — both need a direct code read before implementing either option below.

**Confirmed 2026-09-23 (`data/query_fix_validation_20260923.txt`) — Option A does NOT reduce database-side cost.** Tested the captured query's `WHERE` predicate against real production data (`SmartFran.Solution.SmartLoyalty`), unpaginated vs. `OFFSET 0 ROWS FETCH NEXT 50 ROWS ONLY`: **identical logical reads (875) and elapsed time in both cases.** This is expected SQL Server behavior, not a test artifact: `ROW_NUMBER() OVER (ORDER BY Id)` requires materializing and sorting the *entire* matching set before `OFFSET`/`FETCH` can window it — pagination this way only trims what's returned to the client, not what SQL Server scans/reads. Same lesson as the `GITIN-2074` precedent already documented in `loyalty-dba-investigation` (an index alone didn't help while the query's shape stayed the same).

Only 1 row matched in this live test — much smaller than the row count implied by the original spike's CPU numbers (promotions are time-bound, so today's live row count isn't representative of 2026-09-21/22's). This validates the *mechanism* (pagination doesn't reduce reads for this query shape) but not the *magnitude* of any improvement at the row count actually present during the real spikes.

**Option A — flip `preFiltredPromotions` to `true` for the affected call site.** Still likely helps the *specific symptom observed* (`ASYNC_NETWORK_IO` — the client not draining a large result set fast enough; fewer rows returned means less time spent in that wait state), but **confirmed not to reduce the underlying CPU/logical-reads load on `SFCG-DB01`** per the test above. A partial fix at best — treats the symptom (network wait), not the query's actual scan cost.

**Option B — push the extra business-rule filtering (`AddMultipleFilterInfo`) into the SQL specification itself** rather than as a second in-memory pass over an unpaginated result — same restructuring pattern already used elsewhere in this file for a similar cost problem (see `GetCachedPromotionSpecByCountry`'s `Specification<Promotion>`-based approach, `PromotionService.cs:1647`). This is the option that would actually reduce `SFCG-DB01`'s CPU/IO load, since it addresses the scan itself rather than just the row count returned.

**Revised recommendation:** Option A alone is not sufficient to resolve the CPU-spike root cause — it may reduce `ASYNC_NETWORK_IO` duration but leaves the actual database cost unchanged. Option B is the real fix; Option A could still be applied as an interim mitigation for the network-wait symptom specifically, but should not be presented to Dev as "the fix" for the CPU spike itself.

## `AddMultipleFilterInfo` traced (2026-09-23) — more complex than assumed, real call site unconfirmed

Read the actual method body (`PromotionService.cs:2506-2600`). It is **not** a simple location check (retracting the earlier `PromotionApplyLocation` illustration used above) — it's a franchise/branch-office/region resolution chain, only active when `filterInfo` already contains one of `CityFilter`/`CountryFilter`/`FilterState`/`RegionFilter`/`FranchiseGroupFilter`/`BrancheOfficeFilter`/`FranchiseGroupIdLogged`. If none of those are present, it returns an **empty list** immediately (line 2599).

**Open contradiction, not yet resolved:** in `QueryPromotionApply`'s `!preFiltredPromotions` branch, `promotions.Where(x => result.Contains(x.Id))` against an empty `result` would filter out every promotion — but the captured production trace clearly returned real rows with no location-filter parameters visible (only `@p0 bit`, `@p1 datetime2`). Two possible explanations, neither confirmed: (a) the real caller for the captured spike always supplies a location filter that just wasn't visible in the captured parameter list, or (b) the captured spike isn't from `QueryPromotionApply` at all — `AddMultipleFilterInfo` is called from **14 different sites** in this file (lines 979, 1088, 1206, 1334, 1414, 1496, 1578, 1616, 1630, 1729, 1756, 1860, 1894, 2005), any of which could be the real origin.

**Confirmed real anchor table** (via a direct comment in `Front/WebSite/Controllers/PromotionController.cs:2971`, referencing this exact method): `SmlSupp.PromotionBranchOffice`. Real scale, confirmed 2026-09-23 (`data/promotionbranchoffice_scale_20260923.txt`): **24,978,810 rows**, 17,611 distinct promotions, 2,481 distinct branch offices (~1,418 rows/promotion on average). Any unindexed or poorly-selective query against this table would be independently expensive, regardless of the `Sml.Promotion` full-fetch issue already confirmed above.

**Not yet done, needed before a confident fix proposal:** trace `GetPromotionIdListFiltered` (line 2585, the actual per-filter-type resolver against `SmlSupp.PromotionBranchOffice`/`FranchiseService.QueryBranchOffice`), and confirm which of the 14 `AddMultipleFilterInfo` call sites actually produced the captured spike's trace. Until then, the Option A/B analysis above should be treated as applying to `QueryPromotionApply` specifically, not confirmed as the definitive call path for the observed CPU spike.

## Next steps

1. ~~Confirm whether the same query (or a small set of related LINQ queries) is behind all the `ASYNC_NETWORK_IO` sessions across all 3 hosts~~ — **done**, see above.
2. ~~Check WebService v1 source for the actual LINQ query and its result-set/timeout configuration~~ — **done**, see above. Note: the responsible code (`PromotionService.cs`) is shared between WebService v1 (OnPrem) and WebServiceV2 (Cloud) — a fix likely benefits both, not independently confirmed for WebServiceV2's own call sites.
3. Confirm whether this is a recurring daily/periodic pattern or a one-off — check other recent days for the same `ASYNC_NETWORK_IO` signature on these hosts. Two consecutive nights (2026-09-21, 2026-09-22) with the same signature is suggestive but not yet confirmed as a stable daily pattern.
4. Hand off the code-level fix (item 1 above) to Dev — not something SRE can remediate directly.

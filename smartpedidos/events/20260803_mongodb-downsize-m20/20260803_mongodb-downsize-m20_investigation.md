# Investigation — 20260803_mongodb-downsize-m20

**Status:** converged — decision: proceed with M20 downsize, monitored rollout with defined rollback triggers (see `20260803_mongodb-downsize-m20_ops-events.md` and `20260803_mongodb-downsize-m20_email-ops.md`)

## Purpose

Assess feasibility of downsizing the `PedidosSmartfran` MongoDB Atlas cluster (`us-east-1`, database `smartfran`) to tier **M20**. Goal is a go/no-go recommendation backed by current utilization data, not a guess.

## Confirmed facts

- Cluster identity confirmed from `smartpedidos/docs/infrastructure.md`: `PedidosSmartfran`, `us-east-1`, database `smartfran`.
- Key collections: `orders`, `news`, `logerrors`, `deadletters`, `branches`, `chains`, `platforms`, `newsStates`, `newsTypes`, `configs`.
- **Current tier not yet known** — infrastructure.md does not document it. This is the first blocking unknown.
- **2026-08-03: the mongosh credentials in use lack admin-db privileges.** `db.serverStatus()` and `rs.status()`/`replSetGetStatus` both returned `Unauthorized on admin`. This account is scoped to specific app databases, not cluster-wide admin commands. **Consequence: connection counts, replica topology, and any admin-level server metric cannot be pulled via mongosh with this account — must come from Atlas UI/API (Metrics tab or `atlas clusters metrics processes`) instead.** Not worth escalating credentials just for this investigation.
- **`smartfran.logerrors` collection stats (`db.logerrors.stats()`, 2026-08-03):** 352,943 docs, avgObjSize 533B → data size ≈ 188 MB. `totalIndexSize` ≈ 1.16 GB — **6.2x the data size**, across 5 indexes (`_id_` 260MB, `createdAt_1` 194MB, `updatedAt_-1` 195MB, `message_1_updatedAt_-1` 257MB, `message_1_createdAt_-1` 260MB). `totalSize` ≈ 2.33 GB for this collection alone. Not sharded.
- **No TTL index observed on `logerrors`** — consistent with the unbounded-growth risk flagged when the investigation was opened. Not confirmed as unbounded yet (would need to check for app-level pruning), but no index-based expiry exists.
- **Possible index redundancy on `logerrors`** (flagged, not confirmed): `createdAt_1` and `updatedAt_-1` exist as standalone single-field indexes *alongside* compound `message_1_createdAt_-1` and `message_1_updatedAt_-1`. If application queries always filter by `message` first, the two single-field indexes may be largely redundant with prefixes of the compound ones — would need actual query patterns (`$indexStats` or profiler) to confirm before recommending a drop. Tangential to the downsize question itself but relevant to the storage/cache-pressure numbers below.
- **`smartfran.branches` collection stats (`db.branches.stats()`, 2026-08-03):** only 2,346 docs, avgObjSize 1945B → data size ≈ 4.35 MB, `storageSize` ≈ 2.94 MB. But `totalIndexSize` ≈ 43.8 MB — **~10x the data size** — across 7 indexes, almost entirely from two compound indexes: `alreadyClosedUber_1_lastGetNews_1` (11.6 MB) and `alreadyClosedPeya_1_platforms.StateAPI_1_platforms.platform_1_lastGetNews_1` (33.6 MB). `platforms` is an array field, so these are multikey compound indexes — one 33.6MB index for 2,346 documents (~14KB of index per doc) is disproportionate and consistent with either high per-document array fan-out or a high-cardinality field (`lastGetNews`, a timestamp) inside a multikey compound index, both of which bloat multikey index size fast.
- **`branches` is a very hot write target relative to its size.** Same `.stats()` call's WiredTiger cache block: `'modify calls': 47,506,701` against only 2,346 documents (~20,250 modifies/doc on average, cumulative since last restart), `'history store table insert calls': 32,278,397`, `'pages requested from the cache': 1,227,207,085`, `'checkpoint blocked page eviction': 55,877`. This collection is small but under sustained heavy write churn — plausible driver: `alreadyClosedUber`/`alreadyClosedPeya`/`lastGetNews` fields updating on every platform poll cycle per branch (matches the open/close scheduling role described in `smartpedidos/CLAUDE.md`). **Directly relevant to the downsize decision**, unlike the index-redundancy note above: sustained write IOPS + WT history-store/eviction pressure from a hot small collection can matter more on M20's standard (non-provisioned) IOPS ceiling than raw data size does. Not yet compared against actual IOPS numbers — still need Atlas Metrics for that.
- **Two collections now, same pattern:** `logerrors` (6.2x) and `branches` (~10x) both show index size far exceeding data size. Worth watching whether this repeats across `orders`/`news` too — if so it's a cluster-wide indexing pattern, not a one-off, and matters more for the cache-pressure argument below.
- **`db.stats()` (whole `smartfran` db, 2026-08-03):** 34 collections, 1,814,246 objects, `dataSize` ≈ 2.71 GB, `storageSize` ≈ 1.96 GB (compressed), 92 indexes totaling `indexSize` ≈ 648 MB, `totalSize` ≈ 2.60 GB.
- **Premise flag (opened above) now resolved and closed:** `fsTotalSize` ≈ 10 GB was **not** a tier signal — confirmed tier (below) is M30, whose default disk would be larger. The 10 GB disk is a deliberate manual allocation sized to actual data need (~2.7 GB), unrelated to compute tier. No longer an open risk.
- **✅ Current tier confirmed (Atlas UI cluster overview, 2026-08-03): M30 (General), MongoDB 7.0.39, `us-east-1`, Type = "Replica Set - 3 nodes" (not sharded — sharding disqualifier ruled out), backups active.** M30 spec: 2 vCPU / 8 GB RAM, WT cache ≈ 3.5 GB. M20 spec: 2 vCPU / 4 GB RAM, WT cache ≈ 1.5 GB — **same vCPU count, cache roughly halved**. This is a genuine downsize question now, confirmed, not a wrong-premise situation.
- **Working-set-vs-cache math, first pass:** whole-db `dataSize` (2.71 GB) + `indexSize` (648 MB) ≈ **3.36 GB total** — already over 2x M20's ~1.5 GB cache ceiling, and that's the *entire* dataset, not even isolating the actively "hot" fraction. Under current M30 (~3.5 GB cache) nearly everything fits in cache today; under M20 more than half would not, forcing steady-state disk reads on cache misses. Combined with the write-churn pressure already observed on `branches` and the index bloat on `branches`/`logerrors` *at the current, larger cache size*, downsizing looks like it would tighten an already-present pressure point rather than move into new territory.
- **✅ DECIDING FINDING — Atlas Metrics, RAM, 4-week window (07/06–08/03), all 3 replica set members:**

  | Replica | Min (MB) | Max (MB) | Avg (MB) | Current (MB) |
  |---|---|---|---|---|
  | 1 | 1,367 | 3,108 | 2,184 | 2,456 |
  | 2 | 1,278 | 3,776 | 2,841 | 3,473 |
  | 3 | 1,386 | 3,830 | 2,692 | 2,488 |

  M20's **total** RAM is 4,096 MB. Peak observed usage (replica 3: 3,830 MB; replica 2: 3,776 MB) is **93–94% of M20's entire node RAM** — not the ~1.5 GB WT cache slice, the whole node, before OS/driver/connection overhead is even subtracted. Average usage (2,184–2,841 MB) already sits at **53–69% of M20's total RAM**. This confirms the working-set-math concern above with real utilization data, not just dataset-size inference: **the current workload does not fit inside M20 with any meaningful safety margin, most of the time, on 2 of 3 nodes.**

## Recommendation (superseded — see "Real tension surfaced" section near the end of this file)

**Original call: no-go on M20.** This was based on two independent data points that agreed with each other at the time:

1. **A real production test was already run and reverted** (2026-01-19 → 2026-01-21): M20 visibly capped RAM at ~1,300–1,500 MB (a ceiling, not organic demand) versus M30 freely using 2,000–3,500 MB once reverted. A formal keep-M30 recommendation was already sent to stakeholders on this basis.
2. **Today's independent 4-week RAM metrics** (2026-08-03) show current M30 usage peaking at 3,776–3,830 MB — in the same range as January's post-revert M30 usage, and well above what M20 physically has to offer (4,096 MB total, before OS/driver/connection overhead).

Nothing in the current dataset suggests conditions have improved enough to revisit this. One relevant change since January: `ordertimes`' index size dropped from 220 MB to 52.58 MB, suggesting a cleanup policy was implemented for the specific growth risk January called out — but overall RAM usage today is still in the same band that caused the January revert, so that cleanup hasn't been enough to change the answer on its own.

If cost reduction is the actual driver, the more promising lever remains the index bloat flagged on `branches` (~10x data size) and `logerrors` (~6.2x data size) — untested here, and would need before/after RAM measurement to know if it moves the needle enough to make M20 viable. Absent that, **keep M30** — same conclusion as January, now with a second independent confirmation.
- **Atlas UI "Collections" tab, per-collection breakdown (2026-08-03, partial — alphabetically `n` onward):** `orders` is the largest by far — 497.14 MB storage / 1.41 GB data / 395K docs / 13 indexes / 115.81 MB total index size (~8% of data, not disproportionate, unlike `logerrors`/`branches`). `ordertimes` — 53.96 MB storage / 123.20 MB data / 371K docs / 8 indexes / 52.58 MB index (~43% of data). `openclosedlogs` — 27.77 MB storage / 122.04 MB data / 64K docs / 3 indexes / 2.64 MB index (small ratio, fine). Remaining collections in this batch (`newsTypes`, `orderTelemetry`, `orderrejcloseds`, `ordersFaileds`, `ordertimesavgcrons`, `platforms`, `platformsHistory`, `recoveries`, `regions`, `rejectedMessages`, `rejectpeyas`, `releases`, `tokenmercadopagos`, `ubercheckorders`, `users`) are all small (sub-20MB storage), not relevant to sizing. No tier/sharding info in this view — that's on the cluster overview page, not Collections tab.

## M20 tier reference (Atlas dedicated, general-purpose)

- 2 vCPU, 4 GB RAM
- WiredTiger cache ≈ 1.5 GB (50% of RAM minus 1 GB overhead, standard Atlas default formula) — this is the real ceiling, not the 4 GB headline number. **Note:** the 2026-01-22 internal email (see below) states WT reserves 25% of RAM, giving ≈1 GB for M20/≈2 GB for M30 — lower than the 50%-minus-1GB formula used here. Discrepancy not resolved; doesn't change the directional conclusion either way, both formulas agree M20's cache is roughly half of M30's.
- Standard IOPS (non-NVMe), storage range roughly 10–256 GB depending on config
- 3-node replica set only — **no sharding support** (that starts at M30)
- ~~Max connections ≈ 1,500~~ — **corrected:** per the 2026-01-22 internal analysis (company's own sourced comparison table), max connections is **3,000 for M20, M30, and M40 alike** — connections are not a differentiator between these tiers. My earlier guess of ~1,500 was wrong, superseded by this more authoritative source.

## Prior production test — January 2026 (critical historical context, surfaced 2026-08-03)

**This exact downsize was already attempted and reverted.** Per an internal email sent by the user, subject "Recomendación de tier MongoDB Atlas - Mantener M30", sent **2026-01-22** (one day after the revert below) to internal IT/Operations stakeholders — recipient names not recorded here per this project's no-names-in-written-docs convention:

- **2026-01-19:** downsized M30 → M20 in production.
- **2026-01-21:** reverted back to M30, after 2 days.
- **2026-01-22:** formal keep-M30 recommendation sent (the email referenced throughout this section).
- **Observed during the M20 window:** CPU peaks up to 35%; RAM usage capped/limited at ~1,300–1,500 MB (i.e. hitting a ceiling, not just running lower); max connections 316.
- **Observed after reverting to M30:** CPU normalized ~15–25%; RAM usage ~2,000–3,500 MB (able to use the extra headroom); max connections 286 (lower than the M20 window's 316 — connection count wasn't the limiting factor either way).
- **Database state at the time (January 2026):** dataSize (logical/uncompressed) 7,449 MB; storageSize (compressed) 1,764 MB; indexSize 800 MB; totalSize (storage+index) 2,565 MB.
- **January's stated rationale:** `ordertimes` alone was 27.6% of total index size (220 MB of 800 MB) with no cleanup policy yet, called out as making M20 "unviable medium-term" due to projected growth.
- **Formal recommendation sent to stakeholders in January: keep M30.**

**Cross-check against today's (2026-08-03) data:** `ordertimes` index size is now only 52.58 MB (was 220 MB in January) — a real reduction, suggesting a cleanup/archival policy was implemented since January, addressing that specific growth concern. However, this doesn't overturn the broader RAM finding: today's independent 4-week RAM metrics (peaks 3,776–3,830 MB across replicas) land almost exactly where January's M30-post-revert RAM usage did (2,000–3,500 MB), and well above where January's M20 test got artificially capped (1,300–1,500 MB, hitting a ceiling rather than reflecting true demand). **The two independent data points — a real 2-day production test 7 months ago, and today's 4-week utilization metrics — agree with each other.**

- **Writes to `logerrors` were also stopped, identified as a contributing problem around that same January timeframe** (user-confirmed 2026-08-03, exact date within the January window not specified). This is a second mitigation alongside the M30 revert, not a separate unrelated event.
- **This actually strengthens the no-go case rather than weakening it — as measured before today's index drop below.** `logerrors` writes are one plausible source of write-driven RAM/cache/IOPS pressure — if they were stopped as a fix and have stayed stopped, then this session's 4-week RAM metrics (peaks still 3,776–3,830 MB) were measured under *quieter* write conditions than January's original M20 test, which still had `logerrors` actively writing. **Despite that quieter baseline, RAM usage still landed in the same too-high-for-M20 band.** (`logerrors` held a static 352,943 docs / 188 MB data across both `.stats()` calls today, consistent with writes having stopped and stayed stopped.)

## Live change made mid-session: `logerrors` indexes dropped (2026-08-03)

**Timeline resolved** — this happened just now, in this session, not back in January, and it was a manual action run directly by the user against the cluster — not a command suggested, written, or executed by the assistant. Confirmed by comparing the two `db.logerrors.stats()` calls in this conversation:

| | Before (earlier today) | After (just now) |
|---|---|---|
| `nindexes` | 5 | **1** (`_id_` only) |
| `totalIndexSize` | 1,165,697,024 (~1.16 GB) | 259,903,488 (~259.9 MB) |
| Indexes present | `_id_`, `createdAt_1`, `updatedAt_-1`, `message_1_updatedAt_-1`, `message_1_createdAt_-1` | `_id_` only |
| `size` / `count` / `storageSize` | 188,405,238 / 352,943 / 1,164,718,080 | **unchanged** — only indexes were dropped, data untouched |

**~906 MB of index size freed** (`createdAt_1`, `updatedAt_-1`, and the two `message_1_*` compound indexes, all removed).

**Implication for the recommendation above: this happened *after* the 4-week RAM metrics were captured, so that RAM data does not yet reflect this change.** The no-go conclusion still stands as the best current answer, but it's now based on a slightly stale picture — this 906 MB index reduction is a real, meaningful change that current metrics haven't caught up to yet. It's promising (906 MB is not nothing against a ~4,096 MB M20 ceiling) but not enough on its own to flip the recommendation: peak usage was already only marginally under M30's fully-available headroom, and how much of that 906 MB of index was actually WT-cache-resident (vs. mostly evicted/cold) at any given time isn't known — index size on disk doesn't equal RAM freed.

**Flagging, not blocking:** dropping `createdAt_1`, `updatedAt_-1`, `message_1_updatedAt_-1`, `message_1_createdAt_-1` removes any query plan that relied on them. Worth confirming (via `$indexStats` history, if retained, or just watching query performance / `slow query` logs going forward) that none of those were load-bearing for a query path — this wasn't verified against actual query patterns before the drop, per the "possible redundancy, not confirmed" note earlier in this file.

**Why this drop likely isn't enough to flip the recommendation, worked through 2026-08-03:**
1. 906 MB is *on-disk* index size, not confirmed RAM freed — only the WT-cache-resident fraction of that index was ever costing RAM, and that fraction is unknown without fresh measurement.
2. Best-case (all 906 MB comes off peak RAM): 3,776–3,830 MB → ~2,870–2,924 MB. Still under M20's 4,096 MB headline spec, but headline spec isn't the operative ceiling.
3. **January's real test showed M20's practical ceiling is ~1,300–1,500 MB, not 4,096 MB** — that's where usage got capped (forced eviction, not organic low demand), evidenced by CPU rising to 35% and the resulting revert. Even the best-case post-drop estimate (~2,870–2,924 MB) is still roughly double that real-world ceiling.
4. Overall demand has grown since January (M30 peak 2,000–3,500 MB in Jan → 3,776–3,830 MB now), even after the `ordertimes` cleanup — one collection's index removal is fighting an upward trend, not a flat baseline.

**Unresolved data inconsistency, flagged not explained:** `db.stats()` (captured earlier this session, pre-drop) reported whole-database `indexSize` ≈ 648 MB across 92 indexes/34 collections — smaller than `logerrors`' own 1.16 GB of indexes at that same point in time, which is arithmetically impossible if both came from the same cluster/environment. Doesn't change the conclusion above (which rests on RAM metrics + the January test, not this figure), but the two `.stats()` calls should be re-verified against the same target before either number is trusted further.

**Conclusion unchanged: no-go, pending fresh RAM metrics collected over the next several days post-drop to see if this cleanup moved the needle at all.**

## RAM chart visual review (2026-08-03, `Sin título.jpeg`)

User-provided screenshot (source described as Grafana; chart title "MongoDB: RAM", dark theme) — confirmed to be **the same dataset already logged above**, not fresh data: identical timestamp (2026-08-03 09:17:56) and identical min/max/avg/current values per replica. Does **not** yet confirm the "max 3200 → max 2500" improvement reported earlier — that claim is still unverified, pending a genuinely newer time window (post-index-drop).

**New structural observation from the chart itself (not visible in the table alone): a repeating sawtooth pattern.** RAM climbs steadily over ~2–5 day stretches, then drops sharply to a ~1,300–1,500 MB floor, repeating at least 5 times across the 4-week window (visible drops around 07/09–10, 07/17, 07/20, 07/22, 07/27). Consistent with periodic replica restarts (Atlas maintenance/patching or similar) resetting the WiredTiger cache, which then re-warms until the next restart cuts it off.

**Implication:** the observed peaks (3,776–3,830 MB) may not represent the workload's true organic ceiling — they may just be wherever cache growth happened to get interrupted by a restart. If restarts are cutting growth off before it plateaus, **real demand could be higher than measured, not lower** — this would argue for more caution on M20, not less. Not confirmed — would need to correlate the drop timestamps with Atlas maintenance/restart events to verify the cause, and see whether RAM keeps climbing past ~3,800 MB in any window long enough to go uninterrupted.

## Second chart: "System Memory" (host-level, `WhatsApp Image 2026-08-03 at 10.27.37.jpeg`)

Different Atlas UI panel than the "MongoDB: RAM" chart above — this one is **OS/host-level memory** (MEM USED vs. MEM AVAILABLE, in GB), one panel per replica, ~1-month window ending Aug 2026. Three findings:

1. **Total system memory ≈ 7.4 GB per node** — MEM USED + MEM AVAILABLE sums to 7.39–7.40 GB consistently across all three panels (1.55+5.84, 1.47+5.93, 2.49+4.9 GB). Consistent with M30's 8 GB nominal RAM minus typical host/OS reservation — sanity-checks against the confirmed M30 tier.
2. **Vertical red/orange marker lines corroborate the restart hypothesis from the RAM chart above** — these line up with the same periodic-reset pattern seen in the "MongoDB: RAM" sawtooth, from an independent panel. Strengthens (doesn't yet prove) that periodic restarts are the actual cause of the earlier sawtooth.
3. **MEM USED trends upward across the full ~1-month window in all three panels, with MEM AVAILABLE declining correspondingly.** This is a second, independent signal — at the OS level, not just mongod's WT cache — that overall memory demand is still growing over time, not flattening. **Reinforces caution against M20**, not in favor of it: the workload appears to want more headroom over time, not less.

## Correction (code-verified, 2026-08-03): `logerrors` write-stoppage actually dates to 2026-07-20, not January

Checked `git log` against the local read-only clones (`smartpedidos/repos/dev-src-smartPedidos-concentradorService`, `dev-scr-smartPedidos-platformsService`) rather than relying on the earlier user recollection. Findings:

- **Both services introduced a `mongoLogEnabled` toggle on the same date: 2026-07-20** — commit `f7df10e1` ("feat: configlogs") in concentrador-service, `65f9eff` ("feat : log config") in platforms-service. Before this commit, `Log.save()` wrote to the `logerrors` collection **unconditionally** — there was no flag to disable it. The flag defaults to `false` in code but is actually driven at runtime by a remote config value (`forcedCronHorarios.mongoLogEnabled` / `orderRejClosedTime.mongoLogEnabled`, polled periodically — likely sourced from the `configs` collection, not independently verified here).
- **This means `logerrors` writes could only have actually stopped starting 2026-07-20** — the earlier framing ("we stopped writing to logerrors, that was a problem at that moment [January]") doesn't hold up against the code history. Whatever "problem in January" is being recalled, the write-disable mechanism itself is 2 weeks old, not 7 months old.
- **This also gives the mid-window RAM-chart drop around 07/20 (flagged in the sawtooth/restart discussion above) a concrete, code-verified explanation** — likely the deploy of this change — rather than an unexplained restart guess.

**Why this directly answers "why doesn't stopping logerrors mean we can downsize now":** the RAM chart's 4-week window (07/06–08/03) spans both sides of the 07/20 cutoff. The most recent cycle — entirely within the post-07/20, logging-disabled period — still climbed to a "current" reading of 3,473 MB on Replica 2, nearly matching the pre-cutoff peak of 3,776 MB. **If `logerrors` writes were a major driver of RAM pressure, this most recent cycle should read meaningfully lower than earlier ones. It doesn't.** This is direct evidence — not inference — that `logerrors` was not the dominant source of the memory pressure that failed the January M20 test. Something else in the workload (plausible candidates already flagged: `branches`' extreme write churn, `orders`/`ordertimes` volume) is generating comparable cache demand independent of `logerrors`.

**Conclusion: the January no-go stands, and this new evidence strengthens rather than weakens it** — the one mitigation applied since January (`logerrors` write-stoppage, actually only 2 weeks old) has not visibly reduced peak/current RAM usage in the one full cycle where it's had a chance to.

## Self-correction (2026-08-03): "RAM near ceiling" was the wrong framing for the danger signal

User pushback, correct: WiredTiger's cache is designed to fill whatever RAM it's given — an underused cache is wasted capacity, not health. So "memory used trending toward ~100% of what's available" is **expected behavior on any tier**, not evidence of distress by itself. Comparing M30's current peak (3,830 MB) against M20's total budget (4,096 MB) and calling that "94% full, therefore dangerous" overstates what that comparison actually proves.

**The real failure mode is cache eviction pressure, not raw memory-used percentage.** When the cache is too small for the actively-used working set, WiredTiger evicts more aggressively — more disk reads on cache misses, more CPU spent on eviction/reconciliation, worse query latency. That's the actual cost of an undersized cache.

**Re-reading the January evidence through this lens: the real signal was never the "RAM capped at 1,300–1,500 MB" figure** (repeatedly cited above as central evidence) — that capping is just what a smaller cache does, and is harmless on its own. **The real evidence is the CPU increase: 15–25% baseline → 35% peak under M20.** That's the actual distress signal — more work being done to compensate for a cache that couldn't hold the working set. This piece of evidence is unaffected by the correction above and still supports the no-go.

**Going forward, the right metrics to anchor on are eviction rate, disk IOPS, and CPU/latency — not raw memory-used %.** The whole-db and per-collection `.stats()` calls captured earlier in this file include raw WiredTiger cache/eviction counters (e.g. `branches`: `'checkpoint blocked page eviction': 55877`, `'modified pages evicted': 1,069,928`) but these are cumulative-since-restart counts, not rates, and without a time base they can't be judged as healthy or alarming — flagged as a gap, not asserted either way. **If this decision needs to be revisited, the next useful pull is Atlas Metrics' "Cache Activity" / eviction panels and Disk IOPS (not another RAM chart) to see whether current M30 is already under any eviction pressure, which would be the real pre-check for whether the working set fits in a smaller cache.**

## Real tension surfaced (2026-08-03): Cache Usage + Disk IOPS panels read as healthy, not stressed

Pulled exactly the metrics identified above as the right ones (`WhatsApp Image ... 10.44.02.jpeg` = Cache Usage, `WhatsApp Image ... 10.45.37.jpeg` = Disk IOPS, both per-replica, Atlas UI):

- **Cache Usage (`USED`, the actual WT cache — not OS-level System Memory):** peaks at **~1.2–1.5 GB per replica** (1.24 GB / 1.21 GB / 1.45 GB across the three), sawtooth pattern matching the same restart markers as before. `DIRTY` stays negligible throughout (19–24 MB) — no checkpoint/write-back backlog.
- **Disk IOPS:** Read IOPS **~0.3–0.42/s — essentially zero.** Nearly all reads are served from cache; disk reads (the actual symptom of a cache too small for the working set) are not happening in any meaningful volume. Write IOPS ~38–40/s sustained with periodic checkpoint bursts to 150–200/s — a normal, healthy pattern.

**This is a real tension with the no-go conclusion above, not a confirmation of it.** A WT cache that tops out around 1.4 GB with near-zero disk reads is not a system straining against a ceiling — it reads as comfortably within one, even on the current M30. 1.2–1.5 GB is close to, or under, both cache-ceiling estimates discussed for M20 (~1–1.5 GB depending on formula). It also explains the earlier discrepancy: OS-level "System Memory used" (2.5–3.8 GB) clearly includes far more than the WT cache alone — connections, OS buffers, replication/driver overhead — so that metric was never a clean read of cache pressure to begin with, consistent with the self-correction above.

**Not resolving this artificially in either direction.** Two things are simultaneously true: (1) a real production test in January failed and got reverted, with a genuine CPU increase (15–25% → 35%) as evidence; (2) today's actual cache/IOPS metrics — the ones that matter per the self-correction above — look healthy, not stressed, and conditions have measurably changed since January (`ordertimes` index cleanup ~76% reduction, `logerrors` writes stopped 2026-07-20). Fresh cache/IOPS data of this kind wasn't part of January's original analysis. **Recommendation downgraded from "no-go" to "re-test warranted"** — the honest position given this data is that a controlled repeat of the January test (not a permanent reliance on a 7-month-old result) is the responsible next step, not an assumption either way.

## Working theory

Downsize feasibility hinges on whether current usage fits inside M20's real ceilings, not its headline specs:
1. **Working set vs. cache** — if the hot working set (index + frequently-accessed docs) exceeds ~1.5 GB, expect page faults and latency regressions under M20.
2. **CPU headroom** — fewer vCPUs (down to 2) means less room for query/aggregation bursts; check current peak CPU%, not just average.
3. **Connection count** — `platforms-service` + `concentrador-service` both hold pools; multiply by ECS task count and driver pool size, compare to M20's ~1,500 cap.
4. **IOPS** — check current disk IOPS peaks against M20 standard (non-provisioned) IOPS limits.
5. **Storage headroom** — check current data + index size and growth trend against M20's storage cap.
6. **Sharding** — if the current cluster is sharded, M20 is disqualified outright regardless of the numbers above.

## Ruled out

- Nothing ruled out yet — no data gathered.

## Open questions / next steps

- ~~Current cluster tier~~ — confirmed M30, not sharded.
- ~~Whole-db / most collection stats~~ — confirmed via `db.stats()` + Collections tab; `orders` is clean, `branches`/`logerrors` show index bloat + write churn.
- ~~RAM utilization~~ — confirmed (see deciding finding above). RAM alone is decisive enough for a preliminary no-go.
- **Optional, for completeness before finalizing:** CPU% and Disk IOPS (p95/p99), connection count peaks — unlikely to overturn the RAM-based no-go, but worth a quick check in case they reveal an even sharper constraint (e.g. IOPS) worth naming in the final writeup.
- `news` and `deadletters` collection stats not yet seen individually — lower priority now that the RAM finding is decisive; only worth chasing if we later revisit "what to trim to make M20 viable."
- Recommendation drafted above (no-go, preliminary). Promote to main ticket once user confirms no further data changes the call.

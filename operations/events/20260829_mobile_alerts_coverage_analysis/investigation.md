# Investigation — 20260829_mobile_alerts_coverage_analysis

**Status:** open — proactive analysis, ticket GITIN-1965 (empty, no description yet)

## Scope

Full alert/trigger coverage review for MobileAppService hosts `SFCG-MOBI-01` / `SFCG-MOBI-02` (behind `SFCG-MOBI-LB`), beyond the IIS request-rate spike/nodata work already closed in GITIN-1918 (`operations/events/20260824_mobile_iis_spike_detection/`). Not incident-driven — no alert triggered this.

## Confirmed facts (inherited from GITIN-1918, re-verify before reuse)

- Both hosts link only vendor templates: `IIS by Zabbix agent active`, `Windows by Zabbix agent active` — no shared custom template.
- 7 triggers added by GITIN-1918 (26742–26748: 3 spike levels x 2 hosts + 1 `nodata()` on Mobile 02) carry the fleet-wide 10-tag set and were believed to route via action id 10 ("Google Chat Loyalty to OPE (EMAIL)").
- Mobile 02 has a recurring 7.1–10.1h nightly power-off window, cause (manual vs. scheduled) still unconfirmed.
- VM SKU/size for either host is undocumented.

## Open question raised by this analysis — RESOLVED (2026-08-31, via `docs/zabbix_observability.md`)

Originally flagged: whether GITIN-1918's triggers (26742-26748) actually routed given a suspected `EMAIL`/`MAIL` tag-substring mismatch on action 10. Per `docs/zabbix_observability.md` (updated during `GITIN-1961`/`GITIN-1966`, 2026-08-28/30): the mismatch read was itself based on a stale/incorrect same-day investigation — a later unfiltered `usermacro.get`/`action.get` re-check on 2026-08-28 confirmed the base macros were defined correctly and action 10 was fixed (`EMAIL`→`MAIL`) and enabled by end of that day. No action needed here; GITIN-1918's routing has been correct since 2026-08-28.

Action ids 7/8/9 remain disabled/non-matching as of the 2026-08-30 audit — flagged there as candidate cleanup, not addressed here.

## Cross-reference — this ticket's actual audit scope already covered by GITIN-1966 (2026-08-31)

GITIN-1965 is the **parent** ticket; the fleet-wide Req/s-alert coverage/consistency audit this investigation set out to do was split into **`GITIN-1966`** (child, `loyalty/events/20260830_reqs_alerts_zabbix_audit/`) and already completed there. Key findings relevant to Mobile specifically, from `docs/zabbix_observability.md`:
- `SFCG-MOBI-01`/`02` run **three overlapping alerting schemes simultaneously** on the same `_Total` request-rate item: legacy `PERF_COUNT_TRIG_*` (base defaults), a "Caída brusca" sudden-drop detector (`{$DROP.*:MOBI}`, shared context), and GITIN-1918's IIS Spike triggers (per-host `:MOBI01`/`:MOBI02` context).
- MOBI01's Spike thresholds (`1.5/2.5/4`, OK=1) are ~13x lower than MOBI02's (`20/30/60`, OK=15) — flagged there as "worth verifying this is intentional, not copy-paste drift," **not yet resolved in that ticket**.
- MOBI02 has a `nodata()` trigger (26748, `{$MOBILE_PCOUNT_NODATA_WINDOW:MOBI02}=11h`); MOBI01 has none — flagged as asymmetric, not yet confirmed intentional.

**This investigation's baseline data answers the threshold-gap question**: GITIN-1918's own investigation (`operations/events/20260824_mobile_iis_spike_detection/investigation.md`) already documents that the per-host thresholds were deliberately calibrated from real percentiles — Mobi01's traffic profile is genuinely ~40x lower than Mobi02's, not a copy-paste artifact (Mobi01 3m-avg p99=1.22 vs Mobi02's p99=18.99 at calibration time). The fresh 3-weekend baseline pulled here (below) reconfirms the same gap a week later (Mobi01 combined mean 0.20-0.26 req/s vs Mobi02's 5.34-10.23 req/s across all 4 weekends, a ~20-40x gap) — the 13x-threshold ratio is proportionate to real traffic, not drift. Worth relaying this back to GITIN-1966 rather than re-deriving it there. The MOBI01 `nodata()` asymmetry remains a genuinely open gap this data doesn't resolve.

**Going forward:** this folder's remaining unique value is the traffic-baseline/season-opening analysis below, not a second fleet-wide coverage audit — that audit is GITIN-1966's, already done. Avoid duplicating its trigger-inventory work here.

## Working theory

None yet — this is a coverage/gap inventory, not a root-cause investigation. Plan:
1. Inventory every item + trigger currently attached to both hosts (template-inherited + custom), not just the IIS counter family.
2. Re-check `action.get` live to confirm current (post-1961) routing state, and confirm each Mobile trigger's tag set actually matches an enabled action's conditions.
3. Compare metric coverage against what the linked vendor templates provide by default (CPU, memory, disk, service/process availability, ICMP/agent ping) vs. what has enabled/thresholded triggers vs. what's template-default-disabled.
4. Check trigger dependency structure fleet-wide convention vs. what exists on these two hosts.

## Ruled out

N/A yet.

## Open questions / next steps

- Need live `host.get`/`item.get`/`trigger.get` (with `selectTags`) for both hosts, and live `action.get` with `selectFilter` — commands to be handed to user next.
- Confirm ticket GITIN-1965 stays empty/proactive, or gets a description later that narrows scope.

## Duplicate/overlapping method-count items found (C2, 2026-08-29)

Full item inventory (`data/c2_all_items.json`) shows the GET/POST breakdown exists twice per host, under different key instances, both enabled:
- Original (`_Total` instance, matches the family already used in GITIN-1918): Mobi01 GET=52784/POST=52792, Mobi02 GET=52742/POST=52750.
- Newer (`{$IIS.APP.NAME}` instance): Mobi01 GET=53257/POST=53258, Mobi02 GET=53259/POST=53260. Delay/update interval driven by `{$IIS:ITEM_UPDATE_INTERVAL}` macro instead of a hardcoded `60`.
- Plus two custom aggregate items: 53249/53250 "Avg Requests (POST + GET)" per host, and 53735 "IIS Total Method Requests/sec (MOBI-01 + MOBI-02)" (cross-host sum, lives only on Mobi01's hostid).

Not yet determined whether the `{$IIS.APP.NAME}`-instance pair is intentional per-app-pool granularity (vs. whole-site `_Total`) or an unintentional duplicate from a later re-run of template/item creation. Flag as a coverage-review finding for GITIN-1965 — two near-identical metrics per host is exactly the kind of ambiguity that causes wrong-item mistakes later. Using the `_Total`-instance items (52784/52792, 52742/52750) for the weekend baseline pull below since they match the item family already validated with 16 days of history in GITIN-1918.

## Weekend GET/POST baseline (added 2026-08-29)

2026-08-29 (today, a Saturday) is a candidate "season opening" — **not confirmed either way**, this is exactly what the data pull below is meant to help determine, not an assumed fact. Approach: pull IIS `Get Requests/sec` / `Post Requests/sec` history for `SFCG-MOBI-01`/`SFCG-MOBI-02` for the 3 prior completed weekends (2026-08-08/09, 08-15/16, 08-22/23) as a baseline, then compare today's actual volume against it once today's data is complete. `fetch_weekend_get_post.sh` in this folder pulls the baseline 3 weekends and persists raw JSON under `data/`; today's comparison pull is a separate step once today's window has closed.

Items used (`_Total` key-instance family, matching GITIN-1918): Mobi01 GET=52784/POST=52792, Mobi02 GET=52742/POST=52750.

### Baseline (3 prior weekends, computed 2026-08-29)

| Weekend | Host | Combined GET+POST mean (req/s) | GET p99 | GET max | Sample coverage |
|---|---|---|---|---|---|
| 08-08/09 | Mobi01 | 0.20 | 0.87 | 11.38 | ~100% (2871-2879 samples) |
| 08-08/09 | Mobi02 | 9.28 | 45.10 | 156.53 | ~58% (1674 samples) |
| 08-15/16 | Mobi01 | 0.23 | 1.25 | 2.41 | ~100% (2872-2878 samples) |
| 08-15/16 | Mobi02 | 7.91 | 12.14 | 16.89 | ~58% (1674 samples) |
| 08-22/23 | Mobi01 | 0.25 | 1.07 | 2.78 | ~100% (2877 samples) |
| 08-22/23 | Mobi02 | 5.34 | 7.65 | 12.50 | ~58% (1676 samples) |

Full per-metric percentile table (mean/p50/p90/p95/p99/max for GET and POST separately, both hosts, all 3 weekends) computed by `analyze_weekend_get_post.py`, raw values in `data/w{1,2,3}_*.json` — not reproduced in full here, re-run the script to regenerate.

Observations:
- Mobi01 stays negligible and flat across all three weekends (~40x below Mobi02, consistent with GITIN-1918).
- Mobi02's baseline mean is **trending down** weekend over weekend (9.28 → 7.91 → 5.34 req/s combined) — not a flat "normal weekend" number, so today's comparison should weigh the recent trend, not just the most recent weekend alone.
- Weekend 08-08/09 had a much fatter tail (GET p99=45.1, max=156.5) than the other two (p99 12-16, max 17-24) — a real, separate burst from the documented 08-13 spike episode (`operations/events/20260824_mobile_iis_spike_detection/`).
- Mobi02 sample coverage is consistently ~58% each weekend (nightly power-off gaps), matching the known pattern from GITIN-1918.

### Today's comparison pull (tooling ready, not yet run)

`fetch_today_get_post.sh` pulls the same 4 items (Mobi01/02 x GET/POST) from 2026-08-29 00:00:00 -03:00 through the moment it's run (capped at 2026-08-30 23:59:59 -03:00) — safe to run mid-window for a partial read, re-run to refresh. `analyze_weekend_get_post.py` auto-detects `data/today_*.json` once present and appends a "today vs. baseline avg" delta per host (using the combined GET+POST mean rate) to its output — no manual comparison needed once the pull is run.

### Today's result — FINAL (full weekend, re-pulled 2026-08-31)

An earlier partial-window pull (2026-08-29, mid-Saturday, Mobi02 n=656) has been superseded by this full-window pull (Mobi01 n=2872-2879, Mobi02 n=1674 — matching baseline weekend sample counts exactly, confirming full 08-29/08-30 coverage).

| Host | Combined GET+POST mean | vs. 3-weekend baseline avg | GET p99 | GET max | Samples |
|---|---|---|---|---|---|
| Mobi01 | 0.26 req/s | +14% | 1.30 | 4.06 | 2872 |
| Mobi02 | 10.11 req/s | +35% | 27.34 | 137.89 | 1674 |

- Mobi01: no meaningful change (+14%, within the noise already seen across baseline weekends: 0.20/0.23/0.25 req/s).
- Mobi02: +35% vs. the 3-weekend average, but that average blends a declining trend (9.28 → 7.91 → 5.34 req/s) — against the most recent weekend (08-22/23, 5.34 req/s) today's rate is roughly **+89%**.
- Mobi02's tail today (GET p99=27.34, max=137.89) sits between the two calmer recent weekends (p99 7.65-12.14) and the one already-flagged anomalous weekend (08-08/09, p99=45.10, max=156.53) — elevated, not as extreme as that outlier.

### Per-service (Total) view — for PM/higher-level reporting

Per [[feedback_reporting_granularity_by_audience]]: Ops/SRE gets per-machine numbers (tables above); anything surfaced to PM or above should report the **service total** (Mobi01+Mobi02 combined), not individual VM figures. `analyze_weekend_get_post.py` computes this properly — per-minute totals summed across both hosts/both metrics (Mobi02 minutes with no data during its documented nightly power-off are treated as 0 contribution, not excluded, since that's a real "service is only Mobi01 right now" state, not a data gap) — rather than approximating from summed per-host means.

| Weekend | Samples | Mean (req/s) | p99 | Max |
|---|---|---|---|---|
| 08-08/09 | 2871 | 5.60 | 48.07 | 204.06 |
| 08-15/16 | 2872 | 4.83 | 22.12 | 38.58 |
| 08-22/23 | 2877 | 3.36 | 10.08 | 16.25 |
| 08-29/30 (final, full weekend) | 2872 | 6.15 | 30.17 | 177.09 |

Service-total delta: baseline avg=4.60 req/s, today=6.15 req/s → **+34%**, with a p99 (30.17) meaningfully above the two most recent weekends (10-22) though below the outlier weekend (48.07).

**Conclusion:** this weekend's traffic was measurably and consistently elevated across both per-host and service-total views (+34-35% mean, fatter tail than the two most recent weekends) — a real signal, not a partial-window artifact (full sample counts now confirmed). Whether the business reason is specifically a "season opening" remains a business-calendar fact this data can't confirm on its own; what the data does confirm is that traffic was meaningfully above the recent baseline, concentrated on Mobi02, without tripping the existing spike triggers into an actual incident (no `ops.md`/alert record exists for this weekend as of this writing).

### Hour-by-hour breakdown, Sat/Sun local time (UTC-3) — 2026-08-31, `analyze_hourly_get_post.py`

The daily-mean comparison above hides where the elevation actually is. Hourly service-total mean (Mobi01+Mobi02, GET+POST) shows it's **not** a uniform all-day lift — it's a sharp, localized spike:

| Hour (Sat, local) | 08-08/09 | 08-15/16 | 08-22/23 | 08-29/30 (today) |
|---|---|---|---|---|
| 16:00 | 12.79 | 4.07 | 5.25 | **21.06** |
| 17:00 | 8.05 | 3.95 | 4.92 | **19.69** |
| 18:00 | 7.88 | 4.28 | 4.86 | 12.78 |

Today's 16:00-17:00 window is 2.5-5x every baseline weekend at the same hours — the standout signal. Outside that window (early morning, late evening, all of Sunday) today tracks within or close to the existing baseline spread — Sunday's peak (12-15h range, up to 15.35) is comparable to or below the 08-15/16 weekend's Sunday peak (19.65 at 22:00). Full 24h x 2-day matrix (service total and Mobi02-only) in script output, not reproduced here in full — re-run `analyze_hourly_get_post.py` to regenerate.

Mobi02's nightly power-off (blank ~02:00-10:00 in the Mobi02-only matrix) is consistent across all 4 weekends — unchanged pattern, not affected by today's event.

**Open next step, not yet checked:** Mobi02's IIS Spike thresholds are `{$MOBILE_PCOUNT_SPIKE_WARN/AVG/HIGH:MOBI02}=20/30/60` on a 3-min average (per `docs/zabbix_observability.md`, GITIN-1966 audit). An hourly mean of 21 req/s at 16:00 plausibly crossed the Warning tier at some point within that hour (per-minute values within an hour-mean of 21 likely include points well above 21). Whether the spike triggers (26745-26747) actually fired during 2026-08-29 16:00-18:00 local hasn't been checked — `problem.get` for those triggerids in that window would confirm whether alerting worked as designed for this event or missed it silently. Not yet run.

### Design note (2026-08-31): week-over-week comparison should not be a Zabbix calculated item

Considered building this weekend/hourly comparison as native Zabbix calculated items (`avg(item,1h:now-Nw)` time-shift pattern) instead of the local script. Rejected for two reasons:
1. **Alerting sprawl** — Mobi01/Mobi02 already run 3 overlapping, uncoordinated alerting schemes on this same metric per GITIN-1966's audit; adding a 4th here would compound a problem that ticket is meant to fix, not this one.
2. **Statistical correctness** — the underlying item (`perf_counter_en[...,60]`) already stores an averaged rate (avg req/s per 60s window), not a raw count. Stacking Zabbix's own `avg()` on top over a shifted window is only valid when the underlying samples are regular and equal-length. Mobi02's nightly power-off gaps break that assumption — a bare `avg()` can't distinguish "0 traffic" from "no data," so it would silently average only whatever partial coverage existed in each shifted window, with no guarantee the same amount of coverage existed week to week. This is exactly the ambiguity `analyze_weekend_get_post.py` resolves explicitly (zero-fill for service-total, exclude for Mobi02-alone) — logic Zabbix's native history functions can't express.

Checked and ruled out as a *separate* concern: History storage period on all 4 GET/POST items (52742/52750/52784/52792) is 180d (trends 730d), confirmed 2026-08-31 — so a `now-Nw` lookup within any reasonable comparison window (well beyond `now-3w`) always resolves against full-resolution 1-minute history, never falls back to coarser hourly trend aggregates. Not the blocker; the gap-handling issue above is.

**Conclusion:** keep this kind of comparison in the script (`analyze_weekend_get_post.py` + `fetch_get_post_weeks.sh`), not in Zabbix config. If a standing week-over-week alert is wanted, it should be designed as part of GITIN-1966's cleanup, with the same explicit gap-handling logic, not bolted on independently here.

## Cross-service peak-season check: WebService (on-prem), WebServiceV2 (SmartCloud), SmartPedidos (2026-08-31)

**Correction (2026-08-31, user):** `SFCG-WEBS-01/02/03` ("WebServiceV1" in this investigation's earlier shorthand) and `SFCG-WSV2-01/02` ("WebServiceV2") are **not** two versions of the same service — `SFCG-WEBS-*` serves **on-premise SmartFran**, `SFCG-WSV2-*` serves **SmartCloud**, entirely different platforms/client bases that happen to share a naming pattern. Now recorded in `loyalty/docs/infrastructure.md`. Treat and report them as two independent services below, not a combined "WebServiceV1/V2" category — grouping them together (as this section originally did) would conflate two unrelated platforms' traffic under one number.

Extended the same weekend-baseline approach to `SFCG-WEBS-01/02/03` (on-prem SmartFran WebService), `SFCG-WSV2-01/02` (SmartCloud WebServiceV2), and SmartPedidos (via CloudWatch, no Grafana API available) — to check whether Mobile's traffic elevation is an isolated event or part of a broader pattern (peak season hypothesis). `fetch_get_post_weeks.sh` extended to cover all 7 hosts; `analyze_weekend_get_post.py` generalized to per-service grouping (Mobile / on-prem WebService / SmartCloud WebServiceV2 — kept as separate groups, matching the correction above).

**Baseline gap found and NOT recoverable:** the 10 GET/POST items for WEBS-01/02/03 and WSV2-01/02 had only 7d History retention (fixed to 180d going forward, same as the CPU/RAM fix above — but not retroactive). `now-1w`/`now-2w`/`now-3w` pulls came back empty for these hosts — that data is genuinely gone, not just unfetched.

Attempted to backfill from Trends (hourly aggregates, 365d retention, should still cover these windows) — **failed: `trends.get` is not a valid method on this Zabbix version (6.0.32).** The dedicated Trend API (`trend.get`) was only added in Zabbix 6.4+; on 6.0, trends are visible only through the frontend UI graphs, not queryable via API at all. Confirmed via direct API error (`-32601 Method not found`), not inferred.

**Conclusion:** no way to reconstruct a weekend baseline for either service (on-prem WebService or SmartCloud WebServiceV2) for past weekends, via API or otherwise. Only `now` (2026-08-29/30) has real per-minute data for these 5 hosts — see `analyze_webs_wsv2_trends.py` for the current weekend's hourly shape per service (no baseline to compare against for either). Real baseline data starts accumulating from today forward now that retention is fixed; a real week-over-week comparison will be possible starting `now-1w` in next weekend's pull, not before — for both services independently.

### SmartPedidos (CloudWatch CPUUtilization, `analyze_smartpedidos_cpu.py`)

Unlike Zabbix, no retention gap — CloudWatch keeps 5-min granularity for well over a month by default, so all 4 weekends have real data.

| Weekend | concentrador avg(Average) % | platform avg(Average) % |
|---|---|---|
| 08-08/09 | 5.23 | 7.35 |
| 08-15/16 | 7.27 | 8.66 |
| 08-22/23 | 3.50 | 7.05 |
| 08-29/30 (now) | 3.06 | 8.99 |

Delta vs. baseline: `concentrador-service` **-43%** (lower, not higher), `platform-service` **+17%** (mild increase).

**This does not support the peak-season hypothesis via CPU** — at least not cleanly. Important caveat: `concentrador-service`'s CPU is already known (GITIN-1964) to be dominated by periodic spikes to 100% from an unrelated bug (unbounded fan-out in the PedidosYa sync cron), not by real order/request volume — every weekend here hits `peak(Maximum)=100.00` regardless of the underlying traffic level. CPU is a confounded, noisy proxy for this specific service; this result doesn't rule out a real traffic increase, it just means CPU isn't the right signal to see it with for concentrador-service. `platform-service`'s CPU is cleaner (no known confound) and shows only a mild +17%, not a strong signal either way. **Bottom line: SmartPedidos data neither confirms nor strongly contradicts the peak-season hypothesis via CPU — it's inconclusive with this metric, not evidence against it.**

### SmartPedidos, cleaner signal: SQS `PRD_BranchMessages.fifo` `ApproximateAgeOfOldestMessage`

User-proposed metric, avoids the CPU confound entirely — queue backlog age directly reflects whether the consumer is keeping up with real message volume.

| Weekend | avg(Average) sec | avg(Maximum) sec | peak(Maximum) sec |
|---|---|---|---|
| 08-08/09 | 1.78 | 4.10 | 38.00 |
| 08-15/16 | 0.69 | 1.56 | 293.00 |
| 08-22/23 | 0.25 | 0.70 | 33.00 |
| 08-29/30 (now) | 0.99 | 2.49 | 289.00 |

Now vs. baseline: +10% (0.90s → 0.99s) — within the noise already present between baseline weeks (0.25s-1.78s range). The two large `peak(Maximum)` spikes (289s, 293s) appear in both `now` and 08-15/16 alike, not specific to this weekend — isolated blips, not a pattern.

**SQS shows no peak-season signal.** This is a cleaner, non-confounded result than CPU (no known unrelated bug dominating it) — SmartPedidos genuinely does not appear to be experiencing elevated load this weekend.

### SmartPedidos, direct volume signal: MongoDB `news` document counts (user-proposed, 2026-08-31)

`news` is the internal order/event lifecycle model (per `smartpedidos/CLAUDE.md`) — document creation volume is the most direct available measure of real activity, more direct than CPU or SQS backlog age (both indirect/operational proxies). Pulled via `mongosh` (`data/news_hourly_raw.json`, `analyze_news_volume.py`) — **15-day retention confirmed**: `now-3w` (08-08/09) has zero data (already purged), `now-2w` (08-15/16) is missing Saturday entirely (only Sunday 08-16 exists) and is therefore excluded from the baseline average, not padded or estimated.

| Weekend | Total `news` docs | Status |
|---|---|---|
| now-3w (08-08/09) | 0 | No data — outside 15-day retention |
| now-2w (08-15/16) | 49,155 (Sun only) | Partial — Saturday missing, excluded from baseline avg |
| now-1w (08-22/23) | 72,717 | Complete |
| now (08-29/30) | **95,914** | Complete |

**Now vs. the one complete baseline weekend (now-1w): +32%** (72,717 → 95,914). Only one clean baseline point exists (not 3, unlike Mobile) due to the retention limit — a real caveat on how much this single delta can be trusted, but the volume itself is large enough (tens of thousands of documents per weekend) that this isn't noise.

Sunday-only comparison across all 3 available data points (less clean framing, but 3 data points instead of 1): 08-16=49,155 → 08-23=38,240 → 08-30=51,947. **Not monotonic** — 08-16 was already elevated, 08-23 dipped, 08-30 is the highest. This is real week-to-week volatility, not a clean rising trend — worth keeping in mind before reading the +32% as a straightforward "ramping up" signal.

### Overall cross-service conclusion (2026-08-31, revised)

- **Mobile:** confirmed real elevation, concentrated Sat 16:00-17:00 spike.
- **SmartPedidos:** confirmed real elevation in actual order/event volume (+32% `news` doc count vs. the one complete baseline weekend) — the earlier "no signal" read from CPU/SQS age is **not** a contradiction: those measure operational stress (is the consumer keeping up), and both stayed flat/low precisely because the system absorbed the higher volume without falling behind. Only one clean baseline weekend available due to 15-day retention, and the 3-point Sunday-only trend is non-monotonic — a real but not fully robust signal yet.
- **WebService (on-prem SmartFran, `SFCG-WEBS-*`):** unknown — no baseline recoverable, data collection starts fresh from today.
- **WebServiceV2 (SmartCloud, `SFCG-WSV2-*`):** unknown — same gap, independent of the on-prem service above (different platform, not a related data point).

Both Mobile and SmartPedidos now show real elevation. That's meaningfully more consistent with the peak-season hypothesis than the earlier (CPU/SQS-only) picture suggested — though both WebService and WebServiceV2 remain unconfirmed (two separate unknowns, not one), and SmartPedidos' baseline is thinner (1 clean weekend) than Mobile's (3).

## Applied change: CPU/RAM history retention raised to 180d (2026-08-31)

While confirming History storage period wasn't the blocker for the week-over-week design question above, found CPU/Memory utilization items (`Windows: CPU utilization` 50609/50665, `Windows: Memory utilization` 50616/50672) were at only 7d history retention — inconsistent with the GET/POST items (52742/52750/52784/52792) already at 180d, and too short to support any future week-over-week analysis on CPU/RAM the way this investigation did for request rate. Same 1m polling interval on all 4 items, so this matches the storage-growth order of magnitude already accepted for GET/POST, not a new tier.

Applied via `item.update` (C13 in `scripts.sh`), confirmed via follow-up `item.get`: all 4 items now `history: "180d"`, `trends: "365d"`, matching GET/POST. `trends` unchanged (was already 365d, longer than GET/POST's 730d — inconsistent but not addressed here, out of scope for this fix).

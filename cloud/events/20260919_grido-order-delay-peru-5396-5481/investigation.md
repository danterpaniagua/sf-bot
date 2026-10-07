# Investigation — 20260919_grido-order-delay-peru-5396-5481

**Branch 5523 added to scope, 2026-09-19** — not part of the original Grido complaint (5396/5481), checked separately on a narrower 4h window at user's request. Not yet confirmed whether 5523 is a new independent report or a hunch based on the 5396/5481 pattern.

**Jira ticket:** [GITIN-2084](https://smartit-ar.atlassian.net/browse/GITIN-2084) — "[CLOUD] Demoras en Branches de Peru"

## Reported symptom

Grido is complaining about delays in receiving orders, for franchises **5396** and **5481** (Peru). Reported 2026-09-19. Not yet confirmed: exact delay magnitude, whether it's ongoing right now, when it started, or whether these are the only two affected branches or just the first noticed.

## Related tickets (precedent, not yet confirmed as same root cause)

- **GITIN-2068** (`cloud/events/20260917_smartpedidos-peru-orders-pending/`) — 2026-09-17. Peru orders stuck in "Pending" in SmartPedidos, root-caused to a live `TimeZoneNotFoundException` in `MessageProcessor.SetTimeZones` (Orders API's SQS consumer, `ProcessGridoOrderAsync` path) — Peru isn't in `TimeZoneCountries.cs`'s 4-country dictionary, its fallback used a Windows-style timezone ID that doesn't resolve on the Linux container's tzdata, throwing unhandled → SQS message never deleted → retried until the queue's 3-day retention silently discards it. Branch **5454** was the confirmed live crash; branch **5396** was one of 12 historic stuck orders (unexplained backlog, predates the fix's deploy window, never resolved). Fix (timezone ID correction) deployed ~16:10 ART 2026-09-17, user-confirmed working same day — but **not independently re-verified since**, and the pre-existing 12-order backlog's cause was left open.
- **GITIN-2069** (`cloud/events/20260917_gitin2069-peru-platform-rejections/`) — 2026-09-17, closed same day as a "probable derivative" of GITIN-2068 — **user's determination, not independently verified** against per-order rejection detail. Flagged branch **5396** (Pueblo Libre I) as an outlier: 4.60% Grido-platform rejection rate over 7 days (4/87 orders) vs. 0.55% Peru-wide — 4-8x every other Peru branch. Never confirmed whether 4.60% at n=87 is statistically meaningful, nor what causes branch 5396's rejections specifically.

**Why this matters here:** branch 5396 already has an open, unresolved thread in both prior tickets (unexplained historic backlog in GITIN-2068, unexplained rejection outlier in GITIN-2069). Today's "delay" framing is symptom-language from Grido, not necessarily the same mechanism as "stuck at Pending forever" or "rejected by platform" — could be: (a) a recurrence/incomplete fix of GITIN-2068's bug, (b) the SQS retry-with-backoff behavior itself being visible as "delay" before eventual success or eventual silent drop, (c) something wholly unrelated (e.g. App Service perf, Service Bus backlog, a branch-side POS issue), or (d) branch 5396 specifically having a recurring config/environment problem distinct from both prior root causes. Branch **5481** is new — hasn't appeared in either prior investigation.

## Open questions — need answers before proceeding

1. What does "delay" mean concretely — minutes? hours? orders eventually arriving late, or never arriving at all (which would actually be GITIN-2068's symptom under different language)?
2. Is this ongoing right now, or already resolved by the time it was reported?
3. When did the delay start — correlate against the GITIN-2068 fix deploy (~16:10 ART 2026-09-17) and any deploys since.
4. Are 5396 and 5481 the only affected branches, or the first two noticed?
5. Branch 5481 — has it shown up in any prior Peru investigation? (Not found in GITIN-2068 or GITIN-2069 so far — needs a fresh check, not just "not mentioned in the files already read.")
6. Any live Azure alert, SQS DLQ growth, or Zabbix signal already flagging this independently of the Grido complaint?

## Real data, 2026-09-19 — CloudWatch `ApproximateAgeOfOldestMessage`, both branch queues, 48h window

Pulled via `aws cloudwatch get-metric-statistics` (`AWS/SQS`, `Maximum`, 300s period, 2026-09-17T21:32 ART to 2026-09-19T21:27 ART — 576 datapoints per branch, full coverage, no gaps). Data: `data/sqs_age_oldest_5396.json`, `data/sqs_age_oldest_5481.json`.

**Both branches show a real, recurring delay pattern — this is a different signature from GITIN-2068.** GITIN-2068's bug meant a message was *never* deleted (unbounded growth until 3-day silent expiry). Here, the age metric returns to 0 between spikes — messages ARE draining, just with a recurring multi-minute delay before being picked up:

- **Branch 5396:** 13 of 576 datapoints nonzero. Typical spike 100-200s (~2-3 min). One cluster 2026-09-17 22:17-23:27 ART ramping 55s→874s (~14.6 min) before clearing. Most recent spike **today, 2026-09-19T19:47 ART: 177s** — confirms this is still happening, not resolved.
- **Branch 5481:** 20 of 576 datapoints nonzero, same shape but a worse outlier: 2026-09-17 23:37-23:57 ART ramped 372s→1572s (**~26.2 min**) before clearing. Most recent spikes **today, 2026-09-19T20:22 and 20:42 ART: 131s/156s**.

**Not yet explained:** why the delay is intermittent/recurring rather than constant, and why it clusters more heavily in the evening of 2026-09-17 (same day as the GITIN-2068 fix deploy, ~16:10 ART) — could be coincidental (that evening's traffic pattern), could be a residual effect of the same deploy, not yet distinguished. The steady baseline of smaller (100-200s) recurring spikes across all three days, continuing today, looks like it predates and is independent of the 9/17 evening cluster — needs a longer historical pull (before 9/17) to confirm this is not new.

## Real data, 2026-09-19T21:34 ART — SQS `GetQueueAttributes`, current snapshot

Both branch queues empty at snapshot time: `ApproximateNumberOfMessages: 0`, `ApproximateNumberOfMessagesNotVisible: 0` for both 5396PRD and 5481PRD (`data/sqs_queue_attrs_5396.json`, `_5481.json`). Consistent with the CloudWatch age data above — no accumulating backlog, delays are transient and self-clear within minutes. Point-in-time only; both branches' last recorded age spike (5396: 19:47 ART, 5481: 20:42 ART) had already cleared by this snapshot.

## Real data, 2026-09-19 — Graylog, corrected endpoint

First attempt used the wrong host/path (`sf-monitoreo.smartfran.com`, no `/graylog` prefix) — that's the older SmartPedidos/SmartLoyalty Graylog stack's convention (`$SML_GRAYLOG_API_KEY`, port 9000), not SmartCloud's. Hung/returned empty. This is a known, previously-documented trap (see memory `reference_smartpedidos_smartloyalty_graylog_stack.md`) that wasn't checked against a working example before the first command was written. Corrected to `https://sfcloud-monitoreo.smartfran.com/graylog/api/search/universal/relative` (matches GITIN-2068's working `scripts.sh`) — now returns real responses. Full command history, including the failed attempt, preserved in `scripts.sh` (C3/C4).

**`Service:Orders AND AppLevel:Error AND (5396 OR 5481)`, 48h: 0 results.** But a sanity check (`Service:Orders` alone, no error filter, last 1h) **also returned 0** — and this is not new information: GITIN-2068's investigation.md documents the identical `Service:Orders` field filter returning 0 against a message it independently confirmed existed via a raw Azure export (not Graylog). **This 0-result is inconclusive, for the same unresolved reason as GITIN-2068 — not evidence of "no Orders errors."** Do not restate it as a clean finding anywhere. (Also confirmed in passing: `used_indices: []` appears in the response even on GITIN-2068's own confirmed 22-result free-text query — it is not itself a signal of query failure, and free-text queries, e.g. `"5396" OR "5481"`, are the pattern that's actually worked before; a `Service:Orders`-filtered query has never been confirmed to work in either investigation.)

## Real data, 2026-09-19 — branch 5523, 4h window

**SQS:** currently empty (0 messages, 0 in-flight), same as 5396/5481. CloudWatch `ApproximateAgeOfOldestMessage` (60s granularity, 4h): 6 of 239 datapoints nonzero, in **two separate clusters** ~2h apart — 17s→78s→137s (20:37-20:39 ART) and 18s→77s→142s (22:47-22:49 ART) — near-identical ramp shape both times, then clears. Same signature (short recurring ramp-then-clear) as 5396/5481, reinforcing that this looks like a systemic/periodic mechanism rather than a per-branch anomaly.

**Graylog free-text `"5523"`, 4h: 390 total hits, 100 sampled** (limit was 100 — not exhaustive, 74% of matches not pulled). Confirms the free-text approach works and surfaces real `Service`/`AppLevel`/`TenantId` fields (unlike the field-filtered query). Of the 100 sampled (85 from Orders-PRO, 12 Business-PRO, 2 ScheduledJobs-PRO, 1 Sales-PRO): **all 100 are `AppLevel: Information`, 0 mention Exception/error** — but this is a partial sample, not the full 390, so it does not rule out errors existing in the other 290 hits not fetched.

## CORRECTION, 2026-09-19 — the morning CPU/instance sections below were pulled against the WRONG resource

User confirmed the two reported CPU incidents (~08:50-09:10 and ~10:00-10:18 ART) were about **`SmartFran-Cloud-Sales-Plan-PRO`** all along, not `SmartFran-Cloud-Orders-Plan-PRO`. Every CPU/per-instance section below this point (through the "10 distinct instance IDs... 1→4 scale-out" finding and the `orders_delay_cpu_chart.html` artifact) was pulled and analyzed against **Orders**-Plan-PRO, based on my own unstated assumption (never actually confirmed with the user which plan "the CPU incident" referred to). **None of those findings are known to apply to Sales-Plan-PRO** — they're left in place below as a record of what was checked and why it doesn't answer the actual question, not deleted, per this project's investigation-file convention. Re-pulling against the correct resource next.

**User-provided Sales-Plan-PRO Portal screenshot** (Max CPU%, split by Instance, last 4h as of ~2026-09-19 evening ART) shows a materially different and more severe pattern than anything found on Orders: individual instances saturating to ~100% one at a time, each for ~15-20 min, roughly hourly — `wn1mdwk000VD4` ~8:50-9:10 PM local, another instance ~9:00 PM, `wn1mdwk000VE8` climbing to 100% ~10 PM. This is single-instance CPU saturation, not the mild 20-39% noise seen on Orders.

## Real data, 2026-09-19 — morning CPU/instance events vs. queue delay, decoupled (ORDERS-PLAN-PRO — WRONG RESOURCE, see correction above)

User separately observed two Orders-PRO App Service Plan events this morning via the Azure Portal CPU graph (Maximum aggregation): **incident 1, ~08:50-09:10 ART** and **incident 2, ~10:00-10:18 ART, reported as scaling to 2 instances** (vs. 1 normally). Checked whether either correlates with queue delay on the three franchise queues already in scope.

**CPU (`SmartFran-Cloud-Orders-Plan-PRO`, Maximum, 1-min grain):**
- Incident 1 (11:45-12:15 UTC): mostly 4-5%, periodic spikes to 11-16% every ~5 min.
- Incident 2 (12:55-13:25 UTC): notably higher, sustained 20-31% for the first ~7 min (12:55-13:01 UTC), then dropping to the same 4-19% pattern as incident 1.
- Live baseline (2026-09-20T01:38-02:07 UTC, for comparison): 5-20%, same shape as incident 1 — i.e. incident 1's pattern looks like normal background noise, incident 2's opening 7 minutes stand out as genuinely elevated.

**App Insights `requests` (Orders-PRO_new component): zero rows in both incident windows** despite confirmed real CPU activity — this is explained by architecture already confirmed in GITIN-2068: the SQS consumer (`MessageProcessor.PollOnceAsync`) polls AWS directly as a background loop (an outbound *dependency* call), not an inbound HTTP request, so it wouldn't appear in `requests` regardless of how much CPU it uses. `dependencies` table not yet queried for these windows — would be the correct table to check for SQS-driven activity.

**Queue age, all three branches, 1-min grain, 08:30-10:30 ART (spans both windows): 100% zero across all 120+ datapoints per branch (5396, 5481, 5523).** No message delay coincided with either CPU event on any of the three branches currently in scope. **This decouples this morning's CPU/instance-scaling incidents from the reported Grido delay** — at least for these three branches; doesn't rule out other Peru branches being affected by the CPU event without being checked.

**Not yet resolved:** what actually caused incident 2's CPU elevation/scale-out, and whether it affected some other branch not yet checked, or non-Peru traffic entirely, or was unrelated to Grido/Peru altogether (e.g. a different tenant, a scheduled job, a deploy). The recurring delay pattern found earlier (13:12-20:42 ART) is chronologically distinct from and later than these morning CPU events — nothing so far ties them together as the same root cause.

## Real data, 2026-09-19 — `dependencies` table also empty for both morning windows

Same result as `requests`: **zero rows** in both incident windows (`data/appinsights_deps_incident1_0850.json`, `_incident2_1000.json`). So App Insights has **no telemetry of any kind** — no requests, no dependencies — for Orders-PRO_new during either morning window, despite confirmed real CPU activity on the App Service Plan at the same time (see above).

**Not resolved — three live possibilities, not yet distinguished:**
1. An App Insights ingestion/sampling gap specific to that historical window (data loss on the telemetry side, CPU activity was real and app-driven but never got recorded).
2. The CPU activity isn't from the Orders API app itself at all — e.g. platform-level processes (health probes, warm-up, GC, or another app sharing the same App Service Plan, not yet confirmed whether one exists).
3. Some other in-process work generating CPU load without emitting either requests or dependency telemetry (e.g. a tight in-memory loop, a background timer not wrapped in a tracked operation).

Given "live" queries earlier in this session *did* return normal telemetry for the current moment, App Insights ingestion is working in general — the gap is specific to this historical window, which points more toward (1) or (2) than a global instrumentation failure.

## Real data, 2026-09-19 — continuous 48h CPU series, reveals a likely-scheduled recurring spike

Pulled `CpuPercentage` (Maximum, 5-min grain) for the full 48h window matching 5396/5481's queue-age data (2026-09-17T21:32 to 2026-09-19T21:27 UTC — note these are UTC timestamps, ART = UTC-3). `data/cpu_max_48h.json`, 575 points.

**The ~10:00 ART spike (user's "incident 2") recurs at the same clock time on both days:** 12:52-13:02 UTC (09:52-10:02 ART) shows elevated CPU on **both 2026-09-18 (26-31%) and 2026-09-19 (27-31%)** — same window, same magnitude, two days running. This looks like a **daily scheduled job or recurring platform behavior**, not something caused by today's Peru/Grido traffic specifically. Weakens the working theory that this CPU event is connected to the order-delay complaint at all — it predates today and repeats regardless of the complaint.

**Highest point in the full 48h series: 39% at 2026-09-19T03:52 UTC (00:52 ART)** — not previously checked, doesn't correspond to any window discussed so far (not a reported incident, not a queue-age spike time for 5396/5481/5523). Flagging as unexplained, not investigated further yet.

**Still true:** no CPU value in the full 48h series exceeds ~39% — this remains a fairly quiet App Service Plan overall, nothing that looks like sustained resource exhaustion.

## Real data, 2026-09-19 — per-instance CPU (`CpuPercentage`, `Instance` dimension), corrects the "2 instances" observation

Pulled with `--filter "Instance eq '*'"` on the same App Service Plan/window. **10 distinct instance IDs appeared across the full 48h** (8 with actual data points, 2 with none) — this alone indicates substantial instance churn/recycling over 48h, independent of any incident.

**Concurrency by window (distinct instances with data in that window):**
- Incident 1 (08:50-09:10 ART / 11:45-12:15 UTC): **1 instance** (`ln0xsdlwk000HCJ`, max 16%).
- Incident 2 (10:00-10:18 ART / 12:55-13:25 UTC): **4 instances** active concurrently (`ln0xsdlwk000HCJ` 31%, `ln0xsdlwk000HJD` 15%, `ln0xsdlwk000HET` 17%, `ln0xsdlwk000HIZ` 16%) — **corrects the user's "2 instances" observation to 4.**
- Checked again near end of window (20:30-21:00 ART, 2026-09-19): **still 4 instances**, same 4 IDs as incident 2 — the scale-out at incident 2 has **not scaled back down** as of the end of the 48h data pull.

**So the real event at incident 2 is a 1→4 instance scale-out that persisted for at least ~11 hours afterward**, not a brief 1→2 blip. The 39% CPU peak found earlier (00:52 ART, before either reported incident) belongs to a completely different, short-lived instance (`ln1xsdlwk000HDX`, 206 points, doesn't appear in either incident window or the later check) — yet more evidence of churn distinct from the incident-2 scale-out.

## Artifact: local chart, `orders_delay_cpu_chart.html`

Local HTML chart (not published) — 11 stacked panels: 5396/5481/5523 queue age, plus one panel per distinct CPU instance (8 total) over the same 48h window. Visually confirms the finding above: instance `...000HCJ` runs the full window; `HHQ`/`HJ4`/`HIR`/`HDX` each run for part of the first ~24h then disappear; `HJD`/`HET`/`HIZ` all start exactly at incident 2 (10:00 ART) and persist through the end of the window. Open the file directly in a browser to inspect (hover for exact values, gaps mean "instance not running," not zero).

## Real data, 2026-09-19 — Sales-Plan-PRO per-instance CPU (CORRECT resource) and activity log

Corrected resource per user (2026-09-19): the reported CPU incidents are on **`SmartFran-Cloud-Sales-Plan-PRO`**, not Orders. Pulled `CpuPercentage` (Maximum, `Instance` dimension, 5-min grain, same 48h window as the queue-age data): **10 distinct instances, most individually reaching 87-100%** (`data/sales_cpu_max_48h_per_instance.json`) — a materially more severe pattern than anything on Orders. Notable recent spikes (2026-09-19, ART): `wn1mdwk000VD4` 97-99% at 20:57-21:02; `wn1mdwk000VG1` 99-100% at 18:57-19:02; `wn0mdwk000SWC` 99-100% at 18:32-18:37 and 16:22-16:27; `wn1mdwk000VD6` 99% at 23:17-23:22 on 9/18. Chart rebuilt against this corrected data (`orders_delay_cpu_chart.html`, still local/unpublished) — none of these spikes' timestamps fall inside the originally-reported "incident 1/2" bands (08:50-09:10, 10:00-10:18 ART), which — per the user's own Portal screenshot showing an 8-10 PM axis — were most likely **PM, not AM**, an AM/PM misread on my part earlier that went uncorrected until now. The true incident times are not yet pinned down precisely; the spikes listed above are the closest real candidates found so far.

**Activity log for `SmartFran-Cloud-Sales-Plan-PRO`, first pull (hit the known 50-result cap — see `cloud/CLAUDE.md`): covered only 2026-09-18T02:59Z–2026-09-19T15:10Z, missing the entire evening of 9/19 where the spikes above actually occurred.** Confirms the scaling mechanism is **Azure Monitor autoscale** (`Microsoft.Insights/autoscaleSettings` → "Autoscale scale up/down completed" → "Update hosting plan"), i.e. horizontal instance-count changes — not a SKU/tier change. A few manual "Update hosting plan" actions by `gastona@smartfran.com` also appear on 9/18 evening (20:56-22:06 UTC), separate from the automated rule.

**Second pull, the missing evening window (15:10 UTC 9/19 → 01:00 UTC 9/20): only 1 event, a duplicate of the boundary timestamp — i.e. genuinely zero scaling activity during the entire window when VD4/VG1/SWC each spiked to 99-100%.** No autoscale response fired for any of these individual-instance saturation events. Not yet confirmed why: either the autoscale rule's metric/threshold isn't sensitive to a single instance maxing out (e.g. it triggers on plan-average CPU, which single-instance spikes might not move enough), or the rule was already at its configured max instance count and couldn't scale further. Autoscale rule configuration (thresholds, min/max instances) not yet pulled — needed to distinguish these.

## Real data, 2026-09-19 — queue-delay spikes vs. Sales CPU spikes, no tight correlation found

Computed nearest-neighbor time gaps between today's 9 queue-delay spikes (5396/5481/5523) and the 5 known Sales CPU spikes (VG1/SWC/VD4). **Closest gaps are 20 minutes** (5481@15:27 ↔ VG1@15:47; 5523@20:37 ↔ VD4@20:57); every other pair is 35-155 minutes apart. None are simultaneous or even within the same 10-minute bucket. **This doesn't support a tight causal link** between the Sales CPU saturation events and the reported queue delays — but doesn't rule out a slower/indirect relationship either (e.g. a saturated Sales instance degrading something Sales calls into, with delayed downstream effect). Not investigated further; flagging as inconclusive rather than either confirming or dismissing a connection.

## Real data, 2026-09-19 — manual `gastona` events: SKU change undetermined

Pulled full activity-log event detail (not just the summary projection) for the 4 manual "Update hosting plan" events by `gastona@smartfran.com` (2026-09-18, 20:56-22:06 UTC). The standard Activity Log entry for this operation only carries generic `properties.entity`/`properties.message` fields — **no request/response body showing the actual SKU or instance-count diff**. Cannot determine from this whether these were SKU/tier changes, instance-count changes, or something else. Would need Azure Resource Graph change history or a live `az appservice plan show` check to resolve — not pursued further this session.

## Artifact update: chart now includes escalation markers

`orders_delay_cpu_chart.html` updated with vertical dotted markers for every autoscale/manual event found: green (▲, validated categorical slot 3) for autoscale-up, gold (▼, slot 4) for autoscale-down, neutral gray (●) for manual `gastona` changes — colors validated against the existing blue/orange palette via `validate_palette.js` (all checks pass). Also fixed: branch 5523's data was overflowing the chart's right edge (its evening pull window extended past the shared 48h domain) — now clipped to the shared time range.

## Real data, 2026-09-20 — NEW manual SKU escalation, and the first tight time-correlation found all session

**New event, `gastona@smartfran.com`, "Update hosting plan": Started 02:18:54 UTC, Succeeded 02:18:56 and 02:28:54 UTC (2026-09-20)** — i.e. **23:18-23:28 ART on 2026-09-19**. Not autoscale (caller is the human account, not `Microsoft.Insights/autoscaleSettings`).

**Strong corroborating evidence this was an actual SKU/tier change, not just an instance-count scale-out:** right at 02:17 UTC, three brand-new instances appear with a **different worker-name prefix** — `wn1ldwk0002XC`, `wn1ldwk0002VU`, `wn1ldwk0002WT` (`wn1l...`) — versus every prior instance's `wn0m`/`wn1m`/`wn0x`/`wn1x` prefix. A different prefix is consistent with a different underlying VM family (real SKU change), not the same-prefix pattern a horizontal scale-out would produce. The old saturated instances (`VD4`, `VG1`, `SWC`, all hitting 99-100% right up to 01:57-02:22 UTC) have no further data points after ~02:22-02:27 UTC — replaced by the new `wn1l` instances, which run at a much cooler **14-18%** in their first ~35 minutes of data. This looks like a real, effective mitigation: old high-CPU instances retired, replaced by new ones on (likely) a bigger/different SKU, CPU immediately much lower.

**First tight time-correlation with the queue-delay symptom found all session:** 5481 had a delay spike at **23:17-23:22 ART** (69s→127s) and 5396 at **23:27-23:32 ART** (58s→183s) — both essentially coincident with the 23:18-23:28 ART SKU change window. Every other delay-spike/CPU-event pairing checked earlier was 20+ minutes apart; these two are within minutes. **Flagging as the strongest candidate connection found so far, not a confirmed cause** — a brief disruption during an App Service Plan SKU cutover (instance replacement, connection draining) plausibly could cause a transient processing delay on the Orders bridge, but this hasn't been verified against the actual mechanism (e.g. checking whether Orders-PRO itself saw anything unusual in this same window) and could still be coincidental given the recurring nature of these delay spikes throughout the whole 48h dataset.

## MAJOR FINDING, 2026-09-20 — real Sales-PRO platform-wide timeout cascade, 2026-09-18 21:50-22:00 UTC, with a plausible causal chain to the reported delays

Built via `/cloud-appservice-perf-report` (Graylog raw HTTP export + Sales-Plan-PRO CPU/RAM, linked report: `data/timetaken_report.html`, incident markers in `incidents.txt`). The build script's own sanity check flagged **46 bucket/path rows within 5s of Azure's 230000ms Windows App Service idle timeout** — inspected directly rather than just noted.

**The 21:50-22:00 UTC bucket on 2026-09-18 (18:50-19:00 ART) shows a platform-wide latency collapse across nearly the entire Sales-PRO API surface** — not one endpoint, at least 20 distinct routes affected simultaneously (`data/timetaken_by_path_aggregated.csv`, full bucket dump). Worst offenders:

| Endpoint | Status | Count | Avg ms | Max ms |
|---|---|---|---|---|
| `Sale/Create` | 500 | 98 | 249,998 | 451,434 |
| `Sale/Close` | 500 | 32 | 243,864 | 378,147 |
| `Shift/AddSaleSession` | 500 | 10 | 273,241 | 361,016 |
| `WsFeAr/CaeRequest` | 500 | 41 | 249,964 | 349,534 |
| `Shift/GetLastShifts` | 200 | 245 | 19,514 | 276,087 |
| `Sale/Create` | 200 | 558 | 11,498 | 227,302 |
| `Sale/Close` | 200 | 397 | 3,349 | 229,929 |

98 `Sale/Create` calls failed outright with HTTP 500 after ~4-7.5 minutes; hundreds more (558 `Sale/Create`, 397 `Sale/Close`) technically succeeded but only after multi-second-to-multi-minute delays. This is a genuine, severe production degradation, not noise.

**Timeline this fits into, in causal order:**
1. **21:12-21:22 UTC (9/18):** `wn1mdwk000VD4`/`VD6` Sales instances spike to 99% CPU (see per-instance CPU finding above).
2. **21:06-22:06 UTC (9/18):** `gastona@smartfran.com` makes 4 manual "Update hosting plan" changes on Sales-Plan-PRO — squarely overlapping the incident.
3. **21:50-22:00 UTC (9/18):** the platform-wide Sales API timeout cascade above.
4. **22:02-22:07 UTC (9/18, ART 19:02-19:07):** real queue-delay spikes on **both** 5396 (119s, 185s) and 5481 (14s, 131s) — 2-17 minutes after the cascade started.

**This is a materially stronger candidate than anything found earlier this session** (the prior nearest-neighbor check found only 20+ minute gaps against isolated CPU spikes on 9/19; this is a specific, severe, multi-endpoint HTTP-layer failure event immediately followed by real queue delays on two branches, with a mechanistically plausible chain: CPU saturation → HTTP-layer request pileup/timeout across the Sales API → some dependency of the Orders bridge on Sales (not yet confirmed which) → delayed queue processing). **Still not confirmed as causal** — the actual dependency path from Sales-PRO to the Orders/SQS bridge hasn't been traced in code, and it's one correlated instance, not a repeated pattern (the similarly severe 9/19 CPU spikes, e.g. VD4 99-100% at 20:57-21:02 ART, weren't checked against an equivalent HTTP-timeout-cascade query — only against the coarser per-instance CPU data).

## Real data, 2026-09-20 — the timeout cascade does NOT recur around the 9/19 CPU spikes (important nuance)

Checked the same endpoint-level data against all 5 known 9/19 Sales CPU spike windows (VG1/SWC/VD4, 15:47-21:02 ART). **Only one trivial hit**: 2 `Movement/POSGetAll` 500s at exactly the 230s timeout, 21:30 UTC — nothing resembling 9/18's 20+-endpoint, hundreds-of-requests cascade. The 9/19 spikes reached the same 99-100% CPU magnitude as 9/18's, yet produced no comparable HTTP-layer failure.

**This weakens "CPU saturation alone triggers the cascade"** as an explanation and points more specifically at something unique to the 9/18 21:50 UTC window — most plausibly `gastona`'s manual "Update hosting plan" actions themselves (21:06 and 21:56 UTC bracket the cascade), which can involve instance draining/restart, not just a capacity change. **Not confirmed** — could also be a traffic-volume or timing coincidence specific to that evening. The 2026-09-20 SKU escalation (02:18-02:28 UTC, also a `gastona` manual change) is the one to watch for the same pattern, if/when fresh HTTP-level data covering that window is pulled — not yet done (the Graylog export used for this section covers the same rolling 48h window that also includes 02:18-02:28 UTC 9/20, but that specific window hasn't been checked yet — see below).

## Real data, 2026-09-20 — the cascade does NOT recur around the new SKU-change window either

Checked 2026-09-20T02:00-02:30 UTC (the SKU-escalation window) directly. **Only one trivial hit**: a single `Movement/POSGetAll` 500 at exactly 230008ms, 02:20 UTC — every other endpoint in this window performed normally (`Sale/Create` averaging ~17s max even at its busiest bucket, no mass 500s). **This weakens the "manual plan change triggers cascades" theory too** — neither of the two things present during the 9/18 incident (severe CPU spike, manual `gastona` change) reliably reproduces it on their own. The 2026-09-18 21:50-22:00 UTC event looks like a genuinely isolated, severe one-off rather than a repeating pattern tied to either factor alone. What actually made that specific window different remains unexplained.

## Not yet done

**Active, high-priority (Sales-Plan-PRO thread — the current best lead):**
- Trace the actual code-level dependency (if any) from Sales-PRO to the Orders API/SQS bridge — needed to explain *why* a Sales-side timeout cascade would delay Orders queue processing at all, since they're documented as separate services. This is the single biggest gap: without it, the 9/18 21:50-22:00 UTC finding is a strong correlation, not a mechanism.
- Verify the 9/18 cascade↔delay-spike correlation isn't coincidental: check whether Orders-PRO (the actual SQS consumer) shows any anomaly (errors, restarts, deploys) in the 22:00-22:10 UTC window specifically (right after the cascade).
- Confirm the actual before/after SKU tier for Sales-Plan-PRO (e.g. `az appservice plan show` now vs. before 2026-09-20T02:18Z) — the `wn1l` vs `wn0m/wn1m` prefix-change is strong circumstantial evidence of a real SKU change but not direct confirmation of the tier name itself.
- Pull the autoscale rule's actual configuration (`az monitor autoscale show`) for Sales-Plan-PRO — need thresholds and min/max instance count to explain why zero scale-out happened during confirmed 99-100% single-instance spikes on 9/19.
- What actually made the 9/18 21:50-22:00 UTC window different from every other CPU spike/manual-change event checked (all of which failed to reproduce the cascade) — still completely unexplained.

**Lower priority / not yet pursued:**
- Historical baseline before 2026-09-17 for 5396/5481/5523 — needed to confirm whether the steady ~100-200s recurring delay is new or pre-existing/normal-for-this-branch behavior.
- **5523 Graylog result is a partial sample (100/390)** — re-run with a higher `limit` (or `AND AppLevel:Error` added to the free-text query) to check the remaining hits for any exception.
- **Retry `Service:Orders`-filtered Graylog error search as free-text instead** — e.g. `"5396" OR "5481" AND "Error"` — the field-filtered form has never once returned real results in this or GITIN-2068's investigation.
- Open questions 1-6 from the top of this file (Grido's own reported delay magnitude, ongoing status, exact start time, branch scope) — still not answered by the original reporter. Largely superseded by our own direct telemetry (we've independently confirmed the delay is real, recurring, and still happening as of 9/19 evening), but the reporter's own framing was never obtained.

**Deprioritized — superseded by the Orders→Sales resource correction, kept for the record, not being pursued further:**
- Confirm whether the ~09:52-10:02 ART daily CPU spike (found on **Orders**-Plan-PRO) recurs before 9/18, or maps to a scheduled job — this was on the wrong resource for the actual incident; low value now.
- Confirm whether `SmartFran-Cloud-Orders-Plan-PRO` hosts other apps besides Orders API (was chasing the empty-App-Insights-telemetry mystery on the wrong resource).
- Check Kudu/`AppServicePlatformLogs` for Orders-PRO's empty-telemetry windows — same reason, deprioritized.

## Current synthesis, 2026-09-20 (for a session picking this up cold)

Grido's original complaint (delay receiving orders, branches 5396/5481, later 5523) is **confirmed real and recurring** via direct SQS `ApproximateAgeOfOldestMessage` telemetry — typically 2-3 min, worst case ~26 min, still happening as of the most recent data pull. The investigation's center of gravity shifted from the Orders/SQS bridge itself (no errors found there, two Graylog query patterns checked) to **Sales-Plan-PRO**, after the user separately flagged CPU incidents there. That thread found: (a) individual Sales instances repeatedly saturating to 99-100% CPU with no reliable autoscale response, (b) one genuinely severe, isolated HTTP-timeout cascade across ~20 Sales endpoints on 2026-09-18 21:50-22:00 UTC that lines up within minutes of real queue-delay spikes on two branches — the best lead found so far, but **not yet explained mechanistically** (no known code dependency from Sales to Orders has been traced) and **not reproduced** by any later, similarly-severe CPU spike or manual SKU change. The single most valuable next step is tracing whether Sales-PRO and the Orders/SQS bridge share any real dependency (a shared DB, a synchronous call, a shared connection pool) that could explain the 9/18 cascade's downstream effect — without that, this remains a strong but unconfirmed correlation.

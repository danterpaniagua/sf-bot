# Investigation: Sales-PRO CPU discrepancy — Azure Monitor vs App Insights Live Metrics

**Jira:** [GITIN-2085](https://smartit-ar.atlassian.net/browse/GITIN-2085) — "[CLOUD] Discrepancia en Metrics de Insights"

**Status:** open, 2026-09-18 — early triage, correlating with the live `Sales_CPU_Alert` escalation trigger.

## Reported symptom (2026-09-18)

User observed an instance at 100% CPU usage yesterday (2026-09-17) 20:00-22:00 UTC-3, apparently from an Azure Monitor metric/alert view. App Insights Live Metrics did not show the same spike for the same window/instance.

**Escalation-relevant**: user confirmed a real escalation trigger depends on this CPU data, so this isn't purely diagnostic — need to establish whether the escalation is reading a real signal or a false one, and from which data source.

## Scope confirmed

- App Service: `SmartFran-Cloud-Sales-PRO`, RG `SmartFran.Cloud.PRO`, subscription SmartIT Cloud (`85c76dea-3304-4310-8656-bf21b28e4f4b`).
- App Insights component: `SmartFran-Cloud-Sales-PRO_new`.
- Window in question: `2026-09-17T23:00:00Z` – `2026-09-18T01:00:00Z` (= 20:00-22:00 UTC-3 on 2026-09-17).

## Working hypothesis (not yet confirmed against real data)

- App Insights Live Metrics is a real-time-only stream with no history — comparing it against yesterday's window isn't meaningful on its own; the actual historical comparison needs App Insights `performanceCounters` (process CPU) vs Azure Monitor `Percentage CPU` (host-level, App Service Plan scope) for the same window/instance.
- Host-level and process-level CPU are different metrics by definition (host includes noisy-neighbor/platform overhead on the shared Plan; process is just this app's `w3wp.exe`) — a real divergence between them doesn't by itself mean either reading is wrong.
- Whether the escalation (`Sales_CPU_Alert`) is affected depends on which of these two it's actually scoped to — not yet confirmed.

## Findings so far

- `az monitor metrics alert list -g SmartFran.Cloud.PRO` (RG-scoped) returned empty — contradicted by the subscription-wide listing below (same RG shows results there). Likely a CLI/API quirk with the `--resource-group` filter on this alert type; not chased further since the subscription-wide listing is reliable.
- Subscription-wide `az monitor metrics alert list` found `Sales_CPU_Alert` (plus `Sales_Memory_Alert`, `PRO-Sales-HealthCheck-Error`) in `SmartFran.Cloud.PRO` — full list in `data/alert_rules_list_subscription_wide.txt`.

## Findings — alert definition confirmed (`data/sales_cpu_alert_definition.json`)

`Sales_CPU_Alert` is scoped to `/subscriptions/.../resourceGroups/SmartFran.Cloud.PRO/providers/Microsoft.Web/serverfarms/SmartFran-Cloud-Sales-Plan-PRO` — the **App Service Plan**, i.e. host-level CPU, not the site. Metric `CpuPercentage`, namespace `Microsoft.Web/serverfarms`, `StaticThresholdCriterion`, operator `GreaterThan`, threshold `80.0`, `timeAggregation: Average`, `windowSize: PT5M`, `evaluationFrequency: PT1M`, dimension `Instance` included `*` (any instance). Severity 2, `autoMitigate: true`, action group `Correos-Cloud` (email).

**Implication**: the alert is intentionally watching host-level CPU, a different signal from App Insights' process-level telemetry — the two not matching in Live Metrics doesn't by itself mean the alert is a false positive. Still need the actual host-CPU metric data for the window to (a) confirm the reading was real, not a collection glitch, and (b) identify which instance triggered it.

## Findings — host CPU confirmed real (`data/sales_plan_cpupercentage_20260917_2000_2200_art.txt`)

Real, sustained spike on instance **`wn0xsdwk00072R`**: ramps to 47% avg (99 max) at 23:20Z, then 94-98% avg / 100% max continuously from 23:25Z through 00:30Z (~65 min), drops sharply by 00:40Z (down to single digits by 00:45Z). = **20:20-21:30 ART**, close to (slightly narrower/shifted from) the reported 20:00-22:00 ART window.

Given the alert's `>80% average over a 5-min window, evaluated every 1 min`, this instance would have crossed threshold repeatedly through that stretch — **this is a real host CPU event, not a metric-collection glitch**.

Other instances in the same window: `wn1xsdwk00076O` stayed low (~5-9%); `wn0xsdwk000742` had a smaller, brief, separate spike (52% avg at 23:35Z only, unrelated to the sustained one); `wn0xsdwk000721`, `wn0xsdwk00075L`, `wn1xsdwk0007D7`, `wn0xsdwk00074X` returned no data at all for this window (blank Average/Maximum) — not yet explained, possibly not provisioned/active then.

## Findings — App Insights shows ZERO telemetry for Sales-PRO in this window (not just CPU)

Three separate App Insights queries against `SmartFran-Cloud-Sales-PRO_new` for `2026-09-17T23:00:00Z`–`2026-09-18T01:00:00Z` all returned empty:
- `performanceCounters` filtered by `name contains 'CPU'` — empty (`data/sales_appinsights_perfcounters_cpu_20260917_2000_2200_art.txt`)
- `performanceCounters` unfiltered, grouped by `name` — empty, i.e. no perf-counter telemetry of *any* name (`data/sales_appinsights_perfcounters_allnames_20260917_2000_2200_art.txt`)
- `requests` grouped by `cloud_RoleInstance` — empty, i.e. no request telemetry either (`data/sales_appinsights_requests_summary_20260917_2000_2200_art.txt`)

**Reframes the original question**: this isn't host-CPU-vs-process-CPU showing different values — App Insights received no telemetry of any kind from Sales-PRO for this window, so there was nothing for Live Metrics (or any historical App Insights query) to show regardless of CPU definition.

**Same unexplained pattern as a prior, separate event**: `20260913_pos-net-http-timeout` found App Insights showing zero `requests` telemetry for Pos-PRO despite the app being confirmed alive via Graylog traffic — never explained there either. Both are Windows-hosted App Services on the same SmartFran Cloud stack. Not yet confirmed as the same root cause, but a strong parallel worth carrying forward.

- **Confirmed ongoing, not just historical.** `requests` for Sales-PRO over the last 6h (from now, 2026-09-18) — also empty (`data/sales_appinsights_requests_last6h.txt`). App Insights currently receives no telemetry at all from Sales-PRO.

## Conclusion (original question)

The escalation (`Sales_CPU_Alert`) is **real and trustworthy** — host CPU genuinely hit ~95-100% average sustained for ~65 minutes on instance `wn0xsdwk00072R`, well past the alert's 80%-over-5-min threshold, so it should have fired (email via `Correos-Cloud` action group) repeatedly during that stretch.

Live Metrics/App Insights didn't show it not because of a host-vs-process CPU definition mismatch, but because **App Insights currently has zero telemetry of any kind for Sales-PRO** — an ongoing gap, not specific to that window. This matches an already-known, previously unexplained pattern on Pos-PRO (`20260913_pos-net-http-timeout`) — same SmartFran Cloud stack, both Windows-hosted App Services.

## Open follow-up — separate from the original question

The App Insights telemetry gap itself is unresolved and now confirmed on two App Services (Sales-PRO, Pos-PRO). Not yet checked here: instrumentation key/connection string wiring on Sales-PRO's App Service config (was already checked and ruled out as the cause for Pos-PRO). Given its scope (spans services, matches an existing unresolved precedent), this may warrant its own tracked event rather than continuing under this one — pending user decision.

## Live update (2026-09-18, later same session)

User reports Sales-PRO currently has one instance at 100% CPU, happening now (not the 2026-09-17 historical window above).

**Confirmed against real data** (`data/sales_plan_cpupercentage_live_20260918_2152.json`, `CpuPercentage` on `SmartFran-Cloud-Sales-Plan-PRO`, last 30 min, per-`Instance`): instance **`wn0sdwk000AXF`** sustained ~98-99% average / up to 100% max continuously across all 29-30 one-minute data points in the window (21:22-21:52 UTC) — not a spike, pegged the whole time. The other currently-active instance, `wn0sdwk000AXR`, is normal (8-16% average). This is real, sustained saturation, well past `Sales_CPU_Alert`'s 80%-over-5min threshold — would be actively firing right now.

Instance IDs are different from the 2026-09-17 incident (`wn0xsdwk00072R` and the other 6 IDs from that window all return **no data** now — recycled/replaced instances, standard App Service behavior on restart/redeploy/scale). Only 2 instances currently active vs. 7 seen yesterday — plan may have scaled down since, not yet confirmed why or whether that's related to the CPU saturation.

Not yet checked: whether App Insights telemetry is still zero for Sales-PRO right now (would extend the open gap above into "still ongoing" rather than yesterday-only), and whether this live saturation is Cosmos-retry-driven — cross-reference against `cloud/events/20260918_sales-cosmos-403-firewall/` open, though that investigation found Sales was NOT among the services hit by the Cosmos 403 burst (Business/Person/Orders only), so a direct causal link isn't supported yet.

## w3wp process inspection via Kudu — instance identity NOT verified, treat prior sample as unconfirmed

Two `Get-Process w3wp` samples ~1 min apart were captured via a Kudu console the user opened, believed to be on `wn0sdwk000AXF` (the instance found pegged in the Azure Monitor pull above) — **but this was never actually confirmed**, the console's own hostname was never checked at the time. Sample data (for reference, instance unconfirmed):

- PID 5628 (started 18:49:47 ART): 46→51 threads, 1490→1512 handles, CPU 8.34s→8.36s — quiet/idle, likely a draining process from a prior recycle.
- PID 9440 (started 18:54:37 ART, newer process): 83→79 threads, 3262→3238 handles, CPU 73.47s→75.63s — elevated threads/handles for a short-lived process, but *not* growing between samples (slightly declining), so not confirmed as "actively spiraling" — could be stabilized, or the load may have already eased since the 21:43-21:52 UTC Azure Monitor pull.

**Instance churn discovered right after:** Portal's Instances blade (source of truth) now shows only `WN1MDWK000VD4` (eastus-az3) and `WN1MDWK000VD6` (eastus-az2) — matching neither `wn0sdwk000AXF/AXR` (the Azure Monitor pull) nor confirming which instance the w3wp sample above was even taken on. The App Service Plan has recycled its instance set at least twice within this session's timeframe. **Do not treat the w3wp thread/handle/CPU numbers above as still-current** — they're an unconfirmed historical data point, not live state.

## Pattern reproduced independently on a verified instance (`WN1MDWK000VD6`)

Re-ran `Get-Process w3wp` from a Kudu console reached via the Portal Instances blade's own "View" link for `WN1MDWK000VD6` — instance identity confirmed this time.

| PID | StartTime (ART) | Threads | Handles | CPU(s) |
|---|---|---|---|---|
| 1396 | 18:56:54 | 81 | 3090 | 97.7 |
| 8252 | 19:01:36 | 47 | 1166 | 3.4 |

`1396` (~5 min older) has accumulated ~97.7 CPU-seconds — consistent with near-continuous single-core saturation for essentially its whole lifetime, not an intermittent spike. `8252` (~5 min younger) is quiet.

**Correction — the "reproduced independently" read above was wrong, based on a miscalculation.** `Get-Process`'s `CPU(s)` field is *total accumulated CPU-seconds since process start*, not a percentage. PID `1396` (97.7s CPU, alive ~6-7 min at sample time) works out to roughly 20-25% average of one core, not near-continuous saturation. Retracting the "same signature reproduced" conclusion.

## Fresh Azure Monitor pull — spike already self-resolved, instance set recycled (`data/sales_plan_cpupercentage_live2_20260918_2205.json`)

`wn0sdwk000AXF` (the instance pegged 97-99% through 21:50-21:54 UTC) **declined and cleared on its own**: 90.5% (21:55) → 40.5% (21:56) → 23.8% (21:57) → 2.7% (21:58) → ~0% (21:59-22:00). Total sustained-pegged duration at minimum 21:43-21:54 UTC (~11+ min from the first live pull), likely longer given the historical 2026-09-17 incident self-resolved after ~65 min on the same pattern.

**New instances `wn1mdwk000VD4`/`wn1mdwk000VD6` appear starting exactly 21:58 UTC** — the same minute `AXF` crashed down — confirming the Instances-blade churn we hit mid-session was a real recycle, not a stale UI. Both new instances show a modest startup burst (23-29% avg, up to 54% max at 21:58) tapering to low single digits (3-8%) by 22:00-22:04 — consistent with normal process warm-up, **not** a repeat of the sustained pegging. `VD6`'s host-level numbers (28.8%→5.5% avg) also reconcile with the corrected `Get-Process` read above (PID `1396` ~20-25% of one core), not the "near-100%" I'd wrongly inferred.

**Current state (as of 22:04-22:05 UTC): nothing is actively pegged.** The real, sustained spike happened and self-resolved (matching yesterday's pattern) roughly coincident with an instance recycle — not yet established whether the recycle *caused* the resolution (e.g. platform auto-heal on high CPU) or was unrelated/coincidental. Root cause of the underlying CPU spike itself (thread-pool starvation vs. legitimate heavy load vs. something else) is still **not confirmed** — the `.NET`/ASP.NET Core counter-set query (exception rate, thread-pool queue) was never successfully returned, and with the spike now cleared, capturing that live is no longer possible for this occurrence. Worth checking whether Sales-PRO has an `autoHealRules` / CPU-based auto-heal configured, and treating this as likely-recurring (given the 2026-09-17 precedent) rather than resolved.

## New leading hypothesis — Service Bus retry storm driven by the Cosmos firewall gap (2026-09-18)

Source check (`cloud/repo/SmartFran.Cloud`, `origin/dev`) found `SmartFran.Cloud.Sales.API` runs two `BackgroundService`s — `MoneyMovementConsumer`, `StockMovementConsumer` (`Source/Services/Sales/SmartFran.Cloud.Sales.Application/Services/SaleClose/Abstractions/`) — each starting **one `ServiceBusProcessor` per tenant**, consuming the `"SaleClosed"` topic's `money`/`stock` subscriptions. Both handlers do Cosmos **partial-document patches** and both have an explicitly-documented Polly circuit breaker "protección contra retry storm": opens if >50% of Cosmos-writing calls fail in a 30s/10-call window (stays open 1 min, then half-open); while open or on any transient failure, the message is `AbandonMessageAsync`'d and **redelivered for retry**.

Given `cloud/events/20260918_sales-cosmos-403-firewall/` confirms **0% Cosmos firewall coverage** for every service, including Sales-PRO's own outbound IPs, every Cosmos patch call from these two consumers would currently be failing with 403 — precisely the failure shape this circuit breaker exists to survive (fail fast, abandon, redeliver, retry indefinitely). This is a plausible mechanism for a background-service-driven CPU/thread burn that reproduces on whichever `w3wp` process is currently active, independent of instance identity — consistent with what was observed. **Not yet proven** — would need one of: Service Bus DLQ/message-count data for the `SaleClosed` topic's `money`/`stock` subscriptions during the 21:43-21:58 UTC window (redelivery count spike would support this directly), or the `stock_circuit_breaker_state` metric mentioned in the consumer's own doc comments, if it's exposed anywhere queryable. Next step if pursued further.

### Checked — evidence weakens this hypothesis, not confirmed

- Per-subscription counts on `SaleClosed` (`az servicebus topic subscription list`): `money` — 0 active, 1 dead-lettered; `stock` — 1 active, 6 dead-lettered. Small numbers, not obviously consistent with a sustained multi-minute retry storm.
- Namespace-wide `DeadletteredMessages` metric (`data/servicebus_deadletter_spike_window.json`), 21:40-22:00 UTC at 5-min resolution: **flat at 35.0 for every data point** — no increase during the 21:43-21:58 CPU spike window.

If a retry storm were driving the CPU, the dead-letter count would be expected to climb during the spike, not sit flat. **Downgrading this from leading hypothesis to unconfirmed/weakened** — the circuit breaker's abandon-and-redeliver behavior doesn't necessarily increment the dead-letter count (that only fires once max delivery attempts are exhausted), so this doesn't fully rule out elevated retry *traffic* underneath, but it's no longer the best-supported explanation. Root cause of the CPU spike remains open.

### Throughput data — retry-storm theory ruled out, reversed direction (`data/servicebus_salecosed_throughput_spike_window.json`)

`IncomingMessages`/`OutgoingMessages` on the `SaleClosed` topic, 1-min resolution, 21:35-22:04 UTC:

| Window | Incoming/min | Outgoing/min |
|---|---|---|
| 21:35-21:39 (before spike) | ~55-65 | ~110-130 |
| 21:43-21:55 (during CPU spike) | drops steadily to 1-5 | drops steadily to 2-10 |
| 21:56-22:04 (after recycle) | back to ~50-65 | back to ~100-130 |

**Opposite of what a retry storm predicts.** Message throughput *collapsed* during the CPU saturation rather than spiking, then surged back to/above baseline the moment the recycled instance came online — consistent with message processing being throttled/starved as a *symptom* of whatever was consuming CPU (the pegged process pulling fewer messages per minute because it's blocked/slow), with the post-recycle burst being backlog catch-up, not evidence of the cause. **Service Bus / Cosmos-retry-storm hypothesis is now ruled out as the cause** — root cause of the original CPU spike is still open, and Service Bus data doesn't point anywhere further on its own.

### User hypothesis checked — "Cosmos outage queued messages, burst-draining them caused the spike" — does not fit the data (2026-09-18)

Proposed: Sales couldn't reach Cosmos → messages queued in Service Bus → once restored, the backlog was sent out all at once, causing the ~100% CPU spike. Checked against the timeline already gathered:

- The spike (97-99% CPU) ran **21:43-21:55 UTC**, i.e. *before* the 21:56:54 recycle — but the hypothesis predicts the spike happens *after* restoration, when the backlog drains.
- Throughput was actually **lowest** during the spike (21:43-21:55) and only returned to baseline **after** the recycle (21:56+), while the new instances' CPU stayed modest (23-29% tapering to 5-8%) — the highest-throughput period had the *lowest* CPU, not the highest.
- **Timing gap with the Cosmos firewall burst itself:** the confirmed Cosmos 403 errors (`cloud/events/20260918_sales-cosmos-403-firewall/`) ran **21:08:00-21:09:56 UTC** — about **33 minutes before** this CPU spike even started (21:43 UTC). The two events don't overlap or sit adjacent in time.

**Conclusion: this hypothesis doesn't fit the gathered evidence** — wrong direction on throughput, and a 33-minute gap between the Cosmos errors and the CPU spike. Not ruling out *some* Cosmos/Sales interaction entirely (the Cosmos firewall gap is real and ongoing, so Sales' consumers are presumably still failing Cosmos calls intermittently throughout), but it isn't the explanation for *this specific* CPU spike. Root cause remains unresolved — no further avenues identified without the event recurring live and capturing exception-rate/thread-pool data in the moment.

## Follow-up sample — same PID/StartTime under a different claimed instance label

A later `Get-Process w3wp` sample, reported by the user as taken on `wn1mdwk000VD4`, shows **PID `1396`, StartTime `9/18/2026 6:56:54 PM`** — identical to the earlier `VD6` sample. CPU(s) grew 97.7→136.3s, threads 81→78, handles 3090→3135. **Confirmed genuinely different instances** (`$env:COMPUTERNAME` = `wn1mdwk000VD4`, distinct `$env:WEBSITE_INSTANCE_ID` from the `VD6` session) — not a mislabeling. Two independent VMs' `w3wp.exe` starting at the identical second (`18:56:54`) points to a **coordinated restart across the App Service Plan** (deployment, slot swap, or platform-triggered scale/restart event) rather than coincidence. **Confirmed via Activity Log** (`data/activity_log_sales_2150_2200.txt`, `SmartFran.Cloud.PRO`, 21:50-22:00 UTC window): a `Microsoft.Web/serverfarms/write` operation (Started 21:56:40Z, Succeeded 21:56:43Z) by a named internal user (identity kept out of this file per repo convention — see the raw data file, or ask in conversation) — i.e. a **manual write to the App Service Plan itself**, ~11 seconds before both instances' `w3wp.exe` started in sync at 21:56:54Z.

This reframes the resolution: the CPU spike's decline (99%→90.5%→40.5% across 21:54-21:56, reaching near-zero by 21:58 as `VD4`/`VD6` took over) lines up with this manual plan write, not with an automatic CPU-triggered auto-heal or a self-resolving pattern like 2026-09-17. Someone likely made a scaling/config change to the plan (possibly in direct response to the `Sales_CPU_Alert` firing) that triggered the recycle and ended the spike. Root cause of the *original* CPU saturation itself is still not established — only that a manual intervention is what cleared it this time, which is a different mechanism than the 2026-09-17 precedent (self-resolved with no corresponding plan write seen then, not re-checked to confirm). Following up directly with whoever made this change is likely the fastest way to close this out, faster than further log archaeology.

**Confirmed by user (2026-09-18):** the App Service Plan's size was manually doubled (SKU/tier increase) in response to the alert — consistent with the `serverfarms/write` operation, the synchronized instance restart (a SKU change forces a recycle of every instance on the plan), and the CPU dropping to near-zero right after. This explains the *resolution mechanism* fully.

**Still open — the original root cause of the spike itself.** Doubling capacity is a valid response if this was legitimate load outgrowing the plan's prior size (in which case the fix may be appropriate/permanent), but doesn't distinguish that from a runaway/bug-driven CPU consumer (in which case doubling size only buys headroom and the same issue could recur at a higher load threshold). Not yet determined which. Exception-rate/thread-pool counters were never captured during the live spike (Get-Counter attempts failed/returned nothing, Event Log blocked by sandbox, Profiler blade not yet confirmed checked) — if this recurs, prioritize capturing those live, before any recycle/scale action clears the evidence again.

**Misreading caught and corrected in conversation:** `Get-Process`'s `CPU(s)` field is cumulative CPU-seconds since process start, not a percentage — a value like `136.3` does not mean "136% CPU," it means 136 seconds of accumulated processor time. Taking the growth rate at face value (+38.6s CPU across however long elapsed between samples) is consistent with the Azure Monitor host data showing this instance settled to 5-8% average by 22:00-22:04 UTC — i.e. still reads as cooled-down/normal, not a renewed spike.

## Windows Event Log access — dead end (App Service sandbox restriction)

`Get-WinEvent -LogName Application` from the Kudu console throws `UnauthorizedAccessException` — direct Event Log access is blocked in the App Service Windows sandbox (expected platform behavior, not specific to this app). The earlier `Get-WinEvent -FilterHashtable ... -ErrorAction SilentlyContinue` query that returned no output was **not** "zero events in the window" — it was silently hitting the same permission failure. Retracting that as inconclusive, not a real absence-of-errors finding. This avenue is closed off entirely from Kudu; remaining leads for root-causing the spike: Application Insights Profiler (Portal, not Kudu — worth checking given `ApplicationInsightsProfiler.exe` was confirmed running), DaaS auto-collected artifacts (`D:\home\LogFiles\DaaS`, requested, not yet checked), and `netstat`/`handle.exe` for current connection/handle state (requested, not yet returned) — though the spike itself has already cleared, so these now only speak to current state, not the historical spike.

## Diagnostic Settings on Sales-Plan-PRO confirmed empty (2026-09-19)

Resumes a finding from a prior session (before a context `/clear`) that was never written to this file — re-verified live against real data rather than trusted from memory, per the "unconfirmed action/claim" rule.

`az monitor diagnostic-settings list --resource "/subscriptions/85c76dea-3304-4310-8656-bf21b28e4f4b/resourceGroups/SmartFran.Cloud.PRO/providers/Microsoft.Web/serverfarms/SmartFran-Cloud-Sales-Plan-PRO"` returns `[]` — **zero Diagnostic Settings configured on the App Service Plan resource itself.** Raw output: `data/sales_plan_diagnostic_settings.json`.

**Scope caveat — not yet tied to a specific alert mechanism.** Diagnostic Settings control export routing (Log Analytics / Event Hub / Storage); they are a separate mechanism from Azure Monitor Metric Alerts like `Sales_CPU_Alert`, which read the platform metric store directly and don't require a Diagnostic Setting to fire — this investigation already confirmed `Sales_CPU_Alert` would have fired correctly off real host CPU data with no diagnostic setting involved. So this empty result doesn't by itself explain an "insight alert not firing" complaint; **not yet confirmed which alerts that refers to** (Application Insights Smart Detection/anomaly alerts — which would plausibly be blocked by this, and separately by the zero-telemetry-to-App-Insights gap already confirmed above for Sales-PRO — vs. something else). Needs clarification before drawing a causal conclusion.

## Alert firing history — contradicts the "not firing" premise (2026-09-19)

Queried the Alerts Management API directly (`Microsoft.AlertsManagement/alerts`, `targetResource=SmartFran-Cloud-Sales-Plan-PRO`, `timeRange=7d`) rather than inferring from CPU data alone — `data/alerts_fired_history_sales_plan_7d.json`.

**Both `Sales_CPU_Alert` and `Sales_Memory_Alert` fired repeatedly — ~40 instances combined between 2026-09-15 and 2026-09-19.** Every instance shows `monitorCondition: "Resolved"` (fired, then auto-resolved, consistent with `autoMitigate: true`) and `actionStatus.isSuppressed: false` — actions were not suppressed on any of them. This is a recurring, frequent pattern (multiple firings per day on some days), not an isolated event.

**Action group `Correos-Cloud` confirmed valid** (`data/actiongroup_correos_cloud.json`): `enabled: true`, one email receiver `gastona@smartfran.com`, `status: "Enabled"`, not suppressed anywhere in the fired-alert data above.

**Conclusion: the "insight alerts not firing" premise this ticket (and GITIN-2073's scoping) started from does not hold up against this data.** The alert rules and action group are both working as configured. The Diagnostic Settings gap on the Plan (confirmed empty earlier in this file) and the App Insights zero-telemetry gap are both real, but neither is the cause of a firing failure — because there isn't one, per this data.

**Reframed open question:** if the user isn't seeing/acting on these alerts, the actual gap is downstream of firing — mailbox delivery to `gastona@smartfran.com`, spam/filtering, whether that's even the intended recipient for this escalation, or alert fatigue from ~40 firings in 4 days causing them to be ignored. Not yet investigated — different mechanism than anything chased so far in this file.

## Last-trigger detail reveals the real mechanism: Autoscale uses a different (averaged) CPU view than the alert (2026-09-19)

Pulled the single-alert detail for the most recent `Sales_CPU_Alert` firing (`data/last_trigger_detail_feb5f502.json`) plus the Activity Log for that exact window (`data/activity_log_last_trigger_window.json`).

**Alert fired correctly, per-instance:** condition context shows `dimensions: [{"name": "Instance", "value": "wn1mdwk000VD4"}]`, `metricValue: 92.8333...`, window `04:58:00.909Z`–`05:03:00.909Z`, threshold `80`. Confirms the per-instance split-by-dimension evaluation already established — this specific instance's real CPU crossed threshold and the alert fired at `05:05:06Z`.

**Activity Log for the same window shows a second, separate mechanism reading the metric differently: Autoscale.** `SmartFran-Cloud-Sales-Plan-PRO-Escalabilidad Automática-96` scaled the Plan **1→2 instances at 05:05:25Z** (~19s after the alert fired), then **back down 2→1 at 05:11:25Z** (~6 min later, once average cooled below 70%). Its rule definition (embedded in the Activity Log's `ActiveAutoscaleProfile` property):

```
Scale up:   CpuPercentage > 80, Average, PT5M window, PT1M grain, DividePerInstance: false
Scale down: CpuPercentage < 70, Average, PT10M window, PT1M grain, DividePerInstance: false
Capacity: Min 1, Max 4, Default 1
Recurrence: Weekly, Days [Saturday, Sunday], Hour 4 UTC — this profile ("Profile 2") appears to be a weekend-specific schedule; not yet confirmed whether a different weekday profile exists with different capacity/rules (only this one event's embedded snapshot seen so far, not the full `Microsoft.Insights/autoscalesettings` resource).
```

**`DividePerInstance: false` is the key difference from the alert.** Autoscale evaluates the **average CPU across all instances on the Plan**, not per-instance — the opposite of `Sales_CPU_Alert`'s per-instance split. **This is very likely the real mechanism behind the "Insights shows 30-50%, live shows 100%" observation from the prior (lost) session:** whatever view was being called "Insights" was plausibly showing this same Plan-wide averaged CPU (diluted by idle instances), while "live" showed the true per-instance spike.

**Practical implication:** the email alert itself was never blocked by averaging — it's genuinely per-instance and has been firing correctly (~40 times in 4 days, confirmed above). But **Autoscale's capacity response is the part actually vulnerable to dilution** — with 3+ instances and only one pegged, the Plan-wide average could plausibly stay under 80% and Autoscale would never add capacity, even while the alert correctly fires and notifies. In this specific observed trigger, Autoscale still scaled up (starting from 1 instance, so average ≈ the single instance's own value in that edge case) — not yet confirmed whether this holds with more instances active, which is the scenario that would actually expose the gap.

**Correction (2026-09-21) — the observation stands, but the proposed action was wrong.** `DividePerInstance: false` is confirmed accurate as the current/real setting. **User confirmed `false` is the intentional, correct choice — verified against Microsoft's own documentation** (`azure-monitor/autoscale/autoscale-understanding-settings`): *"dividePerInstance is useful for metrics aggregated by Sum and Count but not for Average aggregations."* The rule here uses `CpuPercentage` with `TimeAggregation: Average` — a percentage is already normalized; `dividePerInstance` exists for Sum-type metrics (e.g. queue length) where dividing by instance count gives a meaningful per-instance value. Applying it to an Average metric doesn't make sense and isn't Microsoft's recommended usage.

**What this changes**: the dilution mechanism (Plan-wide CPU average masking a single hot instance) is still real and still explains the observed "Insights shows 30-50%, live shows 100%" discrepancy — but it's **expected behavior for an Average-aggregated autoscale metric, not a misconfiguration to fix**. The earlier proposed action ("enable `DividePerInstance: true`") is retracted from `ops.md` — pulling it now. If per-instance-aware capacity response is still wanted, the correct lever (not yet explored) would be a different metric/mechanism, not this setting.

## Open questions

- **Reframes GITIN-2073's likely real fix:** the dilution mechanism itself is confirmed real and not a misconfiguration (`DividePerInstance: false` is Microsoft's own recommended setting for an Average-aggregated metric like `CpuPercentage` — see correction above). If per-instance-aware capacity response is still wanted, no viable lever has been identified yet — not a Diagnostic Settings/App Insights wiring change either. Open, unconfirmed direction.
- Pull the full `Microsoft.Insights/autoscalesettings` resource (not just this one event's embedded snapshot) to see all profiles/rules, confirm whether a non-weekend profile exists, and check whether other Plans have the same `DividePerInstance: false` setting.
- Which specific "insight alerts" were reported as not firing — superseded by the finding above (the email alert fired correctly); the actual gap identified is Autoscale's averaged evaluation, not a firing failure.
- If truly no email was received despite ~40 confirmed non-suppressed action executions: check `gastona@smartfran.com` mailbox/delivery, separate from anything found in this file.
- Jira ticket URL — not yet provided (GITIN-2073 covers the separate Plan-Insights-onboarding scope in `20260919_gitin2073-appserviceplan-insights-onboarding/investigation.md`, now likely needs its own scope correction given this finding).

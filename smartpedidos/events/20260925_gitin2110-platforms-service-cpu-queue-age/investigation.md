# Investigation — 20260925_gitin2110-platforms-service-cpu-queue-age

**Jira ticket:** [GITIN-2110](https://smartit-ar.atlassian.net/browse/GITIN-2110)

**Opened as a separate event/ticket from GITIN-2109** (`cloud/events/20260925_gitin2109-peru-branches-order-delay-crs409/`), per user's stated preference to keep these as distinct tickets rather than merge into a running investigation, even though both surfaced the same day and may share a mechanism.

## Reported symptom

User reports: `platforms-service` (SmartPedidos, AWS ECS Fargate) shows CPU spikes coinciding with high `ApproximateAgeOfOldestMessage` on its SQS queue(s). Not yet confirmed: which specific branch queue(s), the exact time window, or the magnitude of either the CPU spike or the age spike — reported as an observation, not yet backed by a pulled CloudWatch series in this session.

## Architecture context

Matches documented failure pattern **F-005 · Consumer queue depth buildup** and **F-006 · High CPU** in the `ops-aws` skill (`.claude/commands/ops-aws.md`) — `platforms-service` auto-scales its consumer count based on `ApproximateNumberOfMessages` (thresholds 200/400/600), and a CPU-bound or slow consumer would directly manifest as growing `ApproximateAgeOfOldestMessage` on the affected branch queue(s), since messages accumulate faster than `pollFromQueue` drains them.

**Possible connection to GITIN-2109 / GITIN-2084 (not confirmed):** both of those tickets are chasing the same class of symptom — Peru branches showing delayed order delivery to POS — but their evidence so far pointed to different layers: GITIN-2084's strongest (still unconfirmed) lead was `SmartFran-Cloud-Sales-Plan-PRO` CPU saturation on the **SmartCloud** side; GITIN-2109's data today showed the SmartPedidos→Cosmos leg itself was fast (max 20.1s for branches 5470/5424, 87/87 orders sampled). **If** this `platforms-service` CPU/queue-age correlation is real and concurrent with GITIN-2109's reported branches, it would locate the actual bottleneck **upstream** of both prior legs — inside SmartPedidos itself, before the order ever reaches the AWS→Azure bridge, which neither of those investigations checked directly (GITIN-2109's Mongo `orders.timestamp` is receipt/persist time, not consumer-processing time). Not yet checked against the same order set.

## Real data, 2026-09-25 — current task definition revision

**Current: `platform-service-production-task:266`.** `smartpedidos/docs/infrastructure.md` (last confirmed 2026-08-05) documents `:253` as current at that time — **13 undocumented revisions since**, doc is stale on this point. Not yet known which of those 13 changed CPU/memory vs. just image/env, or when `:266` itself was registered relative to any observed CPU spike.

**New, same session: `:267` just registered — a live deploy happened while this investigation was in progress.** Not yet confirmed whether this is a deliberate mitigation (e.g. a CPU/memory bump in response to today's spike, matching the 2026-08-05 remediation precedent) or an unrelated routine deploy. This also means any CPU/queue-age data pulled for "right now" spans a deploy boundary — the `ROLLING` deployment strategy briefly runs old and new tasks concurrently (documented for `concentrador-service`; not yet confirmed whether `platform-service` behaves the same way), which can itself produce a transient CPU/behavior blip independent of the underlying issue. Diff `:266` vs `:267` before attributing any CPU change after this point to either the deploy or the original problem.

## Real data, 2026-09-25 — `PRD_BranchMessages.fifo` (concentrador-service consumer queue), 6h, `ApproximateAgeOfOldestMessage`

`data/branchmessages_age_oldest_6h.json` — this is the **single shared queue** downstream of every branch's `{branchId}PRD_PlatformMessages.fifo`, consumed by `concentrador-service` and delivered to POS terminals (per architecture, `BranchMessages.fifo → SmartFran agent`). Distinct from the per-branch producer queues checked in GITIN-2109/GITIN-2084.

**Two clear escalating incidents found, not noise (baseline elsewhere in the window is 0-3s):**

| Cluster | Window (ART) | Ramp |
|---|---|---|
| 1 | 16:08–16:13 | 21s → 81s → 144s → 204s → 260s → **324s** |
| 2 | 20:55–21:01 | 32s → 83s → 147s → 205s → 265s → 324s → **383s** (worse than cluster 1) |

**Cluster 1 ends at 16:13 ART, 34 minutes before Sol Fernandez's WhatsApp report (16:47 ART, GITIN-2109).** An order stuck ~5 minutes in this specific last-mile queue is directly consistent with "recién entra el pedido cuando el repartidor ya llegó al local" — this is the first concrete mechanism found today that could actually produce that symptom, unlike the fast SmartPedidos→Cosmos leg GITIN-2109 measured. **Not yet confirmed as the actual cause** — no specific order ID has been traced through this queue yet, this is a queue-level metric, not a per-order trace.

**Cluster 2 (20:55-21:01 ART) is more severe and falls close to when `platform-service-production-task:267` was registered this same session.** Not yet confirmed whether `:267` is a reactive mitigation (deployed because of cluster 2, or in an attempt to prevent a third one) or coincidental/unrelated routine deploy — needs `:266`/`:267` diff (queries below) plus their exact `registeredAt` to sequence against 20:55-21:01.

## Real data, 2026-09-25 — Graylog check, both incident windows, no application-level errors found

Stack: older SmartPedidos/SmartLoyalty Graylog (`sf-monitoreo.smartfran.com:9000`, `$SML_GRAYLOG_API_KEY`, `search/universal/absolute` — the `/api/tsdb`-style boolean query with parentheses hit the stack's known `"Missing search type result!"` bug even on a short ~20min range, not just the previously-documented 13-day case; fell back to plain single-term queries, which worked).

- `sqs_consumer`, `batch_processing` — **0 results, both cluster windows** (19:00-19:20 UTC and 23:45 UTC-00:15 UTC). `data/graylog_cluster{1,2}_{sqsconsumer,batchprocessing}.json`.
- **Verified this isn't a silent search failure**, not just assumed: sanity check with a guaranteed-common term (`platforms-service`) over the same cluster-1 window returned **29,318 real results** (`data/graylog_sanity_check.json`) — confirms the index/time-range is genuinely being searched, so the 0-result queries above are a real finding, not a tooling gap (same distinction GITIN-2084 had to make with `used_indices: []`).
- One unrelated error surfaced in the sanity sample: repeated `Platform Auth Error: TOKEN_MISSING GET /api/branches/news` from a `Go-http-client` caller with no auth token — doesn't look connected to the queue-age incident (different endpoint, not an SQS/queue code path), noted but not pursued.

**Working theory updated:** no crashed/erroring consumer during either spike — this looks like a genuine capacity/volume bottleneck (matching ops-aws's F-005 "consumer queue depth buildup," not F-001/F-003's crash patterns), where messages are real but draining slower than they arrive. This is consistent with `:267` being a straight CPU-only bump (no code/env change, see above) — the correct remedy for a capacity problem, not for a crash. **Not yet confirmed**: actual message volume during the two windows (PERF log count alone, 29,318/20min in the sanity window, hasn't been isolated to just order-processing volume vs. all platforms-service traffic) — would need a volume-specific query to confirm "more messages than usual" vs. "same volume, slower processing."

## Open questions

1. Which branch(es)' queues showed the high `ApproximateAgeOfOldestMessage` — same ones as GITIN-2109 (5470/5424) or different?
2. What time window — does it overlap with GITIN-2109's ~19:47 UTC WhatsApp report window, or GITIN-2084's known Sales-Plan-PRO CPU windows (2026-09-18 21:50-22:00 UTC, 2026-09-20 02:18-02:28 UTC)?
3. ~~Is this `platforms-service`'s own ECS CPU or confused with `concentrador-service`'s?~~ **RESOLVED, 2026-09-25, from source:** `platforms-service` is the confirmed consumer of `PRD_BranchMessages.fifo` — `api/src/platforms/provider/aws.js:56-115`, `pollFromQueue()` creates an `sqs-consumer` `Consumer` on `config.AWS.SQS.ORDER_CONSUMER.NAME` (= `PRD_BranchMessages.fifo` in `production.js`), calling `setNews()` per batch; its own error log is `[ORDER/ERROR] setNews_processing failed consumer=parent`, matching `ops-aws.md`'s F-002 signal already attributed to platforms-service. `concentrador-service`'s only reference to this queue (`controllers/branch.js:3016`) just echoes the queue name in an API response field — it never consumes from it. **This also corrects this file's earlier assumption about what `PRD_BranchMessages.fifo` is**: it is not the final POS-terminal delivery hop. Per `cloud/docs/infrastructure.md` → "SmartPedidos Bridge," SmartCloud's `MessageProcessor` polls the per-branch `PlatformMessages.fifo` directly and "acks back to SmartPedidos via a second SQS queue" — that second queue is `PRD_BranchMessages.fifo`, and `platforms-service`'s `pollFromQueue`/`setNews` is what consumes those acks to update order state in MongoDB. So `:267`'s CPU bump on `platform-service-production-task` was targeting the correct service.
4. Ongoing right now, or a specific past window the user already observed (e.g. via CloudWatch console)?

## Not yet done — diagnostic queries to run

**Note on region:** `smartpedidos/docs/infrastructure.md` documents SQS queues as `us-east-2`, but GITIN-2084's confirmed-working script (`cloud/events/20260919_grido-order-delay-peru-5396-5481/scripts.sh`, C1/C2) successfully queried them in **`us-east-1`**. Following the confirmed-working region below; this discrepancy is worth resolving separately, not blocking here.

1. **`platforms-service` ECS CPU, 48h, 5-min grain:**
```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS --metric-name CPUUtilization \
  --dimensions Name=ClusterName,Value=smartfran-pedidos-production Name=ServiceName,Value=platform-service-production-service \
  --start-time "$(date -u -d '48 hours ago' +%Y-%m-%dT%H:%M:%S)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
  --period 300 --statistics Average Maximum \
  --region us-east-1 --profile <profile> \
  --output json > /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_gitin2110-platforms-service-cpu-queue-age/data/platforms_cpu_48h.json
```

2. **`ApproximateAgeOfOldestMessage`, branches 5470 and 5424 (same as GITIN-2109), 48h, 5-min grain:**
```bash
for BRANCH in 5470 5424; do
  aws cloudwatch get-metric-statistics \
    --namespace AWS/SQS --metric-name ApproximateAgeOfOldestMessage \
    --dimensions Name=QueueName,Value=${BRANCH}PRD_PlatformMessages.fifo \
    --start-time "$(date -u -d '48 hours ago' +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 300 --statistics Maximum \
    --region us-east-1 --profile <profile> \
    --output json > /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_gitin2110-platforms-service-cpu-queue-age/data/sqs_age_oldest_${BRANCH}.json
done
```

3. Once both are in hand: check whether CPU spikes and queue-age spikes are time-coincident (same nearest-neighbor-gap method GITIN-2084 used), and whether either lines up with GITIN-2109's ~19:47 UTC window today.
4. If confirmed coincident: pull `ApproximateNumberOfMessages` (not just age) for the same queues/window to distinguish "genuinely more messages arriving" from "same volume, slower draining" — the latter points squarely at a consumer-side CPU/perf problem, matching F-005's "PERF — is the consumer slow?" check in `ops-aws.md`.

5. **`:266` and `:267` registration times and cpu/memory, to line up against the CPU/queue-age data once pulled, and to see what `:267` actually changed:**
```bash
for REV in 266 267; do
  aws ecs describe-task-definition \
    --task-definition platform-service-production-task:${REV} \
    --region us-east-1 --profile <profile> \
    --query 'taskDefinition.{registeredAt:registeredAt,cpu:cpu,memory:memory,containers:containerDefinitions[].{image:image,env:environment}}' \
    --output json > /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_gitin2110-platforms-service-cpu-queue-age/data/taskdef_${REV}.json
done
```
If `:267`'s `registeredAt` falls inside or just after a CPU spike window found in step 1, this is likely a reactive mitigation, not a coincidence — diff its `cpu`/`memory` against `:266`'s to confirm (matching the 2026-08-05 precedent: a straight capacity bump, no code change). If `cpu`/`memory` are unchanged between the two, it's a code/image/env change instead and the CPU spike remains unexplained by this deploy.

## Real data, 2026-09-28 — `:268` registered, NOT a simple revert of `:267`

Three days after `:267` went live (fully rolled out, confirmed 2026-09-25). `data/taskdef_268.json`, `data/service_current_taskdef_268.json`.

| Revision | registeredAt | cpu | memory |
|---|---|---|---|
| `:266` (pre-mitigation baseline) | 2026-09-24T09:55 ART | 512 | 2048 |
| `:267` (reactive bump, 2026-09-25) | 2026-09-25T21:33 ART | 1024 | 2048 |
| `:268` (2026-09-28) | 2026-09-28T08:18 ART | **512** | **1024** |

**Not a plain rollback to `:266`.** CPU is back down to `:266`'s level, but memory is cut to **1024 — half of both `:266` and `:267`'s 2048**, i.e. below the pre-mitigation baseline that's been in place since the 2026-08-05 scale-up (`smartpedidos/docs/infrastructure.md`). Same image (`platform-service:10.9.12`) and env vars as both prior revisions — capacity-only change again.

**Deployment in progress at check time:** `:268` primary, 5/5 desired, `rolloutState: IN_PROGRESS`; `:267` draining, 4 tasks still running, desired 0.

**Reason not yet confirmed with user** — asked whether this is (a) `:267`'s CPU bump turning out to be unnecessary/oversized after 3 days of monitoring (cost cleanup), or (b) something else driving a memory reduction specifically.

## Real data, 2026-09-28 — full weekend queue-age/CPU/volume cross-check: `:267` did NOT stop the spikes

Window: `:267`'s full in-service period, 2026-09-26T00:30Z through 2026-09-28T11:20Z (when `:268` began rolling out). `data/branchmessages_age_oldest_weekend.json` (queue age), `data/platforms_cpu_weekend.json` (platforms-service CPU), `data/mongo_news_volume_weekend.txt` (`news` volume per hour — **note: query grouped by `thirdParty` but the output has no `thirdParty` key at all, meaning that field doesn't exist on `news` docs; this is a volume-only view, not per-platform** — a real per-platform breakdown needs the correct field name, not yet found).

**The queue-age spikes continued at similar or worse severity throughout the entire weekend, despite `:267` doubling CPU to 1024:**

| Spike (ART) | Peak age | platforms-service CPU (Max) | `news`/hr, same ART hour (converted from UTC buckets) |
|---|---|---|---|
| Fri 23:45 | 320s | 41.8% | ~7443 |
| Sat 14:40 | 304s | 54.9% | 4264 |
| Sat 18:40 | 303s | 37.5% | 2494 |
| Sat 21:40 | 296s | **60.3%** (weekend's highest CPU reading) | 5757 |
| Sun 15:00–16:30 | ≤52s | 20-23% sustained | 8256 (weekend's single busiest hour) |
| Sun 21:05 | **374s — worse than anything seen before `:267`** | 49.2% | 4371 |

**This weakens the CPU-capacity theory significantly.** If CPU were the actual bottleneck, doubling it should have either eliminated the spikes or required near-100% utilization to reproduce them. Neither happened — the worst spike of the whole investigation (374s) occurred *after* the mitigation, with CPU barely half-saturated even on the doubled allocation. Combined with the earlier Graylog finding (no crashed/erroring consumer during any incident), this points toward a **periodic external dependency stall** as the more likely mechanism — plausibly the SmartCloud ack round-trip on `PRD_BranchMessages.fifo` itself (Orders API → Cosmos → ack, per the architecture resolved above), not platforms-service's own resource allocation.

**Volume correlation is loose, not tight.** All six incidents fall inside the evening dinner-rush window (~13:00–22:00 ART both days, where volume runs 2,000-8,000 `news`/hour vs. near-zero overnight) — elevated load is a necessary background condition. But the single busiest hour of the whole weekend (Sun 15:00-16:00 ART, 8256 `news`) produced only mild spikes (≤52s), while the worst spike (374s) happened in a comparatively average-volume hour (4371) — ruling out "just raw throughput" as a sufficient explanation on its own.

**This materially changes how `:268` (CPU back to 512, memory cut to 1024) should be read**: not necessarily a premature rollback of a working fix, since `:267` shows no clear evidence of having worked at all over 3 full days of monitoring. Still not confirmed with the user why `:268` specifically cuts memory below the original 2048 baseline rather than just reverting cpu.

**Not yet done:**
- Find the correct field for per-platform breakdown on `news` (or confirm platform must be joined from `orders` via `order._id`/`originalId`) to get the per-platform volume view originally requested.
- Check whether `:268`'s lower memory (1024) causes any new symptom once its rollout completes and a comparable window of data exists.

## Real data, 2026-09-28 — Sunday 21:05 ART spike traced: a mass catch-up burst, not one stuck order

Queried `news` docs with `updatedAt` in 2026-09-28T00:02:00Z–00:14:00Z (21:02–21:14 ART, bracketing the CloudWatch spike). `data/mongo_trace_sunday_2105.txt` (843 docs), `mongo_trace_sunday_2105.js` (query, matches on `updatedAt` since that's bumped exactly when `setNews` processes a dequeued `PRD_BranchMessages.fifo` message, per `set-news.js`).

**Found a mass catch-up burst, not a single delayed order.** 843 `news` docs across **405 distinct branches** fall in this window; **292 of them (35%) landed in an 11-second burst, 00:06:23–00:06:34 UTC (21:06:23–21:06:34 ART)** — about a minute after CloudWatch's 21:05 ART sample recorded the queue age at 374s. Before and after that burst, updates trickle in at a normal 1-7/second background rate (full per-second counts in the script output). This is the signature of `pollFromQueue` having accumulated a backlog and draining it all at once, not a steady per-message delay.

**Type breakdown of the 843 (`data/newstypes_lookup.txt` for the `typeId`→`cod` mapping, pulled fresh from `db.newsTypes` since it's config-driven, not hardcoded):**

| typeId | cod | name | count |
|---|---|---|---|
| 14 | `deliv_ord` | deliveredOrder | **794 (94%)** |
| 2 | `rej_ord` | rejected | 18 |
| 10 | `receive_ord` | receivedOrder | 11 |
| 15 | `ready_ord` | readyOrder | 9 |
| 3 | `disp_ord` | dispatchedOrder | 8 |
| 5 | `confirm_ord` | acceptedOrder | 3 |

**Nuance for the GITIN-2109 connection:** this specific burst is overwhelmingly delivery-confirmation acks (`deliv_ord`), not the `ready_ord` step that produced GITIN-2109's `CRS: 409` complaint on 2026-09-25. Only 9 of 843 were `ready_ord`. This doesn't rule out the mechanism connecting the two tickets — `ready_ord` clearly flows through the same queue and does appear here — but this particular Sunday incident's dominant symptom would have been late delivery-confirmation, not blocked "mark ready" actions. The two tickets share a root mechanism candidate (this queue's periodic backlog) without this trace being direct proof of the specific `CRS: 409` scenario.

**Correction to earlier framing:** `gapSeconds` (updatedAt − createdAt) is **not** a reliable "time stuck in this queue" measure — it spans a doc's whole lifecycle from order creation to last update. Values here range from under 1s to over 24h (median 854s ≈ 14 min, consistent with GITIN-2068's earlier delivered-order baseline), which is normal business variance, not evidence of individual orders stuck for that long. The burst-clustering of `updatedAt` itself is the solid evidence; per-document gap size is not.

## Real data, 2026-09-28 — code-level check (develop branch): no success-path logging exists for this consumer at all

Before repeating the Graylog check for the Sunday spike, checked `smartpedidos/repo/dev-scr-smartPedidos-platformsService` (confirmed on `develop`, the production branch) directly. In `api/src/platforms/provider/aws.js`, every `Log.save` call inside `pollFromQueue()` and both `handleMessageBatch` blocks is `ERROR` or `WARN` — **there is no INFO/PERF log line anywhere in this consumer path for the success case** (no "batch received," no "batch processed," no batch size, no processing duration). `sizeMessageSQS` — the actual live queue depth, read via `GetQueueAttributesCommand` on every batch — is computed and used only to decide whether to spin up `secondConsumer`/`thirdConsumer`/`fourConsumer`, and is **never logged**, even at INFO level.

**This fully explains the earlier Graylog "0 results" for `sqs_consumer`/`batch_processing`** (both Sept 25 incident windows, see above): it was never evidence of a healthy consumer, only evidence that nothing gets logged unless something actually errors. A silent backlog-then-burst-drain — exactly the pattern found in both the Sept 25 incidents and the Sunday 21:05 burst — produces **zero log lines of any kind**. Repeating the same Graylog check for Sunday would almost certainly repeat this same non-finding, so it wasn't run — the code-level gap is the more useful and conclusive result.

**Reportable finding in its own right:** this is a real observability gap in the queue-consumer path — the one signal that would have let this be diagnosed from logs directly (live queue depth per batch) is computed but discarded, never surfaced. Worth a `sp-log-improvements`-style finding (SUB-00X: log `sizeMessageSQS` and batch size/duration at INFO/PERF on every `handleMessageBatch` invocation), separate from this event's own resolution.

## Real data, 2026-09-28 — `NumberOfMessagesReceived`, `PRD_BranchMessages.fifo`, last 30 days

User hypothesis: this weekend saw meaningfully more messages than prior weekends. Pulled `NumberOfMessagesReceived` (Sum, hourly, 30 days, 732 datapoints) — `data/branchmessages_received_30d.json`. Bucketed into ART calendar days locally (script inline in this session, not saved as a separate file — trivial sum/groupby), weekends defined as Fri+Sat+Sun anchored on the Friday date.

| Weekend of | Fri+Sat+Sun total |
|---|---|
| 2026-08-28 | 655,409 |
| 2026-09-04 | 605,927 |
| 2026-09-11 | 573,443 |
| 2026-09-18 | 814,228 |
| 2026-09-25 (this ticket's weekend) | 823,794 |

**Confirms elevated volume, but the step-up happened at 09-18, not specifically this weekend.** 09-25 is only ~1% above 09-18 (823,794 vs 814,228), while both are 26-40% above the three weekends prior. **This lines up closely with when GITIN-2068 and GITIN-2084 (the earlier Peru order-delay tickets) were first reported, 2026-09-17/09-19** — the volume growth and the first delay complaints started around the same time, not confirmed as causal but a real temporal coincidence worth noting. Sunday is consistently the highest-volume day of every weekend in this data, consistent with this ticket's own worst spike landing on a Sunday (21:05 ART, 2026-09-27).

**Not yet done:** pull the same metric for weekdays to see if the volume growth is weekend-specific or platform-wide across the whole month (only weekends were checked, per the user's hypothesis framing); check whether `platform-service`'s ECS desired task count changed around 09-17/09-18 (a capacity change unrelated to `:266`/`:267`/`:268` could also explain a step-change in effective headroom).

**Refined to hourly, 11:00-03:00(+1) ART window (excludes the near-zero 03:00-11:00 overnight lull) — same weekend totals, but adds an important nuance.** Weekend totals barely move (660,722 / 605,506 / 570,139 / 815,176 / 822,900 for the same five weekends) confirming the overnight hours weren't skewing anything. But comparing this Sunday (09-27) hour-by-hour against the prior Sunday (09-20): **they track almost identically, including at 21:00 ART — 24,349 vs. 24,077, essentially the same** — and both are well below their own day's actual peak hours (14:00-16:00 ART, 37k-44k). **The 21:05 spike (this ticket's worst) did not coincide with unusually high volume, either vs. the prior week's same hour or vs. its own day's peak hours.** The elevated weekend *total* is real (see above), but it doesn't explain why the worst stall landed at 21:00 rather than during the actual 14:00-16:00 peak — further weakening "raw volume" as a sufficient standalone explanation, consistent with H6's outbound-dependency hypothesis being more specific/plausible than a pure throughput story.

**Not yet done:** identify *why* the burst happens mechanically (consumer stall-then-catchup vs. a periodic batch flush by design on the SmartCloud/Orders-API ack side) — without success-path logs, this now needs either a code trace of the SmartCloud side's ack-sending logic, or adding the missing logging and waiting for a recurrence.

## Cost of the `:267` weekend CPU escalation — estimate, not yet confirmed against real billing (2026-09-28)

User asked for the cost of the weekend CPU escalation (`:267`), per hour and total. This is a **computed estimate from known task-definition specs and public Fargate list pricing (us-east-1: $0.04048/vCPU-hr, $0.004445/GB-hr) — not pulled from AWS Cost Explorer or the actual bill.** Two things are not yet confirmed that this estimate depends on:
- **Actual running task count during the window.** `smartpedidos/docs/infrastructure.md` documents `platform-service` `desiredCount: 10` as the steady-state floor since 2026-08-05 (`MinCapacity` 10, `MaxCapacity` 25, Application Auto Scaling target exists) — used as the assumption below. But this event's own later check (2026-09-28, `:268` rollout) observed `5/5 desired` at that specific moment, which is below the documented floor and unexplained — see the `:268` section above. If autoscaling pushed the count above 10 during the CPU/queue-age spikes (plausible, that's what the target exists for), this estimate understates the real cost; if it was actually running at something like 5 for part of the window, it overstates it.
- **List price vs. actual billing rate** — no Reserved/Savings Plan or negotiated discount factored in, since that data isn't available locally.

**Duration `:267` was in service:** `registeredAt` 2026-09-25T21:33 ART → `:268` began rolling out 2026-09-28T08:18 ART (both from the table above) = **58.75 hours**.

**Task-definition delta, `:266` → `:267`:** CPU 512→1024 (0.5→1 vCPU), memory unchanged at 2048 (2GB).

| | Per task/hr | Fleet/hr (×10, documented `desiredCount`) | Total over 58.75h |
|---|---|---|---|
| `:266` baseline compute cost | $0.02913 | $0.2913 | — |
| `:267` escalated compute cost | $0.04937 | $0.4937 | **≈ $29.00** |
| Incremental cost of the escalation (vs. `:266` baseline) | $0.02024 | $0.2024 | **≈ $11.89** |

**Reportable range, given the task-count uncertainty:** at the documented floor (10 tasks) the escalation's incremental cost is ≈$11.89 over the weekend; if autoscaling ran above 10 during the spikes (plausible, unconfirmed), the real incremental figure is higher, scaling linearly with actual task-hours.

**To replace this estimate with a confirmed figure**, two commands would close the gap — not yet run (need `<profile>`):

```bash
aws ecs describe-services \
  --cluster smartfran-pedidos-production \
  --services platform-service-production-service \
  --region us-east-1 --profile <profile> \
  --query 'services[0].events[?createdAt>=`2026-09-25T21:30:00Z` && createdAt<=`2026-09-28T08:30:00Z`]' \
  --output json > /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_gitin2110-platforms-service-cpu-queue-age/data/service_events_weekend_escalation.json

aws ce get-cost-and-usage \
  --time-period Start=2026-09-25,End=2026-09-29 \
  --granularity DAILY \
  --metrics UnblendedCost \
  --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Elastic Container Service"]}}' \
  --region us-east-1 --profile <profile> \
  --output json > /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_gitin2110-platforms-service-cpu-queue-age/data/cost_explorer_weekend.json
```

Note: Cost Explorer's `SERVICE` filter here returns ECS spend account-wide (Fargate compute for both `platform-service` and `concentrador-service`, plus any other ECS workloads on the account), not isolated to this one service/task-def change — would need cross-referencing against the `describe-services` event history above to attribute the delta specifically to `:267`, not just read off directly.

## User ran both verification commands, 2026-09-28 — real cost data + a major new finding on root cause

Both files landed at the paths above (`data/cost_explorer_weekend.json`, `data/service_events_weekend_escalation.json`).

### Cost Explorer result — real spend, and a cross-check that surfaces a task-count discrepancy

| UTC day | Total ECS UnblendedCost | Notes |
|---|---|---|
| 2026-09-25 | $4.20 | Entirely pre-escalation — `:267` registered 2026-09-25T21:33 ART = **2026-09-26T00:33 UTC**, i.e. just after this UTC day ends. Usable as a real `:266`-baseline day. |
| 2026-09-26 | $6.95 | Full day on `:267`. |
| 2026-09-27 | $6.68 | Full day on `:267`. |
| 2026-09-28 | $1.28 | Partial — `:268` began rollout 08:18 ART = 11:18 UTC, so only ~11.3h of this day is `:267`, rest is `:268` (lower spec). |

This total is account-wide ECS spend (`platform-service` + `concentrador-service`, whose `desiredCount` stayed fixed at 1 the whole time per `infrastructure.md` — so it should cancel out as a constant when diffing days). Observed daily delta, escalation days vs. baseline day: avg($6.95, $6.68) − $4.20 = **$2.61/day**.

**Cross-check against the per-task-hour pricing model:** at $0.02024/task-hr incremental cost (the `:266`→`:267` delta), $2.61/day implies an actual running count of **≈5.4 tasks**, not the documented `desiredCount: 10` floor (`infrastructure.md`, confirmed 2026-08-05, MinCapacity 10/MaxCapacity 25). This **directly conflicts** with what `describe-services` shows for the visible tail of the window (below): fleet consistently at 10. Not reconciled — flagging both rather than picking one, per this project's rule on not trusting a single line of evidence. Possible explanations, none confirmed: Cost Explorer's `UnblendedCost` reflects something other than simple on-demand list price (Savings Plan, Compute Savings, credits) that would change the $/task-hr conversion, in which case the discrepancy is a pricing-model error on my side, not a real task-count of 5. Would need `aws ce get-cost-and-usage` with `--metrics UsageQuantity` (vCPU-hours, GB-hours as actual usage units, not $) to settle this independent of pricing assumptions — not yet pulled.

**Revised cost figure, given this unresolved discrepancy:** the incremental cost of the `:267` escalation over the full 58.75h window is somewhere in **$5.95 (if actual count ≈5, per the Cost Explorer back-calculation) to $11.89 (if actual count =10, per `describe-services`' visible tail and the documented floor)** — real answer not yet pinned down, but bounded.

### `describe-services` result — only the last 100 events, i.e. only ~16.3 of the 58.75 hours are visible

**Hard API limitation, not a query mistake:** `describe-services` returns at most the 100 most recent events for a service regardless of any `--query` time filter applied client-side — the events array itself is capped server-side. Earliest event returned: **2026-09-27T16:03 ART** — the requested window started 2026-09-25T21:33 ART, so **the first ~42.5 hours of the escalation (both Friday-night and Saturday's three queue-age spikes) have zero event visibility from this pull.** Same class of silent-truncation gap as the known `az activity-log` 50-result cap — flagging immediately rather than treating the visible slice as the whole picture.

**For the visible ~16.3h tail, fleet size is confirmed steady at 10** — two full-fleet replacement cycles observed (`has started 10 tasks` → ten sequential `has stopped 1 running tasks`, ~3-4 min apart, over ~40 min each), both returning to 10 running tasks afterward. No task def revision change in this window (`:267` throughout, per the earlier table) — these are same-revision redeployments or forced restarts, not autoscaling or a `:267`→something-else task-def change.

### Major finding: the second full-fleet replacement cycle lands almost exactly on this ticket's worst queue-age spike

The two full-fleet replacement events in the visible tail:

| Event | `started 10 tasks` at (ART) | Coincides with |
|---|---|---|
| 1 | 2026-09-27 16:03:05 | Tail end of the "Sun 15:00–16:30, ≤52s" mild activity window already in this file's spike table |
| 2 | **2026-09-27 21:05:59** | **This ticket's worst spike — CloudWatch's 21:05 ART sample at 374s, and the 292-doc mass catch-up burst timed 21:06:23–21:06:34 ART — the burst starts ~24 seconds after this deployment event, ~40 seconds after `steady state` is reached.** |

**This is a strong, previously-missing causal candidate for the Sunday 21:05 spike specifically — not yet in the working theory.** A full-fleet rolling replacement (`ROLLING` strategy, one task drained at a time over ~40 min while new tasks spin up) means active `pollFromQueue` consumer count is briefly reduced during the transition — draining capacity drops right as the new fleet is still warming up, which would produce exactly the pattern already found independently: queue age spikes, then a mass burst-drain once the fleet stabilizes. Both of the two visible deployment events land on listed spike windows (2 for 2) — not proof, but a real pattern, not coincidence-shaped.

**This does not explain the other four spikes** (Fri 23:45, Sat 14:40, Sat 18:40, Sat 21:40) — those all fall inside the ~42.5h with zero event visibility, so it's unknown whether they also coincide with a same-revision redeployment. **This reframes H6 (periodic external dependency stall) as unconfirmed rather than the leading theory** — a recurring same-revision redeploy/restart pattern is now an equally or more plausible mechanism for at least the one spike that's checkable, and needs the same check for the other four before either theory is preferred.

**Not yet confirmed:** what triggers these same-revision redeployments (CI/CD routine deploy, a manual `--force-new-deployment`, a health-check-driven replacement, an ECS deployment circuit breaker) — `describe-services` events don't carry the trigger/actor, that needs CloudTrail (`ecs:UpdateService` calls) for the same timestamps, not yet pulled.

### Next steps

1. Pull `describe-services` again with a narrower explicit time-boxed approach that doesn't hit the 100-event cap — e.g. per-6-hour-window pulls stitched together, or `aws ecs list-services-events`-equivalent via CloudWatch Events/EventBridge history if the account has it wired up — to get full visibility across all 58.75 hours, not just the tail.
2. Check whether the four Saturday/Friday spikes also coincide with a full-fleet redeployment, once full event visibility exists.
3. Pull CloudTrail for `ecs:UpdateService` calls against `platform-service-production-service` in this window to identify what triggered the two visible redeployments.
4. Pull `aws ce get-cost-and-usage` with `--metrics UsageQuantity` to resolve the cost-implied-vs-observed task-count discrepancy independent of pricing assumptions.

## 10-minute cost reconstruction, visible tail only (2026-09-28)

User asked for cost at 10-minute granularity. **Cost Explorer doesn't offer that** — its finest `--granularity` is `HOURLY`. Built a synthetic 10-minute timeline instead, from the exact task start/stop timestamps already in `data/service_events_weekend_escalation.json` (no new AWS call) × the known Fargate per-task-hour rate — precise, but **only covers the visible ~16.3h tail** (2026-09-27T16:00–2026-09-28T08:30 ART), same 100-event-cap limitation as above. Full table: `data/cost_10min_reconstructed_visible_tail.csv` (99 buckets).

**New detail this surfaces: task count briefly doubles to 20 during each redeploy**, not just cycles through 10 — `ROLLING` strategy with `maximumPercent: 200` means the 10 new tasks start before any old one stops, so for ~10-15 minutes actual running count is ~17-20, not 10, before decaying back down as the old fleet drains over ~40 min. This is a real, if small, extra cost during those windows (bucket cost peaks at $0.164/10min vs. $0.082/10min steady-state — roughly double, matching the doubled task count) — and is itself further evidence for the redeploy-as-mechanism theory above, since it's exactly the kind of transient capacity swing that would produce a queue-age spike.

**Totals, visible tail only:** $8.53 (platform-service Fargate compute only, this slice; not the account-wide Cost Explorer figure above, and not the full 58.75h weekend).

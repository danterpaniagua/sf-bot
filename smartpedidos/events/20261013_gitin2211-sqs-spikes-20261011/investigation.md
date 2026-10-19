# Investigation — 20261013_sqs-spikes-20261011

**Status:** converged for the ticket's stated scope. Reviewed at the time: user statement only. Cause of the stall: not found; no slow delivery platform seen. Scaling: executed, queue recovered. Cause of the stall remains open (GITIN-2162).

Jira: GITIN-2211 "[SP] Spikes en cola" (https://smartit-ar.atlassian.net/browse/GITIN-2211). Folder created before the id existed, keeps its name. All times are local (UTC-3) unless marked; the event is 2026-10-11 ~22:03.

## Scope (pasted by the user, 2026-10-13)

For the scaling analysis of the MAIN SQS oldest-age alert: show that it was reviewed at the time; whether the logs allowed finding the cause; whether it scaled properly; determine whether a slow platform causes the delay. Business level only. Out of scope: analysis of the scaling code (Lambda) and of the platform / concentrador code. The Lambda code was downloaded and read once (C6) for context only; nothing from it goes into the ticket beyond observed outcomes. "Solo negocio" was read as: ticket written at business level, no code detail (not confirmed). Later the user clarified the question is why the queue holds messages with ~200 s of age or more, not why the Lambda runs. Threshold used in this folder: age above 200 s (all 12 stalls exceeded it).

## Calendar context (user, 2026-10-13)

2026-10-09 (Fri) to 2026-10-12 (Mon) was a holiday weekend; 2026-10-13 (Tue) is the first working day. So 10-09, 10-10, 10-11 and 10-12 in the 10-day window are not ordinary days, and no stall has been checked yet on a normal working-day traffic pattern. The stalls on 10-03/10-04 (ordinary weekend) happened as well. Query to catch each occurrence: `scripts-detect.sh` (read-only, any range; default today 00:00 to now).

## Detection runs (`scripts-detect.sh`, 2026-10-13 10:22-10:23)

- Holiday weekend 2026-10-09 00:00 to 10-13 00:00 (`data/detect-holiday1-summary.txt`): 4 stalls, all already in the list: 10-09 22:33 (3 min, peak age 287 s), 10-10 19:42 (3 min, 260 s), 10-11 21:58 (5 min, 306 s), 10-12 16:56 (5 min, 319 s). Minutes with age >= 200 s: 10 (10-09 22:36-22:38; 10-10 19:44-19:46; 10-11 22:02-22:03; 10-12 17:00-17:01). No other zero-deletion run in the 4 days.
- Today 2026-10-13 00:00 to 10:22 (`data/detect-today1-summary.txt`): one new stall, 00:30 local, 5 minutes, up to 342 visible messages and 329 s of age (minutes at 00:33-00:35 with 209, 269 and 329 s). It is the 13th in 11 days. No stall from 00:35 until 10:22, i.e. none yet in the working-day morning. The alarm `sendMailOldestMessage` state-change time read earlier (2026-10-13 00:42:30, C5) is consistent with this stall; the Lambda invocation and task counts for it were not read. The ticket `ops.md` (written before this run) lists 12 stalls.

## Logs for the 2026-10-13 00:30 stall (C10 run 2: `data/c10-run2-summary.txt`; analyses `data/c10-analysis-20261013-0030.txt`, `data/c10-analysis-comm-errors.txt`; local time)

- Consumer-side platform calls: last call 00:29:33.9, none from 00:30 to 00:35:05 (0 between 00:30:30 and 00:34:30), resumed 00:35:06 with 143 calls in the 00:35 minute (normal here ~15-30 per minute at this hour). `platforms-service` kept logging 756-762 messages per minute during the stall (MercadoPago token fetch ~733 per minute) and 4 `TOKEN_MISSING` lines per minute: the process was alive.
- Unlike the other stalls, platform timeouts appear right before the stop: `Platform Communication Error: I+D viewOrder` at 00:27:46, `I+D receiveOrder` at 00:29:05 and 00:29:22, each `timeout of 10000ms exceeded`. Calls to the `ThirdParty` group (label of the logged latency lines; whether `I+D` is part of it was not checked) also took 8.8 s (receiveOrder, 00:27:30) and 3.3 s (dispatchOrder) before the stall, and 2.7-9.7 s (ThirdParty receive/dispatch/delivery/view) in the first two minutes after it (23 calls >= 2.5 s in 00:27-00:38, 17 of them ThirdParty, 5 Rappi `getOrders` at 2.6-4.7 s). In the first minute after the stall the consumer-call p95 was 2.5 s (max 8.9 s) against ~0.1-0.3 s on other days.
- Also before the stop (00:27-00:29): `setNews_processing failed` / `manageNewType failed` with "The news does not meet the transition requirements" (4 at 00:27:11, 2 at 00:27:48, 1 at 00:27:50, 4 at 00:28:12), `setNews failed` with "resolve is not defined" (1 at 00:27:50, 3 at 00:28:30) and MercadoPago "Order ... already exists" lines (3-4 per minute). These error types also appear in other windows; their frequency before the other stalls was not compared.
- Across all 13 windows pulled (-3 to +8 minutes around each start, `data/c10-analysis-comm-errors.txt`): `timeout of 10000ms exceeded` appears only in this stall (3 lines before it) and once at 17:01:32 on 10-12, five minutes after that stall started (after consumption resumed); every other `Platform Communication Error` is an HTTP 400 from Rappi or PediGrido, not slowness. So a slow platform (`I+D`) precedes the 13th stall and is not a feature of the other 12.
- Reading, not proven: a slow third-party platform is a candidate trigger for this stall; it does not explain the other 12 (no timeouts before them), and the 10-second request timeout means a single slow call would not by itself explain five minutes without any logged call.

## Environment facts

- Production SQS is in `us-east-1` (user: `us-east-2` is test and staging). Queues: `<id>PRD_PlatformMessages.fifo` per branch, `PRD_BranchMessages.fifo`, `MainDeadLetter.fifo`, `DeadLetter.fifo`. Account 382381053403. Cluster `smartfran-pedidos-production`, service `platform-service-production-service`.
- User-stated, not checked in Grafana: the Grafana alert is oldest-message age above 250 s (an order can be cancelled when no news arrives within 10 minutes); the spike was seen in Grafana at 22:03 (panel and queue not named; `PRD_BranchMessages.fifo` confirmed by the user as the trigger queue, metric `ApproximateAgeOfOldestMessage`).
- Statistic: Maximum used for age and visible messages in all pulls; Sum for sent/received/deleted counts.

## Confirmed facts

**Queue behavior on 2026-10-11 (C3: 1-minute CloudWatch, `PRD_BranchMessages.fifo`, `data/c3-run1-summary.txt`)**
- Received and deleted were 0 at 21:58, 21:59, 22:00 and 22:01 (22:02: 20 received, 0 deleted) while sent stayed 442-567 per minute. Visible: 35 (21:58), 617, 1,099, 1,590, 1,989 (22:02). Age: 4, 65, 125, 190, 247 s (22:02) and 306 s at 22:03.
- 22:03: 2,879 received / 2,880 deleted in one minute; age 0 at 22:04 (39 s at 22:07, 0-25 s afterwards). Before the stall: 382-558 sent per minute, received and deleted within a few of sent, age 0-4 s.
- Other queues: per-branch queues peaked at 5-15 sent per 5 min (C1, `data/c1-evento-top.txt`; C1 was cut at 500 series, so incomplete). `PRD_BranchMessages.fifo` sent 3,345 per 5 min at 22:45, inside its usual range (daily maxima 1,709-3,663; C2 `data/c2-run1-recomputed.txt`; evenings Fri-Sun 2,800-3,534, weekdays 1,361-1,882). `MainDeadLetter.fifo` holds a stock of 30-77 visible every day and received 0 messages in 10 days. Old-message ages of 4-57 hours on a few per-branch queues exist in both the event and baseline windows (standing backlog).

**Recurrence (C3-B, C4: `data/c3-run1-summary.txt`, `data/c4-run1-runs.txt`)**
- 12 stalls in 10 days (runs of >= 2 consecutive minutes with sent > 0 and deleted = 0), 2-5 minutes each: 10-03 13:09, 21:43, 22:44; 10-04 11:19, 19:09, 20:15; 10-05 08:55; 10-06 21:01; 10-09 22:33; 10-10 19:42; 10-11 21:58; 10-12 16:56. Peak ages (5-minute Maximum): 239, 322, 305, 324, 287, 238, 263, 290, 287, 260, 306, 319 s. All 12 exceed 200 s; 10 reach >= 250 s; 5 reach >= 300 s (1-minute). Same signature as GITIN-2162. Only 3 isolated single zero-deletion minutes outside these runs.
- Detection: "sent > 0 and deleted = 0 for 2 consecutive minutes" matched all 12 and no other run; it is available 2-4 minutes before age reaches 250 s in the 10 stalls that reached it (10-11: after 21:59 against 22:03).

**Is a delivery platform slow? Not in these logs (C7, C10: Graylog `platforms-service`, per minute; `data/c7-analysis-*.txt`, `data/c10-analysis-*.txt`; raw `data/detail-*` ignored by git)**
- 10-11: consumer-side platform calls (`[PERF/INFO] http_response`, readyOrder/dispatchOrder/deliveryOrder/viewOrder) were 0 from 21:57:58 to 22:03:00 (4 calls in the last second) and resumed with 665 calls in the first minute (normal ~100-115 per minute). Latencies normal before and after (PedidosYa readyOrder p95 102 ms before / 90 ms after; PediGrido deliveryOrder p50 ~1.27 s both, ~1.25 s in a control window; UberEats ~1.1-1.2 s). Slower only in the catch-up minute (PedidosYa readyOrder p95 332 ms, PediGrido readyOrder p95 584 ms, at 6-8x the normal call rate).
- No timeout or communication-error line inside the stall; ERROR/WARN lines in the stall are the same as before and after (`order_processing failed platform=MercadoPago` 12/min, `Platform Auth Error: TOKEN_MISSING` 4/min). Consumer-path errors (`setNews failed`, `setNews_processing failed`) appear only in the catch-up minute. `platforms-service` kept logging ~1,030 messages per minute and kept serving other work (MercadoPago token fetch ~950/min, p50 70 ms): the process was alive.
- Other 11 stalls: consumer-side calls 0 in every stall minute and a burst right after, no timeout/communication-error lines; 10-05 08:55 has too little traffic to judge. Limit: a call is logged when it completes; a call that never completed would not appear, but a timeout would log an error and none appears.
- Cause of the stall: not found in the logs.

**Alert chain and scaling on 2026-10-11 (C5, C6, C8, C9: `data/c5-run1-*`, `data/c6-run1-*`, `data/c8-run1-summary.txt`, `data/c9-run1-summary.txt`)**
- CloudWatch alarm `sendMailOldestMessage`: `ApproximateAgeOfOldestMessage` of `PRD_BranchMessages.fifo`, statistic **Average**, period 300 s, 1 of 1 datapoint, threshold > 25 s; unchanged since 2025-01-15; AlarmActions and OKActions both SNS `Pedidos_Production`, which has the Lambda `IntegrationLambdaEcsTaskProd` (plus email and SMS) subscribed. The user stated the trigger statistic is Maximum; the alarm as read is Average (not reconciled; possibly the Grafana alert). A second alarm, `sendMailOldestMessage100`, is `INSUFFICIENT_DATA` since 2025-02-22. In GITIN-2162 the user stated that no alarm existed for the metric; two exist.
- Alarm OK to ALARM at 22:02:25 (4 min 25 s after the stall began), back to OK at 22:10:25; the Lambda ran at both (22:02:25 and 22:10:25; no errors; duration 2.89 s and 2.96 s against a 3 s timeout). Over 10 days the Lambda ran in the 15-minute bucket of all 12 stalls.
- Tasks (C8, 1-minute Maximum): 5 running / 5 desired until 22:02; desired 15 and running 9 at 22:03; running 15 at 22:04; Application Auto Scaling then scaled in (14 at 22:05, 13, 14 again at 22:11 after the second Lambda run, then steps of ~3 minutes) to 5 at 22:39. Age 0 at 22:04 with 15 running. Service CPU average 21% before, 16.6% during the stall, 27% at 22:03 (Maximum 99.8%), 9-14% with 13-15 tasks.
- Consumption resumed at 22:03:00, about 30 s after the scale request and before the running count reached 15; whether the first new tasks (9 running in the 22:03 minute) contributed cannot be told from these series (inference: new tasks were probably not yet consuming). The stalls also occurred with 10 tasks (GITIN-2162), so more tasks are not expected to remove the cause. ECS service events for the night had rotated out of the 100-event buffer.
- The peak of 306 s is about half of the 10 minutes after which, as the user stated, an order can be cancelled.

**Capacity decision (user statement, 2026-10-13):** the permanent task size and task count of `platform-service` were not changed because the recurring behavior had not been detected as a pattern, so no need to change them was seen. Supporting data in this folder: the stalls occur with 5 tasks and also with 10 (GITIN-2162), consumption resumed at 22:03 before the added tasks would have been running, and platform latencies were normal; so the data does not show a capacity shortfall as the cause (not proof that more capacity would not help). Current service state read: 5 desired / 5 running at 22:44 on 10-11 (C8); task definition values are in `smartpedidos/docs/infrastructure.md` (the Compute table there is stale; GITIN-2162 records `:268`, 512 CPU units / 1024 MiB).

**Evidence that it was reviewed at the time:** only the user's statement that it was seen in Grafana at 22:03. No record of an action at that time was read.

## Current working theory

On 2026-10-11 the age of `PRD_BranchMessages.fifo` rose to 306 s because the consumers stopped processing messages for five minutes (21:58-22:02) and then caught up; the same happened 11 other times in 10 days. The delivery platforms answered normally before and after and no timeouts were logged, so a slow platform does not explain it. The alarm and the scale-up executed and the queue was back to normal at 22:04, but consumption restarted before the new tasks would have been running. The reason consumption stops is undetermined.

## Open items

- Who reviewed the 22:03 episode at the time and what was done (user statement only).
- Cause of the consumer stop (GITIN-2162): not found in `platforms-service` logs; MongoDB Atlas events and per-task CPU at the stall times were not checked; the exact start/stop within 2 s of whole minutes (21:57:58 / 22:03:00) is unexplained.
- Which trigger uses Maximum (the user's statement) against the alarm read as Average; Grafana alert settings were not read.
- Detection proposal (zero deletions for 2 minutes, age above 200 s) is not tested in production.

## Scripts (all read-only; outputs in `data/`)

`scripts.sh` (C1), `scripts-c2.sh`, `scripts-c3.sh`, `scripts-c4.sh`, `scripts-c5.sh`, `scripts-c6.sh` (incl. code download, not analysed), `scripts-c7.sh`, `scripts-c8.sh`, `scripts-c9.sh`, `scripts-c10.sh`. Defects found and fixed: `awk` text comparison (C2), `awk` decimal-comma locale (C4, now `LC_ALL=C`), CloudWatch 500-series cap (C1, replaced by named queries), 1440-datapoint limit (C5, replaced in C6), UTC/local string comparison in a filter (C5, recomputed). C6 summary printed SMS numbers; masked in the saved files and in the script.

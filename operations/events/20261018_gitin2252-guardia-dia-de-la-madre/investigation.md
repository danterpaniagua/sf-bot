# Investigation: [OPE] On-call duty, Mother's Day (GITIN-2252) — SmartPedidos brief

**Status (2026-10-18 22:30):** `brief.md`, `resumen.md`, `status-report.md` (Spanish, first person, tickets in the table) and `ops.md` written; measured data added for the SmartPedidos queues, dead-letter queues, platform and concentrador CPU/task drops, the store 4719 queue and Atlas CPU/RAM/network from Zabbix; the SQL review of the database moved to GITIN-2251 (subtask of GITIN-2250), out of this summary. `ops.md` was written once and not revised afterwards. Jira: https://smartit-ar.atlassian.net/browse/GITIN-2252 ("[OPE] Guardia Dia de la Madre", as given by the user; the ticket body was not seen).

## Request

User (2026-10-18): a brief on the SmartPedidos issue from Friday (2026-10-16) to now, with GITIN-2252 as the escalation. Written as `brief.md` (Spanish, hedged; sources below).

## Sources (existing events, read today; not re-verified against live systems)

- `smartpedidos/events/20261017_gitin2248-platform-contenedores-caidos-20261016/investigation.md` (GITIN-2248): task dips of platform-service on 10-13 to 10-16, the Dev fix (H4) and what remains (H5 circular JSON in the logger, H3 exit handler), the alerts' efficacy on 10-16, delivery, and the minimum capacity change to 10 (verified 2026-10-17 11:28-11:30).
- `smartpedidos/events/20261016_gitin2240-concentrador-alerta-fatal/investigation.md` (GITIN-2240): the idle concentrador FATAL alert.
- `smartpedidos/events/20261018_cac-tienda-4719-pedido-en-cola/investigation.md`: today's CAC request about store 4719 (read-only AWS checks written, not run; what was cleared at about 20:13 is not recorded).
- `loyalty/events/20261018_gitin2250-webservice-high-cpu/investigation.md`: today's WebService and Mobile events (not SmartPedidos).

## User-stated observation (2026-10-18, evening; not verified here)

The user reports that the spikes monitored in the WebService and Mobile are also visible in the behavior of the production queue `PRD_BranchMessages.fifo` (us-east-1), and that the dead-letter queues (`MainDeadLetter.fifo`, `DeadLetter.fifo`) did not increase. No SQS or CloudWatch data for it exists in this event. The check (sent, received, deleted, oldest-message age and visible messages of the queue; visible and sent of the dead-letter queues; from 10:00 UTC-3 until now) is written as `scripts/sqs-spikes-pull.sh` and not run.

The user also reports that MongoDB (SmartPedidos, Atlas, cluster PedidosSmartfran) had good health over the weekend. What Zabbix holds (host `Zabbix server`, items `[pedidossmartfran-shard-00-0N-narx2.mongodb.net] ...`, updated every 10 minutes per `{$MONGO_ATLAS_UPD_INT}`; data/zabbix-atlas-discovery-2205.txt, zabbix-atlas-history-2206.txt): CPU, RAM, data size, network in/out per shard, and an "AVG Reads Latency" item whose values equal the RAM values (so it is not used). Not collected in Zabbix: connections, replication lag, operation latency, disk IOPS, elections.

Atlas shard CPU, per-day maximum / mean (UTC-3 days; Fri 10-16, Sat 10-17, Sun 10-18 until 22:06): shard-00 21.8 / 20.9 / 25.3 % (mean 13.3 to 14.9); shard-01 13.6 / 14.4 / 17.4 % (7.8 to 9.1); shard-02 38.7 / 40.6 / 49.5 % (22.0 to 25.6), the Sunday maximum at 15:42. In the Sunday windows shard-02 peaked at 48.0 (W1 14:03-15:28), 44.0 (W2 16:34-17:10), 40.5 (W3 17:10-18:20) and 34.6 % (W4 19:02-19:18). shard-02 carries almost all the network traffic (about 160-185 KB in on average against about 6 KB on the other two; peak out 720 / 769 / 952 KB), which suggests it is the primary, but member states were not read. RAM of shard-02 3.0-3.07 GB, stable. No Atlas CPU trigger opened since 2026-10-16 (the nine CPU triggers carry no tags, so none would notify anyone anyway). The Sunday afternoon rise (15:22-15:42) coincides in time with the daily maximum of the main queue volume. Reading: no saturation in CPU, RAM or network at 10-minute resolution; the rest of the "good health" (connections, replication lag, latency, failovers) is user-stated and not verified; Atlas or Grafana would hold it, and the Grafana Atlas datasource is unmaintained and hides the Atlas API's real errors (GITIN-1748).

The user also reports that the SmartPedidos platform CPU spikes stayed below the 75 % threshold. No platform CPU data was read in this event, and which alarm or metric the 75 % belongs to (average or maximum, service or cluster) is not recorded. From the earlier GITIN-2248 read (not re-verified here): the Application Auto Scaling target-tracking policy for CPU uses an average of 60 % with a scale-out cooldown of 600 s, so CPU between 60 % and 75 % would act on scaling without crossing a 75 % alert.

## Measured on 2026-10-18 21:50-21:52 (data/sqs-spikes-summary-2151.txt, sqs-hourly-profile-2151.txt, sqs-dlq-visible-changes-2151.txt, platform-since-friday-analysis-2151.txt; AWS profile checked: account 382381053403)

- Platform-service, Running < Desired (stretches / minutes): 10-16 60 / 76 (lowest 2 of 5); 10-17 66 / 79 (before 11:28:38: 14 / 17; after: 52 / 62; lowest 3 then 5 of 10); 10-18 until 21:52 95 / 134 (lowest 7 of 10). Concentrador: 0 / 0 except one minute on 10-17 before the change. After the change "below desired" is a different measure (10 tasks), so counts before and after are not directly comparable; traffic per day not controlled. Consistent with the user-stated "more pronounced since Friday".
- Platform-service CPU (AWS/ECS, service level): highest per-minute Average 27.3 / 30.8 / 20.2 % on 10-16 / 17 / 18 (0 minutes above 60 or 75); highest per-minute Maximum 88.1 / 87.1 / 88.8 % with 28 / 32 / 48 minutes above 75. "Under 75" holds for the Average, not for the Maximum; which statistic the user's 75 refers to is not known. What the Maximum measures (a single task or a sampling artefact) was not verified.
- CPU, both services, Maximum as the user-stated criterion (data/platform-since-friday-analysis-2201.txt, 22:01 read): platform-service highest per-minute Maximum 88.1 / 87.1 / 88.8 % (10-16 / 17 / 18), minutes above 75: 28 / 32 / 49, none above 90; highest Average 27.3 / 30.8 / 20.2 %. Concentrador-service (one task) highest Maximum 99.9 / 99.6 / 100.0 %, minutes above 75: 13 / 11 / 18, above 90: 12 / 1 / 5; highest Average 81.8 / 99.6 / 77.7 % (minutes with Average above 75: 1 / 1 / 3). Platform-service drops until 22:01 on 10-18: 96 stretches / 135 minutes. Concentrador shows no task drops on those days (one minute on 10-17). The cause of the concentrador CPU peaks was not looked at.
CPU by per-minute Maximum (AWS/ECS `CPUUtilization`, service level, 1-minute data; UTC-3 days; 10-18 until 22:01; data/platform-since-friday-analysis-2201.txt):

| Service | Day | Highest Maximum % | Minutes Max > 75 | Minutes Max > 90 | Highest Average % |
|---|---|---|---|---|---|
| platform-service | 2026-10-16 | 88.1 | 28 | 0 | 27.3 |
| platform-service | 2026-10-17 | 87.1 | 32 | 0 | 30.8 |
| platform-service | 2026-10-18 | 88.8 | 49 | 0 | 20.2 |
| concentrador-service | 2026-10-16 | 99.9 | 13 | 12 | 81.8 |
| concentrador-service | 2026-10-17 | 99.6 | 11 | 1 | 99.6 |
| concentrador-service | 2026-10-18 | 100.0 | 18 | 5 | 77.7 |

The 75 % threshold on the Maximum is user-stated; where it is set was not seen. What the service-level Maximum measures (one task or a sampling artefact) was not verified. Concentrador-service runs one task, so its Average and Maximum are close.

Pending (user, 2026-10-18): analyse the behaviour of concentrador-service with more than one instance. Not done; whether more instances would lower the peaks is not known (the cause of the peaks was not looked at, and the 75 % decision follows from that analysis).

- `PRD_BranchMessages.fifo` (sent per minute, UTC-3 hours): mean 39 at 10h, 155 at 11h, 310 at 12h, 454 at 13h, 710 at 14h, 844 at 15h, 722 at 16h, 469 at 17h, 290 at 18h, 231 at 19h, 277 at 20h, 372 at 21h; day peak 1,020 in one minute at 16:04. Window peaks: 989 at 15:22 (W1), 764 at 16:35 (W2), 696 at 17:11 (W3), 276 at 19:12 (W4; mean 248 against a 19h mean of 231). Oldest-message age never above 32 s all day (hours 11-20: 22-32 s), visible messages at most 8. Reading: a daily curve with no spike distinguishable from it at this resolution; the user-stated link between the WebService/Mobile spikes and the queue is neither confirmed nor ruled out. The Maximum of the sent/received/deleted counts is 10 everywhere (the SQS batch size), so it carries no information; the Sum is the volume.
- Dead-letter queues: `DeadLetter.fifo` visible 1 all day; `MainDeadLetter.fifo` visible 102 at 10:00, then decreases only (93 at 16:50, 18 at 16:59, 15 at 18:47, 12 at 21:17); no increase. Correction of an earlier statement of mine: `NumberOfMessagesSent` of a dead-letter queue (0 all day) does not count messages that arrive through the redrive policy, so it is not evidence; the visible count is the signal used. Who or what removed ~90 messages from `MainDeadLetter.fifo` at 16:50-16:59 is not known.
- Store 4719: see `smartpedidos/events/20261018_cac-tienda-4719-pedido-en-cola/` (4 messages in flight for about 3.5 hours, received every 3 minutes, never deleted, gone at 20:14).

## Scripts (in `scripts/`; outputs in `data/`)

| # | Script | Purpose | Run |
|---|---|---|---|
| 1 | `sqs-spikes-pull.sh` + `sqs-spikes-analyze.py` | `PRD_BranchMessages.fifo` and dead-letter queues, 1-minute, Maximum (+ Sum for counts) | yes (21:51); first attempt 21:49 failed on AWS credentials |
| 2 | `platform-since-friday-pull.sh` + `platform-since-friday-analyze.py` | Running vs Desired, CPU Average/Maximum of platform-service and concentrador-service, days 16-18 | yes (21:51 and 22:01) |
| 3 | `zabbix-atlas-discovery.sh`, `zabbix-atlas-history.sh` | Atlas shard items, triggers and history held by Zabbix | yes (22:05, 22:06) |
| 4 | `mongo-health-snapshot.js` | Current MongoDB state (read-only, mongosh) | written, not run; not pursued (user decision, 2026-10-18) |
| 5 | `sqs-spikes-analyze.py` outputs | summaries `sqs-spikes-summary-2151.txt`, `sqs-hourly-profile-2151.txt`, `sqs-dlq-visible-changes-2151.txt` | yes |

## Restart of all VMs for Mother's Day (user, 2026-10-18)

All the VMs were restarted for Mother's Day as a fresh start (done by the user). The morning starts seen in Zabbix for the WebService hosts (GITIN-2250) correspond to it.

## Gaps that the brief states instead of filling

- No platform-service data after about 11:41 on 2026-10-17: dips, FATAL lines, CPU and ALB requests per target after the capacity change were not measured. The user mentioned spikes in WebService, Mobile and the SmartPedidos platform seen after the change to 10 tasks; the SmartPedidos part has no data here.
- Whether the Infrastructure-as-Code definition would revert the minimum of 10 on the next apply was not checked.
- Today's SmartPedidos queue check (store 4719) has no output yet.

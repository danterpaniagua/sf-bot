# SmartPedidos — Infrastructure Reference

**Last updated:** 2026-09-03

---

## Data Stores

| Store | Detail |
|---|---|
| MongoDB Atlas cluster | `PedidosSmartfran`, region `us-east-1` |
| Database | `smartfran` |
| Key collections | `orders`, `news`, `logerrors`, `deadletters`, `branches`, `chains`, `platforms`, `newsStates`, `newsTypes`, `configs` |

The `news` collection is the internal event/notification model — each document has a `traces` array tracking state transitions. **Confirmed 15-day retention on `news`** (2026-08-31, `GITIN-1965`): a `createdAt`-based query going back further than ~15 days from "now" returns nothing for the older portion — not a query bug, the documents are actually gone (TTL or equivalent housekeeping, mechanism not confirmed, only the effective retention window). Any analysis using `news` as a volume/activity signal is capped at a ~15-day lookback; plan comparisons accordingly (e.g. a week-over-week check only has ~2 clean prior weeks available, not more).

### Atlas Admin API Reference

| Field | Value |
|---|---|
| Project (`groupId`) | `5e29fa1e9ccf64d7ef306b9c` (project name `ProductionPedidos`) |
| Cluster name | `PedidosSmartfran` |
| Replica hosts (`processId` = `host:port`) | `pedidossmartfran-shard-00-00.narx2.mongodb.net:27017`, `-01`, `-02` |
| Instance size | M20, 3 electable nodes, `us-east-1` |

Base: `https://cloud.mongodb.com/api/atlas/v2` — digest auth (`--user "{PUBLIC_KEY}:{PRIVATE_KEY}" --digest`), requires a versioned `Accept: application/vnd.atlas.YYYY-MM-DD+json` header.

**WiredTiger cache metrics** — use `GET /groups/{groupId}/processes/{processId}/measurements?m=CACHE_USED_BYTES&m=CACHE_DIRTY_BYTES`. The dimension names are `CACHE_USED_BYTES`/`CACHE_DIRTY_BYTES` — **not** `CACHE_USAGE_USED`/`CACHE_USAGE_DIRTY` (those were a hardcoded error in the unmaintained `grafana-mongodb-atlas-datasource` plugin; see `events/20260803_grafana-cache-panel-fix/` for the full root cause).

**`clusterView`** is a path parameter on cluster-level (not per-process) measurement endpoints, e.g. collStats query latency: `GET /groups/{groupId}/clusters/{clusterName}/{clusterView}/{databaseName}/{collectionName}/collStats/measurements`. Allowed values: `PRIMARY`, `SECONDARY`, `INDIVIDUAL_PROCESS`. Not used by the per-process cache-measurements call above.

---

## Message Flow (AWS SQS)

```
PedidosYa / Rappi / UberEats / MercadoPago / PediGrido
        ↓  webhook
  platforms-service
        ↓  pushNewToQueue
  {branchId}_PlatformMessages.fifo  (per-branch; us-east-2 in test/staging, us-east-1 in production as {branchId}PRD_PlatformMessages.fifo)
        ↓  pollFromQueue (parent consumer)
            + up to 3 child consumers (auto-scale at 200 / 400 / 600 depth)
        ↓  setNews → news state transition
  BranchMessages.fifo → SmartFran agent (POS terminal)

  On failure → DeadLetter.fifo / MainDeadLetter.fifo
        ↓  concentrador-service deadLetterSave() on startup
  smartfran.deadletters  (MongoDB)
```

**Region:** `us-east-2` holds the test and staging queues (user-stated 2026-10-13; the testing queue URLs below were read from earlier work, no staging queue was listed). **Production queues are in `us-east-1`** (same region as the Atlas cluster): CloudWatch `AWS/SQS` in `us-east-1` returns `{branchId}PRD_PlatformMessages.fifo`, `PRD_BranchMessages.fifo`, `MainDeadLetter.fifo` and `DeadLetter.fifo` with live traffic (GITIN-2211 pulls, 2026-10-13). The `us-east-2` flow line above and the Auto-scaling note were not re-verified against production.

**Auto-scaling (platforms-service consumers):** based on `ApproximateNumberOfMessages` — depth > 200 spawns a 2nd consumer, > 400 a 3rd, > 600 a 4th.

**Dead letter retention:** `MessageRetentionPeriod: 259200` (3 days) — act within that window.

**Key config flag:** `configs.saveDeadLetterbol` — if `false`, concentrador-service skips dead letter recovery silently.

### Queue URLs (testing environment)

| Queue | URL |
|---|---|
| Producer | `https://sqs.us-east-2.amazonaws.com/382381053403/{branchId}_TST_PlatformMessages.fifo` |
| Consumer | `https://sqs.us-east-2.amazonaws.com/382381053403/TST_BranchMessages.fifo` |
| Dead letter | `https://sqs.us-east-2.amazonaws.com/382381053403/DeadLetter.fifo` |
| Main dead letter | `https://sqs.us-east-2.amazonaws.com/382381053403/MainDeadLetter.fifo` |

Production queue names observed in `us-east-1` (2026-10-13): per-branch `{branchId}PRD_PlatformMessages.fifo` (no underscore before `PRD`, e.g. `5713PRD_PlatformMessages.fifo`) and the shared `PRD_BranchMessages.fifo`, plus `MainDeadLetter.fifo` and `DeadLetter.fifo`.

**Stray queues in `us-west-2`:** a set of `{branchId}_PlatformMessages.fifo` queues (e.g. `1025PER_PlatformMessages.fifo`, created 2020-12-29) exist in account `382381053403` region `us-west-2`, outside the documented `us-east-2` production region. Confirmed created and unused (no active POS consumer) — likely leftover from early provisioning. Not part of the active message flow; flagged here as infra hygiene, not investigated further.

### Production queue signals (GITIN-2211, 2026-10-13)

Measured with CloudWatch `AWS/SQS`, `us-east-1`, queue `PRD_BranchMessages.fifo` (1-minute data; use `Maximum` for age and visible messages, `Sum` for sent/received/deleted):

- **Normal:** about 380-620 messages sent per minute in the evening, received and deleted within a few messages of sent, oldest-message age 0-4 s. Daily 5-minute peak of sent: 1361-3534 at the usual ~22:45 local (weekday evenings 1361-1882, Friday-Sunday evenings 2800-3534), so a fixed threshold on volume would fire daily.
- **Stall pattern:** consumption stops for 2-5 minutes (received and deleted at 0 while sends continue), visible messages and oldest-message age climb, then a catch-up burst (e.g. 2879 received / 2880 deleted in one minute) drains it. 12 stalls in 2026-10-03..10-12; all 12 reached age > 200 s (238-324 s), 10 reached >= 250 s and 5 reached >= 300 s. Each one coincides with a run of >= 2 minutes of zero deletions with sends > 0, and no other such run occurred in the 10 days. Cause not determined (same pattern as GITIN-2162 / GITIN-2110). Triage steps: `ops-aws` skill, F-007. Example: 2026-10-11 21:58-22:02, age 306 s at 22:03.
- **Dead letters:** `MainDeadLetter.fifo` holds a stock of 30-77 visible messages and received 0 messages in the 10 days; `DeadLetter.fifo` visible 0-3. Neither moves during stalls.
- **Pull limit:** a CloudWatch `SEARCH` over all SQS queues is cut at 500 series (`MaxMetricsExceeded`); request the queue by name or split by branch range.

**Alerting chain on `PRD_BranchMessages.fifo` (read 2026-10-13, GITIN-2211):** CloudWatch alarm `sendMailOldestMessage` (`ApproximateAgeOfOldestMessage`, Average, 300 s period, threshold > 25 s) notifies SNS topic `Pedidos_Production` (Lambda, email and SMS subscriptions). The Lambda `IntegrationLambdaEcsTaskProd` (`us-east-1`, python3.12, timeout 3 s, ~2.9 s per run) sets `platform-service-production-service` (cluster `smartfran-pedidos-production`) to 15 desired tasks whenever fewer than 15 are running; Application Auto Scaling target tracking then scales back in (3-minute steps). The Lambda fired in all 12 stalls of 2026-10-03..10-12. A second alarm, `sendMailOldestMessage100`, has been `INSUFFICIENT_DATA` since 2025-02-22.

Reported by the team, not independently checked: Grafana shows these queue metrics and alerts above 250 s of oldest-message age; 250 s was chosen because an order can be cancelled when no news arrives within 10 minutes.

---

## Compute (ECS Fargate)

| Field | Value |
|---|---|
| Cluster | `smartfran-pedidos-production` |
| Region | `us-east-1` |
| Services | `concentrador-service-production-service`, `platform-service-production-service` |
| `concentrador-service` desiredCount / runningCount | `1` / `1` (steady state, confirmed via `describe-services`) — single task, no redundancy |
| `platform-service` desiredCount / runningCount | `10` / `10` (raised from `5`/`5` on 2026-08-05 as a follow-up to the CPU/health-check incident, see below) |
| Deployment controller / strategy | `ECS`, `ROLLING`, `maximumPercent: 200`, `minimumHealthyPercent: 100` |

**Update 2026-10-13 (GITIN-2162, GITIN-2211) — the `platform-service` row above and the task-definition table below are stale:** the service ran at desired/running `5`/`5` on 2026-10-05 08:42 (after a MinCapacity of 10 applied 2026-10-04 15:24), and at 5 tasks at 22:02 on 2026-10-11. The current task definition is `platform-service-production-task:268` (registered 2026-09-28, 512 CPU units / 1024 MiB, image tag `10.9.12`), not `:253`. During queue-age alarms the service is pushed to 15 desired tasks by a Lambda and then scaled in by Application Auto Scaling in 3-minute steps (e.g. 14 at 22:05, 5 at 22:38 on 2026-10-11); see "Production queue signals" above. The table rows were not edited.

**Open risk (2026-07-22, confirmed via `describe-services` event history):** `concentrador-service` is only ever run at `desiredCount: 1`, but the `ROLLING` strategy (`maximumPercent: 200`) means every deployment briefly runs the old and new task concurrently — the new task is started and **registered** to the ALB target group before the old task begins draining/deregistering. This is a real overlap window, not a hypothetical scale-out scenario. Combined with `deadLetterSave() on startup` (see Message Flow above), this means two instances can already run `deadLetterSave()` concurrently during a deploy — a duplicate-processing risk that predates and is independent of any decision to run this service at `desiredCount > 1`.

**Confirmed (2026-07-22):** no Application Auto Scaling target is registered for `concentrador-service` (`describe-scalable-targets` → `[]`) — its `desiredCount` never moves beyond `1` on its own.

**platform-service Application Auto Scaling (confirmed 2026-08-05):** a scalable target has existed since `2020-10-20` (`ecs:service:DesiredCount`, `arn:aws:application-autoscaling:us-east-1:382381053403:scalable-target/0ec57b5b49502adf4af4848eb47324ab8e44`) — this was never previously documented here. `MinCapacity` was raised `5` → `10` on 2026-08-05 as a follow-up to the CPU/health-check incident (`events/20260805_concentrador-platforms-high-cpu-healthcheck/`); `MaxCapacity` is `25`, unchanged. Raising the floor gives more headroom to absorb the same per-task CPU pressure without a single task's health-check failure removing as large a fraction of total capacity.

**Task definitions (confirmed via `describe-task-definition`, revisions current as of 2026-08-05 — a scale-up applied that day, see `events/20260805_concentrador-platforms-high-cpu-healthcheck/`):**

| Field | `concentrador-service-production-task:318` | `platform-service-production-task:253` |
|---|---|---|
| CPU / memory | `1024` / `2048` (1 vCPU / 2 GB) — was `256`/`512` before the 2026-08-05 scale-up | `2048` / `5120` (2 vCPU / 5 GB) — was `512`/`2048` before |
| Container port | `3086` | `3087` |
| Env vars | `SERVICE_NAME=concentrador-service`, `NODE_ENV=production` — no leader-election/lock/instance-id config | `SERVICE_NAME=platforms-service`, `NODE_ENV=production`, `maxCpuLoad=0.7`, `maxMemUsage=2` |
| Task role | `smartfran-task-role` | `smartfran-task-role` |
| Log group | `/ecs/concentrador-service-production-task` | `/ecs/platform-service-production-task` |

No infra-level safeguard (lock, leader election) against the two-tasks-briefly-registered overlap above — if `deadLetterSave()` or other startup logic is protected against double-execution, that protection would have to be in application code. **Local source working copies (edit and pull allowed, never commit or push) now exist** for both services (`smartpedidos/repo/dev-src-smartPedidos-concentradorService/`, `smartpedidos/repo/dev-scr-smartPedidos-platformsService/` — see `smartpedidos/CLAUDE.md`); no double-execution guard was found there either as of 2026-08-05.

### Load Balancer / Target Groups (confirmed 2026-08-05)

Both services sit behind the **same ALB**: `pedidos-concentrador-alb` (`arn:aws:elasticloadbalancing:us-east-1:382381053403:loadbalancer/app/pedidos-concentrador-alb/54b7236209d50ece`).

| | concentrador-service | platform-service |
|---|---|---|
| Target group | `concetrador-serprod-tg` | `platform-service-production-tg` |
| HealthCheckPath | `/` | `/api/metrics/health-check` |
| Matcher | `404` (expects 404 on an unmapped route — generic liveness, not app-aware) | `200` (hits the app's self-reporting `GET /metrics/health-check`, which returns 400 when `os.loadavg()[0] > maxCpuLoad`) |
| Timeout / Interval | `120s` / `300s` | `5s` / `30s` |
| Unhealthy threshold | `2` | `2` |

concentrador's check is lenient (needs several minutes of total unresponsiveness to trip) and CPU-unaware. platform's is tight — as little as ~30–60s of the app self-reporting overloaded is enough to get a task killed. This asymmetry matters when diagnosing "tasks getting killed" reports: check which service and pull the matching target group before assuming a shared mechanism.

**ALB logging (confirmed 2026-08-05):** `access_logs.s3.enabled: true` → bucket `prod-alb-concentrador-logs` (regular client-traffic access logs). `health_check_logs.s3.enabled: false` — the ALB's own health-check requests/responses are **not** captured anywhere, past or future, until this is turned on. No S3 event notification (`get-bucket-notification-configuration` → empty) is wired to `prod-alb-concentrador-logs`, so nothing pushes those access logs onward automatically (e.g. to Graylog) — confirm separately on the Graylog side (System → Inputs) if a poll-based S3 input exists there.

---

## S3 Export Pipeline (Grido / Multi-Platform)

Two scheduled Lambda functions (region `us-east-1`, account `382381053403`), both triggered by their own EventBridge rule on the identical schedule `cron(30 3 * * ? *)` (03:30 UTC daily / 00:30 -03:00):

| Function | Runtime | Writes to | Notes |
|---|---|---|---|
| `mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO` | `nodejs24.x` (bumped from deprecated `nodejs12.x`, 2026-08-31) | `smartfranbkp/news/YYYY/MM/newsYYYYMMDD.json` **and** `newsYYYYMMDD-3.json` (both, since 2026-09-01) | Reads `news` collection, rewrites a rolling `DAYSBEFORE`-day window every run (currently `2`; deliberate resilience/self-healing against missed runs, not a bug). Writes **two files per day from independent queries**: `newsYYYYMMDD.json` (UTC-midnight boundary, `ARG_OFFSET_MINUTES=0` — kept for backwards compatibility) and `newsYYYYMMDD-3.json` (Argentina/UTC-3 boundary, `ARG_OFFSET_MINUTES=-180`, both env-var-configurable) — `GITIN-1970`, see `events/20260831_lambda-s3-export-utc3/`. Field values inside each record remain raw UTC ISO strings (`Z` suffix) regardless of which file — out of that fix's scope. Output goes through `orderMapper()`, which **renames every field to lowercase** (`order.platformId` → `order.platformid`, etc. — top-level `typeId`/`branchId` are the exception, they stay camelCase) and **silently drops fields not explicitly mapped** — confirmed gaps found 2026-09-01: `order.tenant` (entirely absent, not usable as a filter), `order.originalId`/`displayId`/`details[].canje` (added to the mapper that day), plus 12 more populated-but-unmapped SEND-classified fields (`orderPickedUp`, `orderDelivered`, `extraData.country`, etc. — see `events/20260901_grido-redacted-etl-lambda/investigation.md` for the full list). **Any code reading these exported files must account for the lowercase renaming and must not assume a field survived the mapping just because it exists on the raw Mongo document.** |
| `mongoAllCollections-to-s3-CFN-ScheduledMongoToS3-MRO2H3EOSN6E` | not confirmed | `smartfranbkp/<collection>/` | Exports a fixed set of reference collections (`activeSoftware`, `branches`, `chains`, `clients`, `countries`, `deliveryTimes`, `newsStates`, `newsTypes`, `platforms`, `regions`, `users`, `rejectedMessages` — **not** `news`), despite the "AllCollections" name. |

**`smartfranbkp` bucket:** multi-purpose, holds many unrelated top-level prefixes beyond `news/` (`activeSoftware/`, `branches/`, `orders/`, etc.) — not dedicated to any single pipeline. **Lifecycle: `news/` transitions to `DEEP_ARCHIVE` (Glacier) after 365 days from `LastModified`** (confirmed 2026-09-01) — anything older requires an explicit `restore-object` call (~12+ hour wait) before it can be read. "Hot" (`STANDARD`) storage is always roughly the trailing 365 days from whenever it's checked.

**Historical normalization (`GITIN-1980`, `events/20260901_s3-history-utc3-normalization/`, completed 2026-09-01):** `2025-08-17` through `2026-08-30` was retroactively backfilled with `-3` files (re-bucketing existing UTC-day-boundary files into Argentina-day boundaries, no field-value changes) — this range predates the live Lambda's own `-3` output and needed a separate one-off Python script (`scripts.py` in that event folder) rather than re-running the Lambda itself. Anything before `2025-08-17` is in Glacier and was out of scope.

**Known issue, still unresolved as of 2026-09-01:** `mongo-to-s3`'s exported `news` records (both `newsYYYYMMDD.json` and `newsYYYYMMDD-3.json`) contain raw, unredacted customer PII (`customer.name`, `address`, `phone`, `dni`, `email`) — confirmed against real production data. See `smartpedidos/events/20260818_grido-news-etl-s3/field-classification.md` for the full REDACT/SEND-COND/SEND field classification. Not fixed at the source — the redaction happens downstream, see below.

**Two different record shapes coexist under the same `-3`/UTC0 file naming convention (confirmed 2026-09-02, GITIN-1874 H8) — critical for any code reading these files.** `orderMapper()` had a long-standing dead-code bug (GITIN-1970 H4: it built the intended lowercase-mapped object but returned the original, unmapped one) present in every historical version reviewed. Files written while that bug was live are in the **raw MongoDB document shape** (`extraData` — capital D, `originalId`, `platformId`, `order.tenant.name`/`orgId`/`tenantId` present). Files written after the mapping bug was fixed are in `orderMapper()`'s **intended transformed shape** (`extradata` — lowercase, `originalid`, `platformid`, no `tenant` at all — the mapper never copies it). The observed transition point in the export archive is ~2026-08-17, but that's an empirical boundary from one investigation's sample, not a documented deploy date — don't treat it as exact. **`order.tenant.name`/`orgId`/`tenantId` is real and present on 100% of raw-shape records** (confirmed on real data from 2025-10, 2026-05, and 2026-08) — it is only absent from the transformed shape specifically, not from the underlying data. Any script or Lambda reading these files (this one included) must handle both shapes or it will silently treat real data as absent — exactly what happened to `grido-redacted-etl` before this was found (see below).

**Redacted downstream pipeline (`GITIN-1874`, `events/20260901_grido-redacted-etl-lambda/`) — deployed and operational as of 2026-09-02.** A Python Lambda, `grido-redacted-etl`, reads the `-3` files above, filters to `extradata.chain == "Grido"` (**not** `extraData.platform: "PediGrido"` — confirmed 2026-09-01 that PediGrido is only ~19% of Grido's actual volume across platforms; cross-validated 2026-09-02 that `chain` and `tenant.name` never disagree, 0 discrepancies across 81,137 real records), applies a field allow-list confirmed directly against Grido's real requested schema, and writes to a dedicated bucket `smartpedidos-orders` (`us-east-1`, created under `GITIN-1880`, `events/20260831_s3-bucket-securization/`) under a `grido/` prefix. `customer.dni` is deliberately included despite its REDACT classification — a business decision, not a confirmed Legal/PM sign-off. Independent of the two functions above — does not repoint or modify them. **Handles both record shapes** (via `get_ci()`/`get_extradata()` helpers, added 2026-09-02 after the dual-shape bug above was found) — a full historical backfill (2026-05-01 through 2026-09-01) is complete and validated as genuinely Grido-only. No EventBridge schedule yet — manual invoke only; see that event folder for status. Failure alerting is tracked separately under `GITIN-1979`, `events/20260902_error-message-alerting/`.

---

## Alerting / EventBridge (account-wide, confirmed 2026-09-02)

Custom (non-third-party) EventBridge rules with an event pattern, found via `aws events list-rules --query "Rules[?EventPattern!=null]"` — a much larger set of `MontyCloud-*` rules also exists in this account, belonging to a third-party cloud-management SaaS, not built in-house, and not relevant to this project's own alerting:

| Rule | Fires on | Target |
|---|---|---|
| `ECS-ServiceAction-Team` | ECS Service Action events, `smartfran-pedidos-production` cluster | SNS `Alertas-EventBridge-PROD` |
| `ECS-Task-Definition-Version-Created` | New task definition versions, same cluster | SNS `Alertas-EventBridge-PROD` |
| `ECR-Registry-Events-Alert` | ECR image push/action | SNS `Alertas-EventBridge-PROD` |
| `ECS-Task-ECSTaskStateChange-Team` | ECS Task State Change, same cluster | SNS `SNS-SmartPedidosTeam-PROD` |
| `ECS-ContainerInstanceStateChange-Team` | ECS Container Instance State Change, same cluster | SNS `SNS-SmartPedidosTeam-PROD` |
| `ECS-Task-ECSDeploymentStateChange` | Deploys to that cluster | SNS `SNS-SmartPedidosTeam-PROD` |

**Two different SNS topics, not one** — confirmed by checking all six rules directly rather than assuming the rest matched `ECS-ServiceAction-Team`'s target by naming convention (both `arn:aws:sns:us-east-1:382381053403:<name>`, both invoked via the same role `Amazon_EventBridge_Invoke_Alerts_Prod`, each with its own Spanish-language `InputTransformer`). `SNS-SmartPedidosTeam-PROD` is named specifically for this team and carries task-state/container-resource/deployment alerts; `Alertas-EventBridge-PROD` carries task-def versioning and ECR events.

**These fire on ECS cluster events only (concentrador-service/platforms-service) — neither catches Lambda function failures.**

**Lambda-failure alerting added (`GITIN-1979`, `events/20260902_error-message-alerting/`) — deployed and end-to-end confirmed 2026-09-03:**

- Two `CloudWatch Alarm`s on the `AWS/Lambda` `Errors` metric (threshold ≥1 per 5-minute period, `TreatMissingData: notBreaching`), both publishing to **`SNS-SmartPedidosTeam-PROD`** (chosen over `Alertas-EventBridge-PROD` — confirmed via `list-subscriptions-by-topic` that `SmartPedidosTeam` reaches the team distribution list `smartpedidos@smartfran.com` plus an individual, while `Alertas-EventBridge-PROD` only reaches one individual):
  - `grido-redacted-etl-errors` → `grido-redacted-etl` (GITIN-1874)
  - `mongo-to-s3-scheduled-errors` → `mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO` (GITIN-1970)
- A Python Lambda, `sp-pipeline-alerts-chat-bridge`, was built to subscribe to `SNS-SmartPedidosTeam-PROD` (Lambda-protocol SNS subscription) and re-post each alert to **two Google Chat spaces** (Operations and SmartPedidos) via incoming webhooks. Webhook URLs are plain Lambda env vars (`GOOGLE_CHAT_WEBHOOK_URLS`, comma-separated) — same secret-handling pattern as `MONGO_USER`/`MONGO_PASSWD` on the source Lambda, a deliberate choice over SSM `SecureString`. The bridge's execution role has no AWS resource access beyond writing its own CloudWatch logs; its SNS-invoke permission is scoped to this one topic ARN, not account-wide.
- **Validated with a real alarm-triggered test** (`aws cloudwatch set-alarm-state` forcing `grido-redacted-etl-errors` into `ALARM`, then back to `OK`): confirmed the alert reached both Google Chat spaces and both existing team emails through the actual production path, not just a synthetic direct invoke.
- **Google Chat leg deactivated the same day (2026-09-03) — too verbose.** Unsubscribed `sp-pipeline-alerts-chat-bridge` from `SNS-SmartPedidosTeam-PROD` (reversible — the function, its code, and its IAM role remain deployed, just idle). **Current live state: email-only**, via the two pre-existing subscriptions (`smartpedidos@smartfran.com`, `dantep@smartfran.com`). Re-enabling Chat later only needs an `aws sns subscribe` call, no rebuild.

Check `events/20260902_error-message-alerting/` for detail (`ops.md`/`ops-events.md` formalized 2026-09-03).

---

## Services

| Service | Role |
|---|---|
| `platforms-service` | Inbound integration layer for delivery platforms. Validates/normalises orders, persists to MongoDB (`orders` + `news`), pushes to AWS SQS. `Platform` base class with per-platform subclasses for the full order lifecycle. Manages restaurant open/close scheduling and per-platform delivery-time/rejection-reason catalogues. |
| `concentrador-service` | Internal management and POS-facing backend. Serves SmartFran agents and the management dashboard. Owns the SQS consumer path bridging platforms-service to branch POS terminals. Handles dead-letter recovery, platform-history auditing, `news` state transitions. |

Local source working copies (edit and pull allowed, never commit or push) exist in `smartpedidos/repo/` (see above) for architecture/root-cause lookups — see `smartpedidos/CLAUDE.md` for where actual source-level work happens (`smartfran/sp-logs`, a separate project).

---

## Related

- Skill: `/ops-aws` — failure catalog and diagnostic queries for SQS/dead-letter issues (consumer down, stuck orders, DLQ accumulation, queue depth buildup).
- Skill: `/sp-sre-output` — Jira tickets, closure reports for SmartPedidos incidents.
- `docs/cicd.md` — CI/CD pipeline reference (branch strategy, Jenkins/Trivy status per service, `sf-devops` pointer) — deliberately kept separate from this file, which covers runtime/AWS infrastructure only.

# SmartPedidos — Infrastructure Reference

**Last updated:** 2026-08-05

---

## Data Stores

| Store | Detail |
|---|---|
| MongoDB Atlas cluster | `PedidosSmartfran`, region `us-east-1` |
| Database | `smartfran` |
| Key collections | `orders`, `news`, `logerrors`, `deadletters`, `branches`, `chains`, `platforms`, `newsStates`, `newsTypes`, `configs` |

The `news` collection is the internal event/notification model — each document has a `traces` array tracking state transitions.

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
  {branchId}_PlatformMessages.fifo  (per-branch, us-east-2)
        ↓  pollFromQueue (parent consumer)
            + up to 3 child consumers (auto-scale at 200 / 400 / 600 depth)
        ↓  setNews → news state transition
  BranchMessages.fifo → SmartFran agent (POS terminal)

  On failure → DeadLetter.fifo / MainDeadLetter.fifo
        ↓  concentrador-service deadLetterSave() on startup
  smartfran.deadletters  (MongoDB)
```

**Region:** `us-east-2` (queues) — note this differs from the MongoDB Atlas cluster region (`us-east-1`).

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

Production queue naming follows the same pattern without the `_TST_` segment (e.g. `{branchId}_PRD_PlatformMessages.fifo`) — confirm exact naming before use, not independently verified.

**Stray queues in `us-west-2`:** a set of `{branchId}_PlatformMessages.fifo` queues (e.g. `1025PER_PlatformMessages.fifo`, created 2020-12-29) exist in account `382381053403` region `us-west-2`, outside the documented `us-east-2` production region. Confirmed created and unused (no active POS consumer) — likely leftover from early provisioning. Not part of the active message flow; flagged here as infra hygiene, not investigated further.

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

No infra-level safeguard (lock, leader election) against the two-tasks-briefly-registered overlap above — if `deadLetterSave()` or other startup logic is protected against double-execution, that protection would have to be in application code. **Local read-only source clones now exist** for both services (`smartpedidos/repos/dev-src-smartPedidos-concentradorService/`, `smartpedidos/repos/dev-scr-smartPedidos-platformsService/` — see `smartpedidos/CLAUDE.md`); no double-execution guard was found there either as of 2026-08-05.

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

## Services

| Service | Role |
|---|---|
| `platforms-service` | Inbound integration layer for delivery platforms. Validates/normalises orders, persists to MongoDB (`orders` + `news`), pushes to AWS SQS. `Platform` base class with per-platform subclasses for the full order lifecycle. Manages restaurant open/close scheduling and per-platform delivery-time/rejection-reason catalogues. |
| `concentrador-service` | Internal management and POS-facing backend. Serves SmartFran agents and the management dashboard. Owns the SQS consumer path bridging platforms-service to branch POS terminals. Handles dead-letter recovery, platform-history auditing, `news` state transitions. |

Local read-only source clones exist in `smartpedidos/repos/` (see above) for architecture/root-cause lookups — see `smartpedidos/CLAUDE.md` for where actual source-level work happens (`smartfran/sp-logs`, a separate project).

---

## Related

- Skill: `/ops-aws` — failure catalog and diagnostic queries for SQS/dead-letter issues (consumer down, stuck orders, DLQ accumulation, queue depth buildup).
- Skill: `/sp-sre-output` — Jira tickets, closure reports for SmartPedidos incidents.

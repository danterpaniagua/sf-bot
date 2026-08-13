# Investigation — 20260805_concentrador-platforms-high-cpu-healthcheck

**Status:** converged — ready for ticket

**Jira:** [GITIN-1783](https://smartit-ar.atlassian.net/browse/GITIN-1783)

## Remediation applied (2026-08-05, during this investigation)

- platform-service's Application Auto Scaling target (`ecs:service:DesiredCount`, existed since 2020-10-20, previously undocumented) — `MinCapacity` raised `5` → `10`. `desiredCount`/`runningCount` followed to `10`/`10`. `MaxCapacity` unchanged at `25`. Rationale: gives more headroom so a single task's health-check failure removes a smaller fraction of total capacity, reducing the cascade risk described in the kill-loop pattern below. Recorded in `smartpedidos/docs/infrastructure.md`.

## Rollback (2026-08-06)
Task definitions reverted to their pre-incident revisions: concentrador-service `:318` → `:317` (cpu/memory back to `256`/`512`), platform-service `:253` → `:252` (cpu/memory back to `512`/`2048`).

**Confirmed current state (`describe-services` + `describe-scalable-targets`, 2026-08-06 — two checks, state changed between them):**
- First check: `concentrador-service` rollback to `:317` still `IN_PROGRESS` (transient `desired:1`/`running:2` overlap); `platform-service` rollback to `:252` complete at `desired:10`/`running:10`, with ASG `MinCapacity` still `10` (not yet reverted at that point).
- **Second check (later same session): full revert confirmed on both services.** `concentrador-service`: `:317`, single `PRIMARY`/`COMPLETED` deployment, `desired:1`/`running:1`. `platform-service`: `:252`, single `PRIMARY`/`COMPLETED` deployment, `desired:5`/`running:5`, ASG `MinCapacity`/`MaxCapacity` now `5`/`25` — **the `5`→`10` MinCapacity change was also reverted**, between the two checks.
- **Net state: both services are fully back to pre-incident spec and capacity, zero cushion anywhere.** No code-level fix (timeout on `httpClient`, overlap guard on the cron) is in place either. A repeat PediGrido degradation would hit both services exactly as it did on 2026-08-05, with no mitigation of any kind currently standing.

**Rationale (user, 2026-08-06):** the cpu/memory scale-up was never believed to be the actual fix — it coincided with PediGrido's own recovery, not with anything that addressed the real defect. User's stated position: the real root cause is the missing timeout on concentrador-service's shared HTTP client (`utils/httpClient.js`), not health-check/"heartbeat" sensitivity — consistent with this investigation's own H3/root-cause section. A PM-facing narrative may describe the incident as a health-check/heartbeat issue (simpler framing, not incorrect for platform-service's kill-loop *mechanism*), but that is not being treated internally as the root cause for concentrador-service's CPU pressure.

**Risk this reopens:** the Dev action items that address the actual root cause (Acciones propuestas #1 — add timeout to `httpClient`; #2 — overlap guard on `checkOfflinePOSpedigrido`) have not been implemented yet. With the capacity scale-up now reverted and those code fixes still pending, a repeat PediGrido outage would hit concentrador-service (and platform-service, if its own kill-loop trigger is confirmed related) with no mitigation in place at all — neither the capacity cushion nor the code fix. Worth stating in the ticket as an open risk, not implying the incident is fully closed.

## Confirmed facts

**Infrastructure**
- ECS cluster `smartfran-pedidos-production` (`us-east-1`, account `382381053403`).
- concentrador-service: Fargate, was `cpu: 256`/`memory: 512` (task-def `:317`), scaled to `cpu: 1024`/`memory: 2048` (`:318`, registered 2026-08-05 18:06 -03:00). `desired: 1` / `running: 1` — single task, no redundancy, before and after the scale-up.
- platform-service: Fargate, was `cpu: 512`/`memory: 2048` (`:252`), scaled to `cpu: 2048`/`memory: 5120` (`:253`, registered 17:37 -03:00). `desired: 5` / `running: 5`.
- Diffing `:317`→`:318` and `:252`→`:253` (`aws ecs describe-task-definition`): the **only** changes are `cpu`/`memory` — no image or env var changes. Rules out a bad deploy as the trigger; this was a capacity scale-up applied mid-incident.
- ECS service events (C1): each service shows exactly one clean rolling deployment for the scale-up — concentrador 18:12:25→18:19:11, platform 18:12:39→18:15:01. No further "stopped tasks" events after that.
- `describe-tasks` on the specific stopped task IDs from that window: all `stoppedReason` = `"Scaling activity initiated by (deployment ecs-svc/...)"`. **These particular stops are confirmed deployment-driven, not health-check kills.**
- CloudWatch `CPUUtilization` (C3, 5-min buckets): before the scale-up (16:28–18:13 -03:00), both services show repeated *maximum* spikes to 75–99% with low averages — bursty, not sustained. After the scale-up completes, max CPU drops to single/low-double digits and stays there.
- ALB target-group health check config (C4):
  - **platform-service**: `HealthCheckPath: /api/metrics/health-check`, `Matcher: 200`, `Timeout: 5s`, `Interval: 30s`, `UnhealthyThreshold: 2` — hits the app's self-reporting endpoint directly, tight enough that ~30–60s of failing checks kills a task.
  - **concentrador-service**: `HealthCheckPath: /`, `Matcher: 404`, `Timeout: 120s`, `Interval: 300s`, `UnhealthyThreshold: 2` — generic liveness probe, unrelated to CPU/load, far too lenient for a brief spike to trip.
  - Both target groups report all current targets healthy (concentrador 1/1, platform 5/5) as of 18:45.

**Application code**
- platforms-service exposes `GET /metrics/health-check` (`api/src/controllers/metrics.js:5-46`, wired to the ALB path above). Returns HTTP 400 whenever `os.loadavg()[0] > maxCpuLoad` (env, `0.7`). The paired memory guard (`usedMem > maxMemUsage`) is dead code — `usedMem` is a 0–1 ratio, `maxMemUsage` env is `"2"`, so it can never fire. This logic/env pair has been in place since April 2025 (commits `46c934f5`, `ca5c3f98`, `aaf959ee`) — not a recent regression.
- concentrador-service has no app-level health-check route in source at all.
- **Root-cause code path (concentrador-service):** `branch.js:1744` schedules `checkOfflinePOSpedigrido()` on a cron firing **every minute** (`*/1 * * * *`). For every active PediGrido branch needing an open/close sync, it fires a concurrent `PUT` to PediGrido's `v1/locals/status` (`branch.js:1128-1130`) via the shared `httpClient` (`utils/httpClient.js:5`), which is `axios.create()` with **no default timeout** — axios's default is `0` (wait forever) — and the call site (`headersConfig`) passes only headers, no per-request timeout override. The fan-out (`branchesToClose.map(...)` → `Promise.allSettled(...)`) has no concurrency cap and no "skip if previous run still in flight" guard.

## Root cause (converged)

**PediGrido's API (`app.pedigrido.com`) degraded/partially outaged from ~19:28 to ~21:02 UTC (16:28–18:02 -03:00) on 2026-08-05**, evidenced by a Graylog export of concentrador-service PERF logs (`All-Messages-search-result.csv`, 5693 rows, all `concentrador-service`/`PERF`/`INFO`, same window):
- Calls to `v1/locals/status` and `v1/Grido/ConfirmarPedido` took as long as **125–218 seconds** each (e.g. a batch of near-simultaneous calls all resolving together at 19:51:18 UTC after ~137.9s).
- Status-code breakdown for all PediGrido calls in the export: `200`: 809 (many still very slow), `524` (Cloudflare gateway timeout — PediGrido's own origin unresponsive): 248, `502`: 78, `503`: 25, `500`: 3, `400`: 444.
- 761 of ~1600 PediGrido calls in the export took over 5 seconds. First slow call 19:28:08 UTC, last 21:02:12 UTC — sustained across the whole captured window, not a brief blip.
- A Graylog "aggregating duration_ms by msg_rest_url" panel for this same URL (screenshot) shows the aggregate climbing to ~125,000–140,000ms during 19:30–20:45 UTC and dropping back to baseline (~15–20k) by 21:00 UTC — same window.

Because `httpClient` has no timeout and the cron re-fires every 60 seconds regardless of whether the previous batch of PediGrido calls has resolved, each cron tick during the outage added a fresh, unbounded batch of concurrent hung requests on top of whatever was still pending from prior ticks. This is what plausibly drove concentrador-service's CPU/event-loop pressure over a sustained ~90-minute window (matches the CloudWatch CPU-spike window almost exactly) — not a single brief burst, but an accumulating pileup that only resolved once PediGrido recovered and/or the task was scaled up.

A CloudWatch dashboard screenshot (SQS `ApproximateAgeOfOldestMessage` and `MainDeadLetter` `ApproximateNumberOfMessagesVisible`) shows the dead-letter backlog roughly doubling (55→109) in the same rough timeframe — consistent with the same concentrador-service process being globally strained (SQS consumption sharing the event loop/process with the hung PediGrido calls), though the exact timezone of that dashboard screenshot wasn't independently confirmed and this point is corroborating, not load-bearing.

**External corroboration (reported, not independently verified):** PediGrido's own team reported they could not identify which process on their end was consuming their backend capacity — i.e. an admission of an issue on their side during this window. This is secondhand/reported, not something confirmed directly by us, but it's consistent with the 524s (Cloudflare gateway timeout — PediGrido's own origin unresponsive) and 125-218s response times independently found in our own PERF logs above. Combine as: our own data confirms the symptom from our side; PediGrido's admission corroborates the cause sitting on their side, not something SmartFran-side caused.

## What actually happened to the tasks (full ECS event history pulled — corrects earlier assumptions)

- **concentrador-service: never killed.** Full service-event history shows its single task ran continuously from 10:02:08 -03:00 straight through to 18:17:59 -03:00 (stopped only for the scale-up deployment) — **zero stop events during the incident window**. The "health-check is killing tasks" claim does **not** apply to concentrador-service at all; whatever CPU/PediGrido pressure it experienced, ECS never restarted it. This corrects the working theory from earlier in this file, which had wrongly kept concentrador in scope for the health-check-kill claim.
- **platform-service: this is where it actually happened.** Full event history shows a near-continuous kill-and-replace cycle — roughly 20 separate "stopped N running tasks" events, one every 2–3 minutes, from at least **17:15:35 through 18:01:19 -03:00** (46+ minutes), well before the 17:37 scale-up. This is independent of and predates the scale-up — it's the actual incident, not a deployment artifact.
  - ECS's service-event history is capped at ~100 events; platform-service burned through all 100 within about an hour of this churn, so the *true* start (user-reported ~16:30 -03:00) is earlier than 17:15:35 and has already scrolled out of the API — the earliest visible event is a "draining" already in progress, meaning a stop happened before our visibility window starts.
  - Attempted to confirm the literal `stoppedReason` on 10 of these task IDs (spanning 17:18–17:52) — all returned empty; at 1h10m–1h47m old at query time, they'd already aged past ECS's stopped-task retention window. **No literal `stoppedReason` string was recovered for any platform-service kill in this window.** (CloudTrail `lookup-events` could still recover this — not attempted, offered to user as an option, not pursued.)
  - Confidence without that literal field: **high, circumstantial convergence, not a quoted fact.** The ALB health-check config for platform-service (C4, confirmed) is tightly coupled to the app's `loadAvg > 0.7` self-check (`UnhealthyThreshold: 2` at 30s interval — 30-60s to kill). The observed pattern — repeated single/multi-task kills every 2-3 minutes for 46+ minutes — is exactly the signature that mechanism produces under sustained pressure, and it sits in the same window as the CPU spikes (C3) and the PediGrido outage (CSV). Ticket language: state the kill-loop pattern and its timing as confirmed fact (it's directly from ECS service events); state the health-check as the specific trigger as "consistent with," not "confirmed by stoppedReason."

## Ruled out

- Recent code change causing the platforms-service health-check behavior — predates this incident by over a year.
- The `:318`/`:253` task-def revision bump as the root cause — confirmed `cpu`/`memory`-only scale-up, a mitigation, not the trigger.
- The scale-up deployment's own task swap as evidence of a health-check kill — `stoppedReason` confirms it was a normal deployment-driven stop.

## Gap: platform-service's own trigger — mostly closed, not fully proven

The PediGrido-outage root cause (missing timeout, unbounded cron fan-out) is evidenced entirely from **concentrador-service's own PERF logs** — the CSV export is 100% `service: concentrador-service`. We do not have platform-service's own PERF/log data for this window.

platforms-service *does* reference PediGrido (`ConfirmarPedido` appears as a URL-path constant in `api/src/platforms/management/platform/thirdParty.js:22`, `performance.js:15`, `rapiboy.js:21` — the same endpoint concentrador was hammering, per the CSV's `v1/Grido/ConfirmarPedido` — 842 rows).

**Checked in source (2026-08-06):** `api/src/index.js:21` — `axios.defaults.timeout = 20000;` (20s), set once at process startup on the global/default axios instance. The actual PediGrido action handlers (`readyOrder`/`dispatchOrder`/`deliveryOrder`) are in `platforms/management/platform/rapiboy.js:388/440/499` (not `thirdParty.js` as first assumed — `thirdParty.js`'s `ConfirmarPedido`/`urlConfirmed` constant is a different, generic third-party path, not the one producing the `platform=PediGrido` PERF logs actually seen in the data). `rapiboy.js` imports the bare `axios` singleton and calls `axios.put(url, body, headers)` with no per-call `timeout` override, so in theory it inherits the 20s default. Note also: `headers` at each of these call sites is `{ 'Content-Type': 'application/json' }` passed directly as the axios config argument — not wrapped as `{ headers: {...} }` — a separate, likely-unrelated bug (the `Content-Type` header probably isn't actually being sent), flagged for completeness, not chased further.

**Corrected against real data (2026-08-06, second CSV `All-Messages-search-result(3).csv`, 51,158 rows, 100% `platforms-service`, covering 18:00 UTC 08-05 → 02:00 UTC 08-06):** the 20s timeout is **not strictly enforced** in practice. Of 8,420 `platform=PediGrido` PERF rows, 24 exceeded 20,000ms — max **34,353ms** — all with `status: 200` (succeeded, not aborted). So the source-code reading alone overstated the guarantee; something about how this call path is configured means the default timeout doesn't hard-cap it 100% of the time. Root mechanism for that gap not identified (possibly related to the malformed `headers` config above, not confirmed).

**Despite that correction, still a materially different and much smaller-scale situation than concentrador-service:** real max duration 34.3s (platform-service) vs 125-218s (concentrador), and only 24/8,420 calls (0.3%) exceeded 20s at all. No unbounded multi-minute hangs anywhere in this dataset.

**Window-specific evidence (closes most of the previously-open gap):** comparing latency **inside** the confirmed PediGrido-outage window (19:28-21:02 UTC) vs outside it: average duration is nearly flat (3,152ms vs 3,027ms), but the rate of severe (>20,000ms) calls is **~11x higher inside the window** — 12/680 (1.8%) vs 12/7,740 (0.16%). This is real, platform-service-owned evidence that the PediGrido degradation did reach platform-service's own calls during the same window, corroborating (not just timing-coincidental with) the shared cause — but at far smaller magnitude than concentrador's sustained, majority-of-calls impact. Does not by itself prove PediGrido was *the* driver of platform-service's CPU/kill-loop (only 12 severe calls in 94 minutes is a modest signal), but it's stronger than the purely-circumstantial timing overlap stated before.

## New finding (2026-08-06): existing CPU auto-scaling policy structurally could not have fired

platform-service already has a CPU-based target-tracking policy (`Smartfran-Platform-CPU-Policy`, target `ECSServiceAverageCPUUtilization` 60%, since 2020-10-20) plus a request-count policy (`Smart-Platform-Request-Policy`) — contrary to the initial assumption that no CPU rule existed. concentrador-service has **no** scalable target registered at all (confirmed via `describe-scalable-targets` returning only platform-service).

**Confirmed via `describe-alarm-history` (empty result) + `get-metric-statistics` for 2026-08-05 16:00-19:00 -03:00:** the existing alarm never transitioned state during the incident. Average CPUUtilization stayed under ~13% the entire window while Maximum spiked to 75.4% (16:40), 77.4% (16:55), 46.3% (17:00) — single-task spikes diluted by the 5-task fleet average, never remotely close to the 60% target-tracking threshold. This is a structural limitation, not a misconfiguration: `ECSServiceAverageCPUUtilization` is the only predefined CPU metric target-tracking supports for ECS — there's no "Maximum" predefined option.

**Also structural, not fixable by policy tuning:** ECS Application Auto Scaling can only ever change `DesiredCount` (task count/horizontal). It cannot resize a running task's cpu/memory (vertical) — that requires a new task-definition revision + redeploy, which is exactly the manual mitigation applied during the incident (and later reverted). No scaling policy could have automated that specific action.

**Proposed fix (pending user decision on exact thresholds):** additive step-scaling policy on platform-service, driven by a new CloudWatch alarm using `Statistic: Maximum` (not the target-tracking-only Average) on the same `CPUUtilization` metric — e.g. threshold ~80%, 2×60s periods, `ChangeInCapacity` +2 tasks, ~120s cooldown (fast enough to react within the observed 2-3 min kill cycle, vs. the existing policy's 600s scale-out cooldown). Leaves the two existing policies untouched. Not yet created — pending commands to be run by the user.

## Open items

- `GET /metrics/health-check` in platforms-service: dead memory-usage branch, no hysteresis beyond the ALB threshold, HTTP 400 instead of 503 for a capacity signal, unused `os.cpus()` call, per-request env re-parsing instead of `.asFloat()` — see conversation for full list. Candidate follow-up, not blocking this ticket.
- `checkOfflinePOSpedigrido` fix candidates: add a request timeout to `httpClient` (or per-call), add an overlap guard so the every-minute cron doesn't stack concurrent runs, and/or cap fan-out concurrency. Candidate remediation for the ticket's "Acciones propuestas."
- New CPU step-scaling policy for platform-service (see finding above) — design proposed, commands not yet run.

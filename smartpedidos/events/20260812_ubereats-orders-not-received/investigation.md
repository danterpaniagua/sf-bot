# Investigation — 20260812_ubereats-orders-not-received

**Status:** converged — mitigated (rollback), permanent fix still pending

**Ticket:** GITIN-1844

## Confirmed facts

- UberEats webhook entry point is `platforms-service`, routes `POST /uberEats/uber-notification/:country` and `POST /uberEats/uber-notification` (`api/src/routes/uberEats.js:33,63`), handled by `controller.uberNotification` (`api/src/controllers/uberEats.js:173`).
- The webhook handler validates `x-uber-signature` against an HMAC-SHA256 computed with a **secret hardcoded as a literal string** in source (`api/src/controllers/uberEats.js:183`), not read from `platform.credentials` or config/secrets manager. On mismatch it logs `[INTEGRATION/WARN] webhook_signature_mismatch platform=UberEats` and returns HTTP 401 — no order is queued.
- Accepted webhooks are pushed into an **in-process array** `ordenesUber` (`controllers/uberEats.js:18,206`) — not persisted to MongoDB or SQS at receipt time. A `node-cron` job (`*/5 * * * * *`, `controllers/uberEats.js:22-23`) drains this array every 5s, calling out to Uber's Order API (`GET /v1/delivery/order/:id`) with a Bearer token before the order is normalized and handed to `platform.validateNewOrders()`.
- Bearer tokens (`platform.tokenUber[country]`) come from a separate OAuth `client_credentials` login (`platform/uberEats.js:94-127`), refreshed by cron `0 0 1,10,20 * *` (5-field, so **3x/month**: 1st/10th/20th at 00:00) — last scheduled run 2026-08-10 00:00, ~2 days before this report.
- Orders stuck in `ordenesUber` for >24h are logged as `[ORDER/WARN] Missing UberEats delivery orderfail` and dropped (`controllers/uberEats.js:40-44`) — silent loss, no alert beyond the log line.
- Prior incident `events/20260805_concentrador-platforms-high-cpu-healthcheck/` shows platforms-service tasks were repeatedly killed by ALB health checks (self-reported unhealthy under CPU load) on 2026-08-05, fixed 2026-08-06 by decoupling the health check from `os.loadavg()` (now `GET /` + 404 matcher). Relevant here because `ordenesUber` is **not durable** — any task restart drops whatever orders are currently queued in memory, with no trace beyond a possible `webhook_received` log with no matching completion.

- User provided the last order that did come through: internal id 451603854, `oldId` (original Uber id) `443a2f09-6081-4ffe-8d00-2e8e6a9431d0`, store "Grido - Carmen", `branchId` 4426, `created_time` 2026-08-12T14:29:26-04:00 (≈18:29:26 UTC). Presence of `branchId`/`oldId` confirms it passed webhook receipt + signature validation + the id-swap step (`controllers/uberEats.js:87,117-118`) — integration was working at that timestamp.
- `db.logerrors` is not a reliable signal for platforms-service diagnostics: `api/src/utils/log.js:9-13,50-52` shows `mongoLogEnabled: false` by default / `consoleLogEnabled: true` — logs go to stdout → Event Hub → Graylog, not MongoDB. Consistent with prior events (`20260619_sqs-cola-de-mensajes`, `20260728_nuevo-analisis-costos`). The `ops-aws` skill's `db.logerrors` queries are stale against current architecture.

- Wider Graylog export (`All-Messages-search-result(4).csv`, 15,821 rows, 2026-08-12 13:07:40–21:22:26 UTC) gives the full timeline:
  - `webhook_received platform=UberEats` occurs steadily throughout the **entire** window (192 total, roughly 1-3/min, last one 21:12:28 UTC) — Uber → ALB → signature validation is healthy the whole time, including right now.
  - The crash (`[ORDER/ERROR] UberEats getOrders general error`, `ReferenceError: body is not defined`, `dist/controllers/uberEats.js:285:38`) **first appears at 15:43:05 UTC** and never stops — 15,334 occurrences total, climbing from ~120/10min (15:50-ish) to a steady ~600/10min (~1/sec) from 19:00 UTC onward. Rate climbing over ~3h is consistent with more platforms-service task replicas (each has its own in-memory `ordenesUber` array) independently getting a stuck head-of-queue order over time.
  - Downstream completions (`receiveOrder`/`readyOrder`/`branchRejectOrder` PERF entries — i.e. orders that actually got POS-confirmed) occur steadily from 14:22 through **18:45:41 UTC, then stop completely for ~2.5 hours**, with only 2 completions right at the tail (21:14:53, 21:22:26 — essentially "now", current UTC time is 21:27).
  - Current time check: `date -u` → 2026-08-12 21:27:13 UTC. **This is an active, ongoing incident**, not a resolved one — the export runs right up to the present moment.

## Current working theory (root cause, high confidence)

`controllers/uberEats.js`'s per-order try/catch inside `processUberQueue()` has a JS scoping bug: `const body = element` is declared inside the `try` block, but the `catch` block references `body.meta?.resource_id` — `body` is out of scope there, so any per-order processing error triggers a **second** `ReferenceError: body is not defined` instead of logging the real error. That ReferenceError escapes the entire for-loop (a throw inside a catch isn't caught by the same try/catch), aborting the batch before the end-of-cycle `ordenesUber = ordenesUber.filter(...)` cleanup runs. The failing order — and everything queued behind it in that process's in-memory array — stays stuck and is retried (and re-crashes) every ~5s cron tick, forever, until either a task restart clears the in-memory array or the order ages past the 24h `Missing UberEats delivery orderfail` cutoff and gets dropped.

Webhook delivery, signature validation, and OAuth token refresh are all confirmed healthy throughout — this is purely an internal processing defect. Severity escalated from "some orders degraded" (15:43-18:45 UTC, partial completions still occurring) to "effectively total blockage" (18:45-21:2x UTC, near-zero completions despite continuous webhook arrival) as more task replicas accumulated their own stuck order.

## Ruled out

- Hardcoded webhook-signature secret being wrong from the start, or Uber rotating it mid-session — ruled out; `webhook_received` fires continuously through 21:12 UTC with no `webhook_signature_mismatch` entries in either export.
- `db.logerrors` emptiness as evidence of an outage — ruled out; that collection isn't written to for platforms-service regardless of order flow (see Confirmed facts above).
- Devs' "it's a log problem" claim — ruled out as an explanation for missing orders; it correctly identified that `db.logerrors` is the wrong data source, but the actual order flow genuinely is broken (Graylog evidence above), not just under-logged.
- OAuth token expiry/`uber_login failed` — no such entries in either export; not implicated.

## Regression source

Introduced by commit `81c7501` (authored 2026-08-11 15:55:44 -03:00 / 18:55:44 UTC), "feat: enhance webhook event handling for UberEats integration" — added `order_id: body.meta?.resource_id` to the catch block where `body` is out of scope. Previous commit touching this file: `0e02e00` (2026-07-13), a month untouched before that. A later commit `7b9dce4` (2026-08-12 13:02:44 UTC) also touched this file but only reordered `uberNotification`'s try block — unrelated to the bug, doesn't need to be reverted for the fix to hold, but was reverted along with everything else by the task-definition rollback below.

**Deploy-to-first-crash gap:** per user, actual deployment to production happened the morning of 2026-08-12 (exact timestamp not yet confirmed) — not at commit-authoring time (2026-08-11 afternoon). The bug then sat live for a few hours before the first per-order error actually hit the broken catch block at 12:43 -03:00 / 15:43 UTC — consistent with normal order volume needing time to produce whatever condition triggers the still-unknown original per-order failure.

## Mitigation applied

**2026-08-12, user-confirmed:** platforms-service ECS service rolled back to the task definition revision predating the `81c7501` deploy. **User reports order flow working again** after the rollback. This is a mitigation, not a permanent fix — the underlying scoping bug still exists in the current `main`/`develop` branch tip; if `81c7501` (or an equivalent unfixed version) is redeployed without the fix below, the same failure will recur.

**Confirmed via ECS event history cross-referenced with Graylog:** rollback deployment started 2026-08-12 18:11:21 -03:00 (21:11:21 UTC) — 4 new tasks started, old task drained/stopped by 18:12:30 -03:00 (21:12:30 UTC). The two lone successful order completions found at the tail of the wider Graylog export (21:14:53 UTC and 21:22:26 UTC) land 3 and 11 minutes after this rollback finished — direct timestamp confirmation that the rollback caused the recovery, not coincidental timing.

**Full deploy timeline confirmed** via wider `describe-services` events slice (100 entries):

| Time (UTC) | Time (-03:00) | Event |
|---|---|---|
| 2026-08-11 18:55:44 | 15:55:44 | Commit `81c7501` authored |
| 2026-08-12 13:07:13–13:08:53 | 10:07:13–10:08:53 | Buggy revision deployed to production — 5 tasks replaced (the "morning deploy") |
| 2026-08-12 15:43:05 | 12:43:05 | First crash — ~2h35m after deploy |
| 2026-08-12 18:45:41 | 15:45:41 | Last completion before total blockage |
| 2026-08-12 21:11:00–21:12:39 | 18:11:00–18:12:39 | Rollback deployed — 5 tasks replaced with pre-bug revision |
| 2026-08-12 21:14:53 | 18:14:53 | First successful completion post-rollback |

`desiredCount: 5` for platform-service confirmed (1+4 task pattern in every deploy in the event history) — matches the crash-rate plateau of ~600/10min (~1 crash/replica/5s cron tick) once all five replicas had independently accumulated a stuck order. Root cause chain is now fully closed: code defect (evidence: git blame + Graylog stack trace) → deploy timestamp → crash onset → escalation to total blockage → rollback → recovery, all cross-confirmed by independent sources (git history, ECS deployment events, Graylog log export).

## Scope confirmed: UberEats-only, other platforms unaffected

Verified empirically (not just architecturally) via a broader Graylog export (`All-Messages-search-result(6).csv`, 51,057 rows, 09:54–21:54 UTC, `SP_Platform` stream, `NOT message:UberEats AND NOT message:heartbeat`):

- Rappi `getOrders` polling: flat, unbroken ~200/10min the entire day, zero interruption during 15:43–21:11 UTC.
- PedidosYa `receiveOrder`/`readyOrder`: steady growth all day (normal volume ramp), no drop or gap during the incident window.
- MercadoPago, PediGrido, ThirdParty: all show continuous high-volume activity across the same window.

Confirms the earlier architectural reasoning: the bug is isolated to `controllers/uberEats.js`'s dedicated in-memory queue + cron consumer, a pattern unique to Uber Eats among the platform integrations (other platforms process each webhook synchronously in the request handler, e.g. `peya.js`'s `saveOrder`) — no shared state or code path with other platforms, so the crash-looping never touched them.

**Tangential, out of scope for this ticket** (noted per event-scope-isolation convention, not investigated further here): the same export shows 4,050 `connect ECONNREFUSED 127.0.0.1:3088` and 4,098 `Unhandled Rejection` entries, plus 2,880 `Platform Auth Error: TOKEN_MISSING GET /api/branches/news` (matches a pattern already known from `2026-06-19_sqs-cola-de-mensajes`). None of these correlate with the UberEats incident window specifically — flag separately if worth its own investigation.

## Open questions / next steps

1. **(Dev, urgent — still pending)** Fix the `body` scoping bug before the next deploy — reference `element` (or move `const body` outside the try block) in the catch handler at `controllers/uberEats.js` (~line 159 in source, line 285 in compiled `dist/`). Rollback does not fix the source branch.
2. **(Dev, follow-up)** Even with the scoping bug fixed, a single failing order can still abort the whole batch loop and block everything queued behind it that cycle — the per-order try/catch needs to actually contain the failure (log it, `continue`) rather than let any secondary error escape. This is the deeper design flaw the scoping bug was masking.
3. Determine what caused the *original* per-order error each time (now masked) — only recoverable once the scoping bug fix ships and real errors start appearing in logs again. Without this, whatever first triggered a stuck order is still unknown and could still occur even after the scoping fix (it would just fail loudly/correctly instead of jamming the queue).
4. Confirm current task count for platforms-service (`aws ecs describe-services`) to correlate against the crash-rate escalation seen pre-rollback (rate climbing ~15:50-19:00 UTC) — not required for resolution, background context for the ticket.
5. **(Dev, architecture proposal — longer-term, not required for this ticket's closure)** Replace the in-memory `ordenesUber` array + 5s cron consumer with a dedicated SQS queue for UberEats webhook intake, matching the SQS pattern `concentrador-service` already uses downstream and this project's existing DLQ pattern (`MainDeadLetter.fifo`/`DeadLetter.fifo`). Would fix several structural issues at once: (a) durability — a task restart no longer silently drops queued orders; (b) poison-pill isolation — visibility-timeout + redrive-policy/`maxReceiveCount` moves a permanently-failing order to a DLQ automatically instead of blocking every order behind it forever; (c) removes the 5x-replica duplication seen in this incident (each of the 5 replicas independently got its own stuck order) — one shared external queue means a bad message only needs to fail `maxReceiveCount` times total, not once per replica; (d) visible failure — DLQ depth is alertable, replacing the current silent 24h-then-drop log line. Does not replace items 1-2 above (a redesigned consumer still needs correct per-message error handling) and doesn't address the still-unknown original per-order failure (item 3).

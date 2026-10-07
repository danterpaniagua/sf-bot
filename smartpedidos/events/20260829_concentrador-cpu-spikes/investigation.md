# Investigation — 20260829_concentrador-cpu-spikes

**Status:** ticket closed (2026-08-31) — but the Dev code-fix risk below is explicitly OPEN, not resolved by the closure. Tracked here for continuity even though `ops.md` is closed.

**Capacity at closure** (`11_concentrador_taskdef_at_close.json`, 2026-08-29): `concentrador-service-production-task:322`, `cpu:1024`/`memory:2048`, `desired:1`/`running:1` — this was the baseline reverted to `256/512` on the scheduled 08-31 deescalation (below).

**Closure caveat (2026-08-29, user):** ticket closed with capacity mitigation in place. Capacity bump is temporary — deescalation scheduled for Monday 2026-08-31, same pattern as GITIN-1783's 08-06 revert. Root-cause code fixes (concurrency cap on `enviarEstadoPedidosYa`, `httpClient` timeout) are NOT implemented and are not part of this closure — tracked as open Dev action items in `ops.md`. If those fixes aren't in by 08-31, deescalating removes the only mitigation currently in place, same risk GITIN-1783 flagged explicitly when it was reverted without its own code fix.

**Update (2026-08-31): deescalation applied, ticket closed with the risk explicitly open (user decision).** `concentrador-service-production-task:323` registered (`cpu:256`/`memory:512`, matching the pre-mitigation `:321` spec exactly) and deployed — confirmed live (`desired:1`/`running:1`). Escalation email sent to Dev beforehand (`email_dev.md`) flagging the risk of deescalating without the code fix. **Whether the Dev fix (items 1-3) landed before this deescalation is still not confirmed.** The ticket (`ops.md`) is now closed regardless — this was a deliberate call, not an oversight — but the underlying exposure is not resolved: if the fix isn't in, concentrador-service is exposed again to the same unbounded fan-out pattern with no mitigation, at the next PedidosYa `checkIns` firing. This file stays open on that point for whoever picks it up next; don't treat the ticket's closure as evidence the risk was addressed.

**Jira:** [GITIN-1964](https://smartit-ar.atlassian.net/browse/GITIN-1964)

## Confirmed facts

- Ticket reports "several CPU spikes" on concentrador-service, detected via Grafana (user, 2026-08-29). Window: ~10:00 -03:00 through at least 18:15 -03:00, 2026-08-29.
- **C1 — ECS service-event history** (`1_ecs_service_events.json`, both services, history back to 2026-08-13): concentrador-service had **no stop/kill events** in this window — only routine ~6h steady-state pings and a clean single-task swap every 1-2 days (~03:31 -03:00, routine deploy cadence, unrelated). platform-service shows a heavy kill-loop, but on **2026-08-28 20:49–21:25 -03:00** — the evening before this ticket's window; treated as a separate, earlier event, not part of GITIN-1964.
- **C2 — CloudWatch CPUUtilization, concentrador-service** (`2a_cpu_concentrador.json`, 5-min buckets, 10:00-18:20 -03:00): repeated Maximum spikes to 99-100% at 10:00, 10:30, 11:00, 11:15, 11:30, 12:00, 12:15, 12:30, 13:15, 17:00, 18:15 -03:00. Average stays low (single digits to ~30%) — bursty, not sustained.
- **C2b — CloudWatch CPUUtilization, platform-service** (`2b_cpu_platform.json`, same window): flat throughout, Maximum never exceeds ~28%. **Not implicated** — this is a concentrador-only event, unlike GITIN-1783.
- **C3/C4 — concentrador-service task def** (`3_concentrador_taskdef.json`, `5_taskdef_321_capacity.json`): `:321` (pre-mitigation), `cpu:256`/`memory:512`, `desired:1`/`running:1` — single task, no redundancy, unchanged since the GITIN-1783 revert (08-06). No capacity-scaling policy exists on concentrador-service.
- **C5 — ALB health-check config** (`6_tg_healthcheck_config.json`): `Path:/`, `Timeout:120s`, `Interval:300s`, `Unhealthy:2`, `Matcher:404` — lenient, explains zero ECS kills despite CPU hitting 100%.

## Root cause (converged)

**Graylog export analyzed:** `7_graylog_perf_export.csv` (saved in this event folder), 55,860 rows, 100% `concentrador-service`/PERF, window 2026-08-29 12:00–23:10 UTC (09:00–20:10 -03:00).

- **C6 — per-minute volume:** sharp bursts (300–2,600+ log lines in a single minute) at 13:01, 13:31, 14:01, 14:16, 14:31, 15:01, 15:16, 15:31, 16:16, 20:01, 20:16, 21:16 UTC — i.e. **10:01, 10:31, 11:01, 11:16, 11:31, 12:01, 12:16, 12:31, 13:16, 17:01, 17:16, 18:16 -03:00**, matching essentially every CloudWatch CPU-spike timestamp (C2), 1 minute past the mark each time.
- **C7 — burst composition** (checked 13:01–13:02 and 20:01 UTC in detail): dominated by calls to `https://integration-middleware.us.restaurant-partners.com/v2/chains/LATAMSMARTFRAN0001/remoteVendors/<branch>/availability` (~1,100 `GET` + 200-1,000 `PUT` per burst, one per branch remote-vendor ID). This is **PedidosYa's** infrastructure (`peyaBaseUrl` ← `PedidosYa.credentials.data.baseUrl`, `branch.js:320`), not PediGrido — PediGrido (`v1/locals/status`) contributes only 4-17 calls per burst, negligible this time.
- **C8 — call latency inside the burst** (13:01-13:02, `remoteVendors/.../availability` only, n=1,794): median **36.5s**, mean 28.7s, 94% over 10s, 53% over 30s, max 46.1s — and all sampled slow calls returned `status:200`. Not remote failures, just extreme latency: **self-inflicted congestion, not third-party degradation** (unlike GITIN-1783, where PediGrido itself was genuinely down/524ing).

**Mechanism** (confirmed in source, `develop@77c1061f`): `sincroCheckIns()` (`branch.js:1858-1899`) dynamically registers one `cron.schedule` per configured `platform.checkIns` entry (`{hour, minute}`, per platform per country). For PedidosYa (`internalCode: 1`) this fires `enviarEstadoPedidosYa(country)` (`branch.js:2474`), which queries **every** active PedidosYa branch in the country (branches-to-open + branches-to-close, two queries, `branch.js:2480-2492`), then fans out with an **unbounded** `.map()` — no concurrency cap, no batching — issuing a sequential `GET` then `PUT` per branch through the same shared, un-timed `httpClient` (`utils/httpClient.js`, same defect as GITIN-1783) against `integration-middleware.us.restaurant-partners.com`. With ~1,100+ active branches, every `checkIns` firing launches ~1,100+ concurrent GET/PUT round-trips at once — the 10-46s latencies are consistent with self-congestion (event loop / outbound connection pool / receiving-side throttling under that concurrency), not an outage on PedidosYa's side.

**This confirms the user's cron hypothesis** — the trigger is a cron, but specifically `sincroCheckIns`'s PedidosYa `checkIns`-driven fan-out over the full branch fleet, not the every-minute `checkOfflinePOSpedigrido` cron from GITIN-1783.

## Mitigation applied (2026-08-29)

cpu/memory bump on concentrador-service's task definition, `256/512` → `1024 CPU/2048 MB`, same as GITIN-1783's mitigation. Registered manually (not via the scripted `register-task-definition` command offered) as `concentrador-service-production-task:322`. Service updated to `:322` — **deployment confirmed complete** (AWS console, 2026-08-29T21:37:43Z): old task drained/stopped, 1 new task started successfully, deployment status "Complete."

**Post-deploy verification — inconclusive so far** (`10_cpu_concentrador_post_mitigation.json`, 18:37–20:22 -03:00): CPU stayed low (Maximum never exceeded ~28%), but this window **does not contain any of PedidosYa's scheduled `checkIns` times** (10:01, 10:31, 11:01, 11:31, 12:01, 17:01, 23:01 -03:00, per hardcoded schedule found in source) — so low CPU here just means the implicated cron didn't fire, not that the mitigation held against it. One data point: a mild bump to 27.6% Maximum at 19:07 -03:00 lines up with MercadoPago's `checkIns` time (19:11 -03:00) — much lower than pre-mitigation spikes, but MercadoPago's branch count/handler wasn't confirmed to share PedidosYa's exact fan-out pattern, so this is suggestive, not conclusive for the actual root-cause defect. **Real test is the next PedidosYa firing at 23:01 -03:00 (02:01 UTC) today** — not yet checked.

This addresses symptom severity, not the root cause: the real fix is bounding `enviarEstadoPedidosYa`'s fan-out (batching/concurrency cap) and adding a request timeout to `httpClient`. Same caveat as GITIN-1783: capacity alone did not fix that incident's underlying cause; state as an open risk in the ticket, not as resolved.

## When this was introduced (checked against `develop@d5e57110`, pulled 2026-08-29 — no changes to the implicated code vs. the earlier `77c1061f` check, only unrelated Rappi-webhook commits in between)

- The **dynamic `checkIns` scheduling mechanism** (`sincroCheckIns`/`checkforcedCheckins`, DB-configurable `platform.checkIns`) was introduced in commit `59faec4e`, 2026-07-07 ("feat: checkin").
- That commit's diff shows it **replaced an already-existing hardcoded schedule**, not introduced new trigger times — the removed literal array (`pedidosYaTimes`) contained exactly: `{10:01, 10:31, 11:01, 11:31, 12:01, 17:01, 23:01}` (local time, pre-`toUTC`) — matching today's spike timestamps almost exactly. `59faec4e` only changed *how* the schedule is configured (DB-editable vs. hardcoded) and added the `checkforcedCheckins()` poller (`*/15 * * * * *`); it did not touch `enviarEstadoPedidosYa`'s fan-out logic.
- **The actual defect — unbounded `.map()` fan-out over every branch, no concurrency cap, through an un-timed `httpClient`** — predates `59faec4e`. `enviarEstadoPedidosYa` first appears under that name in commit `2e1b7858`, 2025-05-23.
- **Working inference (not confirmed against historical branch-count data):** this is plausibly not a recent regression at all — the schedule and the unbounded-fan-out pattern are both >1 year old. What's more likely to have changed is the *active PedidosYa branch count* growing large enough (~1,100+ now) that the existing unbounded fan-out finally saturates CPU/connections. Branch-count growth over time not independently verified in this session.

## Ruled out

- Repeat of the platform-service side of GITIN-1783 — CPU flat throughout this window (C2b); concentrador-only event.
- ECS health-check kill-loop as a mechanism — zero stop events despite CPU hitting 100% Maximum (C1), consistent with the lenient health check (C5).
- A repeat of GITIN-1783's PediGrido-outage root cause — PediGrido calls are a negligible fraction of burst volume this time (C7); the 08-05 mechanism (sustained 90-min degradation, unbounded `checkOfflinePOSpedigrido`) does not fit today's short, evenly-spaced 15-min-interval bursts.
- Branch open/close-hour clustering (`cronHorariosPediGrido`/`openClosedBranchesGrido`, PediGrido-specific) — considered as a working theory before the Graylog export was available; superseded once the export showed the dominant volume is PedidosYa's `sincroCheckIns`/`enviarEstadoPedidosYa`, not PediGrido at all.

## Open questions / next steps

- Confirm the `:322` deployment reaches steady state, then pull post-mitigation CloudWatch CPUUtilization to see whether Maximum spikes stop (capacity alone may mask but not eliminate the burst pattern, since the fan-out itself is unchanged).
- Confirm `platform.checkIns` config for PedidosYa (`internalCode: 1`) to verify the exact scheduled times match the observed :01/:16/:31/:46 burst pattern precisely (not yet queried directly — inferred from log timing alone so far).
- Dev action items to propose for the ticket: (1) add a per-call or client-default timeout to `httpClient.js`; (2) cap concurrency / batch `enviarEstadoPedidosYa`'s branch fan-out instead of firing all ~1,100+ branches at once; (3) same for the equivalent Rappi/UberEats/MercadoPago `checkIns` handlers (`enviarEstadoRappi`, `sendStatusUberEats`, `sendStateMercadoPago`) if they share the same unbounded-fan-out pattern — not yet checked.

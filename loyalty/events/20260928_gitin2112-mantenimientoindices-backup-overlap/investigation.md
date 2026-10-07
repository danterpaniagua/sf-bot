# Investigation — 20260928_gitin2112-mantenimientoindices-backup-overlap

**Jira ticket:** [GITIN-2112](https://smartit-ar.atlassian.net/browse/GITIN-2112)

**Status:** in progress — mechanism strongly suspected, not fully confirmed. Started as an ad-hoc check of loyalty backup/index-maintenance timing over the weekend (unrelated to `smartpedidos/events/20260925_gitin2110-platforms-service-cpu-queue-age/` — different system, no evidence of any cross-system link).

## Timezone correction (important, applies to everything below)

`loyalty/CLAUDE.md`: SQL Server runs on **GMT (UTC+0)**; user's local timezone is **ART (UTC-3)**. All raw query timestamps below are GMT as returned by the server — every "real" ART time in this file is that value minus 3 hours. Initial messages in this session incorrectly treated these as already-ART before this was caught.

## Confirmed facts

- `PNSSRL_MantenimientoIndices` (SQL Agent job, Schedule 23) is a full-database sweep of `SmartFran.Solution.SmartLoyalty` — iterates ~200+ tables, checking fragmentation and REBUILD/REORGANIZE/SKIP per index, then `UPDATE STATISTICS`.
- **Schedule 23 confirmed via `sysschedules`**: `freq_type=8` (weekly), `freq_interval=86` = 64(Sat)+16(Thu)+4(Tue)+2(Mon) → **Monday/Tuesday/Thursday/Saturday only**, `active_start_time=090000` (09:00 GMT = **06:00 ART**). Friday/Sunday absence in the weekend data is by design, not a missed/failed run.
- **2026-09-26 (Sat) run: FAILED.** Started 09:00:00 GMT (06:00 ART), failed after 15m14s (~09:15:14 GMT / ~06:15:14 ART), stopped at Step 1. `data/sysjobhistory_outcome_20260925_20260928.txt`, `data/sysjobhistory_steps_and_schedule_20260926.txt`.
- **2026-09-28 (Mon) run: succeeded**, full 3 steps, took 2h14m37s (09:00→~11:14 GMT / 06:00→~08:14 ART) — this is closer to the multi-hour durations documented in prior events (Sept 14/15), confirming Saturday's ~15min was an abnormal early termination, not a genuinely light/fast sweep.
- Step 1's own `sysjobhistory.message` for the failed run is **truncated by SQL Server Agent's own storage limit** (~3200 bytes) — ends mid-table-listing with just "The step failed.", no error number/exception text. `data/sysjobhistory_steps_and_schedule_20260926.txt`.
- **`xp_readerrorlog` for the failure window (09:00-09:20 GMT / 06:00-06:20 ART) shows two `BackupToUrl` operations against the same database** (`SmartFran.Solution.SmartLoyalty`) starting during the sweep: one at job start (09:00:01 GMT / 06:00:01 ART, spid102) and a second **mid-sweep** (09:10:00.790 GMT / 06:10:00.790 ART, spid89). Six seconds after the second backup started, the error log logged **"Long Sync IO: Scheduler 14 had 1 Sync IOs in nonpreemptive mode longer than 1000 ms"** (09:10:07.010 GMT / 06:10:07.010 ART) — five minutes before the job's eventual failure. `data/xp_readerrorlog_20260926_0900_0920.txt`.
- `PNSSRL_DetallesEjecucionTablasModulos` for the whole 3-day window contains only the truncated Saturday burst (09:00:04–09:13:39 GMT, 150 rows) — consistent with the job dying partway through the `Mbr` schema tables. `data/detalles_ejecucion_weekend_20260925_20260928.txt`.

## Current working theory

**Weakened by comparative data — no longer the leading theory as originally framed.** Root cause remains unconfirmed. See "Ruled out" for what comparative data against Monday's successful run disproved.

## Real data, 2026-09-28 — log backup sizes, full weekend + Monday's successful run

`msdb.dbo.backupset` confirms **`SmartFran.Solution.SmartLoyalty` takes a transaction log backup every ~10 minutes, continuously, all day every day** — this is structural (FULL recovery model), not something that can be rescheduled around without affecting RPO. One `D` (full) backup also runs daily around 09:00 GMT (554s, confirmed on 2026-09-25) — no full/diff backup ran on the Saturday failure morning, only routine log backups. `data/backupset_friday_saturday_PARTIAL_20260925_20260926.txt` (see "Evidence gap" note below — this is a partial extract, not the complete original result set).

**Saturday's 09:10 GMT log backup (7.56 GB — the one matching the "Long Sync IO" warning) is NOT anomalously large compared to Monday's successful run.** Monday's log backups during the same job window grew far larger without any failure: 15.4 GB (10:20 GMT), 9.87 GB (10:30), 9.54 GB (11:00), 8.38 GB (11:10) — all bigger than Saturday's 7.56 GB. This directly weakens "the job's own heavy logging inflates its downstream log backup, and that contention kills it" as a sufficient explanation — Monday had equal-or-worse log volume throughout its run and succeeded.

**Not yet checked:** whether Monday's run also produced a "Long Sync IO" (or similar) warning in the error log without failing — would confirm whether that warning is even diagnostic of anything job-threatening, or just routine noise under load. Query given to user, not yet run.

## Ruled out

- **Any connection to `smartpedidos` GITIN-2110** (SmartPedidos queue-age spikes) — after the timezone correction, this failure (06:00-06:15 ART Saturday) doesn't overlap any of GITIN-2110's spike windows (all evening/night ART). Different systems, no shared infrastructure identified.
- **"Job just didn't run Fri/Sun" as an anomaly** — confirmed by design via `sysschedules` (Mon/Tue/Thu/Sat only).
- **"Large log backup during the sweep causes/correlates with failure"** — Saturday's 09:10 GMT log backup (7.56 GB, matching the "Long Sync IO" warning) is not actually anomalous: Monday's successful run produced multiple larger log backups during its own window (15.4 GB, 9.87 GB, 9.54 GB, 8.38 GB) with no failure. `data/backupset_monday_20260928_run_window.txt` vs. `data/backupset_friday_saturday_PARTIAL_20260925_20260926.txt`. Large log volume during this job is evidently normal, not a failure trigger on its own.
- **"`PNSSRL_MantenimientoIndices_CustomerPointsLog` overlapping the main sweep causes/correlates with failure"** — this companion job (GITIN-2061, partition-scoped `IX_CustomerId` REBUILD on `Sml.CustomerPointsLog`) started at 09:15:00 GMT on **both** Saturday and Monday (same schedule, fires independently). On Saturday it started 14 seconds before the main job's failure (09:15:14). But on Monday it ran 49m2s (09:15:00-10:04:02 GMT, `run_duration=4902` is `HHMMSS`, not raw seconds — corrected from an earlier misread of "81.7 minutes"), entirely inside the main job's 09:00-11:14 window, with no failure — far longer overlap than Saturday's ~14-second window before the main job died. `data/sysjobhistory_allJobs_saturday_20260926_0830_0920.txt` vs. `data/sysjobhistory_allJobs_monday_20260928_0830_0920.txt`. This overlap is routine (both jobs share the Mon/Tue/Thu/Sat schedule) and evidently tolerated most of the time.

**Both concrete contention candidates tested against Monday's successful run and neither holds up as sufficient.** Monday had the same or more severe version of each condition (bigger log backups, longer companion-job overlap) without failing. Saturday's failure increasingly looks like a genuinely transient, one-off event rather than a reproducible interaction between known scheduled jobs — root cause may not be fully identifiable from historical data alone without catching it live next time.
- **"'Long Sync IO' warning is diagnostic of the failure"** — Monday's successful run logged three of the same warnings (09:50:04 GMT, Schedulers 15/9/7) with no impact. Confirms this is routine background noise under load on this server, not predictive of anything job-threatening. `data/xp_readerrorlog_monday_20260928_0900_1120.txt`.
- **"DBCC CHECKDB (`PNSSRL_CapturaCheckDB`) is a factor"** — discovered only via the Monday error-log check (missed entirely by the earlier windowed job-overlap query, since CHECKDB started at 07:00 GMT, outside that window, while still running through 10:02:50). Confirmed via `sysjobhistory`: **ran only on Monday (07:00:00-10:02:50 GMT, 3h2m50s, succeeded), no row at all for Saturday** — not scheduled that day. This means Monday had strictly *more* heavy concurrent load than Saturday (CHECKDB + bigger log backups + same companion-job overlap) and still succeeded, while Saturday — with less background activity — failed. No "more load correlates with failure" pattern is visible in this data; if anything it trends the opposite direction, reinforcing the transient-event read rather than any load-based theory.

## Status: converged — no reproducible root cause found; retry mitigation is the practical response

Three independent contention theories (log backup size, companion-job overlap, CHECKDB/general background load) were each tested against a direct day-over-day comparison and none survived. Saturday's failure is treated as an unexplained transient event. The applied retry-attempts mitigation (see below) is the appropriate response to that class of event — no further root-cause line of inquiry identified without catching a live recurrence.

## Evidence gap (process note, not a finding)

The original full `msdb.dbo.backupset` query result (515 rows, 2026-09-25 00:00 - 2026-09-28 12:00 GMT) was read and grepped in-session but **not persisted to this event's `data/` before the user re-saved a follow-up query's output to the same local filename (`q1.txt`), overwriting it.** Only the specific rows already quoted in this file survived (see `data/backupset_friday_saturday_PARTIAL_20260925_20260926.txt` and its own caveat). If the complete dataset is needed again, the original query is in `scripts.sql` — will need to be re-run.

## Mitigation applied, 2026-09-28

**Retry added to Step 1 of `PNSSRL_MantenimientoIndices`** (`sp_update_jobstep @retry_attempts=2, @retry_interval=5`) — a safety net, not a root-cause fix: prevents one transient I/O stall from failing the entire multi-hour sweep outright, same failure mode as 2026-09-26. **Applied and independently verified** via `sysjobsteps` read-back (not just trusting "Commands completed successfully" — see GITIN-2061 precedent for why that alone isn't sufficient): `retry_attempts=2, retry_interval=5` confirmed set on `step_id=1`. Does not address the suspected `BackupToUrl` contention itself — see below.

## Real data, 2026-09-29 (Tue) — first scheduled run since mitigation, succeeded cleanly

`data/sysjobhistory_tuesday_20260929.txt`. All 3 steps succeeded, `retries_attempted=0` on every step — **the retry mitigation was not needed today**, so it remains unverified whether it would actually help on a real recurrence (no transient failure occurred to test it against). Not a confirmation the mitigation works, only that today's run didn't need it.

**Step 1 (index sweep) took 37m22s (09:00:00–09:37:22 GMT / 06:00:00–06:37:22 ART)** — notably faster than both prior runs (Saturday's ~15m14s *failed* run, Monday's 2h14m37s successful run). Duration varies a lot run-to-run even among successful ones (Monday 2h14m37s vs. today 37m22s), which is itself worth noting: duration alone isn't a reliable health signal for this job, consistent with the "no reproducible root cause" conclusion already reached — a short run today doesn't mean lighter load, and a long run on Monday didn't mean anything was wrong.

**New structural fact, not previously documented:** Step 2 of `PNSSRL_MantenimientoIndices` itself **starts `Operaciones_MaintenancePlan_Backups.Backup_Log`** (`Job 'Operaciones_MaintenancePlan_Backups.Backup_Log' started successfully`, Step 2, immediately after Step 1 completes) — Step 3 then also succeeds instantly. This means the job is *designed* to trigger a log backup right after its own index sweep, on top of the independent every-~10-minute log backup schedule already confirmed running throughout the day. This is a different mechanism than the original "two unrelated jobs happen to overlap" framing — worth folding into root-cause thinking if this line of investigation reopens, though it doesn't change the "no reproducible cause found yet" conclusion on its own (Step 2 fires *after* Step 1 ends, so it doesn't explain Saturday's mid-Step-1 failure at 09:10 GMT).

## Open questions / next steps

- ~~Backup type/duration/frequency~~ — resolved. Confirmed log backups run continuously (~every 10 min) plus a daily full/diff; separately, `Operaciones_MaintenancePlan_Backups.Backup_FULL` runs Sun/Wed/Fri 09:00 UTC, 8-10 min each (see `ops.md`'s full OK/NOK history table, 2026-09-29).
- ~~Confirm whether the job step has a configured retry~~ — resolved. `retry_attempts=2, retry_interval=5` applied to Step 1 on 2026-09-28, verified against `sysjobsteps` directly (not just trusting "Commands completed successfully"). First scheduled run since (Tue 2026-09-29) succeeded without needing the retry — confirms no regression, doesn't yet confirm the retry actually works against a real recurrence, since none has happened since it was added.
- **Still open**: the full (non-truncated) error/exception behind "The step failed." — would need an Extended Events session active ahead of a future failure, or catching one live. No further Saturday/failure recurrence observed as of 2026-09-29 (ticket closed in `ops.md` without one).
- **Still open**: whether the backup schedule and `PNSSRL_MantenimientoIndices`'s schedule are independently owned by different teams — not pursued further; became less urgent once the three-hypothesis contention theory was ruled out and the schedule itself was already coordinated as part of `loyalty/events/20260922_gitin2060-mantenimientoindices-reschedule/`.

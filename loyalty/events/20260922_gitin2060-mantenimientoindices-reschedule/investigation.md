# Investigation: Reschedule PNSSRL_MantenimientoIndices (06:15 UTC → 08:00 UTC)

**Jira:** [GITIN-2060](https://smartit-ar.atlassian.net/browse/GITIN-2060)

## Status

**Resolved and fully extended (2026-09-22).** All three components of the final "third iteration" schedule are applied and verified: `Backup_FULL` (Sun/Wed/Fri 09:00 UTC), index maintenance (Mon/Tue/Thu/Sat 09:00/09:15 UTC), `Etl CustomerPointsLog` (daily 05:00 UTC, moved from 07:25 UTC via `Sch.TimeTable.FrecuencySubDayInterval`, not Windows Task Scheduler as originally assumed — see "Locating the Etl.CustomerPointsLog trigger mechanism" below). `sp_update_schedule @schedule_id = 23, @active_start_time = 080000` executed 2026-09-22 against `SFCG-DB01`/`msdb`, verified in the same session (`data/schedule_verification_20260922.txt`): `active_start_time = 80000` (08:00:00 UTC), `enabled = 1`, schedule name and `freq_type`/`freq_interval` unchanged (still daily) at that point. The 08:00 UTC target, the exact command, and every caveat were fully derived under GITIN-1981 (`events/20260901_pnssrl_mantenimientoindices_review/`) and re-confirmed as the standing fix across two subsequent recurrences (GITIN-2036/`events/20260914_taskoperator_mktcampaign537_errors/`, and a third on 2026-09-21, GITIN-2076/`events/20260921_customerpointslog-blocking/`).

**Same-day follow-on design changes (two iterations, 2026-09-22)**:

1. First: user decided the 08:00 UTC placement — which only worked by assuming `Backup_FULL` (weekly Sun/Mon/Wed, 06:00 UTC) finishes within ~2h, never actually confirmed — wasn't good enough; wanted index maintenance to not run at all on `Backup_FULL` days, not just scheduled tightly after. Re-verified `Backup_FULL`'s schedule directly rather than trusting the old GITIN-1981 record (`data/backup_full_schedule_reverified_20260922.txt`): confirmed unchanged, `freq_type=8, freq_interval=11` (Sun+Mon+Wed), `06:00 UTC`. Both index jobs changed to weekly `freq_interval=116` (Tue+Thu+Fri+Sat, the complement).

2. Second: user separately flagged `Backup_FULL`'s own Sun+Mon+Wed pattern as "weird" (two of its three days back-to-back). Proposed and confirmed **`Backup_FULL` itself moves to Mon/Wed/Fri** (evenly spaced, gaps of 2/2/3 days, no back-to-back days at all) — `schedule_id=18`, `freq_interval=42`. Both index jobs re-derived as the new exact complement, `freq_interval=85` (Sun/Tue/Thu/Sat). A briefly-considered intermediate pick (`Backup_FULL` → Sun/Wed/Sat, `freq_interval=73`) was rejected — same back-to-back clustering problem, just relocated from Sun/Mon to Sat/Sun. **Final state, all verified**: `data/final_weekly_schedule_20260922.txt`.

**Tradeoff accepted, not free**: index maintenance now runs 4 days/week instead of daily (specific days shifted with each iteration, currently Sun/Tue/Thu/Sat) — more fragmentation accumulates between runs than under a daily cadence. Accepted as the right tradeoff for eliminating the backup-overlap risk entirely, and for evenly spacing `Backup_FULL` itself, rather than just narrowing the original overlap.

This folder exists only to carry GITIN-2060 as its own ticket (per the parent-ticket naming convention) and hold the actual execution record — not to redo the derivation.

## Context (carried forward, not re-derived)

`PNSSRL_MantenimientoIndices` runs a daily offline `ALTER INDEX REBUILD` against `Sml.CustomerPointsLog` at 06:15 UTC, which holds a schema-modification (`Sch-M`) lock for its full duration and has caused three confirmed blocking incidents against MobileAppService/club-site traffic (2026-08-28/29/30 weekend under GITIN-1866, 2026-09-14, 2026-09-21). GITIN-1981's full traffic analysis (POS hours, `Backup_FULL` schedule, MobileAppService's hour-7 UTC spike, a 54-task audit of `SFCG-TO-01`) converged on **08:00 UTC (05:00 UTC-3)** as the least-disruptive start time — not conflict-free, but the remaining overlaps (13 short background tasks, each under ~80s) only queue briefly rather than causing sustained live-traffic blocking. Full derivation: `events/20260901_pnssrl_mantenimientoindices_review/investigation.md` and `ops.md` (H1-H14, "Acciones propuestas" §1).

**Companion ticket GITIN-2061** (partition-scoped `IX_CustomerId` rebuild, rebuilding only the current-year partition instead of the whole table) is a separate, not-yet-started piece of the same underlying fix — tracked in `loyalty/todo/TODO.md`, not this folder.

## Execution

**Command (Q26 from the precedent investigation, `events/20260901_pnssrl_mantenimientoindices_review/scripts.sql`):** `sp_update_schedule` against `msdb`, in-place update of `schedule_id = 23` (confirmed via Q25 against `job_id = 0x9B0BD93393BA1846BE961FADF915AE66`), no change to `freq_type`/`freq_interval` (stays daily). Handed to the user as a copy-paste block in the conversation — not run directly, per project convention.

**Explicit caveats carried forward, still unresolved at execution time:**
- `Backup_FULL`'s own duration (weekly, Sun/Mon/Wed, starts 06:00 UTC) was never confirmed — 08:00 UTC assumes it's finished by then.
- The `SFCG-TO-01` ~12:00 UTC task cluster falls inside the rebuild's worst-case tail (ends ~14:14 UTC on a 6h+ run) — same interaction risk as GITIN-1753, not re-resolved.
- Root cause of the job's own duration variability (1h53m–6h14m, H4/H8) is still unexplained — 08:00 UTC works around this, doesn't fix it.
- `SFCG-CLUB-01`'s hourly traffic profile was never independently checked (only `SFCG-MOBI-01`'s was) — assumed similar, not confirmed.

## Post-close check (2026-09-22): does the final schedule overlap with TaskOperatorService?

User asked whether the new `Backup_FULL` schedule (Mon/Wed/Fri) overlaps with TaskOperatorService's own scheduled work (Sch.Job campaign engine, and the `Etl` framework). Checked both directly rather than assume:

- **`Sch.Job` (campaign engine)**: only 4 `Weekly`-scoped job entries exist at all (out of thousands), and all 4 are **expired** (`ActiveEndDate` in 2020 or 2024, years before today) — none currently live, none historically Friday-scoped either. The only currently-active exposure is the always-on `MktAsignationPointActionManager` campaigns (5-min cadence, 24/7, no day-of-week field) — already uniformly exposed regardless of which days `Backup_FULL` picks. Detail: `data/sch_weekly_jobs_check_20260922.txt`.
- **`Etl` framework**: `dbo.CustomerPointsLog`'s ETL sync (chronically slow, already known — `events/20260715_cpu_spikes/`) runs daily at ~07:25 UTC, typically 3-6h, genuinely overlapping `Backup_FULL`'s 06:00 UTC start every day it runs. **This is real but pre-existing, not introduced by today's change** — the ETL job runs all 7 days regardless, so changing which 3 specific days `Backup_FULL` occupies doesn't change the weekly incidence (still 3/7 days). Monday (this ETL's worst day, ~5.4h avg) is a `Backup_FULL` day under both the old and new schedule, unaffected either way. Friday (newly added) actually averages *lower* duration (~3.2h) than Sunday (removed, ~3.9h) — today's change is neutral-to-slightly-favorable here. Detail: `data/etl_operations_30d_history_20260922.txt`.

**Conclusion**: no new TaskOperatorService/Etl overlap was introduced by today's reschedule. The pre-existing `CustomerPointsLog` ETL/`Backup_FULL` interaction is a real, separate, already-partially-known issue (that ETL operation's own chronic slowness) — worth flagging as a candidate for its own future ticket, not something this ticket needs to fix.

## Third iteration (2026-09-22, ~14:00 UTC): full Etl-aware schedule

Deeper analysis of the `Etl CustomerPointsLog` overlap (above) led to a third schedule revision, now applied and verified (`data/third_iteration_schedule_20260922.txt`):

- **Real percentile data pulled** (`MIN/MAX/AVG/P90/P95` by weekday, `Etl.EtlOperationExecution` for `EtlOperation_Id=6`, 30 days, `data/etl_customerpointslog_percentiles_30d_20260922.txt`):

  | Day | n | Min | Max | Avg | P90 | P95 |
  |---|---|---|---|---|---|---|
  | Sun | 4 | 3.04h | 4.28h | 3.90h | 4.26h | 4.27h |
  | Mon | 5 | 4.81h | 6.80h | 5.39h | 6.30h | 6.55h |
  | Tue | 5 | 3.86h | 5.88h | 4.58h | 5.55h | 5.72h |
  | Wed | 4 | 1.86h | 25.94h (outlier) | 8.47h | 19.12h | 22.53h |
  | Thu | 3 | 2.78h | 3.38h | 3.01h | 3.27h | 3.33h |
  | Fri | 4 | 2.74h | 4.14h | 3.21h | 3.84h | 3.99h |
  | Sat | 4 | 2.87h | 4.30h | 3.32h | 3.94h | 4.12h |

  Monday shows a consistently elevated range (4.81-6.80h across all 5 observed Mondays, min already exceeding any reasonable buffer) — not outlier-driven. Wednesday's high average is entirely outlier-driven (min 1.86h, but one 25.9h run inflates the average/percentiles) — a materially different pattern, more consistent with a rare blocking incident than Monday's structurally slower shape.
- **`Backup_FULL` moved from Mon/Wed/Fri to Sun/Wed/Fri**, index maintenance re-derived as the complement (Mon/Tue/Thu/Sat, was Sun/Tue/Thu/Sat) — removes Monday's double contention (was both a backup day itself and immediately following Sunday's old backup) and removes Tuesday's backup-adjacency (no longer follows a backup day). Gaps for the new backup pattern (Sun/Wed/Fri): 3/2/2, same evenness as before, no consecutive days.
- **Start time moved to 09:00/09:15 UTC (06:00/06:15 UTC-3)**, and `Etl CustomerPointsLog` itself is planned to move to 05:00 UTC (02:00 UTC-3) — clears the 08:00 UTC-3 (11:00 UTC) deploy/migration window with buffer. **`Etl`'s own schedule change is NOT YET APPLIED** — it's a Windows Task Scheduler item on `SFCG-TO-01`, a different mechanism from the SQL Agent jobs changed here; no confirmed command pattern for it yet.
- Applied and verified: `Backup_FULL` (`schedule_id=18`, `freq_interval=41`), both index jobs (`schedule_id=23,25`, `freq_interval=86`), all at 09:00/09:15 UTC.

**Applied 2026-09-22, 14:17 UTC** (see "Locating the Etl.CustomerPointsLog trigger mechanism" below for the full trace — it turned out to be a `Sch.TimeTable` field, not Windows Task Scheduler as originally assumed). Real post-change monitoring (fragmentation, `Etl` duration under the new less-contended time, actual blocking-free confirmation) is the remaining validation step — not further analysis of the old data.

## Locating the Etl.CustomerPointsLog trigger mechanism (2026-09-22, continued)

User surfaced `dbo.RescheduleTask` (a stored proc taking `@TaskId INT, @NewExecuteOn DATETIMEOFFSET`) as a candidate for changing the trigger time. Analyzed the definition: it validates the target `Sch.Task` row isn't already started/done/deactivated, updates that single task's `ExecuteOn`, and conditionally extends `Sch.Job.ValidTo`/`Sch.TimeTable.ActiveEndDate` if the new date exceeds current validity — but does **not** touch `Sch.TimeTable.FrecuencyType`/`FrecuencyInterval` (the recurrence pattern) or any time-of-day field. It reschedules one occurrence, not a recurring pattern — not usable as-is for a permanent daily time change.

Before deciding whether it's even relevant, checked whether `Etl.CustomerPointsLog` is tracked in `Sch.Job` at all (previously only confirmed for `MktAsignationPointActionManager` campaigns, per `task_operator_tasks.md` §3):

```sql
SELECT * FROM Sch.Job WHERE Name LIKE '%CustomerPointsLog%' OR Name LIKE '%Etl%';
```

**Confirmed**: `Sch.Job.Id=755`, `Name=EtlDwGridoCustomerPointsLogProcessor`, `Description="Etl de customer points log. Sincroniza con DwGrido."`, `ValidSince=2019-12-26`, `ValidTo=2029-12-01`, `DeactivatedDate=NULL` — active, currently live job. Full result (31 rows, mostly unrelated `SendMailCustomerNewCard`/other `EtlDwGrido*Processor` entries): `data/sch_job_etl_search_20260922.txt`.

**Caveat, not yet resolved**: `Sch.Job.Id=755`'s description says "Sincroniza con DwGrido" (syncs with the DW) — direction not explicit from the name alone. Not yet confirmed this is the *same* logical process as `Etl.EtlOperationConfig.Id=6` (`ToTable=dbo.CustomerPointsLog`, the one with the ~07:25 UTC start / 3-6h duration history already pulled). Plausible relationship: `Sch.Job`/`Sch.Task` (framework #3) is the trigger/scheduler that kicks off the `Etl` framework's (#2) actual operation — i.e. `Sch.Job.Id=755` may be what *fires* `EtlOperationConfig.Id=6` — but this is inference, not confirmed.

**Next step**: pull `Sch.Task`/`Sch.TimeTable` for `JobId=755` to (a) confirm whether its observed execution times line up with the known ~07:25 UTC pattern (which would confirm the same-process link), and (b) find whatever field actually encodes time-of-day, if any — `Sch.TimeTable` is known to carry `FrecuencyType`/`FrecuencyInterval`/`ActiveStartDate`/`ActiveEndDate` (per the `RescheduleTask` proc and the earlier `Sch.Job` weekly-campaign check), but the exact column set for `Sch.Task` and the time-of-day field haven't been verified this session — given repeated schema-guessing errors earlier (`PNSSRL_AuditSysprocesses`, `Etl.EtlOperationConfig`), verify via `INFORMATION_SCHEMA.COLUMNS` first rather than guessing column names.

**Schema check result**: `Sch.Task` (11 cols) matched the already-documented set exactly. `Sch.TimeTable` (10 cols): `Id, JobId, Enabled, ActiveStartDate, ActiveEndDate, Name, FrecuencyType, FrecuencyInterval, FrequencyRecurrenceFactor, FrecuencySubDayInterval` — `FrecuencySubDayInterval` is a `time` column, a new field not previously documented in §3 (the campaign-537 precedent only exercised `FrecuencyType`/`FrecuencyInterval`).

**Confirmed link — `Job.Id=755` IS the `Etl CustomerPointsLog` trigger:**

```sql
SELECT t.Id AS TimeTableId, t.JobId, t.Enabled, t.ActiveStartDate, t.ActiveEndDate, t.Name,
       t.FrecuencyType, t.FrecuencyInterval, t.FrequencyRecurrenceFactor, t.FrecuencySubDayInterval
FROM Sch.TimeTable t WHERE t.JobId = 755;

SELECT TOP 20 k.Id, k.ExecuteOn, k.ExecutionStarted, k.Done, k.Failed, k.TimeTableId, k.JobId
FROM Sch.Task k WHERE k.JobId = 755 ORDER BY k.ExecuteOn DESC;
```

Result (`data/sch_timetable_task_755_20260922.txt`): `TimeTableId=755`, `Enabled=1`, `FrecuencyType='Daily'`, `FrecuencyInterval=1`, **`FrecuencySubDayInterval=07:25:00`** — an exact match to the already-known `Etl CustomerPointsLog` trigger time. 20-row `Sch.Task` history shows `ExecutionStarted` firing at 07:25 UTC every single day (2026-09-04 through 2026-09-23, one row queued for tomorrow), `Done` timestamps landing 2h48m-5h+ later — consistent with the chronic 3-6h duration already documented from `Etl.EtlOperationExecution`. `Failed=1` on 2026-09-09 (the known 25.9h-outlier day) with a short same-day `Done` — this `Sch.Task` row itself failed fast; the actual 25.9h run is presumably tracked separately in `Etl.EtlOperationExecution`, relationship between the two not further chased (not needed for the scheduling question).

**Mechanism confirmed**: the time-of-day field is `Sch.TimeTable.FrecuencySubDayInterval`, not `ActiveStartDate`'s time component (which is `00:00:00` here) — corrects the earlier guess in this file.

**Applied and verified (2026-09-22, 14:17 UTC)**: `UPDATE Sch.TimeTable SET FrecuencySubDayInterval = '05:00:00' WHERE Id = 755` executed against `SFCG-DB01`/`SmartFran.Solution.SmartLoyalty`. Verification confirms `FrecuencySubDayInterval=05:00:00.0000000`, `Enabled=1`, `FrecuencyType='Daily'` unchanged. Full record: `data/etl_customerpointslog_timetable_update_20260922.txt`. **Caveat**: tomorrow's already-generated `Sch.Task` row (`Id=349380`, `ExecuteOn=2026-09-23 07:25:00 UTC`) was not retroactively changed — the new 05:00 UTC time takes effect starting the following day's task generation, 2026-09-24.

**This closes the last open piece of the third-iteration schedule.** All three components now applied and verified: `Backup_FULL` (Sun/Wed/Fri 09:00 UTC), index maintenance (Mon/Tue/Thu/Sat 09:00/09:15 UTC), `Etl CustomerPointsLog` (daily 05:00 UTC, was 07:25 UTC). Real post-change monitoring (fragmentation, `Etl` duration under the new less-contended time, actual blocking-free confirmation) is the remaining validation step — not further analysis of pre-change historical data.

## Post-change validation (2026-09-23)

First real check of the third-iteration schedule against live job history (`msdb.dbo.sysjobhistory`) and `Sch.Task`, `data/post_change_job_history_20260923.txt`:

- **`Backup_FULL` confirmed working**: first real run since the change — today (Wed 09-23), 09:00:00 UTC, succeeded, 8m17s duration (in line with the historical 8-12 min range). Correct day (Sun/Wed/Fri), correct time.
- **Index maintenance not yet testable**: yesterday's (Tue 09-22) runs of both `PNSSRL_MantenimientoIndices` (08:00 UTC) and `PNSSRL_MantenimientoIndices_CustomerPointsLog` (08:15 UTC, schedule name still `Daily_0815UTC` — stale label, see below) fired under the *old* second-iteration time, since they ran before the third-iteration change went in later that same day (~14:00 UTC). Today isn't an index day under either schedule. First real test: tomorrow, Thu 09-24, first Mon/Tue/Thu/Sat day since the change — should fire at 09:00/09:15 UTC.
- **`Etl CustomerPointsLog` confirmed queued correctly**: `Sch.Task.Id=349745` (tomorrow, 2026-09-24) already generated at **05:00:00 UTC** — the new time. Today's task (`Id=349380`) still ran at the old 07:25 UTC, as predicted (queued before the change). First real execution at 05:00 UTC will be tomorrow morning — still needs to be checked once it happens.
- **Minor, not urgent**: `Schedule 25`'s `@name` is still `Daily_0815UTC` — none of the three `sp_update_schedule` iterations updated the name, only `freq_interval`/`active_start_time`. Cosmetic (doesn't affect function), but misleading to anyone reading `sysschedules` by name.
- Historical rows in the same pull (09-21 `PNSSRL_MantenimientoIndices` FAILED at 06:15 UTC, 4h15m) are the pre-GITIN-2060 baseline — this is GITIN-2076, the third blocking recurrence that motivated this ticket, already documented, not new information.

**Still open**: tomorrow's index-maintenance run (Thu 09-24) and `Etl CustomerPointsLog`'s first 05:00 UTC execution both still need to be checked once they've actually happened.

## Next steps

Closed, `ops.md` updated with the weekday-restriction change and before/after Gantt charts. Remaining open items are tracked separately, not blockers for this ticket:
- **GITIN-2061** — the partition-scoped rebuild itself is applied, but its exclusion mechanism doesn't work as designed (the old job still touches `CustomerPointsLog` via a cheap `REORGANIZE`) — see that folder's own `investigation.md`/`ops.md` H6. Unaffected by today's weekday-restriction change, which is orthogonal (about which *days* the jobs run, not which *tables* the old sweep touches).
- The remaining three explicit caveats (`SFCG-TO-01` 12:00 UTC cluster, job duration variability root cause, `SFCG-CLUB-01` traffic profile) remain unresolved — none block this reschedule.
- The new weekly cadence's fragmentation-accumulation tradeoff isn't yet observed in practice — worth revisiting if fragmentation on `CustomerPointsLog`/`CustomerAdditionalInformation` climbs noticeably over the Sun/Mon/Wed gaps.

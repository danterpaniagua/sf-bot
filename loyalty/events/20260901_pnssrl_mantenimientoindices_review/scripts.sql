-- Event: 20260901_pnssrl_mantenimientoindices_review (GITIN-1981, parent GITIN-1866)
-- Q13/Q14 originally run under GITIN-1866's scripts.sql (loyalty/events/20260816_club_grido_campaign_query_health/scripts.sql)
-- before this ticket was split off. Reproduced here so this ticket's SQL trail is self-contained.

-- === Q13 — Root blocker identification, 2026-08-28/29/30 weekend window ===
;WITH blocked_rows AS (
    SELECT fecha_hora_captura, spid, blocked
    FROM PNSSRL_AuditSysprocesses
    WHERE fecha_hora_captura BETWEEN '2026-08-28 03:00:00' AND '2026-08-31 03:00:00'
      AND blocked <> 0
)
SELECT DISTINCT
    b.fecha_hora_captura,
    b.blocked AS head_spid,
    h.hostname,
    h.program_name,
    h.lastwaittype,
    h.status,
    h.cmd,
    h.comando_ejecutado
FROM blocked_rows b
LEFT JOIN PNSSRL_AuditSysprocesses h
    ON h.fecha_hora_captura = b.fecha_hora_captura
   AND h.spid = b.blocked
WHERE NOT EXISTS (
    SELECT 1 FROM blocked_rows b2
    WHERE b2.fecha_hora_captura = b.fecha_hora_captura AND b2.spid = b.blocked
)
ORDER BY b.fecha_hora_captura;
-- RESULT: head blocker in all 26 blocking snapshots = SQL Agent job 0x9B0BD93393BA1846BE961FADF915AE66
-- running ALTER INDEX REBUILD on Sml.CustomerPointsLog (25 snapshots) / SmlSupp.PromotionBranchOffice (1 snapshot)

-- === Q14 — Blocking severity per snapshot, weekend window ===
SELECT
    fecha_hora_captura,
    COUNT(*) AS blocked_rows,
    COUNT(DISTINCT spid) AS distinct_blocked_spids,
    COUNT(DISTINCT blocked) AS distinct_blocker_spids
FROM PNSSRL_AuditSysprocesses
WHERE fecha_hora_captura BETWEEN '2026-08-28 03:00:00' AND '2026-08-31 03:00:00'
  AND blocked <> 0
GROUP BY fecha_hora_captura
ORDER BY fecha_hora_captura;
-- RESULT: peak 38 blocked sessions / 16 blocker-chain links, 2026-08-28 07:21:00 UTC

-- === Q15 — Job name/step definition for the head blocker job ===
DECLARE @job_id UNIQUEIDENTIFIER = CAST(0x9B0BD93393BA1846BE961FADF915AE66 AS UNIQUEIDENTIFIER);

SELECT
    j.name AS job_name,
    j.enabled,
    j.description,
    js.step_name,
    js.command
FROM msdb.dbo.sysjobs j
LEFT JOIN msdb.dbo.sysjobsteps js ON js.job_id = j.job_id
WHERE j.job_id = @job_id;
-- RESULT: job_name = PNSSRL_MantenimientoIndices, matches queries/PNSSRL_MantenimientoIndices.sql

-- === Q16 — Schedule definition ===
SELECT
    j.name AS job_name,
    sch.name AS schedule_name,
    sch.enabled AS schedule_enabled,
    sch.freq_type,
    sch.freq_interval,
    sch.freq_recurrence_factor,
    sch.active_start_date,
    sch.active_start_time,
    sch.active_end_time
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobschedules js ON js.job_id = j.job_id
JOIN msdb.dbo.sysschedules sch ON sch.schedule_id = js.schedule_id
WHERE j.job_id = CAST(0x9B0BD93393BA1846BE961FADF915AE66 AS UNIQUEIDENTIFIER);
-- RESULT: freq_type=4 (daily), freq_interval=1, active_start_time=06:15:00 UTC — standing daily job

-- === Q17 — Last 10 runs (history/duration/outcome) ===
SELECT TOP 10
    j.name AS job_name,
    CONVERT(VARCHAR(8), h.run_date) AS run_date,
    STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(6), h.run_time), 6), 5, 0, ':'), 3, 0, ':') AS run_time_local,
    RIGHT('000000' + CONVERT(VARCHAR(6), h.run_duration), 6) AS run_duration_hhmmss,
    CASE h.run_status WHEN 0 THEN 'Failed' WHEN 1 THEN 'Succeeded' WHEN 2 THEN 'Retry' WHEN 3 THEN 'Canceled' WHEN 4 THEN 'In Progress' END AS status,
    h.step_name
FROM msdb.dbo.sysjobhistory h
JOIN msdb.dbo.sysjobs j ON j.job_id = h.job_id
WHERE j.job_id = CAST(0x9B0BD93393BA1846BE961FADF915AE66 AS UNIQUEIDENTIFIER)
ORDER BY h.run_date DESC, h.run_time DESC;
-- RESULT: 2026-09-01 duration 01:52:55; 2026-08-31 duration 06:14:11 — high variability, cause not yet identified

-- === Q18 — Definition of PNSSRL_MantenimientoModulos (attempted) ===
SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.PNSSRL_MantenimientoModulos')) AS definition;
EXEC sp_helptext 'dbo.PNSSRL_MantenimientoModulos';
-- RESULT: NULL / "The text for object 'dbo.PNSSRL_MantenimientoModulos' is encrypted." — dead end, WITH ENCRYPTION

-- === Q19 — Reproduce naive vs. correct sysjobhistory row selection (used to test a since-corrected hypothesis) ===
DECLARE @job_id2 UNIQUEIDENTIFIER = CAST(0x9B0BD93393BA1846BE961FADF915AE66 AS UNIQUEIDENTIFIER);

SELECT TOP 1 'Naive (any step)' AS variant, run_date, run_time, run_duration, step_id, step_name
FROM msdb.dbo.sysjobhistory
WHERE job_id = @job_id2
ORDER BY run_date DESC, run_time DESC;

SELECT TOP 1 'Correct (step_id=0, job outcome)' AS variant, run_date, run_time, run_duration, step_id, step_name
FROM msdb.dbo.sysjobhistory
WHERE job_id = @job_id2 AND step_id = 0
ORDER BY run_date DESC, run_time DESC;
-- RESULT: reproduced the symptom (naive row shows duration=0) but the ACTUAL Zabbix master item (below)
-- does not use this naive pattern — see note. Kept for the record; this hypothesis was superseded.

-- === Q20 — sysjobhistory further back, full duration distribution (only 2 data points so far) ===
SELECT
    CONVERT(VARCHAR(8), h.run_date) AS run_date,
    STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(6), h.run_time), 6), 5, 0, ':'), 3, 0, ':') AS run_time_local,
    RIGHT('000000' + CONVERT(VARCHAR(6), h.run_duration), 6) AS run_duration_hhmmss,
    CASE h.run_status WHEN 0 THEN 'Failed' WHEN 1 THEN 'Succeeded' WHEN 2 THEN 'Retry' WHEN 3 THEN 'Canceled' WHEN 4 THEN 'In Progress' END AS status
FROM msdb.dbo.sysjobhistory h
WHERE h.job_id = CAST(0x9B0BD93393BA1846BE961FADF915AE66 AS UNIQUEIDENTIFIER)
  AND h.step_id = 0
ORDER BY h.run_date DESC, h.run_time DESC;
-- Purpose: real distribution of run durations (not just the 2 points already known), and — combined with
-- run_time_local — how far each run's END time drifts past the 06:15 UTC start on its longest days.
-- OUTPUT (2026-09-09): 25 days pulled (2026-08-15 to 2026-09-08). Confirms real, recurring variability,
-- not a one-off outlier: most days cluster ~01:30-02:10, but 6/25 days (24%) exceed 3h (03:18:15, 03:21:24,
-- 03:24:49, 03:59:59, 04:06:25, and the known 06:14:11 on 08-31) -- roughly every 4-5 days. Worst case, a
-- 06:15 UTC start can still be running past 12:00 UTC. This directly informs Q21: any new start time needs
-- enough buffer to absorb a 3-4h+ run, not just the ~1h45m typical case.

-- === Q21 — Hourly connection-volume profile for MobileAppService, to find a genuinely low-traffic window ===
-- NOTE: assumes PNSSRL_AuditSysprocesses is a continuous background capture, not only populated during
-- ad-hoc investigation windows — confirm the date range actually returned covers a real spread of days
-- before trusting this as a full 24h profile, not just the days past investigations happened to capture.
USE PNSSRL;
SELECT
    DATEPART(HOUR, fecha_hora_captura) AS hour_utc,
    COUNT(*) AS snapshot_rows,
    COUNT(DISTINCT spid) AS distinct_spids,
    MIN(fecha_hora_captura) AS earliest_sample,
    MAX(fecha_hora_captura) AS latest_sample
FROM PNSSRL_AuditSysprocesses
WHERE fecha_hora_captura >= DATEADD(DAY, -30, GETUTCDATE())
  AND (hostname LIKE 'SFCG-MOBI%' OR program_name LIKE '%Mobile%')
GROUP BY DATEPART(HOUR, fecha_hora_captura)
ORDER BY hour_utc;
-- Purpose: 24-bucket (hour_utc 0-23) activity profile for MobileAppService over the last 30 days, to find
-- the genuinely lowest-traffic window(s) rather than assuming 06:15 UTC is optimal. Cross-check against
-- Q20's worst-case duration before proposing a new start time — the window needs to stay low-traffic for
-- the full run, not just at the moment it starts.
-- OUTPUT (2026-09-09): 30 continuous days confirmed (2026-08-10/11 to 2026-09-08/09, earliest/latest_sample
-- span the full window with no gaps). Lowest-traffic hours: 3, 4, 5, 10 UTC (2,811-4,410 rows, 55-84 distinct
-- spids). CRITICAL: hour 7 UTC has a massive, isolated spike -- 10,274 rows, ~2x any other hour, 132 distinct
-- spids (also the single highest). The current 06:15 UTC start already borders this, and the 6 long-tail
-- days from Q20 (3-6h+ runs) sweep straight through hours 7-12, including this spike. Cause of the hour-7
-- spike not yet identified -- see Q22.

-- === Q22 — What's driving the hour-7 UTC spike? Another job, or organic traffic? ===
USE msdb;
SELECT
    j.name AS job_name,
    sch.active_start_time,
    sch.freq_type,
    sch.freq_interval
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobschedules js ON js.job_id = j.job_id
JOIN msdb.dbo.sysschedules sch ON sch.schedule_id = js.schedule_id
WHERE j.enabled = 1
  AND sch.active_start_time BETWEEN 063000 AND 080000
ORDER BY sch.active_start_time;

USE PNSSRL;
SELECT TOP 20
    hostname,
    program_name,
    COUNT(*) AS rows_in_hour7,
    COUNT(DISTINCT spid) AS distinct_spids
FROM PNSSRL_AuditSysprocesses
WHERE fecha_hora_captura >= DATEADD(DAY, -30, GETUTCDATE())
  AND DATEPART(HOUR, fecha_hora_captura) = 7
GROUP BY hostname, program_name
ORDER BY rows_in_hour7 DESC;
-- Purpose: first query checks for another SQL Agent job scheduled 06:30-08:00 UTC that could explain the
-- spike (a maintenance/backup job rather than real app traffic); second breaks hour 7's activity down by
-- host/program to see whether it's MobileAppService itself ramping up, a different service entirely, or a
-- batch/report process. Determines whether hour 7 is a movable job (reorder relative to this one) or real
-- user traffic (a hard constraint to schedule around).
-- OUTPUT (2026-09-09): only one job overlaps 06:30-08:00 UTC -- PNSSRL_CapturaCheckDB, active_start_time
-- 07:00:00, freq_type=8/freq_interval=2 (WEEKLY, Mondays only) -- can't explain a spike appearing across a
-- 30-day rollup on its own (would need day-of-week breakdown to confirm it contributes at all on Mondays).
-- Host/program breakdown is decisive: SFCG-MOBI-01's ".Net SqlClient Data Provider" alone accounts for
-- 10,274 rows / 132 distinct spids -- matching Q21's ENTIRE hour-7 MobileAppService total exactly. This is
-- the app's own DB driver, i.e. real application traffic, not a SQL Agent job or batch process that could be
-- reordered. CONCLUSION: hour 7 UTC is a hard constraint (genuine MobileAppService load), not a movable
-- neighbor -- scheduling PNSSRL_MantenimientoIndices needs to work around it, not coordinate with it.

-- === Q23 — Full backup (and log backup) schedule, to check for collision with the recommended 00:30 UTC window ===
-- No confirmed schedule for Operaciones_MaintenancePlan_Backups.Backup_FULL anywhere in this repo -- only
-- that it exists (20260611_job_backup_log incident) and that Backup_Log runs every 10 minutes. Checking
-- directly rather than assuming no overlap.
USE msdb;
SELECT
    j.name AS job_name,
    sch.name AS schedule_name,
    sch.freq_type,
    sch.freq_interval,
    sch.freq_subday_type,
    sch.freq_subday_interval,
    sch.active_start_time,
    sch.enabled AS schedule_enabled
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobschedules js ON js.job_id = j.job_id
JOIN msdb.dbo.sysschedules sch ON sch.schedule_id = js.schedule_id
WHERE j.name LIKE 'Operaciones_MaintenancePlan_Backups%'
ORDER BY j.name;
-- Purpose: confirm Backup_FULL's actual schedule (day/time) and re-confirm Backup_Log's cadence, to check
-- both against the recommended 00:30 UTC window for PNSSRL_MantenimientoIndices before finalizing it.
-- OUTPUT (2026-09-09): Backup_FULL -- freq_type=8 (weekly), freq_interval=11 (bitmask 1+2+8 = Sunday+
-- Monday+Wednesday), active_start_time=06:00:00 UTC. Backup_Log -- daily, every 10 minutes, all day
-- (freq_subday_type=4/interval=10, start 00:00 UTC) -- continuous background activity, already reflected
-- in everything measured so far, not a new conflict to schedule around.
-- REAL FINDING: Backup_FULL at 06:00 UTC on Sun/Mon/Wed collides with the CURRENT 06:15 UTC job start for
-- its entire run on those 3 days (job starts 15min into an active full backup) -- possible contributor to
-- H4's duration variability, not yet confirmed. Also means the recommended 00:30 UTC option's worst-case
-- tail (ends 06:44) would still clip ~44min of Backup_FULL on those same days. See Q24 to test the
-- day-of-week correlation against Q20's 6 long-duration days before finalizing anything.

-- === Q25 — Read-only: confirm schedule_id and current values before changing anything ===
USE msdb;
SELECT
    sch.schedule_id,
    sch.name AS schedule_name,
    sch.active_start_time,
    sch.freq_type,
    sch.freq_interval,
    sch.enabled
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobschedules js ON js.job_id = j.job_id
JOIN msdb.dbo.sysschedules sch ON sch.schedule_id = js.schedule_id
WHERE j.job_id = CAST(0x9B0BD93393BA1846BE961FADF915AE66 AS UNIQUEIDENTIFIER);
-- Purpose: get the exact schedule_id and re-confirm active_start_time is still 06:15:00 UTC before
-- applying any change below -- don't assume it hasn't been touched since Q16.
-- OUTPUT (2026-09-10): schedule_id 23, name PNSSRL_MantenimientoIndices, active_start_time 061500
-- (06:15:00 UTC), freq_type 4 (daily), freq_interval 1, enabled 1. Matches expectations exactly.

-- === Q26 — OPTION 1 (recommended): update the existing schedule in place ===
-- ⚠️ ACTION -- moves PNSSRL_MantenimientoIndices's daily start time to 08:00 UTC (revised 2026-09-10,
-- supersedes the earlier 23:30 UTC value -- that pick fell inside confirmed PoS active hours,
-- 13:00-05:00 UTC). schedule_id confirmed as 23 (Q25). Adjust 080000 if a different exact time is
-- chosen once Backup_FULL's own duration / any ETL schedule is confirmed (see investigation.md's
-- explicit caveats on this recommendation).
USE msdb;
EXEC dbo.sp_update_schedule
    @schedule_id = 23,
    @active_start_time = 080000;
-- OUTPUT: pending.

-- === Q27 — OPTION 2 (alternative): detach the old schedule, attach a new one ===
-- ⚠️ ACTION -- only use this instead of Q26 if the old 06:15 UTC schedule object should be preserved
-- (e.g. as a rollback reference) rather than overwritten in place.
USE msdb;
EXEC dbo.sp_detach_schedule
    @job_id = '9B0BD933-93BA-1846-BE96-1FADF915AE66',
    @schedule_id = 23;

EXEC dbo.sp_add_schedule
    @schedule_name = N'PNSSRL_MantenimientoIndices_0800UTC',
    @freq_type = 4,          -- daily
    @freq_interval = 1,
    @active_start_time = 080000;

EXEC dbo.sp_attach_schedule
    @job_id = '9B0BD933-93BA-1846-BE96-1FADF915AE66',
    @schedule_name = N'PNSSRL_MantenimientoIndices_0800UTC';
-- OUTPUT: pending.

-- === Q28 — Verify the change took effect ===
USE msdb;
SELECT sch.schedule_id, sch.name, sch.active_start_time, sch.enabled
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobschedules js ON js.job_id = j.job_id
JOIN msdb.dbo.sysschedules sch ON sch.schedule_id = js.schedule_id
WHERE j.job_id = CAST(0x9B0BD93393BA1846BE961FADF915AE66 AS UNIQUEIDENTIFIER);
-- OUTPUT: pending.

-- === Q29 — All enabled SQL Agent jobs and their schedules ===
USE msdb;
SELECT
    j.name AS job_name,
    j.enabled AS job_enabled,
    js.step_name AS first_step,
    js.command,
    sch.name AS schedule_name,
    sch.freq_type,
    sch.freq_interval,
    sch.freq_subday_type,
    sch.freq_subday_interval,
    sch.active_start_time,
    sch.enabled AS schedule_enabled
FROM msdb.dbo.sysjobs j
LEFT JOIN msdb.dbo.sysjobsteps js ON js.job_id = j.job_id AND js.step_id = 1
LEFT JOIN msdb.dbo.sysjobschedules jsch ON jsch.job_id = j.job_id
LEFT JOIN msdb.dbo.sysschedules sch ON sch.schedule_id = jsch.schedule_id
WHERE j.enabled = 1
ORDER BY sch.active_start_time, j.name;
-- OUTPUT (2026-09-10, full raw output in data/all_enabled_jobs_schedules_20260910.txt): 12 enabled jobs.
-- CRITICAL NEW FINDING: Actualiza_DWGrido_CustomerPointsBalance -- daily, once at 08:30:00 UTC, not
-- previously known to this investigation. Lands directly inside the 08:00 UTC candidate window. Name
-- suggests it touches customer points balance data -- possible direct conflict with Sml.CustomerPointsLog.
-- Duration and whether it actually locks/reads that table: NOT YET CHECKED, see Q30.
-- Also confirms: PNSSRL_CapturaCheckDB (DBCC CHECKDB all DBs, weekly Monday 07:00 UTC, heavy) and
-- PNSSRL_CapturaUsoIndices (weekly Thu/Fri 23:00 UTC -- retroactively confirms the now-superseded 23:30
-- UTC pick would have collided with this too, beyond the POS-hours issue already found). Several
-- continuous capture jobs (blocking info every 3min, TempdbProc/CapturaQuery every 10min,
-- AuditSysprocesses every 5min) run all day, not schedule-window relevant.

-- === Q30 — Definition and recent execution history of Actualiza_DWGrido_CustomerPointsBalance ===
USE [SmartFran.Solution.SmartLoyalty];
SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.Actualiza_DWGrido_CustomerPointsBalance')) AS definition;
USE msdb;
SELECT TOP 30
    CONVERT(VARCHAR(8), h.run_date) AS run_date,
    STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(6), h.run_time), 6), 5, 0, ':'), 3, 0, ':') AS run_time_utc,
    RIGHT('000000' + CONVERT(VARCHAR(6), h.run_duration), 6) AS run_duration_hhmmss,
    CASE h.run_status WHEN 0 THEN 'Failed' WHEN 1 THEN 'Succeeded' WHEN 2 THEN 'Retry' WHEN 3 THEN 'Canceled' WHEN 4 THEN 'In Progress' END AS status
FROM msdb.dbo.sysjobhistory h
JOIN msdb.dbo.sysjobs j ON j.job_id = h.job_id
WHERE j.name = 'Actualiza_DWGrido_CustomerPointsBalance'
  AND h.step_id = 0
ORDER BY h.run_date DESC, h.run_time DESC;
-- OUTPUT (2026-09-10): definition readable (not encrypted). RESOLVES the Q29 concern -- NOT a conflict:
-- (1) reads FROM SmlSt.CustomerPointsLog (the SmlSt schema, same one Query101 used -- a distinct
-- staging/reporting schema, NOT the Sml.CustomerPointsLog table PNSSRL_MantenimientoIndices rebuilds),
-- writes to a separate linked-server DB ([DWGRIDO].dwgrido.dbo.CustomerPointsBalance) -- no shared
-- object with the index-rebuild job. (2) 30 days of real runs: 3m24s-15m14s, mostly 4-7 min -- fast,
-- not a multi-hour risk. The "CRITICAL" flag on this job in Q29's output was wrong; corrected here.
-- One caveat not independently confirmed: whether SmlSt.CustomerPointsLog is a base table or a view
-- over Sml.CustomerPointsLog (would still matter for lock behavior if the latter) -- not chased further,
-- low-priority given the short duration either way.

-- === Q31 — Sch.Task / Sch.TaskEvent check — DEAD END for task duration, kept for the record ===
-- USE [SmartFran.Solution.SmartLoyalty];
-- SELECT TOP 20 * FROM Sch.Task;
-- SELECT TOP 20 * FROM Sch.TaskEvent ORDER BY 1 DESC;
-- OUTPUT (2026-09-10, data/sch_task_schema_check_20260910.txt): this is TaskOperatorService's own
-- INTERNAL job engine for campaign-triggered actions (MktAsignationPointActionManager, keyed by
-- MktCampaignId/ActionId) -- a third, separate scheduling mechanism, NOT the Windows Task Scheduler
-- \SmartFran\ folder these 13 tasks live in. Does not answer the duration question. Need Windows Task
-- Scheduler's own event log instead -- see Q32 (PowerShell, run on SFCG-TO-01).

-- === Q32 — Real per-execution duration for the 13 touching tasks, from Windows Task Scheduler's own log ===
-- Run on SFCG-TO-01 (PowerShell). Event ID 100 = task action started, 102 = task action completed;
-- both carry the same ActivityId per execution instance, letting us pair start/end directly.
-- "Running on: $env:COMPUTERNAME" ★
-- $tasks = @(
--   'Alerts Update','AssignPointFirstSaleApp','AssignPointNewCustomers_New','Program Results',
--   'ExchangeReportsMonth','ReportUpdateCustomer','ReportPointsTransfer',
--   'ReportManualPointsAssignmentLists','ReportManualPointsAssignmentIndividual',
--   'PointsFranchisePY','PointsLogGenerator','SendCanjesSocioCortesiaToBlobStorage',
--   'SendDetalleCanjesSocioCortesiaToBlobStorage'
-- )
-- $events = Get-WinEvent -FilterHashtable @{
--     LogName = 'Microsoft-Windows-TaskScheduler/Operational'
--     Id = 100,102
--     StartTime = (Get-Date).AddDays(-7)
-- } | Where-Object { $tasks -contains ($_.Properties[0].Value -replace '^\\SmartFran\\','') }
-- $grouped = $events | Group-Object ActivityId
-- $results = foreach ($g in $grouped) {
--     $start = $g.Group | Where-Object Id -eq 100 | Select-Object -First 1
--     $end   = $g.Group | Where-Object Id -eq 102 | Select-Object -First 1
--     if ($start -and $end) {
--         [PSCustomObject]@{
--             TaskName    = $start.Properties[0].Value
--             Start       = $start.TimeCreated
--             End         = $end.TimeCreated
--             DurationSec = [math]::Round(($end.TimeCreated - $start.TimeCreated).TotalSeconds,1)
--         }
--     }
-- }
-- $results | Sort-Object TaskName, Start | Format-Table -AutoSize
-- OUTPUT: pending.

-- === Q29a — All ETL operations configured in SmartFran.Solution.SmartLoyalty's own Etl framework ===
-- Schema discovered in 20260715_cpu_spikes (Q5/Q6/Q7 there): Etl.EtlOperationConfig (definitions),
-- Etl.EtlOperationExecution (real execution history/limits). That investigation only looked at the
-- CustomerPointsLog operation (habitual trigger ~07:25 UTC, chronic ~10-20 rows/sec) -- pulling the
-- full operation list here since any of them could land inside the 08:00-13:00 UTC candidate window.
USE [SmartFran.Solution.SmartLoyalty];
SELECT
    Id,
    OperationName,
    FromTable,
    ToTable,
    BatchSize,
    SetSize,
    MaxExecutionPeriod,
    Enabled
FROM Etl.EtlOperationConfig
ORDER BY OperationName;
-- OUTPUT: pending.

-- === Q29b — Recent execution history for ALL ETL operations (not just CustomerPointsLog), last 30 days ===
USE [SmartFran.Solution.SmartLoyalty];
SELECT
    c.OperationName,
    e.StartDate,
    e.EndDate,
    DATEDIFF(SECOND, e.StartDate, e.EndDate) AS duration_sec,
    e.LowerLimit,
    e.UpperLimit,
    e.TotalRows
FROM Etl.EtlOperationExecution e
JOIN Etl.EtlOperationConfig c ON c.Id = e.OperationConfigId
WHERE e.StartDate >= DATEADD(DAY, -30, GETUTCDATE())
ORDER BY e.StartDate DESC;
-- Purpose: real start/end times and durations for every ETL operation over the last 30 days -- need
-- this to check whether any operation's actual run window (not just its nominal trigger time) overlaps
-- the 08:00-13:00 UTC candidate window for PNSSRL_MantenimientoIndices's reschedule, especially given
-- CustomerPointsLog's own habitual ~07:25 UTC trigger and known slow throughput could run well past 08:00.
-- OUTPUT: pending.

-- === Q24 — Do Q20's long-duration days fall on Sun/Mon/Wed (Backup_FULL's schedule)? ===
USE PNSSRL;
SELECT
    CONVERT(VARCHAR(8), h.run_date) AS run_date,
    DATENAME(WEEKDAY, CONVERT(DATE, CONVERT(VARCHAR(8), h.run_date), 112)) AS weekday,
    RIGHT('000000' + CONVERT(VARCHAR(6), h.run_duration), 6) AS run_duration_hhmmss
FROM msdb.dbo.sysjobhistory h
WHERE h.job_id = CAST(0x9B0BD93393BA1846BE961FADF915AE66 AS UNIQUEIDENTIFIER)
  AND h.step_id = 0
ORDER BY h.run_date DESC;
-- Purpose: adds the actual day-of-week to each of Q20's 25 runs, to check directly whether the 6 days
-- exceeding 3h duration cluster on Sunday/Monday/Wednesday (Backup_FULL's schedule) or are spread evenly
-- across the week. A clean cluster would strongly suggest full-backup I/O contention as H4's cause.
-- OUTPUT (2026-09-09): PARTIAL correlation, NOT a clean confirmation. By weekday (4 Mon, 4 Sun, 3 Wed
-- sampled): Monday is the clear outlier -- 3 of 4 Mondays exceed 3h (04:06:25, 06:14:11, 03:59:59; the 4th,
-- 02:49:08, is still elevated vs. the ~1h45m typical). Sunday is moderately elevated -- 2 of 4 exceed 3h
-- (03:24:49, 03:18:15). But Wednesday -- same Backup_FULL schedule as Sun/Mon -- shows ZERO long runs (all
-- 3 samples: 01:53:34, 01:49:27, 01:30:52, fully typical). This weakens the pure "Backup_FULL I/O
-- contention" hypothesis: if that were the driver, Wednesday should show the same elevation as Sun/Mon and
-- it doesn't. Monday's standout pattern (and Sunday's secondary one) is more specific than "any backup
-- day" -- a weekend-accumulated-fragmentation or weekend-traffic-driven explanation (ties to GITIN-1866's
-- confirmed weekend campaign traffic hitting CustomerPointsLog-adjacent paths) is at least as plausible as
-- backup contention, not yet distinguished. H4 (duration variability cause) stays open/unconfirmed --
-- Monday/Sunday-specific, not simply "Backup_FULL days."

-- === Zabbix "MSSQL: Get job status" master item — pasted by user, not run by this session, recorded for reference ===
-- Confirmed correct: uses msdb.dbo.sysjobservers.last_run_duration (job-level summary, not a raw sysjobhistory step row),
-- with an arithmetically-correct HHMMSS-to-seconds conversion. No bug found.
--
-- SELECT sj.name AS JobName, sj.enabled AS Enabled,
--        sjs.last_run_outcome AS RunStatus, sjs.last_outcome_message AS LastRunStatusMessage,
--        sjs.last_run_duration/10000*3600 + sjs.last_run_duration/100%100*60 + sjs.last_run_duration%100 AS RunDuration,
--        CASE sjs.last_run_date WHEN 0 THEN NULL ELSE msdb.dbo.agent_datetime(sjs.last_run_date,sjs.last_run_time) END AS LastRunDateTime,
--        sja.next_scheduled_run_date AS NextRunDateTime
-- FROM msdb..sysjobs AS sj
-- LEFT JOIN msdb..sysjobservers AS sjs ON sj.job_id = sjs.job_id
-- LEFT JOIN (SELECT job.job_id, max(act.session_id) AS s_id, max(act.next_scheduled_run_date) AS next_scheduled_run_date
--            FROM msdb..sysjobs AS job LEFT JOIN msdb..sysjobactivity AS act ON act.job_id = job.job_id
--            GROUP BY job.job_id) AS sja ON sja.job_id = sj.job_id
-- WHERE Enabled = 1

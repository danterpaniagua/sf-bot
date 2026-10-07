-- Event: 20260928_gitin2112-mantenimientoindices-backup-overlap (GITIN-2112)
-- Read-only investigation, except Q7 (retry-attempts mitigation, applied).
-- All timestamps returned by these queries are GMT (server timezone) -- convert -3h for ART.

-- Q1: index maintenance execution detail, full weekend window
USE PNSSRL;
SELECT
    id_tablas_modulos, indexid, nombre_indice, filas, fragmentacion,
    ejecucion AS inicio,
    CASE
        WHEN fin_reindexado IS NOT NULL THEN 'REBUILD'
        WHEN fin_indexdefrag IS NOT NULL THEN 'REORGANIZE'
        ELSE 'SKIPPED (bajo umbral de fragmentación)'
    END AS accion,
    COALESCE(fin_reindexado, fin_indexdefrag, fin_ue) AS fin,
    DATEDIFF(SECOND, ejecucion, COALESCE(fin_reindexado, fin_indexdefrag, fin_ue)) AS duracion_segundos
FROM PNSSRL_DetallesEjecucionTablasModulos
WHERE ejecucion >= '2026-09-25 00:00:00' AND ejecucion < '2026-09-28 06:00:00'
ORDER BY duracion_segundos DESC;
-- Result: data/detalles_ejecucion_weekend_20260925_20260928.txt

-- Q2: job outcome history
USE msdb;
SELECT j.name AS job_name, h.run_date, h.run_time, h.run_duration, h.run_status, h.message
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobhistory h ON j.job_id = h.job_id
WHERE j.name = 'PNSSRL_MantenimientoIndices' AND h.step_id = 0
  AND h.run_date BETWEEN 20260925 AND 20260928
ORDER BY h.run_date, h.run_time;
-- Result: data/sysjobhistory_outcome_20260925_20260928.txt

-- Q3: step-level detail for the failed run + schedule definition
USE msdb;
SELECT h.step_id, h.step_name, h.run_date, h.run_time, h.run_duration, h.run_status, h.message
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobhistory h ON j.job_id = h.job_id
WHERE j.name = 'PNSSRL_MantenimientoIndices' AND h.run_date = 20260926
ORDER BY h.step_id;

SELECT s.name AS schedule_name, s.freq_type, s.freq_interval, s.freq_recurrence_factor,
       s.active_start_time, s.enabled
FROM msdb.dbo.sysschedules s
WHERE s.schedule_id = 23;
-- Result: data/sysjobhistory_steps_and_schedule_20260926.txt
-- freq_interval=86 = 64(Sat)+16(Thu)+4(Tue)+2(Mon) -> Mon/Tue/Thu/Sat only

-- Q4: SQL Server error log, Saturday failure window
USE master;
EXEC xp_readerrorlog 0, 1, N'', N'', '2026-09-26 09:00:00', '2026-09-26 09:20:00', N'desc';
-- Result: data/xp_readerrorlog_20260926_0900_0920.txt
-- Two BackupToUrl inits (09:00:01, 09:10:00.790) + "Long Sync IO" warning at 09:10:07.010

-- Q5: backup history, full weekend (ORIGINAL - 515 rows, NOT fully persisted, see
--     investigation.md "Evidence gap" -- only re-run if the complete set is needed again)
USE msdb;
SELECT
    bs.database_name, bs.type AS tipo_backup, bs.backup_start_date AS inicio_gmt,
    bs.backup_finish_date AS fin_gmt,
    DATEDIFF(SECOND, bs.backup_start_date, bs.backup_finish_date) AS duracion_segundos,
    bs.backup_size / 1024.0 / 1024.0 / 1024.0 AS tamano_gb,
    bmf.physical_device_name
FROM msdb.dbo.backupset bs
JOIN msdb.dbo.backupmediafamily bmf ON bs.media_set_id = bmf.media_set_id
WHERE bs.database_name = 'SmartFran.Solution.SmartLoyalty'
  AND bs.backup_start_date >= '2026-09-25 00:00:00'
  AND bs.backup_start_date <  '2026-09-28 12:00:00'
ORDER BY bs.backup_start_date;
-- Result (partial only): data/backupset_friday_saturday_PARTIAL_20260925_20260926.txt

-- Q6: backup history, Monday's successful run window (comparison)
USE msdb;
SELECT
    bs.database_name, bs.type AS tipo_backup, bs.backup_start_date AS inicio_gmt,
    bs.backup_finish_date AS fin_gmt,
    DATEDIFF(SECOND, bs.backup_start_date, bs.backup_finish_date) AS duracion_segundos,
    bs.backup_size / 1024.0 / 1024.0 / 1024.0 AS tamano_gb,
    bmf.physical_device_name
FROM msdb.dbo.backupset bs
JOIN msdb.dbo.backupmediafamily bmf ON bs.media_set_id = bmf.media_set_id
WHERE bs.database_name = 'SmartFran.Solution.SmartLoyalty'
  AND bs.backup_start_date >= '2026-09-28 08:50:00'
  AND bs.backup_start_date <  '2026-09-28 11:20:00'
ORDER BY bs.backup_start_date;
-- Result: data/backupset_monday_20260928_run_window.txt
-- Finding: Monday's log backups during the same job window were LARGER than Saturday's
-- (15.4GB/9.87GB/9.54GB/8.38GB vs Saturday's 7.56GB) with no failure -- weakens the
-- backup-contention theory, see investigation.md "Ruled out".

-- Q7: MITIGATION APPLIED - retry attempts on Step 1 (safety net, not root-cause fix)
USE msdb;
EXEC dbo.sp_update_jobstep
    @job_name = N'PNSSRL_MantenimientoIndices',
    @step_id = 1,
    @retry_attempts = 2,
    @retry_interval = 5;

-- Q8: verification of Q7 (never trust "Commands completed successfully" alone - GITIN-2061 precedent)
USE msdb;
SELECT s.step_id, s.step_name, s.retry_attempts, s.retry_interval
FROM msdb.dbo.sysjobsteps s
JOIN msdb.dbo.sysjobs j ON s.job_id = j.job_id
WHERE j.name = 'PNSSRL_MantenimientoIndices' AND s.step_id = 1;
-- Confirmed: retry_attempts=2, retry_interval=5

-- Q9: error log for Monday's run window -- checks whether it also produced a "Long Sync IO"
-- warning without failing.
USE master;
EXEC xp_readerrorlog 0, 1, N'', N'', '2026-09-28 09:00:00', '2026-09-28 11:20:00', N'desc';
-- Result: data/xp_readerrorlog_monday_20260928_0900_1120.txt
-- Finding: 3x "Long Sync IO" warnings (09:50:04 GMT) with no failure -- confirms the warning is
-- routine noise, not diagnostic. ALSO surfaced DBCC CHECKDB running 07:00-10:02:36 GMT (3h44s),
-- previously unknown, missed by Q10's narrower time window.

-- Q10: all jobs starting in a 30-min bracket around the failure/success windows, both days
USE msdb;
SELECT j.name AS job_name, h.run_date, h.run_time, h.run_duration, h.run_status, h.step_id, h.step_name
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobhistory h ON j.job_id = h.job_id
WHERE h.run_date = 20260926 AND h.run_time BETWEEN 083000 AND 092000
ORDER BY h.run_time, j.name, h.step_id;
-- (repeat with run_date = 20260928 for the comparison)
-- Results: data/sysjobhistory_allJobs_saturday_20260926_0830_0920.txt,
--          data/sysjobhistory_allJobs_monday_20260928_0830_0920.txt
-- Gap: this window-restricted query missed CHECKDB entirely (started 07:00 GMT, outside the
-- window, while still running through it) -- see Q11.

-- Q11: CHECKDB job history, unrestricted time window, both days (closes Q10's blind spot)
USE msdb;
SELECT j.name AS job_name, h.run_date, h.run_time, h.run_duration, h.run_status, h.step_id, h.step_name
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobhistory h ON j.job_id = h.job_id
WHERE j.name LIKE '%CHECKDB%'
  AND h.run_date IN (20260926, 20260928)
ORDER BY h.run_date, h.run_time;
-- Result: data/sysjobhistory_checkdb_20260926_20260928.txt
-- Finding: CHECKDB ran ONLY on Monday (succeeded) -- not scheduled on Saturday at all. Monday
-- therefore had MORE heavy concurrent load overall (CHECKDB + bigger log backups + same
-- companion-job overlap) and still succeeded -- no load-correlates-with-failure pattern found.

-- Event: 20260815_gestion_sql_log_full (GITIN-1864)
-- Commands are grouped by phase: Investigation / Audit / Remediation
-- ⚠️ ACTION commands are clearly marked

-- === INVESTIGATION ===

-- C1 — Recovery model + log reuse wait reason
SELECT
    name,
    recovery_model_desc,
    log_reuse_wait_desc,
    state_desc
FROM sys.databases
WHERE name = 'GESTION';
-- OUTPUT (2026-08-15):
-- GESTION    FULL    LOG_BACKUP    ONLINE

-- C2 — Log space used %
DBCC SQLPERF(LOGSPACE);
-- OUTPUT (2026-08-15), before fix:
-- master     1.992188   33.45588   0
-- tempdb     0.7421875  47.89474   0
-- model      0.7421875  45.72368   0
-- msdb       19.61719   6.665671   0
-- GESTION    9265.367   100        0   <- log fully consumed

-- C3 — Log file size / growth settings
USE GESTION;
GO
SELECT
    name AS logical_name,
    physical_name,
    size/128.0 AS size_MB,
    max_size,
    growth,
    is_percent_growth
FROM sys.database_files
WHERE type_desc = 'LOG';
-- OUTPUT (2026-08-15):
-- ROM_Log    C:\Smartfran\DATA\GESTION_log.ldf    9265.375000    1280000    10    1
-- (max_size 1,280,000 pages ~= 9.77 GB; log was at ~92.6% of its own cap)

-- === AUDIT ===

-- C4 — Backup history: checks for any log (L) backups vs full (D) backups
SELECT
    database_name,
    backup_start_date,
    backup_finish_date,
    type
FROM msdb.dbo.backupset
WHERE database_name = 'GESTION'
ORDER BY backup_start_date DESC;
-- OUTPUT (2026-08-15): full history back to 2019-04-07 — every row type 'D' (full backup).
-- Zero 'L' (log) backups ever recorded for GESTION.

-- C5 — Open/long-running transactions holding the log open
SELECT
    dt.database_transaction_begin_time,
    dt.database_transaction_log_bytes_used,
    st.text
FROM sys.dm_tran_database_transactions dt
JOIN sys.dm_tran_session_transactions st2 ON dt.transaction_id = st2.transaction_id
JOIN sys.dm_exec_connections ec ON st2.session_id = ec.session_id
CROSS APPLY sys.dm_exec_sql_text(ec.most_recent_sql_handle) st
WHERE dt.database_id = DB_ID('GESTION');
-- OUTPUT (2026-08-15): 0 rows — no open transaction holding the log open.

-- C6 — Disk free space on the volume hosting GESTION's data/log files
SELECT DISTINCT
    vs.volume_mount_point,
    vs.total_bytes/1048576 AS total_MB,
    vs.available_bytes/1048576 AS free_MB
FROM sys.master_files mf
CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) vs
WHERE mf.database_id = DB_ID('GESTION');
-- OUTPUT (2026-08-15):
-- C:\    228433 MB total    126682 MB free (~123.8 GB free)

-- C7 — SQL Agent job history for any log-backup job
SELECT
    j.name AS job_name,
    h.run_date,
    h.run_time,
    h.run_status,
    h.message
FROM msdb.dbo.sysjobhistory h
JOIN msdb.dbo.sysjobs j ON h.job_id = j.job_id
WHERE j.name LIKE '%GESTION%' OR j.name LIKE '%log%backup%'
ORDER BY h.run_date DESC, h.run_time DESC;
-- OUTPUT (2026-08-15): 0 rows — no SQL Agent job matching GESTION/log backup has ever existed on this instance.

-- === REMEDIATION ===

-- ⚠️ C8 — Switch off unused FULL recovery model, force log truncation
USE master;
GO
ALTER DATABASE GESTION SET RECOVERY SIMPLE;
GO
USE GESTION;
GO
CHECKPOINT;
GO
-- OUTPUT (2026-08-15): "Command(s) completed successfully."

-- C9 — Verification: confirm log truncated
DBCC SQLPERF(LOGSPACE);
-- OUTPUT (2026-08-15), after fix:
-- GESTION    9265.367    9.112289    0   <- dropped from 100% to 9.11%

-- C10 — Manual confirmation (no query): Gestion application started successfully after the fix.

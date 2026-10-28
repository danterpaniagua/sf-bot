-- Read-only. Run on SFCG-DB01 (SQL Server on GMT, UTC+0). Settles the Backup_FULL days/time contradiction
-- between loyalty/docs/task_operator_tasks.md and loyalty/docs/infrastructure.md.

-- 1. Job schedules (freq_interval is a bitmask for weekly jobs: 1 Sun, 2 Mon, 4 Tue, 8 Wed, 16 Thu, 32 Fri, 64 Sat)
SELECT j.name AS job, j.enabled AS job_enabled, s.name AS schedule, s.enabled AS schedule_enabled,
       s.freq_type, s.freq_interval, s.freq_recurrence_factor, s.active_start_time
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobschedules js ON js.job_id = j.job_id
JOIN msdb.dbo.sysschedules s ON s.schedule_id = js.schedule_id
WHERE j.name LIKE '%Backup%' OR j.name LIKE '%Mantenimiento%'
ORDER BY j.name;

-- 2. Full backups actually taken, last 30 days (type D = full)
SELECT database_name, backup_start_date, backup_finish_date,
       DATENAME(weekday, backup_start_date) AS weekday_gmt,
       DATEDIFF(minute, backup_start_date, backup_finish_date) AS minutes
FROM msdb.dbo.backupset
WHERE type = 'D' AND backup_start_date >= DATEADD(day, -30, GETDATE())
ORDER BY backup_start_date DESC;

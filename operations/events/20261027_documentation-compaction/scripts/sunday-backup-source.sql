-- Read-only. Run on SFCG-DB01 (SQL Server on GMT, UTC+0).
-- Who or what takes the extra instantaneous full backup of every database on Sundays at ~11:31-11:41 GMT.

SELECT bs.database_name, bs.backup_start_date, bs.backup_finish_date, bs.type, bs.is_copy_only,
       bs.user_name, bs.software_name, bs.machine_name, bs.backup_size, bs.compressed_backup_size,
       bmf.device_type, bmf.physical_device_name
FROM msdb.dbo.backupset bs
JOIN msdb.dbo.backupmediafamily bmf ON bmf.media_set_id = bs.media_set_id
WHERE bs.type = 'D'
  AND bs.backup_start_date >= DATEADD(day, -35, GETDATE())
  AND (   (DATEPART(weekday, bs.backup_start_date) = DATEPART(weekday, '2026-10-25')
           AND CONVERT(time, bs.backup_start_date) BETWEEN '11:00' AND '12:00')
       OR bs.backup_start_date >= '2026-10-28 09:00' AND bs.backup_start_date < '2026-10-28 09:10')
ORDER BY bs.backup_start_date DESC, bs.database_name;

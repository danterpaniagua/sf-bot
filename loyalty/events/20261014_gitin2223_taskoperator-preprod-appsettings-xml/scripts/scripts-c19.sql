-- Event: 20261014_gitin2223_taskoperator-preprod-appsettings-xml (GITIN-2223)
-- C19 - SOLO LECTURA. Hipotesis "tamano del log": si el log de transacciones de la base PREPROD esta lleno o no puede reutilizarse, los UPDATE se cuelgan o fallan para TODAS las sesiones.
--       Se corre junto con C16 (bloqueos / transacciones abiertas) mientras el problema esta presente.
SET NOCOUNT ON;
GO
PRINT '== 1) hora del servidor';
SELECT SYSDATETIMEOFFSET() AS ahora_con_zona;
GO
PRINT '== 2) uso del log por base (Log Size MB, Log Space Used %)';
DBCC SQLPERF(LOGSPACE);
GO
PRINT '== 3) por que el log no se puede reutilizar (log_reuse_wait_desc: ACTIVE_TRANSACTION = una transaccion abierta lo retiene; LOG_BACKUP = falta backup de log)';
SELECT name, recovery_model_desc, log_reuse_wait_desc, state_desc FROM sys.databases WHERE name LIKE 'SmartFran%' ORDER BY name;
GO
PRINT '== 4) archivos de log: tamano, crecimiento y tope';
SELECT DB_NAME(database_id) AS base, name, CAST(size AS bigint) * 8 / 1024 AS tamano_mb,
       CASE is_percent_growth WHEN 1 THEN CONCAT(growth, ' %') ELSE CONCAT(CAST(growth AS bigint) * 8 / 1024, ' MB') END AS crecimiento,
       CASE max_size WHEN -1 THEN 'sin tope' ELSE CONCAT(CAST(max_size AS bigint) * 8 / 1024, ' MB') END AS tope
FROM sys.master_files WHERE type_desc = 'LOG' AND DB_NAME(database_id) LIKE 'SmartFran%' ORDER BY base;
GO
PRINT '== 5) espacio libre en el disco de cada archivo de log (MB)';
SELECT DISTINCT DB_NAME(f.database_id) AS base, v.volume_mount_point, v.available_bytes / 1048576 AS libre_mb
FROM sys.master_files f CROSS APPLY sys.dm_os_volume_stats(f.database_id, f.file_id) v
WHERE f.type_desc = 'LOG' AND DB_NAME(f.database_id) LIKE 'SmartFran%' ORDER BY base;
GO

-- GITIN-2053 — MobileAppService load-test errors, 2026-09-15
-- Checking whether the 06:00-08:00 UTC TIMEOUT spike (SFCG-MOBI-01, isolated —
-- SFCG-MOBI-02 was deallocated the whole time) correlates with DB-side
-- housekeeping/ETL contention rather than MobileAppService capacity itself.

-- Q1: Blocking activity in PNSSRL for the window, resolve dbid to name
USE PNSSRL;
SELECT
    fecha_hora_captura,
    spid,
    blocked,
    status,
    cmd,
    loginame,
    hostname,
    program_name,
    DB_NAME(dbid) AS database_name,
    lastwaittype,
    waitresource,
    comando_ejecutado
FROM PNSSRL_AuditSysprocesses
WHERE fecha_hora_captura BETWEEN '2026-09-15 05:45:00' AND '2026-09-15 08:15:00'
  AND blocked <> 0
ORDER BY fecha_hora_captura;

-- Q2: Sessions running against SmartFran.Solution.SmartLoyalty in the same
-- window, to see what was actually executing (not just what was blocked)
USE PNSSRL;
SELECT
    fecha_hora_captura,
    spid,
    cpu,
    status,
    cmd,
    loginame,
    hostname,
    program_name,
    lastwaittype,
    comando_ejecutado
FROM PNSSRL_AuditSysprocesses
WHERE fecha_hora_captura BETWEEN '2026-09-15 05:45:00' AND '2026-09-15 08:15:00'
  AND DB_NAME(dbid) = 'SmartFran.Solution.SmartLoyalty'
  AND status <> 'sleeping'
ORDER BY fecha_hora_captura, spid;

-- Q3a: Discover actual Etl.EtlOperationExecution columns before querying it
-- (Q3 as originally written guessed wrong column names — fix this first)
USE [SmartFran.Solution.SmartLoyalty];
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'Etl' AND TABLE_NAME = 'EtlOperationExecution'
ORDER BY ORDINAL_POSITION;

-- Q3b: Same discovery for EtlOperationConfig, to confirm the Id=6 assumption
-- for the CustomerPointsLog operation
USE [SmartFran.Solution.SmartLoyalty];
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'Etl' AND TABLE_NAME = 'EtlOperationConfig'
ORDER BY ORDINAL_POSITION;

-- Q3c: PNSSRL_MantenimientoIndices — does it always target
-- Sml.CustomerPointsLog/IX_CustomerId, or rotate through multiple tables?
-- Uses PNSSRL_DetallesEjecucionTablasModulos per the dba-investigation skill's
-- capture-table reference.
USE PNSSRL;
SELECT *
FROM PNSSRL_DetallesEjecucionTablasModulos
WHERE ejecucion >= '2026-09-14 00:00:00'
ORDER BY ejecucion DESC;

-- Q4: Backup history for SmartFran.Solution.SmartLoyalty around the window —
-- rules out (or confirms) a backup as a contributing factor, any backup type
USE msdb;
SELECT
    bs.database_name,
    bs.backup_start_date,
    bs.backup_finish_date,
    DATEDIFF(SECOND, bs.backup_start_date, bs.backup_finish_date) AS duration_seconds,
    CASE bs.type
        WHEN 'D' THEN 'Full'
        WHEN 'I' THEN 'Differential'
        WHEN 'L' THEN 'Log'
        ELSE bs.type
    END AS backup_type,
    bmf.physical_device_name
FROM msdb.dbo.backupset bs
JOIN msdb.dbo.backupmediafamily bmf ON bs.media_set_id = bmf.media_set_id
WHERE bs.database_name = 'SmartFran.Solution.SmartLoyalty'
  AND bs.backup_start_date BETWEEN '2026-09-15 04:00:00' AND '2026-09-15 09:00:00'
ORDER BY bs.backup_start_date;

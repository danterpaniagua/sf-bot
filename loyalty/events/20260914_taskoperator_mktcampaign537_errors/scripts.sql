-- Event: 20260914_taskoperator_mktcampaign537_errors (GITIN-2036)
-- Reported window (user, local UTC-3): 04:10-06:55
-- Confirmed actual date from pasted TaskOperatorService log: 2026-09-14 (not 09-13 as first reported)
-- Server time (GMT/UTC+0): 07:10-09:55 UTC, 2026-09-14

-- === Q1 - Full Sch.TaskEvent history for ActionId 2508 / MktCampaignId 537, window + buffer ===
USE [SmartFran.Solution.SmartLoyalty];

SELECT
    te.Id,
    te.JobId,
    te.TaskId,
    te.StepId,
    te.Job_Name,
    te.Task_ExecuteOn,
    te.Task_ExecutionStarted,
    te.Task_Done,
    te.Task_Failed,
    te.Task_CanceledDate,
    te.Task_CanceledNote,
    te.Step_Command,
    te.Step_Params,
    te.EventCode,
    te.EventData,
    te.EventDate,
    te.Operator
FROM Sch.TaskEvent te
WHERE te.Job_Name LIKE '%MktCampaignId: 537%'
  AND te.EventDate BETWEEN '2026-09-14 06:30:00' AND '2026-09-14 10:30:00'
ORDER BY te.EventDate ASC;

-- === Q2 - Current live schedule for PNSSRL_MantenimientoIndices (confirm, not assume, per GITIN-1981) ===
USE msdb;

SELECT
    j.name AS JobName,
    j.enabled AS JobEnabled,
    s.name AS ScheduleName,
    s.enabled AS ScheduleEnabled,
    s.freq_type,
    s.freq_interval,
    s.active_start_time,
    s.active_end_time
FROM sysjobs j
JOIN sysjobschedules js ON js.job_id = j.job_id
JOIN sysschedules s ON s.schedule_id = js.schedule_id
WHERE j.name = 'PNSSRL_MantenimientoIndices';

-- === Q3 - Actual run history 2026-09-14 for the index-rebuild job and any backup-named job ===
USE msdb;

SELECT
    j.name AS JobName,
    h.run_date,
    h.run_time,
    h.run_duration,
    h.run_status,   -- 0=Failed 1=Succeeded 2=Retry 3=Canceled 4=InProgress
    h.step_id,
    h.step_name,
    h.message
FROM sysjobhistory h
JOIN sysjobs j ON j.job_id = h.job_id
WHERE h.run_date = 20260914
  AND (j.name LIKE '%MantenimientoIndices%' OR j.name LIKE '%Backup%')
ORDER BY j.name, h.run_time, h.step_id;

-- === Q4 - PNSSRL_AuditSysprocesses data availability check for the window (skill workflow step 3) ===
USE PNSSRL;

SELECT
    MIN(fecha_hora_captura) AS primer_snapshot,
    MAX(fecha_hora_captura) AS ultimo_snapshot,
    COUNT(DISTINCT fecha_hora_captura) AS snapshots_totales
FROM PNSSRL_AuditSysprocesses
WHERE fecha_hora_captura BETWEEN '2026-09-14 07:10:00' AND '2026-09-14 09:55:00';

-- Q3/Q4 results confirmed (data/q3_q4_jobhistory_and_availability_20260914.txt):
--   PNSSRL_MantenimientoIndices ran 06:15:00-~10:22:29 UTC (4h07m29s) - encloses the whole error window.
--   Reschedule to 08:00 UTC from GITIN-1981 was never applied - job still starts 06:15 UTC.
--   AuditSysprocesses: 33 snapshots, 07:11:00-09:51:00 UTC, ~every 4.8 min - enough to cross-reference.

-- === Q5 - Blocking chain in the error window: any blocked session, with its blocker's live command ===
USE PNSSRL;

;WITH blocked_rows AS (
    SELECT fecha_hora_captura, spid, blocked, hostname, program_name, loginame, lastwaittype, status, cmd
    FROM PNSSRL_AuditSysprocesses
    WHERE fecha_hora_captura BETWEEN '2026-09-14 07:10:00' AND '2026-09-14 09:55:00'
      AND blocked <> 0
)
SELECT
    b.fecha_hora_captura,
    b.spid            AS blocked_spid,
    b.hostname         AS blocked_hostname,
    b.program_name     AS blocked_program,
    b.loginame         AS blocked_login,
    b.lastwaittype      AS blocked_waittype,
    b.blocked          AS head_blocker_spid,
    hb.hostname        AS blocker_hostname,
    hb.program_name    AS blocker_program,
    hb.loginame        AS blocker_login,
    hb.status          AS blocker_status,
    hb.comando_ejecutado AS blocker_command
FROM blocked_rows b
LEFT JOIN PNSSRL_AuditSysprocesses hb
    ON hb.fecha_hora_captura = b.fecha_hora_captura
   AND hb.spid = b.blocked
ORDER BY b.fecha_hora_captura, b.spid;
-- Look specifically for blocked_hostname = 'SFCG-TO-01' (or blocked_login = 'sfsqlusr') rows,
-- and check whether blocker_command is an ALTER INDEX REBUILD/REORGANIZE statement.

-- === Q6 - Direct view of SFCG-TO-01's own sessions across the window, regardless of blocked flag ===
USE PNSSRL;

SELECT
    fecha_hora_captura,
    spid,
    blocked,
    status,
    lastwaittype,
    cmd,
    comando_ejecutado
FROM PNSSRL_AuditSysprocesses
WHERE fecha_hora_captura BETWEEN '2026-09-14 07:10:00' AND '2026-09-14 09:55:00'
  AND (hostname = 'SFCG-TO-01' OR loginame = 'sfsqlusr')
ORDER BY fecha_hora_captura, spid;

-- Q5/Q6 results confirmed (data/q5_q6_blocking_chain_confirmed_20260914.txt):
--   spid 62 (SFCG-TO-01 / sfsqlusr = TaskOperatorService) blocked by spid 77's
--   ALTER INDEX REBUILD on Sml.CustomerPointsLog, near-continuously 07:26-09:51 UTC.
--   Root cause of the timeouts is CONFIRMED, not just correlated.
--   Also found: Query084-sql.xml (TaskOperatorService) has a 'completeCustomersOfParaguay'
--   LoyaltyType mode filtering C.CountryId = 9 - structural support for user's claim that
--   a campaign targets new Paraguay customers, but not yet confirmed this is campaign 537
--   (user said "536" once - flagged as likely slip, unconfirmed either way).

-- === Q7 - New Paraguay customers created in the error window: volume and pattern ===
USE [SmartFran.Solution.SmartLoyalty];

SELECT
    c.Id AS CustomerId,
    c.CreatedDate,
    c.Country_Id,
    p.FirstName,
    p.LastName,
    p.Email,
    p.UidCode AS DocumentType,
    p.UidSerie AS DocumentNumber
FROM Sml.Customer c WITH (NOLOCK)
INNER JOIN Sml.Person p WITH (NOLOCK) ON c.Id = p.Id
WHERE c.CreatedDate BETWEEN '2026-09-14 07:00:00' AND '2026-09-14 10:00:00'
  AND c.Country_Id = 9
ORDER BY c.CreatedDate ASC;

-- === Q8 - Schema discovery: any registration-source/channel column on Customer or Person? ===
USE [SmartFran.Solution.SmartLoyalty];

SELECT TABLE_SCHEMA, TABLE_NAME, COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'Sml'
  AND TABLE_NAME IN ('Customer', 'Person', 'CustomerCard', 'Card')
  AND (COLUMN_NAME LIKE '%Source%' OR COLUMN_NAME LIKE '%Channel%' OR COLUMN_NAME LIKE '%Platform%'
       OR COLUMN_NAME LIKE '%App%' OR COLUMN_NAME LIKE '%Ip%' OR COLUMN_NAME LIKE '%UserAgent%')
ORDER BY TABLE_NAME, COLUMN_NAME;

-- Q7 result: 0 rows - no new Country_Id=9 customers created 07:00-10:00 UTC 2026-09-14.
-- Q8 result: Sml.Customer.RegistrationChannel (nvarchar) confirmed to exist.

-- === Q9 - Sch.Task/Sch.TaskEvent history for ActionId 2508: backlog vs live-trigger check ===
USE [SmartFran.Solution.SmartLoyalty];

SELECT
    j.Id AS JobId, j.Name, j.ValidSince, j.ValidTo, j.DeactivatedDate,
    t.Id AS TaskId, t.ExecuteOn, t.ExecutionStarted, t.Done, t.Failed,
    t.CanceledDate, t.CanceledNote
FROM Sch.Job j
INNER JOIN Sch.Task t ON t.JobId = j.Id
WHERE j.Name LIKE '%ActionId: 2508%'
ORDER BY t.ExecuteOn DESC;

-- === Q10 - Full TaskEvent history for this job: error detail + EventData, last 72h ===
USE [SmartFran.Solution.SmartLoyalty];

SELECT
    te.Id, te.EventDate, te.EventCode, te.EventData, te.Task_Failed,
    te.Task_ExecuteOn, te.Task_ExecutionStarted, te.Task_Done,
    te.Step_Command, te.Step_Params
FROM Sch.TaskEvent te
WHERE te.Job_Name LIKE '%ActionId: 2508%'
  AND te.EventDate >= DATEADD(HOUR, -72, GETUTCDATE())
ORDER BY te.EventDate ASC;

-- === Q11 - Broader window: any Country_Id=9 customers created recently (last 7 days), not just today ===
USE [SmartFran.Solution.SmartLoyalty];

SELECT
    c.Id AS CustomerId, c.CreatedDate, c.RegistrationChannel,
    p.Email, p.UidCode AS DocumentType, p.UidSerie AS DocumentNumber
FROM Sml.Customer c WITH (NOLOCK)
INNER JOIN Sml.Person p WITH (NOLOCK) ON c.Id = p.Id
WHERE c.CreatedDate >= DATEADD(DAY, -7, GETUTCDATE())
  AND c.Country_Id = 9
ORDER BY c.CreatedDate DESC;

-- === Q12 - Edition/version check: is ONLINE index rebuild a real option here? ===
SELECT
    SERVERPROPERTY('Edition') AS Edition,
    SERVERPROPERTY('EngineEdition') AS EngineEdition,   -- 2=Standard, 3=Enterprise/Developer, 4=Express, 5=SQL DB, 6=DW, 8=Managed Instance
    SERVERPROPERTY('ProductVersion') AS ProductVersion,
    SERVERPROPERTY('ProductLevel') AS ProductLevel,
    SERVERPROPERTY('ProductUpdateLevel') AS ProductUpdateLevel;

USE [SmartFran.Solution.SmartLoyalty];

-- Enterprise/Developer-only features already persisted in this DB (won't show ONLINE rebuild
-- since it's not in use yet, but confirms whether any other edition-restricted feature is active)
SELECT feature_name FROM sys.dm_db_persisted_sku_features;

-- === Q13 - Is Sml.CustomerPointsLog partitioned? ===
USE [SmartFran.Solution.SmartLoyalty];

SELECT
    OBJECT_NAME(i.object_id) AS TableName,
    i.name AS IndexName,
    i.type_desc,
    p.partition_number,
    p.rows,
    ps.name AS PartitionSchemeOrFilegroup,
    CASE WHEN ps.type = 'PS' THEN 'Partition Scheme (table IS partitioned)'
         ELSE 'Single Filegroup (table is NOT partitioned)' END AS PartitioningStatus
FROM sys.partitions p
JOIN sys.indexes i ON p.object_id = i.object_id AND p.index_id = i.index_id
JOIN sys.data_spaces ps ON i.data_space_id = ps.data_space_id
WHERE i.object_id = OBJECT_ID('Sml.CustomerPointsLog')
ORDER BY i.index_id, p.partition_number;

-- === Q14 - Capture the live ALTER INDEX command for IX_CustomerId during the NEXT run of
--     PNSSRL_MantenimientoIndices (tonight, ~06:15-10:22 UTC on 2026-09-15), to confirm whether
--     it already scopes to a single partition or rebuilds the whole index across all partitions.
--     Run this THE MORNING AFTER (once PNSSRL_AuditSysprocesses has captured the run), not now -
--     querying it before the job runs will return zero rows.
USE PNSSRL;

SELECT DISTINCT
    fecha_hora_captura,
    spid,
    hostname,
    program_name,
    loginame,
    status,
    comando_ejecutado
FROM PNSSRL_AuditSysprocesses
WHERE comando_ejecutado LIKE '%IX_CustomerId%'
  AND comando_ejecutado LIKE '%CustomerPointsLog%'
  AND fecha_hora_captura BETWEEN '2026-09-15 06:00:00' AND '2026-09-15 11:00:00'
ORDER BY fecha_hora_captura;

-- === Q15 - Confirm exact parameters of PNSSRL_MantenimientoModulos (metadata is readable even
--     though the body is WITH ENCRYPTION - parameters are not hidden by encryption) ===
USE PNSSRL;

SELECT
    p.parameter_id,
    p.name AS ParameterName,
    t.name AS DataType,
    p.max_length,
    p.is_output
FROM sys.parameters p
JOIN sys.types t ON p.user_type_id = t.user_type_id
WHERE p.object_id = OBJECT_ID('dbo.PNSSRL_MantenimientoModulos')
ORDER BY p.parameter_id;

-- === Q16 - Search for a config/control table behind @modulo/@tabla (module -> table mapping) ===
USE PNSSRL;

SELECT
    s.name AS SchemaName,
    o.name AS ObjectName,
    o.type_desc
FROM sys.objects o
JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE o.type IN ('U', 'V')  -- tables and views only
  AND (o.name LIKE '%Modulo%' OR o.name LIKE '%MantenimientoIndices%' OR o.name LIKE '%Fillfactor%' OR o.name LIKE '%Fragmenta%')
ORDER BY o.name;

-- === Q17 - Schema of the execution-detail log table (run this first, columns not yet confirmed) ===
USE PNSSRL;

SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'PNSSRL_DetallesEjecucionTablasModulos'
ORDER BY ORDINAL_POSITION;

-- === Q18 - Dump the config/control table (small - module/table definitions, not encrypted) ===
USE PNSSRL;

SELECT TOP 200 *
FROM PNSSRL_TablasModulos
ORDER BY 1;

-- === Q19 - Execution detail for IX_CustomerId specifically, most recent runs first - this is the
--     answer to "did last night's run already scope to one partition, or the whole table?" without
--     needing to wait for tonight's run (Q14) - last night's (2026-09-14) run already completed ===
USE PNSSRL;

SELECT TOP 50
    id_tablas_modulos,
    indexid,
    nombre_indice,
    filas,
    fragmentacion,
    ejecucion,
    fin_reindexado,
    fin_indexdefrag,
    fin_ue,
    fecha_hora_captura
FROM PNSSRL_DetallesEjecucionTablasModulos
WHERE nombre_indice = 'IX_CustomerId'
ORDER BY fecha_hora_captura DESC;

-- === Q20 - Confirm exact partition_number -> boundary date mapping for sch_LogDate_Anual, so any
--     REBUILD PARTITION = n statement targets the correct (current year) partition, not a guess ===
USE [SmartFran.Solution.SmartLoyalty];

SELECT
    ps.name AS PartitionScheme,
    pf.name AS PartitionFunction,
    pf.boundary_value_on_right,   -- 1 = RANGE RIGHT, 0 = RANGE LEFT - affects which side of the boundary date belongs to which partition
    prv.boundary_id,
    prv.boundary_id + 1 AS partition_number_estimate,  -- partition_number is boundary_id+1 for RANGE RIGHT; verify against boundary_value_on_right
    prv.value AS BoundaryValue
FROM sys.partition_schemes ps
JOIN sys.partition_functions pf ON ps.function_id = pf.function_id
LEFT JOIN sys.partition_range_values prv ON pf.function_id = prv.function_id
WHERE ps.name = 'sch_LogDate_Anual'
ORDER BY prv.boundary_id;

-- === Q21 - Full schema of Sch.Job, looking for any recurrence-interval/active-hours/exclusion
--     config column beyond what we've already selected (Id, Name, ValidSince, ValidTo, DeactivatedDate) ===
USE [SmartFran.Solution.SmartLoyalty];

SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'Sch' AND TABLE_NAME = 'Job'
ORDER BY ORDINAL_POSITION;

-- === Q22 - Full row for JobId 168898 (ActionId 2508/MktCampaignId 537), all columns ===
USE [SmartFran.Solution.SmartLoyalty];

SELECT *
FROM Sch.Job
WHERE Id = 168898;

-- === Q23 - Is the fixed 5-minute, 24/7 cadence unique to this campaign, or how this job type
--     behaves generally? Compare against other MktAsignationPointActionManager jobs' own cadence ===
USE [SmartFran.Solution.SmartLoyalty];

SELECT
    j.Id AS JobId,
    j.Name,
    j.ValidSince,
    j.ValidTo,
    j.DeactivatedDate,
    COUNT(t.Id) AS TaskCount,
    MIN(t.ExecuteOn) AS FirstExecuteOn,
    MAX(t.ExecuteOn) AS LastExecuteOn,
    DATEDIFF(MINUTE, MIN(t.ExecuteOn), MAX(t.ExecuteOn)) / NULLIF(COUNT(t.Id) - 1, 0) AS AvgMinutesBetweenExecutions
FROM Sch.Job j
INNER JOIN Sch.Task t ON t.JobId = j.Id
WHERE j.Name LIKE 'MktAsignationPointActionManager%'
  AND j.Id <> 168898
GROUP BY j.Id, j.Name, j.ValidSince, j.ValidTo, j.DeactivatedDate
ORDER BY j.ValidSince DESC;

-- === Q24 - Is there an automated SQL Agent job that adds new yearly partition boundaries
--     (ALTER PARTITION FUNCTION ... SPLIT RANGE) for sch_LogDate_Anual / fn_partition_LogDate_Anual,
--     and if so, when does it run? ===
USE msdb;

SELECT
    j.name AS JobName,
    j.enabled AS JobEnabled,
    s.name AS ScheduleName,
    s.enabled AS ScheduleEnabled,
    s.freq_type,       -- 4=daily, 8=weekly, 16=monthly, 32=monthly relative
    s.freq_interval,
    s.freq_recurrence_factor,
    s.active_start_time,
    js.step_name,
    js.command
FROM sysjobs j
LEFT JOIN sysjobschedules jsch ON jsch.job_id = j.job_id
LEFT JOIN sysschedules s ON s.schedule_id = jsch.schedule_id
LEFT JOIN sysjobsteps js ON js.job_id = j.job_id
WHERE j.name LIKE '%artition%' OR j.name LIKE '%articion%' OR j.name LIKE '%LogDate%'
   OR js.command LIKE '%SPLIT RANGE%' OR js.command LIKE '%PARTITION FUNCTION%'
   OR js.command LIKE '%fn_partition_LogDate_Anual%' OR js.command LIKE '%sch_LogDate_Anual%'
ORDER BY j.name;

-- === Q25 - Since Q24 confirmed no automated job exists, check the partition function's own
--     create_date/modify_date as the best available proxy for "when was a boundary last added" ===
USE [SmartFran.Solution.SmartLoyalty];

SELECT
    name,
    function_id,
    type_desc,
    fanout,
    boundary_value_on_right,
    create_date,
    modify_date
FROM sys.partition_functions
WHERE name = 'fn_partition_LogDate_Anual';

-- === Q26 - Full picture: EVERY index maintained on Sml.CustomerPointsLog (id_tablas_modulos=292),
--     not just IX_CustomerId - needed before excluding the whole table from the daily job, so the
--     replacement step covers everything currently being maintained, not just the one index found
--     via the blocking correlation ===
USE PNSSRL;

SELECT
    indexid,
    nombre_indice,
    filas,
    fragmentacion,
    ejecucion,
    fin_reindexado,
    fin_indexdefrag,
    fin_ue,
    DATEDIFF(SECOND, ejecucion, COALESCE(fin_reindexado, fin_indexdefrag)) AS duration_seconds,
    fecha_hora_captura
FROM PNSSRL_DetallesEjecucionTablasModulos
WHERE id_tablas_modulos = 292
ORDER BY fecha_hora_captura DESC, indexid;

-- ============================================================================================
-- PROPOSED FIX (NOT YET APPLIED - review before running) - partition-scoped rebuild for
-- IX_CustomerId, replacing the encrypted job's full-table rebuild for this one table.
-- Rationale: ops.md action 4 / investigation.md H9-H11. Two parts, both needed together -
-- without Part 1, the encrypted job would just redo a full rebuild the same night regardless.
-- NOT independently tested in non-prod. Recommend a non-prod dry run if available, and close
-- monitoring of PNSSRL_DetallesEjecucionTablasModulos + Sml.CustomerPointsLog fragmentation
-- after first live application.
-- ============================================================================================

-- --- Part 1: Exclude Sml.CustomerPointsLog from the daily encrypted sweep ---
-- Leaves habilitado=1 on the assumption this keeps whatever stats-update step still runs for the
-- table; indexado/defragmentacion=0 should stop it being selected for rebuild/reorganize. This
-- interpretation is inferred from column names, NOT confirmed against the encrypted procedure's
-- actual logic (PNSSRL_MantenimientoModulos is WITH ENCRYPTION, unreadable - see GITIN-1981 H5).
USE PNSSRL;

UPDATE PNSSRL_TablasModulos
SET indexado = 0,
    defragmentacion = 0
WHERE id_tablas_modulos = 292;

-- Rollback if this doesn't behave as expected:
-- UPDATE PNSSRL_TablasModulos SET indexado = 1, defragmentacion = 1 WHERE id_tablas_modulos = 292;

-- --- Part 2: Partition-scoped rebuild of IX_CustomerId, active partition computed dynamically ---
-- so this doesn't silently rot when the year rolls over (no hardcoded "11").
USE [SmartFran.Solution.SmartLoyalty];

-- Safe, read-only check first - confirms which partition number will be targeted before the ALTER
-- INDEX below runs. Expect 11 through end of 2026 (per Q20's confirmed boundary values); should
-- auto-advance to 12 starting 2027 without any script change, as long as that boundary exists
-- (confirmed present through 2030 - see Q20/Q25, investigation.md's partition-maintenance note).
SELECT $PARTITION.fn_partition_LogDate_Anual(SYSDATETIMEOFFSET()) AS ActivePartitionNumber;

DECLARE @PartitionNumber INT = $PARTITION.fn_partition_LogDate_Anual(SYSDATETIMEOFFSET());

ALTER INDEX [IX_CustomerId]
ON [Sml].[CustomerPointsLog]
REBUILD PARTITION = @PartitionNumber;

-- --- Not included below, recommended as follow-on additions (see H11) ---
-- (a) Statistics update for the table, replicating the daily job's fin_ue step:
--       UPDATE STATISTICS [Sml].[CustomerPointsLog] [IX_CustomerId];  -- or WITH FULLSCAN if needed
-- (b) Light-touch reorganize check for the other 3 partition-aligned indexes (clustered,
--     IX_CustomerPointsLog_SaleId, IX_CustomerPointsLog_Points) - H11 confirmed they rarely need
--     action (near-zero rebuild/reorganize activity, fragmentation consistently 0-5%), but going
--     fully unmonitored isn't ideal long-term. A periodic (not necessarily daily) fragmentation
--     check would cover this without meaningfully adding to blocking risk.

-- === Q27 - Is MktCampaignId 537 the ONLY currently-active MktAsignationPointActionManager
--     campaign, or are there others running in parallel that could also be blocked? ===
USE [SmartFran.Solution.SmartLoyalty];

SELECT
    j.Id AS JobId,
    j.Name,
    j.ValidSince,
    j.ValidTo,
    j.DeactivatedDate
FROM Sch.Job j
WHERE j.Name LIKE 'MktAsignationPointActionManager%'
  AND j.DeactivatedDate IS NULL
  AND j.ValidSince <= SYSDATETIMEOFFSET()
  AND j.ValidTo >= SYSDATETIMEOFFSET()
ORDER BY j.ValidSince;

-- === Q28 - Broader check: any OTHER Sch.Job types (not just MktAsignationPointActionManager)
--     currently active that might also write to Sml.CustomerPointsLog? Looks at Step_Params/
--     Step_Command text from recent TaskEvent rows for any job touching this table by name. ===
USE [SmartFran.Solution.SmartLoyalty];

SELECT DISTINCT
    j.Id AS JobId,
    j.Name,
    j.ValidSince,
    j.ValidTo,
    j.DeactivatedDate
FROM Sch.Job j
WHERE j.DeactivatedDate IS NULL
  AND j.ValidSince <= SYSDATETIMEOFFSET()
  AND j.ValidTo >= SYSDATETIMEOFFSET()
  AND j.Name NOT LIKE 'MktAsignationPointActionManager%'
ORDER BY j.ValidSince DESC;

-- === Q29 - Validate "does TaskOperator reschedule each run one-at-a-time, or are tasks
--     pre-generated in bulk in advance?" - count not-yet-executed tasks for JobId 168898, and
--     check the previously-unexamined TimeTableId column ===
USE [SmartFran.Solution.SmartLoyalty];

SELECT
    COUNT(*) AS NotYetExecutedTaskCount,
    MIN(ExecuteOn) AS EarliestPending,
    MAX(ExecuteOn) AS LatestPending
FROM Sch.Task
WHERE JobId = 168898
  AND ExecutionStarted IS NULL;

SELECT DISTINCT TimeTableId
FROM Sch.Task
WHERE JobId = 168898;

-- === Q30 - Does Sch.TimeTable store an actual interval/window config, correcting/expanding H10
--     if so? Check its schema and the row for TimeTableId=168898 (same value as JobId, per Q29) ===
USE [SmartFran.Solution.SmartLoyalty];

SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'Sch' AND TABLE_NAME = 'TimeTable'
ORDER BY ORDINAL_POSITION;

SELECT *
FROM Sch.TimeTable
WHERE Id = 168898;

-- === Q31 - Does EtlDwGridoCustomerPointsLogProcessor (JobId 755) show the same blocking/timeout
--     symptom as ActionId 2508, independently confirming other processes are also affected? ===
USE [SmartFran.Solution.SmartLoyalty];

SELECT
    te.EventDate, te.EventCode, te.EventData, te.Task_Failed,
    te.Task_ExecuteOn, te.Task_ExecutionStarted, te.Task_Done
FROM Sch.TaskEvent te
WHERE te.JobId = 755
  AND te.EventDate >= DATEADD(DAY, -7, GETUTCDATE())
ORDER BY te.EventDate DESC;

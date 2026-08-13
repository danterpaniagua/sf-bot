-- #1: Tasks that never started, delayed >= 4h vs scheduled Task_ExecuteOn
-- Adapted from Front/SmlBackScript/Query/Query052-sql.xml (branch 1) in the local SmartLoyalty source.
-- Run against: SmartFran.Solution.SmartLoyalty
USE [SmartFran.Solution.SmartLoyalty];

DECLARE @pInicioBusqueda datetime, @pFechaHasta datetime, @pGetDate datetime;
SET @pInicioBusqueda = DATEADD(day, -7, GETDATE());
SET @pFechaHasta = CONVERT(date, GETDATE());
SET @pFechaHasta = DATEADD(ms, -3, DATEADD(day, 1, @pFechaHasta));
SET @pGetDate = GETDATE();

SELECT te.[TaskId] AS TaskID
      ,[job].[Name] AS Nombre
      ,CONVERT(varchar,[job].[ValidSince],20) AS Desde
      ,CONVERT(varchar,[job].[ValidTo],20) AS Hasta
      ,CONVERT(varchar,te.[Task_ExecuteOn],20) AS FechaProgramacion
      ,DATEDIFF(HOUR, te.[Task_ExecuteOn], @pGetDate) AS HorasDeRetraso
FROM [Sch].[TaskEvent] te
INNER JOIN [Sch].[Task] Task ON te.TaskId = Task.Id
INNER JOIN [Sch].[Job] job ON te.JobId = job.Id
WHERE Task.CanceledDate IS NULL
AND Task.DeactivatedDate IS NULL
AND te.[EventCode] = 'Created'
AND te.[Task_ExecuteOn] BETWEEN @pInicioBusqueda AND @pFechaHasta
AND DATEDIFF(HOUR, te.[Task_ExecuteOn], @pGetDate) >= 4
AND te.TaskId NOT IN (
    SELECT t.TaskId FROM [Sch].[TaskEvent] t
    WHERE te.[TaskId] = t.[TaskId]
    AND t.[EventCode] <> 'Created'
    AND t.[Task_ExecuteOn] BETWEEN @pInicioBusqueda AND @pFechaHasta
)
ORDER BY HorasDeRetraso DESC;

-- #2: Overdue tasks directly against Sch.Task, independent of whether any TaskEvent was ever written.
-- Narrowed to a 3-day window and excludes tasks whose latest event already shows a terminal state
-- (Ended/Canceled/Disabled) — v1 of this query had neither filter and returned 334k historical rows.
DECLARE @pWindowStart datetime = DATEADD(day, -3, GETDATE());

SELECT t.Id AS TaskID
      ,job.[Name] AS Nombre
      ,CONVERT(varchar, t.ExecuteOn, 20) AS FechaProgramacion
      ,DATEDIFF(HOUR, t.ExecuteOn, GETDATE()) AS HorasDeRetraso
      ,ISNULL(le.EventCode, 'SIN EVENTOS') AS UltimoEvento
FROM [Sch].[Task] t
INNER JOIN [Sch].[Job] job ON t.JobId = job.Id
OUTER APPLY (
    SELECT TOP 1 te.EventCode
    FROM [Sch].[TaskEvent] te
    WHERE te.TaskId = t.Id
    ORDER BY te.Id DESC
) le
WHERE t.CanceledDate IS NULL
AND t.DeactivatedDate IS NULL
AND t.ExecuteOn BETWEEN @pWindowStart AND GETDATE()
AND DATEDIFF(HOUR, t.ExecuteOn, GETDATE()) >= 4
AND (le.EventCode IS NULL OR le.EventCode NOT IN ('Ended', 'Canceled', 'Disabled'))
ORDER BY HorasDeRetraso DESC;

-- #3: Historical run duration per job, for the 12 jobs we're about to reschedule.
-- Used to order the reschedule (longer-running jobs first, per user priority) instead of guessing.
SELECT job.[Name] AS Nombre
      ,COUNT(*) AS Corridas
      ,AVG(DATEDIFF(second, te.Task_ExecutionStarted, te.Task_Done)) / 60.0 AS DuracionPromedioMin
      ,MAX(DATEDIFF(second, te.Task_ExecutionStarted, te.Task_Done)) / 60.0 AS DuracionMaxMin
FROM [Sch].[TaskEvent] te
INNER JOIN [Sch].[Job] job ON te.JobId = job.Id
WHERE te.EventCode = 'Ended'
AND te.Task_ExecutionStarted IS NOT NULL
AND te.Task_Done IS NOT NULL
AND te.Task_Done >= DATEADD(day, -30, GETDATE())
AND job.[Name] IN (
    'EtlDwGridoLocationProcessor','EtlDwGridoSurveyProcessor','EtlDwGridoCustomerProcessor',
    'EtlDwGridoSaleProcessor','EtlDwGridoCustomerSaleProcessor','EtlDwGridoBranchOfficeProcessor',
    'EtlSmlTarget','PromotionFilterProcessor','ExchangeOptionFilterProcessor','CancelOldOrderJob',
    'FixMissingArticleIdSaleDetailProcessor','AutoAcceptAccountRecovery'
)
GROUP BY job.[Name]
ORDER BY DuracionPromedioMin DESC;

-- #4: Cancel the 15 stale older duplicates (per job, keep only the latest stuck instance).
-- AutoAcceptAccountRecovery is hourly, not daily -- 6 stale instances, not 1.
UPDATE [Sch].[Task]
SET CanceledDate = GETDATE()
WHERE Id IN (
    339623, -- PromotionFilterProcessor (08-10, superseded by 339755)
    339617, -- ExchangeOptionFilterProcessor (08-10, superseded by 339745)
    339743, 339746, 339758, 339832, 339833, 339843, -- AutoAcceptAccountRecovery stale x6, superseded by 339847
    339620, -- CancelOldOrderJob (08-10, superseded by 339748)
    339621, -- FixMissingArticleIdSaleDetailProcessor (08-10, superseded by 339749)
    339622, -- EtlDwGridoSurveyProcessor (08-10, superseded by 339750)
    339619, -- EtlDwGridoLocationProcessor (08-10, superseded by 339747)
    339628, -- EtlDwGridoCustomerSaleProcessor (08-10, superseded by 339756)
    339627, -- EtlDwGridoBranchOfficeProcessor (08-10, superseded by 339754)
    339625  -- EtlSmlTarget (08-10, superseded by 339752)
);

-- #5: Reschedule the 12 remaining (latest instance per job), ordered by measured duration
-- (query #3), heaviest first, 1-minute stagger starting 2 minutes out.
-- Pattern per Other/SqlScript/Updates/v6.00/v6.00_ForceFirstExecutionOfTheTask.sql in source.
UPDATE [Sch].[Task] SET ExecuteOn = DATEADD(mi, 2, GETDATE())  WHERE Id = 339755; -- PromotionFilterProcessor (avg 118min/max 178min)
UPDATE [Sch].[Task] SET ExecuteOn = DATEADD(mi, 3, GETDATE())  WHERE Id = 339624; -- EtlDwGridoCustomerProcessor (avg 8.5min/max 118min)
UPDATE [Sch].[Task] SET ExecuteOn = DATEADD(mi, 4, GETDATE())  WHERE Id = 339631; -- EtlDwGridoSaleProcessor (avg 9.6min/max 65min)
UPDATE [Sch].[Task] SET ExecuteOn = DATEADD(mi, 5, GETDATE())  WHERE Id = 339756; -- EtlDwGridoCustomerSaleProcessor (avg 6.75min)
UPDATE [Sch].[Task] SET ExecuteOn = DATEADD(mi, 6, GETDATE())  WHERE Id = 339745; -- ExchangeOptionFilterProcessor (<1min)
UPDATE [Sch].[Task] SET ExecuteOn = DATEADD(mi, 7, GETDATE())  WHERE Id = 339747; -- EtlDwGridoLocationProcessor (<1min)
UPDATE [Sch].[Task] SET ExecuteOn = DATEADD(mi, 8, GETDATE())  WHERE Id = 339754; -- EtlDwGridoBranchOfficeProcessor (<1min)
UPDATE [Sch].[Task] SET ExecuteOn = DATEADD(mi, 9, GETDATE())  WHERE Id = 339749; -- FixMissingArticleIdSaleDetailProcessor (<1min)
UPDATE [Sch].[Task] SET ExecuteOn = DATEADD(mi, 10, GETDATE()) WHERE Id = 339752; -- EtlSmlTarget (<1min)
UPDATE [Sch].[Task] SET ExecuteOn = DATEADD(mi, 11, GETDATE()) WHERE Id = 339847; -- AutoAcceptAccountRecovery (<1min)
UPDATE [Sch].[Task] SET ExecuteOn = DATEADD(mi, 12, GETDATE()) WHERE Id = 339748; -- CancelOldOrderJob (<1min)
UPDATE [Sch].[Task] SET ExecuteOn = DATEADD(mi, 13, GETDATE()) WHERE Id = 339750; -- EtlDwGridoSurveyProcessor (<1min)

-- #6: Status check for the 12 rescheduled tasks -- read-only.
SELECT t.Id AS TaskID
      ,job.[Name] AS Nombre
      ,CONVERT(varchar, t.ExecuteOn, 20) AS ProximaEjecucion
      ,ISNULL(le.EventCode, 'SIN EVENTOS') AS UltimoEvento
      ,CONVERT(varchar, le.Task_ExecutionStarted, 20) AS Inicio
      ,CONVERT(varchar, le.Task_Done, 20) AS Fin
FROM [Sch].[Task] t
INNER JOIN [Sch].[Job] job ON t.JobId = job.Id
OUTER APPLY (
    SELECT TOP 1 te.EventCode, te.Task_ExecutionStarted, te.Task_Done
    FROM [Sch].[TaskEvent] te
    WHERE te.TaskId = t.Id
    ORDER BY te.Id DESC
) le
WHERE t.Id IN (339755, 339624, 339631, 339756, 339745, 339747, 339754, 339749, 339752, 339847, 339748, 339750)
ORDER BY t.ExecuteOn;

-- #7: Actual Sch.Task state (not TaskEvent copies) for the 12 stuck tasks -- read-only.
-- Determines which stored procedure applies: ReRunTask needs Done/CanceledDate/DeactivatedDate NOT NULL;
-- RescheduleTask needs ExecutionStarted/Done/DeactivatedDate all NULL.
SELECT t.Id AS TaskID
      ,job.[Name] AS Nombre
      ,t.ExecuteOn
      ,t.ExecutionStarted
      ,t.Done
      ,t.CanceledDate
      ,t.DeactivatedDate
FROM [Sch].[Task] t
INNER JOIN [Sch].[Job] job ON t.JobId = job.Id
WHERE t.Id IN (339755, 339624, 339631, 339756, 339745, 339747, 339754, 339749, 339752, 339847, 339748, 339750)
ORDER BY t.Id;

-- #8: Proper reschedule via the official ServicesIT tooling. All 12 have Done populated (query #7),
-- so [dbo].[ReRunTask] applies (creates a new Task row + fresh Created TaskEvent), not [dbo].[RescheduleTask].
-- Same heaviest-duration-first ordering as the earlier (failed) direct-UPDATE attempt.
-- DATEADD computed into a variable first -- inline expression as a named EXEC parameter errored
-- ("Incorrect syntax near 'mi'") on the user's client.
DECLARE @t1 DATETIMEOFFSET = DATEADD(mi, 2, GETDATE());
DECLARE @t2 DATETIMEOFFSET = DATEADD(mi, 3, GETDATE());
DECLARE @t3 DATETIMEOFFSET = DATEADD(mi, 4, GETDATE());
DECLARE @t4 DATETIMEOFFSET = DATEADD(mi, 5, GETDATE());
DECLARE @t5 DATETIMEOFFSET = DATEADD(mi, 6, GETDATE());
DECLARE @t6 DATETIMEOFFSET = DATEADD(mi, 7, GETDATE());
DECLARE @t7 DATETIMEOFFSET = DATEADD(mi, 8, GETDATE());
DECLARE @t8 DATETIMEOFFSET = DATEADD(mi, 9, GETDATE());
DECLARE @t9 DATETIMEOFFSET = DATEADD(mi, 10, GETDATE());
DECLARE @t10 DATETIMEOFFSET = DATEADD(mi, 11, GETDATE());
DECLARE @t11 DATETIMEOFFSET = DATEADD(mi, 12, GETDATE());
DECLARE @t12 DATETIMEOFFSET = DATEADD(mi, 13, GETDATE());

EXEC [dbo].[ReRunTask] @TaskId = 339755, @DateTime = @t1;  -- PromotionFilterProcessor
EXEC [dbo].[ReRunTask] @TaskId = 339624, @DateTime = @t2;  -- EtlDwGridoCustomerProcessor
EXEC [dbo].[ReRunTask] @TaskId = 339631, @DateTime = @t3;  -- EtlDwGridoSaleProcessor
EXEC [dbo].[ReRunTask] @TaskId = 339756, @DateTime = @t4;  -- EtlDwGridoCustomerSaleProcessor
EXEC [dbo].[ReRunTask] @TaskId = 339745, @DateTime = @t5;  -- ExchangeOptionFilterProcessor
EXEC [dbo].[ReRunTask] @TaskId = 339747, @DateTime = @t6;  -- EtlDwGridoLocationProcessor
EXEC [dbo].[ReRunTask] @TaskId = 339754, @DateTime = @t7;  -- EtlDwGridoBranchOfficeProcessor
EXEC [dbo].[ReRunTask] @TaskId = 339749, @DateTime = @t8;  -- FixMissingArticleIdSaleDetailProcessor
EXEC [dbo].[ReRunTask] @TaskId = 339752, @DateTime = @t9;  -- EtlSmlTarget
EXEC [dbo].[ReRunTask] @TaskId = 339847, @DateTime = @t10; -- AutoAcceptAccountRecovery
EXEC [dbo].[ReRunTask] @TaskId = 339748, @DateTime = @t11; -- CancelOldOrderJob
EXEC [dbo].[ReRunTask] @TaskId = 339750, @DateTime = @t12; -- EtlDwGridoSurveyProcessor

-- #9: All 12 EXECs failed with "Ya existe una tarea a fecha futuro..." -- find the blocking task
-- per job (ReRunTask's own duplicate-check condition) to see whether it's a normal next-occurrence
-- (already recovered) or another orphaned/stuck row from the same incident. Read-only.
SELECT src.Id AS OriginalStuckTaskID
      ,job.[Name] AS Nombre
      ,blocker.Id AS BlockingTaskID
      ,blocker.ExecuteOn AS BlockingExecuteOn
      ,blocker.ExecutionStarted
      ,blocker.Done
      ,(SELECT TOP 1 te.EventCode FROM [Sch].[TaskEvent] te WHERE te.TaskId = blocker.Id ORDER BY te.Id DESC) AS BlockingUltimoEvento
FROM [Sch].[Task] src
INNER JOIN [Sch].[Job] job ON src.JobId = job.Id
CROSS APPLY (
    SELECT TOP 1 t.*
    FROM [Sch].[Task] t
    WHERE t.JobId = src.JobId
    AND t.DeactivatedDate IS NULL
    AND t.CanceledDate IS NULL
    AND t.Done IS NULL
    AND t.ExecuteOn IS NOT NULL
    AND t.ExecutionStarted IS NULL
    ORDER BY t.ExecuteOn
) blocker
WHERE src.Id IN (339755, 339624, 339631, 339756, 339745, 339747, 339754, 339749, 339752, 339847, 339748, 339750)
ORDER BY src.Id;

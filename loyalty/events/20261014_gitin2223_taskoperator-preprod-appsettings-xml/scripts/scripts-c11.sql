-- Event: 20261014_gitin2223_taskoperator-preprod-appsettings-xml (GITIN-2223)
-- C11 - SOLO LECTURA. Sigue a C10: PREPROD si esta ejecutando tareas (el job 7947 corrio a las 10:00 y 11:00 -03:00 a horario; 14 iniciadas en 24 h),
--       la tarea 139102 tiene ExecuteOn = 2026-10-15 02:00 -03:00 (no 10:45) y una tarea del job 7965 termino con Failed=1 a las 13:02 UTC.
--       Este script identifica los jobs, su calendario, la tarea fallida y las tareas desactivadas por el "Service crashed" de las 12:04 UTC.
USE [SmartFran.Solution.SmartLoyalty-PREPROD];
GO
SET NOCOUNT ON;
PRINT '== 1) jobs de interes (nombre y vigencia)';
SELECT Id, Name, ValidSince, ValidTo, DeactivatedDate FROM Sch.Job WHERE Id IN (7996, 7947, 7965, 5249, 7995) ORDER BY Id;
GO
PRINT '== 2) calendario (TimeTable) de esos jobs';
SELECT Id, JobId, Enabled, ActiveStartDate, ActiveEndDate, Name, FrecuencyType, FrecuencyInterval, FrequencyRecurrenceFactor, FrecuencySubDayInterval
FROM Sch.TimeTable WHERE JobId IN (7996, 7947, 7965, 5249, 7995) ORDER BY JobId, Id;
GO
PRINT '== 3) las ultimas 6 tareas del job 7965 (la que fallo a las 13:02 UTC)';
SELECT TOP (6) Id, ExecuteOn, ExecutionStarted, Done, Failed, DeactivatedDate, DeactivateNote, CanceledDate, TimeTableId FROM Sch.Task WHERE JobId = 7965 ORDER BY Id DESC;
GO
PRINT '== 4) TaskEvent de la tarea fallida 139068';
SELECT TOP (20) Id, JobId, TaskId, StepId, Job_Name, Task_ExecuteOn, Task_ExecutionStarted, Task_Done FROM Sch.TaskEvent WHERE TaskId = 139068 ORDER BY Id;
GO
PRINT '== 5) tareas desactivadas en las ultimas 24 h, por nota (el reinicio por la configuracion rota)';
SELECT DeactivateNote, COUNT(*) AS tareas, MIN(DeactivatedDate) AS desde, MAX(DeactivatedDate) AS hasta
FROM Sch.Task WHERE DeactivatedDate >= DATEADD(HOUR, -24, SYSDATETIMEOFFSET()) GROUP BY DeactivateNote ORDER BY COUNT(*) DESC;
GO
PRINT '== 6) tareas fallidas en los ultimos 7 dias, por job';
SELECT JobId, COUNT(*) AS fallidas, MAX(ExecutionStarted) AS ultima FROM Sch.Task WHERE Failed = 1 AND ExecutionStarted >= DATEADD(DAY, -7, SYSDATETIMEOFFSET()) GROUP BY JobId ORDER BY COUNT(*) DESC;
GO
PRINT '== 7) tareas de 2026 vencidas y sin ejecutar (sin cancelar ni desactivar), con el nombre del job';
SELECT TOP (20) t.Id, t.JobId, j.Name, t.ExecuteOn, t.TimeTableId
FROM Sch.Task t LEFT JOIN Sch.Job j ON j.Id = t.JobId
WHERE t.ExecuteOn >= '2026-01-01' AND t.ExecuteOn <= SYSDATETIMEOFFSET() AND t.ExecutionStarted IS NULL AND t.Done IS NULL AND t.CanceledDate IS NULL AND t.DeactivatedDate IS NULL
ORDER BY t.ExecuteOn;
GO

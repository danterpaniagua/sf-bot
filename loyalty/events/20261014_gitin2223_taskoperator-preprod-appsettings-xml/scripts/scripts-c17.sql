-- Event: 20261014_gitin2223_taskoperator-preprod-appsettings-xml (GITIN-2223)
-- C17 - SOLO LECTURA. Verifica que la tarea 139102 (job 7996, InsigniaReconciliationJob), movida por el usuario a ExecuteOn = 2026-10-14 13:00 -03:00 (= 16:00 UTC), quedo
--       confirmada en la base y que el TaskOperator la ejecuta. Correr una vez ahora (para ver el cambio confirmado y cuanto falta) y otra vez 2 a 3 minutos despues de la hora de ExecuteOn.
USE [SmartFran.Solution.SmartLoyalty-PREPROD];
GO
SET NOCOUNT ON;
PRINT '== 1) hora del servidor y minutos que faltan para ExecuteOn de la tarea 139102 (negativo: ya vencio)';
SELECT SYSDATETIMEOFFSET() AS ahora_con_zona,
       (SELECT ExecuteOn FROM Sch.Task WITH (READCOMMITTED) WHERE Id = 139102) AS execute_on_confirmado,
       DATEDIFF(MINUTE, SYSDATETIMEOFFSET(), (SELECT ExecuteOn FROM Sch.Task WITH (READCOMMITTED) WHERE Id = 139102)) AS minutos_para_ejecutar;
GO
PRINT '== 2) la tarea 139102 y las ultimas 4 del job 7996 (lectura confirmada)';
SELECT TOP (4) Id, ExecuteOn, ExecutionStarted, Done, DATEDIFF(SECOND, ExecutionStarted, Done) AS segundos, Failed, DeactivatedDate, DeactivateNote, CanceledDate
FROM Sch.Task WITH (READCOMMITTED) WHERE JobId = 7996 ORDER BY Id DESC;
GO
PRINT '== 3) eventos de la tarea 139102 (TaskEvent)';
SELECT TOP (10) Id, JobId, TaskId, StepId, Task_ExecuteOn, Task_ExecutionStarted, Task_Done FROM Sch.TaskEvent WHERE TaskId = 139102 ORDER BY Id;
GO
PRINT '== 4) sesiones con transaccion abierta (necesita VIEW SERVER STATE; debe quedar vacio)';
SELECT s.session_id, s.login_name, s.host_name, s.program_name, s.open_transaction_count, s.last_request_start_time
FROM sys.dm_exec_sessions s WHERE s.open_transaction_count > 0 AND s.session_id <> @@SPID AND s.is_user_process = 1;
GO
PRINT '== 5) tareas iniciadas en la ultima hora (cualquier job)';
SELECT Id, JobId, ExecuteOn, ExecutionStarted, Done, Failed FROM Sch.Task WITH (READCOMMITTED) WHERE ExecutionStarted >= DATEADD(HOUR, -1, SYSDATETIMEOFFSET()) ORDER BY ExecutionStarted DESC;
GO

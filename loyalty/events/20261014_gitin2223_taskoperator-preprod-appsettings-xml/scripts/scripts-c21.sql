-- Event: 20261014_gitin2223_taskoperator-preprod-appsettings-xml (GITIN-2223)
-- C21 - SOLO LECTURA. Tras liberarse el bloqueo (C20: ninguna sesion con transaccion abierta): como quedo la fila que cambiaba la sesion de QA (tarea 139118) y las tareas del job 7996.
--       Lectura confirmada (READCOMMITTED); si el COMMIT se hizo el valor nuevo aparece, si fue ROLLBACK aparece el valor anterior.
USE [SmartFran.Solution.SmartLoyalty-PREPROD];
GO
SET NOCOUNT ON;
SELECT SYSDATETIMEOFFSET() AS ahora_con_zona;
GO
SELECT Id, JobId, ExecuteOn, ExecutionStarted, Done, Failed, DeactivatedDate, CanceledDate
FROM Sch.Task WITH (READCOMMITTED) WHERE JobId = 7996 ORDER BY Id DESC;
GO
SELECT COUNT(*) AS sesiones_con_transaccion_abierta FROM sys.dm_exec_sessions WHERE is_user_process = 1 AND open_transaction_count > 0 AND session_id <> @@SPID;
GO

-- Event: 20261014_gitin2223_taskoperator-preprod-appsettings-xml (GITIN-2223)
-- C15 - SOLO LECTURA. Resultado de la corrida forzada con C14 (job ETL 7965, tarea 139104) en PREPROD. Correr unos 3 a 5 minutos despues de C14.
USE [SmartFran.Solution.SmartLoyalty-PREPROD];
GO
SET NOCOUNT ON;
PRINT '== 1) hora del servidor';
SELECT SYSDATETIMEOFFSET() AS ahora_con_zona;
GO
PRINT '== 2) la tarea 139104 y las ultimas 4 del job 7965';
SELECT TOP (4) Id, ExecuteOn, ExecutionStarted, Done, DATEDIFF(SECOND, ExecutionStarted, Done) AS segundos, Failed, DeactivatedDate, DeactivateNote
FROM Sch.Task WHERE JobId = 7965 ORDER BY Id DESC;
GO
PRINT '== 3) ejecuciones de la operacion ETL 15 (PointsTransference): ultimas 5';
SELECT TOP (5) Id, TotalRows, Started, Completed, LowerLimit, UpperLimit, EtlOperation_Id FROM Etl.EtlOperationExecution WHERE EtlOperation_Id = 15 ORDER BY Id DESC;
GO
PRINT '== 4) log de esas ejecuciones: ultimas 8 filas (mensaje cortado a 300 caracteres; revisar antes de pegar)';
SELECT TOP (8) l.Id, l.Status, LEFT(l.StatusMessage, 300) AS mensaje, l.LastRun, l.EtlOperationExecution_Id
FROM Etl.EtlOperationExecutionLog l
WHERE l.EtlOperationExecution_Id IN (SELECT TOP (5) Id FROM Etl.EtlOperationExecution WHERE EtlOperation_Id = 15 ORDER BY Id DESC)
ORDER BY l.Id DESC;
GO
PRINT '== 5) tareas fallidas en las ultimas 2 horas (por job)';
SELECT JobId, COUNT(*) AS fallidas, MAX(ExecutionStarted) AS ultima FROM Sch.Task WHERE Failed = 1 AND ExecutionStarted >= DATEADD(HOUR, -2, SYSDATETIMEOFFSET()) GROUP BY JobId;
GO

-- Event: 20261014_gitin2223_taskoperator-preprod-appsettings-xml (GITIN-2223)
-- C10 - SOLO LECTURA. Por que TaskOperator de PREPROD no ejecuta tareas (QA movio ExecuteOn de la tarea 139102 a 2026-10-14 10:45 -03:00 y no se ejecuto).
-- Correr en la instancia de SFDEV02 con un login que tenga acceso (la cuenta de Windows usada en C3 no lo tiene).
-- v2: la primera version fallo con "Msg 206 datetimeoffset is incompatible with tinyint" (Done es una fecha, no un indicador; no se sabe el tipo de Failed).
--     Cada seccion va en su propio lote (GO) para que un error en una no frene las demas; la seccion 0 muestra los tipos de las columnas.
USE [SmartFran.Solution.SmartLoyalty-PREPROD];
GO
SET NOCOUNT ON;
PRINT '== 0) columnas y tipos de Sch.Task';
SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'Sch' AND TABLE_NAME = 'Task' ORDER BY ORDINAL_POSITION;
GO
PRINT '== 1) servidor y hora (con zona)';
SELECT @@SERVERNAME AS servidor, SYSDATETIMEOFFSET() AS ahora_con_zona, SYSUTCDATETIME() AS ahora_utc;
GO
PRINT '== 2) la tarea 139102 y las ultimas 10 del job 7996';
SELECT TOP (10) Id, ExecuteOn, ExecutionStarted, Done, Failed, DeactivatedDate, DeactivateNote, CanceledDate, CanceledNote, TimeTableId, JobId,
       CASE WHEN Id = 139102 THEN '<== tarea de QA' ELSE '' END AS marca
FROM Sch.Task WHERE JobId = 7996 OR Id = 139102 ORDER BY Id DESC;
GO
PRINT '== 3) tareas vencidas sin ejecutar (ExecuteOn <= ahora, ExecutionStarted y Done nulos, sin cancelar ni desactivar), por job: top 15';
SELECT TOP (15) JobId, COUNT(*) AS vencidas, MIN(ExecuteOn) AS la_mas_vieja, MAX(ExecuteOn) AS la_mas_nueva
FROM Sch.Task
WHERE ExecuteOn <= SYSDATETIMEOFFSET() AND ExecutionStarted IS NULL AND Done IS NULL AND CanceledDate IS NULL AND DeactivatedDate IS NULL
GROUP BY JobId ORDER BY COUNT(*) DESC;
GO
PRINT '== 4) actividad reciente: ultima vez que alguna tarea inicio, y cuantas en la ultima hora / 24 h';
SELECT MAX(ExecutionStarted) AS ultimo_inicio,
       SUM(CASE WHEN ExecutionStarted >= DATEADD(HOUR, -1, SYSDATETIMEOFFSET()) THEN 1 ELSE 0 END) AS iniciadas_ultima_hora,
       SUM(CASE WHEN ExecutionStarted >= DATEADD(HOUR, -24, SYSDATETIMEOFFSET()) THEN 1 ELSE 0 END) AS iniciadas_24h
FROM Sch.Task;
GO
PRINT '== 5) las 10 tareas que iniciaron mas recientemente';
SELECT TOP (10) Id, JobId, ExecuteOn, ExecutionStarted, Done, Failed FROM Sch.Task WHERE ExecutionStarted IS NOT NULL ORDER BY ExecutionStarted DESC;
GO
PRINT '== 6) comparacion: TEST02 (el entorno que funciona): ultimo inicio y actividad';
SELECT MAX(ExecutionStarted) AS ultimo_inicio_test02,
       SUM(CASE WHEN ExecutionStarted >= DATEADD(HOUR, -1, SYSDATETIMEOFFSET()) THEN 1 ELSE 0 END) AS iniciadas_ultima_hora_test02
FROM [SmartFran.Solution.SmartLoyalty-TEST02].Sch.Task;
GO
PRINT '== 6b) en TEST02, la tarea 196433 (job 8529) que QA movio a 10:44 -03:00 y las ultimas 5 del job';
SELECT TOP (5) Id, ExecuteOn, ExecutionStarted, Done, Failed, DeactivatedDate, CanceledDate, TimeTableId, JobId,
       CASE WHEN Id = 196433 THEN '<== tarea de QA en TEST02' ELSE '' END AS marca
FROM [SmartFran.Solution.SmartLoyalty-TEST02].Sch.Task WHERE JobId = 8529 OR Id = 196433 ORDER BY Id DESC;
GO
PRINT '== 7) columnas de las demas tablas del esquema Sch (solo nombres)';
SELECT TABLE_NAME, STRING_AGG(COLUMN_NAME, ', ') WITHIN GROUP (ORDER BY ORDINAL_POSITION) AS columnas
FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'Sch' AND TABLE_NAME <> 'Task' GROUP BY TABLE_NAME ORDER BY TABLE_NAME;
GO

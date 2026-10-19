-- Event: 20261014_gitin2223_taskoperator-preprod-appsettings-xml (GITIN-2223)
-- C12 - SOLO LECTURA. Sigue a C11: el job 7965 (EtlDwGridoPointsTransferenceProcessor, diario 10:00 -03:00) falla todos los dias en PREPROD.
--       a) historial largo de ese job en PREPROD (cuando empezo a fallar y cuanto dura cada corrida);
--       b) el mismo job en TEST02 (el entorno que funciona): nombre, ultimas corridas y si fallan;
--       c) tablas con "Etl" en el nombre en las dos bases (si las tablas del contexto ETL existen en PREPROD);
--       d) bases de datos SmartFran* visibles para el login (existe DwTest-PREPROD?).
USE [SmartFran.Solution.SmartLoyalty-PREPROD];
GO
SET NOCOUNT ON;
PRINT '== a) PREPROD: ultimas 40 corridas del job 7965';
SELECT TOP (40) Id, ExecuteOn, ExecutionStarted, DATEDIFF(SECOND, ExecutionStarted, Done) AS segundos, Failed, DeactivatedDate, DeactivateNote
FROM Sch.Task WHERE JobId = 7965 ORDER BY Id DESC;
GO
PRINT '== a2) PREPROD: corridas del job 7965 por resultado (Failed 1/0/NULL)';
SELECT Failed, COUNT(*) AS tareas, MIN(ExecutionStarted) AS primera, MAX(ExecutionStarted) AS ultima FROM Sch.Task WHERE JobId = 7965 AND ExecutionStarted IS NOT NULL GROUP BY Failed ORDER BY Failed;
GO
PRINT '== b) TEST02: jobs con el mismo nombre';
SELECT Id, Name, ValidSince FROM [SmartFran.Solution.SmartLoyalty-TEST02].Sch.Job WHERE Name = 'EtlDwGridoPointsTransferenceProcessor';
GO
PRINT '== b2) TEST02: ultimas 15 corridas de ese job';
SELECT TOP (15) t.Id, t.ExecuteOn, t.ExecutionStarted, DATEDIFF(SECOND, t.ExecutionStarted, t.Done) AS segundos, t.Failed
FROM [SmartFran.Solution.SmartLoyalty-TEST02].Sch.Task t
WHERE t.JobId IN (SELECT Id FROM [SmartFran.Solution.SmartLoyalty-TEST02].Sch.Job WHERE Name = 'EtlDwGridoPointsTransferenceProcessor') ORDER BY t.Id DESC;
GO
PRINT '== c) tablas con Etl en el nombre: PREPROD';
SELECT TABLE_SCHEMA, TABLE_NAME FROM [SmartFran.Solution.SmartLoyalty-PREPROD].INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME LIKE '%Etl%' ORDER BY 1, 2;
GO
PRINT '== c2) tablas con Etl en el nombre: TEST02';
SELECT TABLE_SCHEMA, TABLE_NAME FROM [SmartFran.Solution.SmartLoyalty-TEST02].INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME LIKE '%Etl%' ORDER BY 1, 2;
GO
PRINT '== d) bases de datos SmartFran* visibles';
SELECT name, create_date FROM sys.databases WHERE name LIKE 'SmartFran%' ORDER BY name;
GO

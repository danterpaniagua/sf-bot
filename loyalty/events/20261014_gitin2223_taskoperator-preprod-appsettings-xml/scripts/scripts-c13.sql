-- Event: 20261014_gitin2223_taskoperator-preprod-appsettings-xml (GITIN-2223)
-- C13 - SOLO LECTURA. Sigue a C12: el job ETL 7965 fallo en las 445 corridas de PREPROD (desde 2025-01-21) y en TEST02 funciona (1-2 s).
--       Antes de forzar una corrida en PREPROD interesa saber si el ETL guarda una marca de avance (la primera corrida exitosa podria procesar mucho atraso)
--       y si su propia tabla de log guarda el texto del error. Se miran las 4 tablas del esquema Etl en PREPROD y en TEST02.
--       Para no traer contenido desconocido: columnas y cantidad de filas de las 4 tablas, y las ultimas 5 filas de EtlOperation y de EtlOperationExecution
--       (revisar la salida antes de pegarla). El log (EtlOperationExecutionLog) solo se cuenta; su contenido se pide despues si hace falta.
USE [SmartFran.Solution.SmartLoyalty-PREPROD];
GO
SET NOCOUNT ON;
PRINT '== a) PREPROD: columnas de las tablas Etl';
SELECT TABLE_NAME, STRING_AGG(COLUMN_NAME + ' ' + DATA_TYPE, ', ') WITHIN GROUP (ORDER BY ORDINAL_POSITION) AS columnas
FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'Etl' GROUP BY TABLE_NAME ORDER BY TABLE_NAME;
GO
PRINT '== b) PREPROD: cantidad de filas';
SELECT 'EtlOperation' AS tabla, COUNT(*) AS filas FROM Etl.EtlOperation
UNION ALL SELECT 'EtlOperationConfig', COUNT(*) FROM Etl.EtlOperationConfig
UNION ALL SELECT 'EtlOperationExecution', COUNT(*) FROM Etl.EtlOperationExecution
UNION ALL SELECT 'EtlOperationExecutionLog', COUNT(*) FROM Etl.EtlOperationExecutionLog;
GO
PRINT '== c) PREPROD: EtlOperation (ultimas 5)';
SELECT TOP (5) * FROM Etl.EtlOperation ORDER BY 1 DESC;
GO
PRINT '== d) PREPROD: EtlOperationExecution (ultimas 5)';
SELECT TOP (5) * FROM Etl.EtlOperationExecution ORDER BY 1 DESC;
GO
PRINT '== e) TEST02: cantidad de filas';
SELECT 'EtlOperation' AS tabla, COUNT(*) AS filas FROM [SmartFran.Solution.SmartLoyalty-TEST02].Etl.EtlOperation
UNION ALL SELECT 'EtlOperationConfig', COUNT(*) FROM [SmartFran.Solution.SmartLoyalty-TEST02].Etl.EtlOperationConfig
UNION ALL SELECT 'EtlOperationExecution', COUNT(*) FROM [SmartFran.Solution.SmartLoyalty-TEST02].Etl.EtlOperationExecution
UNION ALL SELECT 'EtlOperationExecutionLog', COUNT(*) FROM [SmartFran.Solution.SmartLoyalty-TEST02].Etl.EtlOperationExecutionLog;
GO
PRINT '== f) TEST02: EtlOperation y EtlOperationExecution (ultimas 5 de cada una)';
SELECT TOP (5) * FROM [SmartFran.Solution.SmartLoyalty-TEST02].Etl.EtlOperation ORDER BY 1 DESC;
SELECT TOP (5) * FROM [SmartFran.Solution.SmartLoyalty-TEST02].Etl.EtlOperationExecution ORDER BY 1 DESC;
GO

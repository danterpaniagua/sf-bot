-- ============================================================
-- Incidente: Backup_Log fallando — 2026-06-11
-- Archivo de referencia de scripts ejecutados
-- ============================================================

-- Q1: Historial de ejecuciones del job fallando
SELECT TOP 20
    j.name AS Job, h.step_id, h.step_name,
    msdb.dbo.agent_datetime(h.run_date, h.run_time) AS Fecha_UTC,
    CASE h.run_status WHEN 0 THEN 'FAILED' WHEN 1 THEN 'SUCCEEDED'
        WHEN 2 THEN 'RETRY' WHEN 3 THEN 'CANCELLED' END AS Estado,
    h.run_duration AS Duracion_HHMMSS, h.message AS Mensaje_Error
FROM msdb.dbo.sysjobhistory h
JOIN msdb.dbo.sysjobs j ON j.job_id = h.job_id
WHERE j.name = 'Operaciones_MaintenancePlan_Backups.Backup_Log'
ORDER BY h.run_date DESC, h.run_time DESC;

-- Q2: Modelos de recuperación de todas las bases
SELECT name AS Base, recovery_model_desc AS Recovery_Model, state_desc AS Estado
FROM sys.databases WHERE state_desc = 'ONLINE' ORDER BY name;

-- Q3: Verificar login NT Service\SQLSERVERAGENT a nivel servidor
SELECT name, type_desc, is_disabled, default_database_name
FROM sys.server_principals
WHERE name LIKE '%SQLSERVERAGENT%' OR name LIKE '%sqlagent%';

-- Q4: Verificar usuario en msdb
USE msdb;
SELECT name, type_desc, default_schema_name, authentication_type_desc
FROM sys.database_principals
WHERE name LIKE '%SQLSERVERAGENT%' OR name LIKE '%sqlagent%';

-- Q5: Leer cadena de conexión embebida en el paquete SSIS
USE msdb;
DECLARE @pkg XML;
SELECT @pkg = CAST(CAST(packagedata AS VARBINARY(MAX)) AS XML)
FROM msdb.dbo.sysssispackages
WHERE name = 'Operaciones_MaintenancePlan_Backups';

WITH XMLNAMESPACES ('www.microsoft.com/SqlServer/Dts' AS DTS)
SELECT
    cm.value('(@DTS:ObjectName)[1]',        'nvarchar(256)') AS ConnectionName,
    cmd.value('(@DTS:ConnectionString)[1]', 'nvarchar(max)') AS ConnectionString
FROM @pkg.nodes('//DTS:ConnectionManagers/DTS:ConnectionManager') AS T(cm)
CROSS APPLY cm.nodes('DTS:ObjectData/DTS:ConnectionManager') AS U(cmd);

-- Q6: Obtener nombre exacto del servidor
SELECT @@SERVERNAME AS ServerName, @@SERVICENAME AS InstanceName;

-- Q7: Crear login de servicio svc_maintplan y permisos en msdb
CREATE LOGIN svc_maintplan
    WITH PASSWORD = '******************************************',
         CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;

USE msdb;
CREATE USER svc_maintplan FOR LOGIN svc_maintplan;
ALTER ROLE [SQLAgentOperatorRole]  ADD MEMBER svc_maintplan;
GRANT EXECUTE ON dbo.sp_maintplan_open_logentry TO svc_maintplan;
GRANT INSERT  ON dbo.sysmaintplan_log           TO svc_maintplan;
GRANT SELECT  ON dbo.sysmaintplan_subplans      TO svc_maintplan;

-- Q8: Preview — verificar nueva cadena de conexión antes de escribir
USE msdb;
DECLARE @pkg XML;
DECLARE @newConnStr NVARCHAR(500) =
    'Data Source=SFCG-DB01;Integrated Security=True;Pooling=False;Min Pool Size=0;Max Pool Size=100;Connect Timeout=30;Encrypt=False;TrustServerCertificate=False;Packet Size=4096;';

SELECT @pkg = CAST(CAST(packagedata AS VARBINARY(MAX)) AS XML)
FROM msdb.dbo.sysssispackages
WHERE name = 'Operaciones_MaintenancePlan_Backups';

SET @pkg.modify('
    declare namespace DTS="www.microsoft.com/SqlServer/Dts";
    replace value of
    (//DTS:ConnectionManagers/DTS:ConnectionManager/DTS:ObjectData/DTS:ConnectionManager/@DTS:ConnectionString)[1]
    with sql:variable("@newConnStr")
');

WITH XMLNAMESPACES ('www.microsoft.com/SqlServer/Dts' AS DTS)
SELECT cmd.value('(@DTS:ConnectionString)[1]', 'nvarchar(max)') AS NewConnectionString
FROM @pkg.nodes('//DTS:ConnectionManagers/DTS:ConnectionManager/DTS:ObjectData/DTS:ConnectionManager') AS T(cmd);

-- Q9: Aplicar fix — reemplazar cadena de conexión en msdb (Windows Auth)
USE msdb;
DECLARE @pkg XML;
DECLARE @newConnStr NVARCHAR(500) =
    'Data Source=SFCG-DB01;Integrated Security=True;Pooling=False;Min Pool Size=0;Max Pool Size=100;Connect Timeout=30;Encrypt=False;TrustServerCertificate=False;Packet Size=4096;';

SELECT @pkg = CAST(CAST(packagedata AS VARBINARY(MAX)) AS XML)
FROM msdb.dbo.sysssispackages
WHERE name = 'Operaciones_MaintenancePlan_Backups';

SET @pkg.modify('
    declare namespace DTS="www.microsoft.com/SqlServer/Dts";
    replace value of
    (//DTS:ConnectionManagers/DTS:ConnectionManager/DTS:ObjectData/DTS:ConnectionManager/@DTS:ConnectionString)[1]
    with sql:variable("@newConnStr")
');

UPDATE msdb.dbo.sysssispackages
SET packagedata = CAST(CAST(@pkg AS NVARCHAR(MAX)) AS VARBINARY(MAX))
WHERE name = 'Operaciones_MaintenancePlan_Backups';

-- Q10: Verificar estado de todos los jobs post-fix
SELECT
    j.name AS Job, j.enabled AS Habilitado,
    msdb.dbo.agent_datetime(h.run_date, h.run_time) AS Ultima_Ejecucion,
    CASE h.run_status WHEN 0 THEN 'FAILED' WHEN 1 THEN 'SUCCEEDED'
        WHEN 2 THEN 'RETRY' WHEN 3 THEN 'CANCELLED' WHEN 4 THEN 'IN PROGRESS'
    END AS Estado,
    h.run_duration AS Duracion_HHMMSS, h.step_name AS Ultimo_Paso
FROM msdb.dbo.sysjobs j
LEFT JOIN msdb.dbo.sysjobhistory h ON h.job_id = j.job_id
    AND h.instance_id = (
        SELECT MAX(h2.instance_id) FROM msdb.dbo.sysjobhistory h2
        WHERE h2.job_id = j.job_id AND h2.step_id = 0
    )
ORDER BY j.name;

-- Q11: Auditoría de credenciales embebidas en todos los paquetes SSIS de msdb
USE msdb;
WITH XMLNAMESPACES ('www.microsoft.com/SqlServer/Dts' AS DTS),
packages AS (
    SELECT name AS PackageName, CAST(CAST(packagedata AS VARBINARY(MAX)) AS XML) AS pkg
    FROM msdb.dbo.sysssispackages
)
SELECT
    p.PackageName,
    cm.value('(@DTS:ObjectName)[1]',        'nvarchar(256)') AS ConnectionName,
    cmd.value('(@DTS:ConnectionString)[1]', 'nvarchar(max)') AS ConnectionString
FROM packages p
CROSS APPLY p.pkg.nodes('//DTS:ConnectionManagers/DTS:ConnectionManager') AS T(cm)
CROSS APPLY cm.nodes('DTS:ObjectData/DTS:ConnectionManager')               AS U(cmd);

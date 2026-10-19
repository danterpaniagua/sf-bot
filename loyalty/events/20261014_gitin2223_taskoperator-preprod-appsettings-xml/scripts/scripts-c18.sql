-- Event: 20261014_gitin2223_taskoperator-preprod-appsettings-xml (GITIN-2223)
-- C18 - SOLO LECTURA. Aporta lo que falta para juzgar la hipotesis de la transaccion abierta (UPDATE visible solo para la sesion que lo corrio):
--       a) cuando se reinicio el SQL Server y cuando arranco el sistema operativo (si coinciden con el "reinicio despues del cual el UPDATE aplica");
--       b) si las bases usan lectura confirmada con versiones (is_read_committed_snapshot_on = 1): con 1, un SELECT no se bloquea y muestra el ultimo valor confirmado;
--       c) sesiones abiertas ahora por login y equipo (varias sesiones con el mismo login son sesiones distintas, con bloqueos distintos).
USE master;
GO
SET NOCOUNT ON;
PRINT '== a) hora del servidor, inicio del SQL Server e inicio del sistema operativo';
SELECT SYSDATETIMEOFFSET() AS ahora_con_zona, sqlserver_start_time AS sql_server_iniciado, DATEADD(SECOND, -(ms_ticks / 1000), SYSDATETIME()) AS sistema_iniciado_aprox FROM sys.dm_os_sys_info;
GO
PRINT '== b) aislamiento de lectura de las bases SmartFran*';
SELECT name, is_read_committed_snapshot_on, snapshot_isolation_state_desc FROM sys.databases WHERE name LIKE 'SmartFran%' ORDER BY name;
GO
PRINT '== c) sesiones de usuario abiertas por login, equipo y programa (cantidad y transacciones abiertas)';
SELECT login_name, host_name, program_name, COUNT(*) AS sesiones, SUM(open_transaction_count) AS transacciones_abiertas, MIN(login_time) AS la_mas_antigua
FROM sys.dm_exec_sessions WHERE is_user_process = 1 GROUP BY login_name, host_name, program_name ORDER BY login_name, host_name;
GO

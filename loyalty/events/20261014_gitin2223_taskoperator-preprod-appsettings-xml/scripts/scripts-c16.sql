-- Event: 20261014_gitin2223_taskoperator-preprod-appsettings-xml (GITIN-2223)
-- C16 - SOLO LECTURA. Un UPDATE de Sch.Task (tarea 139102) lo ve quien lo corrio pero no otra sesion, el UPDATE de otra sesion se cuelga y despues de reiniciar aplica:
--       hipotesis: una transaccion abierta sin COMMIT mantiene bloqueada la fila. Este script busca sesiones con transaccion abierta, bloqueos, el modo de aislamiento
--       de las bases y compara la fila 139102 leida de forma confirmada vs sin bloqueo (NOLOCK, muestra tambien el valor sin confirmar).
--       Los DMV necesitan el permiso VIEW SERVER STATE; si el login no lo tiene, cada seccion falla sola (hay GO entre secciones) y se corre con un login que lo tenga.
USE [SmartFran.Solution.SmartLoyalty-PREPROD];
GO
SET NOCOUNT ON;
PRINT '== 1) hora del servidor';
SELECT SYSDATETIMEOFFSET() AS ahora_con_zona;
GO
PRINT '== 2) aislamiento de las bases SmartFran* (is_read_committed_snapshot_on = 1: una lectura NO se bloquea y ve el ultimo valor confirmado)';
SELECT name, is_read_committed_snapshot_on, snapshot_isolation_state_desc FROM sys.databases WHERE name LIKE 'SmartFran%' ORDER BY name;
GO
PRINT '== 3) sesiones con transaccion abierta (excluye esta sesion)';
SELECT s.session_id, s.login_name, s.host_name, s.program_name, s.status, s.open_transaction_count, s.last_request_start_time, s.last_request_end_time,
       at.transaction_begin_time, LEFT(REPLACE(REPLACE(st.text, CHAR(13), ' '), CHAR(10), ' '), 300) AS ultima_sentencia
FROM sys.dm_exec_sessions s
JOIN sys.dm_tran_session_transactions tst ON tst.session_id = s.session_id
JOIN sys.dm_tran_active_transactions at ON at.transaction_id = tst.transaction_id
LEFT JOIN sys.dm_exec_connections c ON c.session_id = s.session_id
OUTER APPLY sys.dm_exec_sql_text(c.most_recent_sql_handle) st
WHERE s.session_id <> @@SPID AND s.is_user_process = 1
ORDER BY at.transaction_begin_time;
GO
PRINT '== 4) peticiones bloqueadas ahora (quien espera a quien)';
SELECT r.session_id, r.blocking_session_id, r.wait_type, r.wait_time AS espera_ms, r.status, r.command, DB_NAME(r.database_id) AS base,
       LEFT(REPLACE(REPLACE(st.text, CHAR(13), ' '), CHAR(10), ' '), 300) AS sentencia
FROM sys.dm_exec_requests r OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) st
WHERE r.blocking_session_id <> 0;
GO
PRINT '== 5) bloqueos tomados en la base PREPROD, por sesion y modo';
SELECT request_session_id, resource_type, request_mode, request_status, COUNT(*) AS cantidad
FROM sys.dm_tran_locks WHERE resource_database_id = DB_ID('SmartFran.Solution.SmartLoyalty-PREPROD') AND request_session_id <> @@SPID
GROUP BY request_session_id, resource_type, request_mode, request_status ORDER BY request_session_id, resource_type;
GO
PRINT '== 6) la fila 139102: lectura confirmada vs sin bloqueo (NOLOCK ve tambien el valor sin confirmar)';
SELECT 'confirmada (READCOMMITTED)' AS lectura, Id, JobId, ExecuteOn, ExecutionStarted, Done FROM Sch.Task WITH (READCOMMITTED) WHERE Id = 139102;
SELECT 'sin bloqueo (NOLOCK)' AS lectura, Id, JobId, ExecuteOn, ExecutionStarted, Done FROM Sch.Task WITH (NOLOCK) WHERE Id = 139102;
GO
PRINT '== 7) transaccion mas antigua abierta en la base PREPROD (DBCC OPENTRAN)';
DBCC OPENTRAN WITH TABLERESULTS, NO_INFOMSGS;
GO

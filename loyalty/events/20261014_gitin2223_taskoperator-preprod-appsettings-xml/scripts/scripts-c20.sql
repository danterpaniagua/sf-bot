-- Event: 20261014_gitin2223_taskoperator-preprod-appsettings-xml (GITIN-2223)
-- C20 - SOLO LECTURA. Identificar de que maquina viene cada sesion que tiene una transaccion abierta o esta bloqueada (C16: sesiones 65 y 56).
--       host_name lo informa el cliente; client_net_address (IP de la conexion) lo ve el servidor y es mas confiable.
SET NOCOUNT ON;
GO
PRINT '== 1) hora del servidor';
SELECT SYSDATETIMEOFFSET() AS ahora_con_zona;
GO
PRINT '== 2) origen de cada sesion con transaccion abierta o bloqueada';
SELECT s.session_id, s.login_name, s.host_name, c.client_net_address AS ip_cliente, c.local_net_address AS ip_servidor, c.net_transport, c.auth_scheme,
       s.program_name, s.client_interface_name, s.login_time, s.last_request_start_time, s.last_request_end_time, s.status, s.open_transaction_count
FROM sys.dm_exec_sessions s
LEFT JOIN sys.dm_exec_connections c ON c.session_id = s.session_id
WHERE s.is_user_process = 1
  AND (s.open_transaction_count > 0
       OR s.session_id IN (SELECT blocking_session_id FROM sys.dm_exec_requests WHERE blocking_session_id <> 0)
       OR s.session_id IN (SELECT session_id FROM sys.dm_exec_requests WHERE blocking_session_id <> 0))
ORDER BY s.session_id;
GO
PRINT '== 3) todas las sesiones de usuario abiertas, para comparar IP y host';
SELECT s.session_id, s.login_name, s.host_name, c.client_net_address AS ip_cliente, s.program_name, s.login_time, s.status, s.open_transaction_count
FROM sys.dm_exec_sessions s LEFT JOIN sys.dm_exec_connections c ON c.session_id = s.session_id
WHERE s.is_user_process = 1 ORDER BY s.login_time;
GO
PRINT '== 4) ultima sentencia enviada por la sesion 65 (DBCC INPUTBUFFER solo muestra la ultima, no el UPDATE anterior de la transaccion)';
DBCC INPUTBUFFER(65);
GO

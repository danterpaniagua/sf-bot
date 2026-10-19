-- Event: 20261014_gitin2223_taskoperator-preprod-appsettings-xml (GITIN-2223)
-- C22 - SOLO LECTURA. Se corre en la ventana de SSMS que se quiere identificar (la de QA): informa la propia sesion tal como la ve el servidor.
--       Sirve para comparar con la sesion 65 de C16/C20 (host, IP 200.80.249.74, login 2026-10-14 18:36:25 UTC) y ver si quedo una transaccion abierta (@@TRANCOUNT).
SET NOCOUNT ON;
SELECT @@SPID AS mi_session_id,
       HOST_NAME() AS host_name,
       c.client_net_address AS ip_cliente,
       APP_NAME() AS programa,
       SYSTEM_USER AS login_name,
       @@TRANCOUNT AS transacciones_abiertas_en_esta_ventana,
       s.login_time,
       SYSDATETIMEOFFSET() AS ahora_con_zona
FROM sys.dm_exec_sessions s
JOIN sys.dm_exec_connections c ON c.session_id = s.session_id
WHERE s.session_id = @@SPID;

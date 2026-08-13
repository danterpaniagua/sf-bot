-- Evento: 20260723_bloqueo_customerpointslog_loadtest
-- Reconstruido de forma retroactiva a partir de la conversación de trabajo del mismo día.
-- Base de datos de referencia: PNSSRL (SFCG-DB01)

-- === Q1 — Chequeo de disponibilidad de datos en la ventana del incidente ===
SELECT MIN(fecha_hora_captura) AS primer_registro, MAX(fecha_hora_captura) AS ultimo_registro, COUNT(*) AS total_snapshots
FROM PNSSRL_AuditSysprocesses
WHERE fecha_hora_captura >= '2026-07-23 08:00'
  AND fecha_hora_captura <= '2026-07-23 15:00';

-- === Q2 — Delta de CPU por SPID entre snapshots consecutivos ===
WITH cpu_delta AS (
    SELECT
        spid,
        fecha_hora_captura,
        cpu,
        cpu - LAG(cpu) OVER (PARTITION BY spid ORDER BY fecha_hora_captura) AS cpu_delta_ms,
        loginame,
        hostname,
        program_name,
        DB_NAME(dbid) AS database_name
    FROM PNSSRL_AuditSysprocesses
    WHERE fecha_hora_captura >= '2026-07-23 08:00'
)
SELECT *
FROM cpu_delta
WHERE cpu_delta_ms IS NOT NULL
ORDER BY cpu_delta_ms DESC;

-- === Q3 — Cadena de bloqueo en vivo ===
SELECT
    r.session_id,
    r.blocking_session_id,
    r.wait_type,
    r.wait_time,
    r.wait_resource,
    r.status,
    r.cpu_time,
    r.command,
    s.login_name,
    s.host_name,
    s.program_name,
    DB_NAME(r.database_id) AS database_name
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
WHERE r.blocking_session_id <> 0
   OR r.session_id IN (SELECT blocking_session_id FROM sys.dm_exec_requests WHERE blocking_session_id <> 0);
-- RESULTADO (2026-07-23): session_id 87, blocking_session_id 93, wait_type LCK_M_SCH_M

-- === Q4 — Terminación de la transacción abandonada (causa raíz) ===
KILL 93;
-- RESULTADO (2026-07-23): Commands completed successfully.

-- === Q5 — Verificación post-KILL: estado de SPID 87 y métricas de CPU/espera ===
SELECT
    r.session_id,
    r.status,
    r.command,
    r.cpu_time,
    r.total_elapsed_time,
    r.percent_complete,
    r.wait_type,
    r.wait_time
FROM sys.dm_exec_requests r
WHERE r.session_id = 87;
-- Seguimiento: SPID 87 continuó ejecutándose (ALTER INDEX REBUILD legítimo, PNSSRL_MantenimientoModulos)
-- percent_complete no confiable para rebuilds offline

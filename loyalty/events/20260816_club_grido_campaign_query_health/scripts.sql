-- Q1: Data availability check, primary window (15:00-20:00 UTC)
SELECT
    MIN(fecha_hora_captura) AS primera_captura,
    MAX(fecha_hora_captura) AS ultima_captura,
    COUNT(DISTINCT fecha_hora_captura) AS snapshots_disponibles
FROM PNSSRL_AuditSysprocesses
WHERE fecha_hora_captura BETWEEN '2026-08-16 15:00:00' AND '2026-08-16 20:00:00';

-- Q2: CPU delta per SPID between consecutive snapshots, top 50, primary window
WITH deltas AS (
    SELECT
        spid,
        fecha_hora_captura,
        cpu,
        cpu - LAG(cpu) OVER (PARTITION BY spid ORDER BY fecha_hora_captura) AS cpu_delta,
        loginame,
        hostname,
        program_name,
        status,
        cmd,
        blocked,
        lastwaittype,
        waitresource,
        DB_NAME(dbid) AS db_name
    FROM PNSSRL_AuditSysprocesses
    WHERE fecha_hora_captura BETWEEN '2026-08-16 15:00:00' AND '2026-08-16 20:00:00'
)
SELECT TOP 50
    spid, fecha_hora_captura, cpu_delta, loginame, hostname, program_name,
    status, cmd, blocked, lastwaittype, waitresource, db_name
FROM deltas
WHERE cpu_delta IS NOT NULL
ORDER BY cpu_delta DESC;

-- Q3: Service-level (hostname) CPU breakdown, primary window
SELECT
    hostname,
    program_name,
    COUNT(*) AS snapshot_rows,
    SUM(CASE WHEN cpu_delta > 0 THEN cpu_delta ELSE 0 END) AS total_cpu_delta_ms
FROM (
    SELECT
        hostname,
        program_name,
        cpu - LAG(cpu) OVER (PARTITION BY spid ORDER BY fecha_hora_captura) AS cpu_delta
    FROM PNSSRL_AuditSysprocesses
    WHERE fecha_hora_captura BETWEEN '2026-08-16 15:00:00' AND '2026-08-16 20:00:00'
) x
GROUP BY hostname, program_name
ORDER BY total_cpu_delta_ms DESC;

-- Q4: Blocking check, primary window (0 rows found)
SELECT
    fecha_hora_captura, spid, blocked, lastwaittype, waitresource,
    hostname, program_name, DB_NAME(dbid) AS db_name, comando_ejecutado
FROM PNSSRL_AuditSysprocesses
WHERE fecha_hora_captura BETWEEN '2026-08-16 15:00:00' AND '2026-08-16 20:00:00'
  AND blocked <> 0
ORDER BY fecha_hora_captura;

-- Q5: Top CPU sessions with full query text, primary window
SELECT TOP 20
    session_id, request_id, hora_captura, cpu_time, logical_reads, reads, writes,
    OutStanding_internal_objects_page_counts, granted_query_memory,
    HOST_NAME, login_name, program_name, Query_Text
FROM PNSSRL_TempdbProc
WHERE hora_captura BETWEEN '2026-08-16 15:00:00' AND '2026-08-16 20:00:00'
ORDER BY cpu_time DESC;

-- Q6: Gap-hour check (20:00-21:00 UTC) - data availability, blocking, CPU breakdown
SELECT
    MIN(fecha_hora_captura) AS primera_captura,
    MAX(fecha_hora_captura) AS ultima_captura,
    COUNT(DISTINCT fecha_hora_captura) AS snapshots_disponibles
FROM PNSSRL_AuditSysprocesses
WHERE fecha_hora_captura BETWEEN '2026-08-16 20:00:00' AND '2026-08-16 21:00:00';

SELECT
    fecha_hora_captura, spid, blocked, lastwaittype, waitresource,
    hostname, program_name, DB_NAME(dbid) AS db_name, comando_ejecutado
FROM PNSSRL_AuditSysprocesses
WHERE fecha_hora_captura BETWEEN '2026-08-16 20:00:00' AND '2026-08-16 21:00:00'
  AND blocked <> 0
ORDER BY fecha_hora_captura;

SELECT
    hostname,
    program_name,
    COUNT(*) AS snapshot_rows,
    SUM(CASE WHEN cpu_delta > 0 THEN cpu_delta ELSE 0 END) AS total_cpu_delta_ms
FROM (
    SELECT
        hostname,
        program_name,
        cpu - LAG(cpu) OVER (PARTITION BY spid ORDER BY fecha_hora_captura) AS cpu_delta
    FROM PNSSRL_AuditSysprocesses
    WHERE fecha_hora_captura BETWEEN '2026-08-16 20:00:00' AND '2026-08-16 21:00:00'
) x
GROUP BY hostname, program_name
ORDER BY total_cpu_delta_ms DESC;

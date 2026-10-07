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

-- Follow-up: 2026-08-19 21:00-22:00 UTC-3 MobileAppService spike (= 2026-08-20 00:00-01:00 UTC)

-- Q7: Data availability check, spike window
SELECT
    MIN(fecha_hora_captura) AS primera_captura,
    MAX(fecha_hora_captura) AS ultima_captura,
    COUNT(DISTINCT fecha_hora_captura) AS snapshots_disponibles
FROM PNSSRL_AuditSysprocesses
WHERE fecha_hora_captura BETWEEN '2026-08-20 00:00:00' AND '2026-08-20 01:00:00';

-- Q8: Blocking check, spike window
SELECT
    fecha_hora_captura, spid, blocked, lastwaittype, waitresource,
    hostname, program_name, DB_NAME(dbid) AS db_name, comando_ejecutado
FROM PNSSRL_AuditSysprocesses
WHERE fecha_hora_captura BETWEEN '2026-08-20 00:00:00' AND '2026-08-20 01:00:00'
  AND blocked <> 0
ORDER BY fecha_hora_captura;

-- Q9: Hostname CPU breakdown, spike window (MobileAppService = SFCG-MOBI-01/02)
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
    WHERE fecha_hora_captura BETWEEN '2026-08-20 00:00:00' AND '2026-08-20 01:00:00'
) x
GROUP BY hostname, program_name
ORDER BY total_cpu_delta_ms DESC;

-- Follow-up: 2026-08-28/29/30 weekend window

-- Q10: Data availability check, weekend window
SELECT
    MIN(fecha_hora_captura) AS primera_captura,
    MAX(fecha_hora_captura) AS ultima_captura,
    COUNT(DISTINCT fecha_hora_captura) AS snapshots_disponibles
FROM PNSSRL_AuditSysprocesses
WHERE fecha_hora_captura BETWEEN '2026-08-28 03:00:00' AND '2026-08-31 03:00:00';

-- Q11: Blocking check, weekend window (488 rows found - see investigation.md)
SELECT
    fecha_hora_captura, spid, blocked, lastwaittype, waitresource,
    hostname, program_name, DB_NAME(dbid) AS db_name, comando_ejecutado
FROM PNSSRL_AuditSysprocesses
WHERE fecha_hora_captura BETWEEN '2026-08-28 03:00:00' AND '2026-08-31 03:00:00'
  AND blocked <> 0
ORDER BY fecha_hora_captura;

-- Q12: Hostname CPU breakdown, weekend window
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
    WHERE fecha_hora_captura BETWEEN '2026-08-28 03:00:00' AND '2026-08-31 03:00:00'
) x
GROUP BY hostname, program_name
ORDER BY total_cpu_delta_ms DESC;

-- Q13: Root blocker identification, weekend window
;WITH blocked_rows AS (
    SELECT fecha_hora_captura, spid, blocked
    FROM PNSSRL_AuditSysprocesses
    WHERE fecha_hora_captura BETWEEN '2026-08-28 03:00:00' AND '2026-08-31 03:00:00'
      AND blocked <> 0
)
SELECT DISTINCT
    b.fecha_hora_captura,
    b.blocked AS head_spid,
    h.hostname,
    h.program_name,
    h.lastwaittype,
    h.status,
    h.cmd,
    h.comando_ejecutado
FROM blocked_rows b
LEFT JOIN PNSSRL_AuditSysprocesses h
    ON h.fecha_hora_captura = b.fecha_hora_captura
   AND h.spid = b.blocked
WHERE NOT EXISTS (
    SELECT 1 FROM blocked_rows b2
    WHERE b2.fecha_hora_captura = b.fecha_hora_captura AND b2.spid = b.blocked
)
ORDER BY b.fecha_hora_captura;

-- Q14: Blocking severity per snapshot, weekend window
SELECT
    fecha_hora_captura,
    COUNT(*) AS blocked_rows,
    COUNT(DISTINCT spid) AS distinct_blocked_spids,
    COUNT(DISTINCT blocked) AS distinct_blocker_spids
FROM PNSSRL_AuditSysprocesses
WHERE fecha_hora_captura BETWEEN '2026-08-28 03:00:00' AND '2026-08-31 03:00:00'
  AND blocked <> 0
GROUP BY fecha_hora_captura
ORDER BY fecha_hora_captura;

-- Event: 20260727_cpu_peaks_loadtest
-- Window: 2026-07-27 08:00-11:00 UTC-3 = 11:00-14:00 GMT (server time)

-- Q1 — Data availability check on PNSSRL_AuditSysprocesses for the window
SELECT
    MIN(fecha_hora_captura) AS primera_captura,
    MAX(fecha_hora_captura) AS ultima_captura,
    COUNT(DISTINCT fecha_hora_captura) AS snapshots_distintos,
    COUNT(*) AS filas_totales
FROM PNSSRL_AuditSysprocesses
WHERE fecha_hora_captura BETWEEN '2026-07-27 11:00:00' AND '2026-07-27 14:00:00';

-- Q2 — CPU delta per SPID between consecutive snapshots, with blocking + query text context
WITH cpu_delta AS (
    SELECT
        spid,
        fecha_hora_captura,
        cpu,
        cpu - LAG(cpu) OVER (PARTITION BY spid ORDER BY fecha_hora_captura) AS cpu_delta_ms,
        blocked,
        status,
        lastwaittype,
        loginame,
        hostname,
        program_name,
        DB_NAME(dbid) AS database_name,
        comando_ejecutado
    FROM PNSSRL_AuditSysprocesses
    WHERE fecha_hora_captura BETWEEN '2026-07-27 11:00:00' AND '2026-07-27 14:00:00'
)
SELECT TOP 50 *
FROM cpu_delta
WHERE cpu_delta_ms IS NOT NULL
ORDER BY cpu_delta_ms DESC;

-- Q3 — Server logical core count, to size how much "one saturated core" represents of total CPU
SELECT cpu_count, hyperthread_ratio, scheduler_count, sqlserver_start_time
FROM sys.dm_os_sys_info;

-- Q4 — Historical pattern: does this sfsqlusr/SFCG-TO-01 CustomerPointsLog sync job recur on other days?
SELECT
    CAST(fecha_hora_captura AS DATE) AS captura_dia,
    MIN(fecha_hora_captura) AS primera_aparicion,
    MAX(fecha_hora_captura) AS ultima_aparicion,
    COUNT(*) AS filas_capturadas,
    MIN(cpu) AS cpu_min,
    MAX(cpu) AS cpu_max
FROM PNSSRL_AuditSysprocesses
WHERE loginame = 'sfsqlusr'
  AND hostname = 'SFCG-TO-01'
  AND comando_ejecutado LIKE '%CustomerPointsLog%'
GROUP BY CAST(fecha_hora_captura AS DATE)
ORDER BY captura_dia DESC;

-- Q5 — Total CPU across ALL sessions per snapshot (not just top SPID), vs. 16-core capacity
-- Capacity per ~5min snapshot interval = 16 cores * 300,000ms = 4,800,000 CPU-ms = 100%
WITH cpu_delta_all AS (
    SELECT
        spid,
        fecha_hora_captura,
        cpu - LAG(cpu) OVER (PARTITION BY spid ORDER BY fecha_hora_captura) AS cpu_delta_ms
    FROM PNSSRL_AuditSysprocesses
    WHERE fecha_hora_captura BETWEEN '2026-07-27 11:00:00' AND '2026-07-27 14:00:00'
)
SELECT
    fecha_hora_captura,
    SUM(cpu_delta_ms) AS cpu_total_delta_ms,
    CAST(SUM(cpu_delta_ms) AS FLOAT) / 4800000 * 100 AS pct_16_core_capacity,
    COUNT(*) AS spids_con_delta
FROM cpu_delta_all
WHERE cpu_delta_ms IS NOT NULL
GROUP BY fecha_hora_captura
ORDER BY fecha_hora_captura;

-- Q6 — Data availability check, extended window (covers the full reported peak: 08:00-12:00 UTC-3 = 11:00-15:00 GMT)
SELECT
    MIN(fecha_hora_captura) AS primera_captura,
    MAX(fecha_hora_captura) AS ultima_captura,
    COUNT(DISTINCT fecha_hora_captura) AS snapshots_distintos,
    COUNT(*) AS filas_totales
FROM PNSSRL_AuditSysprocesses
WHERE fecha_hora_captura BETWEEN '2026-07-27 11:00:00' AND '2026-07-27 15:00:00';

-- Q7 — Total CPU across ALL SPIDs (including low/system SPIDs) per snapshot, extended window
WITH cpu_delta_ext AS (
    SELECT
        spid,
        fecha_hora_captura,
        cpu - LAG(cpu) OVER (PARTITION BY spid ORDER BY fecha_hora_captura) AS cpu_delta_ms
    FROM PNSSRL_AuditSysprocesses
    WHERE fecha_hora_captura BETWEEN '2026-07-27 11:00:00' AND '2026-07-27 15:00:00'
)
SELECT
    fecha_hora_captura,
    SUM(cpu_delta_ms) AS cpu_total_delta_ms,
    CAST(SUM(cpu_delta_ms) AS FLOAT) / 4800000 * 100 AS pct_16_core_capacity,
    COUNT(*) AS spids_con_delta
FROM cpu_delta_ext
WHERE cpu_delta_ms IS NOT NULL
GROUP BY fecha_hora_captura
ORDER BY fecha_hora_captura;

-- Q8 — Focus on low/system SPIDs specifically (background threads: checkpoint, lazy writer, ghost cleanup, etc.)
-- during the 100% peak window (13:30-14:30 GMT = 10:30-11:30 UTC-3)
SELECT
    spid,
    fecha_hora_captura,
    cpu,
    cpu - LAG(cpu) OVER (PARTITION BY spid ORDER BY fecha_hora_captura) AS cpu_delta_ms,
    status,
    lastwaittype,
    loginame,
    program_name,
    comando_ejecutado
FROM PNSSRL_AuditSysprocesses
WHERE fecha_hora_captura BETWEEN '2026-07-27 13:15:00' AND '2026-07-27 14:45:00'
  AND spid < 50
ORDER BY spid, fecha_hora_captura;

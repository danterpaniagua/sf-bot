-- Event: 20260803_cpu_peaks_loadtest
-- Window: 2026-08-03 09:00-16:00 UTC-3 (Zabbix graph) = 12:00-19:00 GMT (server time)
-- Reported peaks (UTC-3): ~09:30-10:00 and ~14:00-15:00
-- Confirmed peaks from Zabbix screenshots (local UTC-3): ~10:00, ~14:15, ~14:45 -> GMT ~13:00, ~17:15, ~17:45

-- Q1 — Data availability check, extended window (covers both peaks + buffer)
SELECT
    CAST(fecha_hora_captura AS DATE) AS fecha,
    DATEPART(HOUR, fecha_hora_captura) AS hora,
    COUNT(DISTINCT fecha_hora_captura) AS snapshots,
    MIN(fecha_hora_captura) AS primer_snapshot,
    MAX(fecha_hora_captura) AS ultimo_snapshot
FROM PNSSRL_AuditSysprocesses
WHERE fecha_hora_captura >= '2026-08-03 12:00:00'
  AND fecha_hora_captura <  '2026-08-03 18:30:00'
GROUP BY CAST(fecha_hora_captura AS DATE), DATEPART(HOUR, fecha_hora_captura)
ORDER BY fecha, hora;

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
    WHERE fecha_hora_captura >= '2026-08-03 12:00:00'
      AND fecha_hora_captura <  '2026-08-03 18:30:00'
)
SELECT TOP 50 *
FROM cpu_delta
WHERE cpu_delta_ms IS NOT NULL
ORDER BY cpu_delta_ms DESC;

-- Q3 — Total CPU across ALL sessions per snapshot, vs. 16-core capacity
-- Capacity per ~5min snapshot interval = 16 cores * 300,000ms = 4,800,000 CPU-ms = 100%
WITH cpu_delta_all AS (
    SELECT
        spid,
        fecha_hora_captura,
        cpu - LAG(cpu) OVER (PARTITION BY spid ORDER BY fecha_hora_captura) AS cpu_delta_ms
    FROM PNSSRL_AuditSysprocesses
    WHERE fecha_hora_captura >= '2026-08-03 12:00:00'
      AND fecha_hora_captura <  '2026-08-03 18:30:00'
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

-- Q4 — Blocking check across the full window
SELECT
    fecha_hora_captura,
    spid,
    blocked,
    status,
    lastwaittype,
    waitresource,
    loginame,
    hostname,
    program_name,
    comando_ejecutado
FROM PNSSRL_AuditSysprocesses
WHERE fecha_hora_captura >= '2026-08-03 12:00:00'
  AND fecha_hora_captura <  '2026-08-03 18:30:00'
  AND blocked <> 0
ORDER BY fecha_hora_captura;

-- Q5 — Low/system SPIDs (<50) specifically during each of the three confirmed spikes
-- (blind spot identified in 20260727_cpu_peaks_loadtest: background threads not visible in top-50-by-user-session view)
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
WHERE spid < 50
  AND (
        (fecha_hora_captura BETWEEN '2026-08-03 12:45:00' AND '2026-08-03 13:15:00') OR  -- ~13:00 GMT peak
        (fecha_hora_captura BETWEEN '2026-08-03 17:00:00' AND '2026-08-03 17:30:00') OR  -- ~17:15 GMT peak
        (fecha_hora_captura BETWEEN '2026-08-03 17:30:00' AND '2026-08-03 18:00:00')     -- ~17:45 GMT peak
      )
ORDER BY spid, fecha_hora_captura;

-- Q6 — Distinct hosts/logins connected during the full window (12:00-18:30 GMT)
SELECT
    hostname,
    loginame,
    program_name,
    DB_NAME(dbid) AS database_name,
    COUNT(DISTINCT spid) AS spids_distintos,
    COUNT(*) AS filas_capturadas,
    MIN(fecha_hora_captura) AS primera_aparicion,
    MAX(fecha_hora_captura) AS ultima_aparicion
FROM PNSSRL_AuditSysprocesses
WHERE fecha_hora_captura >= '2026-08-03 12:00:00'
  AND fecha_hora_captura <  '2026-08-03 18:30:00'
GROUP BY hostname, loginame, program_name, DB_NAME(dbid)
ORDER BY spids_distintos DESC, filas_capturadas DESC;

-- Q7 — SQL Server start time (checks for a restart during/near the investigated window)
SELECT sqlserver_start_time, cpu_count, scheduler_count
FROM sys.dm_os_sys_info;

-- GITIN-2250 — cruce de los datos de WEBS con la base de SmartLoyalty (PNSSRL, solo lectura). Evento 2026-10-18.
-- El servidor SQL esta en GMT: ventanas UTC-3 -> GMT (+3 h).
--   V1  saturacion WEBS-02      14:03-15:28 (UTC-3) = 17:03-18:28 GMT
--   V2  segunda saturacion      16:34-17:10         = 19:34-20:10 GMT
--   V3  aumento de POST WEBS-02 17:10-18:20         = 20:10-21:20 GMT
--   V4  pico de Mobile 02       19:02-19:18         = 22:02-22:18 GMT
-- Fuentes: PNSSRL_AuditSysprocesses (fecha_hora_captura; cpu acumulado: se usa la diferencia entre capturas) y PNSSRL_TempdbProc (hora_captura).
-- Sin tablas temporales (CTE). SET STATISTICS IO/TIME ON: la salida cae en la pestaña Messages (SSMS); pegar tambien esa parte.
-- Pegar cada resultado de vuelta; se guarda en data/ con nombre descriptivo.

-- === Q1 — Servidor y disponibilidad de datos por ventana ===
USE PNSSRL;
SELECT @@SERVERNAME AS servidor, SYSUTCDATETIME() AS ahora_gmt;
WITH w AS (SELECT * FROM (VALUES ('V1','2026-10-18T17:03:00','2026-10-18T18:28:00'),('V2','2026-10-18T19:34:00','2026-10-18T20:10:00'),('V3','2026-10-18T20:10:00','2026-10-18T21:20:00'),('V4','2026-10-18T22:02:00','2026-10-18T22:18:00')) v(ventana,desde,hasta))
SELECT w.ventana, 'AuditSysprocesses' AS tabla, COUNT(*) AS filas, COUNT(DISTINCT a.fecha_hora_captura) AS capturas, MIN(a.fecha_hora_captura) AS primera, MAX(a.fecha_hora_captura) AS ultima
FROM w LEFT JOIN dbo.PNSSRL_AuditSysprocesses a ON a.fecha_hora_captura >= w.desde AND a.fecha_hora_captura < w.hasta GROUP BY w.ventana
UNION ALL
SELECT w.ventana, 'TempdbProc', COUNT(*), COUNT(DISTINCT t.hora_captura), MIN(t.hora_captura), MAX(t.hora_captura)
FROM w LEFT JOIN dbo.PNSSRL_TempdbProc t ON t.hora_captura >= w.desde AND t.hora_captura < w.hasta GROUP BY w.ventana
ORDER BY tabla, ventana;

-- === Q2 — CPU consumido por origen (hostname / programa / base), diferencia entre capturas consecutivas por SPID ===
USE PNSSRL;
SET STATISTICS IO ON; SET STATISTICS TIME ON;
WITH w AS (SELECT * FROM (VALUES ('V1','2026-10-18T17:03:00','2026-10-18T18:28:00'),('V2','2026-10-18T19:34:00','2026-10-18T20:10:00'),('V3','2026-10-18T20:10:00','2026-10-18T21:20:00'),('V4','2026-10-18T22:02:00','2026-10-18T22:18:00')) v(ventana,desde,hasta)),
x AS (
  SELECT w.ventana, a.spid, a.hostname, a.program_name, DB_NAME(a.dbid) AS base, a.fecha_hora_captura,
         a.cpu - LAG(a.cpu) OVER (PARTITION BY w.ventana, a.spid, a.hostname, a.program_name ORDER BY a.fecha_hora_captura) AS delta_cpu_ms
  FROM w JOIN dbo.PNSSRL_AuditSysprocesses a ON a.fecha_hora_captura >= w.desde AND a.fecha_hora_captura < w.hasta)
,
g AS (
  SELECT ventana, hostname, program_name, base, COUNT(*) AS capturas, SUM(CASE WHEN delta_cpu_ms > 0 THEN delta_cpu_ms ELSE 0 END) AS cpu_ms_total, COUNT(DISTINCT spid) AS spids,
         ROW_NUMBER() OVER (PARTITION BY ventana ORDER BY SUM(CASE WHEN delta_cpu_ms > 0 THEN delta_cpu_ms ELSE 0 END) DESC) AS rn
  FROM x GROUP BY ventana, hostname, program_name, base)
SELECT ventana, hostname, program_name, base, capturas, cpu_ms_total, spids FROM g WHERE rn <= 12 ORDER BY ventana, rn;
SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

-- === Q3 — Bloqueos por ventana (SPID bloqueante y espera) ===
USE PNSSRL;
WITH w AS (SELECT * FROM (VALUES ('V1','2026-10-18T17:03:00','2026-10-18T18:28:00'),('V2','2026-10-18T19:34:00','2026-10-18T20:10:00'),('V3','2026-10-18T20:10:00','2026-10-18T21:20:00'),('V4','2026-10-18T22:02:00','2026-10-18T22:18:00')) v(ventana,desde,hasta))
,
g AS (
  SELECT w.ventana, a.blocked AS spid_bloqueante, a.lastwaittype, DB_NAME(a.dbid) AS base, COUNT(*) AS filas_bloqueadas, COUNT(DISTINCT a.fecha_hora_captura) AS capturas, MIN(a.fecha_hora_captura) AS primera, MAX(a.fecha_hora_captura) AS ultima,
         ROW_NUMBER() OVER (PARTITION BY w.ventana ORDER BY COUNT(*) DESC) AS rn
  FROM w JOIN dbo.PNSSRL_AuditSysprocesses a ON a.fecha_hora_captura >= w.desde AND a.fecha_hora_captura < w.hasta
  WHERE a.blocked <> 0
  GROUP BY w.ventana, a.blocked, a.lastwaittype, DB_NAME(a.dbid))
SELECT ventana, spid_bloqueante, lastwaittype, base, filas_bloqueadas, capturas, primera, ultima FROM g WHERE rn <= 10 ORDER BY ventana, rn;

-- === Q4 — Esperas de las sesiones activas por ventana ===
USE PNSSRL;
WITH w AS (SELECT * FROM (VALUES ('V1','2026-10-18T17:03:00','2026-10-18T18:28:00'),('V2','2026-10-18T19:34:00','2026-10-18T20:10:00'),('V3','2026-10-18T20:10:00','2026-10-18T21:20:00'),('V4','2026-10-18T22:02:00','2026-10-18T22:18:00')) v(ventana,desde,hasta))
,
g AS (
  SELECT w.ventana, a.status, a.lastwaittype, COUNT(*) AS filas, COUNT(DISTINCT a.spid) AS spids, ROW_NUMBER() OVER (PARTITION BY w.ventana ORDER BY COUNT(*) DESC) AS rn
  FROM w JOIN dbo.PNSSRL_AuditSysprocesses a ON a.fecha_hora_captura >= w.desde AND a.fecha_hora_captura < w.hasta
  WHERE a.status IN ('running','runnable','suspended')
  GROUP BY w.ventana, a.status, a.lastwaittype)
SELECT ventana, status, lastwaittype, filas, spids FROM g WHERE rn <= 12 ORDER BY ventana, rn;

-- === Q5 — Sentencias con mayor CPU acumulado entre capturas, solo sesiones de servidores WEBS y MOBI ===
USE PNSSRL;
SET STATISTICS IO ON; SET STATISTICS TIME ON;
WITH w AS (SELECT * FROM (VALUES ('V1','2026-10-18T17:03:00','2026-10-18T18:28:00'),('V2','2026-10-18T19:34:00','2026-10-18T20:10:00'),('V3','2026-10-18T20:10:00','2026-10-18T21:20:00'),('V4','2026-10-18T22:02:00','2026-10-18T22:18:00')) v(ventana,desde,hasta)),
x AS (
  SELECT w.ventana, a.spid, a.hostname, LEFT(a.comando_ejecutado, 300) AS sentencia,
         a.cpu - LAG(a.cpu) OVER (PARTITION BY w.ventana, a.spid, a.hostname, a.program_name ORDER BY a.fecha_hora_captura) AS delta_cpu_ms
  FROM w JOIN dbo.PNSSRL_AuditSysprocesses a ON a.fecha_hora_captura >= w.desde AND a.fecha_hora_captura < w.hasta
  WHERE a.hostname LIKE '%WEBS%' OR a.hostname LIKE '%MOBI%')
,
g AS (
  SELECT ventana, hostname, sentencia, COUNT(*) AS capturas, SUM(CASE WHEN delta_cpu_ms > 0 THEN delta_cpu_ms ELSE 0 END) AS cpu_ms_total, MAX(CASE WHEN delta_cpu_ms > 0 THEN delta_cpu_ms ELSE 0 END) AS max_delta_ms,
         ROW_NUMBER() OVER (PARTITION BY ventana ORDER BY SUM(CASE WHEN delta_cpu_ms > 0 THEN delta_cpu_ms ELSE 0 END) DESC) AS rn
  FROM x GROUP BY ventana, hostname, sentencia)
SELECT ventana, hostname, sentencia, capturas, cpu_ms_total, max_delta_ms FROM g WHERE rn <= 10 ORDER BY ventana, rn;
SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

-- === Q6 — Sesiones con mayor uso de tempdb / lecturas por ventana (texto completo de la consulta) ===
USE PNSSRL;
WITH w AS (SELECT * FROM (VALUES ('V1','2026-10-18T17:03:00','2026-10-18T18:28:00'),('V2','2026-10-18T19:34:00','2026-10-18T20:10:00'),('V3','2026-10-18T20:10:00','2026-10-18T21:20:00'),('V4','2026-10-18T22:02:00','2026-10-18T22:18:00')) v(ventana,desde,hasta))
,
g AS (
  SELECT w.ventana, t.hora_captura, t.session_id, t.HOST_NAME, t.program_name, t.cpu_time, t.logical_reads, t.writes,
         t.OutStanding_internal_objects_page_counts AS pag_internas, t.granted_query_memory, LEFT(t.Query_Text, 600) AS consulta,
         ROW_NUMBER() OVER (PARTITION BY w.ventana ORDER BY t.cpu_time DESC, t.logical_reads DESC) AS rn
  FROM w JOIN dbo.PNSSRL_TempdbProc t ON t.hora_captura >= w.desde AND t.hora_captura < w.hasta)
SELECT ventana, hora_captura, session_id, HOST_NAME, program_name, cpu_time, logical_reads, writes, pag_internas, granted_query_memory, consulta FROM g WHERE rn <= 8 ORDER BY ventana, rn;

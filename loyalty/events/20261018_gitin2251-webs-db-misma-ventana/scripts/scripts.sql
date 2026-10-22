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

-- === Q7 — Capturas de la sesion que ejecutaba el trigger CustomerPointsLogAfterInsert (hora, SPID, CPU, espera) ===
USE PNSSRL;
WITH w AS (SELECT * FROM (VALUES ('V1','2026-10-18T17:03:00','2026-10-18T18:28:00'),('V2','2026-10-18T19:34:00','2026-10-18T20:10:00'),('V3','2026-10-18T20:10:00','2026-10-18T21:20:00')) v(ventana,desde,hasta)),
x AS (
  SELECT w.ventana, a.fecha_hora_captura, a.spid, a.hostname, a.status, a.lastwaittype, a.blocked, a.cpu,
         a.cpu - LAG(a.cpu) OVER (PARTITION BY w.ventana, a.spid, a.hostname, a.program_name ORDER BY a.fecha_hora_captura) AS delta_cpu_ms,
         LAG(a.fecha_hora_captura) OVER (PARTITION BY w.ventana, a.spid, a.hostname, a.program_name ORDER BY a.fecha_hora_captura) AS captura_previa,
         CASE WHEN a.comando_ejecutado LIKE '%CustomerPointsLogAfterInsert%' THEN 1 ELSE 0 END AS es_trigger
  FROM w JOIN dbo.PNSSRL_AuditSysprocesses a ON a.fecha_hora_captura >= w.desde AND a.fecha_hora_captura < w.hasta
  WHERE a.hostname LIKE '%WEBS%')
SELECT ventana, fecha_hora_captura, captura_previa, spid, hostname, status, lastwaittype, blocked, cpu, delta_cpu_ms
FROM x WHERE es_trigger = 1 ORDER BY ventana, fecha_hora_captura;

-- === Q8 — Indices de Sml.CustomerPointsLog y SmlSt.CustomerPointsLog (metadatos, solo lectura, base de produccion) ===
-- Las estadisticas de uso (dm_db_index_usage_stats) se reinician con el servicio SQL: leerlas junto con el ultimo reinicio.
USE [SmartFran.Solution.SmartLoyalty];
SELECT @@SERVERNAME AS servidor, (SELECT sqlserver_start_time FROM sys.dm_os_sys_info) AS inicio_servicio_gmt;
SELECT OBJECT_SCHEMA_NAME(i.object_id) AS esquema, OBJECT_NAME(i.object_id) AS tabla, i.index_id, i.name AS indice, i.type_desc, i.is_unique, i.is_primary_key, i.is_disabled, i.filter_definition,
       (SELECT STRING_AGG(c.name, ', ') WITHIN GROUP (ORDER BY ic.key_ordinal) FROM sys.index_columns ic JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
         WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 0) AS columnas_clave,
       (SELECT STRING_AGG(c.name, ', ') FROM sys.index_columns ic JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
         WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 1) AS columnas_incluidas,
       (SELECT SUM(ps.row_count) FROM sys.dm_db_partition_stats ps WHERE ps.object_id = i.object_id AND ps.index_id = i.index_id) AS filas,
       (SELECT SUM(ps.used_page_count) * 8 / 1024 FROM sys.dm_db_partition_stats ps WHERE ps.object_id = i.object_id AND ps.index_id = i.index_id) AS mb,
       u.user_seeks, u.user_scans, u.user_lookups, u.user_updates, u.last_user_seek, u.last_user_scan
FROM sys.indexes i
LEFT JOIN sys.dm_db_index_usage_stats u ON u.database_id = DB_ID() AND u.object_id = i.object_id AND u.index_id = i.index_id
WHERE i.object_id IN (OBJECT_ID(N'Sml.CustomerPointsLog'), OBJECT_ID(N'SmlSt.CustomerPointsLog'))
ORDER BY esquema, tabla, i.index_id;

-- === Q9 — Columnas reales de los indices de Sml.CustomerPointsLog (sin ordenar ni transformar) y particiones ===
-- Verifica si LogDate es columna clave real de IX_CustomerId o la agrega la particion (key_ordinal / partition_ordinal / is_included_column).
USE [SmartFran.Solution.SmartLoyalty];
SELECT i.index_id, i.name AS indice, ic.index_column_id, c.name AS columna, ic.key_ordinal, ic.partition_ordinal, ic.is_included_column, ic.is_descending_key, ds.name AS destino, ds.type_desc AS tipo_destino
FROM sys.indexes i
JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
JOIN sys.data_spaces ds ON ds.data_space_id = i.data_space_id
WHERE i.object_id = OBJECT_ID(N'Sml.CustomerPointsLog') AND i.index_id IN (1, 8, 13)
ORDER BY i.index_id, ic.index_column_id;
SELECT p.index_id, COUNT(*) AS particiones, SUM(p.rows) AS filas, MIN(p.rows) AS min_filas, MAX(p.rows) AS max_filas
FROM sys.partitions p WHERE p.object_id = OBJECT_ID(N'Sml.CustomerPointsLog') AND p.index_id IN (1, 8) GROUP BY p.index_id;

-- === Q10 — Zona horaria de Sml.CustomerPointsLog.LogDate (hora del servidor frente a los ultimos LogDate, solo lectura, base de produccion) ===
USE [SmartFran.Solution.SmartLoyalty];
SELECT SYSDATETIME() AS ahora_servidor, SYSUTCDATETIME() AS ahora_utc;
SELECT TOP (5) LogDate FROM Sml.CustomerPointsLog WITH (NOLOCK) ORDER BY LogDate DESC;

-- === Q11 — Clientes con inserts en Sml.CustomerPointsLog entre 17:10 y 17:20 GMT del 2026-10-18 (V1, sesion 117 de WEBS-02) y tamaño de su historial (solo lectura, base de produccion) ===
-- LogDate es datetimeoffset en GMT (+00:00, Q10). El rango sobre LogDate usa la clave del indice agrupado; el conteo por cliente usa IX_CustomerId (no lee Points ni Note).
-- Tope de 500 clientes en la ventana y MAXDOP 1 para limitar la carga. CustomerId es un identificador interno: no se copia a ops.md ni a correos.
USE [SmartFran.Solution.SmartLoyalty];
SET STATISTICS IO ON; SET STATISTICS TIME ON;
WITH ventana AS (
  SELECT TOP (500) CustomerId, COUNT(*) AS filas_insertadas, MIN(LogDate) AS primera, MAX(LogDate) AS ultima, MIN(EventTypeCode) AS evento_min, MAX(EventTypeCode) AS evento_max, SUM(Points) AS puntos_insertados
  FROM Sml.CustomerPointsLog WITH (NOLOCK)
  WHERE LogDate >= '2026-10-18T17:10:00+00:00' AND LogDate < '2026-10-18T17:20:00+00:00'
  GROUP BY CustomerId
  ORDER BY COUNT(*) DESC)
SELECT TOP (30) v.CustomerId, v.filas_insertadas, v.primera, v.ultima, v.evento_min, v.evento_max, v.puntos_insertados, h.filas_historial
FROM ventana v
CROSS APPLY (SELECT COUNT_BIG(*) AS filas_historial FROM Sml.CustomerPointsLog c WITH (NOLOCK) WHERE c.CustomerId = v.CustomerId) h
ORDER BY h.filas_historial DESC
OPTION (MAXDOP 1);
SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

-- === Q12 — Inserts en Sml.CustomerPointsLog entre 17:00 y 17:30 GMT del 2026-10-18: filas por minuto y los LogDate con mas filas (indicio de insercion masiva), solo lectura, base de produccion ===
-- No devuelve identificadores de cliente. El rango sobre LogDate usa la clave del indice agrupado.
USE [SmartFran.Solution.SmartLoyalty];
SET STATISTICS IO ON; SET STATISTICS TIME ON;
SELECT CONVERT(char(16), LogDate, 120) AS minuto_gmt, COUNT_BIG(*) AS filas, COUNT(DISTINCT CustomerId) AS clientes
FROM Sml.CustomerPointsLog WITH (NOLOCK)
WHERE LogDate >= '2026-10-18T17:00:00+00:00' AND LogDate < '2026-10-18T17:30:00+00:00'
GROUP BY CONVERT(char(16), LogDate, 120) ORDER BY minuto_gmt
OPTION (MAXDOP 1);
SELECT TOP (15) LogDate, COUNT_BIG(*) AS filas, COUNT(DISTINCT CustomerId) AS clientes, MIN(EventTypeCode) AS evento_min, MAX(EventTypeCode) AS evento_max
FROM Sml.CustomerPointsLog WITH (NOLOCK)
WHERE LogDate >= '2026-10-18T17:00:00+00:00' AND LogDate < '2026-10-18T17:30:00+00:00'
GROUP BY LogDate ORDER BY COUNT_BIG(*) DESC
OPTION (MAXDOP 1);
SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

-- === Q13 — Query Store de la base de produccion: estado y consultas con mas CPU por intervalo entre 17:00 y 18:30 GMT del 2026-10-18 (solo lectura) ===
-- Si Query Store esta apagado, el primer resultado lo muestra y el segundo sale vacio. Los tiempos de Query Store estan en microsegundos y se pasan a ms.
USE [SmartFran.Solution.SmartLoyalty];
SELECT actual_state_desc, desired_state_desc, readonly_reason, interval_length_minutes, query_capture_mode_desc, current_storage_size_mb, max_storage_size_mb, stale_query_threshold_days
FROM sys.database_query_store_options;
WITH i AS (SELECT runtime_stats_interval_id, start_time, end_time FROM sys.query_store_runtime_stats_interval WHERE end_time > '2026-10-18T17:00:00+00:00' AND start_time < '2026-10-18T18:30:00+00:00'),
s AS (
  SELECT p.query_id, i.start_time, SUM(r.count_executions) AS ejecuciones, SUM(r.avg_cpu_time * r.count_executions) / 1000.0 AS cpu_ms_total, MAX(r.max_cpu_time) / 1000.0 AS max_cpu_ms
  FROM sys.query_store_runtime_stats r JOIN i ON i.runtime_stats_interval_id = r.runtime_stats_interval_id JOIN sys.query_store_plan p ON p.plan_id = r.plan_id
  GROUP BY p.query_id, i.start_time),
g AS (SELECT s.*, ROW_NUMBER() OVER (PARTITION BY s.start_time ORDER BY s.cpu_ms_total DESC) AS rn FROM s)
SELECT g.start_time, g.query_id, g.ejecuciones, g.cpu_ms_total, g.max_cpu_ms, OBJECT_NAME(q.object_id) AS objeto, LEFT(qt.query_sql_text, 200) AS texto
FROM g JOIN sys.query_store_query q ON q.query_id = g.query_id JOIN sys.query_store_query_text qt ON qt.query_text_id = q.query_text_id
WHERE g.rn <= 8 ORDER BY g.start_time, g.rn;

-- === Q14 — CPU maxima de una sola ejecucion desde que el plan esta en cache: trigger CustomerPointsLogAfterInsert y sentencias con mas de 5 s de CPU (DMV, solo lectura, base de produccion) ===
-- Las estadisticas empiezan en cached_time / creation_time (se pierden al reiniciar el servicio, al recompilar o al sacar el plan de cache): comprobar que cubren 2026-10-18 17:11-17:16 GMT.
-- Los tiempos de los DMV estan en microsegundos y se pasan a ms.
USE [SmartFran.Solution.SmartLoyalty];
SELECT OBJECT_NAME(ts.object_id, ts.database_id) AS trigger_, ts.cached_time, ts.last_execution_time, ts.execution_count, ts.total_worker_time / 1000 AS cpu_ms_total,
       ts.total_worker_time / NULLIF(ts.execution_count, 0) / 1000.0 AS cpu_ms_medio, ts.max_worker_time / 1000 AS cpu_ms_max, ts.max_elapsed_time / 1000 AS transcurrido_ms_max, ts.max_logical_reads
FROM sys.dm_exec_trigger_stats ts
WHERE ts.database_id = DB_ID() AND OBJECT_NAME(ts.object_id, ts.database_id) = N'CustomerPointsLogAfterInsert';
SELECT TOP (15) qs.creation_time, qs.last_execution_time, qs.execution_count, qs.total_worker_time / 1000 AS cpu_ms_total, qs.max_worker_time / 1000 AS cpu_ms_max, qs.max_elapsed_time / 1000 AS transcurrido_ms_max, qs.max_logical_reads, st.dbid,
       LEFT(SUBSTRING(st.text, (qs.statement_start_offset / 2) + 1, ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text) ELSE qs.statement_end_offset END - qs.statement_start_offset) / 2) + 1), 200) AS sentencia
FROM sys.dm_exec_query_stats qs CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
WHERE qs.max_worker_time > 5000000
ORDER BY qs.max_worker_time DESC;

-- === Q15 — Filas de PNSSRL_TempdbProc de WEBS-02 y de la sesion 117 entre 17:10 y 17:17 GMT del 2026-10-18 (CPU de la peticion, lecturas, texto), solo lectura ===
-- cpu_time es de la peticion en curso (no acumulado de la sesion). Sin top: son pocas filas por ventana (V1 tiene 48 en total).
USE PNSSRL;
SELECT t.hora_captura, t.session_id, t.HOST_NAME, t.program_name, t.cpu_time, t.logical_reads, t.writes, t.OutStanding_internal_objects_page_counts AS pag_internas, t.granted_query_memory, LEFT(t.Query_Text, 400) AS consulta
FROM dbo.PNSSRL_TempdbProc t
WHERE t.hora_captura >= '2026-10-18T17:10:00' AND t.hora_captura < '2026-10-18T17:17:00'
  AND (t.HOST_NAME LIKE '%WEBS-02%' OR t.session_id = 117)
ORDER BY t.hora_captura, t.session_id;

-- === Q16 — Todas las capturas de la sesion 117 de WEBS-02 entre 17:00 y 17:30 GMT del 2026-10-18 (estado, espera, CPU, texto), solo lectura ===
-- Q7 solo devolvio las capturas dentro del trigger; esta trae las anteriores y posteriores de la misma sesion para ver que hacia antes y despues de los 97.5 s.
USE PNSSRL;
SELECT a.fecha_hora_captura, a.spid, a.hostname, a.program_name, a.status, a.lastwaittype, a.blocked, a.cpu,
       a.cpu - LAG(a.cpu) OVER (PARTITION BY a.spid, a.hostname, a.program_name ORDER BY a.fecha_hora_captura) AS delta_cpu_ms,
       LEFT(a.comando_ejecutado, 400) AS comando
FROM dbo.PNSSRL_AuditSysprocesses a
WHERE a.fecha_hora_captura >= '2026-10-18T17:00:00' AND a.fecha_hora_captura < '2026-10-18T17:30:00'
  AND a.hostname LIKE '%WEBS-02%' AND a.spid = 117
ORDER BY a.fecha_hora_captura;

-- === Q17 — Las 10 sesiones de WEBS-02 con mas CPU en V1 (17:03-18:28 GMT): total, captura del mayor delta y texto en esa captura, solo lectura ===
USE PNSSRL;
WITH x AS (
  SELECT a.fecha_hora_captura, a.spid, a.program_name, a.cpu,
         a.cpu - LAG(a.cpu) OVER (PARTITION BY a.spid, a.hostname, a.program_name ORDER BY a.fecha_hora_captura) AS d,
         LEFT(a.comando_ejecutado, 300) AS cmd
  FROM dbo.PNSSRL_AuditSysprocesses a
  WHERE a.fecha_hora_captura >= '2026-10-18T17:03:00' AND a.fecha_hora_captura < '2026-10-18T18:28:00'
    AND a.hostname LIKE '%WEBS-02%'),
y AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY spid, program_name ORDER BY d DESC) AS rn,
         SUM(d) OVER (PARTITION BY spid, program_name) AS total_ms
  FROM x WHERE d > 0)
SELECT TOP 10 spid, program_name, total_ms, fecha_hora_captura AS captura_mayor_delta, d AS delta_mayor_ms, cmd
FROM y WHERE rn = 1 ORDER BY total_ms DESC;

-- === Q18 — Clientes con inserts en Sml.CustomerPointsLog entre 17:11 y 17:16 GMT del 2026-10-18 (los 5 minutos en que la sesion 117 uso 97.5 s de CPU), sin tope por filas insertadas, ordenados por tamaño de historial, solo lectura, base de produccion ===
-- Q11 tomaba los 500 clientes con mas filas insertadas de 17:10-17:20; un cliente con 1 fila insertada y un historial enorme podia quedar fuera. Aqui entran todos los de la ventana de 5 minutos.
-- LogDate es datetimeoffset en GMT. El conteo por cliente usa IX_CustomerId (no lee Points ni Note). MAXDOP 1 para limitar la carga. CustomerId es un identificador interno: no se copia a ops.md ni a correos.
USE [SmartFran.Solution.SmartLoyalty];
SET STATISTICS IO ON; SET STATISTICS TIME ON;
WITH ventana AS (
  SELECT CustomerId, COUNT(*) AS filas_insertadas, MIN(LogDate) AS primera, MAX(LogDate) AS ultima
  FROM Sml.CustomerPointsLog WITH (NOLOCK)
  WHERE LogDate >= '2026-10-18T17:11:00+00:00' AND LogDate < '2026-10-18T17:16:00+00:00'
  GROUP BY CustomerId)
SELECT TOP (20) v.CustomerId, v.filas_insertadas, v.primera, v.ultima, h.filas_historial, (SELECT COUNT(*) FROM ventana) AS clientes_en_ventana
FROM ventana v
CROSS APPLY (SELECT COUNT_BIG(*) AS filas_historial FROM Sml.CustomerPointsLog c WITH (NOLOCK) WHERE c.CustomerId = v.CustomerId) h
ORDER BY h.filas_historial DESC
OPTION (MAXDOP 1);
SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

-- Q19 (GITIN-2251, read-only, database [SmartFran.Solution.SmartLoyalty]): do rows inserted together for one customer (same CustomerId + LogDate, 17:11-17:16 GMT)
-- make the trigger [Sml].[CustomerPointsLogAfterInsert] multiply the customer's total? Compares the points the trigger left in SmlSt with the real sum of the log.
-- filas_posteriores = rows of the customer inserted after that group (0 means SmlSt should still hold what the trigger computed for that insert).
USE [SmartFran.Solution.SmartLoyalty];
WITH grupos AS (
    SELECT CustomerId, LogDate, COUNT(*) AS filas_en_grupo
    FROM Sml.CustomerPointsLog
    WHERE LogDate >= '2026-10-18T17:11:00+00:00' AND LogDate < '2026-10-18T17:16:00+00:00'
    GROUP BY CustomerId, LogDate
    HAVING COUNT(*) > 1
), top20 AS (
    SELECT TOP (20) CustomerId, LogDate, filas_en_grupo FROM grupos ORDER BY filas_en_grupo DESC
)
SELECT g.CustomerId, g.LogDate, g.filas_en_grupo,
       (SELECT COUNT(*) FROM Sml.CustomerPointsLog c WHERE c.CustomerId = g.CustomerId) AS filas_historial,
       (SELECT COUNT(*) FROM Sml.CustomerPointsLog c WHERE c.CustomerId = g.CustomerId AND c.LogDate > g.LogDate) AS filas_posteriores,
       (SELECT SUM(c.Points) FROM Sml.CustomerPointsLog c WHERE c.CustomerId = g.CustomerId) AS puntos_reales,
       s.Points AS puntos_smlst, s.LastLogDate AS smlst_ultimo_logdate,
       (SELECT COUNT(*) FROM grupos) AS grupos_en_ventana
FROM top20 g
LEFT JOIN SmlSt.CustomerPointsLog s ON s.CustomerId = g.CustomerId
ORDER BY g.filas_en_grupo DESC
OPTION (MAXDOP 1);

-- Event: 20261015_gitin2241-mobile-episodio-previo-0614-0655 (GITIN-2241)
-- SOLO LECTURA (SELECT). El servidor SQL (SFCG-DB01) esta en GMT = UTC. Episodio visto en Zabbix: 2026-10-15 09:15:27 a 09:56:29 UTC (jueves).
-- Hipotesis a comprobar (no verificada): el trabajo de mantenimiento de indices del jueves (docs: 09:00 UTC el general, 09:15 UTC el de CustomerPointsLog) mantuvo un bloqueo que dejo colgado el login.

-- Q1: historial de los trabajos PNSSRL_Mantenimiento* del 2026-10-12 al 2026-10-16: inicio, fin y resultado por paso (step_id 0 = resultado del trabajo)
USE msdb;
SELECT
    j.name AS trabajo,
    h.step_id,
    h.step_name,
    msdb.dbo.agent_datetime(h.run_date, h.run_time) AS inicio_gmt,
    DATEADD(SECOND, (h.run_duration / 10000) * 3600 + ((h.run_duration / 100) % 100) * 60 + (h.run_duration % 100),
            msdb.dbo.agent_datetime(h.run_date, h.run_time)) AS fin_gmt,
    h.run_duration AS duracion_hhmmss,
    h.run_status
FROM msdb.dbo.sysjobhistory AS h
JOIN msdb.dbo.sysjobs AS j ON j.job_id = h.job_id
WHERE j.name LIKE 'PNSSRL_Mantenimiento%'
  AND h.run_date BETWEEN 20261012 AND 20261016
ORDER BY inicio_gmt, j.name, h.step_id;

-- Q2: sesiones de SQL Agent capturadas el 2026-10-15 entre 09:00 y 10:05 GMT: que paso del trabajo corria y cuando
USE PNSSRL;
SELECT
    fecha_hora_captura,
    spid,
    blocked,
    status,
    cmd,
    program_name,
    lastwaittype,
    LEFT(comando_ejecutado, 300) AS comando_ejecutado
FROM PNSSRL_AuditSysprocesses
WHERE fecha_hora_captura BETWEEN '2026-10-15 09:00:00' AND '2026-10-15 10:05:00'
  AND program_name LIKE 'SQLAgent%'
ORDER BY fecha_hora_captura, spid;

-- Q3: sesiones bloqueadas en la misma ventana (blocked <> 0): cuantas por captura y que consulta esperaba
USE PNSSRL;
SELECT
    fecha_hora_captura,
    COUNT(*) AS sesiones_bloqueadas,
    MIN(blocked) AS bloqueador_min,
    MAX(blocked) AS bloqueador_max,
    MAX(lastwaittype) AS espera,
    MAX(LEFT(comando_ejecutado, 200)) AS ejemplo_consulta
FROM PNSSRL_AuditSysprocesses
WHERE fecha_hora_captura BETWEEN '2026-10-15 09:00:00' AND '2026-10-15 10:05:00'
  AND blocked <> 0
GROUP BY fecha_hora_captura
ORDER BY fecha_hora_captura;

-- Q4: que hacia la sesion 109 (la que mantenia bloqueado al reconstructor, spid 91) en la ventana: capturas de la sesion 109 y de la 91
USE PNSSRL;
SELECT
    fecha_hora_captura,
    spid,
    blocked,
    status,
    cmd,
    program_name,
    hostname,
    lastwaittype,
    waitresource,
    LEFT(comando_ejecutado, 400) AS comando_ejecutado
FROM PNSSRL_AuditSysprocesses
WHERE fecha_hora_captura BETWEEN '2026-10-15 09:00:00' AND '2026-10-15 10:05:00'
  AND spid IN (109, 91)
ORDER BY fecha_hora_captura, spid;

-- Q5: que consultas esperaban (blocked <> 0) en la ventana, agrupadas por texto (primeros 150 caracteres) y programa: cuantas veces y primera/ultima captura
USE PNSSRL;
SELECT TOP 40
    LEFT(comando_ejecutado, 150) AS consulta,
    program_name,
    hostname,
    COUNT(*) AS apariciones,
    MIN(fecha_hora_captura) AS primera,
    MAX(fecha_hora_captura) AS ultima
FROM PNSSRL_AuditSysprocesses
WHERE fecha_hora_captura BETWEEN '2026-10-15 09:00:00' AND '2026-10-15 10:05:00'
  AND blocked <> 0
GROUP BY LEFT(comando_ejecutado, 150), program_name, hostname
ORDER BY COUNT(*) DESC;

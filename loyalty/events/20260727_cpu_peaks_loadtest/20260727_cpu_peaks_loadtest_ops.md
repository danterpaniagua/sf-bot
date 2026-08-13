# [TAREA] Picos de CPU (50%/100%) en VM de base de datos durante load test de Grido

## Resumen

Durante un load test de Grido ejecutado el 27/07/2026, se reportaron picos de CPU a nivel de sistema operativo en la VM de base de datos (`SFCG-DB01`), observados en el Zabbix legado (instancia no migrada, sin API): un plateau de "CPU Utilization" en 50% entre las 10:00 y las 12:00 (UTC-3), y picos de "CPU User Time" cerca de las 08:00 y las 09:00 (UTC-3), con un pico de 100% sostenido entre las 10:30 y las 11:30 (UTC-3). La investigación sobre las tablas de captura de `PNSSRL` (motor SQL Server) para toda la ventana reportada (08:00-12:00 UTC-3) no encontró ninguna sesión ni el total agregado de todas las sesiones superando ~6% de la capacidad de 16 núcleos del servidor, incluyendo el intervalo exacto del pico de 100%. Se descarta una consulta o sesión de SQL Server como causa; la causa real queda fuera del alcance de esta tabla de captura.

## Tabla resumen

| Campo | Valor |
|---|---|
| Sistema | SmartLoyalty SQL Server (`PNSSRL`) — `SFCG-DB01` |
| Severidad | Media |
| Detectado | 2026-07-27 08:00–11:30 (UTC-3), durante load test de Grido |
| Resuelto | Se descarta causa a nivel de motor SQL Server (sesiones/consultas). Causa real pendiente de investigación a nivel de sistema operativo/VM — fuera del alcance de las tablas de captura de `PNSSRL` |
| Responsable | Dante Paniagua |

## Causa raíz

No se identificó una causa a nivel de motor SQL Server. El total de CPU sumado de todas las sesiones capturadas en `PNSSRL_AuditSysprocesses` se mantuvo entre ~4% y ~6% de la capacidad de 16 núcleos durante toda la ventana reportada (08:00–12:00 UTC-3 = 11:00–15:00 GMT), incluyendo el tramo exacto del pico de 100% (10:30–11:30 UTC-3). El único consumidor crónico identificado (SPID 151, job de sincronización de `CustomerPointsLog`) finalizó su actividad intensa ~14 minutos antes de que comenzara ese pico, y su aporte máximo nunca superó ~6% del total. La causa de los picos de 50%/100% observados por Zabbix está, por lo tanto, fuera del alcance de lo que esta tabla de captura puede diagnosticar: o bien un proceso ajeno a SQL Server en el mismo sistema operativo, o un hilo interno de SQL Server (checkpoint, lazy writer, limpieza de ghost records) que la captura actual no registra.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | El total de CPU sumado de todas las sesiones SQL Server nunca superó ~6% de la capacidad de 16 núcleos en ninguna captura de la ventana 08:00-12:00 (UTC-3), incluyendo el intervalo exacto del pico reportado de 100% | Alto — contradice que la causa sea una consulta/sesión de SQL Server |
| H2 | Las sesiones o hilos de sistema (SPID<50: checkpoint, lazy writer, limpieza de ghost records) no aparecen en `PNSSRL_AuditSysprocesses` — la tabla de captura no las registra | Medio — punto ciego real en el diagnóstico, no evidencia de ausencia |
| H3 | No se registró bloqueo (`blocked=0`) en toda la ventana reportada, descartando una repetición del patrón de bloqueo del incidente 2026-07-23 (`CustomerPointsLog`/load test) | Informativo |
| H4 | SPID 151 (login `sfsqlusr`, host `SFCG-TO-01`, TaskOperatorService) ejecutó de forma continua un job paginado de sincronización sobre `CustomerPointsLog` entre las 11:01 y 13:16 GMT, saturando cerca de un núcleo completo, pero representando solo ~4-6% del total de 16 núcleos | Bajo — impacto real limitado, y su ventana de actividad termina antes de que comience el pico de 100% reportado |
| H5 | El mismo job (mismo login+host+patrón de consulta) se ejecuta prácticamente todos los días dentro de la ventana de retención de 90 días — confirmado como rutina programada, no disparado por el load test | Informativo |

## Recursos afectados

| Recurso | Observación |
|---|---|
| `SFCG-DB01` (VM de base de datos, `PNSSRL` / `SmartFran.Solution.SmartLoyalty`) | Picos de CPU 50%/100% observados a nivel de sistema operativo (Zabbix legado); sin correlato en la actividad de sesiones SQL Server |
| SPID 151 / login `sfsqlusr` / host `SFCG-TO-01` (TaskOperatorService) | Consumidor crónico de CPU (job diario de sincronización de `CustomerPointsLog`); descartado como causa de los picos reportados |

## Queries ejecutadas

Ver `20260727_cpu_peaks_loadtest_scripts.sql`.

| # | Query | Propósito |
|---|---|---|
| Q1 | Chequeo de disponibilidad de datos (ventana inicial) | Confirmar cobertura de captura para 11:00-14:00 GMT |
| Q2 | Delta de CPU por SPID entre snapshots consecutivos (ventana inicial) | Identificar sesiones con consumo de CPU elevado |
| Q3 | `sys.dm_os_sys_info` | Confirmar cantidad de núcleos lógicos del servidor (16) |
| Q4 | Patrón histórico del job SPID 151 (login+host+query) sobre 90 días | Confirmar si el job es rutina diaria o disparado por el load test |
| Q5 | Total de CPU de todas las sesiones por snapshot, normalizado a capacidad de 16 núcleos (ventana inicial) | Comparar el total agregado contra los picos reportados |
| Q6 | Chequeo de disponibilidad de datos (ventana extendida 11:00-15:00 GMT) | Cubrir la ventana completa del pico reportado |
| Q7 | Total de CPU de todas las sesiones por snapshot (ventana extendida) | Confirmar que el patrón de bajo consumo se mantiene durante todo el pico de 100% |
| Q8 | SPIDs de sistema (<50) durante el pico de 100% (13:15-14:45 GMT) | Buscar actividad de hilos internos de SQL Server — resultado vacío (punto ciego, ver H2) |

## Acciones propuestas

1. (SRE) Configurar un Data Collector Set de Performance Monitor en `SFCG-DB01` vía `logman` (buffer circular, contadores `\Process(*)\% Processor Time` + `\ID Process` y `\Processor(*)\% User Time` / `\% Privileged Time` por núcleo, intervalo de 15s) para quedar corriendo de forma permanente y no depender de que alguien esté mirando en el momento exacto del pico. Además, durante la ventana horaria de un próximo load test, tener Resource Monitor abierto en vivo en `SFCG-DB01` como cruce manual (permite ver también actividad de disco/red por proceso, útil para descartar un backup o escaneo de antivirus). Objetivo: identificar el proceso responsable de los picos de CPU fuera del motor SQL Server.
2. (SRE) Evaluar si la tabla de captura `PNSSRL_AuditSysprocesses` puede extenderse para incluir SPIDs de sistema (<50), dado que actualmente no los registra y esto limita el diagnóstico de hilos internos de SQL Server.
3. (SRE) Evaluar migrar o consolidar el monitoreo de CPU de la VM de base de datos a la instancia Zabbix vigente (`sf-monitoreo.smartfran.com`), dado que actualmente se encuentra en una instancia Zabbix 5 no migrada y sin API, lo que dificultó la correlación en esta investigación.

## Hallazgos secundarios

- El host Zabbix `SFCG-DB01` (hostid 10611, instancia vigente `sf-monitoreo.smartfran.com`) tiene como nombre visible "Loyalty DB CLON", pese a ser el servidor de producción — nomenclatura confusa que generó una hipótesis descartada de estar analizando la VM equivocada. Se confirmó que es producción; el clon real es un host distinto (`SFCG-DB01-CLON`, mayormente apagado). Vale la pena corregir el nombre visible en Zabbix para evitar confusión futura.

# Eventos — 20260727_cpu_peaks_loadtest

## 2026-07-28 12:00 — Apertura de investigación

Abrí la investigación a partir de un reporte de picos de CPU (50% x2, 100% x1) observados durante un load test de Grido el 27/07/2026, en la ventana 08:00-11:00 (UTC-3). Convertí la ventana a hora de servidor (GMT) y verifiqué disponibilidad de datos en `PNSSRL_AuditSysprocesses`.

## 2026-07-28 12:03 — Identificación de SPID 151 como principal consumidor de CPU

Ejecuté el delta de CPU por SPID entre snapshots consecutivos (Q2) y detecté que el SPID 151 (login `sfsqlusr`, host `SFCG-TO-01`, TaskOperatorService) dominó el consumo de CPU entre las 11:01 y 13:16 GMT, ejecutando un job paginado de sincronización sobre `Sml.CustomerPointsLog`. Descarté el patrón de bloqueo del incidente 2026-07-23 (`blocked=0` en toda la ventana).

## 2026-07-28 12:04 — Revisión de magnitud: 16 núcleos y patrón histórico del job

Confirmé que el servidor tiene 16 núcleos lógicos (Q3), lo que implica que un solo SPID saturando un núcleo representa apenas ~6% de la capacidad total — insuficiente para explicar picos de 50%/100%. Confirmé además (Q4) que el job de SPID 151 se ejecuta prácticamente todos los días dentro de la ventana de retención de 90 días, por lo que es rutina y no fue disparado por el load test.

## 2026-07-28 12:06 — Total agregado de CPU muy por debajo de lo reportado

Sumé el delta de CPU de todas las sesiones por snapshot (Q5) y confirmé que el total nunca superó ~6% de la capacidad de 16 núcleos en la ventana inicial capturada.

## 2026-07-28 12:xx — Aclaración de fuente de la métrica y VM correcta

Identifiqué que el host Zabbix `SFCG-DB01` (hostid 10611, instancia vigente) solo expone contadores de instancia SQL Server (vía ODBC), sin ítems de CPU a nivel de sistema operativo. Se confirmó que el gráfico de CPU reportado corresponde a una VM monitoreada en una instancia Zabbix legada (versión 5, no migrada, sin API), y que el hostid 10611 —pese a su nombre visible "Loyalty DB CLON"— es efectivamente el servidor de producción (el clon real es `SFCG-DB01-CLON`, mayormente apagado).

## 2026-07-28 12:xx — Valores reales del pico reportados manualmente

Se reportaron los valores exactos leídos del gráfico legado: "CPU Utilization" en 50% entre las 10:00 y las 12:00 (UTC-3), y "CPU User Time" con picos menores cerca de las 08:00 y las 09:00 (UTC-3) y un pico de 100% sostenido entre las 10:30 y las 11:30 (UTC-3).

## 2026-07-28 12:42 — Confirmación en ventana extendida: SQL Server descartado como causa

Extendí la ventana de consulta a 11:00-15:00 GMT (Q6, Q7) para cubrir el pico completo. El total de CPU de todas las sesiones se mantuvo por debajo del 1% durante todo el pico de 100% reportado (13:30-14:30 GMT). Consulté además los SPIDs de sistema (<50) durante ese mismo intervalo (Q8) y no encontré ningún registro — la tabla de captura no incluye hilos internos de SQL Server, dejando un punto ciego real en el diagnóstico.

Con esta evidencia, descarté una consulta o sesión de SQL Server como causa de los picos de CPU reportados. Cerré la investigación con la causa real pendiente de análisis a nivel de sistema operativo/VM, fuera del alcance de esta tabla de captura.

# [JIRA] Incidente: Pico de CPU en SFCG-DB01 — Corrida ETL retrasada tras reinicio de VM (15/07/2026)

**Tipo:** Incidente de rendimiento
**Severidad:** Alta
**Servidor:** SFCG-DB01 — SQL Server 2022 Standard 16.0.4075.1
**Base de datos afectada:** SmartFran.Solution.SmartLoyalty
**Ventana del evento:** 15/07/2026 17:00–19:56 UTC-3 (20:00–22:56 GMT)
**Reportado por:** Dante Paniagua (a partir de aviso de campaña push de Grido)

---

## Descripción

Grido lanzó una campaña push con tres envíos el 15/07/2026 a las 14:00, 15:00 y 16:00 UTC-3. A partir de las 17:00 UTC-3 se registraron picos de uso de CPU superiores al 70% en SFCG-DB01, sostenidos durante aproximadamente dos horas. La investigación se realizó sobre las tablas de captura de `PNSSRL` (72 snapshots, ventana completa cubierta).

**Nota:** la hipótesis inicial (la campaña generó el volumen que causó el pico) fue descartada al revisar los límites reales de ejecución del proceso ETL — ver Causa raíz.

---

## Causa raíz

**Causa disparadora:** el 15/07/2026 la VM de base de datos fue reiniciada entre las 04:30 y las 05:00 UTC-3 (07:30–08:00 GMT), lo que provocó que las tareas ETL programadas se reprogramaran. Ese horario cae apenas minutos después del disparo diario habitual de la operación `CustomerPointsLog` (~07:25 GMT / ~04:25 UTC-3) — consistente con que el reinicio interrumpió esa corrida antes de completarse. La operación no se ejecutó en su horario habitual ese día y se reprogramó para las 20:53:40 GMT (17:53 UTC-3) — en pleno horario de actividad y coincidiendo con la ventana de la campaña de Grido.

**Causa estructural (preexistente, no introducida por la campaña):** la operación ETL `CustomerPointsLog` (`Etl.EtlOperationConfig`, Id = 6, `ToTable = dbo.CustomerPointsLog`, ejecutada por TaskOperatorService `SFCG-TO-01` con el login `sfsqlusr`) tiene un `FromQuery` con un predicado `OR` no sargable que combina rangos sobre `cpl.LogDate` y `c.CreatedDate`, lo que impide un acceso por índice eficiente. El framework ETL antepone además una consulta de conteo (`COUNT(*) OVER()`) sobre la misma query antes de paginar. Esto hace que la operación rinda de forma crónica entre **~10 y ~20 filas/segundo**, consistente en las 23 ejecuciones diarias revisadas de los últimos 30 días (ver Hallazgos) — no es una degradación puntual del 15/07, sino el comportamiento habitual de esta consulta desde antes de esa fecha.

**Por qué se volvió visible recién ahora:** al ejecutarse siempre en una ventana de baja actividad (~04:25 UTC-3), el costo de esta consulta pasa inadvertido normalmente. El reinicio de la VM el 15/07 corrió el disparo de la tarea a las 17:53 UTC-3, exponiendo por primera vez ese costo crónico durante horario de actividad y carga concurrente (incluida la de la campaña). La corrida del 15/07 procesó un backlog de ~37 horas (en vez de las 24 h habituales, por el día salteado) a un rendimiento de 148.668 filas en 12.864 s (~11,6 filas/seg) — **dentro del rango normal de esta consulta**, no un pico de rendimiento anómalo.

**Rol de la campaña de Grido:** coincidencia temporal, no causa. Los límites reales de la ejecución (`LowerLimit = 2026-07-13 07:25:53`, `UpperLimit = 2026-07-14 20:53:40`, ambos GMT) confirman que el lote procesado no incluye los envíos de la campaña (15/07 14:00–16:00 UTC-3): esas filas quedarán en la corrida siguiente. La campaña pudo sumar carga concurrente al servidor durante la ventana, pero no fue el origen del volumen procesado por SPID 110.

**Origen confirmado en código:** la query configurada coincide de forma verbatim con la capturada en producción. Se encuentra en el repositorio `dev-src-sol-smartloyalty` (rama `main`), archivo `Other/SqlScript/Updates/v10.07.00/v10.07.00_UpdateETLConfigForSync.sql`, líneas 399–431 (bloque `-- Id = 6 -> dbo.CustomerPointsLog`). Config relevante: `BatchSize = 1000000`, `SetSize = 100000` (coincide con el `OFFSET 0 ROWS FETCH NEXT 100000 ROWS` observado), `MaxExecutionPeriod = NULL`.

---

## Hallazgos

### SPID 110 — TaskOperatorService (sincronización CustomerPointsLog)

| Métrica | Valor |
|---|---|
| Host | `SFCG-TO-01` |
| Login | `sfsqlusr` |
| Programa | `.Net SqlClient Data Provider` |
| Ventana de actividad dominante | 20:56–22:56 GMT (17:56–19:56 UTC-3) |
| Delta CPU por snapshot (sysprocesses) | 60.000–97.000 ms cada ~5 min, sostenido |
| Siguiente consumidor en la ventana | ~53.000 ms, evento aislado (consulta de catálogo de artículos) |
| CPU rate pico (TempDB) | ~150.000 ms / 10 seg |
| Lecturas lógicas (una ejecución) | 10.442 → 278.573 |
| Bloqueos | Ninguno (`blocked = 0` en todos los snapshots) |
| Wait types dominantes | `PAGEIOLATCH_SH`, `MEMORY_ALLOCATION_EXT` |

**Descripción de la consulta:** probe de conteo (`COUNT(*) OVER()`) sobre el join `Sml.CustomerPointsLog` ⋈ `Sml.Customer`, previo al fetch paginado (`OFFSET 0 ROWS FETCH NEXT 100000 ROWS`) de la sincronización incremental. El predicado `OR` que combina condiciones sobre `cpl.LogDate` y `c.CreatedDate` no es sargable, lo que fuerza un scan del join en lugar de un seek eficiente a medida que crece el volumen de filas a evaluar.

### Historial de ejecuciones — operación ETL `CustomerPointsLog` (últimos ~30 días)

Confirma que el rendimiento de esta operación es crónicamente bajo (no una degradación puntual) y que el 15/07 es la única corrida que no siguió el horario habitual (~07:25 GMT):

| Fecha (Started, GMT) | Duración | Ventana procesada | Filas | Filas/seg |
|---|---|---|---|---|
| 2026-06-23 14:00 | 90.813 s | 319 h (recuperación previa, no relacionada) | 1.752.227 | 19,3 |
| 2026-06-25 – 2026-07-14 (20 corridas diarias, ~07:25 GMT) | 5.552–19.495 s | 24 h c/u | 53.412–269.865 | 9,1–20,1 |
| **2026-07-15 20:53:40** | **12.864 s** | **37 h (backlog por trigger ausente)** | **148.668** | **11,6** |
| 2026-07-16 07:25:34 (retoma horario habitual) | 6.700 s | 11 h (resto del backlog) | 72.724 | 10,9 |

El 15/07 es la única fecha del período sin ejecución cerca de las 07:25 GMT — coincide con el reinicio de la VM reportado entre las 04:30 y 05:00 UTC-3 (07:30–08:00 GMT), minutos después del horario habitual de disparo. Detalle completo en `20260715_cpu_spikes_etl_history.csv`.

---

## Consultas ejecutadas

| # | Query | Propósito |
|---|---|---|
| Q1 | Disponibilidad de datos | Confirmar cobertura de snapshots en `PNSSRL_AuditSysprocesses` para la ventana del evento |
| Q2 | Delta de CPU por SPID | Rankear sesiones por consumo de CPU entre snapshots consecutivos e identificar el SPID dominante |
| Q3 | Captura TempDB — SPID 110 | Obtener texto completo de la consulta y métricas de recursos (`cpu_time`, `logical_reads`, memory grant) |
| Q4 | Propuesta de reescritura sargable | Reemplazo del predicado `OR` por dos ramas `UNION ALL` sargables — ver `20260715_cpu_spikes_query002_proposal.sql` |
| Q5 | Descubrimiento de esquema `Etl` | Localizar tablas/columnas del framework ETL en `SmartFran.Solution.SmartLoyalty` (`sys.tables`/`sys.columns`) — reveló `Etl.EtlOperationExecution` (límites reales por corrida) |
| Q6 | Límites reales de ejecución — SPID 110 | Obtener `LowerLimit`/`UpperLimit`/`TotalRows` reales de la corrida del evento vía `Etl.EtlOperationExecution` |
| Q7 | Historial de ejecuciones (30 días) | Confirmar patrón de horario habitual (~07:25 GMT) y rendimiento crónico (~10-20 filas/seg) de la operación `CustomerPointsLog` — ver `20260715_cpu_spikes_etl_history.csv` |

---

## Acciones propuestas

1. Reescribir el `FromQuery` de `Etl.EtlOperationConfig` Id = 6 (`dbo.CustomerPointsLog`) para eliminar el predicado `OR` no sargable sobre `cpl.LogDate` / `c.CreatedDate` — separar en dos ramas sargables (`UNION ALL`), ya mutuamente excluyentes, en lugar de un único `OR` entre columnas de distintas tablas. Propuesta concreta en `20260715_cpu_spikes_query002_proposal.sql`. Entregar como nuevo script versionado en `Other/SqlScript/Updates/` siguiendo el patrón existente (no modificar el script v10.07.00 ya aplicado). Validar antes en QA que el framework ETL tolera el cambio de `ORDER BY cpl.Id` a `ORDER BY CustomerPointsLogId` que exige el `UNION ALL`. Esto beneficia **todas** las corridas diarias, no solo escenarios de backlog — la operación rinde de forma crónicamente baja (~10-20 filas/seg) todas las noches.
2. Evaluar índices de soporte sobre `Sml.CustomerPointsLog(LogDate)` y `Sml.Customer(CreatedDate)` para la nueva condición sargable.
3. Confirmar con el equipo responsable del reinicio de la VM (04:30–05:00 UTC-3 del 15/07) si fue programado o no, y si hay otras operaciones ETL que hayan sido reprogramadas de forma similar ese día — para descartar impacto adicional no detectado en esta investigación.
4. Evaluar si el mecanismo de reprogramación de tareas ETL (`SmartFran.Business.Schedule.*`) puede diferir una corrida salteada a la siguiente ventana de baja actividad en lugar de dispararla inmediatamente al reiniciar, para evitar que un backlog crónico pero inofensivo se vuelva visible en horario de actividad.
5. Evaluar si conviene fijar `MaxExecutionPeriod` en la config Id = 6 para acotar el impacto de un lote de recuperación anómalamente grande.

---

## Evidencia

| Archivo | Contenido |
|---|---|
| `20260715_cpu_spikes_query001.sql` | Texto completo de la consulta responsable, capturado desde `PNSSRL_TempdbProc.Query_Text` (SPID 110) |
| `20260715_cpu_spikes_query002_proposal.sql` | Propuesta de reescritura sargable (`UNION ALL`) del `FromQuery` de la config Id = 6, con notas de riesgo y validación |
| `20260715_cpu_spikes_email_pm.md` | Email enviado a PMs con resumen del evento y detalle técnico de la consulta |
| `20260715_cpu_spikes_etl_history.csv` | Historial de 23 ejecuciones de la operación ETL `CustomerPointsLog` (últimos ~30 días) — confirma patrón crónico y horario habitual |
| `20260715_cpu_spikes_ops-events.md` | Registro cronológico de la investigación |

- Fuente primaria: `PNSSRL.dbo.PNSSRL_AuditSysprocesses` — 72 snapshots, ventana 2026-07-15 17:00–23:00 GMT
- Fuente secundaria: `PNSSRL.dbo.PNSSRL_TempdbProc` — 18 capturas para SPID 110 (20:53–20:56 GMT)
- Fuente terciaria: `SmartFran.Solution.SmartLoyalty.Etl.EtlOperationExecution` — límites reales e historial de ejecuciones de la operación `CustomerPointsLog`
- Ventana GMT: 2026-07-15 17:00–23:00

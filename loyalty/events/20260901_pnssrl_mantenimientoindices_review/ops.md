# GITIN-1981 — Revisión de PNSSRL_MantenimientoIndices

**Tags:** SmartLoyalty, PNSSRL, Mantenimiento, PROD, SRE

## Resumen

Durante el análisis de salud de queries del fin de semana 2026-08-28/29/30 (GITIN-1866, ticket padre de este), se identificó que el job de SQL Agent `PNSSRL_MantenimientoIndices` es la causa raíz de una cadena de bloqueo real contra `Sml.CustomerPointsLog` (y, en un evento aislado, `SmlSupp.PromotionBranchOffice`), ambas en `SmartFran.Solution.SmartLoyalty`. El job ejecuta un `ALTER INDEX REBUILD` offline diario a las 06:15 UTC (03:15 UTC-3) que retiene un lock de modificación de esquema durante toda su duración, bloqueando tanto a MobileAppService (`SFCG-MOBI-01`) como al chequeo de fragmentación de Zabbix. Este ticket nace exclusivamente de ese hallazgo — no fue originado por una alerta ni un reporte de usuario. La duración del job es altamente variable (1h52m55s a 6h14m11s en las dos corridas más recientes verificadas), causa aún no determinada. Existe un precedente documentado ([GITIN-1669](https://smartit-ar.atlassian.net/browse/GITIN-1669), 2026-07-23) con el mismo job/tabla como víctima, aunque con un disparador distinto (transacción abandonada bajo login `zabbix`), cuyas acciones propuestas no fueron confirmadas como implementadas.

**Objetivo de este ticket**: encontrar un horario de ejecución para `PNSSRL_MantenimientoIndices` que evite o minimice el bloqueo confirmado. El horario actual (06:15 UTC) ya es de baja actividad por diseño, pero igual genera bloqueo medible — se necesita un análisis de tráfico real (no asumido) sobre los hosts afectados para identificar la ventana de menor actividad antes de proponer un horario concreto. Ese análisis está pendiente (ver Acciones propuestas).

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-1981 (padre: GITIN-1866) |
| Sistema | SmartLoyalty SQL Server (`PNSSRL` / `SmartFran.Solution.SmartLoyalty`) — `SFCG-DB01` |
| Severidad | Media — bloqueo diario confirmado con impacto medible (hasta 38 sesiones bloqueadas simultáneamente), sin caída de servicio reportada; ticket proactivo, no originado por incidente |
| Detectado | N/A — hallazgo proactivo derivado de GITIN-1866 (ventana analizada: 2026-08-28/29/30) |
| Resuelto | Pendiente — investigación en curso, sin acción correctiva aplicada |
| Responsable | Dante Paniagua |

## Causa raíz

El job `PNSSRL_MantenimientoIndices` (SQL Agent, `enabled=1`, schedule diario `06:15:00 UTC`, sin hora de fin definida) ejecuta `EXEC PNSSRL_MantenimientoModulos`, que genera dinámicamente sentencias `ALTER INDEX ... REBUILD` por tabla. Al ser un rebuild offline, retiene `Sch-M` (modificación de esquema) durante toda su duración — confirmado tanto por el hallazgo de esta ventana como por el precedente de 2026-07-23. Mientras el rebuild está en curso sobre `Sml.CustomerPointsLog`, cualquier sesión que requiera `Sch-S` (estabilidad de esquema) sobre la misma tabla queda en cola — incluyendo las consultas de `SFCG-MOBI-01` (MobileAppService) y el propio chequeo de fragmentación de Zabbix. El job es diario, no específico del fin de semana analizado — las dos ocurrencias previas de esta investigación (2026-08-16 y 2026-08-19) simplemente no coincidieron en horario con la ventana de ejecución del job.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Identidad y programación del job confirmadas: `PNSSRL_MantenimientoIndices`, diario, `06:15:00 UTC`, coincide con `queries/PNSSRL_MantenimientoIndices.sql` ya versionado en este repo | Informativo |
| H2 | Bloqueador raíz confirmado en las 26 instantáneas de bloqueo de las tres fechas analizadas (2026-08-28/29/30): siempre el mismo job, ejecutando `ALTER INDEX REBUILD` sobre `Sml.CustomerPointsLog` (25 instantáneas) o `SmlSupp.PromotionBranchOffice` (1 instancia, 2026-08-28 07:56 UTC) | Alto |
| H3 | Bloqueo pico: 38 sesiones bloqueadas simultáneamente, 16 cadenas de bloqueo distintas (2026-08-28 07:21:00 UTC) | Alto |
| H4 | Duración del job altamente variable entre corridas: 1h52m55s (2026-09-01) vs. 6h14m11s (2026-08-31) — causa no determinada | Medio |
| H5 | El procedimiento `PNSSRL_MantenimientoModulos`, que genera los `ALTER INDEX REBUILD`, está creado `WITH ENCRYPTION` — su definición no es legible directamente (`OBJECT_DEFINITION`/`sp_helptext` confirmaron esto), limitando la investigación de la lógica de fillfactor y orden de iteración de tablas | Bajo |
| H6 | Precedente confirmado: el mismo job/tabla ya causó bloqueo el 2026-07-23 ([GITIN-1669](https://smartit-ar.atlassian.net/browse/GITIN-1669)), aunque con un disparador distinto (transacción sin confirmar bajo login `zabbix`, no el job en sí). Las acciones propuestas en ese ticket (coordinar horario de load tests con la ventana de mantenimiento; alertar sobre transacciones idle bajo `zabbix`) no están confirmadas como implementadas | Medio |
| H7 | Se investigó una consulta del usuario sobre por qué Zabbix mostraba un valor "bajo" de duración para este job — se confirmó que la query del ítem `mssql.job.run_duration` (`msdb..sysjobservers.last_run_duration`, con conversión HHMMSS→segundos correcta) no tiene errores. El valor percibido como bajo corresponde a variabilidad real de duración (H4) o a que el ítem refleja la última corrida completa, no el progreso en vivo de una corrida en curso — no es un gap de monitoreo | Informativo |
| H8 | Distribución real de duración confirmada sobre 25 corridas (2026-08-15 a 2026-09-08): la mayoría agrupa entre 1h30m y 2h10m, pero el 24% (6/25 días) supera las 3 horas, hasta 6h14m11s — variabilidad recurrente, no un único outlier | Medio |
| H9 | Perfil horario real de `SFCG-MOBI-01` (30 días continuos, confirmado sin huecos): la hora **07:00-08:00 UTC tiene un pico aislado** de 10.274 filas de captura (~2x cualquier otra hora) y 132 SPIDs distintos — tráfico real de la aplicación (`.Net SqlClient Data Provider` de `SFCG-MOBI-01`, no un job de SQL Agent reordenable). El horario actual (06:15 UTC) ya bordea este pico, y toda corrida que exceda ~45 minutos lo alcanza | Alto |
| H10 | `Operaciones_MaintenancePlan_Backups.Backup_FULL` corre semanalmente a las 06:00 UTC domingo/lunes/miércoles — el horario actual (06:15 UTC) ya arranca dentro de un backup FULL activo esos 3 días. Desglosando las 25 corridas de Q20 por día de semana: lunes es un outlier claro (3/4 corridas superan 3h), domingo moderadamente elevado (2/4), pero **miércoles — mismo horario de backup — no muestra ninguna corrida larga**, lo que debilita (sin descartar) la hipótesis de contención de I/O contra el backup como causa única de H4 | Medio (correlación parcial, no confirmada) |
| H11 | Restricción adicional confirmada por el usuario (2026-09-10): los terminales POS operan de 10:00 a 02:00 UTC-3 del día siguiente (13:00–05:00 UTC) — ventana no considerada en la recomendación original de horario (23:30 UTC), que caía dentro de este rango activo. Invalida esa recomendación; horario revisado a 08:00 UTC — ver Acciones propuestas 1 | Alto (invalidaba la recomendación previa) |
| H12 | Inventario completo de jobs de SQL Agent (Q29) reveló `Actualiza_DWGrido_CustomerPointsBalance` (diario, 08:30 UTC), no conocido hasta ahora, cayendo dentro de la ventana candidata de 08:00 UTC. **Descartado como conflicto tras revisar su definición real (Q30):** lee de `SmlSt.CustomerPointsLog` (schema distinto de `Sml.CustomerPointsLog`, el que reconstruye este job) y escribe en una base separada vía linked server — sin objeto compartido. Duración real observada (30 días): 3m24s–15m14s, mayormente 4-7 min | Informativo (descartado tras verificación) |
| H13 | Auditoría completa de los ~54 tasks de `\SmartFran\` en `SFCG-TO-01` contra el contenido real de sus queries encontró **13 tasks que sí tocan `Sml.CustomerPointsLog`** — la tabla de producción que reconstruye este job, no la de staging. La más notable: `Program Results`, diaria a las 11:00 UTC, dentro de la ventana candidata todos los días | Medio |
| H14 | **De-escala H13.** Duración real por ejecución (Windows Task Scheduler event log, `SFCG-TO-01`) de los 13 tasks: todas breves, entre <1 y ~76 segundos. `SendCanjesSocioCortesiaToBlobStorage`/`SendDetalleCanjesSocioCortesiaToBlobStorage` además están inactivos entre ~03:00 y ~11:00 UTC (no corren 24/7 como se asumía). Un solapamiento con el lock `Sch-M` del rebuild solo demora estos tasks breves hasta que el lock se libera — no genera contención sostenida ni bloquea al rebuild. Riesgo mucho menor que el problema original del ticket (tráfico en vivo de MobileAppService bloqueado). **08:00 UTC vuelve a ser una recomendación razonable** — no por estar libre de solapamientos, sino porque el costo real de esos solapamientos es bajo | Bajo (de-escalado tras verificación) |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| `SFCG-DB01` | Host donde ejecuta el job `PNSSRL_MantenimientoIndices` |
| `Sml.CustomerPointsLog` (`SmartFran.Solution.SmartLoyalty`) | Tabla bloqueada durante el rebuild diario de `IX_CustomerId` |
| `SmlSupp.PromotionBranchOffice` (`SmartFran.Solution.SmartLoyalty`) | Tabla bloqueada en un evento aislado (rebuild de `IX_PromotionBranchOffice_1`) |
| `SFCG-MOBI-01` (MobileAppService) | Consultas EF bloqueadas (`SELECT ... FROM [Sml].[CustomerPointsLog] WHERE CustomerId = @EntityKeyValue1`) |
| `sfzabbix` | Chequeo de fragmentación de índices bloqueado por el mismo job que corrige la fragmentación |

## Comandos ejecutados

| # | Query | Propósito |
|---|---|---|
| Q13 | Identificación de bloqueador raíz | Confirmar qué SPID/proceso encabeza cada cadena de bloqueo en la ventana 2026-08-28/29/30 |
| Q14 | Severidad de bloqueo por instantánea | Cuantificar sesiones bloqueadas y cadenas de bloqueo por instantánea |
| Q15 | Nombre/pasos del job | Identificar el job detrás del GUID encontrado en Q13 |
| Q16 | Definición de programación | Confirmar si es un job diario estándar o específico del fin de semana |
| Q17 | Historial de corridas (últimas 10) | Obtener distribución real de duración del job |
| Q18 | Definición de `PNSSRL_MantenimientoModulos` | Intentar leer la lógica del procedimiento generador de los rebuilds — resultó encriptado |
| Q19 | Reproducción de selección de fila `sysjobhistory` (naive vs. `step_id=0`) | Usada para descartar una hipótesis inicial sobre el ítem de Zabbix, luego corregida al obtener la query real del ítem maestro |
| Q20 | Historial de corridas extendido (25 días) | Distribución real de duración del job — confirma H8 |
| Q21 | Perfil horario de actividad de `SFCG-MOBI-01` (30 días) | Identificar la ventana de menor tráfico real — confirma H9 (pico hora 7 UTC) |
| Q22 | Jobs programados 06:30-08:00 UTC + desglose por host/programa de la hora 7 | Determinar si el pico de la hora 7 es un job reordenable o tráfico real de aplicación — confirma H9 |
| Q23 | Horario de `Operaciones_MaintenancePlan_Backups.Backup_FULL`/`Backup_Log` | Verificar colisión con la ventana recomendada — confirma H10 |
| Q24 | Día de semana de las 25 corridas de Q20 | Cruzar duración vs. día de semana contra el horario de Backup_FULL — confirma H10 |

Detalle completo, incluyendo la query real del ítem Zabbix `MSSQL: Get job status` (provista por el usuario, no ejecutada en esta sesión), en `scripts.sql`.

## Acciones propuestas

1. **(SRE) Recomendación — objetivo principal del ticket: 08:00 UTC (05:00 UTC-3).** Historial de revisiones: 23:30 UTC (invalidada por H11, horario POS) → 08:00 UTC (H12) → en duda por H13 (13 tasks de `SFCG-TO-01` tocan `Sml.CustomerPointsLog`, incluyendo `Program Results` diaria dentro de la ventana) → **confirmada de nuevo tras H14**: la duración real de los 13 tasks es breve (<1-76 seg cada uno), así que un solapamiento solo demora esos tasks hasta que el rebuild libera el lock, no genera contención sostenida ni bloqueo real — riesgo bajo comparado con el problema original (tráfico en vivo de MobileAppService bloqueado). Detalle completo en `investigation.md` y `data/task_duration_history_20260910.txt`. Única verificación pendiente antes de cerrar del todo: confirmar el propósito de negocio de `Program Results` (el único touch diario dentro de la ventana) para descartar sensibilidad a horario de entrega.

**Inventario completo de jobs relevado (Q29/Q30, ver H12):** se listaron los 12 jobs habilitados de SQL Agent contra la ventana 08:00-13:00 UTC. Se encontró `Actualiza_DWGrido_CustomerPointsBalance` (08:30 UTC diario) y se descartó como conflicto — tabla distinta (`SmlSt.CustomerPointsLog`, no `Sml.CustomerPointsLog`), duración real 3-15 min. Ningún otro job del inventario cae en la ventana candidata.

**Salvedades explícitas, todavía no verificadas:** la duración propia de `Backup_FULL` no está confirmada (08:00 UTC asume que termina 2h después de su inicio a las 06:00 UTC, sin confirmar). El cluster de tareas de `SFCG-TO-01` (~12:00 UTC) cae dentro de la cola del peor caso (termina 14:14 UTC) — mismo riesgo de interacción ya conocido de GITIN-1753, no re-resuelto acá. Tampoco se relevó el perfil de `SFCG-CLUB-01` (también afectado por H2). No resuelve la causa de la variabilidad de duración (H4/H10).

**Cronograma horario (00-23 UTC), resumen:**

| Hora UTC | POS activo | Touches breves sobre SmlCPL | Otros tasks (#) |
|---|---|---|---|
| 00 | Sí | — | 0 |
| 01 | Sí | — | 1 |
| 02 | Sí | — | 0 |
| 03 | Sí | — | 1 |
| 04 | Sí | AssignPointFirstSaleApp (<1s) | 0 |
| 05 | No (desde 05:00) | — | 0 |
| 06 | No | — | 2 |
| 07 | No | Alerts Update (44-76s), PointsLogGenerator (lectura) — pico MobileAppService 07:00-08:00 | 2 |
| **08** | **No** | **ExchangeReportsMonth (mensual)** | **6** |
| 09 | No | — | 3 |
| 10 | No | PointsFranchisePY (semanal) | 7 |
| 11 | No | Program Results (30-33s), ReportManualPointsAssignmentIndividual/Lists (semanal), SendCanjes/DetalleSocioCortesia (inicio ciclo 30min) | 9 |
| 12 | No | ReportUpdateCustomer (mensual), SendCanjes/Detalle (continúa) | 5 |
| 13 | Sí (desde 13:00) | SendCanjes/Detalle (continúa) | 1 |
| 14 | Sí | SendCanjes/Detalle (continúa) | 1 |
| 15-22 | Sí | SendCanjes/Detalle (continúa hasta 03:00) | 0 |
| 23 | Sí | SendCanjes/Detalle (continúa) | 1 |

No incluido en la tabla: jobs semanales fuera de este inventario (`Backup_FULL` dom/lun/mié 06:00, `Depura Tempdb` dom 03:00, `CapturaUsoIndices` jue/vie 23:00). El rebuild actual (06:15 UTC) arranca dentro de la hora 6; el propuesto (08:00 UTC, fila resaltada) arranca en una hora con solo touches breves y ningún job semanal conocido. Versión completa con las barras de duración del rebuild (actual vs. propuesto) en `db_schedule_chronogram.txt` (raíz de esta carpeta de evento), y el detalle task-por-task en `loyalty/docs/task_operator_tasks.md` §4.

**Comandos (`scripts.sql`, Q25-Q28), tres opciones:**
- **Opción 1 (recomendada, Q26):** `sp_update_schedule` — modifica el schedule existente in place, mismo `schedule_id`.
- **Opción 2 (Q27):** `sp_detach_schedule` + `sp_add_schedule` + `sp_attach_schedule` — desvincula el schedule actual y crea uno nuevo, útil solo si se quiere preservar el objeto de las 06:15 UTC como referencia de rollback en vez de sobrescribirlo.
- **Opción 3:** GUI de SSMS (Job Properties → Schedules → Edit) — manual, no scripteable.

Q25 (solo lectura) confirma el `schedule_id` exacto (23). Q26/Q27 actualizados con el nuevo horario propuesto (08:00 UTC); Q28 verifica que el cambio surtió efecto una vez aplicado. **Pendiente de nueva aprobación** dado el cambio de horario recomendado — la aprobación previa (2026-09-10) fue sobre 23:30 UTC, ahora superado.
2. **(SRE) Pendiente** — Investigar la causa de la variabilidad de duración del job (H4): candidatos no descartados son el nivel de fragmentación al momento de la ejecución, contención/bloqueo sobre el propio job (como ocurrió en el precedente del 2026-07-23), o crecimiento de las tablas involucradas. Relevante para el objetivo principal — una corrida de 6h14m puede extenderse más allá de cualquier ventana de bajo tráfico que se identifique.
3. **(SRE) Pendiente** — Evaluar, una vez identificada la ventana óptima, si conviene reordenar la secuencia de mantenimiento para que `CustomerPointsLog` se procese primero (o en un horario específico), o aplicar un umbral de fragmentación para omitir rebuilds innecesarios.
4. **(SRE) Pendiente** — Confirmar si las acciones propuestas en el ticket precedente ([GITIN-1669](https://smartit-ar.atlassian.net/browse/GITIN-1669)) fueron implementadas: alerta sobre transacciones idle bajo login `zabbix`, coordinación del horario de load tests de MobileAppService con la ventana de mantenimiento de índices.
5. **(SRE) Completado** — Verificación del ítem Zabbix `mssql.job.run_duration` (H7): confirmado que la query y el cálculo son correctos; no requiere corrección.
6. **(SRE) Pendiente, fuera de alcance inmediato** — Evaluar si este job es candidato a reducir su nivel de bloqueo (p. ej. `WAIT_AT_LOW_PRIORITY`, si aplicable en SQL Server 2022 Standard) dado que `ONLINE=ON` no es una opción evaluable sin más información sobre restricciones de edición/objeto.

## Hallazgos secundarios

Durante el análisis de CPU de la misma ventana (GITIN-1866), `SFCG-TO-01` mostró un consumo de CPU muy por encima de lo esperado (44,6M ms). No se confirmó relación con el bloqueo documentado aquí — queda como pregunta abierta en GITIN-1866, no forma parte del alcance confirmado de este ticket.

Ninguna de las tres plataformas (SmartPedidos, SmartLoyalty, SmartCloud) tiene una ventana de mantenimiento/housekeeping oficial documentada — por eso la recomendación de horario de este ticket tuvo que derivarse desde cero (horario POS + `Backup_FULL` + perfil de tráfico de un solo servicio) en vez de validarse contra un estándar ya definido. Gap estructural cross-plataforma, fuera del alcance de este ticket — no accionado acá.

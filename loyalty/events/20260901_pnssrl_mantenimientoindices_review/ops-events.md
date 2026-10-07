# Eventos — 20260901_pnssrl_mantenimientoindices_review

## 2026-09-01 — Apertura del ticket, desprendido de GITIN-1866

He abierto este evento como desprendimiento de GITIN-1866, tras confirmar en esa investigación que el job `PNSSRL_MantenimientoIndices` es la causa raíz de una cadena de bloqueo real sobre `Sml.CustomerPointsLog`. He recibido el ticket Jira GITIN-1981 (padre GITIN-1866) y he creado `investigation.md` como primer artefacto, trasladando los hallazgos ya confirmados en GITIN-1866 (identidad del job, programación diaria a las 06:15 UTC, severidad del bloqueo).

## 2026-09-01 — Lectura de `queries/PNSSRL_MantenimientoIndices.sql`

He leído el script de referencia ya versionado en el repositorio. He confirmado que coincide con la definición del paso de job obtenida previamente vía `msdb.dbo.sysjobsteps` (Q15) — es el wrapper del job, no la lógica de reconstrucción de índices en sí, que vive en `PNSSRL_MantenimientoModulos`.

## 2026-09-01 — Lectura del precedente `20260723_bloqueo_customerpointslog_loadtest`

He encontrado referencia a `PNSSRL_MantenimientoModulos` en un evento previo (2026-07-23) sobre bloqueo de la misma tabla durante un load test de MobileAppService. He leído `ops.md`, `scripts.sql` y `ops-events.md` de ese evento (carpeta con formato de nombre largo, anterior a la convención `investigation.md`-primero). He confirmado dos hechos relevantes: (1) el rebuild es offline y retiene `Sch-M` durante toda su duración — resuelve la duda sobre `ONLINE`/`OFFLINE`; (2) el disparador de ese incidente fue una transacción sin confirmar bajo el login `zabbix` bloqueando al job, un mecanismo distinto al de esta investigación (donde el job mismo es el bloqueador raíz, no algo que lo bloquea a él). He incorporado ambos hallazgos a `investigation.md`, junto con las acciones propuestas en ese ticket que no están confirmadas como implementadas.

## 2026-09-01 — Intento de lectura de `PNSSRL_MantenimientoModulos` — callejón sin salida

He ejecutado `OBJECT_DEFINITION` y `sp_helptext` sobre `dbo.PNSSRL_MantenimientoModulos` (Q18). He confirmado que el procedimiento está creado `WITH ENCRYPTION` — su definición no es legible por medios estándar. He registrado esto como callejón sin salida en `investigation.md`, con `PNSSRL_AuditSysprocesses.comando_ejecutado` como única vía indirecta restante para inferir su lógica.

## 2026-09-01 — Investigación del ítem Zabbix `mssql.job.run_duration`

He investigado por qué Zabbix mostraba un valor bajo de duración para este job. He reconstruido la cadena de ítems (discovery → ítem maestro "MSSQL: Get job status" → ítems dependientes por job vía JSONPath) y, con una hipótesis inicial basada en reproducir el síntoma contra `sysjobhistory` (Q19), he sospechado un bug de selección de fila (`step_id` faltante). Al obtener la query real del ítem maestro (obtenida directamente desde la configuración de Zabbix, no ejecutada en esta sesión), he corregido esa hipótesis: la query usa `msdb.dbo.sysjobservers.last_run_duration` (campo de resumen a nivel de job, no una fila cruda de `sysjobhistory`) con una conversión HHMMSS→segundos matemáticamente correcta — no hay bug. He actualizado `investigation.md` reemplazando la hipótesis incorrecta por la explicación real: el ítem solo refleja la última corrida completa, no el progreso en vivo de una corrida en curso, y la variabilidad real de duración (ya documentada) explica el valor "bajo" percibido.

## 2026-09-01 — Redacción de `ops.md`

He escrito `ops.md` siguiendo el formato ya establecido por GITIN-1866 (Resumen, Tabla resumen, Causa raíz, Hallazgos, Recursos afectados, Comandos ejecutados, Acciones propuestas, Hallazgos secundarios), consolidando los hallazgos confirmados de esta investigación. He referenciado las queries en `scripts.sql`, que he creado para este evento reproduciendo Q13/Q14 (originalmente ejecutadas bajo GITIN-1866 antes del desprendimiento) junto con Q15-Q19.

## 2026-09-01 — Redefinición del objetivo del ticket

He incorporado la precisión de que el objetivo de GITIN-1981 es encontrar un horario de ejecución para el job que evite o minimice el bloqueo confirmado, no solo documentar la causa raíz. He actualizado `investigation.md` y `ops.md` (Resumen y Acciones propuestas) para reflejar esto como el objetivo principal — pendiente un relevamiento real de tráfico por hora en los hosts afectados antes de poder proponer un horario concreto.

## 2026-09-09 — Relevamiento de tráfico real completado, recomendación de horario entregada

He ejecutado Q20 (historial de corridas extendido a 25 días) y confirmado que la variabilidad de duración es recurrente, no un único outlier: el 24% de las corridas supera las 3 horas. He ejecutado Q21 (perfil horario de `SFCG-MOBI-01` sobre 30 días continuos, confirmado sin huecos vía `earliest_sample`/`latest_sample`) y encontrado un pico aislado en la hora 07:00-08:00 UTC — casi el doble de cualquier otra hora. He ejecutado Q22 para determinar la causa de ese pico: he descartado que fuera otro job de SQL Agent (el único candidato en esa ventana corre solo los lunes) y he confirmado, por desglose de host/programa, que es tráfico real de aplicación de `SFCG-MOBI-01` — no reordenable.

Con estos tres relevamientos, he armado una tabla comparativa de 4 horarios candidatos contra 3 escenarios de duración (mediana, P80, peor caso observado) y he entregado una recomendación concreta: mover el job a 00:30 UTC (21:30 UTC-3, día anterior) — el único horario donde ni siquiera la corrida más larga observada alcanza el pico de tráfico de la hora 7. He documentado la comparación completa en `investigation.md` y actualizado `ops.md` (H8, H9, acción propuesta 1) con la recomendación y sus salvedades (perfil de `SFCG-CLUB-01` no relevado; causa de la variabilidad de duración sigue sin resolver). Queda pendiente la decisión final del usuario antes de aplicar el cambio de horario sobre el job en producción.

## 2026-09-09 — Horario de `Backup_FULL` verificado, correlación parcial con H4 (no confirmada)

He ejecutado Q23 y confirmado el horario real de `Operaciones_MaintenancePlan_Backups.Backup_FULL` (semanal, domingo/lunes/miércoles, 06:00 UTC) y `Backup_Log` (diario, cada 10 minutos). He identificado que el horario actual del job (06:15 UTC) ya arranca dentro de un backup FULL activo esos 3 días — candidato a explicar parte de H4.

He ejecutado Q24 para cruzar día de semana contra duración sobre las 25 corridas de Q20. He encontrado una correlación parcial, no una confirmación limpia: lunes es un outlier claro (3 de 4 corridas superan 3h), domingo moderadamente elevado (2 de 4), pero miércoles — mismo horario de backup que domingo/lunes — no muestra ninguna corrida larga. He documentado esto en `investigation.md` y `ops.md` (H10) como correlación parcial, sin descartar ni confirmar contención de I/O como causa de H4 — he dejado abierta la posibilidad de que sea un patrón específico de lunes/domingo (fragmentación acumulada de fin de semana, o tráfico de campañas ya confirmado en GITIN-1866) en vez de una colisión genérica con cualquier día de backup. He agregado la salvedad correspondiente a la recomendación de horario: en el peor caso observado, el horario recomendado (00:30 UTC) todavía rozaría ~44 minutos de `Backup_FULL` los domingos/lunes/miércoles — un conflicto real pero más acotado que el actual.

## 2026-09-09 — Recomendación de horario ajustada a 23:30 UTC, despeja ambos conflictos

He recalculado el horario recomendado para despejar tanto el pico de MobileAppService (07:00 UTC) como `Backup_FULL` (06:00 UTC) en el peor caso observado, no solo el primero. Con inicio a las **23:30 UTC (20:30 UTC-3, mismo día calendario)**, una corrida de 6h14m11s terminaría a las 05:44 UTC — 16 minutos antes de `Backup_FULL` y 76 minutos antes del pico de MobileAppService, con exposición de tráfico prácticamente igual a la recomendación anterior. He actualizado `investigation.md` (marcando la recomendación de 00:30 UTC como superada, no eliminada) y `ops.md` (acción propuesta 1) con este ajuste.

## 2026-09-09 — Referencia local al precedente reemplazada por el ticket Jira confirmado (GITIN-1669)

He confirmado, contra el contenido real del ticket, que el precedente citado (`20260723_bloqueo_customerpointslog_loadtest`) corresponde a `GITIN-1669`. He reemplazado las 3 referencias a la ruta local en `ops.md` (Resumen, H6, acción propuesta 4) por el link de Jira, siguiendo la regla de "Jira, no rutas locales" para contenido externo. Dejé la referencia local intacta en `investigation.md` (permitido para notas de trabajo internas), agregando el número de ticket confirmado a modo de enriquecimiento.

## 2026-09-09 — Comandos de cambio de horario preparados (Q25-Q28), tres opciones

He agregado a `scripts.sql` los comandos para aplicar la recomendación de horario (23:30 UTC): Q25 (solo lectura, confirma el `schedule_id` exacto), Q26 (Opción 1 recomendada — `sp_update_schedule` in place), Q27 (Opción 2 — desvincular y crear un schedule nuevo, para preservar el original como referencia), Q28 (verificación post-cambio). He actualizado la acción propuesta 1 en `ops.md` con las tres opciones y sus tradeoffs. Ninguno de estos comandos fue ejecutado — quedan pendientes de que el usuario confirme la opción y la hora exacta antes de correrlos contra producción.

## 2026-09-10 — Q25 ejecutado, propuesta de horario aprobada

Q25 confirmó `schedule_id 23`, `active_start_time` todavía en 061500 (06:15:00 UTC) — sin cambios desde la última verificación. He completado Q26/Q27 con ese `schedule_id`. La propuesta de mover el horario a 23:30 UTC quedó aprobada. He actualizado `ops.md` reflejando la aprobación — queda pendiente solo ejecutar el comando (Opción 1, `sp_update_schedule`) y correr Q28 para verificar que el cambio surtió efecto.

## 2026-09-10 — Recomendación de horario revisada a 08:00 UTC: la ventana POS invalidó 23:30 UTC

El usuario confirmó una restricción no considerada hasta ahora: los terminales POS operan de 10:00 a 02:00 UTC-3 del día siguiente (13:00–05:00 UTC). Esto invalida directamente la recomendación aprobada de 23:30 UTC (20:30 UTC-3), que caía dentro de esa ventana activa. He rehecho el análisis con esta restricción sumada a `Backup_FULL` y al pico de tráfico de `SFCG-MOBI-01` ya conocidos: la única ventana libre de los tres factores es 08:00–13:00 UTC. He revisado la recomendación a **08:00 UTC (05:00 UTC-3)** — limpia para el caso mediano y P80, con la cola del peor caso (6h14m11s) extendiéndose ~1h14m después de que el POS reanuda actividad. He dejado explícitas las salvedades no verificadas: duración propia de `Backup_FULL` sin confirmar, horarios de ETL/housekeeping genéricos no relevados de forma independiente. He actualizado H11 (nuevo hallazgo), la acción propuesta 1, y `investigation.md` con el detalle completo. He actualizado los comandos en `scripts.sql` (Q26/Q27) al nuevo horario (080000) y renombrado el schedule de la Opción 2 en consecuencia. La aprobación previa quedó superada — pendiente de nueva aprobación sobre este horario revisado.

## 2026-09-10 — Gap estructural flagueado: sin ventana de housekeeping oficial en ninguna de las 3 plataformas

He registrado que ninguna de las tres plataformas (SmartPedidos, SmartLoyalty, SmartCloud) tiene una ventana de mantenimiento/housekeeping oficial documentada — explica por qué la recomendación de horario de este ticket tuvo que derivarse desde cero en vez de validarse contra un estándar ya definido. He agregado este hallazgo a `investigation.md` y a "Hallazgos secundarios" en `ops.md` (fuera del alcance de este ticket, no accionado acá), y he agregado una nota puntero en `loyalty/docs/infrastructure.md` para que quede visible más allá de este ticket específico.

## 2026-09-10 — Inventario completo de jobs (Q29) y verificación de nuevo hallazgo (Q30)

He ejecutado Q29 (inventario completo de jobs habilitados de SQL Agent) y he guardado la salida cruda en `data/all_enabled_jobs_schedules_20260910.txt`. He encontrado un job no conocido hasta ahora, `Actualiza_DWGrido_CustomerPointsBalance`, diario a las 08:30 UTC — cae dentro de la ventana candidata de 08:00 UTC. Lo he marcado inicialmente como conflicto crítico.

He ejecutado Q30 para verificarlo directamente en vez de asumir: la definición real del procedimiento muestra que lee de `SmlSt.CustomerPointsLog` (schema distinto de `Sml.CustomerPointsLog`, el que reconstruye `PNSSRL_MantenimientoIndices`) y escribe en una base separada vía linked server — sin objeto compartido. El historial real de 30 corridas muestra duración de 3m24s a 15m14s, mayormente 4-7 minutos. He descartado el conflicto y corregido la marca de "CRÍTICO" que había puesto sobre este hallazgo antes de verificarlo. He actualizado H12 en `ops.md`, la acción propuesta 1, y `investigation.md` reflejando que la recomendación de 08:00 UTC queda confirmada, ahora también validada contra el inventario completo de jobs.

También he confirmado, del mismo inventario, que `PNSSRL_CapturaUsoIndices` corre semanalmente jueves/viernes a las 23:00 UTC — refuerza retroactivamente por qué la recomendación superada de 23:30 UTC era mala, más allá del horario POS.

## 2026-09-10 — Auditoría completa de tasks de SFCG-TO-01: la recomendación de 08:00 UTC queda revertida

He recibido el inventario completo (~54 tasks) de la carpeta `\SmartFran\` en `SFCG-TO-01`, con horarios reales. He persistido los datos crudos en `data/sfcg_to01_smartfran_tasks_20260910.txt` y `..._nexttimes_20260910.txt`.

He verificado, contra el contenido real de cada script/query (no solo por nombre), cuáles tocan `Sml.CustomerPointsLog`. He cometido dos errores de método durante esta verificación, ambos corregidos antes de reportar: primero he revisado la carpeta de queries equivocada (`Core/Domain.Query/Domain/Query/` en vez de `Front/SmlBackScript/Query/`, que es la que realmente cargan estos scripts), dándome resultados "limpios" falsos para varios tasks; después he usado una expresión regular que no capturaba la notación con corchetes (`[Sml].[CustomerPointsLog]`), perdiendo más coincidencias. He corregido ambos errores y he rehecho la verificación completa.

Resultado final, persistido en `data/smlbackscript_customerpointslog_audit_20260910.txt`: 13 tasks tocan `Sml.CustomerPointsLog` directamente. El hallazgo más grave es `Program Results`, que corre **diariamente** a las 11:00 UTC, dentro de la ventana candidata de 08:00 UTC todos los días. Aún más grave: `SendCanjesSocioCortesiaToBlobStorage` y `SendDetalleCanjesSocioCortesiaToBlobStorage` corren continuamente cada 30 minutos de 11:00 a 03:00 UTC, ambos tocando la tabla en cada ejecución.

He actualizado `investigation.md` con el detalle completo y `ops.md` (H13, acción propuesta 1) revirtiendo la confirmación previa: la única franja libre de todas las restricciones conocidas (POS, `Backup_FULL`, pico de MobileAppService, y ahora estos 13 tasks) queda en ~05:00-07:00 UTC — más corta que la duración típica del job. No hay, por ahora, una recomendación de horario con confianza suficiente para proponer.

## 2026-09-10 — Búsqueda de duración real: Sch.TaskEvent descartado, redirigido al log de Task Scheduler

Para avanzar sobre la duración real de los 13 tasks (primera de las dos opciones planteadas), he probado primero `Sch.Task`/`Sch.TaskEvent` dentro de `SmartFran.Solution.SmartLoyalty` (encontrado en `GITIN-1828`). He confirmado que es un motor interno completamente distinto — acciones de campañas de marketing (`MktAsignationPointActionManager`), no los tasks de `\SmartFran\` en Windows Task Scheduler. Lo he descartado para este propósito y he dejado el hallazgo documentado (`data/sch_task_schema_check_20260910.txt`) como referencia futura, no como solución.

He preparado Q32 (PowerShell, para correr en `SFCG-TO-01`) contra el log real de Windows Task Scheduler (`Microsoft-Windows-TaskScheduler/Operational`, eventos 100/102 emparejados por `ActivityId`) — la fuente correcta para duración real por ejecución. Entregado al usuario, pendiente de ejecución.

He incorporado un segundo clon local, `loyalty/repo/SmartLoyalty.SmlBackScript/` (copia desplegada, sin credenciales, de lo que realmente corre en `SFCG-TO-01`). He cruzado `PointsLogGenerator`/`Query074-sql.xml` contra ambos clones — idénticos, sin drift de despliegue. He confirmado además que este script reconstruye `SmlSt.CustomerPointsLog` leyendo `Sml.CustomerPointsLog` — es la capa de staging de la que dependen `CustomerPointsLogToBlob` y el job `Actualiza_DWGrido_CustomerPointsBalance` (H12), no una coincidencia de schema.

## 2026-09-10 — Q32 ejecutado: duración real de los 13 tasks, H13 de-escalado, 08:00 UTC confirmada de nuevo

He ejecutado Q32 contra el log de Windows Task Scheduler en `SFCG-TO-01`. He confirmado que la duración real de cada uno de los 13 tasks que tocan `Sml.CustomerPointsLog` es breve — entre menos de 1 segundo y ~76 segundos por ejecución. He corregido además una suposición: `SendCanjesSocioCortesiaToBlobStorage`/`SendDetalleCanjesSocioCortesiaToBlobStorage` no corren 24/7 como sugería la documentación previa ("cada 30 min de 11:00 a 03:00") — el historial real muestra que están inactivos entre ~03:00 y ~11:00 UTC.

He persistido los resultados en `data/task_duration_history_20260910.txt`. He re-evaluado la severidad de H13: un solapamiento con el lock `Sch-M` del rebuild solo demora estos tasks breves hasta que el lock se libera, sin generar contención sostenida ni bloquear al rebuild — un riesgo mucho menor que el problema original del ticket (bloqueo en vivo de MobileAppService). He agregado H14 documentando esta de-escalación y he actualizado la acción propuesta 1: **la recomendación de 08:00 UTC queda confirmada de nuevo**, con una única verificación pendiente (propósito de negocio de `Program Results`, el único touch diario dentro de la ventana) antes de darla por completamente cerrada.

## 2026-09-10 — Cronograma ASCII final persistido en el evento

He construido un cronograma ASCII de 24hs consolidando todos los hallazgos de este evento: horario POS, jobs semanales (`Backup_FULL`, `Depura Tempdb`, `CapturaUsoIndices`), pico de MobileAppService, el job `Actualiza_DWGrido_CustomerPointsBalance`, los 13 tasks con touch breve sobre `Sml.CustomerPointsLog` (H13/H14), la ventana de `SendCanjes/DetalleSocioCortesia`, y el volumen por hora del resto de los ~40 tasks de `\SmartFran\` confirmados sin touch sobre la tabla. He mostrado la versión final en el chat antes de persistirla, según la regla de previsualización de entregables visuales. He persistido el archivo en `db_schedule_chronogram.txt`, dentro de la carpeta del evento. El resultado reafirma la recomendación de 08:00 UTC como bajo riesgo.

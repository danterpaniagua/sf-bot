# GITIN-2061 — Rebuild de IX_CustomerId acotado a la partición activa

**Tags:** SmartLoyalty, PNSSRL, Mantenimiento, PROD, SRE

## Resumen

`PNSSRL_MantenimientoIndices` reconstruía diariamente `IX_CustomerId` sobre `Sml.CustomerPointsLog` como operación de tabla completa (~397M filas), pese a que la tabla ya está particionada por año y solo la partición del año en curso (partición 11, ~51M filas) recibe escrituras nuevas. Este índice era el mayor contribuyente individual a la duración total (altamente variable, 1h53m-6h14m) del job de mantenimiento, causa raíz común de los bloqueos documentados en GITIN-1981, GITIN-2036 y GITIN-2076. Este ticket aplicó la mejora ya diseñada bajo GITIN-2036 (acción 4): acotar el rebuild de este índice a la partición activa mediante un nuevo job separado, y excluir la tabla del barrido diario encriptado que la reconstruía completa.

**Corrección y resolución (2026-09-22): la exclusión inicial (`indexado=0, defragmentacion=0`) no funcionó como se diseñó — detectado durante una corrida real del job antiguo (disparada manualmente para validar GITIN-2078), que seguía tocando `Sml.CustomerPointsLog.IX_CustomerId` (`ALTER INDEX ... REORGANIZE`). Corregido en la misma sesión agregando `habilitado=0`: confirmado efectivo vía una segunda corrida de prueba (cero actividad sobre la tabla). Ver H6-H9 en Hallazgos.**

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-2061 |
| Sistema | SmartLoyalty SQL Server (`msdb` / `PNSSRL` / SQL Agent) — `SFCG-DB01` |
| Severidad | Media — mejora correctiva sobre un contribuyente principal a un riesgo de bloqueo ya confirmado y recurrente |
| Detectado | N/A — mejora identificada y diseñada bajo GITIN-2036 (2026-09-14), pendiente de aplicación hasta ahora |
| Resuelto | 2026-09-22 — aplicado, corregido (H9) y verificado. Primera corrida real programada del job nuevo sigue pendiente (día de la semana según GITIN-2060: domingo/martes/jueves/sábado, 08:15 UTC) |
| Responsable | Dante Paniagua |

## Causa raíz

El procedimiento encriptado `PNSSRL_MantenimientoModulos`, que genera los `ALTER INDEX REBUILD` del job diario, no tiene ningún mecanismo de alcance por partición — su tabla de control (`PNSSRL_TablasModulos`) solo permite activar/desactivar el mantenimiento de una tabla completa. Como resultado, `IX_CustomerId` se reconstruía sobre las 397M de filas de la tabla entera todas las noches, en vez de solo sobre la partición que efectivamente recibe escrituras nuevas (~51M filas, ~13% del total). Detalle completo de la derivación en `events/20260914_taskoperator_mktcampaign537_errors/` (H9-H11).

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Diseño y factibilidad de la mejora ya confirmados bajo GITIN-2036 — este ticket aplica un borrador de script existente, no lo re-deriva | Informativo |
| H2 | Nuevo job creado y verificado: `PNSSRL_MantenimientoIndices_CustomerPointsLog` (`job_id 5C321470-1BA6-4928-8200-1445D05AC776`), diario a las 08:15 UTC, dos pasos (rebuild de partición activa vía `$PARTITION.fn_partition_LogDate_Anual`, luego `UPDATE STATISTICS`) | Informativo (confirmado) |
| H3 | Tabla `Sml.CustomerPointsLog` confirmada excluida del barrido diario encriptado (`PNSSRL_TablasModulos`, `id_tablas_modulos=292`: `indexado=0, defragmentacion=0`, `habilitado` sin cambios) | Informativo (confirmado) |
| H4 | **Anomalía durante la ejecución, resuelta pero sin causa confirmada**: el primer intento del `UPDATE` de exclusión, incluido en el mismo lote que la creación del job, reportó éxito genérico sin mostrar filas afectadas; una verificación inmediata mostró la tabla de control sin cambios. Al re-ejecutar el `UPDATE` de forma aislada con `SET NOCOUNT OFF`, se confirmó `(1 row affected)` y el cambio surtió efecto correctamente. Detalle en `investigation.md` y `data/job_creation_verification_20260922.txt` | Bajo (resuelto, causa no determinada) |
| H5 | Primera corrida real del nuevo job (2026-09-23, 08:15 UTC) aún no observada — no existe entorno no-productivo donde haber validado esto antes; la corrida real será la primera validación de duración e impacto | Medio (pendiente de observación) |
| H6 | **Confirmado (2026-09-22): la exclusión vía `PNSSRL_TablasModulos` no impide que el job antiguo siga tocando el índice.** Durante una corrida real disparada manualmente, se observó `ALTER INDEX [IX_CustomerId] ON [Sml].[CustomerPointsLog] REORGANIZE;` ejecutándose activamente pese a `indexado=0, defragmentacion=0` re-confirmados sin revertir. Falsea el supuesto heredado de GITIN-2036 (ya marcado ahí como "inferido, no confirmado") de que esas dos columnas determinan si una tabla se procesa. No es un riesgo activo — es `REORGANIZE` (online, bajo impacto de bloqueo), no el `REBUILD` costoso que causó los incidentes originales — pero el objetivo real del ticket (que el job antiguo deje de tocar esta tabla) no está logrado por el mecanismo diseñado | Alto (invalida el mecanismo de la acción 1 original, aunque el riesgo inmediato es bajo) |
| H7 | **Duración real medida de este `REORGANIZE` (2026-09-22): ~28,5 minutos** (`ejecucion` 04:08:10.770 → `fin_indexdefrag` 04:36:39.150, `data/reorganize_duration_and_completion_20260922.txt`), sobre una corrida donde la tabla se alcanzó ~9m12s después del inicio del job (03:58:59 → 04:08:10.770). Comparado con el histórico ya conocido (`REBUILD` completo el 2026-09-20: 46m8s) confirma que la duración de este paso específico no está acotada — depende del umbral de fragmentación que decide `REORGANIZE` vs. `REBUILD`, fuera de nuestro control mientras H6 siga sin resolverse | Alto (invalida cualquier solución basada solo en ampliar el margen horario entre los dos jobs) |
| H8 | **Corrida completa finalizada (2026-09-22): 72 minutos totales** (03:58:59-05:10:32), sin errores. El paso de `CustomerPointsLog` (H7, ~28,5 min) fue el mayor contribuyente individual conocido, pero no el único factor — el resto de las ~60+ tablas del sweep sumó los ~43 minutos restantes en pasos individualmente breves. Confirma que aun con `CustomerPointsLog` reducido a `REORGANIZE`, el job completo sigue siendo sustancialmente más largo que el margen de 15 min originalmente planeado entre este job y el nuevo (ver GITIN-2060/ops.md) | Informativo (dato real, no estimado) |
| H9 | **RESUELTO — `habilitado=0` funciona.** Se agregó `habilitado=0` (además de `indexado=0, defragmentacion=0`) sobre `id_tablas_modulos=292` y se re-disparó el job manualmente como prueba (05:17:42-05:25:09, 7m27s total). Confirmado directamente: **cero filas para `id_tablas_modulos=292`** en `PNSSRL_DetallesEjecucionTablasModulos` para esta corrida — las tablas 290 y 291, antes separadas por 292, ahora se procesan una inmediatamente después de la otra. Salvedad honesta: la reducción total de ~65 min no es atribuible únicamente a la exclusión — esta corrida fue inmediatamente posterior a la anterior, con fragmentación ya baja en general por esa razón. El hecho sólido y confirmado directamente es más acotado: cero actividad sobre `CustomerPointsLog`, no la magnitud exacta del ahorro total. Detalle: `data/habilitado_zero_test_result_20260922.txt` | Informativo (resuelve el objetivo del ticket) |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| `SFCG-DB01` | Host donde corre tanto el job nuevo como `PNSSRL_MantenimientoIndices` |
| `Sml.CustomerPointsLog` (`SmartFran.Solution.SmartLoyalty`) | Tabla cuyo índice `IX_CustomerId` pasa de rebuild completo a rebuild acotado a la partición activa |
| `PNSSRL_TablasModulos` (`PNSSRL`) | Tabla de control del barrido diario encriptado — fila `id_tablas_modulos=292` actualizada |

## Comandos ejecutados

| # | Query | Propósito |
|---|---|---|
| 1 | `sp_add_job` / `sp_add_jobstep` (x2) / `sp_update_job` / `sp_add_jobschedule` / `sp_add_jobserver` | Crear el nuevo job `PNSSRL_MantenimientoIndices_CustomerPointsLog`, sus dos pasos y su programación diaria (08:15 UTC) |
| 2 | `UPDATE PNSSRL_TablasModulos SET indexado=0, defragmentacion=0 WHERE id_tablas_modulos=292` | Excluir `Sml.CustomerPointsLog` del barrido diario encriptado |
| 3 | `SELECT`s sobre `sysjobs`/`sysjobschedules`/`sysschedules`/`sysjobsteps` y `PNSSRL_TablasModulos` | Verificar que ambos cambios surtieron efecto |

Salida cruda persistida en `data/prechecks_20260922.txt`, `data/job_creation_verification_20260922.txt`, `data/precheck_owner_query_error_20260922.txt`.

## Acciones propuestas

1. **(SRE) Completado** — Job de rebuild acotado a partición creado, programado y verificado; exclusión del barrido diario aplicada y verificada.
2. **(SRE) Pendiente** — Observar la primera corrida real del nuevo job (2026-09-23, 08:15 UTC) vía `sysjobhistory`: confirmar duración real y ausencia de bloqueo. Si la duración es significativamente menor a la del rebuild completo (~2h52m para este índice), confirma el beneficio esperado.
3. **(SRE) Pendiente, no bloqueante** — Agregar un chequeo periódico liviano de fragmentación para los otros 3 índices alineados a partición de la tabla (índice agrupado, `IX_CustomerPointsLog_SaleId`, `IX_CustomerPointsLog_Points`), que quedan sin ningún mantenimiento automatizado tras esta exclusión — riesgo bajo confirmado (fragmentación consistentemente baja, mantenimiento real casi nulo ya bajo el job anterior), pero sin dueño hoy.
4. **(SRE) Pendiente, fuera de alcance** — Determinar la causa del `UPDATE` de exclusión que no surtió efecto en su primer intento (H4) — no bloqueó este ticket, pero vale entenderlo si se repite en otro cambio similar.
5. **(SRE) Completado — H9.** `habilitado=0` agregado sobre `id_tablas_modulos=292`, confirmado efectivo vía prueba real (cero actividad sobre `CustomerPointsLog` en la corrida de verificación). El job antiguo ya no toca esta tabla en absoluto. Ticket cerrado.
6. **(SRE) Pendiente, no bloqueante** — Determinar si `habilitado=0` tiene algún efecto secundario no evidente todavía (dado que el procedimiento está encriptado) — no se observó ninguno en la prueba, pero solo se validó una corrida.

## Hallazgos secundarios

Ninguno.

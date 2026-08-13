# Eventos — 20260715_cpu_spikes

## 2026-07-16 13:40 — Reporte del evento

Detecté que el 15/07/2026 Grido lanzó una campaña push que coincidió con picos de uso de CPU en la base de datos. Los envíos de campaña se realizaron a las 14:00, 15:00 y 16:00 UTC-3, con picos superiores al 70% de CPU registrados desde las 17:00 UTC-3.

## 2026-07-16 13:42 — Verificación de disponibilidad de datos

Ejecuté la consulta de disponibilidad sobre `PNSSRL_AuditSysprocesses` para la ventana 2026-07-15 17:00–23:00 GMT (14:00–20:00 UTC-3). Confirmé cobertura completa: 72 snapshots con cadencia de ~5 minutos, desde las 17:01:00 hasta las 22:56:00 GMT.

## 2026-07-16 13:43 — Identificación del SPID responsable

Ejecuté la consulta de deltas de CPU por SPID entre snapshots consecutivos. El resultado mostró al SPID 110 (`sfsqlusr`, host `SFCG-TO-01`, TaskOperatorService) como dominante, con deltas de 60.000–97.000 ms por snapshot de forma sostenida entre las 20:56 y las 22:56 GMT, muy por encima del siguiente consumidor (~53.000 ms, evento aislado). El SPID 110 no mostró bloqueos (`blocked = 0`) en ningún snapshot.

## 2026-07-16 13:44 — Captura de texto completo de la consulta

Ejecuté la consulta sobre `PNSSRL_TempdbProc` para el SPID 110 en la misma ventana. Obtuve el texto completo: un probe `COUNT(*) OVER()` sobre el join `Sml.CustomerPointsLog` ⋈ `Sml.Customer`, con predicado `OR` no sargable que combina rangos sobre `cpl.LogDate` y `c.CreatedDate`. El `cpu_time` creció linealmente (~150.000 ms cada 10 segundos) y las lecturas lógicas escalaron de 10.442 a 278.573 en una única ejecución — consistente con un scan paralelo (DOP ~14-15) sobre un volumen de filas inflado por la campaña.

## 2026-07-16 13:45 — Guardado de evidencia

Guardé el texto completo de la consulta responsable en `20260715_cpu_spikes_query001.sql`, incluyendo el probe de conteo capturado en `PNSSRL_TempdbProc` y el fetch paginado equivalente observado en `PNSSRL_AuditSysprocesses`.

## 2026-07-16 13:46 — Cierre de investigación

Con el SPID, el host, la consulta y la cadena causal confirmados por evidencia, di por cerrada la investigación técnica y generé el ticket de cierre.

## 2026-07-16 14:05 — Confirmación de origen en código

Ubiqué la consulta configurada en el repositorio `dev-src-sol-smartloyalty` (rama `main`), archivo `Other/SqlScript/Updates/v10.07.00/v10.07.00_UpdateETLConfigForSync.sql`, líneas 399–431 — bloque de actualización de `Etl.EtlOperationConfig` Id = 6 (`ToTable = dbo.CustomerPointsLog`). El texto de `FromQuery` coincide de forma verbatim con la consulta capturada en producción. Confirmé además `BatchSize = 1000000`, `SetSize = 100000` (coincide con el `FETCH NEXT 100000 ROWS` observado) y `MaxExecutionPeriod = NULL` — sin límite de tiempo de ejecución configurado. Actualicé el ticket con esta referencia y precisé las acciones propuestas.

## 2026-07-16 14:20 — Propuesta de reescritura sargable

Redacté una propuesta de mejora para el `FromQuery` de la config Id = 6: separar el `OR` no sargable entre `c.CreatedDate` y `cpl.LogDate` en dos ramas mutuamente excluyentes unidas por `UNION ALL`, cada una resoluble con un seek por índice dedicado. Documenté en el archivo de propuesta los riesgos a validar antes de llevarla a un script versionado: el cambio de `ORDER BY cpl.Id` a `ORDER BY CustomerPointsLogId` (requerido por el `UNION ALL`) podría afectar cómo el framework ETL recorta el `ORDER BY` para armar el probe de conteo, y no verifiqué si ya existen índices sobre `Sml.Customer(CreatedDate)` / `Sml.CustomerPointsLog(LogDate)`. Guardé la propuesta en `20260715_cpu_spikes_query002_proposal.sql` y referencié el archivo en el ticket.

## 2026-07-16 14:22 — Email a PMs

Redacté el email a PMs con el resumen del evento y, siguiendo la excepción del skill para incidentes de base de datos, el detalle técnico de la consulta responsable (origen: host, programa, login) y su texto completo. Guardado en `20260715_cpu_spikes_email_pm.md`.

## 2026-07-16 14:24 — Búsqueda de boundaries reales de ejecución

Busqué los valores reales de `@LowerBoundary`/`@UpperBoundary` usados en la corrida capturada. Confirmé que el texto de consulta capturado (`comando_ejecutado`/`Query_Text`) solo contiene la plantilla parametrizada, no los valores reales bindeados en tiempo de ejecución. Localicé el esquema `Etl` en `SmartFran.Solution.SmartLoyalty` (no en `PNSSRL`) y encontré `Etl.EtlOperationExecution`, que registra `LowerLimit`/`UpperLimit`/`TotalRows` por corrida real.

## 2026-07-16 14:24 — Límites reales de la corrida del evento

Con la consulta sobre `Etl.EtlOperationExecution` para la operación `CustomerPointsLog`, obtuve la corrida real (Id 24199): iniciada 2026-07-15 20:53:40 GMT, finalizada 2026-07-16 00:28:04 GMT (12.864 s), `LowerLimit = 2026-07-13 07:25:53`, `UpperLimit = 2026-07-14 20:53:40`, 148.668 filas procesadas. Detecté que esta ventana de datos NO incluye los envíos de la campaña (15/07 14:00–16:00 UTC-3) — la hipótesis inicial de causalidad por la campaña quedó en duda.

## 2026-07-16 14:26 — Historial de 30 días — patrón crónico confirmado

Extraje el historial de 23 ejecuciones de la operación en los últimos ~30 días. Confirmé un patrón consistente: disparo diario habitual a las ~07:25 GMT (~04:25 UTC-3, ventana de baja actividad), rendimiento crónico de ~10-20 filas/segundo en todas las corridas (no solo la del evento). El 15/07 es la única fecha sin ejecución cerca de las 07:25 GMT — el disparo se movió a las 20:53:40 GMT, en pleno horario de actividad. Guardé el historial completo en `20260715_cpu_spikes_etl_history.csv`.

## 2026-07-16 14:27 — Causa disparadora: reinicio de VM

Confirmé que el 15/07 se reinició la VM de base de datos, lo que reprogramó las tareas ETL — esto explica por qué el disparo habitual de las 07:25 GMT no ocurrió ese día. Precisé luego que el reinicio ocurrió entre las 04:30 y las 05:00 UTC-3 (07:30–08:00 GMT), apenas minutos después del horario habitual de disparo (~07:25 GMT) — consistente con que el reinicio interrumpió esa corrida. Reescribí la sección de causa raíz del ticket para reflejar la cadena real: reinicio de VM → disparo habitual salteado → corrida reprogramada a las 17:53 UTC-3 → rendimiento crónicamente bajo (preexistente) expuesto por primera vez en horario de actividad, coincidiendo con (pero no causado por) la campaña de Grido. Actualicé también el email a PMs, que originalmente atribuía la causa a la campaña.

## 2026-07-16 14:35 — Aclaración de impacto normal de campañas push

Agregué un párrafo al email a PMs aclarando que, excluyendo este evento puntual, el impacto propio de los envíos push sobre la base de datos es bajo (picos <50%, promedio 25%) y que no es necesario duplicar la base de datos para el fin de semana, aunque queda como opción si se prefiere ese resguardo adicional.

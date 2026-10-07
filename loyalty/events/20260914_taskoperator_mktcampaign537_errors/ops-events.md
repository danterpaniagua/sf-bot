# Eventos — 20260914_taskoperator_mktcampaign537_errors

## 2026-09-14 — Apertura del evento y corrección de fecha

He abierto este evento a partir del reporte de errores en TaskOperatorService para `MktCampaignId 537`, ventana reportada 04:10–06:55 UTC-3 "del día anterior". He creado `investigation.md` como primer artefacto. Al recibir un extracto real del log de TaskOperatorService, he detectado que las fechas de las fallas corresponden al 2026-09-14 (hoy), no al 2026-09-13 como se había reportado verbalmente — he corregido la ventana de trabajo a 07:10–09:55 UTC del 2026-09-14, conservando el horario del día reportado como correcto.

## 2026-09-14 — Confirmación del mecanismo de bloqueo

He ejecutado Q1-Q6 contra `PNSSRL` y `SmartFran.Solution.SmartLoyalty`. He confirmado el horario vigente de `PNSSRL_MantenimientoIndices` (06:15 UTC, sin cambios respecto a la recomendación de GITIN-1981) y su ventana real de ejecución el 09-14 (06:15–~10:22 UTC). He confirmado la cadena de bloqueo real: la sesión de `SFCG-TO-01`/`sfsqlusr` bloqueada por el SPID del job de mantenimiento, ejecutando `ALTER INDEX REBUILD` sobre `Sml.CustomerPointsLog` — mecanismo idéntico al ya documentado en GITIN-1981/GITIN-1866.

## 2026-09-14 — Investigación y descarte inicial de la hipótesis de "ataque scripteado"

He evaluado la hipótesis de creación scripteada de cuentas de Paraguay como disparador del patrón de reintentos. Q7 no encontró clientes con `Country_Id=9` creados en la ventana del incidente del 09-14. He registrado esto como debilitamiento de la hipótesis, no como descarte definitivo en ese momento.

## 2026-09-14 — Confirmación de patrón diario recurrente (Q9)

He recibido y analizado el historial completo de `Sch.Job`/`Sch.Task` para `ActionId 2508` (2007 filas, 2026-09-07 a 2026-09-14). He confirmado que el job corre en cronograma fijo de 5 minutos, no procesando un backlog, y que el patrón de fallos por timeout se repite todos los días verificados desde su creación (09-07) hasta hoy, siempre en la misma franja horaria — reencuadrando el alcance del ticket de un evento aislado a una falla estructural diaria.

## 2026-09-14 — Confirmación de detalle de excepción y extensión completa de la falla (Q10)

He recibido el historial completo de `Sch.TaskEvent` (72h, 15.804 líneas), guardado en `data/q10.txt`. He confirmado el texto exacto de la excepción (`Execution Timeout Expired`) y su stack trace completo, la identidad de `MktCampaignId` como 537 (no 536, descartando una mención aislada anterior), y la extensión completa de la falla del 09-14: 34 fallos distintos entre 07:10:59 y 09:55:48 UTC.

## 2026-09-14 — Cierre definitivo de la hipótesis de "ataque scripteado" (Q11)

He revisado nuevamente la hipótesis de ataque scripteado a la luz del patrón diario confirmado. He señalado que la evidencia ya reunida (Q7, mecanismo de cronograma fijo en Q9) no la respalda, y he ejecutado Q11 para verificar la ventana completa de 7 días. He confirmado que solo 12 de 929 altas de Paraguay caen en el rango horario 07-09 UTC, sin concentración de canal, y ninguna en el día del incidente (09-14) — he descartado la hipótesis de forma definitiva y he registrado el análisis (agregado, sin exponer PII cruda) en `investigation.md`.

## 2026-09-14 — Redacción de `ops.md`

He redactado el ticket de cierre (`ops.md`) para GITIN-2036, referenciando GITIN-1981 como ticket relacionado con la misma causa raíz y recomendación de horario aún sin aplicar. He propuesto como acción principal aplicar esa reprogramación ya definida, en vez de duplicar una nueva recomendación.

## 2026-09-14 — Redacción de email a Operaciones

He redactado `email_ops.md` para GITIN-2036, en tono de coordinación entre pares, sin código ni estimaciones de tiempo, proponiendo que la reprogramación ya preparada en GITIN-1981 cubra también este ticket.

## 2026-09-14 — Investigación de mejora al rebuild: partitioning confirmado

He evaluado alternativas al rebuild diario completo (chunking, rebuild solo del año en curso) más allá de la sola reprogramación de horario. He confirmado en vivo la edición del servidor (Standard, 16.0.4075.1, RTM CU8) y, vía `sys.dm_db_persisted_sku_features`, que `Partitioning` y `Compression` ya están en uso activo en esta base. He confirmado que `Sml.CustomerPointsLog` está particionada por año (`sch_LogDate_Anual`, 16 particiones), y que el índice `IX_CustomerId` — el mismo confirmado como bloqueador en Q5/Q6 — está alineado con ese esquema. La partición 11 (~51M filas) es la única con crecimiento activo; las particiones 1-10 corresponden a años históricos cerrados. He preparado Q14 para capturar el texto real del comando `ALTER INDEX` durante la próxima corrida (noche del 2026-09-14 al 2026-09-15) y confirmar si el job ya limita el rebuild a la partición activa o reconstruye la tabla completa — pendiente de resultado hasta mañana.

## 2026-09-14 — Confirmación directa del alcance del rebuild sin esperar a mañana (Q15-Q20)

He identificado, a partir de los parámetros de `PNSSRL_MantenimientoModulos` (Q15), la tabla de control `PNSSRL_TablasModulos` y el log de ejecución `PNSSRL_DetallesEjecucionTablasModulos` (Q16-Q18) — ambos legibles pese a que el procedimiento en sí está encriptado. He confirmado con el log real de ejecución (Q19) que `IX_CustomerId` sobre `Sml.CustomerPointsLog` (`id_tablas_modulos=292`) se reconstruye como tabla completa (~397M filas) tanto el 2026-09-13 (47m8s) como el 2026-09-14 (2h52m25s) — sin necesidad de esperar la corrida de mañana. He confirmado además, vía los valores de límite de la función de partición (Q20), que la partición 11 corresponde al año 2026 en curso. He actualizado H9 de "pendiente" a confirmado en `ops.md` y `investigation.md`, y he fortalecido la acción propuesta 4 con el mecanismo exacto (`REBUILD PARTITION = 11`) como mejora adicional a la reprogramación de horario ya propuesta.

## 2026-09-14 — Confirmación de que la tabla de control no soporta alcance por partición

He revisado la fila completa de `PNSSRL_TablasModulos` para `Sml.CustomerPointsLog` (`id_tablas_modulos=292`), ya disponible en el resultado de Q18 sin necesidad de una consulta nueva. He confirmado que la tabla de control solo expone interruptores de tabla completa (`indexado`, `defragmentacion`, `habilitado`) y ninguna columna de alcance por partición — aplicar el rebuild acotado a la partición activa requeriría excluir esta tabla del barrido diario y agregar un paso separado fuera del procedimiento encriptado. He registrado este hallazgo en `ops.md` y `investigation.md`.

## 2026-09-14 — Verificación de la ausencia de horarios de baja actividad en TaskOperatorService

He confirmado con la evidencia completa de Q9 que `ActionId 2508` corre en cronograma fijo de 5 minutos las 24 horas, sin ninguna ventana de inactividad — lo que invalida la reprogramación de horario de GITIN-1981 como corrección suficiente para este ticket. He corregido `ops.md` en consecuencia (acción 1 y hallazgos H5/H10).

## 2026-09-14 — Confirmación de que el cronograma fijo no es configurable ni específico de esta campaña (Q21-Q23)

He revisado el esquema completo de `Sch.Job` (Q21) y confirmado que no existe ninguna columna de intervalo, horario activo o ventana de exclusión. He comparado el cronograma de `ActionId 2508` contra las diez campañas `MktAsignationPointActionManager` anteriores relevadas desde 2021 (Q23) y confirmado el mismo cronograma fijo de ~5 minutos en todas, sin excepción — comportamiento universal del motor de campañas, no una configuración particular de la campaña 537. He fortalecido H10 en `ops.md` con este hallazgo y he corregido `loyalty/docs/task_operator_tasks.md`, cuya caracterización previa ("no en un cronograma fijo") quedaba desactualizada para efectos de riesgo de bloqueo.

## 2026-09-14 — Evaluación del particionado anual y ausencia de mantenimiento de límites (Q24-Q25)

He evaluado si el particionado anual de `Sml.CustomerPointsLog` está bien dimensionado frente a una alternativa trimestral/mensual, concluyendo que anual es razonable para la mejora propuesta en esta investigación sin requerir un re-particionado. He confirmado además que no existe ningún job de SQL Agent que agregue nuevos límites de partición, y que la función de partición no fue modificada desde su creación en 2023-11-08 — los límites hasta 2030 se definieron de una sola vez, sin mantenimiento incremental desde entonces. He registrado este hallazgo como secundario en `ops.md`, fuera del alcance directo de este ticket.

## 2026-09-14 — Verificación del riesgo de excluir la tabla completa del barrido diario

He evaluado si excluir `Sml.CustomerPointsLog` del job diario abandonaría mantenimiento activo sobre sus otros 4 índices, no solo `IX_CustomerId`. He confirmado con el historial completo de ejecución (Q26) que ninguno de esos 4 índices recibe rebuild real en la muestra disponible (~20 noches), y que el reorganize real ocurre solo 4 veces en total, con fragmentación consistentemente baja. He registrado este hallazgo como H11 en `ops.md`, reduciendo el riesgo de la acción 4 en vez de aumentarlo.

## 2026-09-14 — Redacción del script propuesto y análisis de riesgos/reversión

He redactado en `scripts.sql` el script de la corrección propuesta (exclusión de `Sml.CustomerPointsLog` del barrido diario + rebuild acotado a la partición activa, con el número de partición calculado dinámicamente). He documentado en `ops.md` los riesgos de cada parte, su plan de reversión, y el riesgo principal de secuenciación: sin un job recurrente real para la Parte 2, excluir la tabla del barrido diario dejaría `IX_CustomerId` sin mantenimiento. El script no fue ejecutado ni probado en un entorno de prueba.

## 2026-09-14 — Reescritura de `email_ops.md` con el estado final

He reescrito `email_ops.md` con la estructura de detección y propuesta actualizada, incorporando los hallazgos confirmados en esta sesión (bloqueo por mantenimiento de índices, rebuild sin optimizar, cronograma de campañas sin ventana de baja actividad). He descartado la afirmación inicial sobre superposición con el backup full por no estar respaldada por la evidencia ya confirmada (Q3) — la he quitado del correo en vez de dejarla como nota de corrección.

## 2026-09-14 — Agregado de secciones de riesgos y plan de reversión al correo

He agregado a `email_ops.md` las secciones "Riesgos" y "Plan de reversión", en lenguaje llano y sin sentencias SQL, con el detalle técnico completo referenciado al ticket en vez de incluido en el correo — siguiendo la regla de la skill de no incluir código en correos a Operaciones.

## 2026-09-14 — Confirmación de una segunda víctima y corrección sobre la reprogramación de horario

He verificado si el bloqueo afecta solo a `MktCampaignId 537` o a cualquier proceso que toque `Sml.CustomerPointsLog`. He confirmado que no hay otra campaña `MktAsignationPointActionManager` activa en paralelo, pero he encontrado una segunda víctima independiente y concreta: `EtlDwGridoCustomerPointsLogProcessor`, con degradación diaria de 1h56m-4h55m y una falla completa el 2026-09-09. He elevado la severidad del ticket en consecuencia y he agregado H12/H13 y las acciones 5/6 en `ops.md`.

Al revisar `Sch.TimeTable` (tabla apuntada por `TimeTableId`, no explorada hasta ahora) he encontrado columnas de frecuencia/horario reales, pero no pude leer la fila de la campaña 537 por falta de permiso de `SELECT`. He corregido en `loyalty/docs/task_operator_tasks.md` y en `ops.md` la afirmación anterior de que no existía ninguna palanca de configuración de horario — quedaba como no confirmada, no como descartada.

## 2026-09-14 — Actualización de `email_ops.md` con la segunda víctima y el permiso pendiente

He agregado a `email_ops.md` el hallazgo de `EtlDwGridoCustomerPointsLogProcessor` como segunda víctima confirmada, y una mención al permiso de `SELECT` pendiente sobre `Sch.TimeTable` como posible vía de coordinación con Operaciones.

## 2026-09-14 — Confirmación del intervalo configurable en `Sch.TimeTable` tras el otorgamiento de permiso

Con el permiso de `SELECT` ya otorgado a `sfzabbix`, he leído la fila real de `Sch.TimeTable` para `TimeTableId 168898` y he confirmado `FrecuencyType='Minutes'`, `FrecuencyInterval=5` — el intervalo de 5 minutos es un valor de configuración simple, no lógica de aplicación fija como se había dejado sin confirmar antes. He corregido H13 en `ops.md` de "no confirmado" a confirmado, he agregado la acción 5 como alternativa real de bajo riesgo técnico pero con impacto de negocio a validar, y he actualizado `investigation.md`, `task_operator_tasks.md` y `email_ops.md` en consecuencia.

## 2026-09-14 — Verificación contra el código fuente real: dos filas de Sch.TimeTable no son viables

He revisado si dos filas de `Sch.TimeTable` (una de noche, otra de día) podrían coexistir para el mismo job. En vez de asumir a partir del esquema de base de datos, he leído el motor de scheduling real en `loyalty/repo/dev-src-sol-smartloyalty/Front/TaskOperatorService/TaskOperatorService.cs` y he confirmado que `task.TimeTable` es una propiedad singular, sin ninguna lógica de selección entre varias filas — una segunda fila para el mismo `JobId` simplemente no sería leída. He encontrado además un precedente real de cómo se modificó este sistema antes (`v5.11_UpdateTimetableEtlSmlCustomerTarget.sql`), que actualiza la fila existente en vez de insertar una nueva. He actualizado la acción 5 en `ops.md` y el detalle en `investigation.md` con esta confirmación.

## 2026-09-14 — Verificación del mecanismo de reintento y de la idempotencia del acreditado de puntos

He revisado el código real de `DoPointAssignationAction` y `Query084-sql.xml` para responder si las tareas fallidas se reprograman y si eso genera duplicación de puntos. He confirmado que cada tarea (falle o no) genera la siguiente en el cronograma normal, sin mecanismo especial de reintento, y que el diseño es idempotente — la consulta de selección excluye a quien ya tenga puntos acreditados, independientemente del watermark de la campaña. He de-escalado H8 en `ops.md` tras esta confirmación. He dejado registrada como pregunta abierta, no verificada, si el motor de scheduling (en una librería compartida no clonada en este repositorio) previene solapamiento de ejecuciones si algún día una corrida superara el intervalo de 5 minutos.

## 2026-09-14 — Agregado de la confirmación de idempotencia a `email_ops.md`

He agregado a la sección de riesgos de `email_ops.md` la confirmación de que ninguna falla genera pérdida ni duplicación de puntos. He dejado fuera del correo la pregunta abierta sobre solapamiento de ejecuciones, por ser un detalle técnico interno sin acción pendiente asociada.

## 2026-09-14 — Refinamiento del patrón de duración por día de semana

He buscado un ejemplo de corrida de 2.5-3h de `IX_CustomerId` en un día sin `Backup_FULL`, sin encontrar ninguno en las 20 noches muestreadas. He confirmado en cambio un patrón más preciso: las 4 corridas largas caen exclusivamente en domingo o lunes, nunca en miércoles (también día de backup) ni en ningún día sin backup. He agregado H14 en `ops.md` y el detalle completo en `investigation.md`, dejando explícito que esto refina la causa de la variabilidad sin cambiar la corrección ya propuesta.

## 2026-09-16 — Vinculación de los tickets hijos creados en Jira

He vinculado en `ops.md` los dos tickets hijos ya creados en Jira para las acciones propuestas: GITIN-2060 (reprogramación de horario, acción 1) y GITIN-2061 (rebuild acotado a la partición activa, acción 4). He agregado ambos también a la tabla resumen, fila "Tickets hijos".

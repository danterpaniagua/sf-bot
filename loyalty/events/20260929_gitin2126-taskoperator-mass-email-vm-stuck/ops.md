**Tags:** SmartLoyalty, TaskOperator, Azure

## Resumen

`sfdev02` corre tanto TaskOperatorService como su SQL Server local para los ambientes `test02` y `preprod` — a diferencia de producción, donde el servicio y la base viven en hosts separados. El 2026-09-29 se reportó un envío masivo de emails desde `TEST02` y la VM atascada en estado "Deallocating" por más de 10 minutos al reiniciarse.

El envío masivo es TaskOperatorService enviando su propio mail de alerta por excepción (`"ERROR!! on TaskOperatorService [SFDEV02]"`) hacia tres grupos internos (`grupo.servicesit@`, `grupo.it.analysts@`, `operaciones@smartfran.com` — no clientes), sin ningún throttling: cuando la conexión SQL local falla de forma persistente, el bucle principal de TaskOperatorService reintenta sin pausa entre excepciones, generando un email por cada intento fallido. `test02` envía correo a través de SendGrid; las estadísticas de SendGrid confirman **54.975 requests el 2026-09-29** (vs. 403 el día anterior, normal). El backlog de entrega de SendGrid (independiente de la app) siguió resolviéndose por varias horas después de haberse detenido el servicio — actividad confirmada hasta las `19:29 UTC` vía API, y sin nuevas llegadas reportadas desde las `20:22 UTC` en adelante, siempre entregando/rebotando mensajes ya enviados, nunca generando nada nuevo.

Hubo dos caídas de `sfdev02` en el período. La primera (noche del 28, 22:01-22:29) es el apagado nocturno programado de la VM en Azure — un evento que se repite todas las noches, no un incidente puntual. La segunda (tarde del 29, 13:36-14:22) tiene el síntoma de "Deallocating" explicado por dos acciones manuales de VM superpuestas durante la respuesta al incidente, pero su origen — por qué la conexión SQL se rompió y `Preprod` terminó inesperadamente a las 13:36:33, media hora antes de cualquier intervención manual — no está identificado; es la única causa raíz de fondo que queda abierta en este ticket.

Como mitigación se detuvo y deshabilitó el servicio Windows de TaskOperator en `test02` y `preprod`. `test02` pasó por varios ciclos de reactivación/detención a lo largo del día — una prueba inicial (corrida limpia, sin incidentes), un nuevo apagado tras confirmarse que el envío masivo seguía en curso (backlog de entrega de SendGrid, no la app), y una reactivación final para verificación directa. Esa reactivación final quedó confirmada sana por evidencia directa, no por inferencia: conexión SQL sana (`SELECT GETUTCDATE()` exitoso) y una corrida completa de `test02` sin ninguna excepción en el log — y por separado, en chequeos posteriores, se confirmó que el backlog de entrega de SendGrid también había terminado de drenar por completo (100% de los mensajes ya entregados, cero pendientes de reintento).

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2126](https://smartit-ar.atlassian.net/browse/GITIN-2126) |
| Sistema | TaskOperatorService (SmartLoyalty) — VM `sfdev02`, ambiente `TEST02` |
| Severidad | Alto |
| Detectado | 2026-09-29 |
| Resuelto | Parcial — envío masivo confirmado detenido: backlog de entrega de SendGrid drenado por completo (verificado, cero mensajes pendientes de reintento). `test02` reactivado y confirmado sano por evidencia directa (query SQL directa + corrida completa sin ninguna excepción); `preprod` sigue deshabilitado. Mecanismo, volumen y timeline del incidente completamente entendidos. Queda abierto: causa raíz de por qué la conexión SQL se rompió el 29/09 entre las 13:36 y 14:04 (no vuelto a repetirse desde entonces — ver H6 por una pista de deploy aún no confirmada), y el fix de código pendiente de implementar. |
| Responsable | SRE SmartLoyalty |

## Causa raíz

**Envío masivo — mecanismo confirmado en código fuente** (`Front/TaskOperatorService/TaskOperatorService.cs`, método `ThreadOperator`): el bucle principal del servicio llama a `RunSchedule()` dentro de un `try/catch`. Cuando `RunSchedule` lanza una excepción no manejada, el `catch` envía dos emails (a `customerSupportEmail` e `itServicesEmail`, asunto `"ERROR!! on TaskOperatorService [hostname]"`) y hace `continue` sin ningún `Thread.Sleep` — solo el camino exitoso duerme. Una falla de conexión SQL persistente convierte esto en un bucle sin freno (~8+ iteraciones/segundo), generando un volumen de emails muy por encima de lo que cualquier persona esperaría de un mecanismo de alerta. El mismo código produce el texto exacto ("Requires support attention.") de las alertas genéricas recibidas repetidamente durante el incidente (`12:14:53`, `13:51:36`, `13:54:46`, `14:07:07`).

**Caída de VM — dos eventos distintos, con distinto origen.** La caída de la noche del 28 (22:01-22:29) es el Auto-shutdown programado de Azure sobre `sfdev02` (`shutdown-computevm-sfdev02`, `19:00` hora Argentina) — un evento diario, no un incidente. Al compartir `test02`/`preprod` y su SQL Server la misma VM, este apagado nocturno tumba también la base local todas las noches.

La caída de la tarde del 29 (13:36-14:22) tiene dos partes. El síntoma reportado ("atascada en Deallocating >10 min") está explicado por el registro de actividad de Azure: dos acciones manuales de VM superpuestas durante la respuesta al incidente (un `deallocate` a las `14:07:03`, un `powerOff` de otra persona del equipo a las `14:12:46` que falló por conflicto con el `deallocate` en curso, y un segundo `deallocate` a las `14:14:58` que recién tuvo éxito a las `14:18:54` — unos 11-12 minutos, coincidente con lo reportado). Pero el origen de esa caída — `Preprod` terminó inesperadamente a las `13:36:33` y la conexión SQL se rompió (tormenta de más de 1.140 excepciones entre `13:41` y `14:04`) **antes** de que cualquier acción manual comenzara — no está identificado. Esta es la única causa raíz de fondo sin confirmar en todo el incidente.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Mecanismo del envío masivo confirmado en código fuente: `ThreadOperator()` sin backoff en el camino de excepción — ver Causa raíz. No es `AutoAcceptAccountRecovery`. Destinatarios: `grupo.servicesit@`, `grupo.it.analysts@`, `operaciones@smartfran.com` (internos, no clientes). | Alto |
| H2 | Volumen confirmado vía SendGrid: 54.975 requests el 2026-09-29 (vs. 403 normal el día anterior). El backlog de entrega de SendGrid, independiente de la app, siguió resolviéndose por varias horas después de detener `test02` — actividad confirmada hasta las `19:29 UTC` vía API, sin nuevas llegadas reportadas desde las `20:22 UTC`, nunca con mensajes nuevos, solo entregas/rebotes de lo ya enviado durante la tormenta. | Alto |
| H3 | La limitación de recepción de G Suite sobre `operaciones@`/`grupo.it.analysts@` (36.638/36.480 mensajes rechazados `13:45-14:46 UTC`, 28.913/28.868 `14:45-15:46 UTC`) es consecuencia directa de H1/H2. | Alto |
| H4 | `sfdev02` tiene un Auto-shutdown de Azure habilitado (`shutdown-computevm-sfdev02`, `19:00` hora Argentina), que explica la caída de la VM la noche del 28/09 — evento recurrente, no aislado. | Alto |
| H5 | El síntoma "atascada en Deallocating" de la tarde del 29/09 fue causado por dos acciones manuales de VM superpuestas durante la respuesta al incidente (`deallocate`/`powerOff` fallido/`deallocate`), no por una falla de plataforma. | Medio |
| H6 | **Origen de la caída de conexión SQL de la tarde del 29/09 (13:36-14:04) sin confirmar** — ocurrió antes de cualquier acción manual sobre la VM. Es la única causa raíz de fondo abierta en este ticket. **Pista nueva, no confirmada** (C15): la rama `test02` del repositorio fuente (distinta de `main`, que está un mes desactualizada) tuvo un merge real a las `09:33` del 28/09 — un día antes del incidente — con un feature grande ("SaleProvider"/"Insignia") que modifica `Core/Data/Data/Context/SmartLoyaltyContext.cs`, el contexto de EF que usa TaskOperatorService. No confirmado si ese build llegó a desplegarse en `sfdev02`, ni un mecanismo directo que lo conecte con la falla de conexión — la migración más reciente ya estaba aplicada en la base seis días antes (`Sml.202609231326210_AddInsigniaRollbackColumns`, 23/09), así que el 28/09 pudo haber sido solo un deploy de código reutilizando el esquema existente. **Descartado, 2026-09-30**: un evento de plataforma de Azure compartido con GITIN-2128 (`smartfran-graylog-pro` tuvo un timeout de I/O a Azure Storage confirmado oficialmente el mismo día) — el Resource Health de `sfdev02` no muestra ningún evento `platformInitiated=true` en todo el día (`data/az_resource_health_events_sfdev02_summary_20260929.txt`); son incidentes no relacionados. | Alto |

## Recursos afectados

| Componente | Impacto |
|---|---|
| TaskOperatorService (`TEST02`) | Envío masivo confirmado (H1/H2) — 54.975 requests a SendGrid el 29/09; backlog de entrega resolviéndose por horas, confirmado al menos hasta las `19:29 UTC` |
| Buzones internos (`grupo.servicesit@`, `grupo.it.analysts@`, `operaciones@`) | Limitación de recepción de G Suite por el volumen (H3) — riesgo de pérdida/demora de otros correos operativos legítimos durante la ventana |
| VM `sfdev02` | Dos caídas: apagado nocturno programado (28/09, recurrente, H4) y caída con origen sin confirmar (29/09 tarde, H6), con síntoma de "Deallocating" explicado por acciones manuales superpuestas (H5) |
| TaskOperator — `test02` | Reactivado tras confirmar backlog de SendGrid drenado y conexión SQL sana (corrida sin excepciones) |
| TaskOperator — `preprod` | Detenido y deshabilitado, sin cambios durante todo el incidente |

## Comandos ejecutados

Análisis local de los 35 archivos `.svclog` provistos por el usuario (`SmartLoyalty.TaskOperatorService.zip`) — patrones/frecuencia y registro de auditoría por tarea (`BeginOn`/`EndOn`/`Elapsed`), sin persistir contenido crudo en este repositorio (formato con riesgo histórico de PII real de clientes).

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | `SELECT sqlserver_start_time FROM sys.dm_os_sys_info` | Confirmar el reinicio de SQL Server local durante la caída del 29/09 |
| C2 | `Get-WinEvent` (Service Control Manager, log System, 24h) en `SFDEV02` | Reconstruir el timeline de paradas/arranques de ambos servicios |
| C3 | Análisis de `_13214.svclog` y del `.svclog` completo de la corrida de prueba (16:36-17:24, tras reactivar `test02`) | Confirmar conexión sana antes del apagado manual y corrida de prueba limpia |
| C4 | `az vm list` | Ubicar el resource group de `sfdev02` |
| C5 | `Get-WinEvent` (System, Event ID 41/1074/6005/6006/6008/109) en `SFDEV02` | Identificar el mecanismo de apagado (`wvchelper`/Azure Guest Agent) en ambas caídas |
| C6 | `az monitor activity-log list` sobre `sfdev02` | Confirmar el origen del síntoma "Deallocating" (H5) — dos acciones manuales de VM superpuestas |
| C7 | `az resource show` sobre `shutdown-computevm-sfdev02` | Confirmar el horario del Auto-shutdown (H4) |
| C8 | Emails de alerta genérica pegados por el usuario (`12:14:53`/`13:51:36`/`13:54:46`/`14:07:07`) | Acotar la ventana de "algo ya andaba mal" antes de la caída confirmada |
| C9 | Alertas de G Suite (limitación de recepción) pegadas por el usuario | Detectar el volumen real del envío masivo (H3) |
| C10 | `GET /v3/stats` de SendGrid (diario, 28-29/09) | Confirmar la escala real: 54.975 requests el 29/09 vs. 403 el 28/09 (H2) |
| C11 | `GET /v3/messages` de SendGrid (Email Activity) | Identificar el mecanismo real del envío masivo (H1) |
| C12 | `GET /v3/messages` de SendGrid, paginado (7 llamadas + rechequeos posteriores) | Confirmar el backlog de entrega resolviéndose por horas, sin nada nuevo (H2) |
| C13 | Revisión de código fuente (`ThreadOperator()`, `AutoAcceptAccountRecovery.cs`, `LoyaltyEmailNotifier.cs`) | Confirmar el mecanismo exacto del envío masivo (H1) y descartar `AutoAcceptAccountRecovery` como causa |
| C14 | `SELECT GETUTCDATE()` sobre `TEST02` + análisis del `.svclog` de una corrida completa de `test02` (19:28-19:33) tras reactivar | Confirmar que la conexión SQL está sana ahora mismo y que el reinicio no generó ninguna excepción nueva |
| C15 | `git fetch` + `git diff origin/main...origin/test02` sobre el repo fuente | Verificar si hubo un deploy el 28/09 que pudiera explicar la caída de conexión (H6) — encontrado un merge real a las `09:33` en la rama `test02` (`main` está un mes desactualizado), sin relación directa confirmada aún con el mecanismo de la falla |

## Acciones propuestas

1. **(Dev) FIX REQUERIDO — Corregir `ThreadOperator()` en `Front/TaskOperatorService/TaskOperatorService.cs`: falta backoff en el camino de excepción.** El `catch` del bucle principal envía 2 emails y hace `continue` sin ningún `Thread.Sleep`. Agregar un `Thread.Sleep` al `catch` (mismo intervalo que el camino exitoso, o con backoff creciente) y/o deduplicar excepciones idénticas repetidas antes de re-enviar el email. Sin este fix, el mismo defecto se dispara ante cualquier corte de conexión SQL futuro — no es específico de este incidente.
2. **(SRE/Infra) Investigar el origen de la caída de conexión SQL del 29/09 (H6) — única causa raíz de fondo abierta.** Por qué `Preprod` terminó inesperadamente a las `13:36:33`. Puntos de partida: log de errores de SQL Server local en `sfdev02` para esa ventana, y confirmar con Dev si el merge de la rama `test02` (`09:33` del 28/09, ver H6) efectivamente se desplegó en `sfdev02` y si incluyó un recycle del servicio/app pool.
3. ~~(SRE) Decidir si `test02` puede reactivarse~~ — **resuelto**: reactivado tras confirmar directamente (no por inferencia) que el backlog de SendGrid drenó por completo y que la conexión SQL está sana (query directa + corrida completa sin excepciones). `preprod` sigue deshabilitado; evaluar su reactivación con el mismo criterio si se necesita.
4. **(Dev) Implementar shutdown ordenado ("nice shutdown") en TaskOperatorService** — el apagado nocturno de `sfdev02` (H4) es recurrente, no aislado; sin drenar el trabajo en curso antes de cerrar conexiones, cada noche repite el riesgo de pérdida/inconsistencia de datos. Mismo patrón resuelto para SmartFran Cloud (`cloud/events/20260922_gitin1637-api-healthcheck-sla/`): enganchar `ApplicationStopping`/`ApplicationStopped` para dejar de tomar trabajo nuevo, drenar lo en curso, y sólo entonces cerrar conexiones.
5. **(SRE/Infra) Decidir si el Auto-shutdown nocturno de `sfdev02` (H4) debe deshabilitarse o reprogramarse** hasta que la Acción 4 esté implementada.
6. **(SRE) Coordinar acciones sobre VMs en Azure entre miembros del equipo durante respuesta a incidentes** — evitar llamadas superpuestas/conflictivas (`deallocate`/`powerOff` simultáneos) como las de H5.

# [TAREA] Picos de CPU (User Time hasta 92.69%) en VM de base de datos durante nuevo load test de Grido — mismo patrón que GITIN-1669

## Resumen

Durante un nuevo load test de Grido ejecutado el 03/08/2026, se reportaron picos de "CPU User Time" a nivel de sistema operativo en la VM de base de datos (`SFCG-DB01`), observados en el mismo Zabbix legado (instancia no migrada, sin API) identificado en GITIN-1669: un pico cerca de las 10:00 (UTC-3) y dos picos adicionales cerca de las 14:15 y 14:45 (UTC-3), con un máximo de 92.69%. La investigación sobre las tablas de captura de `PNSSRL` para la ventana completa (12:00-18:30 GMT) encontró que el total de CPU agregado de todas las sesiones SQL Server nunca superó ~6.3% de la capacidad de 16 núcleos del servidor. El primer pico (~10:00 UTC-3) tiene una correlación plausible — aunque no confirmable — con un job crónico de sincronización (SPID 114, TaskOperatorService); los otros dos picos (14:15 y 14:45 UTC-3) no tienen ningún correlato ni a nivel de sesión SQL Server ni a nivel de sistema operativo (reinicio, Windows Update, escaneo de Windows Defender — todos descartados). La causa raíz de esos dos picos permanece sin resolver, igual que en GITIN-1669.

## Tabla resumen

| Campo | Valor |
|---|---|
| Sistema | SmartLoyalty SQL Server (`PNSSRL`) — `SFCG-DB01` |
| Severidad | Media |
| Detectado | 2026-08-03 09:30-10:00 y 14:00-15:00 (UTC-3), durante load test de Grido |
| Resuelto | Pico 1 (~10:00 UTC-3) con correlación plausible no confirmada. Picos 2 y 3 (14:15 y 14:45 UTC-3) sin causa identificada — descartadas todas las hipótesis a nivel de motor SQL Server y de sistema operativo verificables de forma retroactiva |
| Responsable | Dante Paniagua |
| Ticket Jira | [GITIN-1749](https://smartit-ar.atlassian.net/browse/GITIN-1749) |
| Ticket relacionado | [GITIN-1669](https://smartit-ar.atlassian.net/browse/GITIN-1669) (20260727_cpu_peaks_loadtest — mismo patrón) |

## Causa raíz

**Nota de corrección (2026-08-03, misma sesión):** la primera pasada de chequeos a nivel de sistema operativo (Windows Update, Windows Defender, tareas programadas, Data Collector Sets existentes) se ejecutó por error en `SFCG-TO-01` (servidor de aplicación de TaskOperatorService) en lugar de `SFCG-DB01` (motor de base de datos, el host cuyos picos de CPU son objeto de este ticket) — el acceso RDP disponible apuntaba por defecto a `SFCG-TO-01`. Se detectó por los prefijos `\\SFCG-TO-01\...` en la exportación CSV del colector `CPUWatch`, y se repitió toda la batería de chequeos confirmando el hostname (`$env:COMPUTERNAME`) en cada comando. Los hallazgos de `SFCG-TO-01` se conservan como contexto útil (ver `docs/infrastructure.md` → "Scheduled Tasks (`SFCG-TO-01`)"), pero la Causa raíz de abajo refleja únicamente los resultados verificados en `SFCG-DB01`.

**Pico 1 (~10:00 UTC-3 / ~13:00 GMT) — correlación plausible, no confirmada.** SPID 114 (login `sfsqlusr`, host `SFCG-TO-01`, TaskOperatorService) ejecutó de forma continua el job paginado de sincronización de `CustomerPointsLog`/`Customer` entre las 12:06 y 13:06 GMT, saturando cerca de un núcleo completo (~6.3% del total de 16 núcleos — el equivalente matemático de 1/16). Esta magnitud coincide con la hipótesis de que el ítem Zabbix "CPU User Time" mide el núcleo más caliente en un momento dado (agregación `[max]` sobre 16 núcleos) en lugar del promedio de toda la VM (`CPU Utilization`, agregación `[avg]`) — un núcleo saturado al 100% mientras los otros 15 están inactivos se leería como ~100% en el primer gráfico pero solo ~6% en el segundo, que es exactamente la brecha observada entre ambos gráficos (92.69% vs. 41-42%). No se puede confirmar esta teoría sin acceso a la configuración de los ítems en la instancia Zabbix legada. Reforzado por un cluster de tareas programadas en `SFCG-TO-01` (`ReportUpdateCustomer`, `ReportErrorSurveyNoResponse`, `NotSamplesSurveyActivated`, `Promotion Vigency Advisor B/C`) que se ejecutan entre las 12:00 y las 12:30 GMT, justo dentro de la ventana de SPID 114 — solo 2 de las 5 son realmente diarias, el resto semanal/bisemanal/mensual, así que la superposición del 03/08 fue en parte coincidencia de calendarios independientes.

**Picos 2 y 3 (14:15 y 14:45 UTC-3 / 17:15 y 17:45 GMT) — sin causa identificada, batería completa verificada en `SFCG-DB01`.** El total de CPU de todas las sesiones SQL Server capturadas se mantuvo en ~0% en ambos intervalos exactos — no hay ninguna sesión ni acumulado de sesiones que explique el pico. Se descartaron además, a nivel de sistema operativo, confirmado directamente en `SFCG-DB01`: un reinicio del servidor (última vez: 2026-07-15, sin relación); instalación de actualizaciones de Windows (a diferencia del patrón diario fijo de `SFCG-TO-01`, en `SFCG-DB01` las instalaciones de Security Intelligence de Defender están dispersas todo el día — 13:28:56, 07:55:33, 00:53:49 GMT hoy, etc. — ninguna cae dentro de los 15 minutos de ningún pico); actividad de Windows Defender (sin escaneos completos ni rápidos en la ventana, sin detecciones, solo heartbeats rutinarios ~:44:51 cada hora); los dos Data Collector Set preexistentes del Azure Guest Agent (`GAEvents`, `RTEvents`, tracing de bajo overhead, sin señal de ráfaga); y tareas programadas — `SFCG-DB01` **no tiene** la carpeta `\SmartFran\` (exclusiva de `SFCG-TO-01`), solo tareas genéricas de Windows (`PcaPatchDbTask`, `SystemTask`/CertificateServicesClient, `Schedule Scan`/UpdateOrchestrator, `QueueReporting`, `Consolidator`/CEIP), ninguna dentro de los 15 minutos de los picos. La causa real queda fuera del alcance de lo que las tablas de captura de `PNSSRL` y los logs de Windows de `SFCG-DB01` pueden diagnosticar — la única vía real para identificarla es una captura en vivo de procesos del sistema operativo durante el próximo load test, tal como se recomendó en GITIN-1669 y no se implementó antes de este segundo evento. Como paliativo, se dejó corriendo en forma permanente un Data Collector Set propio (`CPUWatch`, ver Acciones propuestas #1), esta vez correctamente ubicado en `SFCG-DB01`.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | El total de CPU sumado de todas las sesiones SQL Server nunca superó ~6.3% de la capacidad de 16 núcleos en ninguna captura de la ventana 12:00-18:30 GMT, incluyendo los tres intervalos exactos de los picos reportados | Alto — contradice que la causa de los picos 2 y 3 sea una consulta/sesión de SQL Server |
| H2 | SPID 114 (login `sfsqlusr`, host `SFCG-TO-01`, TaskOperatorService) ejecutó el mismo job de sincronización de `CustomerPointsLog` visto como SPID 151 en GITIN-1669, esta vez solapando con el pico 1 reportado (12:06-13:06 GMT) | Bajo — consumo crónico conocido, correlación con pico 1 plausible pero no confirmada |
| H3 | Los SPIDs de sistema (<50) no aparecen en `PNSSRL_AuditSysprocesses` durante ninguno de los tres picos — mismo punto ciego documentado como H2 en GITIN-1669, la acción propuesta de extender la captura no fue implementada | Medio — punto ciego real en el diagnóstico, sigue sin resolverse desde GITIN-1669 |
| H4 | No se registró bloqueo (`blocked=0`) en toda la ventana investigada | Informativo |
| H5 | Las 36 combinaciones de host/login/programa conectadas durante la ventana corresponden todas a infraestructura conocida — no se identificó ninguna conexión no autorizada | Informativo |
| H6 | No hubo reinicio de `SFCG-DB01` cerca de la ventana investigada (último reinicio: 2026-07-15) — verificado vía conexión SQL (`sys.dm_os_sys_info`), no depende del host RDP | Informativo |
| H7 | En `SFCG-DB01`, ninguna instalación de actualización de Windows se solapa con los tres picos — las instalaciones (mayormente Security Intelligence de Defender) están dispersas todo el día sin patrón fijo, la más cercana a 28 min de un pico | Informativo |
| H8 | En `SFCG-DB01`, Windows Defender no ejecutó ningún escaneo (rápido o completo) ni detectó ninguna amenaza durante la ventana investigada — el último escaneo rápido finalizó a las 02:08 GMT, ~11 horas antes del primer pico; el escaneo completo nunca se ejecutó en este equipo | Informativo |
| H9 | En `SFCG-TO-01` (no `SFCG-DB01`): cluster de tareas programadas (`ReportUpdateCustomer`, `ReportErrorSurveyNoResponse`, `NotSamplesSurveyActivated`, `Promotion Vigency Advisor B/C`) se ejecuta entre las 12:00 y 12:30 GMT, dentro de la ventana de SPID 114 — solo 2 de las 5 son diarias, el resto semanal/bisemanal/mensual. Refuerza que el pico 1 es rutina de inicio de jornada, no algo disparado por el load test | Informativo |
| H10 | `SFCG-DB01` no tiene la carpeta `\SmartFran\` (exclusiva de `SFCG-TO-01`) — solo tareas genéricas de Windows, ninguna dentro de los 15 minutos de los picos 2 y 3. Se descarta la clase completa de tareas programadas como causa, verificado en ambos servidores | Alto — descarta otra hipótesis pendiente para los picos 2 y 3 |
| H11 | Los dos Data Collector Set preexistentes del Azure Guest Agent (`GAEvents`, `RTEvents`) están presentes tanto en `SFCG-TO-01` como en `SFCG-DB01` — verificados en ambos, mismo tracing de bajo overhead (heartbeats, telemetría), sin señal de ráfaga aguda en ninguno de los dos hosts — se descartan como causa | Informativo |
| H12 | En `SFCG-TO-01`: la tarea `Check_list_SF` (verifica que TaskOperatorService esté corriendo) se ejecuta cada 5 minutos anclada en :00 — cae exactamente en :15 y :45 de cada hora, coincidiendo al minuto con los picos 2 y 3. Sin embargo, su costo de CPU es local a `SFCG-TO-01`, no a `SFCG-DB01` — no explica directamente el gráfico de CPU del motor de base de datos salvo que genere carga pesada en el motor SQL, ya descartado (H1) | Bajo — coincidencia de horario notable pero sin mecanismo causal directo confirmado hacia `SFCG-DB01` |

## Recursos afectados

| Recurso | Observación |
|---|---|
| `SFCG-DB01` (VM de base de datos, `PNSSRL` / `SmartFran.Solution.SmartLoyalty`) | Picos de "CPU User Time" hasta 92.69% observados a nivel de sistema operativo (Zabbix legado); sin correlato confirmado en la actividad de sesiones SQL Server ni en los logs de sistema operativo revisados para los picos 2 y 3 |
| SPID 114 / login `sfsqlusr` / host `SFCG-TO-01` (TaskOperatorService) | Consumidor crónico de CPU (job diario de sincronización de `CustomerPointsLog`); correlación plausible con el pico 1, no confirmada |

## Queries ejecutadas

Ver `20260803_cpu_peaks_loadtest_scripts.sql` y `20260803_cpu_peaks_loadtest_scripts.ps1` (este último ejecutado directamente en `SFCG-DB01`, fuera del alcance de `PNSSRL`).

| # | Query/Comando | Propósito |
|---|---|---|
| Q1 | Chequeo de disponibilidad de datos (12:00-18:30 GMT) | Confirmar cobertura de captura para la ventana completa |
| Q2 | Delta de CPU por SPID entre snapshots consecutivos | Identificar sesiones con consumo de CPU elevado |
| Q3 | Total de CPU de todas las sesiones por snapshot, normalizado a capacidad de 16 núcleos | Comparar el total agregado contra los tres picos reportados |
| Q4 | Chequeo de bloqueo (`blocked <> 0`) en toda la ventana | Descartar cadena de bloqueo como causa |
| Q5 | SPIDs de sistema (<50) durante los tres picos confirmados | Buscar actividad de hilos internos de SQL Server — resultado vacío (punto ciego, ver H3) |
| Q6 | Hosts/logins distintos conectados durante la ventana completa | Descartar conexión no autorizada como factor |
| Q7 | `sys.dm_os_sys_info` — hora de arranque de SQL Server | Descartar reinicio del servidor cerca de la ventana |
| P1 | Historial de instalación de Windows Update (`Microsoft.Update.Session` COM API) — **ejecutado en `SFCG-TO-01` por error** | Hallazgos sobre `SFCG-TO-01`, no aplican a `SFCG-DB01` (ver Nota de corrección) |
| P2 | Log operacional de Windows Defender + `Get-MpComputerStatus` + `Get-MpThreatDetection` — **ejecutado en `SFCG-TO-01` por error** | Hallazgos sobre `SFCG-TO-01`, no aplican a `SFCG-DB01` |
| P3a | `logman query` — listado de todos los Data Collector Set — **ejecutado en `SFCG-TO-01` por error** | Identificó `GAEvents`/`RTEvents`, re-verificados en `SFCG-DB01` (P4c) |
| P3b/d | `logman query GAEvents -ets` / `RTEvents -ets` — **ejecutado en `SFCG-TO-01` por error** | Ver P4c para la verificación correcta en `SFCG-DB01` |
| P3e | `Get-Service` filtrado por Azure/Guest Agent/SqlIaaS — **ejecutado en `SFCG-TO-01` por error** | Confirmó presencia de SQL IaaS Extension / Azure Guest Agent en `SFCG-TO-01` |
| P3c/f | `LastRunTime` de tareas programadas (y detalle de `\SmartFran\`) — **ejecutado en `SFCG-TO-01` por error** | Identificó el cluster del pico 1 (H9) y `Check_list_SF` (H12) — válido para `SFCG-TO-01`, ver `docs/infrastructure.md` |
| P3g | Triggers de `CustomerPointLog_to_BlobStorage` — **ejecutado en `SFCG-TO-01` por error** | Confirmó horario fijo (11:10/18:00 GMT) en `SFCG-TO-01` |
| P4a | Windows Update install history, re-ejecutado en `SFCG-DB01` (hostname confirmado por comando) | Descartar instalación de actualización como causa de los picos 2 y 3 (H7) |
| P4b | Log operacional de Defender + `Get-MpComputerStatus` + `Get-MpThreatDetection`, re-ejecutado en `SFCG-DB01` | Descartar Windows Defender como causa de los picos 2 y 3 (H8) |
| P4c | `logman query GAEvents -ets` / `RTEvents -ets`, re-ejecutado en `SFCG-DB01` | Descartar los colectores preexistentes como causa, esta vez en el host correcto (H11) |
| P4d | `LastRunTime` de todas las tareas programadas del servidor, re-ejecutado en `SFCG-DB01` | Confirmar ausencia de `\SmartFran\` y descartar tareas genéricas de Windows como causa (H10) |

## Acciones propuestas

1. **(SRE) Implementado 2026-08-03 (recreado correctamente en `SFCG-DB01` tras corrección de host):** Data Collector Set `CPUWatch` configurado y corriendo en `SFCG-DB01` vía `logman` (buffer circular, contadores `\Process(*)\% Processor Time` + `\ID Process` y `\Processor(*)\% User Time` / `\% Privileged Time` por núcleo, intervalo de 15s) — queda corriendo de forma permanente, no depende de que alguien esté mirando en el momento exacto del pico. Resuelve además si "CPU User Time" es realmente el máximo por núcleo (teoría de Causa raíz) o el promedio de la VM. **Pendiente:** complementar con Resource Monitor abierto en vivo durante la ventana horaria del próximo load test de Grido (coordinando el horario con anticipación), como cruce manual y para ver actividad de disco/red por proceso. Esta acción ya fue propuesta en GITIN-1669 (con alcance más genérico) y no se había implementado antes de este segundo evento.
2. (SRE) Evaluar si la tabla de captura `PNSSRL_AuditSysprocesses` puede extenderse para incluir SPIDs de sistema (<50) — punto ciego confirmado por segunda vez consecutiva (GITIN-1669 y este evento).
3. (SRE) Evaluar migrar o consolidar el monitoreo de CPU de la VM de base de datos a la instancia Zabbix vigente (`sf-monitoreo.smartfran.com`) — sigue pendiente desde GITIN-1669, la instancia legada continúa sin API y dificulta la correlación.
4. (SRE) Si se confirma la teoría de agregación `[max]` por núcleo vs. `[avg]` de VM completa para los ítems "CPU User Time" / "CPU Utilization" (requiere acceso a la configuración de ítems en la instancia Zabbix legada), documentar la semántica exacta en `docs/infrastructure.md` para evitar reinterpretar los gráficos en futuras investigaciones.
5. (SRE) Reprogramar el cluster de tareas identificado en H9 (`ReportUpdateCustomer`, `ReportErrorSurveyNoResponse`, `NotSamplesSurveyActivated`, `Promotion Vigency Advisor B`, `Promotion Vigency Advisor C`), actualmente concentrado entre las 12:00 y las 12:30 GMT — distribuirlas en horarios distintos entre sí y fuera de la ventana de actividad de SPID 114 (12:06-13:06 GMT), reduciendo la concentración de carga al inicio de la jornada. *(Horario destino a definir.)*

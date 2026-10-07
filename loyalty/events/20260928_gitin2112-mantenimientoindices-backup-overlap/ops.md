**Tags:** SmartLoyalty, DBA, Mantenimiento

## Resumen

El 2026-09-26 (sábado), el job `PNSSRL_MantenimientoIndices` (barrido diario de mantenimiento de índices sobre `SmartFran.Solution.SmartLoyalty`, `SFCG-DB01`) falló luego de 15m14s de ejecución, deteniéndose en medio del recorrido por las tablas del esquema `Mbr`. Se investigaron tres hipótesis concretas de contención (backup de log concurrente, solapamiento con el job complementario `PNSSRL_MantenimientoIndices_CustomerPointsLog`, y carga general de fondo incluyendo `DBCC CHECKDB`); las tres fueron descartadas al compararlas contra la ejecución exitosa del lunes 2026-09-28, que presentó condiciones iguales o más severas — de hecho, con mayor carga concurrente total — sin fallar. La causa raíz puntual no quedó confirmada; se interpreta como un evento transitorio aislado. Se aplicó un mitigador de reintentos sobre el paso que falló.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2112](https://smartit-ar.atlassian.net/browse/GITIN-2112) |
| Caso | Falla de `PNSSRL_MantenimientoIndices`, 2026-09-26 |
| Base de datos | `SmartFran.Solution.SmartLoyalty` / `PNSSRL` (`SFCG-DB01`) |
| Severidad | Medio |
| Detectado | 2026-09-28 (revisión retrospectiva del fin de semana) |
| Resuelto | Sí, 2026-09-29 — sin causa raíz puntual confirmada (evento transitorio aislado); mitigador de reintentos aplicado y verificado; primera corrida programada tras el mitigador (martes 2026-09-29) exitosa, sin necesidad de reintento |
| Responsable | SRE SmartLoyalty |

## Causa raíz

**No confirmada.** Se descartaron tres hipótesis concretas de contención, todas mediante comparación directa contra la ejecución exitosa del lunes 2026-09-28 bajo condiciones equivalentes o más severas: (1) un backup de log inusualmente grande (7.56 GB) coincidente con una advertencia "Long Sync IO" en el error log, cinco minutos antes de la falla — descartada porque el lunes se registraron backups de log aún mayores (hasta 15.4 GB) durante la misma ventana del job, sin falla, y la misma advertencia "Long Sync IO" apareció tres veces el lunes sin ningún impacto; (2) solapamiento con el job complementario `PNSSRL_MantenimientoIndices_CustomerPointsLog` (rebuild de partición sobre `Sml.CustomerPointsLog`), que arrancó apenas 14 segundos antes de la falla del sábado — descartada porque el lunes ambos jobs se solaparon por 49 minutos completos sin falla; (3) carga general de fondo — se descubrió que `DBCC CHECKDB` (`PNSSRL_CapturaCheckDB`) corrió el lunes (3h0m44s, 07:00-10:02 GMT, solapando gran parte de la corrida exitosa) pero **no estuvo programado el sábado en absoluto** — es decir, el lunes tuvo objetivamente más carga concurrente total (CHECKDB + backups más grandes + mismo solapamiento del job complementario) y aun así no falló. No se encontró ningún patrón de "más carga → más probabilidad de falla" en los datos; si acaso, la tendencia es la opuesta. El mensaje de error propio del paso fallido (`sysjobhistory.message`) quedó truncado por el límite de almacenamiento de SQL Server Agent (~3200 bytes), sin exponer la excepción real. Sin una causa reproducible identificada, la falla del sábado se interpreta como un evento transitorio aislado.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | `PNSSRL_MantenimientoIndices` falló el 2026-09-26 06:00-06:15:14 ART (09:00-09:15:14 GMT), deteniéndose en el paso 1 tras procesar parcialmente el esquema `Mbr`. Mensaje de error truncado, sin excepción real disponible. | Medio |
| H2 | Programación del job (`sysschedules`, `schedule_id=23`) confirmada: semanal, Lunes/Martes/Jueves/Sábado, 06:00 ART — la ausencia de corridas viernes/domingo es por diseño, no una falla silenciosa. | Informativo |
| H3 | Hipótesis de contención por backup de log descartada — el lunes exitoso presentó backups de log más grandes (hasta 15.4 GB) durante la misma ventana sin falla. | Bajo (descartado) |
| H4 | Hipótesis de contención por solapamiento con `PNSSRL_MantenimientoIndices_CustomerPointsLog` descartada — el lunes exitoso presentó 49 minutos de solapamiento completo entre ambos jobs sin falla, muy por encima de los 14 segundos previos a la falla del sábado. | Bajo (descartado) |
| H5 | Los jobs de mantenimiento rutinario (`Operaciones_MaintenancePlan_Backups.Backup_Log`, `PNSSRL_CapturaQuery`, `PNSSRL - Agent maintenance SysprocessesHistory`) no aparecen en el historial del sábado en la misma ventana — no están programados los sábados. No relacionado con la falla, solo confirma menor actividad de fondo ese día, no mayor. | Informativo |
| H6 | La advertencia "Long Sync IO" (encontrada en el error log del sábado, coincidente con la falla) también apareció tres veces el lunes (09:50:04 GMT) sin ningún impacto — confirmado como ruido rutinario bajo carga, no diagnóstico de nada relacionado con fallas. | Bajo (descartado como indicador) |
| H7 | `DBCC CHECKDB` (`PNSSRL_CapturaCheckDB`) corrió el lunes 07:00-10:02 GMT (3h0m44s, exitoso, 0 errores), solapando gran parte de la corrida exitosa de `PNSSRL_MantenimientoIndices` — pero no estuvo programado el sábado en absoluto. El lunes tuvo objetivamente más carga concurrente total que el sábado y aun así no falló. | Informativo (descarta la hipótesis de carga general) |
| H8 | El Paso 2 de `PNSSRL_MantenimientoIndices` dispara directamente el job `Operaciones_MaintenancePlan_Backups.Backup_Log` al finalizar el Paso 1 — no es un job independiente que solo coincide en horario, es parte del diseño de `PNSSRL_MantenimientoIndices`. Confirmado en la corrida exitosa del martes 2026-09-29. No explica la falla del sábado (el Paso 2 corre después de que el Paso 1 termina, y la falla del sábado ocurrió dentro del Paso 1), pero es contexto estructural nuevo no documentado antes. | Informativo |

## Recursos afectados

| Componente | Impacto |
|---|---|
| `PNSSRL_MantenimientoIndices` (SQL Agent job) | Ejecución del 2026-09-26 falló tras 15m14s; corrida completa recuperada recién el 2026-09-28 (próxima fecha programada) |
| `SmartFran.Solution.SmartLoyalty` (esquema `Mbr` y posteriores) | Mantenimiento de índices/estadísticas incompleto entre el sábado fallido y el lunes exitoso — ventana de ~2 días con estadísticas potencialmente desactualizadas en las tablas no alcanzadas |

## Horarios de ejecución de `PNSSRL_MantenimientoIndices` — 3 corridas

| Fecha | ART / GMT | Duración | Resultado | Reintentos usados |
|---|---|---|---|---|
| Sábado 2026-09-26 | 06:00:00 / 09:00:00 | 15m14s | **Falló** (sin mitigador aplicado aún) | N/A |
| Lunes 2026-09-28 | 06:00:00 / 09:00:00 | 2h14m37s | Exitoso | N/A (mitigador aplicado ese mismo día, después de esta corrida) |
| Martes 2026-09-29 | 06:00:00 / 09:00:00 | 37m22s | Exitoso | 0 (no fue necesario) |

La duración varía fuertemente entre corridas exitosas (2h14m37s lunes vs. 37m22s martes) — confirma que la duración por sí sola no es un indicador confiable de salud de este job.

**Hallazgo adicional, martes:** el Paso 2 del propio job dispara `Operaciones_MaintenancePlan_Backups.Backup_Log` (no es un job independiente solapado por casualidad, sino parte del diseño del job) — ver H8.

### Historial de corridas — OK/NOK, desde el reschedule de GITIN-2060 (aplicado 2026-09-22)

| Tarea | Fecha | Estado | Duración |
|---|---|---|---|
| Backup (`Operaciones_MaintenancePlan_Backups.Backup_FULL`) | Mié 2026-09-23 | OK | 8m17s |
| Backup (`Operaciones_MaintenancePlan_Backups.Backup_FULL`) | Vie 2026-09-25 | OK | 9m46s |
| Backup (`Operaciones_MaintenancePlan_Backups.Backup_FULL`) | Dom 2026-09-27 | OK | 8m15s |
| Index (`PNSSRL_MantenimientoIndices`) | Jue 2026-09-24 | OK | 33m23s |
| Index (`PNSSRL_MantenimientoIndices`) | Sáb 2026-09-26 | **NOK** | 15m14s |
| Index (`PNSSRL_MantenimientoIndices`) | Lun 2026-09-28 | OK | 2h14m37s |
| Index (`PNSSRL_MantenimientoIndices`) | Mar 2026-09-29 | OK | 37m22s |
| Pointslog (`PNSSRL_MantenimientoIndices_CustomerPointsLog`) | Jue 2026-09-24 | OK | 3m30s |
| Pointslog (`PNSSRL_MantenimientoIndices_CustomerPointsLog`) | Sáb 2026-09-26 | OK | 45m57s |
| Pointslog (`PNSSRL_MantenimientoIndices_CustomerPointsLog`) | Lun 2026-09-28 | OK | 49m2s |
| Pointslog (`PNSSRL_MantenimientoIndices_CustomerPointsLog`) | Mar 2026-09-29 | OK | 46m38s |

Único NOK del período: `PNSSRL_MantenimientoIndices` el sábado 2026-09-26 (ver Causa raíz). Los tres jobs corrieron sin overlap de horario conflictivo en todas las demás fechas verificadas desde el reschedule.

### Otros jobs — sábado (falla) vs. lunes (éxito)

| Job | Sábado 2026-09-26 (ART / GMT) | Duración | Lunes 2026-09-28 (ART / GMT) | Duración |
|---|---|---|---|---|
| `Actualiza_DWGrido_CustomerPointsBalance` | 05:30:00 / 08:30:00 | 9m28s | 05:30:00 / 08:30:00 | 10m41s |
| `PNSSRL_MantenimientoIndices_CustomerPointsLog` | 06:15:00 / 09:15:00 | 45m57s (Exitoso) | 06:15:00 / 09:15:00 | 49m2s (Exitoso) |
| `Operaciones_MaintenancePlan_Backups.Backup_Log` | No programado ese día | — | Cada ~10 min, 05:30-06:20+ ART | 1-7s c/u |
| `PNSSRL_CapturaQuery` | No programado ese día | — | Cada ~10 min, 05:30-06:20+ ART | 0-1s, excepto 06:20 ART: 44m2s |
| `PNSSRL - Agent maintenance SysprocessesHistory` | No programado ese día | — | Cada ~5 min | ~0s c/u |

## Consultas ejecutadas

Todas las queries de esta investigación están documentadas en `scripts.sql`, dentro de esta misma carpeta de evento. Resultados reales de cada una persistidos en `data/`.

| # | Query | Propósito |
|---|---|---|
| Q1 | `PNSSRL_DetallesEjecucionTablasModulos`, fin de semana completo | Detalle de ejecución del barrido de índices |
| Q2 | `sysjobhistory` (nivel job), 25-28/09 | Confirmar qué días corrió/falló el job |
| Q3 | `sysjobhistory` (nivel paso) + `sysschedules` | Mensaje de error del paso fallido y programación real del job |
| Q4 | `xp_readerrorlog`, ventana de falla del sábado | Buscar la excepción real detrás de la falla |
| Q5 | `msdb.dbo.backupset`, fin de semana completo | Tipo/tamaño/duración de backups (parcialmente persistido, ver `investigation.md`) |
| Q6 | `msdb.dbo.backupset`, ventana de la corrida exitosa del lunes | Comparación de tamaños de backup contra el sábado |
| Q7 | `sp_update_jobstep` — reintentos sobre el paso 1 | Mitigador aplicado |
| Q8 | `sysjobsteps` (verificación) | Confirmar que Q7 se aplicó efectivamente |
| Q9 | `xp_readerrorlog`, ventana de la corrida del lunes | Confirmar si "Long Sync IO" es indicativo de algo o ruido rutinario — descartado como indicador (H6); reveló `DBCC CHECKDB` corriendo, no detectado antes |
| Q10 | `sysjobhistory`, todos los jobs, ventana 08:30-09:20 GMT, sábado y lunes | Detectar otros jobs solapados además de los ya identificados |
| Q11 | `sysjobhistory`, `PNSSRL_CapturaCheckDB`, sin restricción de horario, ambos días | Confirmar si CHECKDB corrió el sábado — no corrió (H7) |
| Q12 | `sysjobhistory`, `PNSSRL_MantenimientoIndices`, martes 2026-09-29 | Confirmar la primera corrida programada tras aplicar el mitigador |
| Q13 | `sysjobhistory`, los 3 jobs (`step_id=0`), fechas restantes desde el reschedule de GITIN-2060 | Completar el historial OK/NOK Backup/Index/Pointslog desde 2026-09-22 |

## Acciones propuestas

1. **(SRE) Completado.** Reintentos agregados al paso 1 de `PNSSRL_MantenimientoIndices` (`retry_attempts=2, retry_interval=5`) — mitigador de resiliencia, no corrige la causa raíz (no confirmada), pero evita que una falla transitoria puntual aborte todo el barrido de ~2 horas sin reintento. Aplicado y verificado directamente contra `sysjobsteps`.
2. **(SRE) Completado.** Corrida programada del martes 2026-09-29 monitoreada — exitosa, sin necesidad de reintento (0 reintentos usados). No confirma que el mitigador funcione ante una recurrencia real (no hubo falla que lo activara), solo que no hubo regresión.
3. (Dev/DBA) Si la falla vuelve a ocurrir, capturar el error real antes de que el límite de truncado de `sysjobhistory` lo pierda — considerar una sesión de Extended Events activa durante la ventana del job como captura permanente. Queda como seguimiento abierto, no bloquea el cierre de este ticket.

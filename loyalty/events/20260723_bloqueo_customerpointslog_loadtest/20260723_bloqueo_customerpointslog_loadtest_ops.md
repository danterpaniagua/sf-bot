# [TAREA] Bloqueo en CustomerPointsLog durante load test de MobileAppService

## Resumen

El equipo de App Grido ejecutó un load test sobre MobileAppService desde las 08:30 (UTC-3), lo que coincidió con picos de ~5.000 batch requests reportados por Zabbix sobre `PNSSRL`. La investigación en vivo encontró una cadena de bloqueo real: SPID 87 (un `ALTER INDEX REBUILD` de mantenimiento legítimo) bloqueado por SPID 93, una transacción abandonada/sin confirmar bajo el login `zabbix`. Se terminó SPID 93, lo que resolvió la causa raíz del bloqueo. El síntoma residual (SPID 87 continuando su rebuild, generando CPU y bloqueando acceso a la tabla) se dejó en curso por decisión del usuario, en vez de terminarlo — al cierre de la sesión de trabajo, la CPU y las métricas de Zabbix ya habían vuelto a niveles normales.

## Tabla resumen

| Campo | Valor |
|---|---|
| Sistema | SmartLoyalty SQL Server (`PNSSRL`) — `SFCG-DB01` |
| Severidad | Alta |
| Detectado | 2026-07-23 08:30 (UTC-3) |
| Resuelto | Causa raíz (SPID 93) terminada el mismo día; síntoma residual (SPID 87) normalizado sin intervención adicional — confirmado con tiempos de espera de Zabbix de las últimas 3h (avg 45ms / max 5.746ms en locks), órdenes de magnitud por debajo de los valores del incidente |
| Responsable | Dante Paniagua |

## Causa raíz

Una transacción sin confirmar bajo el login `zabbix` (SPID 93) — consistente con una sesión de SSMS dejada abierta, no con un proceso de monitoreo activo — retuvo un lock que bloqueó a SPID 87 con `wait_type LCK_M_SCH_M` (bloqueo de modificación de esquema). SPID 87 era un `ALTER INDEX REBUILD` de mantenimiento programado (`PNSSRL_MantenimientoModulos`), que por ser un rebuild offline retiene `Sch-M` durante toda su duración. El load test de MobileAppService, iniciado a las 08:30, generó tráfico adicional contra la misma tabla mientras el bloqueo ya estaba activo, amplificando el síntoma reportado por Zabbix (picos de batch requests, tiempos de espera elevados).

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Cadena de bloqueo confirmada en vivo vía DMVs: SPID 87 bloqueado por SPID 93, `wait_type LCK_M_SCH_M` | Alto — bloqueo activo durante el load test |
| H2 | SPID 93 identificado como transacción abandonada/sin commit bajo el login `zabbix` — no correspondía a un proceso de monitoreo esperado | Alto — causa raíz del bloqueo |
| H3 | Tras terminar SPID 93 (`KILL 93`), SPID 87 continuó ejecutándose — es un `ALTER INDEX REBUILD` legítimo, no una consecuencia del incidente | Informativo |
| H4 | Los rebuilds offline retienen `Sch-M` durante toda su duración y no reportan `percent_complete` confiable — no fue posible estimar con precisión cuánto le faltaba mientras estuvo en curso | Medio |
| H5 | Zabbix reportó tiempos de espera elevados (avg 8.272 / max 30.078 en ventana de 6h); una métrica posterior (ventana desde las 14:09) mostró avg 55.683 — se confirmó que correspondía al mismo SPID 87 en ejecución, no a un evento nuevo | Informativo |
| H6 | Se evaluó terminar 7 sesiones adicionales bajo el login `zabbix` — se decidió esperar a que terminara el rebuild en curso en vez de intervenir sobre ellas | Bajo |
| H7 | Al cierre de la sesión de trabajo, la CPU había bajado a ~14% y Zabbix reportaba valores normalizados (min 0,59 / avg 4,4 / max 14). **Confirmado con datos de las 3h siguientes:** tiempos de espera de Locks avg 45ms / max 5.746ms y Waits avg 7ms / max 1.244ms — órdenes de magnitud por debajo de los valores del incidente (avg 8.272-55.683ms). SPID 87 terminó y la situación está normalizada | Informativo — confirmado |

## Recursos afectados

| Recurso | Observación |
|---|---|
| `PNSSRL` / tabla relacionada a `CustomerPointsLog` | Bloqueada mientras SPID 93 retuvo el lock y luego mientras SPID 87 completaba el rebuild |
| SPID 93 (login `zabbix`) | Terminado (`KILL 93`) — causa raíz del bloqueo |
| SPID 87 (`ALTER INDEX REBUILD`, `PNSSRL_MantenimientoModulos`) | Dejado en curso por decisión del usuario — no se confirmó su finalización |
| MobileAppService (load test, App Grido) | Generó el tráfico que expuso el bloqueo, no lo causó |

## Queries ejecutadas

Ver `20260723_bloqueo_customerpointslog_loadtest_scripts.sql`.

| # | Query | Propósito |
|---|---|---|
| Q1 | Chequeo de disponibilidad de datos en `PNSSRL_AuditSysprocesses` | Confirmar cobertura de captura para la ventana del incidente |
| Q2 | Delta de CPU por SPID entre snapshots consecutivos | Identificar sesiones con consumo de CPU elevado en la ventana |
| Q3 | DMVs en vivo (`sys.dm_exec_requests`, `sys.dm_exec_sessions`, `sys.dm_tran_locks`) | Confirmar la cadena de bloqueo real (H1, H2) |
| Q4 | `KILL 93` | Terminar la transacción abandonada — causa raíz |
| Q5 | Verificación post-`KILL`: estado de SPID 87 y métricas de CPU/espera | Confirmar que el bloqueo se liberó y seguimiento del rebuild residual (H3-H7) |

## Acciones propuestas

1. Investigar por qué quedó abierta una sesión bajo el login `zabbix` con una transacción sin confirmar — origen probable de bloqueos similares a futuro.
2. ~~Confirmar si el `ALTER INDEX REBUILD` (SPID 87 / `PNSSRL_MantenimientoModulos`) terminó exitosamente.~~ Confirmado — tiempos de espera normalizados en las 3h posteriores (H7).
3. Evaluar coordinar el horario de los load tests de MobileAppService con la ventana de mantenimiento de índices, para evitar que ambos coincidan de nuevo.
4. Definir una alerta o un límite de tiempo para sesiones idle/sin commit bajo el login `zabbix`, para detectar transacciones abandonadas antes de que bloqueen mantenimiento programado.

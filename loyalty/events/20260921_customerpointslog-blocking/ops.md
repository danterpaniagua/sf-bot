# GITIN-2076 — Bloqueo activo sobre Sml.CustomerPointsLog

**Tags:** SmartLoyalty, CustomerPointsLog, PNSSRL_MantenimientoIndices, PROD, SRE

## Resumen

El 2026-09-21, durante la verificación de una ventana segura para otro ticket (GITIN-2074), se detectó una cadena de bloqueo activa sobre `Sml.CustomerPointsLog` en `SFCG-DB01`. El job `PNSSRL_MantenimientoIndices` (rebuild diario a las 06:15 UTC) llevaba ~4h10m esperando un lock de modificación de esquema, sin haber empezado el rebuild (0% de progreso), bloqueado por un job de sincronización ETL conocido por su throughput crónicamente lento. Detrás de ese job en cola quedaron 12 sesiones reales de aplicación (MobileAppService, sitio de club, un healthcheck de Zabbix), con tiempos de espera crecientes. Se canceló el job de rebuild (`KILL`) para liberar la cola — confirmado que la cadena de bloqueo se despejó por completo. **No resuelve la causa de fondo**: este es el tercer episodio del mismo problema ya diagnosticado en GITIN-1981, cuyas dos tareas de remediación (GITIN-2060, GITIN-2061) siguen sin aplicarse meses después.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2076](https://smartit-ar.atlassian.net/browse/GITIN-2076) |
| Sistema | SmartLoyalty SQL Server (`SmartFran.Solution.SmartLoyalty`) — `SFCG-DB01` |
| Severidad | Alta — bloqueo real de tráfico de aplicación en producción (MobileAppService, sitio de club), tercera recurrencia de un problema ya conocido |
| Detectado | 2026-09-21, ~10:22 GMT (hallazgo incidental durante verificación de otra tarea) |
| Resuelto | Parcial — síntoma inmediato despejado (`KILL` a las ~10:30 GMT); causa de fondo (GITIN-2060/2061) sigue sin aplicarse |
| Responsable | Dante Paniagua |

## Causa raíz

No fue una única sesión trabada — un patrón de inanición de cola de locks. El job ETL (`Etl.EtlOperationConfig.Id=6`, sync hacia `dbo.CustomerPointsLog`) reconfirma locks de estabilidad de esquema lote tras lote durante su ejecución (~1h+), sin dejar nunca un hueco suficiente para que `PNSSRL_MantenimientoIndices` obtenga el lock de modificación de esquema que necesita para su `ALTER INDEX REBUILD`. Ese job, en cola, bloquea a su vez a toda solicitud de lectura posterior sobre la misma tabla, por la política estándar de equidad de colas de locks — de ahí el bloqueo en cascada hacia MobileAppService y el sitio de club.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | `PNSSRL_MantenimientoIndices` (job confirmado vía `msdb.dbo.sysjobs`) en cola por `LCK_M_SCH_M` durante ~4h10m, 0% de progreso, bloqueado por SPID 80 | Alto |
| H2 | SPID 80 (`SFCG-TO-01`) es el job ETL conocido (`Etl.EtlOperationConfig.Id=6`) con throughput crónicamente lento — causa raíz documentada en `events/20260715_cpu_spikes/` (predicado `OR` no sargable + `COUNT(*) OVER()`), remediación nunca aplicada | Alto |
| H3 | 12 sesiones reales de aplicación en cola detrás del rebuild: MobileAppService (`SFCG-MOBI-01`), sitio de club (`SFCG-CLUB-01`), healthcheck de Zabbix | Alto |
| H4 | Recurrencia confirmada: mismo job identificado en GITIN-1981 (06:15 UTC, hasta 38 sesiones bloqueadas), ya recurrido una vez el 2026-09-14 (`events/20260914_taskoperator_mktcampaign537_errors/`). Este es el tercer episodio — GITIN-2060 (reprogramación a 08:00 UTC) y GITIN-2061 (rebuild acotado a la partición actual) siguen sin aplicarse | Alto |
| H5 | Modo de falla nuevo respecto a los dos episodios previos: antes el job bloqueaba a otros por su propia duración larga; hoy el job mismo quedó bloqueado por otro proceso, sin avanzar nada | Medio |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| `SFCG-DB01` | Host de base de datos donde ocurrió la cadena de bloqueo |
| `Sml.CustomerPointsLog` (`SmartFran.Solution.SmartLoyalty`) | Tabla bloqueada |
| `SFCG-MOBI-01` (MobileAppService) | 8 sesiones en cola |
| `SFCG-CLUB-01` (sitio de club) | 4 sesiones en cola |
| `sfzabbix` | 1 healthcheck en cola |

## Comandos ejecutados

| # | Propósito |
|---|---|
| — | Chequeo de carga en vivo (`sys.dm_exec_requests`) previo a otro ticket — detectó el bloqueo incidentalmente |
| — | Chequeo de locks sobre `Sml.CustomerPointsLog` (`sys.dm_tran_locks`) |
| — | Identificación de cadena de bloqueo completa (`blocking_session_id`) |
| — | Identificación del nombre del job vía `msdb.dbo.sysjobs` a partir del GUID |
| — | `KILL 93` — cancelación del job de rebuild en cola |
| — | Recheck de la cadena de bloqueo — confirmó que se despejó por completo |

Resultados completos persistidos en `data/01_blocking_chain.txt` (copia; el archivo original quedó guardado por error en `cloud/events/20260920_sales-oom-48h/data/q13.txt`).

## Acciones propuestas

1. **(SRE) Completado** — `KILL 93` para liberar la cola de sesiones bloqueadas. Ejecutado 2026-09-21 ~10:30 GMT, confirmado exitoso.
2. **(SRE) Pendiente** — Confirmar si la corrida cancelada de `PNSSRL_MantenimientoIndices` necesita re-ejecutarse manualmente o si el plan de mantenimiento se recupera solo en su próximo horario (06:15 UTC).
3. **(SRE) Pendiente, propio** — GITIN-2060 (reprogramar `PNSSRL_MantenimientoIndices` a 08:00 UTC) y GITIN-2061 (rebuild acotado a partición actual) son la remediación real de este problema recurrente, no lo aplicado hoy. Este es el tercer incidente atribuible a que ambas tareas siguen abiertas meses después de GITIN-1981 — sumadas a `loyalty/todo/TODO.md`.
4. **(Dev) Pendiente** — Corregir la consulta del job ETL (`Etl.EtlOperationConfig.Id=6`): predicado `OR` no sargable y `COUNT(*) OVER()` innecesario, documentado en `events/20260715_cpu_spikes/`.

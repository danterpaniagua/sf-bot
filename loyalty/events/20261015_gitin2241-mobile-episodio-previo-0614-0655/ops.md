# GITIN-2241 — [SML] Mobile: Episodio 20261015 6AM

**Tags:** `SmartLoyalty`, `MobileAppService`, `SRE`, `PROD`

## Qué pasó

- PediGrido informó, junto con la caída de MobileAppService del 15-10 ([GITIN-2238](https://smartit-ar.atlassian.net/browse/GITIN-2238)), un episodio más breve ese mismo día entre las 06:14 y las 06:55 (hora de Argentina) que se recuperó solo, y sugirió que podría tratarse de un problema recurrente o intermitente.
- Según Operaciones, ese horario se usa para tareas de mantenimiento.

## Resumen

El escenario web de Zabbix `[PROD] MobileApp` registró el episodio: el paso de inicio de sesión no respondió en 55 controles seguidos, de las 06:15:27 a las 06:56:29 (hora de Argentina), con tiempos de espera de 15 segundos, mientras el paso de healthcheck respondía con normalidad; por eso la sonda del balanceador no registró caída. En esos mismos minutos corrió el trabajo del Agente de SQL Server `PNSSRL_MantenimientoIndices_CustomerPointsLog` (06:15:00 a 06:57:01), que reconstruye un índice de la tabla `Sml.CustomerPointsLog`; las capturas de la base muestran de 22 a 41 sesiones por captura esperando un bloqueo de esa tabla entre las 06:16 y las 06:56, y las fallas terminaron al terminar el trabajo. En la semana revisada hubo fallas en los cuatro días con ejecución programada y ninguna en los tres días sin ella. Todavía no se comprobó que el inicio de sesión espere sobre esa tabla ni qué sostenía el bloqueo, por lo que la causa no está confirmada.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2241](https://smartit-ar.atlassian.net/browse/GITIN-2241) (relacionado con [GITIN-2238](https://smartit-ar.atlassian.net/browse/GITIN-2238)) |
| ID alerta | NA |
| Sistema | MobileAppService (`SFCG-MOBI-01`, `SFCG-MOBI-02`), balanceador `SFCG-MOBI-LB`, base de datos `SmartFran.Solution.SmartLoyalty` en `SFCG-DB01`, Zabbix |
| Severidad | Por definir |
| Detectado | 2026-10-15 (informado por PediGrido) |
| Resuelto | No: causa sin confirmar; sin cambios aplicados |
| Responsable | SRE |

## Causa raíz

NA

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | El episodio existe en nuestro monitoreo. En `web.test.fail["[PROD] MobileApp"]` (un control cada 30 s) hubo 55 controles seguidos con el paso 2 (`POST Account/Login`) fallido, de las 09:15:27 a las 09:56:29 UTC (06:15:27 a 06:56:29 -03:00); el control anterior (09:14:41) y el siguiente (09:57:01) pasaron. Cada falla fue un tiempo de espera de 15 s con 0 bytes recibidos. El paso 1 (`healthcheck`) respondió 200 en todos esos controles, con 0,52 a 1,55 s (promedio 0,57 s dentro del episodio, 0,55 s fuera). | Alto |
| H2 | La sonda de salud del balanceador (`DipAvailability` de `192.168.50.111`, `SFCG-MOBI-01`, y `VipAvailability`) marcó 100 % en los 120 minutos de 08:30 a 10:30 UTC; la de `SFCG-MOBI-02` no tiene muestras en toda esa ventana. La sonda mide el healthcheck, no la latencia de las consultas, por lo que no ve este episodio. | Medio |
| H3 | `SFCG-MOBI-01` no reinició su app pool en el episodio (uptime continuo; su único reinicio del día fue hacia las 05:00 UTC). `SFCG-MOBI-02` no tiene datos en Zabbix de 04:00:17 a 11:50:17 UTC ni métricas de plataforma de Azure (disponibilidad y CPU) de 04:05 a 11:45 UTC: según Operaciones tiene un apagado y encendido programados y estaba apagado. En el episodio respondía un solo servidor (no se leyó el registro de peticiones del balanceador ni de IIS). | Medio |
| H4 | El trabajo `PNSSRL_MantenimientoIndices_CustomerPointsLog` corrió el 2026-10-15 de 09:15:00 a 09:57:01 GMT (paso `RebuildIXCustomerIdActivePartition`, con la consulta `ALTER INDEX [IX_CustomerId] ON [Sml].[CustomerPointsLog] REBUILD PARTITION = @PartitionNumber;`). Las capturas de `PNSSRL_AuditSysprocesses`, cada 5 minutos, muestran sesiones bloqueadas solo de las 09:16:00 a las 09:56:00 (nada a las 09:11 ni a las 10:01); en ocho de las nueve capturas la sesión del `REBUILD` (spid 91) estaba suspendida esperando un bloqueo de modificación de esquema (`LCK_M_SCH_M`) retenido por la sesión 109, y de 22 a 41 sesiones por captura esperaban un bloqueo de estabilidad de esquema (`LCK_M_SCH_S`) con consultas de conteo y suma sobre `Sml.CustomerPointsLog`. La última falla (09:56:29) y el primer control correcto (09:57:01) coinciden con el fin del trabajo. | Alto |
| H5 | La duración del trabajo en las corridas leídas fue de 48 min 42 s (12-10), 38 min 37 s (13-10) y 42 min 01 s (15-10); la documentación interna indica unos 4 minutos para una corrida posterior a la primera. El trabajo se ejecutó con éxito en los tres casos. | Medio |
| H6 | Recurrencia: `web.test.fail` falló los días 10-10 (5 controles, 09:15:37 a 09:18:39 UTC), 12-10 (37, 09:15:44 a 10:03:01), 13-10 (5, 09:50:18 a 09:53:20) y 15-10 (55), todos con ejecución programada (lunes, martes, jueves y sábado según la documentación; lunes, martes y jueves confirmados en el historial del Agente), y no falló los días 09, 11 y 14-10 (sin ejecución; el 14-10 confirmado en el historial). La cantidad de controles fallidos varía mucho con duraciones parecidas del trabajo y no se explica. | Medio |

## Acciones Tomadas (hora UTC)

| # | Hora | Acción |
|---|---|---|
| 1 | 2026-10-16 15:08 | Se agregó el ticket al nombre de la carpeta del evento. |
| 2 | 2026-10-16 15:11 | Lectura de la disponibilidad de la sonda del balanceador, 08:30 a 10:30 UTC del 15-10, por servidor y de la entrada pública (solo lectura). |
| 3 | 2026-10-16 15:16 a 15:29 | Lecturas de Zabbix (escenario `[PROD] MobileApp` y sus pasos, items del pool de aplicaciones de ambos servidores, historial de uptime de todo el 15-10, recurrencia del 09 al 15-10) y de Azure (métricas de plataforma de ambas VMs); solo lectura. |
| 4 | 2026-10-16 15:27 | Tres consultas de solo lectura en `SFCG-DB01`: historial de los trabajos de mantenimiento de índices del 12 al 16-10, sesiones del Agente y sesiones bloqueadas del 15-10 de 09:00 a 10:05 GMT. |

No se aplicaron cambios en Zabbix, Azure, el balanceador, los servidores ni la base de datos.

## Recursos afectados

| Componente | Estado |
|---|---|
| MobileAppService (inicio de sesión) | Fallas entre las 09:15:27 y las 09:56:29 UTC del 15-10 |
| Trabajo `PNSSRL_MantenimientoIndices_CustomerPointsLog` | Sin cambios |
| `SFCG-MOBI-02` | Apagado programado de 04:05 a 11:45 UTC (según Operaciones y métricas de Azure); sin cambios |

## Acciones propuestas

| # | Responsable | Acción | Estado |
|---|---|---|---|
| 1 | SRE | Consultar qué hacía la sesión 109 (la que mantenía bloqueada a la reconstrucción) y cuáles eran las consultas que esperaban en la ventana, incluida si había consultas del inicio de sesión de Mobile (dos consultas de solo lectura sobre las capturas de la base). | Pendiente |
| 2 | SRE | Corregir la duración documentada del trabajo según las corridas reales (H5). | Pendiente |
| 3 | SRE | Si la consulta 1 confirma que el inicio de sesión espera sobre esa tabla, evaluar con quien administra la tarea cambiar su horario o su duración. | Por decidir |
| 4 | SRE | Evaluar una alerta que mire el paso de inicio de sesión del escenario `[PROD] MobileApp` (las alertas de [GITIN-2239](https://smartit-ar.atlassian.net/browse/GITIN-2239) miran el paso de healthcheck, que respondía con normalidad en el episodio). | Por decidir |

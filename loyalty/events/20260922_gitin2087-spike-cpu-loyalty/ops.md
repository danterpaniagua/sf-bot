# GITIN-2087 — [SML] Spike CPU Loyalty

**Tags:** SmartLoyalty, WebService, PROD, SRE, CPU

## Resumen

Pico de CPU en el servidor de base de datos de SmartLoyalty (`SFCG-DB01`) la noche del 2026-09-21 (~20:00 GMT / 17:00 UTC-3), originado en los tres servidores de WebService v1/SOAP (`SFCG-WEBS-01/02/03`). Es la recurrencia de un hallazgo detectado en mayo de 2026 con el mismo mecanismo, que en ese momento quedó señalado para un ticket propio nunca abierto — la recurrencia actual es más amplia, afectando a los tres hosts en vez de uno solo. El mismo patrón volvió a repetirse la noche siguiente (2026-09-22), confirmando que no es un evento aislado.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2087](https://smartit-ar.atlassian.net/browse/GITIN-2087) |
| Sistema | SmartLoyalty SQL Server (`SFCG-DB01`) — hosts origen `SFCG-WEBS-01/02/03` (WebService v1/SOAP) |
| Severidad | Media — pico de CPU confirmado, sin caída de servicio reportada |
| Detectado | 2026-09-21, ~20:00 GMT |
| Resuelto | Pendiente — causa raíz identificada a nivel de mecanismo y de código; corrección pendiente de Dev |
| Responsable | Dante Paniagua |

## Causa raíz

`ASYNC_NETWORK_IO` domina el consumo de CPU en la ventana analizada (~101.717 de CPU combinado entre los tres hosts) — este wait type indica que la aplicación WebService no lee las filas del result set con suficiente velocidad, manteniendo la sesión SQL activa más tiempo del necesario.

Dos queries LINQ/Entity Framework generan el patrón: un full-fetch de `Sml.Promotion` (todas las promociones activas, sin paginado real) y un full-fetch de `Sml.Article`/`Sml.Product` (`ForSale=1`). La primera se rastreó hasta `PromotionService.QueryPromotionApply`, que acepta parámetros de paginado reales pero los omite deliberadamente cuando se invoca con `preFiltredPromotions=false` (tradeoff de performance documentado en un ticket histórico, `SML-6455`), haciendo en su lugar un filtro adicional en memoria (`AddMultipleFilterInfo`) sobre el resultado completo sin paginar. Ese código es compartido entre WebService v1 (OnPrem, los hosts afectados) y WebServiceV2 (SmartCloud).

Se validó contra datos reales de producción que activar el paginado (`OFFSET`/`FETCH`) por sí solo no reduce el costo de lectura en el servidor — misma cantidad de logical reads con y sin paginado, ya que `ROW_NUMBER() OVER (...)` requiere materializar y ordenar todo el conjunto antes de poder aplicar la ventana. Esto significa que activar el paginado ayudaría al tiempo en `ASYNC_NETWORK_IO` (menos filas transmitidas al cliente) pero no a la causa raíz del consumo de CPU en `SFCG-DB01`; la corrección real requiere mover el filtro adicional (`AddMultipleFilterInfo`) a la consulta SQL en lugar de aplicarlo como un segundo paso en memoria.

`AddMultipleFilterInfo` es, en el código real, una cadena de resolución de franquicia/sucursal/región contra la tabla de soporte `SmlSupp.PromotionBranchOffice` (~25 millones de filas) — no una validación simple. El método se invoca desde 14 puntos distintos de `PromotionService.cs`; identificar cuál de esos 14 orígenes generó específicamente la traza de este pico queda como trabajo de Dev antes de implementar la corrección.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | `ASYNC_NETWORK_IO` confirmado como wait type dominante en la ventana 19:30-20:30 GMT del 2026-09-21, en los tres hosts de WebService — total ~101.717 de CPU, muy por encima del segundo contribuyente (`SOS_WORK_DISPATCHER`, 26.053) | Alto |
| H2 | Recurrencia de un hallazgo detectado en mayo de 2026 — mismo mecanismo, esa vez limitado a `SFCG-WEBS-03` únicamente. Ese hallazgo recomendaba explícitamente abrir un ticket separado, nunca abierto hasta ahora | Alto (recurrencia de un hallazgo sin resolver hace 4 meses) |
| H3 | El alcance de esta recurrencia es más amplio que el original — afecta los tres hosts (`WEBS-01`, `02`, `03`), no solo uno. Se repitió con la misma firma la noche siguiente (2026-09-22) | Medio |
| H4 | Las dos queries responsables (`Sml.Promotion`, `Sml.Article`/`Sml.Product`) hacen full-fetch sin paginado real por diseño de `PromotionService.QueryPromotionApply` — confirmado a nivel de código | Alto |
| H5 | Activar el paginado real por sí solo no reduce el costo de lectura en `SFCG-DB01` (validado contra datos reales: misma cantidad de logical reads con y sin paginado) — la corrección requiere reestructurar el filtro adicional a nivel de SQL, no solo paginar | Medio |
| H6 | La tabla de soporte `SmlSupp.PromotionBranchOffice`, parte del mecanismo de filtrado adicional, tiene ~25 millones de filas — cualquier consulta poco selectiva contra ella sería costosa por sí sola | Medio |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| `SFCG-WEBS-01`/`02`/`03` | Hosts de WebService (v1, SOAP) — origen de las sesiones con `ASYNC_NETWORK_IO` |
| `SFCG-DB01` | Servidor SQL donde se registra el consumo de CPU |
| `Sml.Promotion`, `Sml.Article`/`Sml.Product` | Tablas consultadas por las queries responsables |
| `SmlSupp.PromotionBranchOffice` | Tabla de soporte del mecanismo de filtrado adicional (~25M filas) |

## Comandos ejecutados

Ver `scripts.sql` en este evento.

| # | Query | Propósito |
|---|---|---|
| Q1 | `SELECT` sobre `PNSSRL_AuditSysprocesses`, filtrado por `lastwaittype LIKE '%ASYNC_NETWORK%'` | Confirmar la recurrencia del patrón de mayo |
| Q2 | `SELECT` agregado (`GROUP BY hostname, lastwaittype, status`) | Cuantificar el CPU total por wait type y host |
| Q3 | `SELECT TOP 1 ValidToDate` sobre `Sml.Promotion` | Obtener un valor de parámetro real para las pruebas siguientes |
| Q4 | Query responsable, sin paginado (baseline) | Medir logical reads/tiempo del comportamiento actual en producción |
| Q5 | Misma query, con paginado real (`OFFSET`/`FETCH`) | Validar si el paginado por sí solo reduce el costo — resultado: no |
| Q6 | `SELECT COUNT(*)` sobre `SmlSupp.PromotionBranchOffice` | Confirmar la escala real de la tabla de soporte del filtro adicional |

## Acciones propuestas

1. **(SRE)** — Completado. Se aisló la(s) query(s) LINQ exacta(s) detrás de las sesiones `ASYNC_NETWORK_IO`: full-fetch de `Sml.Promotion` y de `Sml.Article`/`Sml.Product`, confirmadas en los tres hosts.
2. **(SRE)** — Completado. Se validó contra datos reales de producción que el paginado por sí solo no reduce el costo de lectura en el servidor.
3. **(Dev) Pendiente, prioridad alta** — Confirmar cuál de los 14 puntos de invocación de `AddMultipleFilterInfo` en `PromotionService.cs` generó la traza de este pico, trazar `GetPromotionIdListFiltered` (el resolutor real contra `SmlSupp.PromotionBranchOffice`), y mover ese filtro a la consulta SQL en lugar de aplicarlo en memoria sobre un resultado sin paginar.
4. **(SRE) Pendiente** — Confirmar si este patrón es recurrente/diario revisando otras fechas recientes, más allá de las dos noches consecutivas ya observadas.

## Hallazgos secundarios

Ninguno.

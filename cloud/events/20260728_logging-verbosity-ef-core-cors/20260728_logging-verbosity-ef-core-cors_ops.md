# [TAREA] Verbosidad de logging (EF Core / CORS / pipeline MVC) en Business y Sales — reducir antes de escalar

## Resumen

El análisis del volumen actual real de Graylog (índices más recientes de OpenSearch, `business__6` y `sales__2`) encontró que el driver dominante del volumen de logs de Business y Sales no es lógica de negocio, sino logging de framework/ORM dejado en nivel debug en producción: `Microsoft.EntityFrameworkCore` en Business y el pipeline de ASP.NET Core MVC + middleware de CORS en ambas apps. Esto es independiente de cualquier decisión de infraestructura o plataforma (Datadog/Graylog) ya evaluada en `20260723_franchise-scaling-costs`, y reducirlo achica proporcionalmente el volumen en cada uno de los escenarios de escala (1.000/2.000/2.600 franquicias) ya cotizados en ese ticket.

## Tabla resumen

| Campo | Valor |
|---|---|
| Sistema | Graylog (OpenSearch, `sfcloud-monitoreo`) — apps Business y Sales, proyecto `cloud-graylog` |
| Severidad | Media |
| Detectado | 2026-07-28 |
| Resuelto | Pendiente — requiere cambio de configuración de logging en ambas apps (fuera del alcance de este ticket ejecutarlo) |
| Responsable | Dante Paniagua |

## Causa raíz

`Microsoft.EntityFrameworkCore` está logueado a nivel `Debug` en producción en Business — cada `DbCommand`, apertura/cierre de conexión e inicialización/disposición de `DbContext` genera su propia línea de log. En Sales (y también presente en Business), el middleware de CORS y el pipeline de ASP.NET Core MVC (`Start processing HTTP request` → `Route matched` → `Executing action method` → `Executing endpoint` → `Executed endpoint` → `Executing OkObjectResult`) multiplican cada request real en ~6 líneas de log independientes a nivel Info/Debug.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Business: el top-20 de valores de `resultDescription` representa el 33,2% de su volumen actual (4.374.288 / 13.165.348 docs) — 19 de los 20 son trazas de debug de Entity Framework Core (`dbug: Microsoft.EntityFrameworkCore.*`, ciclo de vida de `DbCommand`, apertura/cierre de conexión, init/dispose de `BusinessContext`) | Alto — volumen evitable con un cambio de configuración, no de infraestructura |
| H2 | Sales: el top-20 de `resultDescription` representa el 34,6% de su volumen actual (1.489.355 / 4.301.202 docs). De eso: 406.094 sin `resultDescription` (logs HTTP crudos, legítimo), 193.002 es `CORS policy execution successful` (ruido de middleware), el resto es el pipeline de ASP.NET Core MVC repetido ~6 veces por request real (`SaleController.CreateAsync`/`CloseAsync`, ~46.500-46.600 llamadas reales cada uno) | Alto — mismo patrón de volumen evitable por configuración |
| H3 | La cola larga (66,8% del volumen de Business, 65,4% del de Sales, fuera del top-20) no fue analizada en detalle — es razonable esperar que contenga más del mismo patrón EF Core/pipeline MVC a menor frecuencia por mensaje individual, pero esto no está confirmado | Medio — podría implicar que el % evitable real es mayor al 33-35% ya confirmado |
| H4 | La teoría de "Business tiene `AppServiceConsoleLogs` deshabilitado por drift manual" (documentada en `cloud-graylog/CLAUDE.md`, 2026-07-02) queda descartada por datos reales — Console Logs es hoy la categoría más grande de Business (8.459.208 docs, 48,4% del volumen combinado actual de Business+Sales), no está ausente | Informativo — descarta una explicación ya usada en `20260723_franchise-scaling-costs` para la brecha de volumen 12,1M/día medido vs. ~27,5M/día esperado; esa brecha vuelve a estar sin explicar |
| H5 | Sales no tiene ningún documento de categoría `AppServiceConsoleLogs` en su índice actual — hallazgo nuevo, no señalado antes en ningún ticket previo | Bajo — a confirmar si es por diseño (Sales no emite consola) o por configuración de Diagnostic Setting |

## Recursos afectados

| Recurso | Observación |
|---|---|
| `SmartFran-Cloud-Business-PRO` (Business API, .NET 7.0) | Logging de `Microsoft.EntityFrameworkCore` en nivel Debug en producción (H1) |
| `SmartFran-Cloud-Sales-PRO` (Sales, Windows) | Logging de CORS y pipeline ASP.NET Core MVC en nivel Info/Debug en producción (H2) |

## Comandos ejecutados

Ver `20260728_logging-verbosity-ef-core-cors_scripts.sh`.

| # | Comando | Propósito |
|---|---|---|
| Q1 | Muestra de un doc (`sales__0`) | Confirmar nombres reales de campos (`name`, `category`) |
| Q2 | Agregación `name.keyword`/`category.keyword` | Intento fallido — campos no tienen subcampo `.keyword` |
| Q3 | `_cat/indices` | Confirmar índices reales vigentes (rotación desde la medición del 2026-07-23) |
| Q4 | Mapping de `business__6` | Confirmar que `name`/`category` son `keyword` puro |
| Q5 | Agregación real por app + categoría (`business__6`, `sales__2`) | Ranking de impacto actual por categoría (H4, H5) |
| Q6 | Mapping repetido (corrección de sintaxis `grep`) | — |
| Q7 | Agregación por `operationName` | Descartado como campo útil — valor genérico de Azure |
| Q8 | Mapping de `message` (text) y `resultDescription` (keyword) | Identificar campo correcto para mensajes exactos |
| Q9 | Agregación final por `resultDescription`, con marcador `missing` | Base de H1, H2, H3 |

## Acciones propuestas

1. (Dev) Cambiar el nivel de logging de `Microsoft.EntityFrameworkCore` de `Debug` a `Warning` en la configuración de producción de Business (`appsettings.json` → `Logging:LogLevel`).
2. (Dev) Cambiar el nivel de logging de `Microsoft.AspNetCore.*` (CORS, Mvc, Routing, Hosting) de `Information`/`Debug` a `Warning` en la configuración de producción de Sales (y confirmar si aplica también a Business).
3. (SRE) Una vez aplicado el cambio, re-medir el volumen real de ingesta (misma consulta Q5/Q9 de este ticket) para cuantificar la reducción real lograda contra la estimación de 30-50%.
4. (SRE) Confirmar con Dev si Sales tiene `AppServiceConsoleLogs` habilitado en su Diagnostic Setting — hoy no aparece ningún documento de esa categoría (H5), y no está confirmado si es esperado.
5. (SRE) Ampliar el análisis de `resultDescription` a la cola larga (66,8%/65,4% del volumen no cubierto por el top-20) para confirmar si el mismo patrón EF Core/pipeline MVC se repite a menor escala por mensaje individual (H3).
6. (SRE) Una vez confirmada la reducción real de volumen, recalcular las proyecciones de costo de `20260723_franchise-scaling-costs` (Insights, Graylog self-hosted, Datadog) a 1.000/2.000/2.600 franquicias — todas están construidas sobre el volumen actual, y esta reducción aplica proporcionalmente a cada escenario.

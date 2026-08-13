# Eventos — 20260728_logging-verbosity-ef-core-cors

## 2026-07-28 — Apertura: análisis de impacto actual de logs en Graylog

He confirmado los nombres reales de campos en un documento de muestra de `sales__0` (Q1) y he intentado una primera agregación por `name.keyword`/`category.keyword` (Q2), que devolvió 0 buckets pese a más de 10.000 hits. He listado los índices reales vigentes (Q3) y he encontrado que `business__1` (usado en la medición del 2026-07-23) ya rotó/fue purgado, con `business__6` y `sales__2` como los índices más recientes. He verificado el mapping real (Q4) y confirmado que `name`/`category` son campos `keyword` puro, sin subcampo `.keyword` — corregí la agregación para usar los campos directos.

## 2026-07-28 — Agregación por app + categoría: hallazgo que descarta el drift documentado

He ejecutado la agregación real por app + categoría sobre los índices más recientes (Q5). Encontré que `AppServiceConsoleLogs` de Business está muy activo (8.459.208 docs, la categoría más grande de la app) — esto contradice la nota de `cloud-graylog/CLAUDE.md` (2026-07-02) sobre un drift que lo tenía deshabilitado. También encontré, sin haber sido señalado antes, que Sales no tiene ningún documento de esa categoría en su índice actual.

## 2026-07-28 — Descarte de `operationName` como campo útil

He agregado por `operationName` (Q7) y encontré que es un tag genérico de Azure (`Microsoft.Web/sites/log`) que coincide numéricamente con la categoría dominante de cada app, sin aportar granularidad real de mensaje.

## 2026-07-28 — Identificación de `resultDescription` como campo correcto para mensajes

Verifiqué el mapping de `message` (Q8) y confirmé que es un campo `text` analizado, no agregable como string exacto. Encontré que `resultDescription` es `keyword` y es el campo correcto para este análisis.

## 2026-07-28 — Hallazgo principal: logging de EF Core y pipeline MVC en nivel debug

Ejecuté la agregación final por `resultDescription` con marcador `missing` (Q9). Encontré que el top-20 de mensajes de Business (33,2% de su volumen actual) es casi enteramente logging de debug de Entity Framework Core, y que el top-20 de Sales (34,6% de su volumen) incluye ruido de CORS y el pipeline de ASP.NET Core MVC repetido ~6 veces por request real. Documenté esto como H1-H3 y abrí este ticket, separado de `20260723_franchise-scaling-costs`, ya que es un hallazgo de configuración de aplicación, no de infraestructura ni de elección de plataforma.

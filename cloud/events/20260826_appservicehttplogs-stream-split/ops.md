# GITIN-1940 — Separar AppServiceHTTPLogs en Streams/Index Sets dedicados por app

**Tags:** `SmartCloud`, `Graylog`, `SRE`

## Resumen

Tras habilitar `AppServiceHTTPLogs` para las 8 apps PROD (GITIN-1937, 2026-08-25), esta categoría — un registro por cada request HTTP, en cada app — quedaba mezclada en el mismo stream compartido `PROD-{App}-AppServicePlan` junto con `AppServiceConsoleLogs`/`AppServiceAppLogs`, sin ninguna separación por categoría, dominando el volumen del stream. La promoción de campos útiles para esta categoría (`StatusCode`/`Path`/`Method`/`ElapsedMilliseconds`/`ClientIP`, GITIN-1940, 2026-08-26) hizo evidente que valía la pena resolver esta mezcla en vez de convivir con ella.

Se crea un Stream + Index Set dedicado por app para `AppServiceHTTPLogs`, y se agrega una regla de exclusión al stream existente para que el volumen efectivamente se retire de ahí, no se duplique. Se ejecuta primero un piloto (Admin), se confirma end-to-end, y se replica el mismo patrón para las 7 apps restantes. Se pre-configura además el equivalente en DEV, aunque esa categoría todavía no está habilitada ahí.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-1940](https://smartit-ar.atlassian.net/browse/GITIN-1940) (mismo ticket que la promoción de campos en `cloud/events/20260825_sales-caerequest-408-timeout/`) |
| ID alerta | N/A — trabajo planificado, no disparado por alerta |
| Sistema | SmartFran Cloud — Graylog (Streams / Index Sets) |
| Severidad | Media |
| Detectado | 2026-08-26 |
| Resuelto | 2026-08-26 — 8 apps PROD completadas; DEV pre-configurado, no activo |
| Responsable | Dante Paniagua, SRE |

## Causa raíz

Los streams existentes (`PROD-{App}-AppServicePlan`) matchean únicamente por el campo `name`, sin ninguna regla sobre `category` — por diseño, todas las categorías de Diagnostic Settings de una app (Console/App/HTTP logs) caen en el mismo stream. Al habilitarse `AppServiceHTTPLogs` (un registro por request HTTP, mucho más frecuente que los logs de aplicación) sin una regla que lo separara, el volumen de esta categoría termina dominando el stream compartido de cada app.

## Campos promovidos (GITIN-1940)

Mismo ticket, trabajo previo del 2026-08-25/26 (`cloud/events/20260825_sales-caerequest-408-timeout/`) — motivado por los `408` de `Sales WsFeAr/CaeRequest` sin ningún campo estructurado sobre el cual filtrar. No es parte de este split de streams, pero es la razón por la que el volumen de `AppServiceHTTPLogs` pasó a valer la pena separar: antes de esto, la categoría solo era consultable por texto completo.

Se promovieron 5 campos a nivel superior en Graylog, desde dos formas de origen distintas — la línea de hosting-diagnostics "Request finished" de ASP.NET Core (siempre presente, cualquier app) y la propia categoría `AppServiceHTTPLogs` de Azure (acceso IIS, Event Hub apps Windows):

| Campo | Clave de origen | Tipo | Confirmado en vivo |
|---|---|---|---|
| `StatusCode` | `Properties.StatusCode` (Request-finished) o `properties.ScStatus` (AppServiceHTTPLogs, cast String→Integer) | Integer | Sí — 2026-08-26 |
| `Path` | `Properties.Path` (Request-finished) o `properties.CsUriStem` (AppServiceHTTPLogs) | String | Sí — 2026-08-26 |
| `Method` | `Properties.Method` (Request-finished) o `properties.CsMethod` (AppServiceHTTPLogs) | String | Sí — 2026-08-26 |
| `ElapsedMilliseconds` | `Properties.ElapsedMilliseconds` (Request-finished, Float) o `properties.TimeTaken` (AppServiceHTTPLogs, cast Integer→Float) | Float | Sí — 2026-08-26 |
| `ClientIP` | `properties.CIp` (solo AppServiceHTTPLogs — la línea Request-finished no tiene equivalente) | String | Sí — 2026-08-26 |

Confirmación: `StatusCode`/`Path`/`Method`/`ElapsedMilliseconds` verificados contra muestras reales de Sales-PRO/-DEV/-PRO-stg2 (788 matches/1h, rama Request-finished); los 5 campos, incluyendo `ClientIP`, re-confirmados contra muestras reales de Admin-PRO/Platform-PRO/Orders-PRO (5770 matches/1h, rama `AppServiceHTTPLogs`) — ambas ramas de origen verificadas funcionando, incluyendo los casts `ScStatus`→Integer y `TimeTaken`→Float. Alcance de `AppServiceHTTPLogs` sin confirmar para Pos — no chequeado si Pos emite esta categoría en absoluto. Referencia completa: `cloud-graylog/docs/graylog-log-fields.md`.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | `AppServiceHTTPLogs` mezclado sin separación en el mismo stream que Console/App logs para las 8 apps PROD, dominando volumen. Resuelto con este ticket. | Medio |
| H2 | Primer intento de `index_prefix` (`{app}_http_`) rechazado por Graylog por colisión con el prefix existente `{app}_`. Corregido a `http_{app}_`. | Bajo |
| H3 | La regla de exclusión sobre el stream existente solo se re-confirmó en vivo para Admin (el piloto) — para las 7 apps del batch se asume el mismo comportamiento por tener la regla idéntica, sin verificación independiente. | Bajo |
| H4 | DEV no emite actualmente `AppServiceHTTPLogs` (Diagnostic Settings de DEV solo envían `AppServiceConsoleLogs`) — el stream/index set de DEV quedó pre-configurado pero sin poder verificarse en vivo. | Bajo |
| H5 | `cloud-graylog/docs/architecture.md` (diagrama de Streams) no refleja el nuevo split por categoría — queda desactualizado. | Bajo |

## Recursos afectados

| App | Index Set nuevo | Stream nuevo | Stream existente (regla de exclusión agregada) |
|---|---|---|---|
| Admin | `SFC-Admin-prod-http` (`6a8edb274814bcaed323ea2a`) | `PROD-Admin-AppServiceHTTPLogs` (`6a8edbc94814bcaed323ede1`) | `PROD-Admin-AppServicePlan` (`6a7cb18f4814bcaed30a8791`) |
| Business | `6a8edd544814bcaed323f88c` | `6a8edd554814bcaed323f891` | `6a452a0d18ebc987b1ca003a` |
| Catalog | `6a8edd584814bcaed323f8bf` | `6a8edd584814bcaed323f8c8` | `6a7cb1924814bcaed30a87aa` |
| Orders | `6a8edd5b4814bcaed323f8f4` | `6a8edd5c4814bcaed323f903` | `6a7cb1944814bcaed30a87bf` |
| Person | `6a8edd5e4814bcaed323f92d` | `6a8edd5f4814bcaed323f934` | `6a7cb18d4814bcaed30a8774` |
| Platform | `6a8edd624814bcaed323f95d` | `6a8edd624814bcaed323f968` | `6a7cb18a4814bcaed30a875a` |
| Pos | `6a8edd654814bcaed323f99b` | `6a8edd664814bcaed323f9a8` | `6a7cb1884814bcaed30a8744` |
| Sales | `6a8edd694814bcaed323f9cd` | `6a8edd694814bcaed323f9d6` | `6a47c5c94b3c88a95fad7a7a` |
| DEV (todas) | `DEV-http` | `DEV-AppServiceHTTPLogs` (`6a8ee1ff4814bcaed324085a`) | `DEV` (`6a7a1b8a34e7b9a985f43cbc`) |

Todos los 9 index sets nuevos (8 PROD + DEV) quedan con retención `hot_only`, `P7D`/`P9D`.

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | pilot-create-index-set-and-stream (Admin) | Crear index set + stream nuevos para el piloto |
| C2 | pilot-add-rules-and-resume (Admin) | Agregar reglas `name`/`category` y reanudar el stream nuevo |
| C3 | ⚠️ pilot-exclude-from-existing-stream (Admin) | Agregar regla de exclusión al stream existente |
| C4 | ⚠️ batch-create-and-exclude-remaining-7-apps | Replicar el patrón del piloto para Business/Catalog/Orders/Person/Platform/Pos/Sales |
| C5 | verification-queries | Guía de verificación de inflow/exclusión (solo ejecutada para Admin) |

Detalle completo en `scripts.sh`. La configuración de DEV y el ajuste de retención (`P7D`/`P9D`) en los 8 index sets PROD se ejecutaron en la misma sesión pero no quedaron guardados como comandos reproducibles en `scripts.sh` — ver Hallazgos secundarios.

## Acciones propuestas

1. **Completado (2026-08-26)** — Piloto en Admin: stream + index set nuevos creados, regla de exclusión agregada al stream existente, inflow del stream nuevo confirmado en vivo (209 mensajes/10min).
2. **Completado (2026-08-26)** — Batch replicado sin fallos para las 7 apps restantes.
3. **Completado (2026-08-26)** — DEV pre-configurado (stream + index set), a la espera de que se habilite `AppServiceHTTPLogs` en Diagnostic Settings de DEV.
4. **Completado (2026-08-26)** — Retención de los 8 index sets PROD ajustada de `P30D`/`P40D` a `P7D`/`P9D`.
5. Re-confirmar en vivo, para al menos 2-3 apps del batch, que la regla de exclusión efectivamente detuvo el flujo de `AppServiceHTTPLogs` hacia el stream viejo (H3) — solo se verificó para Admin.
6. Actualizar el diagrama de Streams en `cloud-graylog/docs/architecture.md` para reflejar el split por categoría (H5).
7. Cuando se habilite `AppServiceHTTPLogs` para DEV, confirmar que el stream `DEV-AppServiceHTTPLogs` efectivamente empieza a recibir datos (H4).

## Hallazgos secundarios

- Durante la investigación de la convención de nombres existente, se ejecutaron 2 llamados `GET` de solo lectura directamente vía herramienta en lugar de entregarlos como bloques copy-paste — desvío de proceso sin impacto de datos, corregido en el resto de la sesión.
- El trabajo de pre-configuración de DEV y el ajuste de retención de los 8 index sets PROD no quedaron capturados como comandos reproducibles en `scripts.sh` — solo documentados narrativamente en `investigation.md`. Si se necesita repetir o auditar exactamente esos pasos, no hay un script listo para copiar-pegar; requeriría reconstruirlo desde la descripción en `investigation.md`.

# Formateo de logs directos GELF de Sales en Graylog — GITIN-1835

**Tags:** `SmartCloud`, `Graylog`, `Azure`, `PROD`

**Resumen:** los logs de errores de aplicación y advertencias de SignalR de Sales (SmartFran-Cloud-Sales-PRO) llegan a Graylog sin formatear: `message`/`full_message` muestran el string literal `"log entry"` en vez del contenido real, y `source` muestra el string sin resolver `"%{resource_path}"`. La causa es que estos mensajes ya no llegan por Event Hub/Diagnostic Settings (GITIN-1811 confirmó que esa categoría no está soportada para .NET en Windows), sino por un sink GELF directo de Serilog que salta ese pipeline por completo — el pipeline de Logstash que formatea el resto de los logs nunca los procesa. Además, estos mensajes no llegan al stream dedicado `PROD-Sales-AppServicePlan` (que muestra `0 msg/s` pese a tráfico activo de Sales), solo a Default Stream.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-1835 |
| ID alerta | — (detectado durante trabajo de diagnóstico, no por alerta automática) |
| Sistema | Graylog SmartCloud (`sfcloud-monitoreo.smartfran.com`) — App Service `SmartFran-Cloud-Sales-PRO` |
| Severidad | Media — no hay pérdida de datos, pero los logs de error de Sales son ilegibles/no buscables en Graylog |
| Detectado | 2026-08-14 |
| Resuelto | 2026-08-14 — confirmado contra tráfico real en producción (mensaje `4e564600-97f3-11f1-8f28-7c1e52beabec`, no solo simulador) |
| Responsable | Dante Paniagua (SRE) |

## Causa raíz

GITIN-1811 (cerrado 2026-08-11) confirmó que `AppServiceConsoleLogs`, la categoría de Diagnostic Settings que exporta logs de aplicación a Event Hub, no está soportada por Azure para aplicaciones .NET en Windows App Service — solo JavaSE/Tomcat. Sales y Pos son las dos únicas apps Windows de la flota. La resolución propuesta en ese ticket fue un sink GELF directo desde Serilog, saltando Diagnostic Settings/Event Hub por completo. Esa decisión de arquitectura ya está implementada: los mensajes de error/SignalR de Sales llegan hoy como JSON CLEF crudo de Serilog (`Timestamp`/`Level`/`MessageTemplate`/`Exception`/`Properties`), sin el envelope `records`/`resourceId` que Azure Diagnostic Settings agrega — por lo que nunca pasan por el pipeline de Logstash (`azure-eventhub-to-graylog.conf`) que construye `message`/`full_message`/`source` para el resto de los servicios. El literal `"%{resource_path}"` que aparece en `source` es, con alta probabilidad, sintaxis de ese mismo pipeline de Logstash copiada por error a la configuración del sink GELF de la aplicación — no tiene efecto fuera de Logstash. No confirmado a nivel de código de aplicación.

Por separado, el stream dedicado `PROD-Sales-AppServicePlan` rutea por coincidencia exacta del campo `name` (confirmado vía API) — campo que nunca existe en estos mensajes CLEF, por lo que quedan únicamente en Default Stream.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Los mensajes de error/SignalR de Sales llegan como JSON CLEF crudo de Serilog, sin el envelope de Azure Diagnostic Settings — confirmado comparándolos contra un mensaje `AppServiceHTTPLogs` bien formateado del mismo recurso. Causa raíz | Alto |
| H2 | `message`/`full_message` muestran el literal `"log entry"` — fallback hardcodeado del pipeline de Logstash para mensajes sin campos reconocidos, nunca alcanzado por estos mensajes ya que no pasan por ese pipeline | Alto |
| H3 | `source` muestra el literal sin resolver `"%{resource_path}"` — sintaxis propia de Logstash, sin significado fuera de ese contexto | Medio |
| H4 | El stream `PROD-Sales-AppServicePlan` no recibe ninguno de estos mensajes (`0 msg/s` confirmado pese a tráfico activo real de Sales) — su regla de ruteo coincide por el campo `name`, inexistente en estos mensajes | Medio |
| H5 | Origen del tag `"event_original_guard_skipped"` no identificado — no es generado por el pipeline de Logstash (sin `add_tag` en ese archivo); probablemente comportamiento propio de la librería del sink GELF de Serilog usada por la aplicación. No investigado en profundidad, fuera de alcance de este ticket | Bajo |

## Recursos afectados

- `SmartFran-Cloud-Sales-PRO` (App Service, Windows) — origen de los mensajes
- Graylog SmartCloud (`sfcloud-monitoreo.smartfran.com`) — Default Stream, stream `PROD-Sales-AppServicePlan`
- `cloud-graylog/docs/sales-direct-gelf-clef-format.rule` (repo `cloud-graylog`, no versionado en este monorepo) — fuente de las 6 reglas del fix

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | Consulta de reglas de stream (`PROD-Sales-AppServicePlan`) | Confirmar que el ruteo depende del campo `name` |
| C2 | Búsqueda de mensaje por `_id` vía Views Search API (3 pasos: crear/ejecutar/poll) | Obtener el JSON completo de un mensaje real para pruebas de simulación |
| C3 | Consulta de la fuente cruda de una regla vía API | Descartar caracteres ocultos ante un error opaco de la UI |
| C4 ⚠️ | Actualización de una regla vía API (`PUT`) | Bypass de un bug de la UI que devolvía `Bad Request` sin detalle en la actualización de reglas, para contenido ya confirmado válido |

Ver `scripts.sh` para el detalle completo. Las reglas y el pipeline en sí (el fix) se crearon manualmente en la UI de Graylog, no vía script — ver `cloud-graylog/docs/sales-direct-gelf-clef-format.rule` para la fuente completa.

## Acciones propuestas

1. **(SRE)** — Completado y confirmado contra tráfico real. Pipeline "GITIN-1835 Sales CLEF formatting" creado con 6 reglas en 2 stages, conectado a Default Stream: Stage 0 formatea `message`/`full_message`/`source` para cualquier mensaje CLEF directo (condicionado por `has_field("MessageTemplate")`, exclusivo de Serilog); Stage 1 agrega `name`/`resource_group`/`resource_path`/`subscription`/`type` y rutea explícitamente a `PROD-Sales-AppServicePlan` vía `route_to_stream()`, para la combinación confirmada `Properties_Service: "Sales"` / `Properties_Environment: "Production"`. Confirmado con un mensaje real de producción (`4e564600-97f3-11f1-8f28-7c1e52beabec`) presente en ambos streams (`PROD-Sales-AppServicePlan` y Default Stream) con todos los campos correctamente formateados.
2. **(Dev)** — Revisar la configuración del sink GELF directo de Serilog en `SmartFran.Cloud.Sales.API`: por qué el campo `Sender`/`source` se envía como el literal `"%{resource_path}"` (posible copia de la sintaxis de Logstash sin adaptar), y qué genera el tag `"event_original_guard_skipped"` en cada mensaje.
3. **(SRE)** — Si Pos u otro ambiente de Sales (DEV/STG/TEST) adopta el mismo sink GELF directo, extender el Stage 1 con una regla equivalente para esa combinación Service+Environment — confirmando el mapeo a un recurso Azure real antes de escribir la regla, no asumiendo el patrón de nombres.

## Segunda entrega: filtrado por severidad (`AppLevel`) en todo el pipeline de Event Hub

**Resumen:** el equipo de desarrollo pidió poder filtrar por severidad en Graylog para los servicios que sí llegan vía Event Hub (Business, Platform, Person, Admin, Catalog, Orders, y los ambientes DEV de Sales/Pos) — no solo Sales-PRO. Se encontró que el campo `level` propio de los registros `AppServiceAppLogs`/`AppServiceConsoleLogs` de Azure (string, ej. `"Error"`, `"Informational"`) se perdía silenciosamente: el pipeline de Logstash (`azure-eventhub-to-graylog.conf`) promueve ese campo al `level` interno de Logstash, pero la salida GELF requiere ahí un valor numérico de severidad — el string de Azure quedaba sobrescrito antes de llegar a Graylog, recuperable solo dentro del JSON crudo (`event_original`) o del blob `properties`, nunca como campo filtrable.

**Causa raíz:** `record.each { |k, v| event.set(k, v) }` en el segundo bloque `ruby` del pipeline promueve todas las claves del registro de Azure sin excepción, incluyendo `level`, que luego colisiona con el campo `level` numérico requerido por el output `gelf`.

**Fix aplicado y confirmado en vivo (2026-08-14):** captura de `record["level"]` en un nuevo campo `AppLevel`, agregada justo antes de la promoción genérica, sin tocar el `level` numérico de GELF. Desplegado en `/etc/logstash/conf.d/azure-eventhub-to-graylog.conf` (VM `sfcloud-monitoreo`), validado con `logstash -t` (`Configuration OK`) y reiniciado sin incidentes. Confirmado con tráfico real: 4.233 mensajes con `AppLevel` poblado en los primeros 30 minutos post-reinicio, en múltiples servicios (Person, Platform confirmados directamente).

**Hallazgo adicional durante el despliegue:** la copia versionada de `azure-eventhub-to-graylog.conf` en el repo `cloud-graylog` había quedado desactualizada respecto al archivo real en la VM — corregido trayendo el contenido real al repo. En el proceso se detectaron credenciales reales (SAS de Event Hub, clave de storage account) que habían quedado momentáneamente en el archivo del repo — reemplazadas por los placeholders originales antes de cualquier commit; el archivo no tiene historial de commits previo, por lo que no llegó a quedar expuesto en el historial de git.

## Hallazgos secundarios

- **Error real de producción encontrado incidentalmente durante la confirmación de este fix, fuera de alcance de este ticket:** el mensaje real usado para confirmar `route_to_stream()` (`4e564600-97f3-11f1-8f28-7c1e52beabec`, 2026-08-14 ~15:17 UTC) es en sí mismo un error genuino — `Sale.Close.StockMovement.Failed`, HTTP 403 al llamar al endpoint `StockCreate` de la API de Business durante el cierre de una venta (`SaleId: 3107f4b0-4d37-49b0-807d-7fa26fa297f7`). No investigado — ajeno al alcance de formateo de logs de este ticket, pero amerita seguimiento propio (posible problema de autorización M2M entre Sales y Business).

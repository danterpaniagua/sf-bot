# GITIN-1940 — Promover campos HTTP en Graylog y separar AppServiceHTTPLogs en Streams dedicados

**Tags:** `SmartCloud`, `Azure`, `Graylog`, `Obserbavilidad`, `PROD`, `SRE`

## Resumen

La línea de logging nativa de ASP.NET Core "Request finished" (hosting-diagnostics, no un helper de `SmartFranLogExtensions`) no tenía sus campos de HTTP — `StatusCode`, `Path`, `Method`, `ElapsedMilliseconds` — promovidos a nivel raíz en el pipeline de Logstash hacia Graylog. Esto impedía filtrar u obtener métricas por endpoint/código de estado de forma estructurada; el único camino era full-text search sobre `message`. El caso concreto que motivó el pedido: los 408 de `WsFeAr/CaeRequest` en Sales no podían aislarse ni contarse sin revisar mensaje por mensaje. Se promovieron los 4 campos, y se sumó `ClientIP` al alcance al identificarse que Azure expone la misma información (método, path, status, latencia, IP origen) también vía la categoría nativa `AppServiceHTTPLogs`, con nombres de campo distintos (`CsMethod`/`CsUriStem`/`ScStatus`/`TimeTaken`/`CIp`) — se unificaron ambos orígenes bajo los mismos 5 nombres de campo.

Una vez desplegado, quedó expuesto que `AppServiceHTTPLogs` (habilitada fleet-wide por GITIN-1937 el día anterior) es la categoría de mayor volumen dentro de los streams compartidos por app (`PROD-{App}-AppServicePlan`), mezclada sin distinción con `AppServiceConsoleLogs`/`AppServiceAppLogs`. Como trabajo de seguimiento bajo este mismo ticket, se creó un Stream + Index Set dedicado por app para `AppServiceHTTPLogs` (8 apps PROD), con retención reducida a 7 días, y se excluyó esa categoría de los streams originales para que el volumen deje de mezclarse ahí.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-1940](https://smartit-ar.atlassian.net/browse/GITIN-1940) |
| ID alerta | N/A — solicitud directa, no originada por alerta |
| Sistema | SmartFran Cloud — Logstash (Event Hub → Graylog) + Graylog Streams/Index Sets |
| Severidad | Baja — mejora de observabilidad, no incidente productivo |
| Detectado | 2026-08-25 (muestra de 408 en Sales que motivó el pedido) |
| Resuelto | 2026-08-26 |
| Responsable | Dante Paniagua, SRE |

## Causa raíz

El pipeline de Logstash (`azure-eventhub-to-graylog.conf`) sólo promovía a nivel raíz un subconjunto de campos del CLEF de cada servicio (`TraceKey`/`TenantId`/`Service`/etc., de tickets previos) — los campos propios de la línea "Request finished" y de la categoría nativa `AppServiceHTTPLogs` quedaban stringificados dentro de `Properties`/`properties`, sin ser alcanzables por queries estructuradas. Al resolver eso y quedar el volumen de `AppServiceHTTPLogs` visible/queryable, se hizo evidente que compartía Stream e Index Set con el resto de las categorías de cada app — sin separación por tipo de log dentro del mismo App Service.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Gap original: `StatusCode`/`Path`/`Method`/`ElapsedMilliseconds`/`ClientIP` no promovidos para ninguna de las 2 formas de origen (línea "Request finished" y `AppServiceHTTPLogs`). Resuelto en este ticket. | Medio |
| H2 | `AppServiceHTTPLogs` es la categoría de mayor volumen en los 8 streams compartidos por app, sin separar del resto. Resuelto en este ticket (Streams/Index Sets dedicados). | Medio |
| H3 | Anomalía de formato: el `TenantId` de la muestra original de Sales (`org_z72xsKwcFsVLHF3c`) tiene forma de `org_id` de Auth0, distinto del hash opaco de 12 caracteres visto en toda otra muestra confirmada de Sales. No investigado — fuera de alcance de este ticket. | Bajo |
| H4 | Instancia `smartfran-cloud-sales-pro-stg2.azurewebsites.net` detectada incidentalmente en tráfico real, sin `Service`/`Environment`/`Component` (aparece como `source: unknown-service`) — una instancia de staging aparentemente sin tagging aplicado. No investigado. | Bajo |
| H5 | Durante la investigación de nombres de recursos existentes, 2 llamadas `GET` de sólo lectura se ejecutaron directamente en lugar de entregarse como bloques copy-paste al usuario — desvío de la convención del proyecto, sin impacto (sin escritura de estado). Detectado y reportado en la misma sesión. | Bajo |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| `sfcloud-monitoreo.smartfran.com` (Logstash) | Pipeline `azure-eventhub-to-graylog.conf` parcheado y reiniciado |
| Sales, Business, Admin, Platform, Person, Catalog, Orders, Pos (PRO) | Origen de los campos promovidos; 8 Streams + 8 Index Sets nuevos creados para `AppServiceHTTPLogs` |
| Streams `PROD-{App}-AppServicePlan` (8, ya existentes) | Regla invertida agregada (`category != AppServiceHTTPLogs`) |
| Streams `PROD-{App}-AppServiceHTTPLogs` (8, nuevos) | `SFC-{App}-prod-http` como Index Set, retención 7 días |

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | Parche Logstash (`gitin-1940.patch`) | ⚠️ Agregar bloque Ruby de promoción de campos al pipeline en vivo |
| C2 | `logstash -t` | Validar sintaxis del pipeline parcheado |
| C3 | `systemctl restart logstash` | ⚠️ Aplicar el cambio |
| C4 | Búsquedas Graylog (Views Search API) | Confirmar en vivo los 5 campos en ambas formas de origen |
| C5 | `GET /streams`, `GET /system/indices/index_sets` | Relevar convención de nombres existente antes de crear recursos nuevos |
| C6 | Creación de Index Set + Stream por app (8x) | ⚠️ Crear `SFC-{App}-prod-http` y `PROD-{App}-AppServiceHTTPLogs` |
| C7 | Reglas de Stream (nombre + categoría, 8x) | ⚠️ Enrutar `AppServiceHTTPLogs` al nuevo stream por app |
| C8 | Regla invertida en stream original (8x) | ⚠️ Excluir `AppServiceHTTPLogs` del stream compartido por app |
| C9 | `PUT` retención Index Sets (8x) | ⚠️ Reducir retención de los nuevos Index Sets a 7 días |

Detalle completo en `scripts.sh` (este directorio, campos) y `cloud/events/20260826_appservicehttplogs-stream-split/scripts.sh` (Streams/Index Sets).

## Acciones propuestas

1. **[Completado]** Agregar al pipeline de Logstash la promoción de `StatusCode`/`Path`/`Method`/`ElapsedMilliseconds`/`ClientIP`, cubriendo tanto la línea "Request finished" (Event Hub apps + Sales) como la categoría `AppServiceHTTPLogs` (con el cast de tipos necesario: `ScStatus` string→Integer, `TimeTaken` Integer→Float).
2. **[Completado]** Desplegar el cambio en producción y confirmar en tráfico real los 5 campos en ambas formas de origen.
3. **[Completado]** Crear Stream + Index Set dedicado (`PROD-{App}-AppServiceHTTPLogs` / `SFC-{App}-prod-http`, retención 7 días) para `AppServiceHTTPLogs` en las 8 apps PROD, y excluir esa categoría de los streams compartidos originales.
4. **[Pendiente]** Confirmar puntualmente en las 7 apps restantes (sólo `Admin` tuvo su inflow al stream nuevo verificado explícitamente en tráfico real) que la exclusión del stream original efectivamente dejó de recibir `AppServiceHTTPLogs`.
5. **[Pendiente, fuera de alcance]** Actualizar el diagrama de Streams en `cloud-graylog/docs/architecture.md`, desactualizado tras esta separación por categoría.
6. **[Pendiente, fuera de alcance]** Evaluar si el patrón `WsFeAr/CaeRequest` con `StatusCode:408` amerita una alerta de Graylog ahora que es una query estructurada — no decidido en este ticket.

## Hallazgos secundarios

- **H3 (anomalía `TenantId`)** y **H4 (instancia `-stg2` sin tagging)** quedan como candidatos a seguimiento en un ticket aparte — no bloquean el cierre de GITIN-1940.
- **H5 (proceso)** ya fue reportado y corregido dentro de la misma sesión — no requiere seguimiento adicional.

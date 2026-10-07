# GITIN-2098 — TraceID no promovido en Graylog

**Tags:** SmartCloud, Graylog, Azure, PROD

## Resumen

Los identificadores de trazado distribuido W3C (`TraceId`, `SpanId`, `ParentId`) que Serilog agrega automáticamente a cada línea de log de las 6 aplicaciones Event Hub (Business, Admin, Platform, Person, Catalog, Orders), Sales (sink directo GELF) y el tráfico legado de `SFC-PosWasmRelay` quedaban únicamente anidados dentro de los campos `Properties`/`event_original` (JSON en formato string), sin promoción a campos planos de nivel superior en Graylog — a diferencia de `TraceKey`, `Service` y `Environment`, ya unificados desde GITIN-1883/1892. Esto impedía filtrar o correlacionar logs por trace id directamente en Graylog, forzando búsqueda de texto completo sobre campos JSON anidados. Detectado el 2026-09-23 al revisar un mensaje real de Sales-PRO. Plataforma SmartFran Cloud, componente Graylog/Logstash, severidad Baja/Media (impacto en observabilidad, sin impacto en disponibilidad).

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-2098 |
| ID alerta | N/A — detectado por revisión manual, no por alerta automática |
| Sistema | Graylog / Logstash — SmartFran Cloud |
| Severidad | Baja/Media |
| Detectado | 2026-09-23 |
| Resuelto | 2026-09-23 |
| Responsable | Dante Paniagua (SRE) |

## Causa raíz

El pipeline de Logstash nunca incluyó una regla de promoción para `Properties.TraceId`/`.SpanId`/`.ParentId`. Estos campos forman el triplete de trazado distribuido W3C que un enricher propio de Serilog (registrado en el bootstrap compartido de logging, junto a `Service`/`Environment`/`Version`) estampa desde el `Activity` en curso sobre cada línea de log, en todos los servicios que usan ese bootstrap — el mismo alcance universal que `TraceKey`. Sin embargo, ninguno de los tickets previos de promoción de campos (GITIN-1883, GITIN-1892, GITIN-1940) targeteó específicamente este triplete: se promovió `TraceKey` (la clave de negocio propia de la aplicación) y otros campos, pero `TraceId`/`SpanId`/`ParentId` nunca se agregaron al pipeline. La documentación del esquema de logs del equipo de desarrollo tampoco lo lista como campo propio — solo aparece como valor de fallback de `TraceKey`.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | `TraceId`/`SpanId`/`ParentId` presentes en `Properties` (JSON string) en las 6 apps Event Hub, Sales y tráfico legado de PosWasmRelay, sin promoción a campo plano | Medio |
| H2 | La categoría `FunctionAppLogs` (4 Function Apps) ya promueve los 3 campos desde GITIN-2050 — sin gap ahí | — |
| H3 | La documentación del esquema de logs del equipo de desarrollo no lista `TraceId` como campo propio del esquema | Bajo |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| Logstash pipeline | Instancia SmartCloud Graylog, `azure-eventhub-to-graylog.conf` |
| Streams PROD | `PROD-Sales-AppServicePlan`, `PROD-Business-AppServicePlan`, `PROD-Admin-AppServicePlan`, `PROD-Platform-AppServicePlan`, `PROD-Person-AppServicePlan`, `PROD-Catalog-AppServicePlan`, `PROD-Orders-AppServicePlan`, `PROD-Pos-AppServicePlan` (tráfico legado PosWasmRelay) |

## Comandos ejecutados

Ver `scripts.sh` en este evento.

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | Fetch live conf | Relevar la configuración viva de Logstash antes de redactar el parche |
| D1 | Copiar parche a la VM | Transferir `gitin-2098.patch` vía SSH |
| D2 | Backup + dry-run | Respaldar el archivo vivo y validar el parche sin aplicarlo |
| D3 | ⚠️ Aplicar parche | Aplicar `gitin-2098.patch` sobre la configuración viva |
| D4 | Validar sintaxis | `logstash -t` — Configuration OK |
| D5 | ⚠️ Reiniciar Logstash | `systemctl restart logstash` |
| D6 | Confirmar estado | `systemctl status logstash` — activo, sin errores |
| V1 | Verificar Sales-PRO | Confirmar `TraceId`/`SpanId`/`ParentId` en tráfico real |
| V2 | Verificar Business-PRO | Confirmar `TraceId`/`SpanId`/`ParentId` en tráfico real |

## Acciones propuestas

1. **(SRE)** — Completado. Se relevó la configuración viva de Logstash y se confirmó sincronizada con la copia de referencia local antes de redactar el parche.
2. **(SRE)** — Completado. Se agregó un nuevo bloque de filtro en `azure-eventhub-to-graylog.conf` (`gitin-2098.patch`) que promueve `Properties.TraceId`/`.SpanId`/`.ParentId` a campos planos, siguiendo el mismo patrón de dos ramas usado por GITIN-1883/1892 (apps Event Hub vía `resultDescription` anidado; Sales/PosWasmRelay vía `Properties` de nivel superior).
3. **(SRE)** — Completado. Se validó la sintaxis (`Configuration OK`) y se reinició el servicio Logstash sin incidentes ni caída del servicio.
4. **(SRE)** — Completado. Se verificó en tráfico real post-deploy: Sales-PRO (138 hits en 5 minutos, 10/10 mensajes muestreados con `TraceId`+`SpanId`, `ParentId` presente en 6/10) y Business-PRO (106 hits en 5 minutos, 10/10 mensajes con los 3 campos).
5. **(SRE)** — Completado. Se actualizó la documentación de referencia de campos de Graylog y la documentación del esquema de logs del equipo de desarrollo para reflejar los nuevos campos promovidos, incluyendo la corrección de que `TraceId`/`SpanId`/`ParentId` son campos propios y no solo el valor de fallback de `TraceKey`.
6. **(SRE)** — Pendiente. Confirmar si el mismo gap aplica al lado DEV — no verificado en este ticket.

# Mensajes con source:unknown-service en Sales PRO — GITIN-1908

**Tags:** `SmartCloud`, `Graylog`, `Azure`, `Obserbavilidad`

## Resumen

Se reportaron mensajes en Graylog con `source: "unknown-service"` originados en SmartFran Cloud Sales PRO. Se sospechó inicialmente que compartía causa raíz con GITIN-1905 (desalineación entre `Properties_Service`/`Properties_Environment`, documentado localmente, y `Service`/`Environment`, ya vigente en el pipeline). La investigación descartó esa hipótesis: las dos reglas de pipeline "CLEF source" (GITIN-1835) ya usan el campo `Service` sin prefijo. El comportamiento se explica en cambio por tres orígenes distintos de ausencia del campo `Service`, confirmados contra tráfico real: dos legítimos y sin impacto (diagnósticos propios de ASP.NET Core y logging interno del SDK Azure SignalR) y uno que representa una pérdida real de atribución sobre un evento de negocio (`WalletNotificationService`).

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-1908 |
| ID alerta | N/A — reporte de bug, no alerta automática |
| Sistema | SmartFran Cloud Sales PRO — reglas de pipeline Graylog GITIN-1835 ("CLEF source"), Logstash (`azure-eventhub-to-graylog.conf`, bloque GITIN-1883) |
| Severidad | Baja |
| Detectado | 2026-08-20 |
| Resuelto | No — causa raíz identificada y confirmada contra tráfico real; pendiente decisión de alcance (ver Acciones propuestas) |
| Responsable | SRE |

## Causa raíz

Las reglas de pipeline "GITIN-1835: CLEF source from Properties.Service" y "GITIN-1835: CLEF source fallback" ya referencian el campo `Service` sin prefijo (migradas junto con la regla que confirmó GITIN-1905, no hay desalineación de nombre de campo). El fallback que setea `source: "unknown-service"` se dispara correctamente cada vez que Logstash no encuentra un valor de `Service` no vacío dentro de `Properties` para promover (bloque GITIN-1883 en `azure-eventhub-to-graylog.conf`, líneas 159–226). Confirmado contra tráfico real que esta ausencia ocurre en tres escenarios: mensajes de diagnóstico propios del framework ASP.NET Core, logging interno del SDK Azure SignalR, y logs de negocio de `WalletNotificationService` (código propio de Sales) que no pasan por los helpers estándar de logging (`SmartFranLogExtensions`) y por lo tanto nunca reciben `Service`/`TenantId`.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | 223.916 mensajes con `source: "unknown-service"` en 24h (todos los streams). De una muestra de 20, el 100% son diagnósticos propios de ASP.NET Core (`SourceContext: Microsoft.AspNetCore.Hosting.Diagnostics`, `Microsoft.AspNetCore.Cors.Infrastructure.CorsService`) desde Sales PRO, sin campo `Service` en `Properties` — comportamiento esperado, no es un bug. | Bajo |
| H2 | Excluyendo el `SourceContext` de ASP.NET Core quedan 1.268 mensajes (0,6% del total). De una muestra de 20 de estos, 8 corresponden a logging interno del SDK Azure SignalR (`Microsoft.Azure.SignalR.ServiceConnection`, `Microsoft.Azure.SignalR.DefaultServiceEventHandler`) — misma clase de ausencia legítima que H1. | Bajo |
| H3 | 12 de los 20 mensajes de la muestra de H2 corresponden a `SmartFran.Cloud.Sales.Application.Services.VirtualWallet.SignalR.WalletNotificationService` (código propio de Sales, no un namespace de framework/SDK), logueando el evento de negocio "Notificación enviada: Orden creada [ID]" sin pasar por los helpers estándar de logging — pierde atribución de `Service`/`TenantId` sobre un evento de negocio trazable. | Medio |
| H4 | El archivo de referencia local `cloud-graylog/docs/sales-direct-gelf-clef-format.rule` sigue mostrando `Properties_Service` en el título/cuerpo de las reglas documentadas — desactualización documental de la misma clase identificada en GITIN-1905, no afecta el pipeline en vivo. | Bajo |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| Graylog Pipeline Rules | "GITIN-1835: CLEF source from Properties.Service" (`6a7f29664814bcaed30c7de7`), "GITIN-1835: CLEF source fallback" (`6a7f24784814bcaed30c6d52`) |
| App Service | `SmartFran-Cloud-Sales-PRO` (`smartfran-cloud-sales-pro.azurewebsites.net`) |
| Logstash | `cloud-graylog/docs/azure-eventhub-to-graylog.conf`, bloque GITIN-1883 (líneas 159–226) — repo `cloud-graylog`, separado de este monorepo |
| Documentación desactualizada | `cloud-graylog/docs/sales-direct-gelf-clef-format.rule` (ver H4) |

## Comandos ejecutados

| # | Comando/Script | Propósito |
|---|---|---|
| C1 | `scripts.sh` — `GET /system/pipelines/rule`, filtro "CLEF source" | Confirmar el código vigente de ambas reglas de pipeline |
| C2 | `scripts.sh` — Views Search `source:"unknown-service"`, 24h, muestra 20 | Cuantificar y muestrear los mensajes afectados |
| C3 | `scripts.sh` — misma búsqueda excluyendo `SourceContext:Microsoft.AspNetCore.*` | Descartar/aislar mensajes no explicados por ruido de framework |

## Acciones propuestas

1. Confirmar el conteo exacto por `SourceContext` dentro de los 1.268 mensajes restantes (SDK Azure SignalR vs. `WalletNotificationService`), en vez de extrapolar de la muestra de 20.
2. Elevar a PM/Arquitectura la decisión de alcance para el tier de `WalletNotificationService`: (a) dejarlo como está; (b) enrutar su logging a través de los helpers estándar `SmartFranLogExtensions` para que reciba `Service`/`TenantId`; (c) una mejora de fallback más amplia (derivar `source` de `Host` cuando falte `Service`) que cubra los tres orígenes a la vez.
3. Actualizar `cloud-graylog/docs/sales-direct-gelf-clef-format.rule` y la nota en `azure-eventhub-to-graylog.conf` que marca la ausencia de `Service` en Sales como "no confirmada independientemente" — ya quedó confirmada contra tráfico real en este ticket.
4. Cerrar como "comportamiento esperado, no es un bug" una vez resuelto el punto 2, o mantener abierto si se decide implementar el enrutamiento de `WalletNotificationService`.

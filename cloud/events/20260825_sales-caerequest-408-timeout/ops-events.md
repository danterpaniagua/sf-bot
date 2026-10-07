# Eventos — 20260825_sales-caerequest-408-timeout (GITIN-1940)

## 2026-08-25 17:02 — Diseño del cambio de Logstash

He diseñado el bloque de promoción de `StatusCode`/`Path`/`Method`/`ElapsedMilliseconds` para la línea "Request finished" de ASP.NET Core, cubriendo tanto los Event Hub apps como Sales. Lo he agregado a la copia local del pipeline y a la documentación de campos, dejándolo marcado como desplegado-pendiente-de-verificar.

## 2026-08-26 12:07 — Despliegue en Logstash

**Comando:** C1 — parche `gitin-1940.patch` sobre `/etc/logstash/conf.d/azure-eventhub-to-graylog.conf`
**Resultado:**
`Hunk #1 succeeded` en dry-run y en aplicación real.

He verificado el archivo en vivo antes de generar el parche, confirmando que coincidía exactamente con la copia local. He aplicado el parche sin errores.

## 2026-08-26 12:07 — Validación y reinicio

**Comando:** C2 — `logstash -t`; C3 — `systemctl restart logstash`
**Resultado:**
`Configuration OK`. `systemctl status`: `active (running)`, `Event Hub is processing events...`.

He confirmado que el servicio quedó arriba y consumiendo mensajes, no en crash-loop.

## 2026-08-26 12:08 — Primera confirmación parcial en vivo

**Resultado:**
Muestra real de `Platform-PRO` con `StatusCode: 200` y `ElapsedMilliseconds: 114.2319` a nivel raíz — aunque de un log de `HttpClient` saliente, no de la línea "Request finished" en sí.

He confirmado que el bloque promueve correctamente estos dos campos para cualquier mensaje con esas claves, no sólo para la línea que motivó el ticket.

## 2026-08-26 12:11 — Confirmación completa de Path/Method

**Resultado:**
788 mensajes coincidentes con `SourceContext:"Microsoft.AspNetCore.Hosting.Diagnostics"` en la última hora; 5 muestras reales de Sales-PRO/-DEV/-PRO-stg2 con `Path`/`Method`/`StatusCode`/`ElapsedMilliseconds` presentes y correctos.

He confirmado los 4 campos en la línea "Request finished" real, no sólo en el proxy de HttpClient.

## 2026-08-26 12:12 — Confirmación de ClientIP vía AppServiceHTTPLogs

**Resultado:**
5770 mensajes coincidentes con `category:AppServiceHTTPLogs` en la última hora; 5 muestras reales de Admin-PRO/Platform-PRO/Orders-PRO con `ClientIP`/`StatusCode`/`Path`/`Method`/`ElapsedMilliseconds` presentes y correctos, incluyendo los casteos de tipo (`ScStatus` string→Integer, `TimeTaken` Integer→Float).

He confirmado los 5 campos en ambas formas de origen. Doy por verificado en vivo el alcance completo de este ticket.

## 2026-08-26 12:25 — Inicio del trabajo de separación de Streams (seguimiento, mismo ticket)

He relevado la convención de nombres existente (`GET /streams`, `GET /system/indices/index_sets`) antes de crear recursos nuevos, confirmando el patrón `PROD-{App}-AppServicePlan` / `SFC-{App}-prod`.

## 2026-08-26 12:25-12:35 — Creación de Streams e Index Sets dedicados

**Comando:** C6/C7/C8 — creación de Index Set + Stream + reglas, por app (8x)
**Resultado:**
Los 8 Index Sets (`SFC-{App}-prod-http`) y los 8 Streams (`PROD-{App}-AppServiceHTTPLogs`) quedaron creados sin errores, con las reglas de `name`+`category` en el stream nuevo y la regla invertida de `category` en el stream original.

He verificado el piloto (Admin) con tráfico real antes de replicar al resto — 209 mensajes en el stream nuevo dentro de los primeros 10 minutos.

## 2026-08-26 12:34 — Reducción de retención a 7 días

**Comando:** C9 — `PUT` sobre los 8 Index Sets nuevos
**Resultado:**
Los 8 quedaron con `data_tiering` en `P7D`/`P9D`, confirmado en la respuesta de cada `PUT`.

He tenido que corregir el script dos veces antes de que funcionara: el primer intento se corrompió al pegarse en la terminal (script Python multilínea inline), y el segundo chocó con `noclobber` reusando archivos vacíos de un intento previo. Ambos quedaron documentados en `cloud/events/20260826_appservicehttplogs-stream-split/investigation.md` para la próxima vez que este proyecto scriptee un `PUT` de Graylog.

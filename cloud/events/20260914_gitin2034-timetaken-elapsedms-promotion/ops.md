# GITIN-2034 — Corregir promoción de TimeTaken/ElapsedMilliseconds en AppServiceHTTPLogs

**Tags:** `SmartCloud` `Azure` `Graylog` `Obserbavilidad` `PROD` `SRE`

## Resumen

La rama `AppServiceHTTPLogs` del bloque de Logstash de GITIN-1940 (promoción de `Method`/`Path`/`StatusCode`/`ElapsedMilliseconds`/`ClientIP`) asumía que el campo `properties` (minúscula) siempre llegaba pre-stringificado como JSON por Azure. Esa asunción era correcta para la forma de ingesta "envuelta" (batch `records`), pero no para la forma "plana" (sin wrapper), donde el propio filtro `json` inicial de este pipeline parsea `properties` directamente como un Hash vivo. Para mensajes en esa segunda forma — confirmado con tráfico real de `SmartFran-Cloud-Sales-PRO` — el guard original (`props_json.is_a?(String)`) fallaba silenciosamente y ninguno de los 5 campos se promovía, dejando esos mensajes sólo consultables por full-text search, igual que antes de GITIN-1940.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2034](https://smartit-ar.atlassian.net/browse/GITIN-2034) |
| ID alerta | N/A — detectado durante la investigación de `20260913_pos-net-http-timeout` |
| Sistema | SmartFran Cloud — Logstash (Event Hub → Graylog), pipeline `azure-eventhub-to-graylog.conf` |
| Severidad | Baja — gap de observabilidad, no incidente productivo |
| Detectado | 2026-09-13/14 |
| Resuelto | 2026-09-14 |
| Responsable | Dante Paniagua, SRE |

## Causa raíz

El bloque `AppServiceHTTPLogs` de GITIN-1940 sólo contemplaba una de las dos formas reales en que Azure entrega esta categoría vía Event Hub: la forma envuelta en `"records"` (donde `properties` llega pre-stringificado) y la forma plana/sin wrapper (donde el filtro `json` inicial del pipeline parsea `properties` como Hash vivo, no como String). El guard `props_json.is_a?(String)` sólo cubría el primer caso — para el segundo, todo el bloque no hacía nada, sin error visible. Confirmado con un mensaje real de Sales-PRO (`_id: b4966b92-b038-11f1-be92-7c1e52beabec`, `/api/v1/Status/Health`) donde ninguno de los 5 campos estaba presente. Bug secundario en el mismo bloque: `ScStatus` en la forma plana llega como Integer, no como String numérico, y el cast original sólo contemplaba el segundo caso.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Bloque `AppServiceHTTPLogs` de GITIN-1940 no promovía ningún campo para mensajes en la forma plana/sin wrapper — confirmado en tráfico real de Sales-PRO. Resuelto en este ticket. | Medio |
| H2 | `ScStatus` no se casteaba correctamente cuando llegaba como Integer (sólo se contemplaba el caso String numérico). Resuelto en este ticket. | Bajo |
| H3 | Intento de despliegue #1 falló validación de sintaxis (`logstash -t`) por un apostrofo en un comentario dentro del bloque `code => '...'` de Logstash, cerrando la cadena de forma prematura — el mismo modo de falla que el propio archivo advierte en su encabezado. Sin impacto: el archivo en disco quedó inválido brevemente pero Logstash nunca se reinició con esa versión (revertido desde el backup antes del restart). Resuelto en el intento #2. | Bajo |
| H4 | Hallazgo separado, de mayor escala: 64.866 fallas de indexación en Graylog (`mapper_parsing_exception`), todas por un campo `time` (tipo `date`) rechazando formato no-ISO8601 (`MM/DD/YYYY`). Sin relación confirmada con este ticket — documentos completos rechazados, no un campo puntual. Fuera de alcance, candidato a ticket propio. | Medio |
| H5 | El gap original en `Service:"Sales"` (rama GELF directo, línea "Request finished") — sólo `ElapsedMilliseconds` ausente, con `StatusCode`/`Path`/`Method` funcionando — permanece sin explicar. Se descartó por trazado de código que comparta la misma causa (Hash vs. String) que H1. Fuera de alcance de este ticket. | Bajo |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| `sfcloud-monitoreo.smartfran.com` (Logstash) | Pipeline `azure-eventhub-to-graylog.conf` parcheado y reiniciado |
| `SmartFran-Cloud-Sales-PRO` (y potencialmente otras apps Windows con `AppServiceHTTPLogs` en forma plana) | Mensajes antes sin los 5 campos promovidos, ahora corregidos |

## Comandos ejecutados

Ver `scripts.sh` para el detalle completo, incluyendo el intento de despliegue fallido y su reversión.

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | Descarga de la conf en vivo vía SSH | Confirmar que el bloque GITIN-1940 seguía intacto antes de asumir una regresión |
| C2 | Búsqueda Graylog `category:AppServiceHTTPLogs` | Confirmar que la rama funciona en otras apps (Admin-PRO/Orders-PRO) |
| C3 | `GET /api/system/indexer/failures` | Descartar relación con el hallazgo de fallas de indexación (H4) |
| C4 | Búsqueda Graylog por `_id` puntual | ★ Confirmar la causa raíz real (H1) con un mensaje real de Sales-PRO |
| D0-D2 | Verificación + backup + dry-run del parche | Preparación segura antes de aplicar |
| D3 | Aplicar parche (intento #1) | ⚠️ Falló validación de sintaxis (H3) |
| D4b | Revertir desde backup | ⚠️ Recuperación tras la falla del intento #1 |
| D1b-D2b | Copiar y dry-run del parche corregido | Preparación del intento #2 |
| D3b | Aplicar parche (intento #2) | ⚠️ Exitoso |
| D4c | `logstash -t` | Validar sintaxis — Configuration OK |
| D5 | `systemctl restart logstash` | ⚠️ Aplicar el cambio |
| D6 | `systemctl status logstash` | Confirmar arranque limpio, sin crash-loop |
| V1 | Búsqueda Graylog post-despliegue | Confirmar los 5 campos en tráfico real de Sales-PRO |

## Acciones propuestas

1. **[Completado]** Corregir el bloque `AppServiceHTTPLogs` de GITIN-1940 para aceptar `properties` tanto como Hash como String, y castear `ScStatus` en sus dos formas posibles.
2. **[Completado]** Desplegar el cambio en producción y confirmar en tráfico real de Sales-PRO los 5 campos promovidos correctamente.
3. **[Completado]** Validar la conf en vivo contra lo desplegado (sin drift) y confirmar en vivo, con conteos reales de 24h, los 23 campos trackeados en `docs/graylog-log-fields.md` — no sólo los 5 de este ticket. Encontrado de paso: `Category` ya está en vivo (638 hits/24h), corrigiendo una afirmación desactualizada del documento (2026-08-19, "no observado en vivo").
4. **[Completado]** Actualizar `docs/graylog-log-fields.md` con el mecanismo del bug, la corrección de `Category`, y el gap remanente en `Service:"Sales"` — todo trazable a verificación real, no a código o documentación previa asumida.
5. **[Pendiente, fuera de alcance]** Investigar el hallazgo de fallas de indexación por el campo `time` (H4) — candidato a ticket propio dado su volumen (64.866 fallas).
6. **[Pendiente, fuera de alcance]** Investigar el gap remanente en `Service:"Sales"` / `ElapsedMilliseconds` (H5) — no comparte la causa raíz de este ticket, requiere investigación propia.
7. **[Pendiente, fuera de alcance]** Confirmar si otras apps Windows (Pos-PRO) también reciben `AppServiceHTTPLogs` en la forma plana y se benefician de esta misma corrección — no verificado puntualmente en este ticket, sólo confirmado para Sales-PRO.

## Hallazgos secundarios

- **H4** (fallas de indexación por campo `time`) y **H5** (gap `ElapsedMilliseconds` en `Service:"Sales"`) quedan como candidatos a ticket propio — no bloquean el cierre de GITIN-2034.
- **H3** (falla del intento de despliegue #1) ya fue detectada, revertida y corregida dentro de la misma sesión — no requiere seguimiento adicional.

# Eventos — gestion_clubgrido_waf_504

## 2026-07-21 — Reporte de Grido: 504 en gestion.clubgrido.com/Catalog/Crud

**Resultado:**
He recibido el reporte de Grido sobre error 504 en `https://gestion.clubgrido.com:4430/Catalog/Crud`. Identifiqué el recurso involucrado como el Application Gateway WAF_v2 `WAF_APPs` (RG `DefaultGroup01`, suscripción Smart IT - Grido), confirmado por el usuario con los datos de resource group, tier (WAF V2), IP frontend (`13.82.133.54`, `WAF_PROD01`) y subnet (`sfcgvnet01/WAF_01`).

## 2026-07-21 — Relevamiento de configuración y salud de backend

**Comando:** C1, C2 — `appgw-show`, `appgw-backend-health`
**Resultado:**
He confirmado tres `backendHttpSettings` (`Backend_WebSite` puerto 4430/180s timeout, `Backend_ClubSite` y `Backend_ClubSite_PY` puerto 443/60s), sin health probes personalizados en ninguno. Los tres servidores de backend reportaron `Healthy` vía el probe por defecto contra la raíz.

He mapeado el listener `Listener_WebSite_HTTPS` (host `gestion.clubgrido.com.ar`, puerto frontend 4430) a la regla `Rule_WebSite`, pool `Back_WebSite`, con un único servidor `192.168.50.131` — sin redundancia.

## 2026-07-21 — Confirmación de workspace de Log Analytics

**Comando:** C3, C4 — `law-workspace-guid`, `law-diag-settings-list`
**Resultado:**
He confirmado que el Application Gateway exporta diagnósticos (configuración `LOGS_WAF`) al workspace `analisis-loadbalancer`, GUID `e00bc24a-820a-45fa-ad4a-3a4dc083d205`.

## 2026-07-21 — Descubrimiento de esquema y consulta de ApplicationGatewayAccessLog

**Comando:** C5, C6 — `kql-accesslog-schema`, `kql-accesslog-504-query`
**Resultado:**
He descubierto el esquema real de campos de `ApplicationGatewayAccessLog` (los sufijos de tipo de `AzureDiagnostics` no son adivinables — `timeTaken_d`, no `timeTaken_s`). Con el esquema confirmado, ejecuté la consulta completa para `gestion.clubgrido.com` en las últimas 48h, exportada a tabla (3.706 filas).

Analicé el archivo resultante y confirmé la distribución de `HttpStatus_d`: 502=3.121, 200=305, 499=265, 504=13, 206=2. La distribución de `Error_info_s` mostró `ERRORINFO_UPSTREAM_NO_LIVE`=3.121, `ERRORINFO_CLIENT_CLOSED_REQUEST`=544, `ERRORINFO_CLIENT_TIMED_OUT`=28, `ERRORINFO_UPSTREAM_TIMED_OUT`=13.

Identifiqué que los 13 casos de 504 corresponden todos a `ERRORINFO_UPSTREAM_TIMED_OUT`, con cuatro de ellos concentrados en `/Catalog/SetListCatalog` con `TimeTaken` de ~180,0xx segundos — coincidencia exacta con el `requestTimeout` configurado en `Backend_WebSite`. Esto confirma que el gateway esperó el tiempo completo configurado y el backend nunca respondió — descarté una mala configuración del gateway como causa.

Identifiqué además, sin que fuera parte del reporte original de Grido, que los 3.121 casos de `ERRORINFO_UPSTREAM_NO_LIVE` se concentran en una ventana continua de `2026-07-20T05:04:52Z` a `2026-07-21T10:01:04Z` (~29 horas) — indisponibilidad total del pool de backend, de escala muchísimo mayor al problema reportado.

## 2026-07-21 — Descarte de ApplicationGatewayPerformanceLog y del WAF como causa

**Comando:** C7, C8 — `kql-perflog-schema`, `kql-firewalllog-schema`
**Resultado:**
Confirmé que `ApplicationGatewayPerformanceLog` no devuelve datos para este recurso — verifiqué que es un comportamiento esperado, dado que esta categoría de log sólo aplica a gateways de tier v1, y `WAF_APPs` es v2 (el tier v2 expone salud/throughput vía métricas de Azure Monitor, no vía esta categoría de diagnóstico).

Obtuve una muestra de `ApplicationGatewayFirewallLog` y confirmé `WAFMode_s: "Detection"` en la policy `WAV_directiva` — el WAF no puede bloquear ningún request en este modo, sólo registra coincidencias. La muestra obtenida mostró una coincidencia (`action_s: "Matched"`, no `"Blocked"`) sobre un endpoint no relacionado (`/Account/ChangePassword`, falso positivo de detección de SQLi sobre un token CSRF). Con esto descarté al WAF como causa de los 504 reportados, sin necesidad de ejecutar una consulta completa adicional sobre el firewall log.

## 2026-07-21 — Ticket documentado y skill de análisis creada

**Resultado:**
Documenté ambos hallazgos (504 en `/Catalog/*` por timeout de aplicación, y el incidente de 502/`UPSTREAM_NO_LIVE` de ~29 horas) en un único ticket, dado que comparten el mismo recurso raíz (`WAF_APPs` / `Back_WebSite` / `192.168.50.131`) y fueron detectados en la misma investigación. Archivé la salida completa de la consulta de access log (3.706 filas) junto al ticket.

Creé además la skill `/loyalty-azure-waf` en `.claude/commands/` (submódulo `sf-skills`), documentando el flujo completo de este análisis (mapa de listener→pool conocido, gotchas de esquema de `AzureDiagnostics`, tabla de referencia de `error_info_s`, y notas sobre por qué `ApplicationGatewayPerformanceLog` no aplica a tier v2) para reutilizar en investigaciones futuras de WAF sobre sitios de SmartLoyalty.

---

## 2026-07-21 — Identificación del servidor backend y su auto-shutdown

**Comando:** C9 — `vm-show`, `vm-list-ip-addresses`
**Resultado:**
Consultando por separado el estado de auto-shutdown de la VM `SFCG-WSIT-01` (RG `DefaultGroup01`), confirmé que tiene un schedule habilitado (`Enabled`, 02:00 hora Argentina, notificaciones deshabilitadas). Al obtener el detalle de la VM (tags `SML: WebSite`, `Website: 01`) y su dirección IP privada, identifiqué que `SFCG-WSIT-01` = `192.168.50.131` — el mismo servidor único que ya había identificado como el backend del pool `Back_WebSite` en la investigación del ticket de WAF. Confirmé que este es el servidor responsable de ambos hallazgos documentados (H1 timeouts en `/Catalog/*`, H2 indisponibilidad de 29 horas).

## 2026-07-21 — Investigación y descarte de la hipótesis de auto-shutdown como causa del incidente de 29h

**Comando:** C10, C11 — `activity-log-list`, `vm-get-instance-view`
**Resultado:**
Dado que el horario de auto-shutdown (02:00 ART = 05:00 UTC) es muy cercano al inicio del incidente de 29 horas (05:04:52 UTC), consulté `az monitor activity-log` sobre `SFCG-WSIT-01` en toda la ventana del incidente, primero con un filtro exacto sobre `resourceId` y luego con búsqueda case-insensitive ante la ausencia de resultados relevantes.

Confirmé que **no existe ningún evento `deallocate`/`stop`/`powerOff`** para esta VM en ningún momento de la ventana consultada (2026-07-19 20:00Z a 2026-07-21 12:00Z) — descarté formalmente el auto-shutdown como causa del incidente. El único evento registrado es un `start/action` manual a las 2026-07-21T10:00:16Z, 48 segundos antes del último `502` observado en el access log, precedido por eventos de Resource Health `Updated`/`Resolved` sobre el mismo recurso.

Concluí que la evidencia es más consistente con un cuelgue a nivel de sistema operativo o IIS en la VM — sin cambio de estado de energía registrado a nivel Azure durante 29 horas, pero con el sitio inaccesible durante todo ese período hasta el reinicio manual. No identifiqué la causa raíz del cuelgue en sí — requiere revisión de logs directamente en la VM, fuera del alcance de esta sesión.

Actualicé el ticket principal: corregí la hipótesis de auto-shutdown (descartada), agregué los hallazgos H6 (riesgo independiente del auto-shutdown) y H7 (cuelgue de SO/IIS como causa más probable), y revisé la tabla de recursos afectados y las acciones propuestas en consecuencia. Por la política de este repositorio de no incluir nombres de personas en el registro escrito, referencié el reinicio manual por su operación y timestamp en Activity Log, sin la identidad de quien lo ejecutó.

---

## 2026-07-21 — Causa raíz de H1 confirmada a nivel de código fuente

**Resultado:**
Ubiqué el repositorio de código fuente de SmartLoyalty (`loyalty/repo/dev-src-sol-smartloyalty`) y leí `CatalogController.cs` (`Crud`, `SetListCatalog`, `ProcessFileListCatalog`, `SendMails`) y `CustomerService.cs` (`GetCustomerAvailable`). Confirmé un patrón N+1: `GetCustomerAvailable` ejecuta hasta dos consultas a base de datos por cada fila del archivo subido por el operador, sin batching ni async.

Con el conteo de filas confirmado por el usuario (7.940, formato `Dni;<número>`), y localizando en el servidor los cuatro archivos exactos subidos en cada uno de los cuatro horarios de 504 (tres reintentos del mismo archivo `AA LISTAAAA.csv`, un cuarto intento con `socios-formateados.csv` renombrado), confirmé que la falla es determinística — no intermitente. Actualicé el ticket con la causa raíz completa, tabla de horarios exactos (para correlación con CPU de `SFCG-DB01` en Zabbix) y tabla de rutas de archivos relevantes (fuente y VM).

## 2026-07-22 — Identificación y verificación del Logic App de reactivación diaria — corrección de H8

**Comando:** C17, C18 — `az resource list` (Logic Apps), `az rest` sobre runs/actions del Logic App
**Resultado:**
A partir de un dato provisto por el usuario (la reactivación es vía Logic App, no Azure Function), listé los Logic Apps de la suscripción e identifiqué `Start_WSIT_01` (RG `DefaultGroup01`) como el mecanismo responsable. Confirmé que su trigger de recurrencia (10:00 UTC diario) está en estado `Succeeded` y consulté el historial de ejecuciones de ambos días del incidente.

Ambas ejecuciones (07-20 y 07-21) muestran la acción `Start_virtual_machine` en estado `Succeeded`. Descargué los `inputs`/`outputs` reales de esa acción para el run del 07-21: confirmé una llamada `POST` genuina a la API de Azure (`.../virtualMachines/SFCG-WSIT-01/start` vía la conexión `azurevm-2`) con respuesta real `HTTP 200` y encabezados de correlación de Azure auténticos — el arranque automático de la VM funciona correctamente ambos días.

Identifiqué que el estado `Failed` del run completo (en ambos días) se debe exclusivamente al paso posterior `Send_an_email_on_success`, que falla con `code: "NotFound"` — un conector de email roto, sin relación con el arranque de la VM. Esto explica por qué el mecanismo parecía no funcionar pese a estar funcionando correctamente.

**Corrección aplicada al ticket:** revertí la conclusión anterior (H8 como hallazgo crítico de "reactivación no identificada/fallida"). H8 pasa a ser informativo (mecanismo identificado y confirmado funcionando); se agregó H9 (notificación de éxito rota, historial de ejecuciones engañoso). Reescribí las acciones propuestas 4 y 5 — de "localizar el mecanismo faltante" (prioridad alta) a "corregir el conector de email roto" (prioridad baja, cosmético). Documenté que el evento manual de Activity Log (`start/action`, 2026-07-21T10:00:16Z) cae dentro de la ventana de ejecución del Logic App y fue muy probablemente una intervención redundante.

---

## 2026-07-22 — Recreación y reorganización del ticket principal

**Resultado:**
Reescribí `20260721_gestion_clubgrido_waf_504_ops.md` completo a pedido del usuario, dado que las múltiples correcciones sucesivas (auto-shutdown descartado → reinstalado → reactivación no identificada → reactivación identificada y confirmada) habían dejado el documento con lenguaje narrativo de "conclusión anterior corregida" en varios puntos, redundante para un lector que retoma el ticket sin el contexto de la investigación. Mantuve todos los hallazgos, rutas de archivo, horarios y comandos ya confirmados, pero presenté únicamente el entendimiento final en cada sección — sin el historial de hipótesis descartadas. Renumeré los hallazgos (H1–H9) en orden lógico y ajusté las referencias cruzadas en Acciones propuestas en consecuencia. No se modificó este archivo de eventos (registro de actividad, append-only) más que con esta entrada.

---

## 2026-07-22 — Confirmación independiente en Zabbix: pico de CPU en SFCG-DB01

**Resultado:**
Recibí del usuario un dato de Zabbix: durante la ventana de los 4 horarios de 504 confirmados (2026-07-21), `SFCG-DB01` alcanzó ~50% de CPU máximo, frente a ~1% de promedio fuera de esa ventana. Es una confirmación independiente del patrón N+1 (miles de consultas secuenciales generan exactamente este tipo de pico de CPU en el servidor de base de datos), desde una fuente de datos distinta al código fuente ya revisado.

Actualicé el ticket: agregué el dato a la sección "Causa raíz — Hallazgo 1", marqué la acción propuesta 9 como resuelta, y actualicé el campo "Resuelto" de la tabla resumen para reflejar la confirmación independiente. Dejé pendiente, como nota opcional, acotar el pico de CPU a cada uno de los 4 horarios individuales en vez de sólo a la ventana agregada, si se requiere mayor precisión.

# Eventos — 20260821_mobileappservice_loadtest_503

## 2026-08-21 — Apertura de investigación

He recibido el reporte de Grido: errores 503 durante una prueba de carga contra MobileAppService, con mensaje de cliente "Unable to read data from the transport connection: An existing connection was forcibly closed by the remote host." He confirmado que Graylog no registra ningún 503 para la ventana reportada.

## 2026-08-21 — Confirmación de arquitectura de red

He confirmado que MobileAppService corre sobre IIS en `SFCG-MOBI-01`/`SFCG-MOBI-02` (no App Service PaaS), detrás de un Azure Load Balancer Standard (`SFCG-MOBI-LB`, `DefaultGroup01`) no documentado previamente. He corregido `docs/infrastructure.md`: la IP pública `20.121.19.174` pertenece al LB (`SFCG-MOBI-LB-publicip`), no directamente a la NIC de `SFCG-MOBI-01` como figuraba antes.

## 2026-08-21 — Revisión de configuración del LB

He relevado la única regla activa del LB (`SFCG-MOBI-LB-lbrule02`, TCP 8043→8043, `idleTimeoutInMinutes=15`) y su probe de salud asociado (`SFCG-MOBI-LB-probe02`, TCP puro, `numberOfProbes=1`). He confirmado que ambas VMs (`sfcg-mobi-01421`, `sfcg-mobi-02639`) integran el backend pool.

## 2026-08-21 — Detección de caída de Health Probe Status

Extraje la métrica `DipAvailability` del LB para la ventana de la prueba de carga (11:00–12:44 GMT) y detecté una caída puntual a 56.52%/62.5% entre las 12:07 y 12:08 GMT, coincidente con el arranque de `SFCG-MOBI-02`.

## 2026-08-21 — httperr.log y eventos WAS de `SFCG-MOBI-02`

He analizado el httperr.log y los eventos WAS de `SFCG-MOBI-02` para la ventana 12:04–12:11 GMT: confirmé dos reinicios de WAS (12:06:37 y 12:07:46 GMT) y 9 respuestas HTTP 503 reales emitidas por IIS entre las 12:07:20 y 12:07:21 GMT, generadas por el probe TCP del LB promoviendo la instancia a "healthy" antes de que IIS estuviera lista para servir tráfico. `SFCG-MOBI-02` se encendió después del reporte original de Grido — por lo tanto, este hallazgo no explica el incidente original y quedó fuera de alcance de este ticket (deuda técnica preexistente, documentada en `docs/infrastructure.md`).

## 2026-08-21 — Descarte de recycling de application pool en `SFCG-MOBI-01`

He ejecutado `Get-WinEvent` contra `Microsoft-Windows-WAS` en `SFCG-MOBI-01` para la ventana 12:04–12:11 GMT: cero eventos. He descartado el recycling de application pool como causa en esa instancia.

## 2026-08-21 — Confirmación de `connectionTimeout=15s`

He confirmado `connectionTimeout=00:00:15` en el sitio MobileAppService, idéntico en `SFCG-MOBI-01` y `SFCG-MOBI-02` — muy por debajo del default de IIS (120s). He confirmado que es una configuración deliberada de hardening de seguridad, no un error de configuración.

## 2026-08-21 — Confirmación de ausencia de dispositivo L7 en el camino de red

He confirmado que `WAF_APPs` (Application Gateway) no está conectado a MobileAppService — sólo enruta WebSite/ClubGrido. El camino real de MobileAppService es NSG (allow-list IP a IP uno a uno) → `SFCG-MOBI-LB` (L4) → IIS, sin ningún componente con capacidad de generar un código de estado HTTP salvo IIS mismo.

## 2026-08-21 — Prueba definitiva: cero 503 reales en el incidente original

He escaneado la totalidad de los archivos `httperr*.log` rotados en `SFCG-MOBI-01` para la ventana 2026-08-21T11:00:00Z–12:06:37Z (inicio de la prueba de carga hasta el arranque de `SFCG-MOBI-02`): 969 entradas totales, 0 con `sc-status=503`. He confirmado que el incidente original no involucró ningún 503 real — el mecanismo es un reset de conexión por `Timer_ConnectionIdle`, que la herramienta de prueba de carga de Grido clasifica como "503" en su propio reporte.

## 2026-08-21 — Cierre del ticket

He redactado `ops.md` con la causa raíz confirmada y la acción propuesta: dado que `connectionTimeout=15s` es deliberado, la corrección corresponde al cliente de prueba de carga de Grido (y potencialmente al cliente mobile productivo) — debe tolerar el cierre de una conexión pooled inactiva y reintentar automáticamente sobre una conexión nueva.

## 2026-08-21 — Re-auditoría de `sfcgnetsec01` y corrección de atribución de IP

He re-auditado las reglas inbound de `sfcgnetsec01` para el puerto 8043 y he confirmado dos reglas activas: `Allow-SmartFran-MobileApp` (P111, 14 IPs) y `Grido-Mobile-Allow` (P113, 9 IPs, incluye `172.191.0.208`). He identificado, vía `~/Documentos/git/smartfran-documentacion/sml-sf-mobile.md`, que `172.191.0.208` corresponde a "APIM Grido" — la IP de egreso del Azure API Management de Grido, no una máquina de prueba de carga directa. He corregido la atribución en `investigation.md` y he precisado la acción propuesta 1 de `ops.md` para apuntar la coordinación de reintentos al nivel de ese APIM.

He detectado además una diferencia entre las IPs en vivo de ambas reglas (`Allow-SmartFran-MobileApp`, `Grido-Mobile-Allow`) y la lista "Limpio" documentada en `sml-sf-mobile.md` (14 vs. 3, y 9 vs. 3 respectivamente). He documentado la comparación en `docs/azure_nsg.md` como candidato de revisión separado, fuera del alcance de este ticket.

## 2026-08-21 — Corrección: `smartfran-documentacion` no es una fuente confirmada de estado actual

`smartfran-documentacion` no debe tratarse como documentación actualizada — el trabajo activo está en `bots/`, que puede tener datos más recientes. He revertido el tono de "confirmado" a "reportado, no verificado de forma independiente" en `docs/azure_nsg.md`, `.claude/commands/loyalty-azure-lb.md`, `investigation.md` y el ítem 1 de acciones propuestas de `ops.md`, tanto para la atribución de `172.191.0.208` como "APIM Grido" como para la comparación de desvío de IPs contra la lista "Limpio". He actualizado la memoria de referencia sobre ese repositorio con la misma advertencia de vigencia.

## 2026-08-21 — Cierre del ticket

He cerrado el ticket. La prueba de carga posterior se completó sin cambios de infraestructura de nuestro lado (`connectionTimeout` sin modificar, sin cambios en el LB/probe). No confirmé si esa corrida tuvo cero resets de conexión o sólo un volumen tolerado. He actualizado el campo `Resuelto` de `ops.md` y el estado de `investigation.md` a cerrado, dejando la acción propuesta 1 (coordinación con Grido) como seguimiento abierto no bloqueante.

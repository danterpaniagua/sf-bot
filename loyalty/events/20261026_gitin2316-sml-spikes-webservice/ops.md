# GITIN-2316 Sml Spikes. Webservice

**Tags:** SmartLoyalty, SEGURIDAD, SRE, PROD

## Qué pasó
- El 2026-10-26, entre las 21:22 y las 21:27 (UTC-3), `SFCG-WEBS-01` recibió entre 56 y 359 requests GET por segundo; su valor habitual es cerca de 0,07 GET/s y el servicio recibe casi solo POST (2 a 6 req/s).
- `SFCG-WEBS-02` y `SFCG-WEBS-03` no recibieron ese pico (GET máximo 0,12 req/s en la misma ventana).
- La CPU de `SFCG-WEBS-01` llegó a 24 % como máximo en la ventana de las 21:00 a las 21:52 (UTC-3).

## Resumen
El 2026-10-26 entre las 21:14 y las 22:00 (UTC-3), una única dirección IP pública (`181.116.88.166`, red de AMX Argentina / Claro según el registro RDAP de LACNIC) hizo 133.048 requests GET contra el sitio del WebService en `SFCG-WEBS-01` (puerto 8080, `W3SVC2`). El 99,97 % recibió 404, repartidos en una gran cantidad de rutas distintas (nombres de archivos y carpetas de administración, copias de respaldo y configuración, y una prueba tipo `/render/https:/www.google.com`). El pico de tasa fue de unos 330 req/s entre las 21:21 y las 21:27 (UTC-3). No se vio ningún 200 ni 500 de esa IP. Solo `SFCG-WEBS-01` lo recibió, lo que es coherente con la distribución por IP de origen del Load Balancer. No se determinó quién es el origen ni si fue una prueba autorizada. En `SFCG-WEBS-01` se aplicó Dynamic IP Restrictions en modo solo registro.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2316](https://smartit-ar.atlassian.net/browse/GITIN-2316) |
| Caso | Barrido de rutas por GET desde una única IP contra el WebService (`SFCG-WEBS-01`) |
| Base de datos | NA |
| Severidad | No determinada |
| Detectado | 2026-10-26 21:14 a 22:00 (UTC-3), según el log de IIS de la IP |
| Resuelto | Pendiente |
| Responsable | SRE |

## Causa raíz
El pico de GET corresponde a un barrido de rutas y archivos desde una única IP pública, que generó 133.048 requests en unos 46 minutos, 66.523 de ellos entre las 21:20 y las 21:29 (UTC-3). No se determinó quién es el origen ni si fue un ataque o una prueba autorizada. No se identificó una ocurrencia anterior.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Una única IP (`181.116.88.166`) hizo 133.048 GET en el log del día (00:14:02 a 01:00:20 UTC); 133.011 fueron 404. En la ventana 00:20 a 00:29 UTC fueron 66.523 de los 66.558 GET del log, con picos de 19.627 y 19.755 requests por minuto. Solo método GET. | Medio |
| H2 | Respuestas distintas de 404 de esa IP: 403 para `/`, `/service/` y `/config/`; 301 para `/config` y `/service`; 400 para 26 rutas `/render/https:/www.google.com` con distintas extensiones (también bajo `/service/` y `/config/`). Ningún 200 ni 500. El barrido pudo saber que existen carpetas `service` y `config` en el sitio; no se revisó su contenido ni si se sirven archivos por nombre. | Medio |
| H3 | El pico llegó solo a `SFCG-WEBS-01`; `SFCG-WEBS-02` y `SFCG-WEBS-03` no tuvieron GET por encima de 0,12 req/s. Coherente con la distribución `SourceIP` del Load Balancer (no se leyeron los logs de IIS de esos dos servidores). | Bajo |
| H4 | La CPU de `SFCG-WEBS-01` no siguió al barrido: máximo 24 % a las 21:21 (UTC-3), con promedio de 4 % en la ventana. El pico de CPU de las 21:21 no queda explicado por el barrido (el log muestra solo 4 GET a las 21:20 UTC-3). | Bajo |
| H5 | El tráfico legítimo máximo por IP y por segundo en `SFCG-WEBS-01` fue de 5 requests (logs del 26 y 27 de octubre en UTC, sin el barrido ni la prueba). | Informativo |
| H6 | Con Dynamic IP Restrictions (100 requests por 1.000 ms, solo registro), una prueba de 800 requests a 925 req/s dejó 108 marcados con sub-estado 502 y 692 con sub-estado 0, todos con respuesta 404. En este modo la detección se ve solo en el log de IIS; ningún registro de eventos de IIS tiene datos. | Informativo |

## Endpoints solicitados

Lista parcial, con lo que ya está en los datos del evento. El total de rutas distintas pedidas por la IP no se calculó. Como ninguna ruta fuera de las 15 de abajo tuvo más de 3 pedidos, en la ventana de 00:20 a 00:29 UTC el barrido pidió como mínimo unas 22.000 rutas distintas (unos 66.450 pedidos del barrido sin contar las rutas de la tabla, divididos por 3).

**Las 15 rutas más pedidas, de 00:20 a 00:29 UTC (21:20 a 21:29 UTC-3), todos los clientes** (en esa ventana hubo 66.558 GET; cada ruta de abajo tiene de 3 a 35 pedidos):

| Ruta | Pedidos | Origen |
|---|---|---|
| `/healthcheck.ashx` | 35 | Sondeo del Load Balancer (`168.63.129.16`), no es parte del barrido |
| `/dns-query` | 16 | Barrido |
| `/service/dns-query` | 12 | Barrido |
| `/render` | 9 | Barrido |
| `/service/render` | 7 | Barrido |
| `/ADMIN.zip`, `/ADMIN.xml`, `/ADMIN.txt`, `/ADMIN.json`, `/ADMIN.config`, `/ADMIN.bak`, `/ADMIN.aspx` | 3 cada una (21 en total) | Barrido |
| `/Security.txt` | 3 | Barrido |
| `/service/README.svc` | 3 | Barrido |
| `/service/SiteMap.xml` | 3 | Barrido |

**Rutas de la IP que no devolvieron 404, en todo el día (37 pedidos, de 133.048):**

| Ruta | Estado | Pedidos |
|---|---|---|
| `/` | 403 | 3 |
| `/service/` | 403 | 3 |
| `/config/` | 403 | 2 |
| `/config` | 301 | 2 |
| `/service` | 301 | 1 |
| `/render/https:/www.google.com` y variantes `.aspx .zip .bak .txt .xml .json` | 400 | 7 |
| `/service/render/https:/www.google.com` y variantes `.asmx .aspx .svc .xml .json .txt` | 400 | 13 |
| `/config/render/https:/www.google.com` y variantes `.json .aspx .xml .txt .bak` | 400 | 6 |

El resto, 133.011 pedidos, devolvió 404. La mayoría son rutas distintas con muy pocos pedidos cada una; la lista completa y el conteo de rutas distintas siguen pendientes.

## Recursos afectados

| Recurso | Detalle |
|---|---|
| `SFCG-WEBS-01` (sitio `W3SVC2`, puerto 8080) | Recibió el barrido. Regla de Dynamic IP Restrictions aplicada en modo solo registro. |
| `SFCG-WEBS-02`, `SFCG-WEBS-03` | Sin el pico de GET según Zabbix. Sin cambios. |

## Acciones Tomadas

| # | Hora (UTC) | Acción |
|---|---|---|
| 1 | 2026-10-27 00:52 | Consulta de solo lectura de Zabbix (GET, POST, Total y CPU) de `SFCG-WEBS-01`, `-02` y `-03` entre las 21:00 y las 21:52 (UTC-3). |
| 2 | 2026-10-27 entre 01:00 y 01:30 (hora exacta no registrada) | Lectura del log de IIS de `SFCG-WEBS-01` (`W3SVC2`): GET por IP, ruta, estado y minuto en la ventana, y todas las líneas de la IP de origen en el día. |
| 3 | Antes de 2026-10-27 01:14 (hora exacta no registrada) | En `SFCG-WEBS-01`: respaldo de la configuración de IIS (`before-gitin2316-dynip`) y Dynamic IP Restrictions en modo solo registro (100 requests por 1.000 ms; no bloquea). Aplicado a nivel de servidor. |
| 4 | 2026-10-27 01:14 y 01:15 | Prueba de la regla desde una estación de la red interna: 800 requests a una ruta inexistente; 108 quedaron marcados (sub-estado 502) y no se bloqueó ninguno. |
| 5 | 2026-10-27 (hora exacta no registrada) | Consulta del registro RDAP de LACNIC para la IP de origen. |

## Acciones propuestas

| # | Responsable | Acción | Estado |
|---|---|---|---|
| 1 | SRE | Pasar Dynamic IP Restrictions de `SFCG-WEBS-01` a modo bloqueo (`enableLoggingOnlyMode` en `false`, acción 403). El umbral actual (100 req/s) es unas 20 veces el pico legítimo medido (5 req/s). | Pendiente de aprobación |
| 2 | SRE | Aplicar la misma regla en `SFCG-WEBS-02` y `SFCG-WEBS-03` después de validar `SFCG-WEBS-01`. | Pendiente |
| 3 | SRE | Revisar el contenido de las carpetas `config` y `service` del sitio y si se sirven archivos por nombre. | Pendiente |
| 4 | SRE | Verificar si el barrido siguió después de las 22:00 (UTC-3) volviendo a leer el log. | Pendiente |
| 5 | SRE | Evaluar un bloqueo de la IP de origen en el NSG o en el Load Balancer. | Pendiente de decisión |
| 6 | SRE | Comparar la IP de origen con las IP públicas de los servicios de internet de la oficina para descartar un origen interno. | Pendiente |
| 7 | SRE | Si el origen no es propio, evaluar el reporte al contacto de abuso del proveedor. | Pendiente de decisión |
| 8 | SRE | Evaluar un WAF o un límite de tasa delante del Load Balancer. | Pendiente |

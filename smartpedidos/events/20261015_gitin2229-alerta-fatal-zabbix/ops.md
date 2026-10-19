# GITIN-2229 — [SP] Alerta FATAL Zabbix

**Tags:** `SmartPedidos`, `Platform`, `Obserbavilidad`, `SRE`, `PROD`

## Qué pasó

- Subtarea de [GITIN-2222](https://smartit-ar.atlassian.net/browse/GITIN-2222). Las tareas de platform-service se detienen cuando el proceso ejecuta `process.exit(1)` tras un rechazo de promesa no manejado, y Graylog registra el mensaje `[INFRA/FATAL] unhandled_rejection` en el momento de la salida: 63 mensajes en 14 horas el 14-10.
- La alerta de Zabbix creada en GITIN-2222 compara las tareas en ejecución con las deseadas usando promedios de 10 minutos de CloudWatch, por lo que no muestra el texto del error y un reemplazo rápido puede no verse.
- Hoy no existe una alerta en Zabbix basada en los mensajes FATAL de Graylog.

## Resumen

Se creó en Zabbix una alerta sobre los mensajes FATAL de platform-service en Graylog: un item consulta cada minuto la cantidad de líneas FATAL de los últimos 5 minutos, un trigger High se abre cuando hay al menos una y un trigger Average avisa si el item deja de recibir datos. La alerta se abrió y se recuperó con eventos reales y sus avisos llegaron al Chat de Operaciones y al grupo de Telegram; los títulos de las tarjetas y la etiqueta `env=PROD` quedaron aplicados. El mismo tratamiento para concentrador-service no es posible hoy porque ese servicio no registra mensajes FATAL; queda a cargo de Desarrollo (GITIN-1477) y se sigue en [GITIN-2240](https://smartit-ar.atlassian.net/browse/GITIN-2240). Un evento de las 19:04 UTC no generó avisos; la causa se investiga en GITIN-2222.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2229](https://smartit-ar.atlassian.net/browse/GITIN-2229) (subtarea de [GITIN-2222](https://smartit-ar.atlassian.net/browse/GITIN-2222)) |
| ID alerta | NA |
| Sistema | Zabbix (host `Zabbix server`), Graylog de SmartPedidos, platform-service |
| Severidad | High (trigger FATAL) y Average (sin datos) |
| Detectado | 2026-10-14 (63 mensajes FATAL en 14 horas) |
| Resuelto | Parcial: alerta de Platform creada y verificada con eventos reales; la de concentrador-service depende de Desarrollo |
| Responsable | SRE |

## Causa raíz

NA

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | En Graylog el campo `level` no es el nivel de la aplicación (la búsqueda `level:FATAL` devolvió 0 con 62 líneas FATAL presentes); el nivel está en `msg_level`. Las líneas FATAL de platform-service tienen `msg_level=FATAL`, `msg_category=INFRA` y `msg_service=platforms-service`. La consulta elegida es `msg_level:FATAL AND msg_service:"platforms-service"`. | Bajo |
| H2 | Las búsquedas de Graylog con texto libre combinado con `AND` devuelven HTTP 500 (`Missing search type result!`); con campos calificados responden 200. Se desconoce el motivo. | Bajo |
| H3 | En 7 días hubo 223 líneas FATAL, todas de platform-service; ninguna de concentrador-service. | Medio |
| H4 | concentrador-service no registra mensajes FATAL: en `api/src/index.js` (líneas 46 a 51, rama `develop`) el manejador de excepciones no capturadas está registrado con el nombre `'uncaughtException:'` (con dos puntos al final), por lo que no se ejecuta, y no se encontró ninguna llamada de log `[INFRA/FATAL]` en `api/src`. El contenido de los manejadores no se leyó en detalle. Una alerta por cantidad de FATAL no se dispararía para ese servicio. | Medio |
| H5 | El evento FATAL de las 19:04 UTC (recuperado a las 19:12) no generó avisos, a diferencia de los cinco anteriores. Los eventos no estaban suprimidos y tenían las mismas etiquetas de enrutamiento; la causa probable está fuera de los objetos de este ticket (grupo de usuarios del destinatario, GITIN-2222) y no está probada. | Alto |
| H6 | Los avisos iniciales mostraban los títulos sin resolver (`{EVENT.TAGS.SVC_FRIENDLYNAME}`) porque los triggers no tenían las etiquetas `SVC_FRIENDLYNAME` y `friendlyname`; con ellas aplicadas, la tarjeta de recuperación muestra "El servicio Graylog FATAL Platform se ha normalizado en Zabbix server". | Bajo |
| H7 | Al inicio la macro `{$SML_GRAYLOG_API_KEY}` del host `Zabbix server` estaba definida como texto plano (visible en el frontend y por API para quien tenga acceso al host). | Medio |

## Acciones Tomadas (hora UTC)

| # | Hora | Acción |
|---|---|---|
| 1 | 2026-10-15 13:11 a 13:17 | Lecturas de Graylog (conteos por rango y por consulta, campos de los mensajes) y de Zabbix (hosts, items HTTP existentes, macros) para elegir la consulta y el host del item. |
| 2 | 2026-10-15 13:21 | Macros `{$GRAYLOG.PLATFORM.FATAL.MAX}` (0) y `{$GRAYLOG.NODATA.WINDOW}` (10m) en el host `Zabbix server`. El primer intento de crear el item falló por el formato de las cabeceras HTTP; no quedó ningún item ni trigger. |
| 3 | 2026-10-15 13:24 | Item HTTP `graylog.platform.fatal.count` (cada minuto, rango de 300 s, autenticación básica con la macro de la clave de Graylog, valor leído de `total_results`) y triggers "Graylog: Platform FATAL detected" (High) y "Graylog: Platform FATAL check without data" (Average) en el host `Zabbix server`. A los 75 segundos el item estaba en estado normal con valor 0 y los triggers sin error. |
| 4 | 2026-10-15 15:33 a 17:55 | Tres eventos reales del trigger High (problema y recuperación de 5 minutos cada uno); los avisos de problema y de recuperación llegaron al Chat de Operaciones. Los títulos aparecían sin resolver (H6). |
| 5 | 2026-10-15 18:02 | Etiquetas `friendlyname` y `SVC_FRIENDLYNAME` ("Graylog FATAL Platform") en los dos triggers y en el prototipo de trigger ECS de GITIN-2222, con lectura posterior. |
| 6 | 2026-10-15 19:36 | Etiqueta `env=PROD` en los dos triggers FATAL y en el prototipo ECS, con lectura posterior (para que aparezcan en el dashboard). |
| 7 | 2026-10-15 20:23 en adelante | Eventos FATAL posteriores (recuperación de 20:23, problemas y recuperaciones hasta las 00:31 del 16-10) enviados por Zabbix al Chat y a Telegram; según lo informado, los avisos llegan en ambos canales (los mensajes de Telegram se vieron pegados en la conversación). |
| 8 | 2026-10-16 11:10 | Lectura de los triggers ECS descubiertos: tienen `env=PROD`, `friendlyname` y `SVC_FRIENDLYNAME` heredadas del prototipo. |

## Recursos afectados

| Componente | Estado |
|---|---|
| Zabbix, host `Zabbix server` | Item 54607, triggers 26919 y 26920 y las macros `{$GRAYLOG.PLATFORM.FATAL.MAX}` y `{$GRAYLOG.NODATA.WINDOW}` creados |
| Zabbix, prototipo de trigger ECS y triggers descubiertos | Etiquetas de título y `env=PROD` agregadas (GITIN-2222) |
| concentrador-service | Sin cambios; no registra FATAL |

## Acciones propuestas

| # | Responsable | Acción | Estado |
|---|---|---|---|
| 1 | Dev | Registrar una línea `[INFRA/FATAL]` en los manejadores de proceso de concentrador-service con el mismo esquema que Platform (`msg_level=FATAL`, `msg_category=INFRA`, `msg_service=concentrador-service`) y corregir el nombre del evento `'uncaughtException:'`. Si el proceso debe además terminar es decisión de Desarrollo. Relacionado con [GITIN-1477](https://smartit-ar.atlassian.net/browse/GITIN-1477). | Pendiente |
| 2 | SRE | Cuando concentrador-service registre FATAL, crear el mismo item y los mismos triggers para `msg_service:"concentrador-service"` ([GITIN-2240](https://smartit-ar.atlassian.net/browse/GITIN-2240)). | Pendiente |
| 3 | SRE | Verificar que la macro `{$SML_GRAYLOG_API_KEY}` esté definida como texto secreto (hoy se desconoce su tipo actual). | Pendiente |
| 4 | SRE | Cerrar la causa de la falta de avisos de las 19:04 UTC (GITIN-2222). | Pendiente |

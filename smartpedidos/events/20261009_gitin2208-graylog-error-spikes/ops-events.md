# Eventos — 20261009_gitin2208-graylog-error-spikes

## 2026-10-09 11:47 — Primer intento: histograma y términos de la API universal de Graylog

**Comando:** C1 — Histograma y términos de `search/universal` (`scripts.sh`, descartado)
**Resultado:**
`curl: (22) The requested URL returned error: 404` en el endpoint `histogram`. Salida en `data/run1-bad-tz/pull-log.txt`.

He confirmado que el Graylog 5.2.12 de `sf-monitoreo.smartfran.com:9000` no expone los endpoints `histogram` ni `terms` de la API universal. He reescrito la extracción para usar solo `search/universal/absolute` (conteos con `limit=1` y muestras de mensajes).

## 2026-10-09 11:50 — Conteos por hora y por 5 minutos, con ventanas desplazadas

**Comando:** C2 — Conteos por franja y muestras (`scripts.sh`)
**Resultado:**
Las franjas posteriores a las 08:50 devolvieron 0 y la muestra "antes de las 09:00" traía mensajes con marca de tiempo 14:01–14:49 UTC, es decir, de la hora actual. Salidas movidas a `data/run1-bad-tz/`.

He detectado que Graylog interpreta las fechas sin zona (`YYYY-MM-DD HH:MM:SS`) como UTC-3, por lo que todas las ventanas quedaron 3 horas adelantadas, y que los ceros eran tiempo futuro y no silencio. He cambiado el script a fechas ISO con `Z`.

## 2026-10-09 11:58 — Conteos corregidos y muestras por tramo

**Comando:** C2 — Conteos por franja y muestras (`scripts.sh`, fechas ISO)
**Resultado:**
La prueba inicial devolvió el mensaje más nuevo a 3 segundos del reloj. Conteo de `ERROR` por hora: base nocturna de 950 a 1.300; 08:00 4.215; 09:00 6.782; 10:00 4.255 (el día anterior, el aumento empezó a las 10:00). Por 5 minutos, ráfagas al inicio de cada media hora: 08:00 3.253, 09:00 2.076, 09:30 3.249, 10:00 1.263, 10:30 1.201, 11:00 998, 11:30 719. Salidas en `data/counts-*.tsv` y `data/sample-*.json`.

He verificado que los picos son ráfagas periódicas de 500 a 600 errores `Branch OpenClose Error` en un minuto (uno por sucursal), de `concentrador-service`, y no un aumento sostenido. El filtro de texto libre `ERROR` también cuenta líneas INFO y líneas IIS de otro sistema.

## 2026-10-09 12:07 — Línea de tiempo por tipo de error, hoy y ayer

**Comando:** C2 — Series de 5 minutos por tipo (`scripts.sh`, `COUNTS_ONLY=1`)
**Resultado:**
`openClosedBranchesGrido` (timeout de 20000 ms): 1.581 a las 08:00, 990 a las 09:00 y 1.543 a las 09:30; cero ayer entre las 07:00 y las 12:00 y cero hoy desde las 10:00. `enviarEstadoPedidosYa` (HTTP 400): ráfagas cada media hora desde las 10:00, con valores casi idénticos a los de ayer (1.123 contra 1.129 a las 10:00). Errores de token: 40 por franja de 5 minutos en ambos días. La serie de `checkOfflinePOS` devolvió 0 por un error de consulta (la frase entre comillas no coincide con los mensajes reales). Salidas en `data/counts-5min-*.tsv`.

He confirmado que solo las ráfagas de Grido son nuevas hoy; las de PedidosYa y el fondo de errores de token se repiten a diario.

## 2026-10-09 12:27 — Búsqueda de reinicios de concentrador-service

**Comando:** C3 — Señales de reinicio (`scripts-restarts.sh`)
**Resultado:**
Mensajes por minuto: 07:50–08:10 sin cortes (mínimo 8, una ráfaga de 3.192 a las 08:02); 09:00–09:35 con un minuto en cero a las 09:34, justo después de las ráfagas de 09:32 y 09:33; control 10:20–10:55 sin cortes (mínimo 24). Las 30 búsquedas de palabras de arranque o cierre devolvieron HTTP 500 de Graylog. Salidas en `data/restarts/`.

He observado un único corte de un minuto a las 09:34, compatible con una interrupción breve del servicio o de la entrega de sus logs, pero no he podido comprobar un reinicio: la búsqueda de arranque falló y no he revisado los eventos de ECS.

## 2026-10-09 17:25 — Redacción de ops.md

He redactado `ops.md` con las ráfagas de Grido y PedidosYa, el fondo de errores de token y la causa raíz en NA, con los reinicios y la causa de los timeouts de Grido como acciones pendientes.

## 2026-10-12 12:57 — Ajuste de scripts-restarts.sh

He modificado `scripts-restarts.sh` para que guarde el cuerpo del error de Graylog en `startup-terms-*.tsv`, de modo que la próxima ejecución muestre por qué la consulta devuelve HTTP 500. Todavía no la he vuelto a ejecutar.

# GITIN-2208 — [SP] ERROR en Graylog: picos de errores desde las 9 AM

**Etiquetas:** `SmartPedidos`, `Concentrador`

## Resumen

El 2026-10-09 se observaron picos de mensajes `ERROR` en el Graylog de SmartPedidos (filtro de texto libre `ERROR`). El análisis de los conteos por franja muestra que los picos no son un aumento sostenido de errores sino ráfagas que se repiten al inicio de cada media hora, generadas por el proceso de apertura y cierre de sucursales de `concentrador-service`: cada ráfaga contiene entre 500 y 600 errores, uno por sucursal, dentro de un mismo minuto. Hoy aparecieron además tres ráfagas de timeouts contra la integración de Grido (08:00, 09:00 y 09:30) que no ocurrieron ayer en el mismo horario y que no se repitieron desde las 10:00 (revisado hasta cerca de las 12:10). Desde las 10:00 se repiten las ráfagas de errores HTTP 400 de PedidosYa, con valores casi idénticos a los de ayer. Además hay un fondo constante de errores de token. Las horas son locales (UTC-3).

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2208](https://smartit-ar.atlassian.net/browse/GITIN-2208) |
| ID alerta | NA |
| Sistema | Graylog (SmartPedidos / SmartLoyalty), `concentrador-service` |
| Severidad | Por definir con Operaciones (impacto en sucursales no verificado) |
| Detectado | 2026-10-09, picos desde las 08:00 (conteos de Graylog) |
| Resuelto | No. Las ráfagas de Grido no se repitieron desde las 10:00 pero su causa no está identificada; las ráfagas de PedidosYa y el fondo de errores de token continúan |
| Responsable | SRE (análisis); Dev (proceso de apertura/cierre) |

## Causa raíz

NA

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Tres ráfagas de timeouts de `openClosedBranchesGrido` (error `timeout of 20000ms exceeded`, código ECONNABORTED): 1.581 mensajes en la franja de 5 minutos de las 08:00, 990 en la de las 09:00 y 1.543 en la de las 09:30 (4.114 en total). Cada ráfaga abarca unas 500 a 600 sucursales distintas dentro de un minuto. No hubo mensajes de este tipo ayer entre las 07:00 y las 12:00 ni hoy desde las 10:00. | Medio |
| H2 | Ráfagas de `enviarEstadoPedidosYa` con respuesta HTTP 400 (más algunos 404 y 409) cada media hora desde las 10:00: 1.123, 1.052, 769 y 577 mensajes en las franjas de las 10:00, 10:30, 11:00 y 11:30 de hoy, contra 1.129, 1.061, 801 y 604 ayer. Es un patrón diario y no una novedad de hoy. Cada ráfaga abarca unas 570 sucursales. El mensaje de log no incluye el cuerpo de la respuesta de PedidosYa. | Medio |
| H3 | Fondo constante en ambos días: `No authorization token was found` y `Platform Auth Error: TOKEN_MISSING GET /api/branches/news` (40 mensajes de token por franja de 5 minutos, hoy y ayer) y fallos de token de MercadoPago (`mercadopago_token_fetch failed`). No se determinó qué servicio emite los de `GET /api/branches/news`. | Medio |
| H4 | Los conteos horarios de `ERROR`: base nocturna de 950 a 1.300 por hora. Ayer el aumento empezó a las 10:00 (3.820); hoy empezó a las 08:00 (4.215) y la hora de las 09:00 llegó a 6.782, similar al pico de ayer a las 22:00 (6.905). | Medio |
| H5 | El filtro de texto libre `ERROR` sobrecuenta: cada falla de Grido genera además una línea de nivel INFO (`http_response`) que contiene la palabra, y coincide con líneas IIS de otro sistema (SmartLoyalty). Por eso las franjas de las ráfagas de Grido muestran el doble de mensajes que los errores reales (3.253, 2.076 y 3.249). Un filtro por el campo `level` del JSON excluiría ambos casos. | Bajo |
| H6 | En la ventana de 07:50 a 08:10, el volumen de logs de `concentrador-service` por minuto estuvo entre 8 y 19 mensajes salvo el minuto de las 08:02 (3.192 mensajes, la ráfaga de Grido); no hay un corte hacia cero. La misma verificación de las ventanas 09:00 a 09:35 y 10:20 a 10:55 queda pendiente. | Bajo |

## Recursos afectados

| Componente | Impacto |
|---|---|
| concentrador-service | Proceso de apertura y cierre de sucursales: errores de timeout con Grido y respuestas HTTP 400 con PedidosYa en ráfagas cada media hora. El efecto sobre el estado real (abierto o cerrado) de las sucursales en esas plataformas no se verificó. |
| platforms-service | Aparece en los logs de error junto con concentrador (261 de 3.000 mensajes en una muestra de las 11:00 a 11:49); no se determinó qué proporción corresponde a los errores de token. |
| Graylog (sf-monitoreo) | Los conteos del filtro `ERROR` se inflan por las líneas INFO y las líneas IIS que contienen la palabra. |

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | `scripts.sh` (histograma y terminos de la API universal) | Descartado: Graylog 5.2.12 respondió 404 para esos endpoints |
| C2 | `scripts.sh` (conteos por franja y muestras de mensajes; modo `COUNTS_ONLY` con `TAG` para la serie por tipo, hoy y ayer) | Conteo de `ERROR` por hora y por 5 minutos, muestras para agrupar por servicio y mensaje, y serie por tipo de error contra ayer. Salidas en `data/` |
| C3 | `scripts-restarts.sh` | Buscar señales de reinicio o despliegue de `concentrador-service` en las ventanas de los picos y en una ventana de control. Salidas en `data/restarts/` (la ventana de 07:50 a 08:10 está completa por minuto; el resto, pendiente) |

## Acciones propuestas

1. (SRE) Completar la verificación de reinicios o despliegues de `concentrador-service` en las ventanas de 09:00 a 09:35 y de control, y revisar los eventos del servicio en ECS de la mañana del 2026-10-09 entre las 07:50 y las 09:35. El script está listo.
2. (Dev) Revisar `openClosedBranchesGrido`: qué llama a Grido, por qué lanza unas 500 solicitudes simultáneas en un minuto con un timeout de 20 segundos, y si conviene limitar la concurrencia o agregar reintentos con espera. Confirmar con Grido si su servicio tuvo problemas a las 08:00, 09:00 y 09:30.
3. (Dev) Revisar los HTTP 400 de `enviarEstadoPedidosYa` (unas 570 sucursales cada media hora desde las 10:00, todos los días) y registrar el cuerpo de la respuesta de PedidosYa en el log para poder identificar la causa.
4. (Dev) Revisar el origen de `No authorization token was found` y `TOKEN_MISSING GET /api/branches/news`, y de los fallos de token de MercadoPago, que se repiten de forma constante.
5. (SRE) Proponer a Operaciones usar el campo `level` del JSON en lugar del texto libre `ERROR` para las búsquedas y los tableros, y evaluar una alerta sobre ráfagas por franja de 5 minutos. No está decidido.
6. (Operaciones) Informar si hubo sucursales con estado incorrecto (abiertas o cerradas) en Grido o PedidosYa durante la mañana de hoy.

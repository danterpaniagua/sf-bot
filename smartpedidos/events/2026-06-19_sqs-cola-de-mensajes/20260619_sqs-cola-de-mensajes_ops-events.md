# Eventos — 20260619_sqs-cola-de-mensajes

## 2026-06-19 22:33 — Exportación de logs desde Graylog

Exportación de logs del período del evento desde Graylog. Dos archivos: nivel ERROR (5.741 filas) y todos los niveles (100.040 filas). Filtro aplicado: servicio SmartPedidos, ventana temporal alineada al período de alerta. Captura de métricas `ApproximateAgeOfOldestMessage` y `Tareas Corriendo` desde panel de Grafana (22:36 ART). En el momento de la captura la cola ya había recuperado estado normal (current = 0).

## 2026-06-22 — Análisis de logs — breakdown inicial

Análisis del CSV de errores (5.741 filas, todas de `platforms-service`). Distribución: INFRA 2.881 / ORDER 2.824 / INTEGRATION 36. Dos señales dominantes: `TOKEN_MISSING GET /api/branches/news` (2.879) y `order_processing failed platform=MercadoPago` (2.576). Los 5.741 errores pertenecen exclusivamente a `platforms-service` — no hay registros de `concentrador-service` en el filtro de Graylog.

## 2026-06-22 — Análisis MercadoPago — correlación con pico SQS

Todos los `order_processing failed` de MercadoPago son webhooks `topic=delivery` (`/shipments/{id}`), `attempts=1`, `actions=[]`. Tres subtipos de error identificados: (1) sin mensaje de error — webhook sin orden asociada, (2) `TypeError: Cannot read properties of undefined (reading 'cloud')` en `mercadoPago.js:227`, (3) `ReferenceError: t0 is not defined` en `tokensCloud.js:134`. Volumen horario UTC: 23:00 → 315, 00:00 → 741, 01:00 → 568 — correlaciona con el pico de Grafana (316 s a las 01:00 UTC).

## 2026-06-22 — Análisis de 401 en proximity-integration

`order_data_fetch failed platform=MercadoPago`: 109 errores, todos HTTP 401 sobre `https://api.mercadopago.com/proximity-integration/v1/orders/{id}`. 14 pedidos únicos con 8–10 reintentos cada uno. Primera ocurrencia: 16:11:40 UTC del 19/06. El error persiste hasta las 01:31 UTC del 20/06. Diagnóstico: credencial de `proximity-integration` vencida, sin rotación durante el evento.

## 2026-06-22 — Análisis FIFO — message groups bloqueados

`setNews_processing failed consumer=parent`: 99 errores, 90 `message_group_id` únicos bloqueados. 10 grupos con 2–3 reintentos cada uno. Error: `"The news does not meet the transition requirements"`. Primera ocurrencia: 13:41 UTC. Grupos repetidos entre 13:41 y 15:07 UTC — el consumer FIFO de concentrador reintenta mensajes que no pueden avanzar en la máquina de estados de novedades.

## 2026-06-22 — Análisis del CSV completo (All levels)

100.040 eventos, todos `platforms-service`. Cuatro hallazgos adicionales respecto al CSV de errores: (1) `token_fetch` HTTP 204 de MP para `user_id: 743414862` en 18:43 y 23:40 UTC — confirma causa raíz del `ReferenceError: t0 is not defined` en `tokensCloud.js:134`; (2) los 358 `receiveOrder` de MercadoPago (pedidos nuevos) son todos exitosos (HTTP 200) — los fallos son exclusivamente sobre webhooks de entrega, no sobre ingesta de pedidos; (3) `uber_cron_tick` a 180–192 ticks/min en la ventana 01:00–01:34 UTC vs. tasa normal de 60/min — platform-service operó con ~3 instancias ECS durante el pico; (4) todos los `http_response` de todas las plataformas retornaron HTTP 200 — sin degradación externa confirmada.

## 2026-06-22 — Brecha de visibilidad identificada

El filtro de Graylog "SmartPedidos" no incluye logs de `concentrador-service`. El comportamiento del consumer SQS FIFO durante el evento (excepciones, timeouts, dead letter) no es observable con los datos actuales. Se requiere extracción de logs de concentrador para el período 23:00–01:30 UTC.

## 2026-06-22 — Cierre de análisis y generación de artefactos

Generación de `20260619_sqs-cola-de-mensajes_ops.md` con hallazgos, causa raíz y acciones propuestas. Evento cerrado para análisis — remediaciones de código y operacionales pendientes de ejecución por los equipos responsables.

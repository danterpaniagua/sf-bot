# SQS — Cola de mensajes `PRD_BranchMessages.fifo` con edad elevada

## Resumen

El 19 de junio de 2026 a partir de las 22:00 ART, la métrica `ApproximateAgeOfOldestMessage` de la cola SQS FIFO `PRD_BranchMessages.fifo` alcanzó un pico de 316 segundos, indicando mensajes bloqueados sin consumir en el lado del concentrador. El origen se encuentra en el procesamiento de webhooks de entrega de MercadoPago: una credencial vencida en la API `proximity-integration` comenzó a devolver 401 a las 16:11 UTC, y dos defectos de código preexistentes en el handler de webhooks (`tokensCloud.js` y `mercadoPago.js`) hicieron fallar el procesamiento de 2.576 notificaciones de entrega durante la hora pico de cena (23:00–01:00 UTC). Los fallos acumulados en el estado de novedades bloquearon 90 message groups en el consumer FIFO del concentrador, envejeciendo los mensajes hasta el pico observado. La cola se recuperó de forma autónoma antes de las 01:36 UTC del 20 de junio.

## Tabla resumen

| Campo | Valor |
|---|---|
| ID alerta | — (detección manual vía Grafana) |
| Sistema | SmartPedidos — platforms-service / concentrador-service |
| Cola SQS | `PRD_BranchMessages.fifo` |
| Severidad | Alta |
| Detectado | 2026-06-19 22:00 ART (01:00 UTC 2026-06-20) |
| Recuperado | 2026-06-20 ~01:36 UTC (confirmado en Grafana, current = 0) |
| Investigado | 2026-06-22 |
| Estado | Cerrado — acciones de remediación pendientes |
| Responsable | Dante Paniagua |

## Causa raíz

La credencial de la API `proximity-integration` de MercadoPago venció a las 16:11 UTC del 19 de junio, devolviendo 401 en los fetches de datos de pedido. Esta condición de error se superpuso con dos defectos de código en el handler de webhooks de entrega: `tokensCloud.js:134` no maneja la respuesta HTTP 204 del endpoint de token de MP antes de usar la variable de token (produciendo `ReferenceError: t0 is not defined`), y `mercadoPago.js:227` no protege con null-guard la lectura del atributo `.cloud` en el resultado de la consulta de configuración de sucursal (produciendo `TypeError: Cannot read properties of undefined`). Durante la hora pico (23:00–01:00 UTC), el volumen de webhooks de entrega amplificó ambos defectos: 2.576 webhooks `topic=delivery` fallaron sin procesar, dejando las novedades asociadas en estado inconsistente. El consumer FIFO del concentrador, operando con una sola tarea ECS sin autoscaling configurado para profundidad de cola, acumuló 90 message groups bloqueados hasta que la carga natural de tráfico cedió.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Credencial `proximity-integration` de MercadoPago vencida desde las 16:11 UTC — `order_data_fetch` devuelve 401. 14 pedidos únicos con 8–10 reintentos cada uno. | Alto |
| H2 | `tokensCloud.js:134` — `ReferenceError: t0 is not defined` cuando el endpoint de token de MP responde HTTP 204 (sin contenido). Confirmado para `user_id: 743414862` en 18:43, 18:44 y 23:40 UTC. Ruta de error no manejada. | Alto |
| H3 | `mercadoPago.js:227` — `TypeError: Cannot read properties of undefined (reading 'cloud')` — consulta de configuración de sucursal retorna `undefined` sin null-guard. Afecta webhooks de entrega de usuarios no registrados. | Medio |
| H4 | 2.576 webhooks `topic=delivery` de MercadoPago (`/shipments/{id}`) fallaron sin procesar. 375 shipments únicos afectados; pico de 741 errores/hora a las 00:00 UTC. Las actualizaciones de estado de entrega y tracking de conductor de esos pedidos se perdieron. | Alto |
| H5 | `setNews_processing failed consumer=parent` — 90 message groups únicos de `PRD_BranchMessages.fifo` bloqueados por transición de estado inválida en concentrador. Hasta 3 reintentos por group. | Alto |
| H6 | Concentrador con 1 tarea ECS durante todo el evento (min=1, max=1). Sin política de autoscaling basada en profundidad de cola. Platform-service escaló a ~3 instancias durante el pico (confirmado por `uber_cron_tick` a 3× la tasa normal). | Medio |
| H7 | Sin alarma en CloudWatch para `ApproximateAgeOfOldestMessage` en `PRD_BranchMessages.fifo`. El evento fue detectado manualmente por revisión de Grafana. | Medio |
| H8 | Sin logs de concentrador en la exportación de Graylog — el filtro "SmartPedidos" captura únicamente `platforms-service`. El comportamiento del consumer SQS durante el evento no es observable con los logs actuales. | Medio |
| H9 | TOKEN_MISSING: dos IPs internas de AWS (`172.31.24.5` y `172.31.59.252`) realizan `GET /api/branches/news` sin token JWT a razón de ~240 req/hora cada una (`Go-http-client/2.0`). | Bajo |

## Recursos afectados

| Componente | Impacto |
|---|---|
| `platforms-service` | Handler de webhooks de entrega de MercadoPago — 2.576 fallos de procesamiento; actualizaciones de estado de entrega y tracking perdidos |
| `concentrador-service` | Consumer FIFO `PRD_BranchMessages.fifo` — 90 message groups bloqueados; sin logs disponibles para análisis |
| Cola `PRD_BranchMessages.fifo` | `ApproximateAgeOfOldestMessage` pico 316 s a las 01:00 UTC |
| Integración MercadoPago | `proximity-integration` API con credencial vencida; endpoint de token devolviendo 204 para user_id 743414862 |

## Comandos ejecutados

Análisis: `20260619_sqs-cola-de-mensajes_scripts.py`

| # | Script / Herramienta | Propósito |
|---|---|---|
| C1 | Graylog — exportación CSV (ERROR) | Extraer 5.741 eventos de nivel ERROR del período 2026-06-19 |
| C2 | Graylog — exportación CSV (All) | Extraer 100.040 eventos de todos los niveles del mismo período |
| C3 | Grafana — captura panel Operaciones | Obtener métricas `ApproximateAgeOfOldestMessage` y `Tareas Corriendo` |
| C4 | scripts.py — análisis errores | Breakdown por servicio, categoría, mensaje; bucketing por hora UTC |
| C5 | scripts.py — análisis MercadoPago | Subtipo de errores, recursos únicos, conteo de reintentos, stack traces |
| C6 | scripts.py — análisis PERF | Latencias y códigos de status de `http_response` por plataforma y acción |
| C7 | scripts.py — análisis FIFO | Identificación de message_group_ids repetidos en `setNews_processing failed` |
| C8 | scripts.py — correlación token_fetch 204 | Vinculación de respuestas 204 del endpoint de token MP con errores `t0 is not defined` |
| C9 | scripts.py — `uber_cron_tick` por minuto | Verificación de instancias concurrentes de platform-service durante el pico |

## Acciones propuestas

1. **[Dev]** Corregir `tokensCloud.js:134` — agregar manejo de respuesta HTTP 204 antes de acceder a la variable de token. Cuando el endpoint de MP no retorna token (204), la función debe lanzar un error controlado o retornar `null`, no continuar hacia la derreferencia de `t0`.

2. **[Dev]** Corregir `mercadoPago.js:227` — agregar null-guard en la lectura de `.cloud` sobre el resultado de la consulta de configuración de sucursal. Si el resultado es `undefined` o `null`, registrar el webhook como no procesable y no propagar el TypeError.

3. **[SRE / Infra]** Rotar la credencial de la API `proximity-integration` de MercadoPago y configurar una alerta de vencimiento en el gestor de secretos (mínimo 30 días de anticipación).

4. **[SRE]** Crear alarma en CloudWatch: `ApproximateAgeOfOldestMessage > 60 s` en `PRD_BranchMessages.fifo` → notificación al canal de operaciones.

5. **[SRE / Infra]** Configurar política de autoscaling para el servicio ECS concentrador basada en `ApproximateNumberOfMessages` de `PRD_BranchMessages.fifo`. La ausencia de escalado dejó un único consumer para drenar los 90 message groups bloqueados.

6. **[SRE]** Extraer logs de concentrador del período 23:00–01:30 UTC para confirmar el comportamiento del consumer FIFO durante el evento. Evaluar añadir concentrador al filtro de Graylog "SmartPedidos" o crear un stream dedicado.

7. **[Dev / SRE]** Identificar el servicio o agente que usa las IPs `172.31.24.5` y `172.31.59.252` para consultar `GET /api/branches/news` sin cabecera JWT y corregir la autenticación.

## Hallazgos secundarios

| # | Hallazgo | Acción recomendada |
|---|---|---|
| S1 | Platform-service escaló a ~3 instancias durante el pico (confirmado por `uber_cron_tick` a 3× la tasa normal de 60/min). El autoscaling de platform funciona. El contraste con concentrador (1 tarea fija) es la brecha operacional principal. | Verificar que el target de autoscaling de platform-service esté correctamente definido y documentado |
| S2 | PedidosYa y MercadoPago concentraron el 61% de su tráfico diario en la ventana 23:00–01:30 UTC (hora pico de cena en ART). Este patrón es esperado pero amplifica cualquier defecto de procesamiento activo en esa ventana. | Considerar como referencia para dimensionamiento de recursos y ventanas de mantenimiento |
| S3 | No hay logs de UberEats con errores durante este evento. Los 141 `receiveOrder` de UberEats en el período resultaron exitosos (200). | Sin acción requerida |

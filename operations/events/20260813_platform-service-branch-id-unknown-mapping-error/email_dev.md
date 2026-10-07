Asunto: GITIN-1854 — Pérdida de documentos en Graylog por valores centinela no filtrados en log.js (platforms-service / concentrador-service)

Hola equipo,

Estamos viendo pérdida de documentos en Graylog (rechazo completo del documento por `mapper_parsing_exception` en OpenSearch, no solo un campo mal formateado) causada por un patrón recurrente en `log.js`'s `_stdout` (ambas copias, platforms-service y concentrador-service): solo omite un campo cuando su valor es `undefined`, pero no filtra valores centinela tipo string (`'unknown'`, `'error'`) ni corrige claves camelCase que no coinciden con las claves snake_case que la función desestructura explícitamente. Esos valores/campos terminan mapeados a tipos numéricos en OpenSearch y el documento completo se rechaza.

Call sites confirmados:

**platforms-service:**
- `api/src/utils/log.js`, método `_stdout` (líneas 20-37) — el filtro insuficiente en sí.
- Patrón `branchId ?? 'unknown'` en `platforms/management/strategies/newsTypeStrategy.js` (líneas 36, 70, 93, 143, 168, 203) y en cada subclase `orderStrategy/*` (`viewStrategy.js:53`, `branchRejectStrategy.js:45,58,96`, `platformRejectStrategy.js:97`, `retriveDriverStrategy.js:32,73`, `dispatchStrategy.js:47`, `receiveStrategy.js:39,65`, `confirmStrategy.js:36`, `readyStrategy.js:36,72`).
- `platforms/provider/aws.js:50` (`pushNewToQueue`) y `:380` (`pushAutoReplyToQueue`).

**concentrador-service:**
- `utils/httpClient.js:35` — interceptor de error de axios: `status: error.response?.status ?? 'error'`.
- `platforms/provider/aws.js:174,184,325,342`, `utils/tokensCloud.js:78`, `controllers/uberEats.js:76` — `status_code: ... ?? 'unknown'`.
- `controllers/branch.js` (8 sitios: líneas 5228,5268,5288,5301,5314,5327,5352,5402,5407) — mismo patrón `?? 'unknown'`.
- `controllers/branch.js:2819-2851`, función `sendClosedToPlatformsAfterRejectClosed` — loguea `branchId`/`platformId` en camelCase dentro del `catch`; `log.js` solo desestructura `branch_id`/`platform_id` (snake_case), por lo que ambas claves caen en el objeto catch-all `rest: {...}` sin filtrar.

**Fix solicitado:** en `log.js`'s `_stdout` (ambas copias), normalizar u omitir valores centinela tipo string antes de emitir un campo — no solo filtrar `undefined`. Esto resuelve de una sola vez los cuatro campos ya confirmados (`msg_branch_id`, `msg_rest_status`, `msg_rest_status_code`, `msg_rest_platformId`) y previene la misma falla para cualquier otro campo con un fallback similar.

**Hallazgo nuevo, aún sin causa raíz confirmada (2026-09-18):** el campo `msg_meta_newOrder_user_id` está recibiendo lo que aparenta ser una dirección de email real de cliente en lugar de un ID — mismo mecanismo de rechazo de documento. Dado que podría implicar exposición de PII en un campo no pensado para contenerla, pedimos que se priorice ubicar el punto de origen en el código (probablemente en el flujo de `newOrder`) y confirmar qué valor se está pasando ahí en lugar del ID esperado.

Referencia: GITIN-1854

Gracias,

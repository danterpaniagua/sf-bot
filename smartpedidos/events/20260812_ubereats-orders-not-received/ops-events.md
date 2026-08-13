# Eventos — 20260812_ubereats-orders-not-received

## 2026-08-12 — Apertura del evento

Reporte inicial: no se reciben órdenes de Uber Eats. Ticket Jira GITIN-1844 confirmado. Ubiqué el punto de entrada del webhook en platforms-service (`controllers/uberEats.js`) y documenté el flujo completo en `investigation.md`.

## 2026-08-12 — Consulta a `db.logerrors` descartada como fuente confiable

Confirmé mediante `db.logerrors.find(...)` sin filtro de plataforma que la colección no registra actividad de platforms-service en absoluto. Verifiqué en código (`utils/log.js`) que `mongoLogEnabled: false` por defecto — el logging va por stdout → Event Hub → Graylog, no por MongoDB. Los devs habían señalado "problema de logs"; confirmé que la fuente de datos consultada era la incorrecta, pero el problema de fondo resultó ser real (ver hallazgo siguiente).

## 2026-08-12 — Causa raíz identificada vía exportación de Graylog

Analicé dos exportaciones de Graylog (`All-Messages-search-result(2).csv`, 3.327 filas, ventana 18:00-19:00 UTC; `All-Messages-search-result(4).csv`, 15.821 filas, ventana 13:07-21:22 UTC). Hallazgo: 15.334 de 15.821 eventos son el mismo error `[ORDER/ERROR] UberEats getOrders general error` (`ReferenceError: body is not defined`, `dist/controllers/uberEats.js:285:38`), presente desde las 15:43:05 UTC y sin interrupción hasta el momento de la exportación (21:22 UTC, prácticamente en tiempo real). Los webhooks de Uber Eats llegan de forma continua durante toda la ventana (192 eventos `webhook_received`, el último a las 21:12:28 UTC) — la integración con Uber, el ALB y la validación de firma funcionan correctamente. Las confirmaciones de orden hacia POS (`receiveOrder`/`readyOrder`) se detienen por completo entre 18:45:41 y 21:14:53 UTC.

Causa raíz en código: bug de scoping en JavaScript en el catch por-orden dentro de `processUberQueue()` — `const body = element` está declarado dentro del bloque `try`, pero el bloque `catch` referencia `body.meta?.resource_id`, fuera de alcance. Cualquier error real de procesamiento de una orden dispara un segundo `ReferenceError` que enmascara el error original, escapa del bucle `for`, y aborta el ciclo completo antes de que se ejecute la limpieza de la cola en memoria (`ordenesUber`). La orden problemática — y todo lo encolado detrás de ella en esa instancia — queda bloqueada y se reintenta (y vuelve a fallar) en cada ciclo del cron (~5s), indefinidamente.

## 2026-08-12 — Regresión ubicada en historial de git

Identifiqué el commit que introdujo el bug mediante `git blame`/`git log -L` sobre el repositorio local de solo lectura: commit `81c7501` (2026-08-11 18:55:44 UTC), que agregó la referencia a `body.meta?.resource_id` en el catch. El commit anterior sobre este archivo era de un mes antes (2026-07-13), sin cambios en el medio.

## 2026-08-12 — Mitigación aplicada por el usuario

El usuario aplicó rollback del servicio ECS de platforms-service a la revisión de task definition previa al despliegue de `81c7501`. Usuario reporta que el flujo de órdenes volvió a funcionar tras el rollback. Pendiente: corrección del bug de scoping en el código fuente antes de un próximo despliegue, ya que el rollback no corrige la rama de desarrollo — un redespliegue sin el fix reproduciría el mismo problema.

## 2026-08-12 — Confirmación de timeline completo y de alcance limitado a Uber Eats

Confirmé vía historial de eventos de `aws ecs describe-services` el timeline completo: despliegue del código con el bug 12/08 13:07-13:09 UTC, primer error 15:43 UTC, bloqueo total desde 18:45 UTC, rollback 21:11-21:12 UTC, primera orden exitosa post-rollback 21:14:53 UTC. Confirmé además, con una exportación más amplia de Graylog (51.057 filas, 09:54-21:54 UTC, stream `SP_Platform`), que PedidosYa, Rappi, MercadoPago y PediGrido mantuvieron actividad continua durante toda la ventana del incidente — el problema estuvo aislado a la integración de Uber Eats.

## 2026-08-12 — Ticket redactado

Redacté el ticket completo (`ops.md`) con causa raíz, hallazgos, recursos afectados y acciones propuestas, referenciando GITIN-1844.

# 12-08-2026_platforms-service-ubereats-orders-blocked

**Tags:** SmartPedidos, Platform, Graylog, AWS, DEPLOY, PROD

## Resumen

El 12/08/2026 se reportó que no se estaban recibiendo órdenes de Uber Eats en las sucursales. La investigación confirmó que la recepción de webhooks de Uber Eats funcionó correctamente durante todo el incidente (ALB, validación de firma y OAuth sin problemas); la falla estuvo en el procesamiento interno de `platforms-service`, donde un defecto de código introducido el día anterior provocó un bloqueo progresivo hasta llegar a un corte total de aproximadamente 2 horas y media. Otras plataformas (PedidosYa, Rappi, MercadoPago, PediGrido) no se vieron afectadas — se confirmó actividad continua en todas ellas durante la misma ventana.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-1844 |
| ID alerta | — (reporte directo, sin alerta automática) |
| Sistema | platforms-service (SmartPedidos) |
| Severidad | Alta |
| Detectado | 2026-08-12 15:43 UTC (12:43 -03:00) — inicio de la degradación |
| Resuelto | 2026-08-12 21:11-21:12 UTC (18:11-18:12 -03:00) — mitigado vía rollback; corrección definitiva en código pendiente |
| Responsable | Dante Paniagua, SRE |

## Causa raíz

Un commit desplegado la mañana del 12/08/2026 (13:07-13:09 UTC / 10:07-10:09 -03:00) introdujo un bug de scoping de JavaScript en `controllers/uberEats.js`, dentro del ciclo de procesamiento por orden de `processUberQueue()`: la variable `body` se declara con `const` dentro del bloque `try`, pero el bloque `catch` la referencia (`body.meta?.resource_id`) fuera de su alcance. Cuando una orden dispara cualquier error real durante su procesamiento, el manejador `catch` genera un segundo error (`ReferenceError: body is not defined`) que enmascara el error original y escapa de todo el ciclo `for`, abortándolo antes de que se ejecute la limpieza de la cola en memoria (`ordenesUber`). La orden problemática — y todo lo encolado detrás de ella en esa instancia — queda bloqueada y se reintenta (con el mismo resultado) en cada ciclo del cron (~5 segundos), de forma indefinida. Cada una de las 5 réplicas de tarea de platforms-service mantiene su propia cola en memoria, por lo que el bloqueo se fue acumulando de forma independiente en cada una a medida que llegaban más órdenes, hasta que las cinco quedaron bloqueadas simultáneamente.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Bug de scoping en el `catch` de `processUberQueue()` (`controllers/uberEats.js`) — enmascara el error real de cada orden y aborta el ciclo completo de procesamiento antes de limpiar la cola en memoria. Causa raíz confirmada del incidente. | Alto |
| H2 | Diseño de cola en memoria (`ordenesUber`) sin persistencia — una sola orden problemática bloquea permanentemente todo lo encolado detrás en esa réplica, y cualquier reinicio de tarea pierde silenciosamente lo que esté en cola en ese momento. Defecto estructural independiente del bug puntual de H1. | Medio |
| H3 | Secreto de firma de webhook (HMAC-SHA256) hardcodeado como literal en el código fuente (`controllers/uberEats.js`) en lugar de credentials/secrets manager. No causal en este incidente — se confirmó que la validación de firma funcionó correctamente durante toda la ventana — pero es una vulnerabilidad de seguridad independiente. | Medio |

## Recursos afectados

| Componente | Impacto |
|---|---|
| platforms-service | Degradación progresiva desde 15:43 UTC; bloqueo total de órdenes Uber Eats entre ~18:45 UTC y 21:11 UTC (2h26m). Las 5 réplicas de tarea quedaron bloqueadas de forma acumulativa. |
| Integración Uber Eats | Webhooks recibidos correctamente durante toda la ventana (confirmado — sin interrupción), pero sin completar el flujo hacia POS de sucursal. |
| PedidosYa / Rappi / MercadoPago / PediGrido | Sin impacto — actividad continua confirmada durante toda la ventana del incidente. |
| concentrador-service | No implicado — el defecto está aislado al procesamiento interno de platforms-service, previo a cualquier interacción con concentrador. |

## Comandos ejecutados

Detalle completo en `scripts.sh`.

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | MongoDB `db.logerrors.find(...)` | Descartada como fuente confiable — platforms-service no escribe ahí (logging migrado a Graylog) |
| C2 | Graylog (stream `SP_Platform`) — exportación CSV | Confirmar actividad de Uber Eats y aislar el patrón de error `body is not defined` |
| C3 | Graylog (stream `SP_Platform`) — exportación CSV | Confirmar que otras plataformas no fueron afectadas durante la misma ventana |
| C4 | `git log` / `git blame` / `git log -L` sobre `controllers/uberEats.js` | Ubicar el commit que introdujo el bug de scoping |
| C5 | `aws ecs describe-services` (historial de eventos) | Confirmar timestamps exactos del despliegue original y del rollback |

## Acciones propuestas

1. **(Dev, urgente)** Corregir el bug de scoping en `controllers/uberEats.js` (~línea 159) — referenciar `element` en lugar de `body` en el `catch`, o declarar `body` fuera del bloque `try`. El rollback aplicado no corrige la rama de desarrollo; un redespliegue sin este fix reproduce el incidente.
2. **(Dev)** Revisar el manejo de errores del ciclo `processUberQueue()` para que una falla en una orden puntual no aborte el procesamiento de las órdenes encoladas detrás de ella en la misma réplica.
3. **(Dev)** Evaluar reemplazar la cola en memoria (`ordenesUber`) por un mecanismo persistente, dado que actualmente cualquier reinicio de tarea pierde silenciosamente las órdenes en tránsito (H2).
4. **(Dev)** Mover el secreto de firma de webhook de Uber Eats a credentials/secrets manager en lugar de mantenerlo como literal en el código fuente (H3).
5. **(SRE)** Una vez desplegado el fix, validar en Graylog que el patrón `body is not defined` no vuelve a aparecer tras el siguiente despliegue de `platforms-service`.

## Hallazgos secundarios

Durante el análisis del export ampliado de Graylog se observaron, fuera del alcance de este incidente: 4.050 ocurrencias de `connect ECONNREFUSED 127.0.0.1:3088` y 4.098 `Unhandled Rejection`, además de 2.880 `Platform Auth Error: TOKEN_MISSING GET /api/branches/news` (patrón ya conocido de `2026-06-19_sqs-cola-de-mensajes`). Ninguno de estos correlaciona con la ventana del incidente actual — a evaluar si ameritan una investigación separada.

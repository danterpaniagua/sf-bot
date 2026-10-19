**Asunto:** platform-service: reinicios de tareas por rechazos de promesa no manejados (GITIN-2222)

Hola equipo,

Les comparto lo que encontramos al revisar por qué se detienen tantas tareas de platform-service en producción, para que lo evalúen. Detalle completo en [GITIN-2222](https://smartit-ar.atlassian.net/browse/GITIN-2222).

**Qué vemos**
- Las tareas de platform-service del cluster `smartfran-pedidos-production` se detienen solas: las seis tareas detenidas que ECS conservaba el 14-10 tenían `EssentialContainerExited` y código de salida 1, sin intervención de un despliegue, del escalado ni del health check.
- En Graylog hay 63 mensajes `[INFRA/FATAL] unhandled_rejection` de platforms-service en 14 horas. En todos el rechazo lo lanza el propio código de registro de errores, no la llamada que falló originalmente.
- Las paradas por día pasaron de 5–17 hasta el 12-10 a 97 el 13-10 y 101 el 14-10. El item de Zabbix "AWS ECS Cluster: Task Count" (nominal 6, un punto por minuto) no baja de 6 entre el 08 y el 10-10 ni el 12-10, y muestra descensos repetidos desde el 13-10 a las 13:00 (-03:00).

**Qué creemos que pasa (tres puntos en `develop`, HEAD `dfb668e`)**

1. **`api/src/index.js` líneas 121–137, commit `b56d403` (08-10, en `develop` desde el 09-10).** `unhandledRejection` ahora registra un FATAL y llama `process.exit(1)`. Antes solo registraba y el proceso seguía. El registro de `uncaughtException` estaba mal escrito y nunca se disparaba; ahora sí. Con esto, cualquier rechazo no manejado reinicia la tarea.
2. **`SanitizeHeaders` se llama como función** (desde el refactor del 2026-09-21, commits `a22c9c7`, `43b4023` y `225f850`). `api/src/utils/sanitizeHeaders.js` exporta una clase con el método estático `sanitizeHeader`, pero 17 llamadas en 7 archivos todavía la usan como función: `controllers/rappi.js:61`, `platforms/management/platform/pedidosYa.js` (líneas 237, 358, 444, 503 y 565), `controllers/mercadoPago.js` (2), `controllers/uberEats.js` (1), `platforms/management/platform/mercadoPago.js` (3), `platforms/management/platform/uberEats.js` (4) y `utils/tokensCloud.js` (1). El refactor actualizó solo los llamadores de `rappi.js`, `rapiboy.js` y `thirdParty.js`. Eso lanza "Cannot call a class as a function" dentro de los argumentos de `Log.saveError`, es decir, dentro del manejo de errores: 40 de los 63 rechazos (30 desde `pedidosYa`, 10 desde `rappi`). En `platforms/management/platform/rappi.js` la llamada ya es correcta (`SanitizeHeaders.sanitizeHeader(options)`). Corrección posible: `sanitizeHeaders.sanitizeHeader(...)` en esas 17 llamadas.
3. **`JSON.stringify` sobre un error circular** (desde el commit del 2026-06-23). En `api/src/utils/log.js` línea 32, si el error no tiene `message` se serializa con `JSON.stringify(error)`; con un objeto que contiene el socket HTTP falla con "Converting circular structure to JSON": 23 de los 63 rechazos. Podría usarse el `serializeError` que ya existe en esa clase, o un stringify que maneje referencias circulares.

Sobre el momento en que empezó el aumento: la revisión `:271` de la task definition se desplegó el 13-10 a las 09:40 (-03:00) y los descensos empiezan a las 13:00. Que `:271` incluya el commit del 08-10 es una inferencia por las fechas; no verificamos qué commits contiene cada imagen.

**Qué no sabemos**
- Por qué fallan las llamadas que entran a esas rutas de error (en las ventanas previas a cada parada aparecen `order_processing failed platform=MercadoPago`, `Platform Auth Error: TOKEN_MISSING GET /api/branches/news` y `requestLastMile failed`). No lo investigamos.
- Si alguno de los `new Promise(async ...)` que SonarQube marca como bug en `pedidosYa.js` (L147, 266, 284, 407, 468, 525) y en `platforms/management/platform/rappi.js` (L134, 173, 228, 324, 427) llegó a lanzar en producción. Con el manejador del punto 1, un throw dentro de uno de esos ejecutores terminaría el proceso. Tampoco revisamos la comparación `===` que SonarQube marca como siempre falsa (`pedidosYa.js` L169, `platforms/.../rappi.js` L250).
- SonarQube, con el análisis actual, no reporta nada sobre las llamadas a `SanitizeHeaders` (revisamos `pedidosYa.js`, `platforms/.../rappi.js` y `controllers/rappi.js`). Probablemente porque las reglas activas son casi todas de estilo; no lo verificamos.

**Lo que proponemos que evalúen (ustedes deciden alcance y orden)**
- Corregir las llamadas a `SanitizeHeaders` y la serialización de `Log._stdout`, para que el manejo de errores deje de lanzar.
- Revisar si el manejador de `unhandledRejection` debe terminar el proceso o solo registrar, y si conviene que el `process.exit(1)` espere a un cierre ordenado.
- Revisar por qué fallan las llamadas a MercadoPago, PedidosYa y Rappi que llegan a esas rutas.

**Lo que ya cambiamos del lado de infraestructura (no toca el código)**
- Los avisos de SNS pasaron a configurarse para enviarse solo cuando una tarea se detiene, con el motivo (`stopCode`, `stoppedReason`) y el código de salida del contenedor. Falta confirmar con el primer aviso real que el formato llega como esperamos.
- Agregamos una alerta en Zabbix para tareas en ejecución por debajo de las deseadas, dirigida al Chat de Operaciones. El enrutamiento todavía no se confirmó con un aviso real.

Quedo atento por si necesitan los logs de Graylog o los datos de Zabbix.

Saludos,
Dante

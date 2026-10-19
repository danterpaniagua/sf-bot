# GITIN-2222 — [SP] Reinicios de tareas de Platform en ECS y exceso de avisos SNS

**Tags:** `SmartPedidos`, `Platform`, `AWS`, `Obserbavilidad`, `SRE`, `PROD`

## Qué pasó

- Las tareas de platform-service se detienen solas: las seis tareas detenidas que ECS conservaba el 14-10 tenían el código de parada `EssentialContainerExited` y el contenedor terminó con código de salida 1, sin intervención de un despliegue, del escalado ni del health check del balanceador.
- Las paradas por día de platform-service pasaron de 5–17 hasta el 12-10 a 97 el 13-10 y 101 el 14-10. En el item "AWS ECS Cluster: Task Count" de Zabbix (un punto por minuto, nominal 6) los descensos repetidos empiezan el 13-10 a las 13:00 (-03:00), con un mínimo de 3,8.
- Graylog muestra 63 mensajes `[INFRA/FATAL] unhandled_rejection` de platforms-service en 14 horas.
- Cada cambio de estado de cada tarea (ocho por tarea) llegaba por dos reglas de EventBridge y tres suscripciones de correo, y ningún correo traía el motivo.

## Resumen

Las tareas de platform-service del cluster `smartfran-pedidos-production` se estaban deteniendo solas, y los avisos de SNS (más de 6.500 correos en 10 días) llegaban sin el motivo, por lo que no se podía saber por qué. El análisis encontró que cada parada corresponde a un rechazo de promesa no manejado dentro del propio manejo de errores del código, que un manejador agregado el 08-10 convierte en `process.exit(1)`; la corrección del código queda para Dev. Del lado de infraestructura se hizo visible el problema: los avisos de SNS se limitaron a las tareas detenidas e incluyen el motivo y el código de salida, y se creó en Zabbix una alerta de tareas en ejecución por debajo de las deseadas, dirigida al Chat de Operaciones. El enrutamiento de esa alerta y el formato de los avisos nuevos todavía no se confirmaron con un aviso real.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2222](https://smartit-ar.atlassian.net/browse/GITIN-2222) |
| ID alerta | NA |
| Sistema | platform-service (ECS, cluster `smartfran-pedidos-production`), reglas EventBridge y topics SNS, Zabbix |
| Severidad | Por definir |
| Detectado | 2026-10-14 (el aumento de paradas empieza el 2026-10-13) |
| Resuelto | Parcial: avisos filtrados con motivo y alerta de Zabbix creada (enrutamiento pendiente de verificar); la causa en el código sigue sin corregir (Dev) |
| Responsable | SRE (avisos y alerta), Dev (corrección del código) |

## Causa raíz

Causa inmediata (confirmada): el proceso de platform-service termina con código 1 tras un rechazo de promesa no manejado que se produce dentro de la rama de manejo de errores, por dos fallas del código de registro: `SanitizeHeaders` es una clase con método estático y se invoca como función en las rutas de error de PedidosYa y Rappi (error "Cannot call a class as a function", 40 de los 63 eventos), y `Log._stdout` aplica `JSON.stringify` a un objeto de error con una referencia circular al socket HTTP (23 de los 63). Desde el commit del 08-10 (entró a la rama `develop` el 09-10 en un merge entre las 16:33 y las 17:42 -03:00), cualquier rechazo no manejado ejecuta `process.exit(1)`; antes solo se registraba y el proceso seguía. Esa combinación es consistente con que el aumento empiece el 13-10: la revisión `:271` de la task definition se desplegó ese día a las 09:40 -03:00 y los descensos de Task Count empiezan a las 13:00. Que `:271` contenga el commit del 08-10 es una inferencia por las fechas; no se verificó qué commits tiene cada imagen. Por qué fallan las llamadas que llegan a esas rutas de error (por ejemplo MercadoPago, PedidosYa, Rappi) no se investigó.

Ocurrencias anteriores: antes del 13-10 hubo paradas (5–17 por día entre el 04 y el 12-10) y un descenso aislado de Task Count el 11-10 a las 09:00 (mínimo 5,4 durante 15 minutos); no se analizó su causa ni se identificó un ticket anterior sobre el mismo síntoma.


## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Las tareas de platform-service se detienen solas: 6 tareas detenidas conservadas por ECS (14-10, 20:44 a 21:21 -03:00), todas de la revisión `:272`, con `EssentialContainerExited`, código de salida 1 y vida de 16 minutos a 2 h 43 min. Una de ellas (20:48:28 -03:00) coincide con el correo del topic SNS. Las tareas detenidas por el despliegue de las 09:38 (`:271` a `:272`) salieron con `ServiceSchedulerInitiated`, por lo que el código 1 por sí solo no distingue una caída. | Alto |
| H2 | Cuándo empezó: paradas por día de platform-service (eventos distintos, buzón del 04 al 14-10): 11, 17, 11, 5, 5, 12, 13, 12, 12 hasta el 12-10; **97 el 13-10 y 101 el 14-10**. Revisiones: `:270` desde el 08-10 09:45, **`:271` desde el 13-10 09:40**, `:272` desde el 14-10 09:38. El item "AWS ECS Cluster: Task Count" (sumatoria de las tareas del cluster, nominal 6, un punto por minuto, historia de 7 días) no baja de 6 el 08, 09, 10 y 12-10; el 11-10 tiene un episodio aislado a las 09:00 (mínimo 5,4, 15 minutos); desde el 13-10 las 13:00 hay descensos repetidos: 139 minutos por debajo de 5,95 el 13-10 (mínimo 3,8 entre las 22:00 y las 23:00) y 77 el 14-10 hasta las 23:16 (mínimo 4,8 a las 16:00). | Alto |
| H3 | Posible bug 1, agregado el 2026-10-08 (commit "improve error handling and logging in platform initialization", `api/src/index.js`): el manejador de `unhandledRejection` registra un FATAL y llama `process.exit(1)`. Antes solo registraba y el proceso seguía; el registro de `uncaughtException` estaba mal escrito (`'uncaughtException:'`) y nunca se disparaba, ahora se dispara con el mismo comportamiento. En `develop` desde el 09-10. | Alto |
| H4 | Posible bug 2, agregado el 2026-09-21: ese día `SanitizeHeaders` (`api/src/utils/sanitizeHeaders.js`) pasó de función a clase con el método estático `sanitizeHeader` (commits `a22c9c7`, `43b4023` y `225f850`; llegó a `develop` por los merges del 21 y 22-09) y se actualizaron solo algunos llamadores. Quedan 17 llamadas en 7 archivos que usan el import como función: `controllers/rappi.js` línea 61, `platforms/management/platform/pedidosYa.js` líneas 237, 358, 444, 503 y 565, `controllers/mercadoPago.js` (2), `controllers/uberEats.js` (1), `platforms/management/platform/mercadoPago.js` (3), `platforms/management/platform/uberEats.js` (4) y `utils/tokensCloud.js` (1). Cada llamada lanza `TypeError` dentro de los argumentos de `Log.saveError`; 40 de los 63 rechazos (30 desde `pedidosYa`, 10 desde `rappi`); las otras rutas no produjeron rechazos en la ventana revisada. Inofensivo hasta el cambio de H3. | Alto |
| H5 | Posible bug 3, agregado el 2026-06-23: `Log._stdout` (`api/src/utils/log.js` línea 32) usa `JSON.stringify(error)` cuando el error no tiene `message`; con objetos que contienen un socket HTTP falla con "Converting circular structure to JSON" (23 de los 63). El propio registro de errores lanza. | Alto |
| H6 | Las rutas de error se ejecutan muchas veces por minuto: en las ventanas previas a cada parada aparecen `order_processing failed platform=MercadoPago`, `Platform Auth Error: TOKEN_MISSING GET /api/branches/news` y `requestLastMile failed`. No se investigó por qué fallan esas llamadas. | Medio |
| H7 | Avisos SNS: cada tarea genera ocho cambios de estado y cada uno llegaba a dos topics por dos reglas (una de ellas, `ECS-Task-Definition-Version-Created`, tenía en realidad el mismo patrón que la de tareas más los despliegues y las instancias de contenedor) y a tres suscripciones de correo: 6.591 correos entre el 04 y el 14-10 en el buzón revisado. La plantilla solo traía la hora, el estado y la task definition, no el motivo. | Medio |
| H8 | La plantilla estándar de Zabbix "AWS ECS Serverless Cluster by HTTP" no puede detectar una parada individual: pide a CloudWatch el promedio de 10 minutos de `RunningTaskCount`, consulta cada 5 minutos y no incluye ninguna métrica de paradas ni de reinicios. Un reemplazo de tarea dura menos de un minuto. El item de cluster "Task Count" sí tiene un punto por minuto. | Medio |
| H9 | El mismo cluster está monitoreado por dos hosts de Zabbix (`Zabbix server`, de alta manual, y `smartfran-pedidos-production`, descubierto) con la misma plantilla. | Bajo |

### Código involucrado (platformsService, rama `develop`, HEAD `dfb668e` del 13-10)

**Bug 1 (H3), `api/src/index.js` líneas 121-137, commit `b56d403` del 08-10:** el rechazo no manejado termina el proceso.

```js
async function logFatalAndExit(error, message, customData = {}) {
  try {
    await Log.save('FATAL', error, { category: 'INFRA', message, ...customData });
  } finally {
    process.exit(1);
  }
}

process.on('unhandledRejection', async reason => {
  const error = reason instanceof Error ? reason : new Error(`Unhandled rejection: ${String(reason)}`);
  await logFatalAndExit(error, '[INFRA/FATAL] unhandled_rejection');
});
```

**Bug 2 (H4), `api/src/utils/sanitizeHeaders.js` y sus llamadas:** el módulo exporta una clase con método estático; se importa con nombre en minúscula y se llama como función.

```js
// utils/sanitizeHeaders.js
class SanitizeHeaders {
    static sanitizeHeader(headers = {}) { /* ... */ }
}
export default SanitizeHeaders;

// controllers/rappi.js:4 y :61
import sanitizeHeaders from '../utils/sanitizeHeaders';
Log.saveError(error, { /* ... */ header: sanitizeHeaders(req.headers), /* ... */ });   // TypeError: Cannot call a class as a function

// platforms/management/platform/pedidosYa.js:21 y :237 (también 358, 444, 503, 565)
header: sanitizeHeaders(headersConfig)
```

Corrección posible: `sanitizeHeaders.sanitizeHeader(...)` en las 17 llamadas (mismo import, siete archivos).

**Bug 3 (H5), `api/src/utils/log.js` línea 32:** si el error no tiene `message`, se serializa con `JSON.stringify(error)`, que falla con estructuras circulares (socket HTTP).

```js
...(error != null && { error: error?.message ?? (typeof error === 'object' ? JSON.stringify(error) : String(error)) }),
```

Corrección posible: usar el `serializeError` que ya existe en la misma clase, o un `JSON.stringify` con control de referencias circulares.

## Acciones Tomadas (hora UTC)

| # | Hora | Acción |
|---|---|---|
| 1 | 2026-10-15 01:09 | Regla `ECS-Task-ECSTaskStateChange-Team` (topic `SNS-SmartPedidosTeam-PROD`): solo `lastStatus = STOPPED`. Un primer intento a las 01:03 se revirtió a las 01:06 |
| 2 | 2026-10-15 02:11 | La misma regla: plantilla final del correo con servicio, `stopCode`, `stoppedReason`, hora de parada, task definition y nombre/código de salida del primer contenedor |
| 3 | 2026-10-15 02:10 | Regla `ECS-Task-Definition-Version-Created` (topic `Alertas-EventBridge-PROD`): solo `ECS Task State Change` con `STOPPED` y la misma plantilla; deja de enviar los cambios de estado de despliegue y de instancia de contenedor |
| 4 | 2026-10-15 01:36 | Zabbix, plantilla "AWS ECS Serverless Cluster by HTTP": macro `{$AWS.ECS.CLUSTER.SERVICE.RUNNING.DIP}` = 0,05 y prototipo de trigger "Running tasks below desired" (Warning) en la regla "Cluster Services discovery" |
| 5 | 2026-10-15 01:43 a 01:49 | Primer enrutamiento (etiquetas `GIT-SML-OPE` y condición agregada a la acción 7); revertido a las 01:49 porque el enrutamiento no debe usar etiquetas de SML |
| 6 | 2026-10-15 01:52 | Zabbix: acción nueva 11 "Google Chat SmartPedidos to Operaciones" (condiciones `scope = OPE`, `scope = SP`, `action ~ GCHAT`; mismo destinatario y tipo de medio que la acción 7) y etiquetas del prototipo `scope=OPE`, `scope=SP`, `action=GCHAT` |
| 7 | 2026-10-15 01:58 | Zabbix: macro `{$AWS.ECS.CLUSTER.SERVICE.RUNNING.DIP}` = 1000 en el host `Zabbix server` para que la alerta no se dispare ahí; en el host descubierto de dev la API la rechazó (sin cambios) |

## Recursos afectados

| Componente | Estado |
|---|---|
| platform-service (ECS, 5 tareas deseadas) | Paradas por salida del contenedor con código 1; código sin corregir |
| concentrador-service (ECS, 1 tarea) | Sin cambios en este ticket |
| Reglas EventBridge de tareas ECS y topics `SNS-SmartPedidosTeam-PROD` y `Alertas-EventBridge-PROD` | Filtradas a `STOPPED` con motivo (cambios 1 a 3) |
| Zabbix: plantilla ECS, acción 11, macro en `Zabbix server` | Creados (cambios 4 a 7); las etiquetas de enrutamiento llegan a los triggers ya descubiertos en la próxima pasada de descubrimiento (latido de 3 horas, hacia las 04:45 UTC, estimado) |

## Acciones propuestas

Las acciones de SRE que ya se hicieron figuran en "Acciones Tomadas"; aquí queda lo pendiente o por decidir.

| # | Responsable | Acción | Estado |
|---|---|---|---|
| 1 | Dev | Corregir las llamadas a `SanitizeHeaders` (`SanitizeHeaders.sanitizeHeader(...)` o exportar una función) en `controllers/rappi.js` y en `platforms/management/platform/pedidosYa.js` (H4). | Pendiente |
| 2 | Dev | Hacer que `Log._stdout` no falle con errores que contienen estructuras circulares (try/catch o serialización segura) (H5). | Pendiente |
| 3 | Dev | Revisar el manejador de `unhandledRejection`/`uncaughtException`: no terminar el proceso por errores originados en el propio registro, o esperar a que termine el trabajo en curso antes de salir (H3). | Pendiente |
| 4 | Dev | Investigar por qué fallan las llamadas hacia MercadoPago, PedidosYa y Rappi que llegan a esas rutas de error, incluyendo los `TOKEN_MISSING` (H6). | Pendiente |
| 5 | SRE | Verificar a partir de las 04:50 UTC del 15-10 que los triggers descubiertos de Zabbix tengan las etiquetas `scope=OPE`, `scope=SP` y `action=GCHAT`, y que llegue el primer mensaje al Chat de Operaciones; ajustar el margen de la macro (0,05) con datos reales. | Pendiente (verificación posterior al descubrimiento de Zabbix) |
| 6 | SRE | Verificar el primer correo `STOPPED` de cada topic con el formato nuevo (línea del contenedor y caso sin código de salida). | Pendiente (esperando el primer aviso real) |
| 7 | SRE | Decidir si se mantiene la regla `ECS-Task-Definition-Version-Created`: con el filtro actual cada parada llega por tres correos; eliminarla deja dos (H7). | Por decidir |
| 8 | SRE | Evaluar un trigger sobre el item "AWS ECS Cluster: Task Count" (un punto por minuto) para detectar paradas en el momento, ya que los items por servicio llegan como promedio de 10 minutos (H8). | Pendiente (la alerta creada usa los items por servicio, promedio de 10 minutos; no el item de cluster por minuto) |
| 9 | SRE | Evaluar una alerta en Zabbix basada en el conteo de mensajes `[INFRA/FATAL]` de Graylog, que además trae el texto del error (H1, H8). | Pendiente |
| 10 | SRE | Revisar si el cluster debe seguir monitoreado por dos hosts de Zabbix (H9). | Pendiente |


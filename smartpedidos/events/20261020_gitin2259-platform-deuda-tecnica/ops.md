# GITIN-2259 — [SP] Platform: Deuda Técnica

**Tags:** `SmartPedidos`, `Platform`, `Logs`, `Deuda técnica`, `SRE`, `PROD`

## Qué pasó

- Durante el trabajo sobre los logs de platforms-service (mejoras de logging y revisión de los eventos FATAL de [GITIN-2222](https://smartit-ar.atlassian.net/browse/GITIN-2222) y [GITIN-2248](https://smartit-ar.atlassian.net/browse/GITIN-2248)) se detectaron varios puntos de deuda técnica en el código de platform.
- Los puntos se fueron registrando entre el 09-06-2026 y el 22-06-2026 (PGAP-001, PGAP-002, PGAP-003) y se sumaron hallazgos de octubre sobre el logger y los manejadores de proceso.

## Resumen

Al trabajar los logs de platforms-service se detectaron cuatro puntos de deuda técnica que siguen presentes en la rama `develop` (revisada el 20-10-2026, commit `643d17f`): el tiempo de las llamadas HTTP se mide a mano en cada método (39 temporizadores en 6 archivos de proveedores), 31 mensajes de error llevan el id de la orden dentro del texto en lugar de un campo estructurado, el logger puede lanzar una excepción al serializar un error con estructura circular, y el manejo de rechazos y excepciones no capturadas quedó sin una política definida. Un quinto punto (el id de la orden ausente en los logs del consumidor SQS) ya está corregido en `develop`. Ninguno está corregido todavía; se proponen como tareas para Desarrollo, cada una con riesgo, esfuerzo y una Definition of Done verificable (las Definition of Done son propuestas de SRE y los esfuerzos de las acciones 1, 2 y 5 son estimaciones de SRE; ninguno está validado con Desarrollo), y queda por decidir la prioridad y el orden.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2259](https://smartit-ar.atlassian.net/browse/GITIN-2259) |
| ID alerta | NA |
| Sistema | platforms-service (SmartPedidos, PROD) |
| Severidad | NA (deuda técnica, no un incidente) |
| Detectado | 09-06-2026 a 22-06-2026 (PGAP-001, 002, 003); 14-10-2026 a 16-10-2026 (logger y manejadores) |
| Resuelto | No. PGAP-003 corregido en `develop` (commit `649b426`, 22-06-2026) |
| Responsable | Desarrollo (correcciones de código); SRE (relevamiento y seguimiento) |

## Causa raíz

NA

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | PGAP-001 — Los tiempos de las llamadas a las plataformas se miden a mano en cada método con `const t0` y un log `[PERF/INFO]`: 39 temporizadores en 6 archivos de `api/src/platforms/management/platform/` (`thirdParty.js` 16, `rapiboy.js` 10, `mercadoPago.js` 6, `rappi.js` 5, `pedidosYa.js` 1, `uberEats.js` 1) y 46 sitios `[PERF/INFO]`. Platform no tiene `utils/httpClient.js` ni interceptores (concentrador-service sí usa un interceptor). Un cambio en el formato del log de tiempos obliga a tocar todos esos sitios, y un método nuevo queda sin tiempos si se olvida el bloque. Origen: los temporizadores vienen de la primera implementación de los logs de tiempo (commit `afc296a`, 12-05-2026, en `pedidosYa.js`, `uberEats.js` y `tokensCloud.js`; commit `2a154f0`, 08-06-2026, en `rappi.js`, `rapiboy.js`, `mercadoPago.js` y `thirdParty.js`); platform nunca pasó al cliente HTTP con interceptor. | Medio |
| H2 | PGAP-002 — 31 sitios de error con el id de la orden concatenado en el mensaje: 30 "Platform Communication Error" (`pedidosYa.js` 6, `thirdParty.js` 6, `rapiboy.js` 6, `rappi.js` 4, `uberEats.js` 4, `mercadoPago.js` 3, `controllers/thirdParty.js` 1) y 1 "Platform Auth Error" (`app.js`). En Graylog no se puede filtrar por `order_id` los errores de comunicación de una orden sin analizar el texto del mensaje. | Medio |
| H3 | `Log._stdout` (`api/src/utils/log.js`, línea 32) llama a `JSON.stringify(error)` cuando el error es un objeto sin `message`. Si el objeto contiene un socket HTTP, lanza "Converting circular structure to JSON". En el análisis de [GITIN-2222](https://smartit-ar.atlassian.net/browse/GITIN-2222) 23 de 63 eventos FATAL fueron de este tipo. Sigue igual en `develop` (commit `643d17f`). La rama `logs22` (commit `2b7ebb1`, 20-10-2026) lo corrige: deja de serializar el error con `JSON.stringify` (solo usa `error.message`) y envuelve la construcción de la línea en un `try/catch` con una línea de reserva `[INFRA/ERROR] log_stdout_failed`; esa rama no está integrada a `develop` y no se sabe si fue revisada ni desplegada. | Alto |
| H4 | Los manejadores de proceso en `api/src/index.js` registran `[INFRA/FATAL]` y desde el 19-10-2026 (commit `643d17f`) ya no terminan el proceso (`process.exit(1)` comentado en `logFatalAndExit`). No hay una política definida de qué hacer tras una excepción no capturada (seguir corriendo o terminar). Si ese cambio está desplegado no fue verificado. | Medio |

### H3 — código

`api/src/utils/log.js`, línea 32:

```js
...(error != null && { error: error?.message ?? (typeof error === 'object' ? JSON.stringify(error) : String(error)) }),
```

Corrección sugerida: que la serialización no pueda lanzar, por ejemplo con `try/catch` (o un serializador seguro ante referencias circulares) y un valor de reserva como `String(error)`, para que un fallo del logger no genere un nuevo rechazo no manejado. La rama `logs22` hace esto; una consecuencia es que un `error` sin `message` (un texto, un objeto plano) ya no aparece en el campo `error` de la línea de log.

Corregidos en `develop` y por eso no figuran como hallazgos abiertos: PGAP-003 (los cuatro logs `setNews_processing failed` del consumidor SQS ya incluyen `order_id`) y el uso de la clase `SanitizeHeaders` como función (0 llamadas incorrectas restantes según la revisión de [GITIN-2248](https://smartit-ar.atlassian.net/browse/GITIN-2248)).

## Acciones Tomadas

| # | Hora (UTC) | Acción |
|---|---|---|
| 1 | 09-06-2026 a 22-06-2026 | Registro de PGAP-001, PGAP-002 y PGAP-003 en el registro de deuda técnica, con causa, remediación y esfuerzo estimado. |
| 2 | 20-10-2026 | Verificación de los puntos contra `develop` de platform (commit `643d17f`): lectura de código y conteos, sin modificar nada. Resultado en los hallazgos. |
| 3 | 20-10-2026 | PGAP-003 marcado como resuelto en el registro (sin borrarlo) al comprobar que los cuatro logs del consumidor SQS incluyen `order_id`. |
| 4 | 20-10-2026 | Definition of Done agregada a cada punto del registro de deuda técnica (PGAP-001, 002 y 003, y los de concentrador-service), para poder dar cada uno por cerrado con un criterio verificable. Las Definition of Done son propuestas de SRE, sin validar con Desarrollo. |

## Recursos afectados

| Componente | Estado |
|---|---|
| platforms-service | Código con los puntos H1 a H4 presentes en `develop` |
| concentrador-service | Sin cambios; su deuda técnica se lleva aparte |

## Acciones propuestas

Cada acción tiene una Definition of Done (DoD): se da por cerrada cuando se cumple y se verifica. Riesgo es el del hallazgo que corrige (el de la tabla de Hallazgos; para la acción 5, el de dejar el registro desactualizado). Esfuerzo: las acciones 3 y 4 toman el valor del registro de deuda técnica (Medio); las acciones 1, 2 y 5 son una estimación de SRE sin validar con Desarrollo.

| # | Responsable | Acción | Riesgo | Esfuerzo | Definition of Done | Estado |
|---|---|---|---|---|---|---|
| 1 | Dev | H3: hacer segura la serialización de `Log._stdout` (que un error con estructura circular no lance). La rama `logs22` (commit `2b7ebb1`) lo implementa; falta su integración a `develop` y el despliegue. | Alto | Bajo | Llamar al logger con un objeto circular (con un socket HTTP adentro) escribe la línea de log con un valor de reserva y no lanza; y en Graylog, 0 líneas "Converting circular structure to JSON" de platforms-service en los 7 días posteriores al despliegue. | En rama, pendiente de integración |
| 2 | Dev | H4: definir la política ante `unhandledRejection` y `uncaughtException` (seguir corriendo o terminar tras registrar FATAL) y confirmar si el cambio del 19-10-2026 está desplegado. | Medio | Bajo | La decisión queda escrita en el ticket y los dos manejadores de `index.js` la cumplen; en un caso de prueba cada manejador registra un `[INFRA/FATAL]` y el proceso se comporta como se decidió. | Por decidir |
| 3 | Dev | H1: reemplazar los temporizadores manuales por un cliente HTTP con interceptor, como en concentrador-service. | Medio | Medio | 0 `const t0` en los archivos de proveedores; los logs `[PERF/INFO]` de cada plataforma (PedidosYa, Rappi, UberEats, MercadoPago, PediGrido, terceros) siguen apareciendo en Graylog con los mismos campos que antes del cambio. | Pendiente |
| 4 | Dev | H2: pasar el id de la orden a un campo estructurado (`order_id`) en los 31 sitios de error. | Medio | Medio | 0 mensajes "Platform Communication Error" / "Platform Auth Error" con el id concatenado; en Graylog, una consulta por `order_id` devuelve los errores de comunicación de esa orden sin analizar el texto del mensaje. | Pendiente |
| 5 | SRE | Mantener el registro de deuda técnica actualizado y asociar estos puntos a las tareas que se creen. | Bajo | Bajo | Cada punto del registro tiene su tarea asociada y su Definition of Done, y su estado coincide con lo que hay en `develop` en la última revisión. | Pendiente |

# GITIN-2220 — [SP] Platform: consultas excesivas a GET WalletCredentials de Cloud (MercadoPago token_fetch)

**Etiquetas:** `SmartPedidos`, `Platform`, `PROD`

## Resumen

`platforms-service` consulta a SmartCloud el token de MercadoPago de cada comercio mediante `GET /api/v1/WalletCredentials/{id}` (acción `token_fetch`). El 11-10-2026, entre las 21:50 y las 22:10 (hora local, UTC-3), los logs de Platform en Graylog muestran unas 957 consultas por minuto (16 por segundo); el 98 % responde 204 (18.776 de 19.141) y dos identificadores de comercio concentran el 96 % (10.808 y 7.488 de 19.141; 55 identificadores distintos). En SmartCloud, el servicio Business registra ese mismo endpoint con 504.921 consultas el 08-10, 1.898.817 el 09-10 y entre 1,17 y 1,51 millones por día del 10 al 12-10; antes del 08-10 no figura entre las rutas más frecuentes. La lectura del código de Platform muestra que cuando SmartCloud no devuelve un token (respuesta vacía o error) no se guarda nada, ni el fallo ni un tiempo de espera, de modo que cada evento del mismo comercio vuelve a consultar. Se propone un cambio en Platform (caché del resultado negativo por comercio con espera creciente, una sola consulta simultánea por comercio y corrección del manejo del 204). No está confirmado que la consulta repetida de Platform sea la causa de todo el volumen que ve SmartCloud, ni que los dos comercios más consultados sean las cuentas con renovación fallida de GITIN-2209.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2220](https://smartit-ar.atlassian.net/browse/GITIN-2220) |
| Tickets relacionados | [GITIN-2209](https://smartit-ar.atlassian.net/browse/GITIN-2209) (disco de Graylog de SmartCloud; renovación fallida de tokens), [GITIN-2211](https://smartit-ar.atlassian.net/browse/GITIN-2211) (medición de las consultas de Platform), [GITIN-2218](https://smartit-ar.atlassian.net/browse/GITIN-2218) (gráficos de Graylog; crecimiento de GET en Business), [GITIN-2208](https://smartit-ar.atlassian.net/browse/GITIN-2208) (errores de token MercadoPago en Concentrador) |
| ID alerta | NA |
| Sistema | SmartPedidos `platforms-service` (código en rama `develop`, commit a762c1a del 09-10-2026; el commit desplegado en producción no se verificó); SmartCloud Business API |
| Severidad | Por definir con Operaciones |
| Detectado | 2026-10-13, al cruzar los datos de GITIN-2209, GITIN-2211 y GITIN-2218 |
| Resuelto | No. Solo hay propuesta de cambio; no se modificó código |
| Responsable | Dev (cambio en Platform); SRE (medición antes y después) |

## Causa raíz

NA

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Medido (GITIN-2211, Graylog de SmartPedidos, 11-10 21:50–22:10): Platform registra `token_fetch` de MercadoPago unas 957 veces por minuto (16 por segundo); 98 % con estado 204; dos identificadores de comercio suman el 96 % y hay 55 distintos en total. | Alto |
| H2 | Medido (GITIN-2218, Graylog de SmartCloud, logs de aplicación de Business, GET): `WalletCredentials/{id}` pasa de no figurar entre las rutas principales hasta el 07-10 a 504.921 consultas el 08-10, 1.898.817 el 09-10, 1.172.153 el 10-10, 1.484.266 el 11-10 y 1.512.060 el 12-10 (los valores son cotas inferiores: se conservaron las 15 rutas principales por día). El total de GET de Business pasó de unos 4.000 por día (05 al 07-10) a 675.435 el 08-10 y 2.078.674 el 09-10. | Alto |
| H3 | Código de Platform: la función `getTokenMercadoPagoCloud` solo consulta a SmartCloud cuando no hay un token guardado para el comercio, y guarda únicamente las respuestas correctas. Cuando la respuesta es vacía (204) o hay error devuelve `null` y no guarda nada, por lo que no existe caché del resultado negativo, límite por comercio, espera creciente ni consulta única simultánea (en los archivos leídos). | Alto |
| H4 | Código de Platform: la comprobación del estado 204 lee `response.status` de una respuesta correcta de axios, que expone `status`; por lectura del código, la advertencia de 204 no puede ejecutarse (no se probó). Una respuesta 204 vacía termina en el error "Invalid token response from cloud", registrado como ERROR, y se escribe además el log de rendimiento de la consulta. | Medio |
| H5 | Código de Platform: los llamadores (`controllers/mercadoPago.js` y `platforms/management/platform/mercadoPago.js`) consultan por cada notificación o pedido y, ante `null`, continúan con el siguiente elemento; también reintentan la consulta ante un 401 con token guardado. Cuatro llamadas más en el mismo archivo no se leyeron. | Medio |
| H6 | SmartCloud (GITIN-2209): al menos dos cuentas de MercadoPago devuelven `invalid_grant` al renovar el token; el código de Cloud deja la credencial activa y vuelve a intentar la renovación en cada consulta. Es una causa posible de las respuestas vacías que recibe Platform, pero no está confirmado que los dos comercios más consultados por Platform sean esas cuentas, ni cómo mapea Cloud la renovación fallida a un 204. | Medio |
| H7 | Platform envía el encabezado `TraceKey` con el valor fijo `1234`, por lo que las consultas no se pueden correlacionar con los logs de SmartCloud por esa clave. | Bajo |
| H8 | No está medido si Concentrador también consulta este endpoint y a qué ritmo; el llamador en SmartCloud es un sujeto máquina a máquina de Auth0 cuyo `client_id` está configurado en Platform y en Concentrador, así que no los distingue. | Medio |

## Propuesta de cambio en Platform

Archivo adjunto: `outputs/propuesta-tokensCloud.js` (boceto, no aplicado) sobre `api/src/utils/tokensCloud.js`. Los tiempos son valores iniciales a ajustar, no mediciones.

| # | Cambio | Detalle |
|---|---|---|
| P1 | Caché del resultado negativo por comercio | Tras una respuesta vacía, 204 o error, no volver a consultar a SmartCloud para ese comercio hasta que venza un tiempo (valor inicial 5 minutos, configurable). |
| P2 | Espera creciente | El tiempo se duplica en cada fallo consecutivo hasta un máximo (valor inicial 1 hora) y se reinicia con una respuesta correcta. |
| P3 | Una consulta simultánea por comercio | Los llamadores concurrentes del mismo comercio comparten la misma consulta en curso. |
| P4 | Manejo del 204 | Comprobar `status` de la respuesta y resolverlo antes del error "Invalid token response": una advertencia, sin traza de error, y devolver `null`. |
| P5 | Logs | Registrar el fallo repetido una vez por ventana y por comercio; enviar el `TraceKey` real en lugar de `1234`. |

Efecto esperado (aritmética sobre el valor propuesto de 5 minutos, no una medición): dos comercios con fallo costarían unas 2 consultas cada 5 minutos por tarea, en lugar de las 16 por segundo de H1. La caché propuesta está en la memoria de cada tarea de ECS, por lo que con varias tareas el total es proporcional al número de tareas; compartirla entre tareas requiere guardarla en MongoDB con un índice de vencimiento, con una lectura más por consulta. El cambio reduce la carga sobre SmartCloud y Graylog; no entrega un token a esos comercios, lo que requiere reautorizar las cuentas o corregirlo del lado de SmartCloud (GITIN-2209).

## Recursos afectados

| Componente | Estado observado |
|---|---|
| `platforms-service` (SmartPedidos) | Unas 16 consultas por segundo de `token_fetch` de MercadoPago el 11-10 (H1) |
| Business API (SmartCloud), endpoint `GET /api/v1/WalletCredentials/{id}` | Entre 1,17 y 1,90 millones de consultas por día del 09 al 12-10 (H2); parte de esas consultas puede no provenir de Platform (H8) |
| Graylog de SmartCloud (índice de Business) | Crecimiento de volumen asociado al mismo endpoint, seguido en GITIN-2209 |
| Graylog de SmartPedidos | Cada consulta de Platform escribe una línea de rendimiento y, si falla, un ERROR |

## Comandos ejecutados

No se ejecutó ningún comando contra sistemas para este ticket; la evidencia proviene de las mediciones de otros tickets y de la lectura del código.

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | GITIN-2211 `scripts-c7.sh` | Logs de `platforms-service` por minuto en Graylog de SmartPedidos (origen de H1) |
| C2 | GITIN-2218 `scripts-c3.sh` | GET de Business por día y por ruta en Graylog de SmartCloud (origen de H2) |
| C3 | GITIN-2209 `scripts-business*.sh` | Origen y texto de los errores `invalid_grant` en Business (origen de H6) |

## Acciones propuestas

1. (Dev) Implementar P1 a P5 en `platforms-service` y desplegar; el tiempo inicial y su máximo se acuerdan con Operaciones.
2. (Dev) Antes de implementar, revisar qué hace `controllers/mercadoPago.js` con un elemento omitido (si la notificación se reintenta, con qué frecuencia y si el pedido queda pendiente) y revisar las cuatro llamadas restantes de `platforms/management/platform/mercadoPago.js`.
3. (Dev) Decidir si la caché negativa vive en la memoria de cada tarea o en MongoDB con vencimiento, para compartirla entre tareas de ECS.
4. (SRE) Confirmar con los logs de SmartCloud si los dos comercios más consultados por Platform son las cuentas con `invalid_grant` de GITIN-2209 (credenciales 31 y 66).
5. (SRE) Medir si Concentrador consulta el mismo endpoint y a qué ritmo, y qué parte de las consultas de Business corresponde a cada servicio.
6. (SRE) Medir después del despliegue con el mismo conteo de `token_fetch` de GITIN-2211 y el conteo de GET de Business de GITIN-2218 para comparar con H1 y H2.
7. (Dev / Operaciones) Reautorizar las cuentas de MercadoPago con renovación fallida o corregir el manejo en SmartCloud, según GITIN-2209; este cambio en Platform no lo reemplaza.
8. (Dev) Verificar qué commit está desplegado en producción antes de aplicar el cambio sobre `develop`.

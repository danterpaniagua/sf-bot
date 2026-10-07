# [SP] 5489 No recibe pedidos

**Tags:** `SmartPedidos`, `Platform`, `Concentrador`, `MongoDB`, `AWS`, `Graylog`

## Resumen

Se reportó que la sucursal 5489 no recibía pedidos: llegaban alertas de pedidos nuevos, pero la cola `5713PRD_PlatformMessages.fifo` no tenía mensajes. Según lo informado por el equipo de integración, la sucursal cambió de número (5489 pasó a 5713), la sucursal anterior se eliminó del Concentrador y los datos de integración de las plataformas se cargaron en el número nuevo. La investigación del 02/10/2026 mostró que el reporte reúne situaciones distintas: la cola SQS está bien creada y configurada; los pedidos de PedidosYa fueron rechazados por platforms-service porque no encontró sucursal asociada; y los pedidos de PediGrido de la sucursal 5713 se guardaron en Mongo pero nunca llegaron al POS. Durante la investigación, la entrada de PediGrido de la sucursal estuvo ausente y luego se restauró.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2161](https://smartit-ar.atlassian.net/browse/GITIN-2161) |
| ID alerta | No disponible |
| Sistema | SmartPedidos: platforms-service, concentrador-service, AWS SQS, MongoDB |
| Severidad | Por definir |
| Detectado | 2026-10-02 |
| Resuelto | Pendiente de validación. A las 00:44 UTC del 03/10 llegan al POS pedidos de PedidosYa, Rappi y MercadoPago; la entrada de PediGrido se restauró (verificada a las 00:49 UTC) y aún no se validó con un pedido de prueba |
| Responsable | SRE |

Los horarios están en UTC; la hora local es UTC-3.

## Causa raíz

La cola SQS no es la causa: existe con el nombre esperado y su configuración es equivalente a la de una sucursal que funciona correctamente (H1).

**PedidosYa.** Causa probable, sin historial que la confirme en el intervalo exacto: la entrada de PedidosYa de la sucursal 5713 tenía como referencia el código anterior (5489) cuando concentrador-service intentó guardarla entre las 21:01 y las 21:06, mientras que PedidosYa ya enviaba el código 5713 entre las 22:50 y las 23:03. platforms-service asocia cada pedido a una sucursal comparando el código que envía la plataforma con la referencia guardada, y al no coincidir rechaza el pedido sin guardarlo. A las 00:37 la entrada tiene la referencia 5713 y un pedido posterior fue recibido; Mongo no conserva el historial del campo, por lo que no se puede fijar cuándo se corrigió (H2, H3).

**PediGrido, pedidos del 23/09 al 01/10.** Causa no determinada. Los 7 pedidos se guardaron y ninguno llegó al POS. Hipótesis sin probar: platforms-service solo envía el pedido a SQS si la sucursal informa una versión de agente mayor a 1.24, y el agente 1.33 de la sucursal 5713 se instaló el 01/10 a las 19:23 UTC, después del último de esos pedidos; la cola no registró sondeos hasta alrededor de las 19:25 (H4, H5).

**PediGrido, durante la investigación.** La entrada de PediGrido de la sucursal 5713 existía a las 00:24 UTC, no existía a las 00:35 ni a las 00:44, y existe activa a las 00:49. Quién la modificó y por qué no consta en los datos (H6).

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | La cola `5713PRD_PlatformMessages.fifo` existe, fue creada el 22/09 y es idéntica en atributos y política a la de la sucursal 3013, salvo el cifrado administrado por SQS, activo por defecto en colas nuevas. La cola anterior `5489PRD_PlatformMessages.fifo` sigue existiendo y está vacía; la sucursal 5489 ya no existe en Mongo. (C1, C7, C8, C14) | Bajo |
| H2 | Tres pedidos de PedidosYa (códigos 2309204253, 2309193736 y 2309230293) fueron rechazados entre las 22:50 y las 23:03 UTC con "There is no branch for this order". Los tres traían `branchId` 5713, restaurante 522890 y `test` en falso, y cada uno se recibió dos veces con 10 segundos de diferencia. No se guardó ningún pedido. (C13, C16, C17) | Alto |
| H3 | concentrador-service registró 5 errores `branch_update_duplicate_reference` entre las 21:01 y las 21:06 UTC al guardar la sucursal 5713. El cuerpo enviado mostraba PedidosYa con referencia 5489. Ninguna sucursal tiene hoy una referencia 5489, y solo la sucursal 5713 tiene el identificador de PedidosYa que le corresponde. (C14, C15, C17) | Medio |
| H4 | Los 7 pedidos de PediGrido de la sucursal 5713 (23/09 al 01/10) se guardaron pero ninguno fue visto por el POS ni tiene la traza de "recibido por el POS". Seis fueron rechazados por la plataforma unos 10 minutos después y el pedido 5637871 (01/10, 17:28 UTC) sigue en PENDING. En la sucursal 3013, el POS vio 28 de sus 30 pedidos PediGrido más recientes dentro de 1 a 12 segundos. (C4, C5, C9, C10) | Alto |
| H5 | El agente 1.33 de la sucursal 5713 se instaló el 01/10 a las 19:23:20 UTC. La cola no registró sondeos antes de ese día y los comenzó alrededor de las 19:25 UTC; en la hora del pedido del 01/10 no hay envíos a la cola. La condición de versión de agente es la hipótesis, no un hecho probado: se desconoce la versión previa del agente. (C2, C11, C12) | Medio |
| H6 | La entrada de PediGrido de la sucursal 5713 estaba presente a las 00:24 UTC del 03/10, ausente a las 00:35 y 00:44, y presente (activa, referencia 5713) a las 00:49. Ninguna otra sucursal retiene esa referencia. (C6, C13, C15, C20) | Medio |
| H7 | Los pedidos del 03/10 llegaron al POS en 0,6 a 2 segundos: dos de MercadoPago (00:18 UTC), uno de PedidosYa (00:38 UTC) y uno de Rappi (00:42 UTC, completado hasta READY). El pedido de PedidosYa 2309501289 fue aceptado en el POS y la plataforma lo rechazó 49 segundos después; el motivo no está determinado. (C13, C18, C19) | Medio |

## Recursos afectados

| Componente | Estado observado |
|---|---|
| platforms-service | Rechaza y no guarda los pedidos cuyo código de sucursal no coincide con la referencia guardada (PedidosYa, 22:50 a 23:03 UTC). Guardó los pedidos PediGrido sin enviarlos a la cola (23/09 al 01/10). |
| concentrador-service | 5 intentos de actualización de la sucursal 5713 fallidos por referencia duplicada (21:01 a 21:06 UTC). |
| AWS SQS `5713PRD_PlatformMessages.fifo` | Configuración correcta. Sin mensajes enviados por los pedidos PediGrido del 01/10; sin sondeos hasta alrededor de las 19:25 UTC de ese día. |
| MongoDB (`branches`, `orders`, `news`) | Entrada PediGrido de la sucursal 5713 ausente durante parte de la investigación, ya restaurada. Pedido PediGrido 5637871 en PENDING. |

## Comandos ejecutados

Registro completo en `scripts.sh`; la salida real de cada uno está en `data/`.

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | `get-queue-attributes` de la cola 5713 | Verificar existencia, atributos y política |
| C2 | CloudWatch, mensajes enviados y recibidos por la cola 5713 (48 h) | Ver si se envió algo a la cola |
| C3 | `mongo_branch_5713.js` | Estado de la sucursal 5713 y sus news recientes |
| C4 | `mongo_orders_5713.js` | Plataformas de la sucursal y pedidos por plataforma y estado |
| C5 | `mongo_order_trace_5713.js` | Línea de tiempo del pedido PENDING del 01/10 contra uno rechazado |
| C6 | `mongo_compare_branch.js` | Comparar la configuración de 5713 con la sucursal de referencia 3013 |
| C7 | `get-queue-attributes` de la cola 3013 y comparación | Comparar atributos y política entre colas |
| C8 | `get-queue-url` de colas de referencia | Confirmar el patrón de nombres |
| C9 | `mongo_closed_path_5713.js` | Descartar sucursal cerrada y revisar trazas |
| C10 | `mongo_control_pedigrido.js` | Comparar la recepción de pedidos PediGrido entre 5713 y 3013 |
| C11 | `mongo_agent_install_5713.js` | Versión y fecha de instalación del agente |
| C12 | CloudWatch, lecturas vacías de la cola 5713 (14 días) | Determinar desde cuándo se sondea la cola |
| C13 | `mongo_fresh_5713.js` (dos ejecuciones) | Pedidos recientes de 5713 y flujo general de plataformas |
| C14 | `mongo_old_5489.js` y consulta de la cola 5489 | Estado de la sucursal y la cola anteriores |
| C15 | `mongo_refs_5713.js` (dos ejecuciones) | Comparar las referencias de plataforma con el número nuevo y el anterior |
| C16 | Graylog, rechazos "There is no branch for this order" (3 h y 30 min) | Confirmar los rechazos de platforms-service |
| C17 | Graylog, mensajes con `branchId` 5713 (6 h) | Errores de actualización de la sucursal y rechazos |
| C18 | `mongo_latest_news_5713.js` | Trazas de los pedidos más recientes |
| C19 | `mongo_platformresult_5713.js` | Resultado de plataforma del pedido PedidosYa rechazado |
| C20 | `mongo_pedigrido_holders.js` | Verificar la entrada PediGrido y posibles duplicados |

## Acciones propuestas

1. (SRE) Validar PediGrido con un pedido de prueba en la sucursal 5713: confirmar que se guarda el pedido, que la news recibe la traza de "recibido por el POS" en pocos segundos y que no hay rechazos "There is no branch for this order" en Graylog.
2. (SRE) Confirmar con el equipo de integración: quién modificó la entrada PediGrido de la sucursal 5713 y por qué; los horarios de las pruebas de PedidosYa y PediGrido; si los tres pedidos de PedidosYa con `test` en falso eran de prueba; y el motivo del rechazo de plataforma del pedido 2309501289.
3. (SRE) Determinar la versión del agente de la sucursal 5713 antes del 01/10 a las 19:23 UTC (registros del agente o equipo que desplegó la versión 1.33) para confirmar o descartar la hipótesis de la condición de versión.
4. (SRE) Definir con el equipo el tratamiento del pedido PediGrido 5637871, que sigue en PENDING.
5. (SRE) En futuras renumeraciones de sucursal, verificar antes de la prueba que la referencia de cada plataforma coincida con el código que esa plataforma envía.
6. (Dev) Evaluar registrar un log cuando platforms-service omite el envío a SQS por la condición de versión de agente o de apertura de la sucursal.
7. (Dev) Evaluar corregir `pushNewToQueue`, que no espera (`await`) el envío dentro de su `try`, de modo que un error asíncrono no queda registrado por su propio manejo de errores.

## Hallazgos secundarios

| # | Hallazgo | Riesgo |
|---|---|---|
| HS1 | En platforms-service (rama `develop`, referencia de producción), el envío a SQS se omite sin ningún log cuando la sucursal no informa una versión de agente mayor a 1.24 y no está marcada como `cloud`; una versión no informada se evalúa como `NaN` y la comparación es falsa. | Medio |
| HS2 | `pushNewToQueue` devuelve la promesa de `send` sin `await` dentro del `try`; un error asíncrono de SQS no pasa por su `catch` y aflora recién en el llamador como `saveNewOrders 5 failed`. | Bajo |

# GITIN-2161 — Actualización 05/10/2026

Los horarios están en UTC; la hora local es UTC-3.

## Estado

Desde el 03/10 a las 00:49, momento en que se verificó la entrada de PediGrido de la sucursal 5713, los pedidos de PedidosYa y PediGrido llegaron al POS. La extracción se hizo el 05/10 a las 12:10.

## Pedidos de la sucursal 5713 desde el 03/10 00:49

| Plataforma | Pedidos | Estados | Primer pedido | Último pedido |
|---|---|---|---|---|
| PedidosYa | 33 | 33 en READY | 03/10 00:52 | 05/10 01:25 |
| PediGrido | 3 | 1 DELIVERED, 2 REJECTED | 03/10 00:59 | 04/10 22:01 |
| MercadoPago | 6 | 2 READY, 4 REJECTED | 03/10 19:00 | 04/10 16:27 |
| Rappi | 4 | 4 REJECTED | 03/10 01:03 | 04/10 02:24 |

- **PedidosYa:** ninguno de los 33 pedidos quedó sin ser visto por el POS. En 3 pedidos el cruce con su novedad no encontró registro; ese cruce se hace por fecha de creación idéntica y no se investigó la causa.
- **PediGrido:** los 3 pedidos fueron vistos por el POS entre 1 y 2 segundos después de crearse y pasaron por recibido, visto, aceptado y listo. Uno terminó DELIVERED. Los otros dos terminaron REJECTED después de estar listos; el motivo y quién los rechazó no se relevaron. Los 7 pedidos de PediGrido anteriores (23/09 al 01/10) nunca llegaron al POS.
- **MercadoPago y Rappi:** hay 8 pedidos REJECTED (4 de cada plataforma); en esta extracción no se leyeron sus trazas ni los motivos.

## Pendiente

1. (SRE) Confirmar con el equipo de integración el motivo de los rechazos de los pedidos de PediGrido (2), MercadoPago (4) y Rappi (4) posteriores al 03/10.
2. (SRE) Determinar la versión del agente de la sucursal 5713 antes del 01/10 a las 19:23 para confirmar o descartar la hipótesis de la condición de versión (causa de los pedidos de PediGrido del 23/09 al 01/10, no confirmada).
3. (SRE) Definir con el equipo el tratamiento del pedido PediGrido 5637871, que estaba en PENDING al 03/10; su estado no se volvió a consultar.
4. (SRE) Confirmar con el equipo de integración los horarios de las pruebas de PedidosYa y PediGrido del 02/10 y si los tres pedidos de PedidosYa con `test` en falso eran de prueba.

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C21 | `scripts.sh` — re-ejecución de las últimas news y pedidos de 5713 | Ver los pedidos más recientes del 05/10 |
| C22 | `scripts.sh` — pedidos de 5713 desde el 03/10 00:49 | Conteo por plataforma y estado, y trazas de PediGrido y PedidosYa |

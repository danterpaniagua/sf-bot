# Eventos — 20260711_disputa_puntos_38778247

## 2026-07-11 23:00 — Apertura de investigación

He recibido el reclamo de la socia 38778247, quien manifiesta haber canjeado 10.000 puntos el 11/06/2026 con un descuento real de 20.000, y desconoce tres movimientos adicionales (+1.000 02/07, −6.500 16/06, −3.000 11/06).

## 2026-07-11 23:02 — Resolución de identidad

He confirmado el CustomerId `CA9E37DC-E985-CAB0-1A3B-08D30721E94F` (Fatima Marina Gonzalez), cuenta activa desde 2015, sin señales de cuenta sintética (email no desechable, alta por punto de venta).

## 2026-07-11 23:03 — Verificación de saldo

He confirmado saldo actual de 1.623 pts, con `LastLogDate` coincidente con el movimiento de +1.000 del 02/07 en disputa.

## 2026-07-11 23:06 — Reconstrucción del historial de puntos

He reconstruido el historial completo de eventos (01/06–05/07). He confirmado que el canje reconocido de 10.000 pts corresponde a dos líneas de −5.000 bajo el mismo `SaleId`. He identificado una tercera operación de −3.000, siete minutos después, con `SaleId` distinto — coincide exactamente con el monto disputado.

## 2026-07-11 23:07 — Confirmación de movimientos disputados

He confirmado que los tres movimientos denunciados (−3.000, −6.500, +1.000) existen en el log y coinciden en fecha, hora y monto con el reclamo de la socia.

## 2026-07-11 23:08 — Descarte de exploit sistémico

He verificado ausencia de asignaciones manuales (`ManualAssignPoints`) y transferencias (`PointsTransference`) en el período — descarto el patrón de exploit conocido en este caso.

## 2026-07-11 23:09 — Trazabilidad de sucursal y tarjeta

He trazado el origen de las seis ventas del período vía `Sml.Sale`. He confirmado que la tarjeta (`CustomerCardId` 5706842) es idéntica en todas las operaciones y que las sucursales coinciden con el patrón habitual de la socia — descarto clonación de tarjeta y geolocalización anómala.

## 2026-07-11 23:10 — Cierre de investigación

He documentado el hallazgo en `_ops.md`. He propuesto verificar con la sucursal 3467 si hubo doble operación el 11/06, confirmar con la socia si comparte la tarjeta con un familiar, y, de no confirmarse ninguna de las dos hipótesis, acreditar 9.500 pts por compensación administrativa. Estado: pendiente decisión de operaciones.

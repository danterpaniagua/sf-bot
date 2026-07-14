# Eventos — 20260711_disputa_puntos_38778247

## 2026-07-11 23:00 — Apertura de investigación

Se ha recibido el reclamo de la socia 38778247, quien manifiesta haber canjeado 10.000 puntos el 11/06/2026 con un descuento real de 20.000, y desconoce tres movimientos adicionales (+1.000 02/07, −6.500 16/06, −3.000 11/06).

## 2026-07-11 23:02 — Resolución de identidad

Se ha confirmado el CustomerId `CA9E37DC-E985-CAB0-1A3B-08D30721E94F` (Fatima Marina Gonzalez), cuenta activa desde 2015, sin señales de cuenta sintética (email no desechable, alta por punto de venta).

## 2026-07-11 23:03 — Verificación de saldo

Se ha confirmado saldo actual de 1.623 pts, con `LastLogDate` coincidente con el movimiento de +1.000 del 02/07 en disputa.

## 2026-07-11 23:06 — Reconstrucción del historial de puntos

Se ha reconstruido el historial completo de eventos (01/06–05/07). Se ha confirmado que el canje reconocido de 10.000 pts corresponde a dos líneas de −5.000 bajo el mismo `SaleId`. Se ha identificado una tercera operación de −3.000, siete minutos después, con `SaleId` distinto — coincide exactamente con el monto disputado.

## 2026-07-11 23:07 — Confirmación de movimientos disputados

Se ha confirmado que los tres movimientos denunciados (−3.000, −6.500, +1.000) existen en el log y coinciden en fecha, hora y monto con el reclamo de la socia.

## 2026-07-11 23:08 — Descarte de exploit sistémico

Se ha verificado ausencia de asignaciones manuales (`ManualAssignPoints`) y transferencias (`PointsTransference`) en el período — se descarta el patrón de exploit conocido en este caso.

## 2026-07-11 23:09 — Trazabilidad de sucursal y tarjeta

Se ha trazado el origen de las seis ventas del período vía `Sml.Sale`. Se ha confirmado que la tarjeta (`CustomerCardId` 5706842) es idéntica en todas las operaciones y que las sucursales coinciden con el patrón habitual de la socia — se descarta clonación de tarjeta y geolocalización anómala.

## 2026-07-11 23:10 — Cierre de investigación

Se ha documentado el hallazgo en `_ops.md`. Se ha propuesto verificar con la sucursal 3467 si hubo doble operación el 11/06, confirmar con la socia si comparte la tarjeta con un familiar, y, de no confirmarse ninguna de las dos hipótesis, acreditar 9.500 pts por compensación administrativa. Estado: pendiente decisión de operaciones.

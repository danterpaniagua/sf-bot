# Evento: Incremento de puntos acumulados — 02/06/2026

**Estado:** CERRADO — Sin fraude  
**Fecha de investigación:** 2026-06-02  
**Período analizado:** 07:00–08:00 UTC-3 (10:00–11:00 UTC)

---

## Origen de la alerta

Se detectó un incremento inusual en la cantidad de puntos insertados en la base de producción `SmartFran.Solution.SmartLoyalty` durante la franja horaria 07:00–08:00 UTC-3 del 02/06/2026. La revisión de los últimos 7 días confirmó que dicha franja no registraba actividad previa — el incremento fue el primer evento acumulado en ese horario en la semana.

---

## Hallazgos

| Métrica | Valor |
|---|---|
| Eventos totales | 25 |
| Puntos totales | 4.555 |
| Ventana activa | 10:19–10:45 UTC (26 minutos) |
| Clientes únicos | 7 |
| Transacciones POS (`SaleId` distintos) | 10 (252106268–252106277, secuenciales) |
| Asignaciones manuales | 0 |
| Transferencias involucradas | 0 |
| Superación de límite diario (3.000 pts) | Ninguno |
| Superación de límite semanal (5.000 pts) | Ninguno |

**Desglose por tipo de evento**

| EventTypeCode | Eventos | Puntos |
|---|---|---|
| `EarnPointsByBuying` | 21 | 4.555 |
| `EarnPointsByPromotion` | 3 | 0 |
| `Article99999WithoutPoints` | 1 | 0 |

**Detalle por cliente — ventana 07:00–08:00 UTC-3**

| Cliente | Documento | EventTypeCode | Transacciones | Puntos |
|---|---|---|---|---|
| Emiliano Casadio | DNI 30544063 | `EarnPointsByBuying` | 3 | 1.900 |
| Emiliano Casadio | DNI 30544063 | `EarnPointsByPromotion` | 1 | 0 |
| Daiana Diaz | DNI 36793447 | `EarnPointsByBuying` | 3 | 850 |
| Daiana Diaz | DNI 36793447 | `EarnPointsByPromotion` | 1 | 0 |
| Jesica Galván | DNI 36793456 | `EarnPointsByBuying` | 4 | 580 |
| German Zanier | DNI 27065746 | `EarnPointsByBuying` | 1 | 500 |
| Juan Marcelo Barrera | DNI 31404957 | `EarnPointsByBuying` | 3 | 430 |
| Juan Marcelo Barrera | DNI 31404957 | `Article99999WithoutPoints` | 1 | 0 |
| Carlos Mansilla | DNI 27395557 | `EarnPointsByBuying` | 5 | 165 |
| Carlos Mansilla | DNI 27395557 | `EarnPointsByPromotion` | 1 | 0 |
| Cristian Emanuel Cejas | DNI 47713718 | `EarnPointsByBuying` | 2 | 130 |

**Distribución temporal:** actividad irregular distribuida en 26 minutos. Sin concentración en ráfagas de segundos. No se detectó cadencia automatizada.

**Fuente:** todas las filas tienen `SaleId` real y `ManualAssignPointsId = NULL`. Los puntos se originaron en transacciones POS legítimas.

---

## Cliente de mayor acumulación

**Emiliano Casadio — DNI 30544063**

| Período | Puntos | Límite | Estado |
|---|---|---|---|
| Día (02/06) | 1.900 | 3.000 | ✓ |
| Últimos 7 días | 1.900 | 5.000 | ✓ |
| Últimos 30 días | 2.125 | 10.000 | ✓ |

Historial previo confirmado: sesión del 14/05/2026 con 225 pts en 4 eventos. Cliente activo con actividad previa real. El incremento respecto a la sesión anterior se atribuye a la compra de artículos de mayor valor de puntos (Art. 12 y 13, 700 pts c/u, venta 252106268).

---

## Conclusión

La actividad del período investigado corresponde a acumulaciones por compra legítimas procesadas a través del POS. No se identificaron indicadores de fraude: sin asignaciones manuales, sin automatización, sin superación de límites, sin transferencias encadenadas, sin cuentas mula.

El incremento en la franja horaria 07:00–08:00 UTC-3 se explica por actividad de compra real en una franja que históricamente no registraba eventos. **No se requiere acción.**

---

*Investigación realizada el 2026-06-02. Analista: Dante Paniagua.*

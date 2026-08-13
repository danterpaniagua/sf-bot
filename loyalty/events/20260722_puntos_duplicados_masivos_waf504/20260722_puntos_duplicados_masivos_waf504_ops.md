# Duplicación masiva de puntos por reintentos ante error 504 de WAF — CERRADO

## Resumen del incidente

El 22/07/2026, Grido ejecutó una asignación masiva de puntos (`MassivePointsAssignment`, `EventTypeCode = PrizePoints`) sobre varios listados de socios ganadores. El WAF devolvió error 504 al cliente por timeout de respuesta, pero la ejecución del lado del servidor no se cancela ante un 504 de WAF — el proceso siguió corriendo en el servidor (11 min a 1.5 h por corrida). El operador, al ver el 504, reintentó la misma operación varias veces, generando ejecuciones concurrentes sobre listados que en la práctica apuntaban a la misma población objetivo (mismos socios repetidos entre "Lista socios ganadores", "Lista 1", "Lista 2" y "Campaña recupero"). El proceso `MassivePointsAssignment` / `AssignmentPointsCatalog` no tiene control de idempotencia, por lo que cada corrida otorgó puntos de forma independiente al mismo socio.

**Resolución:** reversión total de lo duplicado (376.450.000 pts) + reasignación manual correcta de la campaña (79.400.000 pts), ambas ejecutadas y verificadas contra producción. Sin acciones pendientes de este incidente.

## Métricas

| Métrica | Valor |
|---|---|
| Fecha del incidente | 2026-07-22 |
| EventTypeCode original | PrizePoints |
| Clientes impactados por la campaña (4 listas) | 7.940 |
| Puntos totales otorgados (4 listas) | 376.450.000 |
| Clientes con exceso real (`TotalPoints > 10.000`) | 7.930 |
| Exceso a revertir | 297.050.000 |
| **Puntos revertidos (100% de las 4 listas, ejecutado)** | **376.450.000** |
| **Puntos reasignados correctamente (campaña re-corrida, ejecutado)** | **79.400.000** |

## Desglose por Note (listado de campaña)

| Note | Clientes distintos | Lotes distintos (reintentos) | Filas totales | Puntos totales |
|---|---|---|---|---|
| Lista socios ganadores | 7.907 | 3 | 23.721 | 237.210.000 |
| Lista 1 socios ganadores | 3.984 | 2 | 7.968 | 79.680.000 |
| Lista 2 socios ganadores | 3.956 | 1 | 3.956 | 39.560.000 |
| Campaña recupero | 2.000 | 1 | 2.000 | 20.000.000 |
| **Total** | 17.847 (con solapamiento entre listas) | — | 37.645 | **376.450.000** |

"Lista socios ganadores" concentra el 63% del exceso por sí sola (3 lotes = 2 reintentos de más sobre el mismo listado); "Lista 1" fue reenviada una vez; "Lista 2" y "Campaña recupero" no tuvieron reintento propio — su exceso proviene enteramente del solapamiento con los otros listados (mismos socios, listas distintas).

## Detalle de participantes

Listado completo (`CustomerId`, `DocumentType`, `DocumentNumber`, Notes/Batches, puntos, exceso, IDs de batch) de los 7.930 clientes con exceso real: `implicated_customers.csv`.

Agregado por patrón de duplicación:

| Patrón | Clientes | Puntos totales | Exceso |
|---|---|---|---|
| 3 Notes distintos impactando al mismo cliente | 1.987 | 119.220.000 | 99.350.000 |
| 2 Notes distintos impactando al mismo cliente | 5.933 | 256.930.000 | 197.600.000 |
| 1 Note (caso límite) | 20 | 300.000 | 100.000 |
| **Total** | **7.940** | **376.450.000** | **297.050.000** |

**Caso límite (20 clientes, 1 Note):** se desagrega en dos subgrupos limpios — 10 clientes con un único grant de 10.000 bajo "Lista 2" (sin duplicado, sin exceso) y 10 clientes impactados dos veces dentro de "Lista 1" (mismo Note, dos batches, 20.000 pts, 100.000 pts de exceso en total). Ambos subgrupos quedaron cubiertos por la reversión total. Detalle: `caso_limite_query5.csv`.

## Contabilidad de puntos

| Actor | Rol | Pts Totales (exceso) | Recuperable | No Recuperable |
|---|---|---|---|---|
| Población con exceso real (7.930 socios — ver `implicated_customers.csv`) | Socios Club Grido, destinatarios de la campaña | 297.050.000 | Ver estado final abajo | Ver estado final abajo |

No aplica el eje de origen de cuenta — a diferencia de una investigación de fraude, esta población son socios legítimos, afectados por una falla operativa, no por actividad sospechosa de cuenta.

**Estado final de puntos** (calculado sobre la población completa de reversión, 7.940 socios / 376.450.000 pts, previo a la reversión):

| Estado | Clientes | Puntos |
|---|---|---|
| Activo (cuenta no desactivada) | 7.940 | 376.450.000 (100%) |
| — Gastado (`DiscountPointsByExchange`, irreversible) | 15 | 48.100 |
| — Transferido (`PointsByTransferSent`) | 17 | 104.970 |
| — Activo/recuperable (balance intacto) | ~7.910 | 376.296.930 |
| Retenido (cuenta desactivada) | 0 | 0 |

99,96% del monto a revertir seguía como balance activo al momento de la reversión. Cero cuentas retenidas/desactivadas. Los 48.100 pts gastados son irreversibles por diseño; los 104.970 transferidos quedarían rastreables hacia la cuenta receptora si se decide perseguirlos (no ejecutado, fuera de alcance).

## Reversión — ejecutada y verificada

Se decidió revertir el **100% de los puntos otorgados** bajo las cuatro listas (incluyendo "Campaña recupero") en vez de sólo el exceso por cliente, dado que la campaña se iba a volver a correr desde cero.

| Note | Puntos revertidos |
|---|---|
| Lista socios ganadores | 237.210.000 |
| Lista 1 socios ganadores | 79.680.000 |
| Lista 2 socios ganadores | 39.560.000 |
| Campaña recupero | 20.000.000 |
| **Total** | **376.450.000** |

Convención: una transacción por fila original (`CustomerId` + `ManualAssignPointsId`), `Points` negativo, `EventTypeCode = PointsAdjustmentBatchError-{batchid}`, `Note = 'Ajustamos tu saldo por un error de asignacion de puntos'`.

**Hallazgo de seguridad previo a la ejecución:** el trigger `CustomerPointsLogAfterInsert` (activo en `Sml.CustomerPointsLog`) recalcula el saldo cacheado del cliente en `SmlSt.CustomerPointsLog` uniendo `inserted` contra el historial completo por `CustomerId`, sin condición adicional de fila — un `INSERT` con más de una fila por cliente multiplica el saldo recalculado por esa cantidad de filas (fan-out). Los clientes de esta reversión tenían entre 1 y 6 filas cada uno; un `INSERT` masivo de las 37.645 filas habría corrompido el saldo cacheado de ~7.930 de los 7.940 clientes. `EventTypeCode` no tiene FK — el valor dinámico usado es seguro.

**Mitigación y ejecución:** 6 pasadas secuenciales (`ROW_NUMBER() OVER (PARTITION BY CustomerId ...)`, máximo 1 fila por cliente por pasada), verificando `@@ROWCOUNT` antes de cada `COMMIT`:

| Pasada | Filas esperadas | Filas obtenidas |
|---|---|---|
| 1 | 7.940 | 7.940 ✓ |
| 2 | 7.930 | 7.930 ✓ |
| 3 | 7.920 | 7.920 ✓ |
| 4 | 7.907 | 7.907 ✓ |
| 5 | 3.961 | 3.961 ✓ |
| 6 | 1.987 | 1.987 ✓ |
| **Total** | **37.645** | **37.645 ✓** |

Verificación final por query directa: `COUNT(*)` / `SUM(Points)` de filas `PointsAdjustmentBatchError-%` de ese día = 37.645 filas / -376.450.000 pts, coincide exactamente. Búsqueda de `CustomerId`+`EventTypeCode` duplicados = 0 filas.

Bug de alias corregido en el proceso (Q5, Q7, Q10): `p.UidSerie AS DocumentType, p.UidCode AS DocumentNumber` estaba invertido respecto de la convención del proyecto (`UidCode` = tipo de documento, `UidSerie` = número). Corregido en `_scripts.sql` y en los CSV de salida.

Registro verbatim con timestamps: `20260722_puntos_duplicados_masivos_waf504_reversion_evidencia.md`.

## Reasignación de la campaña — ejecutada y verificada

Es la corrida "desde cero" de la campaña: 10.000 pts a cada uno de los 7.940 socios ganadores (`EventTypeCode = 'ManualPrizePoints'`, `Note = 'Puntos por visita frecuente'`), desde `assignment.csv`. Hecha a mano vía SQL validado en vez de `MassivePointsAssignment`, justamente para no repetir la falta de idempotencia que causó el incidente original — validación de integridad referencial y de duplicados antes y después de escribir.

| Paso | Resultado |
|---|---|
| Crear tabla de staging (`SmlTemp.Assignment_20260722_VisitaFrecuente`) | OK |
| Cargar `assignment.csv` | `BULK INSERT` falló (path del cliente no accesible desde el servidor); reemplazado por 8 lotes `INSERT...VALUES` sin dependencia de filesystem del servidor. 7.940/7.940 filas |
| Verificar carga | 7.940 filas ✓ |
| Validar integridad referencial (`CustomerId` vs `Sml.Customer`) | 0 filas sin correspondencia ✓ |
| `INSERT` real (un solo `INSERT` — cada cliente aparece una vez, no aplica el bug de fan-out) | 7.940 filas ✓ |
| Verificación final por query | 7.940 filas, 79.400.000 pts ✓ |
| Limpieza (`DROP TABLE`) | OK |

Registro verbatim: `20260722_puntos_duplicados_masivos_waf504_asignacion_evidencia.md`.

## Recomendaciones a futuro

1. Agregar control de idempotencia a `MassivePointsAssignment`/`AssignmentPointsCatalog` (`RequestId` o hash del listado) para que reintentos ante timeout de WAF no dupliquen la asignación en próximas campañas.
2. Aumentar el timeout del WAF para esta operación específica, o mover `MassivePointsAssignment` a un flujo asincrónico (encolar y confirmar por polling) para que un timeout de gateway no incentive reintentos manuales sobre una operación de larga duración.

## Referencia de queries

Ver `20260722_puntos_duplicados_masivos_waf504_scripts.sql`.

| # | Query | Propósito |
|---|---|---|
| Q1 | `fn_my_permissions` | Permisos efectivos del login (denegado sobre `Sml.ManualAssignPoints`, concedido sobre `Sml.CustomerPointsLog`) |
| Q2 | Descubrimiento de lotes | `ManualAssignPointsId` de hoy agrupados por `Note` |
| Q3 | Duplicados dentro del mismo Note | Clientes impactados más de una vez por el mismo listado |
| Q4 | Solapamiento cruzado entre Notes | Confirma que distintos Notes apuntan a la misma población objetivo |
| Q5 | Detalle del caso límite | Resuelto por análisis directo del resultado de Q10, sin necesidad de ejecutarla |
| Q6a-c | Estado gastado/activo/transferido/retenido | Ejecutada — ver sección "Contabilidad de puntos" |
| Q7 | Listado completo de clientes implicados | Resuelto por derivación desde Q10, exportado a `implicated_customers.csv` |
| Q8 | Conteo agregado por Note | Base del desglose por listado |
| Q9 | EventTypeCode distintos del día | Descubrimiento inicial |
| Q10 | Especificación de reversión (solo lectura) | Base de Q11 |
| Q11 | Reversión (DML, 6 pasadas) | Ejecutada y verificada |
| Q12 | Reasignación de campaña (DML) | Ejecutada y verificada |

## Archivos de evidencia

| Archivo | Contenido |
|---|---|
| `20260722_puntos_duplicados_masivos_waf504_scripts.sql` | Todas las queries, Q1-Q12 |
| `implicated_customers.csv` | 7.930 clientes con exceso real |
| `caso_limite_query5.csv` | Detalle de los 20 clientes del caso límite |
| `20260722_puntos_duplicados_masivos_waf504_query10_reversion.tsv` | Especificación fila-por-fila de la reversión (37.645 filas) |
| `assignment.csv` | Listado fuente de la reasignación de campaña (7.940 `CustomerId`) |
| `20260722_puntos_duplicados_masivos_waf504_q12_paso2_values.sql` | Carga de `assignment.csv` en 8 lotes |
| `20260722_puntos_duplicados_masivos_waf504_reversion_evidencia.md` | Registro verbatim de la ejecución de Q11 (6 pasadas) |
| `20260722_puntos_duplicados_masivos_waf504_asignacion_evidencia.md` | Registro verbatim de la ejecución de Q12 |
| `20260722_puntos_duplicados_masivos_waf504_email_pm.md` | Email de cierre para PMs |
| `20260722_puntos_duplicados_masivos_waf504_ops-events.md` | Log cronológico completo de la investigación y ejecución |

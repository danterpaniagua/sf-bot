# Evidencia de ejecución — Reversión Query 11 (20260722_puntos_duplicados_masivos_waf504)

Registro verbatim de la ejecución de Query 11 (`_scripts.sql`), 6 pasadas secuenciales, cada una con verificación de `@@ROWCOUNT` contra el valor esperado antes de `COMMIT`. Total esperado: **37.645 filas**, **-376.450.000 pts**.

## Intento inicial (login sin permisos de escritura)

| Campo | Valor |
|---|---|
| Resultado | `Msg 229, Level 14, State 5, Line 325` — INSERT permission denegado sobre `Sml.CustomerPointsLog` |
| RowsInserted | 0 |
| Timestamp | 2026-07-22T18:55:30.1370084+00:00 |
| Acción | `ROLLBACK` de la transacción abierta. Confirma lo ya documentado en Q1 (login de investigación sin permiso de escritura). Reversión continuada con cuenta con permisos de escritura. |

## Pasadas 1-6

| Pasada | Filas esperadas | Filas obtenidas (`RowsInserted`) | Timestamp de finalización | Estado |
|---|---|---|---|---|
| 1 | 7.940 | 7.940 | 2026-07-22T18:56:22.6945090+00:00 | Coincide. `COMMIT` confirmado ("Commands completed successfully", 2026-07-22T18:57:02.2039144+00:00) |
| 2 | 7.930 | 7.930 | 2026-07-22T18:57:32.7359483+00:00 | Coincide. `COMMIT` instruido |
| 3 (resultado ambiguo) | 7.920 | 7.930 (idéntico al de la Pasada 2, mismo timestamp) | 2026-07-22T18:57:32.7359483+00:00 | **No confiable** — mismo `RowsInserted` y mismo timestamp que la Pasada 2; se interpretó como error de copy-paste, no como ejecución real. Se pidió no hacer `COMMIT` y verificar `@@TRANCOUNT` antes de continuar |
| 3 (real) | 7.920 | 7.920 | 2026-07-22T18:58:35.2723103+00:00 | Coincide (timestamp distinto al anterior, confirma ejecución real). Usuario hizo `COMMIT` sin ejecutar la verificación de `@@TRANCOUNT` solicitada |
| 4 | 7.907 | 7.907 | 2026-07-22T19:01:36.8526188+00:00 | Coincide. `COMMIT` instruido |
| 5 | 3.961 | 3.961 | 2026-07-22T19:02:25.3077672+00:00 | Coincide. `COMMIT` instruido |
| 6 | 1.987 | 1.987 | 2026-07-22T19:04:04.3038262+00:00 | Coincide. `COMMIT` instruido |

**Nota sobre confirmación de `COMMIT`:** las Pasadas 1 y 3 tienen confirmación explícita de `COMMIT` por parte del usuario (mensaje de éxito o declaración directa "3 commited"). Las Pasadas 2, 4 y 5 recibieron la instrucción de hacer `COMMIT` antes de continuar con la siguiente pasada; se asume ejecutado dado que la sesión continuó normalmente a la pasada siguiente, pero no hay confirmación textual explícita en el registro de conversación para esas tres pasadas puntuales.

## Verificación post-Pasada 3 (motivada por el resultado ambiguo)

Ejecutada porque el `COMMIT` de la Pasada 3 se hizo sin la verificación de `@@TRANCOUNT` solicitada — se verificó el estado real de la tabla en lugar de confiar en el output de sesión.

| Query | Resultado | Timestamp |
|---|---|---|
| `COUNT(*)` y `SUM(Points)` de filas `PointsAdjustmentBatchError-%` de hoy | 23.790 filas, -237.900.000 pts — coincide exactamente con 3 pasadas limpias (7.940+7.930+7.920) | 2026-07-22T18:59:49.7425730+00:00 |
| Búsqueda de `CustomerId`+`EventTypeCode` duplicados entre esas filas | 0 filas — sin duplicados | 2026-07-22T19:00:49.4762376+00:00 |

**Conclusión de la verificación:** el resultado ambiguo de la Pasada 3 fue un error de copy-paste en la sesión, no una ejecución duplicada real. No hay filas de reversión duplicadas en producción a esa fecha/hora.

## Totales acumulados hasta la Pasada 5 (confirmado por conteo esperado, no re-verificado por query después de la Pasada 4)

| Pasadas completas | Filas acumuladas esperadas | Puntos acumulados esperados |
|---|---|---|
| 1-5 | 35.658 | -356.580.000 |
| 1-6 (al completarse) | 37.645 | -376.450.000 |

## Verificación final (post-Pasada 6)

| Query | Resultado | Timestamp |
|---|---|---|
| `COUNT(*)` y `SUM(Points)` de filas `PointsAdjustmentBatchError-%` de hoy | **37.645 filas, -376.450.000 pts** — coincide exactamente con el total esperado (6 pasadas limpias) | 2026-07-22T19:04:48.0711096+00:00 |
| Búsqueda de `CustomerId`+`EventTypeCode` duplicados entre esas filas | **0 filas** — sin duplicados | 2026-07-22T19:04:48.0711096+00:00 |

## Estado: REVERSIÓN COMPLETA Y VERIFICADA

Las 6 pasadas de Query 11 se ejecutaron y confirmaron. El total insertado (37.645 filas, -376.450.000 pts) coincide exactamente con el monto validado en `_ops.md` para las cuatro listas de la campaña. Verificación de duplicados por query (no sólo por conteo de filas de sesión) confirma cero filas de reversión repetidas. No quedan pasadas pendientes.

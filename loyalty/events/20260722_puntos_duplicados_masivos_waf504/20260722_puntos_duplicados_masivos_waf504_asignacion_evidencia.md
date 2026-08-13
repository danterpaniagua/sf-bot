# Evidencia de ejecución — Query 12: reasignación manual de la campaña ("Puntos por visita frecuente")

**Esta es la corrida "desde cero" de la campaña**, ya anunciada en la Decisión de reversión de `_ops.md` — hecha a mano vía SQL validado (staging + verificación de integridad referencial + verificación de duplicados) en vez de reutilizar `MassivePointsAssignment`, la herramienta sin control de idempotencia que causó el incidente original. Coincide con la misma población de 7.940 clientes ya revertida porque son los mismos ganadores de la campaña — confirmado explícitamente con el usuario antes de generar cualquier DML. Registro verbatim de la ejecución de Query 12 (`_scripts.sql`).

## Verificación previa de superposición de población

Antes de generar cualquier DML se comparó `assignment.csv` (7.940 `CustomerId`, 0 duplicados) contra la población ya revertida de este mismo ticket (`query10_reversion.tsv`): superposición del 100% (7.940 de 7.940, sin adiciones ni omisiones). Se preguntó explícitamente al usuario si era intencional antes de continuar — confirmó que sí.

## Paso 1 — Crear tabla de staging

`CREATE TABLE SmlTemp.Assignment_20260722_VisitaFrecuente (CustomerId UNIQUEIDENTIFIER NOT NULL PRIMARY KEY);` — ejecutado sin errores reportados.

## Paso 2 — Carga de datos

**Intento 1 (`BULK INSERT` desde archivo):** falló — `Msg 4860, Level 16, State 1`: `Cannot bulk load. The file "C:\Users\dantep\Documents\assignment.csv" does not exist or you don't have file access rights.` (2026-07-22T19:21:27.0684795+00:00). Causa: el path es local a la máquina cliente, no visible para el motor de SQL Server en `SFCG-DB01`.

**Intento 2 (`INSERT...VALUES` en 8 lotes, generados localmente desde `assignment.csv`, sin dependencia de filesystem del servidor):** ver `20260722_puntos_duplicados_masivos_waf504_q12_paso2_values.sql`. Resultado, 8 lotes ejecutados en orden:

| Lote | Filas esperadas | Filas obtenidas |
|---|---|---|
| 1 | 1.000 | 1.000 ✓ |
| 2 | 1.000 | 1.000 ✓ |
| 3 | 1.000 | 1.000 ✓ |
| 4 | 1.000 | 1.000 ✓ |
| 5 | 1.000 | 1.000 ✓ |
| 6 | 1.000 | 1.000 ✓ |
| 7 | 1.000 | 1.000 ✓ |
| 8 | 940 | 940 ✓ |
| **Total** | **7.940** | **7.940 ✓** |

Timestamp de finalización del conjunto: 2026-07-22T19:25:27.7129456+00:00.

## Paso 3 — Verificación de carga

`SELECT COUNT(*) FROM SmlTemp.Assignment_20260722_VisitaFrecuente` → **7.940** filas. Coincide exactamente. Timestamp: 2026-07-22T19:26:00.5625299+00:00.

## Paso 4 — Validación de integridad referencial

Búsqueda de `CustomerId` en staging sin correspondencia en `Sml.Customer` → **0 filas**. Todos los `CustomerId` son válidos; el `INSERT` real no fallaría por FK. Timestamp: 2026-07-22T19:26:16.2989087+00:00.

## Paso 5 — INSERT real

`INSERT INTO Sml.CustomerPointsLog` desde la tabla de staging (un solo `INSERT`, sin necesidad de pasadas múltiples — cada cliente aparece una sola vez en la fuente, no aplica el bug de fan-out del trigger `CustomerPointsLogAfterInsert` documentado en Q11).

| Campo | Valor |
|---|---|
| Filas esperadas | 7.940 |
| Filas obtenidas (`RowsInserted`) | 7.940 ✓ |
| Timestamp | 2026-07-22T19:26:51.6713621+00:00 |
| `COMMIT` | Instruido tras confirmar coincidencia |

## Paso 6 — Verificación final por query

`SELECT COUNT(*), SUM(Points) FROM Sml.CustomerPointsLog WHERE EventTypeCode = 'ManualPrizePoints' AND LogDate >= '2026-07-22' AND LogDate < '2026-07-23'` → **7.940 filas, 79.400.000 pts**. Coincide exactamente con lo esperado (7.940 clientes × 10.000 pts). Timestamp: 2026-07-22T19:27:28.3960752+00:00.

## Paso 7 — Limpieza

`DROP TABLE SmlTemp.Assignment_20260722_VisitaFrecuente` — instruido tras confirmar el Paso 6.

## Estado: REASIGNACIÓN COMPLETA Y VERIFICADA — CAMPAÑA CERRADA

7.940 socios ganadores recibieron 10.000 pts cada uno (`EventTypeCode = 'ManualPrizePoints'`, `Note = 'Puntos por visita frecuente'`) — 79.400.000 pts totales, verificado por query directa contra producción. Esta es la corrida "desde cero" de la campaña de premios afectada por el incidente WAF-504 — cierra el incidente de punta a punta: reversión de lo duplicado (Query 11) + reasignación correcta y sin duplicados (Query 12).

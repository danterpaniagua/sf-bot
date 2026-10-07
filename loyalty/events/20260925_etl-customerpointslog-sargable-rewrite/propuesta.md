# Propuesta técnica — Reescritura sargable de la consulta ETL `CustomerPointsLog`

**Para:** Equipo Dev — SmartLoyalty
**De:** Dante Paniagua, SRE
**Ticket Jira:** [GITIN-2108](https://smartit-ar.atlassian.net/browse/GITIN-2108)

## Resumen

La operación ETL `CustomerPointsLog` (`Etl.EtlOperationConfig`, `Id = 6`, `ToTable = dbo.CustomerPointsLog`, ejecutada por TaskOperatorService) tiene un rendimiento crónicamente bajo — **~10 a 20 filas/segundo**, confirmado sobre 23 corridas en 30 días (investigación original, `events/20260715_cpu_spikes/`) y consistente con las corridas más recientes (hoy, 2026-09-25: 3h40m32s para 153.082 filas). La causa es un predicado `OR` no sargable en su `FromQuery`, que impide cualquier acceso por índice. Se propone reemplazarlo por dos ramas sargables unidas con `UNION ALL`, ya diseñadas y ahora con soporte de índice confirmado para ambas — no requiere DDL nueva.

## Por qué esto importa ahora, no solo en julio

El reagendamiento aplicado bajo GITIN-2060 (mover esta operación a las 05:00 UTC) evitó la doble contención con `Backup_FULL` los lunes, pero solo trabajó sobre el horario, no sobre la duración de la operación misma. `Backup_FULL` corre hoy domingo/miércoles/viernes a las 09:00 UTC. La corrida de hoy (viernes) terminó a las 08:43 UTC — **a solo 17 minutos** del inicio de `Backup_FULL`. El peor caso conocido (lunes, ~5,4h promedio, o el outlier histórico de 25,9h) atravesaría por completo esa ventana cualquier domingo, miércoles o viernes. La reescritura elimina el riesgo en la fuente en vez de seguir angostando el margen del horario.

## Causa raíz

El `FromQuery` combina con `OR` dos condiciones sobre columnas de tablas distintas (`c.CreatedDate` y `cpl.LogDate`). Un `OR` entre columnas de tablas distintas no es sargable — el optimizador no puede resolverlo con un seek por índice sobre ninguna de las dos columnas y recurre a un scan del join completo. El framework ETL además antepone un probe de conteo (`COUNT(*) OVER()`) sobre la misma consulta antes de paginar, duplicando el costo del scan en cada ejecución.

Origen en código: `Other/SqlScript/Updates/v10.07.00/v10.07.00_UpdateETLConfigForSync.sql:399-431` (repo `dev-src-sol-smartloyalty`, rama `main`).

## Propuesta — reescritura sargable

Las dos ramas del `OR` original ya son mutuamente excluyentes (cliente nuevo vs. cliente existente), por lo que se pueden separar en dos `SELECT` sargables unidos por `UNION ALL`, sin necesidad de deduplicar:

```sql
SELECT cpl.Id as CustomerPointsLogId
      ,EventTypeCode
      ,CustomerId
      ,LogDate
      ,Points
      ,SYSDATETIMEOFFSET() as _SyncDate
FROM Sml.CustomerPointsLog cpl (nolock)
INNER JOIN Sml.Customer c (nolock) ON cpl.CustomerId = c.Id
WHERE @LowerBoundary IS NOT NULL
  AND c.CreatedDate >= @LowerBoundary
  AND c.CreatedDate < @UpperBoundary
  AND cpl.LogDate < @UpperBoundary

UNION ALL

SELECT cpl.Id as CustomerPointsLogId
      ,EventTypeCode
      ,CustomerId
      ,LogDate
      ,Points
      ,SYSDATETIMEOFFSET() as _SyncDate
FROM Sml.CustomerPointsLog cpl (nolock)
INNER JOIN Sml.Customer c (nolock) ON cpl.CustomerId = c.Id
WHERE (@LowerBoundary IS NULL OR cpl.LogDate >= @LowerBoundary)
  AND cpl.LogDate < @UpperBoundary
  AND (@LowerBoundary IS NULL OR c.CreatedDate < @LowerBoundary)

ORDER BY CustomerPointsLogId
```

- **Rama A** (`c.CreatedDate` — cliente nuevo): seek directo sobre `Sml.Customer.__IX_Customer_CreatedDate`. Ahora exige `@LowerBoundary IS NOT NULL` explícitamente — ver corrección abajo.
- **Rama B** (`cpl.LogDate` — cliente existente): seek directo sobre el índice **clustered** de `Sml.CustomerPointsLog` (la tabla está particionada por `LogDate` y ese es literalmente el key del clustered index) — el mejor acceso posible, no solo eliminación de partición.

### Corrección aplicada (2026-09-25): las ramas no eran mutuamente excluyentes cuando `@LowerBoundary IS NULL`

El borrador original de julio tenía un bug de correctitud, no solo de performance, detectado al re-revisar la lógica booleana: cuando `@LowerBoundary IS NULL` (primera corrida / recuperación de backlog completo), ambos guards `(@LowerBoundary IS NULL OR ...)` colapsan a `TRUE`, y la condición de Rama B (`cpl.LogDate < @UpperBoundary` sola) termina siendo un superconjunto de la condición de Rama A (`c.CreatedDate < @UpperBoundary AND cpl.LogDate < @UpperBoundary`) — toda fila que cumple Rama A también cumple Rama B, duplicando prácticamente cada fila en el `UNION ALL`. Esto no existe en la consulta `OR` actual en producción (un `OR` simple no puede duplicar una fila) — es una regresión que introducía específicamente la reescritura con `UNION ALL`.

**Corrección**: Rama A ahora exige `@LowerBoundary IS NOT NULL` sin condicional — devuelve cero filas en una corrida sin watermark, y Rama B sola cubre correctamente todo el rango histórico en ese caso (separar "cliente nuevo" de "cliente existente" no tiene sentido sin un watermark contra el cual ser "nuevo"). Las corridas incrementales normales (`@LowerBoundary` definido) no cambian de comportamiento.

## Evidencia — soporte de índice confirmado (2026-09-25)

Verificado directamente contra `sys.indexes`/`sys.index_columns`, no asumido:

| Tabla | Índice | Tipo | Columna líder |
|---|---|---|---|
| `Sml.CustomerPointsLog` | `ClusteredIndex_sch_LogDate_Anual` | CLUSTERED | `LogDate` (key_ordinal=1) |
| `Sml.Customer` | `__IX_Customer_CreatedDate` | NONCLUSTERED | `CreatedDate` DESC (key_ordinal=1) |

**Ambas ramas tienen soporte de índice confirmado — no se requiere crear ningún índice nuevo.** Resultado crudo: `data/customerpointslog_indexes_20260925.txt`, `data/customer_indexes_20260925.txt`.

## Qué falta validar antes de llevar esto a producción

1. **Tolerancia del framework ETL al `ORDER BY`.** El `FromQuery` original termina en `ORDER BY cpl.Id`; con `UNION ALL` el `ORDER BY` solo puede referirse a la columna de salida (`ORDER BY CustomerPointsLogId`). El framework externo (`SmartFran.Business.Etl.*`, no incluido en este repo) envuelve el `FromQuery` en un probe de conteo y en el fetch paginado — si localiza/recorta el `ORDER BY` por texto exacto en vez de parsear el SQL, este cambio de alias podría romper ese mecanismo. Necesita confirmarse contra el comportamiento real del framework, o con una captura en QA.
2. **Validación de equivalencia en QA.** Confirmar que el resultado del `UNION ALL` es exactamente igual al del `OR` original — comparar conteos y una muestra de filas para un mismo rango de fechas, antes de reemplazar la configuración en producción. **Incluir explícitamente el caso `@LowerBoundary IS NULL`** (primera corrida / recuperación de backlog completo) en esa validación, no solo corridas incrementales en estado estable — es justo el caso donde el bug de duplicación (ver corrección arriba) se manifestaba.
3. **Dónde entregar el cambio.** Como script nuevo versionado en `Other/SqlScript/Updates/`, siguiendo el patrón existente — no modificar el script `v10.07.00` ya aplicado.

## Beneficio esperado — con una salvedad real, no solo formal

Esto ataca un costo real y confirmado del lado de la consulta origen — no es especulativo, la captura de julio mostró lecturas lógicas creciendo de 10.442 a 278.573 dentro de una misma ejecución del `SELECT`, con `PAGEIOLATCH_SH` (I/O de lectura) como wait type dominante, consistente con el scan que provoca el `OR` no sargable.

**Lo que todavía no está establecido**: qué proporción de las 3-6h totales corresponde a esta consulta origen versus el costo de escribir los datos en destino. Confirmado recién (`Etl.EtlOperationConfig.Id=6`: `InputConnStr=SmlConnString`, `OutputConnStr=DwConnString`) que origen y destino son **conexiones distintas** — esto no es una sincronización entre dos tablas de la misma base, es OLTP hacia un Data Warehouse separado, por red. La captura de julio fue una porción de ~3 minutos de una corrida de 3h34m — prueba que la consulta origen es cara en algún momento de la corrida, no qué fracción del total representa frente a los batches de escritura hacia el DW (`BatchSize=1000000`/`SetSize=100000`).

**Conclusión honesta**: esta reescritura corrige un costo real, pero no puedo afirmar hoy que resuelva la mayor parte de las 3-6h hasta medir esa proporción con una captura durante una corrida completa (no solo una porción). Reduce en cualquier caso el riesgo de colisión con `Backup_FULL` los domingos/miércoles/viernes descripto arriba, independientemente de cuánto mejore la duración total.

**Actualización (2026-09-25) — primera comparación real, resultado mixto.** Ejecutadas ambas versiones (actual vs. propuesta) sobre la misma ventana real de 153.082 filas, con `SET STATISTICS IO/TIME ON`:
- **Correctitud confirmada al 100%** — los seis valores agregados (incluyendo un checksum sobre todas las filas) coinciden exactamente entre ambas versiones.
- **CPU time cayó ~3,5x** (1.007.206 ms → 285.875 ms) — la métrica más directamente relacionada con el problema original de picos de CPU.
- **Pero el tiempo transcurrido (wall-clock) casi se duplicó** (146.178 ms → 299.754 ms), y las lecturas lógicas de `CustomerPointsLog` también casi se duplicaron (2.136.826 → 4.273.569). Causa más probable: la consulta actual obtuvo un plan paralelo (~7 workers), la propuesta corrió esencialmente en serie — menos trabajo total, pero repartido en menos workers.
- Se encontró y corrigió una asimetría en la metodología de prueba (un `ORDER BY` presente solo en una de las dos consultas de prueba, no en la real producción). **Los números de wall-clock/lecturas de arriba están pendientes de una re-corrida justa** antes de tomarlos como definitivos — el resultado de CPU y de correctitud sí se mantienen.

**No recomendar avanzar a producción todavía** — el resultado de CPU es alentador, pero el aumento de wall-clock (si se confirma tras la re-corrida) podría empeorar, no mejorar, el riesgo de colisión con `Backup_FULL` que motivó revisar esto. Falta también el plan de ejecución real (no solo `STATISTICS IO/TIME`) para entender por qué las lecturas de `CustomerPointsLog` subieron en vez de bajar.

Cualquier corrección o comentario, bienvenido antes de avanzar con la validación en QA.

Saludos,
Dante

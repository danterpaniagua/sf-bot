Para: Dev — SmartLoyalty.WebServiceV2
De: Dante Paniagua, SRE
Asunto: Query101 — fix validado contra datos reales, listo para aplicar

Hola equipo,

Este es el mismo hallazgo documentado en GITIN-1267 (2026-05-17) — recurrió y generó los picos de CPU de ayer (GITIN-2074). Ya creamos los índices propuestos en ese momento, pero confirmamos que **no alcanzan solos**: la consulta necesita el rewrite también. Buena noticia — probamos el rewrite completo contra datos reales de producción hoy y funciona.

## El problema

`Query101-sql.xml` filtra por `CardNumber OR (UidCode + UidSerie)`. El `OR`, combinado con `LOWER()` sobre `UidCode`, le impide al optimizador usar cualquier índice — ni siquiera el de `CardNumber`, aunque exista.

```sql
DECLARE @CardNumber NVARCHAR(100) = @p0
DECLARE @UidCode NVARCHAR(100) = @p1
DECLARE @UidSerie NVARCHAR(100) = @p2
SELECT ai.FavoriteProduct, ai.AverageWeight, ai.LastBuyDate, a.Name AS FavoriteProductName
FROM [SmlSt].[CustomerAdditionalInformation] ai
LEFT JOIN [Sml].[Article] a ON TRY_CAST(ai.FavoriteProduct AS INT) = a.Id
WHERE ai.CardNumber = @CardNumber OR
(
    @UidCode IS NOT NULL
    AND @UidSerie IS NOT NULL
    AND LOWER(ai.UidCode) = LOWER(@UidCode)
    AND ai.UidSerie = @UidSerie
)
```

## Prueba con datos reales — confirmado con `SET STATISTICS IO`

Con un `CardNumber` real, la consulta actual hace **104.970 lecturas lógicas** contra `CustomerAdditionalInformation` (scan del índice clustered completo). Quitando el `OR` y dejando solo `CardNumber`, con el índice nuevo ya creado (`IX_CustomerAdditionalInformation_CardNumber`), baja a **4 lecturas** — un seek limpio, confirmado también en el plan de ejecución.

## El fix — ya probado contra datos reales, ambas ramas

```sql
DECLARE @CardNumber NVARCHAR(100) = {0}
DECLARE @UidCode    NVARCHAR(100) = {1}
DECLARE @UidSerie   NVARCHAR(100) = {2}

SELECT ai.FavoriteProduct, ai.AverageWeight, ai.LastBuyDate,
       a.Name AS FavoriteProductName
FROM [SmlSt].[CustomerAdditionalInformation] ai
LEFT JOIN [Sml].[Article] a ON TRY_CAST(ai.FavoriteProduct AS INT) = a.Id
WHERE ai.CardNumber = @CardNumber

UNION

SELECT ai.FavoriteProduct, ai.AverageWeight, ai.LastBuyDate,
       a.Name AS FavoriteProductName
FROM [SmlSt].[CustomerAdditionalInformation] ai
LEFT JOIN [Sml].[Article] a ON TRY_CAST(ai.FavoriteProduct AS INT) = a.Id
WHERE @UidCode IS NOT NULL
  AND @UidSerie IS NOT NULL
  AND ai.UidCode  = @UidCode
  AND ai.UidSerie = @UidSerie
```

Probamos esta versión hoy contra datos reales de producción, las dos ramas por separado:

| Escenario | Lecturas lógicas | vs. consulta actual |
|---|---|---|
| `CardNumber` real (UidCode/UidSerie null) | 8 (4 + 4, la segunda rama corta por el `IS NOT NULL`) | 104.970 → 8 |
| `UidCode`+`UidSerie` real (CardNumber null) | 4 | 104.970 → 4 |

Ambos escenarios devolvieron la fila correcta. `LOWER()` se saca de las dos comparaciones — la collation del servidor ya es case-insensitive, así que el resultado no cambia. `TRY_CAST` sobre `FavoriteProduct` en el join con `Article` sigue como está por ahora; el fix estructural para eso (agregar `FavoriteProductId INT` con FK) queda aparte, no es necesario para esta mejora.

Detalle completo de las pruebas en `data/09_post_index_plancache_check.txt`, `data/10_post_index_execution_plan.txt`, `data/11_isolated_cardnumber_test.txt`, `data/12_optimized_query_union_test.txt` (`events/20260920_cpu-spikes/`, GITIN-2074).

Cualquier duda antes de aplicarlo, avisen.

Saludos,
Dante

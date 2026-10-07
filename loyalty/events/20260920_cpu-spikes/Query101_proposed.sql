-- Proposed rewrite of Query101-sql.xml (see Query101.sql for the current production version).
-- Origin: GITIN-1267 (2026-05-17, events/20260517_query101_webservicev2/), recurrence GITIN-2074.
-- OR -> UNION (two seek-able branches); LOWER() dropped (server collation is already case-insensitive).
-- Validated against real production data 2026-09-21: 104,970 -> 8 logical reads (CardNumber branch),
-- 104,970 -> 4 logical reads (UidCode+UidSerie branch). See ops.md "Resultado de las pruebas" and
-- data/12_optimized_query_union_test.txt. Not yet applied — Dev-owned, WSV2 app-side XML resource
-- file, not a DB object. TRY_CAST on FavoriteProduct in the Article join is left as-is here; the
-- structural fix for that (FavoriteProductId INT FK) is a separate, not-yet-scoped change.

DECLARE @CardNumber NVARCHAR(100) = @p0
DECLARE @UidCode    NVARCHAR(100) = @p1
DECLARE @UidSerie   NVARCHAR(100) = @p2

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

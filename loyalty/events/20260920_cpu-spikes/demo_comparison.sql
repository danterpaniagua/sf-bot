-- Reusable before/after demo for GITIN-2074 — run either block anytime against
-- SmartFran.Solution.SmartLoyalty to reproduce the comparison. Read-only.

-- 1. Current Query101 (OR/LOWER) — expect ~105k logical reads on CustomerAdditionalInformation.
SET STATISTICS IO ON;

DECLARE @CardNumber NVARCHAR(100);
SELECT TOP 1 @CardNumber = CardNumber FROM SmlSt.CustomerAdditionalInformation WHERE CardNumber IS NOT NULL;
DECLARE @UidCode NVARCHAR(100) = NULL;
DECLARE @UidSerie NVARCHAR(100) = NULL;

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

SET STATISTICS IO OFF;
GO

-- 2. Proposed fix (UNION, no LOWER) — expect single-digit logical reads.
SET STATISTICS IO ON;

DECLARE @CardNumber NVARCHAR(100);
SELECT TOP 1 @CardNumber = CardNumber FROM SmlSt.CustomerAdditionalInformation WHERE CardNumber IS NOT NULL;
DECLARE @UidCode NVARCHAR(100) = NULL;
DECLARE @UidSerie NVARCHAR(100) = NULL;

SELECT ai.FavoriteProduct, ai.AverageWeight, ai.LastBuyDate, a.Name AS FavoriteProductName
FROM [SmlSt].[CustomerAdditionalInformation] ai
LEFT JOIN [Sml].[Article] a ON TRY_CAST(ai.FavoriteProduct AS INT) = a.Id
WHERE ai.CardNumber = @CardNumber
UNION
SELECT ai.FavoriteProduct, ai.AverageWeight, ai.LastBuyDate, a.Name AS FavoriteProductName
FROM [SmlSt].[CustomerAdditionalInformation] ai
LEFT JOIN [Sml].[Article] a ON TRY_CAST(ai.FavoriteProduct AS INT) = a.Id
WHERE @UidCode IS NOT NULL AND @UidSerie IS NOT NULL
  AND ai.UidCode = @UidCode AND ai.UidSerie = @UidSerie

SET STATISTICS IO OFF;

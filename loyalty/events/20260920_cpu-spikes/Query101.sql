-- ContentResource: file:\D:\SmartLoyalty.WebServiceV2\bin\Domain\Query\Query101-sql.xml
-- Captured from PNSSRL_AuditSysprocesses.comando_ejecutado, window 2026-09-20 22:15-23:23 GMT
-- Identified as top CPU contributor in this window: 91,704ms total across 19 distinct SPIDs on SFCG-WSV2-01/02

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

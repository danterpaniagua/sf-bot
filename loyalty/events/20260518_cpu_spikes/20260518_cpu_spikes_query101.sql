-- Fuente: PNSSRL_AuditSysprocesses.comando_ejecutado
-- Capturado durante eventos CPU User Time >90% -- 2026-05-18
-- Origen: SFCG-WSV2-01 | Cuenta: SMARTIT\itservices
-- Archivo: D:\SmartLoyalty.WebServiceV2\bin\Domain\Query\Query101-sql.xml

(@p0 nvarchar(4000),@p1 nvarchar(3),@p2 nvarchar(8))

DECLARE @CardNumber NVARCHAR(100) = @p0
DECLARE @UidCode    NVARCHAR(100) = @p1
DECLARE @UidSerie   NVARCHAR(100) = @p2

SELECT
    ai.FavoriteProduct,
    ai.AverageWeight,
    ai.LastBuyDate,
    a.Name AS FavoriteProductName
FROM [SmlSt].[CustomerAdditionalInformation] ai
LEFT JOIN [Sml].[Article] a
    ON TRY_CAST(ai.FavoriteProduct AS INT) = a.Id
WHERE ai.CardNumber = @CardNumber
   OR (
        @UidCode  IS NOT NULL
    AND @UidSerie IS NOT NULL
    AND LOWER(ai.UidCode) = LOWER(@UidCode)
    AND ai.UidSerie = @UidSerie
      )

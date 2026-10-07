-- QUERY CORREGIDA (propuesta, UNION ALL sargable) — Etl.EtlOperationConfig Id=6
-- Misma ventana que query_current_last24h.sql, para comparacion directa:
-- LowerLimit = 2026-09-23 05:00:44 UTC, UpperLimit = 2026-09-24 05:02:31 UTC
-- (Etl.EtlOperationExecution Id=24836, corrida real del 2026-09-25)
--
-- Incluye la correccion del 2026-09-25: Rama A ahora exige @LowerBoundary IS NOT NULL
-- de forma incondicional, para no duplicar filas cuando no hay watermark (ver
-- investigation.md, "Correctness bug found and fixed"). No aplica en esta ventana
-- puntual (@LowerBoundary esta definido), pero se mantiene por fidelidad a la
-- version que realmente se propone llevar a produccion.

DECLARE @LowerBoundary NVARCHAR(27) = '2026-09-23 05:00:44.0000000';
DECLARE @UpperBoundary NVARCHAR(27) = '2026-09-24 05:02:31.0000000';

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT
    COUNT(*) AS RowCount_Total,
    COUNT(DISTINCT CustomerPointsLogId) AS RowCount_DistinctId,
    MIN(LogDate) AS MinLogDate,
    MAX(LogDate) AS MaxLogDate,
    SUM(CAST(Points AS BIGINT)) AS SumPoints,
    CHECKSUM_AGG(CHECKSUM(CustomerPointsLogId, EventTypeCode, CustomerId, LogDate, Points)) AS RowsetChecksum
FROM (
    SELECT cpl.Id as CustomerPointsLogId
          ,EventTypeCode
          ,CustomerId
          ,LogDate
          ,Points
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
    FROM Sml.CustomerPointsLog cpl (nolock)
    INNER JOIN Sml.Customer c (nolock) ON cpl.CustomerId = c.Id
    WHERE (@LowerBoundary IS NULL OR cpl.LogDate >= @LowerBoundary)
      AND cpl.LogDate < @UpperBoundary
      AND (@LowerBoundary IS NULL OR c.CreatedDate < @LowerBoundary)
) AS FixedQueryResult;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
-- Nota: la salida de STATISTICS IO/TIME aparece en la pestana "Messages" de SSMS
-- (o via sqlcmd en stderr/salida separada), no en el grid de resultados — pegar
-- ambas al copiar el resultado.

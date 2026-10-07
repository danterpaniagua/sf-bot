-- QUERY ACTUAL (produccion, OR no sargable) — Etl.EtlOperationConfig Id=6
-- Ventana: la real de la ultima corrida (2026-09-25), Etl.EtlOperationExecution Id=24836
-- LowerLimit = 2026-09-23 05:00:44 UTC, UpperLimit = 2026-09-24 05:02:31 UTC
-- Origen del texto: events/20260715_cpu_spikes/20260715_cpu_spikes_query001.sql (captura de produccion)
--
-- Nota de fidelidad: el parametro real capturado en produccion es NVARCHAR(27)
-- ("yyyy-MM-dd HH:mm:ss.fffffff", sin offset), no DATETIMEOFFSET — se respeta
-- el tipo exacto para no alterar el comportamiento de conversion implicita.
--
-- Correccion 2026-09-25: se agrego ORDER BY CustomerPointsLogId al final del
-- derived table (misma forma que query_fixed_last24h.sql) — la version anterior
-- de este archivo no la tenia, mientras que la version fixed si, haciendo la
-- comparacion de STATISTICS IO/TIME injusta (el costo real de ORDER BY, que la
-- paginacion real de produccion siempre paga via OFFSET/FETCH, solo aparecia
-- de un lado). Con esta correccion ambos archivos pagan el mismo costo de sort.
--
-- Correccion 2 (2026-09-25): "ORDER BY" solo, sin TOP/OFFSET/FOR XML, no es valido
-- en un derived table de un SELECT simple (Msg 1033) — a diferencia de un UNION ALL,
-- donde SQL Server si lo permite al final del combinado. Se agrego "OFFSET 0 ROWS"
-- para cumplir la sintaxis sin saltear filas ni cambiar el costo del sort.

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
    SELECT
        cpl.Id as CustomerPointsLogId,
        EventTypeCode,
        CustomerId,
        LogDate,
        Points
    FROM Sml.CustomerPointsLog cpl (nolock)
    INNER JOIN Sml.Customer c (nolock) ON cpl.CustomerId = c.Id
    WHERE
        (
            (@LowerBoundary IS NULL OR c.CreatedDate >= @LowerBoundary)
            AND c.CreatedDate < @UpperBoundary
            AND cpl.LogDate < @UpperBoundary
        )
        OR
        (
            (@LowerBoundary IS NULL OR cpl.LogDate >= @LowerBoundary)
            AND cpl.LogDate < @UpperBoundary
            AND (@LowerBoundary IS NULL OR c.CreatedDate < @LowerBoundary)
        )
    ORDER BY CustomerPointsLogId
    OFFSET 0 ROWS
) AS CurrentQueryResult;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
-- Nota: la salida de STATISTICS IO/TIME aparece en la pestana "Messages" de SSMS
-- (o via sqlcmd en stderr/salida separada), no en el grid de resultados — pegar
-- ambas al copiar el resultado.

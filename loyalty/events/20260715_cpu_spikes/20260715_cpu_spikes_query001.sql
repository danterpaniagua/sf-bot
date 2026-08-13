-- SPID 110 | sfsqlusr | SFCG-TO-01 (TaskOperatorService) | SmartFran.Solution.SmartLoyalty
-- Captured from PNSSRL_TempdbProc, window 2026-07-15 17:00-23:00 GMT (14:00-20:00 UTC-3)
-- Row-count probe preceding paginated CustomerPointsLog sync fetch.
-- cpu_time grew ~150,000 ms per 10s snapshot; logical_reads 10,442 -> 278,573 over ~3 min single execution.

SELECT TOP 1 COUNT(*) OVER () AS [RowCont]
FROM (
    SELECT
        cpl.Id as CustomerPointsLogId,
        EventTypeCode,
        CustomerId,
        LogDate,
        Points,
        SYSDATETIMEOFFSET() as _SyncDate
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
)

-- Follow-up paginated fetch (same SPID, same predicate), captured in PNSSRL_AuditSysprocesses:
--
-- (@LowerBoundary nvarchar(27),@UpperBoundary nvarchar(27))
-- SELECT cpl.Id as CustomerPointsLogId
--     ,EventTypeCode
--     ,CustomerId
--     ,LogDate
--     ,Points
--     ,SYSDATETIMEOFFSET() as _SyncDate
-- FROM Sml.CustomerPointsLog cpl (nolock)
-- INNER JOIN Sml.Customer c (nolock) ON cpl.CustomerId = c.Id
-- WHERE
--     (
--         (@LowerBoundary IS NULL OR c.CreatedDate >= @LowerBoundary)
--         AND c.CreatedDate < @UpperBoundary
--         AND cpl.LogDate < @UpperBoundary
--     )
--     OR
--     (
--         (@LowerBoundary IS NULL OR cpl.LogDate >= @LowerBoundary)
--         AND cpl.LogDate < @UpperBoundary
--         AND (@LowerBoundary IS NULL OR c.CreatedDate < @LowerBoundary)
--     )
-- ORDER BY cpl.Id
-- OFFSET 0 ROWS FETCH NEXT 100000 ROWS ONLY

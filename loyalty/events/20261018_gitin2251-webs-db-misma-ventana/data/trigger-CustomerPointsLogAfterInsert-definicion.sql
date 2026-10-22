USE [SmartFran.Solution.SmartLoyalty]
GO
/****** Object:  Trigger [Sml].[CustomerPointsLogAfterInsert]    Script Date: 10/19/2026 12:37:13 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER TRIGGER [Sml].[CustomerPointsLogAfterInsert]
ON [Sml].[CustomerPointsLog]
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    WITH PointsSummary AS (
        SELECT
            i.CustomerId,
            SUM(cpl.Points) AS TotalPoints
        FROM inserted i
        INNER JOIN sml.customerpointsLog cpl
            ON i.CustomerId = cpl.CustomerId
        GROUP BY i.CustomerId
    )

    MERGE SmlSt.CustomerPointsLog AS target
    USING (
        SELECT
            i.CustomerId,
            p.TotalPoints,
            MAX(i.LogDate) AS LastLogDate
        FROM inserted i
        INNER JOIN PointsSummary p ON i.CustomerId = p.CustomerId
        GROUP BY i.CustomerId, p.TotalPoints
    ) AS source
    ON target.CustomerId = source.CustomerId
    WHEN MATCHED THEN
        UPDATE SET
            target.Points = source.TotalPoints,
            target.LastLogDate = source.LastLogDate
    WHEN NOT MATCHED THEN
        INSERT (CustomerId, Points, LastLogDate)
        VALUES (source.CustomerId, source.TotalPoints, source.LastLogDate);
END;

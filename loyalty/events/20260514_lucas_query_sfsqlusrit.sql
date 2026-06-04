-- Captured from: PNSSRL.dbo.PNSSRL_AuditSysprocesses
-- Account:       sfsqlusrit
-- Host:          LUCAS-KIUVI
-- Database:      SmartFran.Solution.SmartLoyalty
-- Event date:    2026-05-14
-- CPU consumed:  168,783 ms cumulative by 17:36 GMT (14:36 UTC-3)
--
-- Purpose: Franchise consumption notification report.
--          Queries daily and weekly sales per branch office and returns
--          aggregated data (email list + alert counts) for PowerShell to
--          send notification emails to franchise staff.
--
-- Note: Script was marked "** PARA PRUEBAS **" and run manually from a
--       QA workstation directly against production.
--
-- ============================================================
-- Capture 1 — 2026-05-14 17:01 GMT (14:01 UTC-3)
-- @BaseDate hardcoded to 2026-05-12 (test mode active)
-- ============================================================

DECLARE @BaseDate DATETIMEOFFSET;
DECLARE @LimitDay SMALLINT;

-- ** PARA PRUEBAS **
  SET @BaseDate = CAST('20260512 12:00 -03:00' AS DATETIMEOFFSET);

-- Esto depende de la hora que se programe el job. Puede ser necesario restar un dia o no.

--SET @BaseDate = CAST(SWITCHOFFSET(DATEADD(dd, -1, SYSDATETIMEOFFSET()), '-03:00') AS DATE);

-- Para version sql 2008
SET @BaseDate =  CAST(
    CAST(DATEPART(year, @BaseDate) AS NVARCHAR)
    + RIGHT('0' + CAST(DATEPART(month, @BaseDate) AS NVARCHAR), 2)
    + RIGHT('0' + CAST(DATEPART(day, @BaseDate) AS NVARCHAR), 2)
    + ' 00:00:00 -03:00' AS DATETIMEOFFSET)


DECLARE @GETDATE AS NVARCHAR(MAX)
SET @GETDATE =
    (SELECT
            CASE DATEPART (WEEKDAY, @BaseDate)
                                    WHEN 1 THEN 'DOMINGO'
                                    WHEN 2 THEN 'LUNES'
                                    WHEN 3 THEN 'MARTES'
                                    WHEN 4 THEN 'MIERCOLES'
                                    WHEN 5 THEN 'JUEVES'
                                    WHEN 6 THEN 'VIERNES'
                                    WHEN 7 THEN 'SABADO'
                                END + ' '
            + CONVERT(CHAR(2), DATEPART (DAY, @BaseDate)) + ' DE '
            + CASE DATEPART (MONTH, @BaseDate)
                                        WHEN 1 THEN 'ENERO'
                                        WHEN 2 THEN 'FEBRERO'
                                        WHEN 3 THEN 'MARZO'
                                        WHEN 4 THEN 'ABRIL'
                                        WHEN 5 THEN 'MAYO'
                                        WHEN 6 THEN 'JUNIO'
                                        WHEN 7 THEN 'JULIO'
                                        WHEN 8 THEN 'AGOSTO'
                                        WHEN 9 THEN 'SEPTIEMBRE'
                                        WHEN 10 THEN 'OCTUBRE'
                                        WHEN 11 THEN 'NOVIEMBRE'
                                        WHEN 12 THEN 'DICIEMBRE'
                                    END
            + ' DE '
            + CONVERT(CHAR(4), DATEPART (YEAR, @BaseDate)))

SET @LimitDay = 3;


-- ****** traigo de la Membership los usuarios a quienes les enviaremos el mail de notificaciones ******
SELECT
        member.Email
        , member.FirstName
        , member.LastName
        , bo.Id AS BranchOfficeId
        , bo.Name AS BranchOfficeName
        , bo.Code AS BranchOfficeCode
        , fg.Id AS FranchiseGroupId
    INTO
        #StaffFranchiseQuery
    FROM
        [Sml].[FranchiseStaff] fs
        INNER JOIN [Mbr].[User] usr ON fs.UserId = usr.Id
        INNER JOIN [Mbr].[UserRole] urole ON usr.Id = urole.User_Id
        INNER JOIN [Mbr].[Member] member ON usr.MemberId = member.Id
        INNER JOIN [Mbr].[Role] role ON role.Id = urole.Role_Id
        INNER JOIN [Sml].[BranchOffice] bo ON fs.FranchiseGroupId = bo.FranchiseGroupId
        INNER JOIN [Sml].[FranchiseGroup] fg ON fg.Id = bo.FranchiseGroupId
    WHERE
        (role.Code = N'SmartFran.Solution.SmartLoyalty.FrequentlyConsumptionNotificationAlert')

-- *******************************************************************************************************


-- ######## NOTIFICACIONES DE CONSUMOS EN EL DIA DE LA FECHA ############
-- ****************** consumos de socios *************************
    SELECT
            Sale.BranchOfficeId
            , Person.UidCode
            , Person.UidSerie
            , COUNT(*) AS CountSale
        INTO
            #ConsumptionsByDay
        FROM
            [Sml].Sale
            INNER JOIN [Sml].Person ON [Sml].Sale.CustomerId = [Sml].Person.Id
        WHERE
            ([Sml].Sale.SaleDate >=  @BaseDate) AND ([Sml].Sale.SaleDate < DATEADD(dd, 1, @BaseDate))
            AND ([Sml].Sale.InvalidatedPointsLogId IS NULL)
            AND ([Sml].Sale.BranchOfficeId IN (SELECT BranchOfficeId FROM #StaffFranchiseQuery))
        GROUP BY
            [Sml].Sale.BranchOfficeId,
            [Sml].Person.UidCode,
            [Sml].Person.UidSerie
        HAVING COUNT(*) >= @LimitDay
-- ******************************************************************
-- ****************** consumos de socios pendientes *****************
    UNION SELECT
            Sale.BranchOfficeId
            , CardPendingAffiliate.CustomerUidCode
            , CardPendingAffiliate.CustomerUidSerie
            , COUNT(*) AS CountSale
        FROM
            [Sml].Sale
            INNER JOIN [Sml].SalePendingAffiliate ON [Sml].Sale.Id = [Sml].SalePendingAffiliate.Id
            INNER JOIN [Sml].CardPendingAffiliate ON [Sml].SalePendingAffiliate.CardPendingAffiliateId = [Sml].CardPendingAffiliate.Id
        WHERE
            ([Sml].Sale.SaleDate >=  @BaseDate) AND ([Sml].Sale.SaleDate < DATEADD(dd, 1, @BaseDate))
            AND ([Sml].Sale.InvalidatedPointsLogId IS NULL)
            AND ([Sml].Sale.CustomerId IS NULL)
            AND ([Sml].Sale.BranchOfficeId IN (SELECT BranchOfficeId FROM #StaffFranchiseQuery))
        GROUP BY
            [Sml].Sale.BranchOfficeId,
            CustomerUidCode,
            CustomerUidSerie
        HAVING COUNT(*) >= @LimitDay
-- *******************************************************************

-- ######## NOTIFICACIONES DE CONSUMOS EN LOS ULTIMOS 7 DIAS ############
-- ********************** consumos de socios *******************************
    SELECT
        Sale.BranchOfficeId
        , Person.UidCode
        , Person.UidSerie
        , CAST(SWITCHOFFSET(Sale.SaleDate, '-03:00') AS DATE) AS [WeekDay]
        , COUNT(*) AS CountSale
        INTO
            #ConsumptionsByWeek
        FROM
            [Sml].Sale
            INNER JOIN [Sml].Person ON [Sml].Sale.CustomerId = [Sml].Person.Id
        WHERE
            ([Sml].Sale.SaleDate >=  DATEADD(dd, -6, @BaseDate)) AND ([Sml].Sale.SaleDate < DATEADD(dd, 1, @BaseDate))
            AND ([Sml].Sale.InvalidatedPointsLogId IS NULL)
            AND ([Sml].Sale.BranchOfficeId IN (SELECT BranchOfficeId FROM #ConsumptionsByDay))
        GROUP BY
            [Sml].Sale.BranchOfficeId,
            [Sml].Person.UidCode,
            [Sml].Person.UidSerie,
            CAST(SWITCHOFFSET([Sml].Sale.SaleDate, '-03:00') AS DATE)
        HAVING COUNT(*) >= @LimitDay
-- **************************************************************************
-- ********************** consumos de socios pendientes *********************
    UNION SELECT
            [Sml].Sale.BranchOfficeId
            , [Sml].CardPendingAffiliate.CustomerUidCode
            , [Sml].CardPendingAffiliate.CustomerUidSerie
            , CAST(SWITCHOFFSET([Sml].Sale.SaleDate, '-03:00') AS DATE) AS [WeekDay]
            , COUNT(*) AS CountSale
        FROM
            [Sml].Sale
            INNER JOIN [Sml].SalePendingAffiliate ON [Sml].Sale.Id = [Sml].SalePendingAffiliate.Id
            INNER JOIN [Sml].CardPendingAffiliate ON [Sml].SalePendingAffiliate.CardPendingAffiliateId = [Sml].CardPendingAffiliate.Id
        WHERE
            ([Sml].Sale.SaleDate >=  DATEADD(dd, -6, @BaseDate)) AND ([Sml].Sale.SaleDate < DATEADD(dd, 1, @BaseDate))
            AND ([Sml].Sale.InvalidatedPointsLogId IS NULL)
            AND ([Sml].Sale.CustomerId IS NULL)
            AND ([Sml].Sale.BranchOfficeId IN (SELECT BranchOfficeId FROM #ConsumptionsByDay))
        GROUP BY
            [Sml].Sale.BranchOfficeId,
            CustomerUidCode,
            CustomerUidSerie,
            CAST(SWITCHOFFSET([Sml].Sale.SaleDate, '-03:00') AS DATE)
        HAVING COUNT(*) >= @LimitDay
-- **************************************************************************

-- Devolvemos la informacion agrupada para que sea procesada por PowerShell
SELECT
    f.FranchiseGroupId,
    (
        SELECT STUFF((
            SELECT DISTINCT ',' + sf.Email
            FROM #StaffFranchiseQuery sf
            WHERE sf.FranchiseGroupId = f.FranchiseGroupId
            AND sf.Email IS NOT NULL AND LTRIM(RTRIM(sf.Email)) <> ''
            FOR XML PATH('')
        ), 1, 1, '')
    ) AS EmailList,
    cb.BranchOfficeId,
    cb.BranchOfficeName,
    cb.BranchOfficeCode,
    cb.AlertDay,
    ISNULL((
        SELECT COUNT(*)
        FROM #ConsumptionsByWeek cw
        WHERE cw.BranchOfficeId = cb.BranchOfficeId
    ), 0) AS AlertWeek,
    @GETDATE AS ReportDate
FROM
    (SELECT DISTINCT FranchiseGroupId FROM #StaffFranchiseQuery WHERE BranchOfficeId IN (SELECT BranchOfficeId FROM #ConsumptionsByDay)) f
    INNER JOIN (
        SELECT
            a1.BranchOfficeId,
            sf.FranchiseGroupId,
            sf.BranchOfficeName,
            sf.BranchOfficeCode,
            COUNT(*) AS AlertDay
        FROM
            #ConsumptionsByDay a1
            LEFT JOIN (SELECT DISTINCT BranchOfficeId, FranchiseGroupId, BranchOfficeName, BranchOfficeCode FROM #StaffFranchiseQuery) sf ON a1.BranchOfficeId = sf.BranchOfficeId
        GROUP BY
            a1.BranchOfficeId,
            sf.FranchiseGroupId,
            sf.BranchOfficeName,
            sf.BranchOfficeCode
    ) cb ON cb.FranchiseGroupId = f.FranchiseGroupId
ORDER BY
    f.FranchiseGroupId, cb.BranchOfficeName

-- ============================================================
-- Capture 2 — 2026-05-14 17:36 GMT (14:36 UTC-3)
-- @BaseDate switched to dynamic (yesterday), test line commented out
-- CPU cumulative at this point: 168,783 ms
-- ============================================================

DECLARE @BaseDate DATETIMEOFFSET;
DECLARE @LimitDay SMALLINT;

-- ** PARA PRUEBAS **
 -- SET @BaseDate = CAST('20260513 12:00 -03:00' AS DATETIMEOFFSET);

-- Esto depende de la hora que se programe el job. Puede ser necesario restar un dia o no.

SET @BaseDate = CAST(SWITCHOFFSET(DATEADD(dd, -1, SYSDATETIMEOFFSET()), '-03:00') AS DATE);

-- Para version sql 2008
SET @BaseDate =  CAST(
    CAST(DATEPART(year, @BaseDate) AS NVARCHAR)
    + RIGHT('0' + CAST(DATEPART(month, @BaseDate) AS NVARCHAR), 2)
    + RIGHT('0' + CAST(DATEPART(day, @BaseDate) AS NVARCHAR), 2)
    + ' 00:00:00 -03:00' AS DATETIMEOFFSET)


DECLARE @GETDATE AS NVARCHAR(MAX)
SET @GETDATE =
    (SELECT
            CASE DATEPART (WEEKDAY, @BaseDate)
                                    WHEN 1 THEN 'DOMINGO'
                                    WHEN 2 THEN 'LUNES'
                                    WHEN 3 THEN 'MARTES'
                                    WHEN 4 THEN 'MIERCOLES'
                                    WHEN 5 THEN 'JUEVES'
                                    WHEN 6 THEN 'VIERNES'
                                    WHEN 7 THEN 'SABADO'
                                END + ' '
            + CONVERT(CHAR(2), DATEPART (DAY, @BaseDate)) + ' DE '
            + CASE DATEPART (MONTH, @BaseDate)
                                        WHEN 1 THEN 'ENERO'
                                        WHEN 2 THEN 'FEBRERO'
                                        WHEN 3 THEN 'MARZO'
                                        WHEN 4 THEN 'ABRIL'
                                        WHEN 5 THEN 'MAYO'
                                        WHEN 6 THEN 'JUNIO'
                                        WHEN 7 THEN 'JULIO'
                                        WHEN 8 THEN 'AGOSTO'
                                        WHEN 9 THEN 'SEPTIEMBRE'
                                        WHEN 10 THEN 'OCTUBRE'
                                        WHEN 11 THEN 'NOVIEMBRE'
                                        WHEN 12 THEN 'DICIEMBRE'
                                    END
            + ' DE '
            + CONVERT(CHAR(4), DATEPART (YEAR, @BaseDate)))

SET @LimitDay = 3;


-- ****** traigo de la Membership los usuarios a quienes les enviaremos el mail de notificaciones ******
SELECT
        member.Email
        , member.FirstName
        , member.LastName
        , bo.Id AS BranchOfficeId
        , bo.Name AS BranchOfficeName
        , bo.Code AS BranchOfficeCode
        , fg.Id AS FranchiseGroupId
    INTO
        #StaffFranchiseQuery
    FROM
        [Sml].[FranchiseStaff] fs
        INNER JOIN [Mbr].[User] usr ON fs.UserId = usr.Id
        INNER JOIN [Mbr].[UserRole] urole ON usr.Id = urole.User_Id
        INNER JOIN [Mbr].[Member] member ON usr.MemberId = member.Id
        INNER JOIN [Mbr].[Role] role ON role.Id = urole.Role_Id
        INNER JOIN [Sml].[BranchOffice] bo ON fs.FranchiseGroupId = bo.FranchiseGroupId
        INNER JOIN [Sml].[FranchiseGroup] fg ON fg.Id = bo.FranchiseGroupId
    WHERE
        (role.Code = N'SmartFran.Solution.SmartLoyalty.FrequentlyConsumptionNotificationAlert')

-- *******************************************************************************************************


-- ######## NOTIFICACIONES DE CONSUMOS EN EL DIA DE LA FECHA ############
-- ****************** consumos de socios *************************
    SELECT
            Sale.BranchOfficeId
            , Person.UidCode
            , Person.UidSerie
            , COUNT(*) AS CountSale
        INTO
            #ConsumptionsByDay
        FROM
            [Sml].Sale
            INNER JOIN [Sml].Person ON [Sml].Sale.CustomerId = [Sml].Person.Id
        WHERE
            ([Sml].Sale.SaleDate >=  @BaseDate) AND ([Sml].Sale.SaleDate < DATEADD(dd, 1, @BaseDate))
            AND ([Sml].Sale.InvalidatedPointsLogId IS NULL)
            AND ([Sml].Sale.BranchOfficeId IN (SELECT BranchOfficeId FROM #StaffFranchiseQuery))
        GROUP BY
            [Sml].Sale.BranchOfficeId,
            [Sml].Person.UidCode,
            [Sml].Person.UidSerie
        HAVING COUNT(*) >= @LimitDay
-- ******************************************************************
-- ****************** consumos de socios pendientes *****************
    UNION SELECT
            Sale.BranchOfficeId
            , CardPendingAffiliate.CustomerUidCode
            , CardPendingAffiliate.CustomerUidSerie
            , COUNT(*) AS CountSale
        FROM
            [Sml].Sale
            INNER JOIN [Sml].SalePendingAffiliate ON [Sml].Sale.Id = [Sml].SalePendingAffiliate.Id
            INNER JOIN [Sml].CardPendingAffiliate ON [Sml].SalePendingAffiliate.CardPendingAffiliateId = [Sml].CardPendingAffiliate.Id
        WHERE
            ([Sml].Sale.SaleDate >=  @BaseDate) AND ([Sml].Sale.SaleDate < DATEADD(dd, 1, @BaseDate))
            AND ([Sml].Sale.InvalidatedPointsLogId IS NULL)
            AND ([Sml].Sale.CustomerId IS NULL)
            AND ([Sml].Sale.BranchOfficeId IN (SELECT BranchOfficeId FROM #StaffFranchiseQuery))
        GROUP BY
            [Sml].Sale.BranchOfficeId,
            CustomerUidCode,
            CustomerUidSerie
        HAVING COUNT(*) >= @LimitDay
-- *******************************************************************

-- ######## NOTIFICACIONES DE CONSUMOS EN LOS ULTIMOS 7 DIAS ############
-- ********************** consumos de socios *******************************
    SELECT
        Sale.BranchOfficeId
        , Person.UidCode
        , Person.UidSerie
        , CAST(SWITCHOFFSET(Sale.SaleDate, '-03:00') AS DATE) AS [WeekDay]
        , COUNT(*) AS CountSale
        INTO
            #ConsumptionsByWeek
        FROM
            [Sml].Sale
            INNER JOIN [Sml].Person ON [Sml].Sale.CustomerId = [Sml].Person.Id
        WHERE
            ([Sml].Sale.SaleDate >=  DATEADD(dd, -6, @BaseDate)) AND ([Sml].Sale.SaleDate < DATEADD(dd, 1, @BaseDate))
            AND ([Sml].Sale.InvalidatedPointsLogId IS NULL)
            AND ([Sml].Sale.BranchOfficeId IN (SELECT BranchOfficeId FROM #ConsumptionsByDay))
        GROUP BY
            [Sml].Sale.BranchOfficeId,
            [Sml].Person.UidCode,
            [Sml].Person.UidSerie,
            CAST(SWITCHOFFSET([Sml].Sale.SaleDate, '-03:00') AS DATE)
        HAVING COUNT(*) >= @LimitDay
-- **************************************************************************
-- ********************** consumos de socios pendientes *********************
    UNION SELECT
            [Sml].Sale.BranchOfficeId
            , [Sml].CardPendingAffiliate.CustomerUidCode
            , [Sml].CardPendingAffiliate.CustomerUidSerie
            , CAST(SWITCHOFFSET([Sml].Sale.SaleDate, '-03:00') AS DATE) AS [WeekDay]
            , COUNT(*) AS CountSale
        FROM
            [Sml].Sale
            INNER JOIN [Sml].SalePendingAffiliate ON [Sml].Sale.Id = [Sml].SalePendingAffiliate.Id
            INNER JOIN [Sml].CardPendingAffiliate ON [Sml].SalePendingAffiliate.CardPendingAffiliateId = [Sml].CardPendingAffiliate.Id
        WHERE
            ([Sml].Sale.SaleDate >=  DATEADD(dd, -6, @BaseDate)) AND ([Sml].Sale.SaleDate < DATEADD(dd, 1, @BaseDate))
            AND ([Sml].Sale.InvalidatedPointsLogId IS NULL)
            AND ([Sml].Sale.CustomerId IS NULL)
            AND ([Sml].Sale.BranchOfficeId IN (SELECT BranchOfficeId FROM #ConsumptionsByDay))
        GROUP BY
            [Sml].Sale.BranchOfficeId,
            CustomerUidCode,
            CustomerUidSerie,
            CAST(SWITCHOFFSET([Sml].Sale.SaleDate, '-03:00') AS DATE)
        HAVING COUNT(*) >= @LimitDay
-- **************************************************************************

-- Devolvemos la informacion agrupada para que sea procesada por PowerShell
SELECT
    f.FranchiseGroupId,
    (
        SELECT STUFF((
            SELECT DISTINCT ',' + sf.Email
            FROM #StaffFranchiseQuery sf
            WHERE sf.FranchiseGroupId = f.FranchiseGroupId
            AND sf.Email IS NOT NULL AND LTRIM(RTRIM(sf.Email)) <> ''
            FOR XML PATH('')
        ), 1, 1, '')
    ) AS EmailList,
    cb.BranchOfficeId,
    cb.BranchOfficeName,
    cb.BranchOfficeCode,
    cb.AlertDay,
    ISNULL((
        SELECT COUNT(*)
        FROM #ConsumptionsByWeek cw
        WHERE cw.BranchOfficeId = cb.BranchOfficeId
    ), 0) AS AlertWeek,
    @GETDATE AS ReportDate
FROM
    (SELECT DISTINCT FranchiseGroupId FROM #StaffFranchiseQuery WHERE BranchOfficeId IN (SELECT BranchOfficeId FROM #ConsumptionsByDay)) f
    INNER JOIN (
        SELECT
            a1.BranchOfficeId,
            sf.FranchiseGroupId,
            sf.BranchOfficeName,
            sf.BranchOfficeCode,
            COUNT(*) AS AlertDay
        FROM
            #ConsumptionsByDay a1
            LEFT JOIN (SELECT DISTINCT BranchOfficeId, FranchiseGroupId, BranchOfficeName, BranchOfficeCode FROM #StaffFranchiseQuery) sf ON a1.BranchOfficeId = sf.BranchOfficeId
        GROUP BY
            a1.BranchOfficeId,
            sf.FranchiseGroupId,
            sf.BranchOfficeName,
            sf.BranchOfficeCode
    ) cb ON cb.FranchiseGroupId = f.FranchiseGroupId
ORDER BY
    f.FranchiseGroupId, cb.BranchOfficeName

-- ============================================================
-- Red de Fraude "Batman" -- Investigación 2026-06-12
-- Base: SmartFran.Solution.SmartLoyalty
-- Todas las consultas en orden de ejecución
-- ============================================================

-- ============================================================
-- Q_FANIN: Fan-in sweep -- cuentas con múltiples emisores
-- ============================================================
-- (ejecutado en sesión previa -- 30 hubs identificados)

-- ============================================================
-- Q_BATMAN_ALIAS: Búsqueda de aliases por nombre y email
-- ============================================================
SELECT
    p.FirstName + ' ' + p.LastName AS Nombre,
    p.UidSerie                      AS DNI,
    p.Email,
    smlst.Points                    AS Saldo_Actual
FROM [SmartFran.Solution.SmartLoyalty].sml.Person p
LEFT JOIN [SmartFran.Solution.SmartLoyalty].smlst.CustomerPointsLog smlst ON smlst.CustomerId = p.Id
WHERE
    p.FirstName + ' ' + p.LastName LIKE '%batman%'
    OR p.FirstName + ' ' + p.LastName LIKE '%bat man%'
    OR p.FirstName + ' ' + p.LastName LIKE '%murcielago%'
    OR p.FirstName + ' ' + p.LastName LIKE '%murciélago%'
    OR p.FirstName + ' ' + p.LastName LIKE '%bruce wayne%'
    OR p.FirstName + ' ' + p.LastName LIKE '%caballero%oscuro%'
    OR p.FirstName + ' ' + p.LastName LIKE '%señor%noche%'
    OR p.FirstName + ' ' + p.LastName LIKE '%dark knight%'
    OR p.Email LIKE '%locosdeperros%'
    OR TRY_CAST(p.UidSerie AS BIGINT) BETWEEN 43541185 AND 43541220
ORDER BY p.UidSerie;

-- ============================================================
-- Q_BAT1: Historial de envíos de El Batman y Bat Man
-- ============================================================
SELECT
    ps.FirstName + ' ' + ps.LastName                            AS Emisor,
    ps.UidSerie                                                 AS DNI_Emisor,
    ps.Email                                                    AS Email_Emisor,
    FORMAT(DATEADD(HOUR,-3,pt.[Date]),'yyyy-MM-dd HH:mm:ss')   AS Fecha_ARG,
    ABS(cpl_s.Points)                                           AS Puntos,
    pt.SourceChannel,
    pr.FirstName + ' ' + pr.LastName                           AS Receptor,
    pr.UidSerie                                                 AS DNI_Receptor
FROM [SmartFran.Solution.SmartLoyalty].sml.PointsTransference pt
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog cpl_s ON cpl_s.Id = pt.IdCustomerPointsLogSender
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog cpl_r ON cpl_r.Id = pt.IdCustomerPointsLogReceiver
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person ps ON ps.Id = cpl_s.CustomerId
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person pr ON pr.Id = cpl_r.CustomerId
WHERE ps.UidSerie IN ('43541208','43541200')
ORDER BY pt.[Date];

-- ============================================================
-- Q_BAT2: Historial de Huanca (38973061) -- receives + canjes
-- ============================================================
SELECT
    FORMAT(DATEADD(HOUR,-3,cpl.LogDate),'yyyy-MM-dd HH:mm:ss') AS Fecha_ARG,
    cpl.EventTypeCode,
    cpl.Points,
    bo.Code AS Sucursal,
    fg.Name AS Franquicia
FROM [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog cpl
LEFT JOIN [SmartFran.Solution.SmartLoyalty].sml.Sale s   ON s.Id = cpl.SaleId
LEFT JOIN [SmartFran.Solution.SmartLoyalty].sml.BranchOffice bo ON bo.Id = s.BranchOfficeId
LEFT JOIN [SmartFran.Solution.SmartLoyalty].sml.FranchiseGroup fg ON fg.Id = bo.FranchiseGroupId
WHERE cpl.CustomerId = (
    SELECT Id FROM [SmartFran.Solution.SmartLoyalty].sml.Person
    WHERE UidSerie = '38973061'
)
  AND cpl.EventTypeCode IN ('PointsByTransferReceived','DiscountPointsByExchange')
ORDER BY cpl.LogDate;

-- ============================================================
-- Q_BAT3: Saldo actual de cuentas clave
-- ============================================================
SELECT
    p.FirstName + ' ' + p.LastName AS Nombre,
    p.UidSerie                      AS DNI,
    p.Email,
    smlst.Points                    AS Saldo_Actual
FROM [SmartFran.Solution.SmartLoyalty].sml.Person p
JOIN [SmartFran.Solution.SmartLoyalty].smlst.CustomerPointsLog smlst ON smlst.CustomerId = p.Id
WHERE p.UidSerie IN ('43541208','43541200','38973061');

-- ============================================================
-- Q_BAT_INBOUND: Historial entrante de El Batman (43541208)
-- ============================================================
SELECT
    FORMAT(DATEADD(HOUR,-3,cpl.LogDate),'yyyy-MM-dd HH:mm:ss') AS Fecha_ARG,
    cpl.EventTypeCode,
    cpl.Points,
    cpl.Note
FROM [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog cpl
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person p ON p.Id = cpl.CustomerId
WHERE p.UidSerie = '43541208'
  AND cpl.EventTypeCode NOT IN ('PointsByTransferSent','NewCustomer')
ORDER BY cpl.LogDate;

-- ============================================================
-- Q_FEEDERS_MAY25: Identidad feeders Mayo 25 (19K y 24K a Batman)
-- ============================================================
SELECT
    ps.FirstName + ' ' + ps.LastName                          AS Emisor,
    ps.UidSerie                                               AS DNI_Emisor,
    ps.Email,
    FORMAT(DATEADD(HOUR,-3,pt.[Date]),'yyyy-MM-dd HH:mm:ss') AS Fecha_ARG,
    ABS(cpl_s.Points)                                         AS Puntos,
    pt.SourceChannel
FROM [SmartFran.Solution.SmartLoyalty].sml.PointsTransference pt
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog cpl_s ON cpl_s.Id = pt.IdCustomerPointsLogSender
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog cpl_r ON cpl_r.Id = pt.IdCustomerPointsLogReceiver
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person ps ON ps.Id = cpl_s.CustomerId
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person pr ON pr.Id = cpl_r.CustomerId
WHERE pr.UidSerie = '43541208'
  AND pt.[Date] >= '2026-05-25T00:00:00+00:00'
  AND pt.[Date] <  '2026-05-26T06:00:00+00:00';

-- ============================================================
-- Q_FEEDERS_HISTORIAL: Historial completo de feeders Ciraco/Diaz
-- ============================================================
SELECT
    ps.FirstName + ' ' + ps.LastName                          AS Emisor,
    ps.UidSerie                                               AS DNI_Emisor,
    FORMAT(DATEADD(HOUR,-3,pt.[Date]),'yyyy-MM-dd HH:mm:ss') AS Fecha_ARG,
    ABS(cpl_s.Points)                                         AS Puntos,
    pt.SourceChannel,
    pr.FirstName + ' ' + pr.LastName                         AS Receptor,
    pr.UidSerie                                               AS DNI_Receptor,
    pr.Email                                                  AS Email_Receptor
FROM [SmartFran.Solution.SmartLoyalty].sml.PointsTransference pt
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog cpl_s ON cpl_s.Id = pt.IdCustomerPointsLogSender
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog cpl_r ON cpl_r.Id = pt.IdCustomerPointsLogReceiver
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person ps ON ps.Id = cpl_s.CustomerId
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person pr ON pr.Id = cpl_r.CustomerId
WHERE ps.UidSerie IN ('23223694','36449166')
ORDER BY pt.[Date];

-- ============================================================
-- Q_ELBARTO_HISTORIAL: Historial completo Elbarto Malo (43541209)
-- ============================================================
SELECT
    FORMAT(DATEADD(HOUR,-3,cpl.LogDate),'yyyy-MM-dd HH:mm:ss') AS Fecha_ARG,
    cpl.EventTypeCode,
    cpl.Points,
    cpl.Note
FROM [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog cpl
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person p ON p.Id = cpl.CustomerId
WHERE p.UidSerie = '43541209'
ORDER BY cpl.LogDate;

-- ============================================================
-- Q_ELBARTO_SALIENTES: Destinos de Elbarto Malo
-- ============================================================
SELECT
    FORMAT(DATEADD(HOUR,-3,pt.[Date]),'yyyy-MM-dd HH:mm:ss') AS Fecha_ARG,
    ABS(cpl_s.Points)                                         AS Puntos,
    pt.SourceChannel,
    pr.FirstName + ' ' + pr.LastName                         AS Receptor,
    pr.UidSerie                                               AS DNI_Receptor,
    pr.Email                                                  AS Email_Receptor
FROM [SmartFran.Solution.SmartLoyalty].sml.PointsTransference pt
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog cpl_s ON cpl_s.Id = pt.IdCustomerPointsLogSender
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog cpl_r ON cpl_r.Id = pt.IdCustomerPointsLogReceiver
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person ps ON ps.Id = cpl_s.CustomerId
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person pr ON pr.Id = cpl_r.CustomerId
WHERE ps.UidSerie = '43541209'
ORDER BY pt.[Date];

-- ============================================================
-- Q_EUSTACIO_HISTORIAL: Historial completo Eustacio Castro (92623449)
-- ============================================================
SELECT
    FORMAT(DATEADD(HOUR,-3,cpl.LogDate),'yyyy-MM-dd HH:mm:ss') AS Fecha_ARG,
    cpl.EventTypeCode,
    cpl.Points,
    cpl.Note
FROM [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog cpl
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person p ON p.Id = cpl.CustomerId
WHERE p.UidSerie = '92623449'
ORDER BY cpl.LogDate;

-- ============================================================
-- Q_EUSTACIO_REVERSAL: Operador de reversión dic. 2024
-- ============================================================
SELECT
    map.RegisterByUser,
    map.AssignmentConcept,
    map.Points,
    FORMAT(DATEADD(HOUR,-3,map.AssignDate),'yyyy-MM-dd HH:mm:ss') AS Fecha_ARG,
    map.Status,
    map.ErrorLog
FROM [SmartFran.Solution.SmartLoyalty].sml.ManualAssignPoints map
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog cpl ON cpl.ManualAssignPointsId = map.Id
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person p ON p.Id = cpl.CustomerId
WHERE p.UidSerie = '92623449'
  AND map.Points < 0;

-- ============================================================
-- Q_EUSTACIO_SALIENTES: Destinos de Eustacio Castro
-- ============================================================
SELECT
    FORMAT(DATEADD(HOUR,-3,pt.[Date]),'yyyy-MM-dd HH:mm:ss') AS Fecha_ARG,
    ABS(cpl_s.Points)                                         AS Puntos,
    pr.FirstName + ' ' + pr.LastName                         AS Receptor,
    pr.UidSerie                                               AS DNI_Receptor,
    pr.Email
FROM [SmartFran.Solution.SmartLoyalty].sml.PointsTransference pt
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog cpl_s ON cpl_s.Id = pt.IdCustomerPointsLogSender
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog cpl_r ON cpl_r.Id = pt.IdCustomerPointsLogReceiver
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person ps ON ps.Id = cpl_s.CustomerId
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person pr ON pr.Id = cpl_r.CustomerId
WHERE ps.UidSerie = '92623449'
ORDER BY pt.[Date];

-- ============================================================
-- Q_RECEPTORES: Historial completo de receptoras/cashout
-- (ejecutar por separado para cada DNI)
-- ============================================================
SELECT
    FORMAT(DATEADD(HOUR,-3,cpl.LogDate),'yyyy-MM-dd HH:mm:ss') AS Fecha_ARG,
    cpl.EventTypeCode,
    cpl.Points,
    cpl.Note
FROM [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog cpl
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person p ON p.Id = cpl.CustomerId
WHERE p.UidSerie IN (
    '48016024',  -- Angel Pereyra
    '47813765',  -- Valentina Choque
    '46403467',  -- Agustina Guzman
    '45978514'   -- Agustina Sandoval Sobarzo
)
ORDER BY p.UidSerie, cpl.LogDate;

-- ============================================================
-- Q_GUZMAN_SALIENTES: Destinos de Agustina Guzman
-- ============================================================
SELECT
    FORMAT(DATEADD(HOUR,-3,pt.[Date]),'yyyy-MM-dd HH:mm:ss') AS Fecha_ARG,
    ABS(cpl_s.Points)                                         AS Puntos,
    pt.SourceChannel,
    pr.FirstName + ' ' + pr.LastName                         AS Receptor,
    pr.UidSerie                                               AS DNI_Receptor,
    pr.Email
FROM [SmartFran.Solution.SmartLoyalty].sml.PointsTransference pt
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog cpl_s ON cpl_s.Id = pt.IdCustomerPointsLogSender
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog cpl_r ON cpl_r.Id = pt.IdCustomerPointsLogReceiver
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person ps ON ps.Id = cpl_s.CustomerId
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person pr ON pr.Id = cpl_r.CustomerId
WHERE ps.UidSerie = '46403467'
ORDER BY pt.[Date];

-- ============================================================
-- Q_LIMITE_CONFIG: Verificación de límites vigentes
-- ============================================================
SELECT AttributeCode, Value
FROM [SmartFran.Solution.SmartLoyalty].Sml.LocationAttributeValue
WHERE LocationId = 1
ORDER BY AttributeCode;

-- ============================================================
-- Q_HOMER_SPO: Pendiente -- historial Homer Spo (43541207)
-- ============================================================
SELECT
    FORMAT(DATEADD(HOUR,-3,cpl.LogDate),'yyyy-MM-dd HH:mm:ss') AS Fecha_ARG,
    cpl.EventTypeCode,
    cpl.Points,
    cpl.Note
FROM [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog cpl
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person p ON p.Id = cpl.CustomerId
WHERE p.UidSerie = '43541207'
ORDER BY cpl.LogDate;

-- ============================================================
-- Disputa de puntos — Socia 38778247 (Fatima Marina Gonzalez)
-- Archivo de referencia de scripts ejecutados
-- ============================================================

-- Q1: Resolución de CustomerId + identidad + validación de email + estado de cuenta
SELECT
    p.Id                                                          AS CustomerId,
    TRY_CAST(p.UidSerie AS BIGINT)                                AS DNI,
    p.FirstName + ' ' + p.LastName                                AS Nombre,
    p.Email,
    CASE
        WHEN p.Email LIKE '%yopmail.com'
          OR p.Email LIKE '%hilostar.com'
          OR p.Email LIKE '%bultoc.com'
          OR p.Email LIKE '%datehype.com'
          OR p.Email LIKE '%mailinator.com'
          OR p.Email LIKE '%guerrillamail.com'
          OR p.Email LIKE '%tempmail.com'
        THEN 'DOMINIO_DESECHABLE'
        WHEN cm.CustomerId IS NULL THEN 'NO_EN_MAILING'
        ELSE 'OK'
    END                                                            AS Email_Flag,
    CASE WHEN TRY_CAST(p.UidSerie AS BIGINT) IS NULL
         THEN 'Desactivada' ELSE 'Activa' END                     AS EstadoCuenta,
    c.RegistrationChannel,
    c.CreatedDate,
    c.RegisterById                                                AS SucursalRegistroId,
    bo.Code                                                        AS SucursalCodigo,
    bo.Name                                                        AS SucursalNombre
FROM [SmartFran.Solution.SmartLoyalty].sml.Person p
LEFT JOIN [SmartFran.Solution.SmartLoyalty].sml.Customer c ON c.Id = p.Id
LEFT JOIN [SmartFran.Solution.SmartLoyalty].sml.BranchOffice bo ON bo.Id = c.RegisterById
LEFT JOIN [SmartFran.Solution.SmartLoyalty].SmlSt.CustomerMailing cm ON cm.CustomerId = p.Id
WHERE TRY_CAST(p.UidSerie AS BIGINT) = 38778247;

-- Q2: Saldo actual
SELECT CustomerId, Points AS SaldoActual, LastLogDate
FROM [SmartFran.Solution.SmartLoyalty].smlst.CustomerPointsLog
WHERE CustomerId = 'CA9E37DC-E985-CAB0-1A3B-08D30721E94F';

-- Q3: Historial completo de eventos de puntos, 2026-06-01 / 2026-07-05
SELECT
    l.Id,
    l.LogDate,
    DATEADD(HOUR, -3, l.LogDate)          AS LogDate_UTC3,
    l.EventTypeCode,
    l.Points,
    l.Note,
    l.SaleId,
    l.PromotionId,
    l.ArticleId,
    l.ManualAssignPointsId
FROM [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog l
WHERE l.CustomerId = 'CA9E37DC-E985-CAB0-1A3B-08D30721E94F'
  AND l.LogDate >= '2026-06-01T03:00:00'
  AND l.LogDate <  '2026-07-05T03:00:00'
ORDER BY l.LogDate;

-- Q4: Transferencias enviadas/recibidas en la misma ventana (descartadas — 0 filas)
SELECT
    pt.Id, pt.Date, pt.SourceChannel,
    ls.CustomerId AS Sender_CustomerId, ls.Points AS Sender_Points, ls.EventTypeCode AS Sender_Event,
    lr.CustomerId AS Receiver_CustomerId, lr.Points AS Receiver_Points, lr.EventTypeCode AS Receiver_Event
FROM [SmartFran.Solution.SmartLoyalty].sml.PointsTransference pt
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog ls ON ls.Id = pt.IdCustomerPointsLogSender
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog lr ON lr.Id = pt.IdCustomerPointsLogReceiver
WHERE (ls.CustomerId = 'CA9E37DC-E985-CAB0-1A3B-08D30721E94F' OR lr.CustomerId = 'CA9E37DC-E985-CAB0-1A3B-08D30721E94F')
  AND pt.Date >= '2026-06-01T03:00:00'
  AND pt.Date <  '2026-07-05T03:00:00'
ORDER BY pt.Date;

-- Q5: Localización de la tabla Sale (INFORMATION_SCHEMA)
SELECT TABLE_SCHEMA, TABLE_NAME, COLUMN_NAME
FROM [SmartFran.Solution.SmartLoyalty].INFORMATION_SCHEMA.COLUMNS
WHERE COLUMN_NAME IN ('SaleId', 'Id')
  AND TABLE_NAME LIKE '%Sale%'
ORDER BY TABLE_NAME, COLUMN_NAME;

-- Q6: Esquema de Sml.Sale
SELECT COLUMN_NAME, DATA_TYPE
FROM [SmartFran.Solution.SmartLoyalty].INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'Sml' AND TABLE_NAME = 'Sale'
ORDER BY ORDINAL_POSITION;

-- Q7: Traza de sucursal/terminal/tarjeta para todas las ventas de la cuenta en la ventana
SELECT
    s.Id                AS SaleId,
    s.SaleDate,
    DATEADD(HOUR, -3, s.SaleDate) AS SaleDate_UTC3,
    s.BranchOfficeId,
    bo.Code             AS BranchCode,
    bo.Name             AS BranchName,
    s.CustomerCardId,
    s.PaymentTypeCode,
    s.PlatformCode,
    s.PointsLogId,
    s.InvalidatedPointsLogId
FROM [SmartFran.Solution.SmartLoyalty].Sml.Sale s
LEFT JOIN [SmartFran.Solution.SmartLoyalty].sml.BranchOffice bo ON bo.Id = s.BranchOfficeId
WHERE s.CustomerId = 'CA9E37DC-E985-CAB0-1A3B-08D30721E94F'
  AND s.SaleDate >= '2026-06-01T03:00:00'
  AND s.SaleDate <  '2026-07-05T03:00:00'
ORDER BY s.SaleDate;

-- Q8: Suma histórica total (control cruzado contra saldo smlst)
SELECT SUM(Points) AS SumaHistoricaTotal
FROM [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog
WHERE CustomerId = 'CA9E37DC-E985-CAB0-1A3B-08D30721E94F';

-- Q9: Saldo directo al 2026-06-10 (fin del día, UTC-3) — sumado desde el log, no inferido
SELECT SUM(Points) AS Saldo_al_2026_06_10
FROM [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog
WHERE CustomerId = 'CA9E37DC-E985-CAB0-1A3B-08D30721E94F'
  AND LogDate < '2026-06-11T03:00:00';

-- Q10: Localización de la tabla maestra de Promotion
SELECT TABLE_SCHEMA, TABLE_NAME, COLUMN_NAME
FROM [SmartFran.Solution.SmartLoyalty].INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME LIKE '%Promotion%'
ORDER BY TABLE_NAME, ORDINAL_POSITION;

-- Q11: Decodificación de las promociones canjeadas el 11/06 y 16/06
SELECT
    p.Id AS PromotionId, p.Name, p.Description, p.Points, p.Type, p.Quantity
FROM [SmartFran.Solution.SmartLoyalty].Sml.Promotion p
WHERE p.Id IN (9406, 14887, 9408);

-- Q12: SaleDetail — líneas de artículo para los dos SaleId del 11/06
SELECT sd.*
FROM [SmartFran.Solution.SmartLoyalty].Sml.SaleDetail sd
WHERE sd.SaleId IN (252627711, 252628141);

-- Q13: SalePromotion — vínculo promoción/venta para los mismos SaleId
SELECT sp.*
FROM [SmartFran.Solution.SmartLoyalty].Sml.SalePromotion sp
WHERE sp.SaleId IN (252627711, 252628141);

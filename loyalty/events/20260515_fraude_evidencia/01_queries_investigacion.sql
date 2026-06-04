-- ============================================================
-- INVESTIGACIÓN DE FRAUDE — TRANSFERENCIAS DE PUNTOS
-- Fechas del evento: 2026-05-14 / 2026-05-15
-- Investigador: Dante Paniagua, SRE
-- ============================================================

USE [SmartFran.Solution.SmartLoyalty]

-- ============================================================
-- Q1. Verificación de volumen — ambas noches
-- ============================================================
SELECT
    EventTypeCode,
    COUNT(*)            AS transfers,
    SUM(ABS(Points))    AS total_pts,
    MIN(LogDate)        AS inicio,
    MAX(LogDate)        AS fin
FROM sml.CustomerPointsLog
WHERE (LogDate >= '2026-05-14 03:30:00 +00:00' AND LogDate < '2026-05-14 08:00:00 +00:00')
   OR (LogDate >= '2026-05-15 05:30:00 +00:00' AND LogDate < '2026-05-15 07:30:00 +00:00')
  AND EventTypeCode IN ('PointsByTransferSent','PointsByTransferReceived')
GROUP BY EventTypeCode, CAST(SWITCHOFFSET(LogDate,'-03:00') AS DATE)

-- ============================================================
-- Q2. Detalle de transferencias — Noche 1 (2026-05-14)
-- ============================================================
;WITH cpl AS (
    SELECT CustomerId, EventTypeCode, ABS(Points) pts
    FROM sml.CustomerPointsLog
    WHERE LogDate >= '2026-05-14 03:30:00 +00:00'
      AND LogDate <  '2026-05-14 08:00:00 +00:00'
      AND EventTypeCode IN ('PointsByTransferSent','PointsByTransferReceived')
),
agg AS (
    SELECT
        CustomerId,
        SUM(CASE WHEN EventTypeCode='PointsByTransferSent'     THEN pts ELSE 0 END) sent,
        SUM(CASE WHEN EventTypeCode='PointsByTransferReceived' THEN pts ELSE 0 END) rcvd,
        MAX(CASE WHEN EventTypeCode='PointsByTransferSent'     THEN pts ELSE 0 END) max_tx,
        COUNT(CASE WHEN EventTypeCode='PointsByTransferSent'   THEN 1  END)         cnt_sent,
        COUNT(CASE WHEN EventTypeCode='PointsByTransferReceived' THEN 1 END)        cnt_rcvd
    FROM cpl GROUP BY CustomerId
)
SELECT
    CASE WHEN a.sent>0 AND a.rcvd>0 THEN 'HUB'
         WHEN a.rcvd>0              THEN 'Receptor'
                                    ELSE 'Emisor' END      AS rol,
    p.FirstName+' '+p.LastName                             AS nombre,
    p.UidCode+' '+p.UidSerie                               AS documento,
    p.Email,
    a.cnt_sent                                             AS tx_enviadas,
    a.sent                                                 AS pts_enviados,
    a.max_tx                                               AS mayor_tx,
    a.cnt_rcvd                                             AS tx_recibidas,
    a.rcvd                                                 AS pts_recibidos,
    CASE WHEN a.sent > 8000
         THEN 'EXCEDE DIARIO (+'+CAST(a.sent-8000 AS VARCHAR)+')'
         ELSE 'OK' END                                     AS limite_diario,
    a.CustomerId
FROM agg a
JOIN sml.Person p ON a.CustomerId = p.Id
ORDER BY
    CASE WHEN a.sent>0 AND a.rcvd>0 THEN 1
         WHEN a.rcvd>0              THEN 2 ELSE 3 END,
    a.sent DESC

-- ============================================================
-- Q3. Detalle de transferencias — Noche 2 (2026-05-15)
-- ============================================================
;WITH cpl AS (
    SELECT CustomerId, EventTypeCode, ABS(Points) pts
    FROM sml.CustomerPointsLog
    WHERE LogDate >= '2026-05-15 05:30:00 +00:00'
      AND LogDate <  '2026-05-15 07:30:00 +00:00'
      AND EventTypeCode IN ('PointsByTransferSent','PointsByTransferReceived')
),
agg AS (
    SELECT
        CustomerId,
        SUM(CASE WHEN EventTypeCode='PointsByTransferSent'     THEN pts ELSE 0 END) sent,
        SUM(CASE WHEN EventTypeCode='PointsByTransferReceived' THEN pts ELSE 0 END) rcvd,
        MAX(CASE WHEN EventTypeCode='PointsByTransferSent'     THEN pts ELSE 0 END) max_tx,
        COUNT(CASE WHEN EventTypeCode='PointsByTransferSent'   THEN 1  END)         cnt_sent,
        COUNT(CASE WHEN EventTypeCode='PointsByTransferReceived' THEN 1 END)        cnt_rcvd
    FROM cpl GROUP BY CustomerId
)
SELECT
    CASE WHEN a.sent>0 AND a.rcvd>0 THEN 'HUB'
         WHEN a.rcvd>0              THEN 'Receptor'
                                    ELSE 'Emisor' END      AS rol,
    p.FirstName+' '+p.LastName                             AS nombre,
    p.UidCode+' '+p.UidSerie                               AS documento,
    p.Email,
    a.cnt_sent                                             AS tx_enviadas,
    a.sent                                                 AS pts_enviados,
    a.max_tx                                               AS mayor_tx,
    a.cnt_rcvd                                             AS tx_recibidas,
    a.rcvd                                                 AS pts_recibidos,
    CASE WHEN a.sent > 8000
         THEN 'EXCEDE DIARIO (+'+CAST(a.sent-8000 AS VARCHAR)+')'
         ELSE 'OK' END                                     AS limite_diario,
    a.CustomerId
FROM agg a
JOIN sml.Person p ON a.CustomerId = p.Id
ORDER BY
    CASE WHEN a.sent>0 AND a.rcvd>0 THEN 1
         WHEN a.rcvd>0              THEN 2 ELSE 3 END,
    a.sent DESC

-- ============================================================
-- Q4. Actividad de cuentas hub/receptoras post-evento
-- ============================================================
SELECT
    p.FirstName+' '+p.LastName  AS nombre,
    cpl.LogDate,
    cpl.EventTypeCode,
    cpl.Points,
    cpl.Note
FROM sml.CustomerPointsLog cpl
JOIN sml.Person p ON cpl.CustomerId = p.Id
WHERE cpl.CustomerId IN (
    'B8B4E7DC-0353-C4B3-53E0-08DC0286FF2B',
    'F926ABB4-3B3C-C783-B653-08DDCBC46A21',
    'E06CD7DA-2EEE-CA28-A8FE-08D89BDDFE90',
    '348A7937-0090-CC25-1789-08DDB839291B',
    '6458F887-F02A-CC30-A3E6-08D9C25043D3',
    '1AD71215-EEA1-CF8F-7101-08DE1977E6C0'
)
  AND cpl.LogDate >= '2026-05-14 04:00:00 +00:00'
ORDER BY cpl.CustomerId, cpl.LogDate

-- ============================================================
-- Q5. Patrón de registro de cuentas involucradas
-- ============================================================
;WITH senders AS (
    SELECT DISTINCT CustomerId
    FROM sml.CustomerPointsLog
    WHERE LogDate >= '2026-05-14 03:30:00 +00:00'
      AND LogDate <  '2026-05-15 08:00:00 +00:00'
      AND EventTypeCode = 'PointsByTransferSent'
)
SELECT
    c.RegistrationChannel,
    c.RegisterById,
    CAST(c.CreatedDate AS DATE)     AS created_date,
    COUNT(*)                        AS accounts,
    MIN(p.UidSerie)                 AS dni_min,
    MAX(p.UidSerie)                 AS dni_max
FROM senders s
JOIN sml.Customer c ON s.CustomerId = c.Id
JOIN sml.Person   p ON s.CustomerId = p.Id
GROUP BY c.RegistrationChannel, c.RegisterById, CAST(c.CreatedDate AS DATE)
ORDER BY COUNT(*) DESC

-- ============================================================
-- Q6. Export raw PointsLog — ambas noches (para CSV completo)
-- Exportar desde SSMS: Results to File (.csv)
-- ============================================================
SELECT
    cpl.Id,
    cpl.CustomerId,
    p.FirstName+' '+p.LastName      AS nombre,
    p.UidCode+' '+p.UidSerie        AS documento,
    p.Email,
    cpl.LogDate,
    cpl.EventTypeCode,
    cpl.Points,
    cpl.Note,
    CASE
        WHEN cpl.LogDate >= '2026-05-14 03:30:00 +00:00'
         AND cpl.LogDate <  '2026-05-14 08:00:00 +00:00' THEN 'Noche 1'
        WHEN cpl.LogDate >= '2026-05-15 05:30:00 +00:00'
         AND cpl.LogDate <  '2026-05-15 07:30:00 +00:00' THEN 'Noche 2'
    END                             AS noche
FROM sml.CustomerPointsLog cpl
JOIN sml.Person p ON cpl.CustomerId = p.Id
WHERE
    (   (cpl.LogDate >= '2026-05-14 03:30:00 +00:00' AND cpl.LogDate < '2026-05-14 08:00:00 +00:00')
     OR (cpl.LogDate >= '2026-05-15 05:30:00 +00:00' AND cpl.LogDate < '2026-05-15 07:30:00 +00:00')
    )
    AND cpl.EventTypeCode IN ('PointsByTransferSent','PointsByTransferReceived')
ORDER BY cpl.LogDate

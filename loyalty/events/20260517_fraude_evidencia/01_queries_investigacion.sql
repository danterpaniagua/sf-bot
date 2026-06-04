-- ============================================================
-- INVESTIGACIÓN DE FRAUDE — TRANSFERENCIAS DE PUNTOS
-- Fecha del evento: 2026-05-17
-- Evento 1 (madrugada): 01:00–02:00 UTC-3  →  04:00–05:00 GMT
-- Evento 2 (mañana):    08:00–10:00 UTC-3  →  11:00–13:00 GMT
-- Investigador: Dante Paniagua, SRE
-- ============================================================

USE [SmartFran.Solution.SmartLoyalty]

-- ============================================================
-- Q1. Verificación de volumen — ambos eventos
-- ============================================================
SELECT
    CASE
        WHEN LogDate >= '2026-05-17 04:00:00 +00:00'
         AND LogDate <  '2026-05-17 05:00:00 +00:00' THEN 'Evento 1 - Madrugada'
        WHEN LogDate >= '2026-05-17 11:00:00 +00:00'
         AND LogDate <  '2026-05-17 13:00:00 +00:00' THEN 'Evento 2 - Mañana'
    END                     AS evento,
    EventTypeCode,
    COUNT(*)                AS transfers,
    SUM(ABS(Points))        AS total_pts,
    MIN(LogDate)            AS inicio,
    MAX(LogDate)            AS fin
FROM sml.CustomerPointsLog
WHERE
    (   (LogDate >= '2026-05-17 04:00:00 +00:00' AND LogDate < '2026-05-17 05:00:00 +00:00')
     OR (LogDate >= '2026-05-17 11:00:00 +00:00' AND LogDate < '2026-05-17 13:00:00 +00:00')
    )
    AND EventTypeCode IN ('PointsByTransferSent','PointsByTransferReceived')
GROUP BY
    CASE
        WHEN LogDate >= '2026-05-17 04:00:00 +00:00'
         AND LogDate <  '2026-05-17 05:00:00 +00:00' THEN 'Evento 1 - Madrugada'
        WHEN LogDate >= '2026-05-17 11:00:00 +00:00'
         AND LogDate <  '2026-05-17 13:00:00 +00:00' THEN 'Evento 2 - Mañana'
    END,
    EventTypeCode
ORDER BY evento, EventTypeCode

-- ============================================================
-- Q2. Detalle de participantes — Evento 1 (madrugada)
-- ============================================================
;WITH cpl AS (
    SELECT CustomerId, EventTypeCode, ABS(Points) pts
    FROM sml.CustomerPointsLog
    WHERE LogDate >= '2026-05-17 04:00:00 +00:00'
      AND LogDate <  '2026-05-17 05:00:00 +00:00'
      AND EventTypeCode IN ('PointsByTransferSent','PointsByTransferReceived')
),
agg AS (
    SELECT
        CustomerId,
        SUM(CASE WHEN EventTypeCode='PointsByTransferSent'       THEN pts ELSE 0 END) sent,
        SUM(CASE WHEN EventTypeCode='PointsByTransferReceived'   THEN pts ELSE 0 END) rcvd,
        MAX(CASE WHEN EventTypeCode='PointsByTransferSent'       THEN pts ELSE 0 END) max_tx,
        COUNT(CASE WHEN EventTypeCode='PointsByTransferSent'     THEN 1  END)         cnt_sent,
        COUNT(CASE WHEN EventTypeCode='PointsByTransferReceived' THEN 1  END)         cnt_rcvd
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
-- Q3. Detalle de participantes — Evento 2 (mañana)
-- ============================================================
;WITH cpl AS (
    SELECT CustomerId, EventTypeCode, ABS(Points) pts
    FROM sml.CustomerPointsLog
    WHERE LogDate >= '2026-05-17 11:00:00 +00:00'
      AND LogDate <  '2026-05-17 13:00:00 +00:00'
      AND EventTypeCode IN ('PointsByTransferSent','PointsByTransferReceived')
),
agg AS (
    SELECT
        CustomerId,
        SUM(CASE WHEN EventTypeCode='PointsByTransferSent'       THEN pts ELSE 0 END) sent,
        SUM(CASE WHEN EventTypeCode='PointsByTransferReceived'   THEN pts ELSE 0 END) rcvd,
        MAX(CASE WHEN EventTypeCode='PointsByTransferSent'       THEN pts ELSE 0 END) max_tx,
        COUNT(CASE WHEN EventTypeCode='PointsByTransferSent'     THEN 1  END)         cnt_sent,
        COUNT(CASE WHEN EventTypeCode='PointsByTransferReceived' THEN 1  END)         cnt_rcvd
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
-- Q4. Patrón de cadencia — detección de automatización
-- ============================================================
SELECT
    CASE
        WHEN LogDate >= '2026-05-17 04:00:00 +00:00' THEN 'Evento 1'
        ELSE 'Evento 2'
    END                                                    AS evento,
    CustomerId,
    LogDate,
    LAG(LogDate) OVER (PARTITION BY CustomerId ORDER BY LogDate) AS prev_log,
    DATEDIFF(SECOND,
        LAG(LogDate) OVER (PARTITION BY CustomerId ORDER BY LogDate),
        LogDate)                                           AS seg_desde_prev,
    Points,
    Note
FROM sml.CustomerPointsLog
WHERE
    (   (LogDate >= '2026-05-17 04:00:00 +00:00' AND LogDate < '2026-05-17 05:00:00 +00:00')
     OR (LogDate >= '2026-05-17 11:00:00 +00:00' AND LogDate < '2026-05-17 13:00:00 +00:00')
    )
    AND EventTypeCode = 'PointsByTransferSent'
ORDER BY CustomerId, LogDate

-- ============================================================
-- Q5. Patrón de registro de cuentas emisoras — ambos eventos
-- ============================================================
;WITH senders AS (
    SELECT DISTINCT CustomerId
    FROM sml.CustomerPointsLog
    WHERE
        (   (LogDate >= '2026-05-17 04:00:00 +00:00' AND LogDate < '2026-05-17 05:00:00 +00:00')
         OR (LogDate >= '2026-05-17 11:00:00 +00:00' AND LogDate < '2026-05-17 13:00:00 +00:00')
        )
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
-- Q6. Export raw PointsLog — ambos eventos (Results to File)
-- ============================================================
SELECT
    cpl.Id,
    cpl.CustomerId,
    p.FirstName+' '+p.LastName                             AS nombre,
    p.UidCode+' '+p.UidSerie                               AS documento,
    p.Email,
    cpl.LogDate,
    CAST(SWITCHOFFSET(cpl.LogDate,'-03:00') AS DATETIME)   AS LogDate_local,
    cpl.EventTypeCode,
    cpl.Points,
    cpl.Note,
    CASE
        WHEN cpl.LogDate >= '2026-05-17 04:00:00 +00:00'
         AND cpl.LogDate <  '2026-05-17 05:00:00 +00:00' THEN 'Evento 1 - Madrugada'
        WHEN cpl.LogDate >= '2026-05-17 11:00:00 +00:00'
         AND cpl.LogDate <  '2026-05-17 13:00:00 +00:00' THEN 'Evento 2 - Mañana'
    END                                                    AS evento
FROM sml.CustomerPointsLog cpl
JOIN sml.Person p ON cpl.CustomerId = p.Id
WHERE
    (   (cpl.LogDate >= '2026-05-17 04:00:00 +00:00' AND cpl.LogDate < '2026-05-17 05:00:00 +00:00')
     OR (cpl.LogDate >= '2026-05-17 11:00:00 +00:00' AND cpl.LogDate < '2026-05-17 13:00:00 +00:00')
    )
    AND cpl.EventTypeCode IN ('PointsByTransferSent','PointsByTransferReceived')
ORDER BY cpl.LogDate

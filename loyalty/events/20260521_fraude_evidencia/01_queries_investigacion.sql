-- ============================================================
-- Investigación: Posible fraude en transferencia de puntos
-- Evento: 2026-05-21 01:00–02:00 (UTC-3) = 04:00–06:00 GMT
-- Ventana de consulta: 2026-05-21 02:00–08:00 +00:00
-- Base de datos: SmartFran.Solution.SmartLoyalty
-- ============================================================

-- Q1: Volumen de transferencias en la ventana
-- Agrupado por día local (UTC-3) y canal de origen.
SELECT
    CAST(DATEADD(HOUR, -3, pt.[Date]) AS DATE)   AS fecha_local,
    pt.SourceChannel,
    COUNT(*)                                      AS total_transferencias,
    SUM(ABS(cpl_s.Points))                        AS total_puntos
FROM [SmartFran.Solution.SmartLoyalty].[sml].[PointsTransference]  pt
JOIN [SmartFran.Solution.SmartLoyalty].[sml].[CustomerPointsLog]   cpl_s
    ON cpl_s.Id = pt.IdCustomerPointsLogSender
WHERE pt.[Date] >= '2026-05-21 02:00:00 +00:00'
  AND pt.[Date] <  '2026-05-21 08:00:00 +00:00'
GROUP BY
    CAST(DATEADD(HOUR, -3, pt.[Date]) AS DATE),
    pt.SourceChannel
ORDER BY fecha_local, total_puntos DESC;


-- Q2: Detección de fan-in
-- Cuentas que recibieron puntos de múltiples emisores distintos en la ventana.
SELECT
    cpl_r.CustomerId                              AS receptor_id,
    COUNT(DISTINCT cpl_s.CustomerId)              AS emisores_distintos,
    COUNT(*)                                      AS transferencias_recibidas,
    SUM(cpl_r.Points)                             AS puntos_recibidos
FROM [SmartFran.Solution.SmartLoyalty].[sml].[PointsTransference]  pt
JOIN [SmartFran.Solution.SmartLoyalty].[sml].[CustomerPointsLog]   cpl_s
    ON cpl_s.Id = pt.IdCustomerPointsLogSender
JOIN [SmartFran.Solution.SmartLoyalty].[sml].[CustomerPointsLog]   cpl_r
    ON cpl_r.Id = pt.IdCustomerPointsLogReceiver
WHERE pt.[Date] >= '2026-05-21 02:00:00 +00:00'
  AND pt.[Date] <  '2026-05-21 08:00:00 +00:00'
GROUP BY cpl_r.CustomerId
HAVING COUNT(DISTINCT cpl_s.CustomerId) > 1
ORDER BY emisores_distintos DESC, puntos_recibidos DESC;


-- Q3: Resolución de identidad
-- Nombre, documento, email y rol de cada participante por transferencia.
SELECT
    pt.Id                                         AS transfer_id,
    pt.[Date]                                     AS fecha_gmt,
    DATEADD(HOUR, -3, pt.[Date])                  AS fecha_local,
    pt.SourceChannel,
    -- Emisor
    cpl_s.CustomerId                              AS emisor_id,
    p_s.FirstName + ' ' + p_s.LastName            AS emisor_nombre,
    p_s.UidCode + ' ' + p_s.UidSerie              AS emisor_documento,
    p_s.Email                                     AS emisor_email,
    cpl_s.Points                                  AS puntos_enviados,
    -- Receptor
    cpl_r.CustomerId                              AS receptor_id,
    p_r.FirstName + ' ' + p_r.LastName            AS receptor_nombre,
    p_r.UidCode + ' ' + p_r.UidSerie              AS receptor_documento,
    p_r.Email                                     AS receptor_email,
    cpl_r.Points                                  AS puntos_recibidos
FROM [SmartFran.Solution.SmartLoyalty].[sml].[PointsTransference]  pt
JOIN [SmartFran.Solution.SmartLoyalty].[sml].[CustomerPointsLog]   cpl_s ON cpl_s.Id = pt.IdCustomerPointsLogSender
JOIN [SmartFran.Solution.SmartLoyalty].[sml].[CustomerPointsLog]   cpl_r ON cpl_r.Id = pt.IdCustomerPointsLogReceiver
JOIN [SmartFran.Solution.SmartLoyalty].[sml].[Person]              p_s   ON p_s.Id   = cpl_s.CustomerId
JOIN [SmartFran.Solution.SmartLoyalty].[sml].[Person]              p_r   ON p_r.Id   = cpl_r.CustomerId
WHERE pt.[Date] >= '2026-05-21 02:00:00 +00:00'
  AND pt.[Date] <  '2026-05-21 08:00:00 +00:00'
ORDER BY pt.[Date];


-- Q4: Validación de límites
-- Emisores que superaron 8.000 puntos enviados en el día (límite diario de transferencia).
SELECT
    cpl_s.CustomerId                              AS emisor_id,
    p.FirstName + ' ' + p.LastName                AS emisor_nombre,
    p.UidCode + ' ' + p.UidSerie                  AS emisor_documento,
    COUNT(*)                                      AS transferencias,
    SUM(ABS(cpl_s.Points))                        AS total_puntos_enviados
FROM [SmartFran.Solution.SmartLoyalty].[sml].[PointsTransference]  pt
JOIN [SmartFran.Solution.SmartLoyalty].[sml].[CustomerPointsLog]   cpl_s ON cpl_s.Id = pt.IdCustomerPointsLogSender
JOIN [SmartFran.Solution.SmartLoyalty].[sml].[Person]              p     ON p.Id     = cpl_s.CustomerId
WHERE pt.[Date] >= '2026-05-21 02:00:00 +00:00'
  AND pt.[Date] <  '2026-05-21 08:00:00 +00:00'
GROUP BY cpl_s.CustomerId, p.FirstName, p.LastName, p.UidCode, p.UidSerie
HAVING SUM(ABS(cpl_s.Points)) > 8000
ORDER BY total_puntos_enviados DESC;


-- Q5: Saldo actual de cuentas receptoras (hub activity)
-- Completar con los receptor_id identificados en Q2.
-- Saldo >> puntos recibidos = concentración previa (riesgo de consolidación).
-- Saldo = 0 en emisores = vaciamiento total de cuenta.
SELECT
    scpl.CustomerId,
    p.FirstName + ' ' + p.LastName                AS nombre,
    p.UidCode + ' ' + p.UidSerie                  AS documento,
    scpl.Points                                   AS saldo_actual,
    scpl.LastLogDate                              AS ultimo_movimiento
FROM [SmartFran.Solution.SmartLoyalty].[smlst].[CustomerPointsLog] scpl
JOIN [SmartFran.Solution.SmartLoyalty].[sml].[Person]              p    ON p.Id = scpl.CustomerId
WHERE scpl.CustomerId IN (
    -- Fan-in (Q2)
    '73514A0D-9D8F-C16A-5F0E-08D4251C8784',  -- Camila Ruiz
    'C61BC332-4642-CAD9-14BB-08DC0FAF9ADF',  -- Daiana Ricabarren
    -- Receptores de Jonatan Belen (28.000 pts)
    '941EFCA8-A0B0-C4DE-E2BF-08DE5EDB0614',  -- Ana Noriega (16.000 recibidos)
    'C76F2594-2B6F-C133-5F8E-08DE92CA6DD8',  -- Anabel Belén (12.000 recibidos)
    -- Rapid accumulate-and-transfer
    '420724D4-38EF-C22E-3757-08DE55FCFF7E',  -- Valentina Cortez
    -- Circular transfer
    '5BD60584-5EA6-CE8C-6588-08DBD30B769D'   -- Adrian Cares
)
ORDER BY scpl.Points DESC;


-- Q6: Patrón de registro de emisores
-- Agrupa por canal, registrador y fecha de creación.
-- Alta concentración en misma fecha/canal/registrador = cuentas mula sintéticas.
SELECT
    c.RegistrationChannel,
    c.RegisterById,
    CAST(c.CreatedDate AS DATE)                   AS fecha_registro,
    COUNT(*)                                      AS cuentas
FROM [SmartFran.Solution.SmartLoyalty].[sml].[PointsTransference]  pt
JOIN [SmartFran.Solution.SmartLoyalty].[sml].[CustomerPointsLog]   cpl_s ON cpl_s.Id = pt.IdCustomerPointsLogSender
JOIN [SmartFran.Solution.SmartLoyalty].[sml].[Customer]            c     ON c.Id     = cpl_s.CustomerId
WHERE pt.[Date] >= '2026-05-21 02:00:00 +00:00'
  AND pt.[Date] <  '2026-05-21 08:00:00 +00:00'
GROUP BY c.RegistrationChannel, c.RegisterById, CAST(c.CreatedDate AS DATE)
ORDER BY cuentas DESC;

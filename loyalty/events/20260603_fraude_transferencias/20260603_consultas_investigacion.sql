-- ============================================================
-- Investigación: Fraude de Transferencias — 2026-06-03
-- Ventana reportada: 07:00–08:00 UTC-3
-- Vectores: credential stuffing + mal uso beneficio empleados
-- Ventana GMT: 10:00–11:00 GMT
-- ============================================================

-- T1: Volumen en ventana reportada
SELECT
    COUNT(*)                                        AS Total_Transferencias,
    SUM(ABS(cpl_s.Points))                          AS Puntos_Total,
    COUNT(DISTINCT pt.IdCustomerPointsLogSender)    AS Emisores_Unicos,
    COUNT(DISTINCT pt.IdCustomerPointsLogReceiver)  AS Receptores_Unicos,
    MIN(DATEADD(HOUR, -3, pt.Date))                 AS Primera_UTC3,
    MAX(DATEADD(HOUR, -3, pt.Date))                 AS Ultima_UTC3
FROM [SmartFran.Solution.SmartLoyalty].sml.PointsTransference      pt
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog       cpl_s ON cpl_s.Id = pt.IdCustomerPointsLogSender
WHERE
    pt.Date >= '2026-06-03T10:00:00.000'
    AND pt.Date <  '2026-06-03T11:00:00.000';

-- T2: Fan-in — receptores con múltiples emisores en ventana
SELECT
    cpl_r.CustomerId                                AS Receptor_Id,
    COUNT(DISTINCT cpl_s.CustomerId)               AS Emisores_Distintos,
    COUNT(*)                                        AS Transferencias_Recibidas,
    SUM(cpl_r.Points)                               AS Puntos_Recibidos
FROM [SmartFran.Solution.SmartLoyalty].sml.PointsTransference      pt
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog       cpl_s ON cpl_s.Id = pt.IdCustomerPointsLogSender
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog       cpl_r ON cpl_r.Id = pt.IdCustomerPointsLogReceiver
WHERE
    pt.Date >= '2026-06-03T10:00:00.000'
    AND pt.Date <  '2026-06-03T11:00:00.000'
GROUP BY cpl_r.CustomerId
HAVING COUNT(DISTINCT cpl_s.CustomerId) > 1
ORDER BY Emisores_Distintos DESC, Puntos_Recibidos DESC;

-- T3: Resolución de identidad — todos los participantes en ventana
SELECT
    pt.Id                                           AS TransferenciaId,
    DATEADD(HOUR, -3, pt.Date)                      AS Fecha_UTC3,
    pt.SourceChannel,
    ps.FirstName + ' ' + ps.LastName               AS Emisor,
    ps.UidCode + ' ' + ps.UidSerie                 AS Doc_Emisor,
    cpl_s.Points                                    AS Puntos_Enviados,
    pr.FirstName + ' ' + pr.LastName               AS Receptor,
    pr.UidCode + ' ' + pr.UidSerie                 AS Doc_Receptor,
    cpl_r.Points                                    AS Puntos_Recibidos
FROM [SmartFran.Solution.SmartLoyalty].sml.PointsTransference      pt
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog       cpl_s ON cpl_s.Id = pt.IdCustomerPointsLogSender
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog       cpl_r ON cpl_r.Id = pt.IdCustomerPointsLogReceiver
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person                  ps    ON ps.Id    = cpl_s.CustomerId
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person                  pr    ON pr.Id    = cpl_r.CustomerId
WHERE
    pt.Date >= '2026-06-03T10:00:00.000'
    AND pt.Date <  '2026-06-03T11:00:00.000'
ORDER BY pt.Date;

-- T4: Validación de límites — emisores con > 8.000 pts enviados hoy
SELECT
    cpl_s.CustomerId                                AS Emisor_Id,
    ps.FirstName + ' ' + ps.LastName               AS Emisor,
    ps.UidCode                                      AS TipoDoc,
    ps.UidSerie                                     AS Documento,
    COUNT(*)                                        AS Transferencias,
    SUM(ABS(cpl_s.Points))                          AS Puntos_Enviados_Dia
FROM [SmartFran.Solution.SmartLoyalty].sml.PointsTransference      pt
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog       cpl_s ON cpl_s.Id = pt.IdCustomerPointsLogSender
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person                  ps    ON ps.Id    = cpl_s.CustomerId
WHERE
    pt.Date >= '2026-06-03T03:00:00.000'
    AND pt.Date <  '2026-06-04T03:00:00.000'
GROUP BY cpl_s.CustomerId, ps.FirstName, ps.LastName, ps.UidCode, ps.UidSerie
HAVING SUM(ABS(cpl_s.Points)) > 8000
ORDER BY Puntos_Enviados_Dia DESC;

-- T5: Saldo actual de todos los participantes en ventana
SELECT
    p.FirstName + ' ' + p.LastName                 AS Cliente,
    p.UidCode                                       AS TipoDoc,
    p.UidSerie                                      AS Documento,
    bal.Points                                      AS Saldo_Actual,
    bal.LastLogDate
FROM [SmartFran.Solution.SmartLoyalty].sml.PointsTransference      pt
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog       cpl   ON cpl.Id IN (pt.IdCustomerPointsLogSender, pt.IdCustomerPointsLogReceiver)
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person                  p     ON p.Id = cpl.CustomerId
JOIN [SmartFran.Solution.SmartLoyalty].smlst.CustomerPointsLog     bal   ON bal.CustomerId = cpl.CustomerId
WHERE
    pt.Date >= '2026-06-03T10:00:00.000'
    AND pt.Date <  '2026-06-03T11:00:00.000'
GROUP BY p.FirstName, p.LastName, p.UidCode, p.UidSerie, bal.Points, bal.LastLogDate
ORDER BY bal.Points DESC;

-- T6: Patrón de registro de emisores en ventana
SELECT
    c.RegistrationChannel,
    c.RegisterById,
    CONVERT(DATE, c.CreatedDate)                    AS Fecha_Registro,
    COUNT(DISTINCT cpl_s.CustomerId)               AS Emisores,
    SUM(ABS(cpl_s.Points))                          AS Puntos_Enviados
FROM [SmartFran.Solution.SmartLoyalty].sml.PointsTransference      pt
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog       cpl_s ON cpl_s.Id = pt.IdCustomerPointsLogSender
JOIN [SmartFran.Solution.SmartLoyalty].sml.Customer                c     ON c.Id     = cpl_s.CustomerId
WHERE
    pt.Date >= '2026-06-03T10:00:00.000'
    AND pt.Date <  '2026-06-03T11:00:00.000'
GROUP BY c.RegistrationChannel, c.RegisterById, CONVERT(DATE, c.CreatedDate)
ORDER BY Emisores DESC;

-- T7: Detalle completo de transfers día para Roldan y Homer Spo
SELECT
    pt.Id                                       AS TransferenciaId,
    DATEADD(HOUR, -3, pt.Date)                  AS Fecha_UTC3,
    pt.SourceChannel,
    ps.FirstName + ' ' + ps.LastName           AS Emisor,
    ps.UidSerie                                 AS Doc_Emisor,
    ABS(cpl_s.Points)                           AS Puntos,
    pr.FirstName + ' ' + pr.LastName           AS Receptor,
    pr.UidSerie                                 AS Doc_Receptor,
    bal_r.Points                                AS Saldo_Receptor_Actual
FROM [SmartFran.Solution.SmartLoyalty].sml.PointsTransference      pt
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog       cpl_s ON cpl_s.Id = pt.IdCustomerPointsLogSender
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog       cpl_r ON cpl_r.Id = pt.IdCustomerPointsLogReceiver
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person                  ps    ON ps.Id    = cpl_s.CustomerId
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person                  pr    ON pr.Id    = cpl_r.CustomerId
JOIN [SmartFran.Solution.SmartLoyalty].smlst.CustomerPointsLog     bal_r ON bal_r.CustomerId = cpl_r.CustomerId
WHERE
    cpl_s.CustomerId IN (
        '7E8B3C9E-5D71-C842-64CD-08D8745E0AD3',  -- Carlos Andrés Roldan
        '8DD60691-D9BE-C158-FF02-08DEBAC4AD81'   -- Homer Spo
    )
    AND pt.Date >= '2026-06-03T03:00:00.000'
    AND pt.Date <  '2026-06-04T03:00:00.000'
ORDER BY pt.Date;

-- T8: Origen de puntos de emisores en ventana (¿empleados Grido?)
-- Reemplazar UidSerie según cuenta a verificar
SELECT TOP 20
    DATEADD(HOUR, -3, cpl.LogDate)              AS Fecha_UTC3,
    cpl.Points,
    cpl.EventTypeCode,
    cpl.ManualAssignPointsId,
    cpl.Note
FROM [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog cpl
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person p ON p.Id = cpl.CustomerId
WHERE p.UidSerie = '37195561'   -- Matias Ezequiel Roggio (cambiar por DNI a verificar)
  AND cpl.Points > 0
ORDER BY cpl.LogDate DESC;

-- T9: Origen de puntos para Roldan y Homer Spo
SELECT TOP 20
    p.FirstName + ' ' + p.LastName             AS Cliente,
    p.UidSerie                                  AS Documento,
    DATEADD(HOUR, -3, cpl.LogDate)              AS Fecha_UTC3,
    cpl.Points,
    cpl.EventTypeCode,
    cpl.ManualAssignPointsId,
    cpl.Note
FROM [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog cpl
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person            p   ON p.Id = cpl.CustomerId
WHERE cpl.CustomerId IN (
    '7E8B3C9E-5D71-C842-64CD-08D8745E0AD3',  -- Carlos Andrés Roldan
    '8DD60691-D9BE-C158-FF02-08DEBAC4AD81'   -- Homer Spo
)
AND cpl.Points > 0
ORDER BY cpl.CustomerId, cpl.LogDate DESC;

-- T10: Perfil de cuentas hub — Nahir Niz y Lucas Riquelme
SELECT
    p.FirstName + ' ' + p.LastName             AS Cliente,
    p.UidSerie                                  AS Documento,
    DATEADD(HOUR, -3, cpl.LogDate)              AS Fecha_UTC3,
    cpl.Points,
    cpl.EventTypeCode,
    cpl.ManualAssignPointsId
FROM [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog cpl
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person            p   ON p.Id = cpl.CustomerId
WHERE p.UidSerie IN ('44238411', '46374837')  -- Lucas Riquelme, Nahir Niz
ORDER BY p.UidSerie, cpl.LogDate DESC;

-- T11: Senders que alimentaron a Homer Spo (identificación de cuentas comprometidas)
SELECT
    DATEADD(HOUR, -3, pt.Date)                  AS Fecha_UTC3,
    pt.SourceChannel,
    ps.FirstName + ' ' + ps.LastName           AS Emisor,
    ps.UidCode + ' ' + ps.UidSerie             AS Documento,
    ABS(cpl_s.Points)                           AS Puntos,
    c.RegistrationChannel,
    CONVERT(DATE, c.CreatedDate)                AS Fecha_Registro,
    bal_s.Points                                AS Saldo_Emisor_Actual
FROM [SmartFran.Solution.SmartLoyalty].sml.PointsTransference      pt
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog       cpl_r ON cpl_r.Id = pt.IdCustomerPointsLogReceiver
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog       cpl_s ON cpl_s.Id = pt.IdCustomerPointsLogSender
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person                  ps    ON ps.Id    = cpl_s.CustomerId
JOIN [SmartFran.Solution.SmartLoyalty].sml.Customer                c     ON c.Id     = cpl_s.CustomerId
JOIN [SmartFran.Solution.SmartLoyalty].smlst.CustomerPointsLog     bal_s ON bal_s.CustomerId = cpl_s.CustomerId
WHERE cpl_r.CustomerId = '8DD60691-D9BE-C158-FF02-08DEBAC4AD81'  -- Homer Spo
  AND pt.Date >= '2026-05-25T00:00:00.000'
ORDER BY pt.Date;

-- ============================================================
-- Consultas de seguimiento
-- ============================================================

-- Verificar si Lucas Riquelme redistribuyó los 50.000 pts desde 01:52 UTC-3
SELECT
    DATEADD(HOUR, -3, cpl.LogDate)  AS Fecha_UTC3,
    cpl.Points,
    cpl.EventTypeCode
FROM [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog cpl
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person p ON p.Id = cpl.CustomerId
WHERE p.UidSerie = '44238411'  -- Lucas Riquelme
  AND cpl.LogDate >= '2026-06-03T04:52:00.000'  -- desde 01:52 UTC-3
ORDER BY cpl.LogDate DESC;

-- Verificar si Nahir Niz canjeó los 30.000 pts recibidos hoy
SELECT
    DATEADD(HOUR, -3, cpl.LogDate)  AS Fecha_UTC3,
    cpl.Points,
    cpl.EventTypeCode
FROM [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog cpl
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person p ON p.Id = cpl.CustomerId
WHERE p.UidSerie = '46374837'  -- Nahir Niz
  AND cpl.LogDate >= '2026-06-03T03:00:00.000'
ORDER BY cpl.LogDate DESC;

-- Investigar Leonardo Della Nave — superposición entre vectores
SELECT
    DATEADD(HOUR, -3, cpl.LogDate)  AS Fecha_UTC3,
    cpl.Points,
    cpl.EventTypeCode,
    cpl.ManualAssignPointsId,
    cpl.Note
FROM [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog cpl
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person p ON p.Id = cpl.CustomerId
WHERE p.UidSerie = '42022733'  -- Leonardo Della Nave
ORDER BY cpl.LogDate DESC;

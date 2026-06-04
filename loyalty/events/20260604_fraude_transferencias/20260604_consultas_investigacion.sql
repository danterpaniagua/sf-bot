-- ============================================================
-- Investigación: Transferencias sospechosas 2026-06-04
-- Ventana UTC-3: 01:00 – 09:00
-- Ventana GMT:   04:00 – 12:00
-- ============================================================
-- HALLAZGOS (análisis realizado 2026-06-04):
--   CRÍTICO: Esquema circular Simon Brizuela (46845173/46845174) / Dimon Briz (123456)
--   ALTO: María Celeste Mamanis → Santiago Cabral — automatización + límite superado
--   MEDIO: Sergio Emanuel Cordero — 16.000 pts en 16 segundos, dos receptores distintos
-- ============================================================

-- Q1: Resumen por hora — volumen y participantes
SELECT
    FORMAT(DATEADD(HOUR, -3, pt.Date), 'yyyy-MM-dd HH:00') AS Hora_UTC3,
    COUNT(*)                                                  AS Transferencias,
    SUM(ABS(sender.Points))                                   AS Puntos_Enviados,
    COUNT(DISTINCT sender.CustomerId)                         AS Emisores,
    COUNT(DISTINCT receiver.CustomerId)                       AS Receptores
FROM [SmartFran.Solution.SmartLoyalty].sml.PointsTransference pt
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog sender
    ON sender.Id = pt.IdCustomerPointsLogSender
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog receiver
    ON receiver.Id = pt.IdCustomerPointsLogReceiver
WHERE pt.Date >= '2026-06-04T04:00:00+00:00'
  AND pt.Date <  '2026-06-04T12:00:00+00:00'
GROUP BY FORMAT(DATEADD(HOUR, -3, pt.Date), 'yyyy-MM-dd HH:00')
ORDER BY Hora_UTC3;

-- Q2: Fan-in — receptores con más de un emisor distinto
SELECT
    receiver.CustomerId                       AS Receptor_Id,
    COUNT(DISTINCT sender.CustomerId)         AS Emisores_Distintos,
    COUNT(*)                                  AS Transferencias_Recibidas,
    SUM(receiver.Points)                      AS Puntos_Recibidos,
    MIN(pt.Date)                              AS Primera_GMT,
    MAX(pt.Date)                              AS Ultima_GMT
FROM [SmartFran.Solution.SmartLoyalty].sml.PointsTransference pt
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog sender
    ON sender.Id = pt.IdCustomerPointsLogSender
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog receiver
    ON receiver.Id = pt.IdCustomerPointsLogReceiver
WHERE pt.Date >= '2026-06-04T04:00:00+00:00'
  AND pt.Date <  '2026-06-04T12:00:00+00:00'
GROUP BY receiver.CustomerId
HAVING COUNT(DISTINCT sender.CustomerId) > 1
ORDER BY Emisores_Distintos DESC, Puntos_Recibidos DESC;

-- Q3: Cadencia por minuto — señal de automatización si hay ráfagas en 1-2 minutos
SELECT
    FORMAT(DATEADD(HOUR, -3, pt.Date), 'yyyy-MM-dd HH:mm') AS Minuto_UTC3,
    COUNT(*)                                                  AS Transferencias,
    SUM(ABS(sender.Points))                                   AS Puntos
FROM [SmartFran.Solution.SmartLoyalty].sml.PointsTransference pt
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog sender
    ON sender.Id = pt.IdCustomerPointsLogSender
WHERE pt.Date >= '2026-06-04T04:00:00+00:00'
  AND pt.Date <  '2026-06-04T12:00:00+00:00'
GROUP BY FORMAT(DATEADD(HOUR, -3, pt.Date), 'yyyy-MM-dd HH:mm')
ORDER BY Minuto_UTC3;

-- Q4: Resolución de identidad — todos los participantes con nombre, DNI y canal
SELECT
    FORMAT(DATEADD(HOUR, -3, pt.Date), 'yyyy-MM-dd HH:mm:ss') AS Hora_UTC3,
    pt.SourceChannel,
    sender.CustomerId                                            AS Emisor_Id,
    ps.FirstName + ' ' + ps.LastName                            AS Emisor_Nombre,
    ps.UidCode                                                   AS Emisor_TipoDoc,
    ps.UidSerie                                                  AS Emisor_Documento,
    ABS(sender.Points)                                           AS Puntos,
    receiver.CustomerId                                          AS Receptor_Id,
    pr.FirstName + ' ' + pr.LastName                            AS Receptor_Nombre,
    pr.UidCode                                                   AS Receptor_TipoDoc,
    pr.UidSerie                                                  AS Receptor_Documento
FROM [SmartFran.Solution.SmartLoyalty].sml.PointsTransference pt
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog sender
    ON sender.Id = pt.IdCustomerPointsLogSender
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog receiver
    ON receiver.Id = pt.IdCustomerPointsLogReceiver
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person ps
    ON ps.Id = sender.CustomerId
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person pr
    ON pr.Id = receiver.CustomerId
WHERE pt.Date >= '2026-06-04T04:00:00+00:00'
  AND pt.Date <  '2026-06-04T12:00:00+00:00'
ORDER BY pt.Date;

-- Q5: Validación de límites — emisores que superan 8.000 pts en la ventana
-- Nota: los colaboradores tienen límite de 30.000 pts/día — confirmar perfil antes de declarar infracción
SELECT
    sender.CustomerId                            AS Emisor_Id,
    p.FirstName + ' ' + p.LastName               AS Nombre,
    p.UidCode                                     AS TipoDoc,
    p.UidSerie                                    AS Documento,
    COUNT(*)                                      AS Transferencias,
    SUM(ABS(sender.Points))                       AS Puntos_Enviados_Ventana,
    CASE WHEN SUM(ABS(sender.Points)) > 30000
         THEN 'SUPERA_LIMITE_COLABORADOR'
         WHEN SUM(ABS(sender.Points)) > 8000
         THEN 'SUPERA_LIMITE_CLIENTE (verificar perfil)'
         ELSE 'OK'
    END                                           AS Evaluacion
FROM [SmartFran.Solution.SmartLoyalty].sml.PointsTransference pt
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog sender
    ON sender.Id = pt.IdCustomerPointsLogSender
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person p
    ON p.Id = sender.CustomerId
WHERE pt.Date >= '2026-06-04T04:00:00+00:00'
  AND pt.Date <  '2026-06-04T12:00:00+00:00'
GROUP BY sender.CustomerId, p.FirstName, p.LastName, p.UidCode, p.UidSerie
HAVING SUM(ABS(sender.Points)) > 8000
ORDER BY Puntos_Enviados_Ventana DESC;

-- Q6: Saldo actual — receptores con fan-in (hub detection)
SELECT
    cpl.CustomerId                                AS Receptor_Id,
    p.FirstName + ' ' + p.LastName                AS Nombre,
    p.UidCode                                      AS TipoDoc,
    p.UidSerie                                     AS Documento,
    cpl.Points                                     AS Saldo_Actual,
    cpl.LastLogDate                                AS Ultima_Actividad_GMT
FROM [SmartFran.Solution.SmartLoyalty].smlst.CustomerPointsLog cpl
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person p
    ON p.Id = cpl.CustomerId
WHERE cpl.CustomerId IN (
    SELECT receiver.CustomerId
    FROM [SmartFran.Solution.SmartLoyalty].sml.PointsTransference pt
    JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog sender
        ON sender.Id = pt.IdCustomerPointsLogSender
    JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog receiver
        ON receiver.Id = pt.IdCustomerPointsLogReceiver
    WHERE pt.Date >= '2026-06-04T04:00:00+00:00'
      AND pt.Date <  '2026-06-04T12:00:00+00:00'
    GROUP BY receiver.CustomerId
    HAVING COUNT(DISTINCT sender.CustomerId) > 1
)
ORDER BY Saldo_Actual DESC;

-- Q7: Canal de origen — señal de automatización si un solo canal domina
SELECT
    pt.SourceChannel,
    COUNT(*)                AS Transferencias,
    SUM(ABS(sender.Points)) AS Puntos_Total
FROM [SmartFran.Solution.SmartLoyalty].sml.PointsTransference pt
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog sender
    ON sender.Id = pt.IdCustomerPointsLogSender
WHERE pt.Date >= '2026-06-04T04:00:00+00:00'
  AND pt.Date <  '2026-06-04T12:00:00+00:00'
GROUP BY pt.SourceChannel
ORDER BY Transferencias DESC;

-- Q8: Patrón de registro — clustering de cuentas emisoras por fecha y canal
SELECT
    c.RegistrationChannel,
    c.RegisterById,
    CAST(c.CreatedDate AS DATE)        AS Fecha_Registro,
    COUNT(DISTINCT sender.CustomerId)  AS Cuentas_Emisoras
FROM [SmartFran.Solution.SmartLoyalty].sml.PointsTransference pt
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog sender
    ON sender.Id = pt.IdCustomerPointsLogSender
JOIN [SmartFran.Solution.SmartLoyalty].sml.Customer c
    ON c.Id = sender.CustomerId
WHERE pt.Date >= '2026-06-04T04:00:00+00:00'
  AND pt.Date <  '2026-06-04T12:00:00+00:00'
GROUP BY c.RegistrationChannel, c.RegisterById, CAST(c.CreatedDate AS DATE)
ORDER BY Cuentas_Emisoras DESC;

-- ============================================================
-- CONSULTAS DE SEGUIMIENTO (post-análisis Q1–Q8)
-- ============================================================

-- FQ1: Saldo actual de Dimon Briz y Simon Brizuela 46845174 (cuenta alimentadora)
SELECT
    cpl.CustomerId,
    p.FirstName + ' ' + p.LastName AS Nombre,
    p.UidSerie                      AS Documento,
    cpl.Points                      AS Saldo_Actual,
    cpl.LastLogDate                 AS Ultima_Actividad_GMT
FROM [SmartFran.Solution.SmartLoyalty].smlst.CustomerPointsLog cpl
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person p
    ON p.Id = cpl.CustomerId
WHERE cpl.CustomerId IN (
    'E6CC99E8-368F-C66B-00A1-08DEB39859AC',  -- Dimon Briz 123456
    '95333272-6EBD-C5CC-0BAE-08DE555FC9DA'   -- Simon Brizuela 46845174 (alimentador)
);

-- FQ2: Historial completo de Dimon Briz — origen de puntos previos al esquema
SELECT
    FORMAT(DATEADD(HOUR, -3, LogDate), 'yyyy-MM-dd HH:mm:ss') AS Fecha_UTC3,
    EventTypeCode,
    Points,
    SaleId,
    ManualAssignPointsId
FROM [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog
WHERE CustomerId = 'E6CC99E8-368F-C66B-00A1-08DEB39859AC'
ORDER BY LogDate;

-- FQ3: Verificación de perfil colaborador — Mamanis y Cordero
-- HumanResourcesPoints recurrentes confirman empleado Grido
SELECT
    cpl.CustomerId,
    p.FirstName + ' ' + p.LastName AS Nombre,
    p.UidSerie                      AS Documento,
    COUNT(*)                        AS Asignaciones_HR,
    SUM(cpl.Points)                 AS Puntos_HR_Total,
    MIN(FORMAT(DATEADD(HOUR, -3, cpl.LogDate), 'yyyy-MM-dd')) AS Primera,
    MAX(FORMAT(DATEADD(HOUR, -3, cpl.LogDate), 'yyyy-MM-dd')) AS Ultima
FROM [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog cpl
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person p
    ON p.Id = cpl.CustomerId
WHERE cpl.CustomerId IN (
    'BF87EC69-C6F3-CDE1-6027-08D87DD1E54E',  -- María Celeste Mamanis
    '67F9F6D2-1EAC-CD0D-F0F6-08D212DCB98D'   -- Sergio Emanuel Cordero
)
  AND cpl.EventTypeCode = 'HumanResourcesPoints'
GROUP BY cpl.CustomerId, p.FirstName, p.LastName, p.UidSerie;

-- ============================================================
-- Investigación: Exploit Asignaciones Manuales GSFERNANDEZ
-- Fecha: 2026-06-02
-- Ventana inicial reportada: 06:00–08:00 UTC-3
-- ============================================================

-- PASO 0: Conversión de zona horaria
-- Ventana reportada 06:00–08:00 UTC-3 = 09:00–11:00 GMT
-- Nota: servidor corre en GMT (UTC+0)

-- ============================================================
-- SECCIÓN A — Investigación de ventana reportada
-- ============================================================

-- Q1: Desglose EventTypeCode — ventana 06:00–08:00 UTC-3
SELECT
    EventTypeCode,
    COUNT(*)        AS Eventos,
    SUM(Points)     AS Puntos
FROM [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog
WHERE
    LogDate >= '2026-06-02T09:00:00.000'
    AND LogDate <  '2026-06-02T11:00:00.000'
    AND EventTypeCode NOT IN ('PointsByTransferSent', 'PointsByTransferReceived')
GROUP BY EventTypeCode
ORDER BY Puntos DESC;

-- Q2: Baseline — misma ventana horaria en los 7 días previos
SELECT
    CONVERT(DATE, DATEADD(HOUR, -3, LogDate)) AS Fecha_UTC3,
    EventTypeCode,
    COUNT(*)        AS Eventos,
    SUM(Points)     AS Puntos
FROM [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog
WHERE
    EventTypeCode NOT IN ('PointsByTransferSent', 'PointsByTransferReceived')
    AND (
           (LogDate >= '2026-05-26T09:00:00.000' AND LogDate < '2026-05-26T11:00:00.000')
        OR (LogDate >= '2026-05-27T09:00:00.000' AND LogDate < '2026-05-27T11:00:00.000')
        OR (LogDate >= '2026-05-28T09:00:00.000' AND LogDate < '2026-05-28T11:00:00.000')
        OR (LogDate >= '2026-05-29T09:00:00.000' AND LogDate < '2026-05-29T11:00:00.000')
        OR (LogDate >= '2026-05-30T09:00:00.000' AND LogDate < '2026-05-30T11:00:00.000')
        OR (LogDate >= '2026-05-31T09:00:00.000' AND LogDate < '2026-05-31T11:00:00.000')
        OR (LogDate >= '2026-06-01T09:00:00.000' AND LogDate < '2026-06-01T11:00:00.000')
    )
GROUP BY
    CONVERT(DATE, DATEADD(HOUR, -3, LogDate)),
    EventTypeCode
ORDER BY Fecha_UTC3, EventTypeCode;

-- Q3: Cadencia por minuto — ventana 06:00–08:00 UTC-3
SELECT
    DATEADD(MINUTE, DATEDIFF(MINUTE, 0, DATEADD(HOUR, -3, LogDate)), 0) AS Minuto_UTC3,
    EventTypeCode,
    COUNT(*)        AS Eventos,
    SUM(Points)     AS Puntos
FROM [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog
WHERE
    LogDate >= '2026-06-02T09:00:00.000'
    AND LogDate <  '2026-06-02T11:00:00.000'
    AND EventTypeCode NOT IN ('PointsByTransferSent', 'PointsByTransferReceived')
GROUP BY
    DATEADD(MINUTE, DATEDIFF(MINUTE, 0, DATEADD(HOUR, -3, LogDate)), 0),
    EventTypeCode
ORDER BY Minuto_UTC3;

-- Q4: Top receptores — ventana 06:00–08:00 UTC-3
SELECT TOP 50
    cpl.CustomerId,
    p.FirstName + ' ' + p.LastName AS Cliente,
    p.UidCode                       AS TipoDoc,
    p.UidSerie                      AS Documento,
    cpl.EventTypeCode,
    COUNT(*)                        AS Transacciones,
    SUM(cpl.Points)                 AS Puntos
FROM [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog cpl
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person            p   ON p.Id = cpl.CustomerId
WHERE
    cpl.LogDate >= '2026-06-02T09:00:00.000'
    AND cpl.LogDate <  '2026-06-02T11:00:00.000'
    AND cpl.EventTypeCode NOT IN ('PointsByTransferSent', 'PointsByTransferReceived')
GROUP BY cpl.CustomerId, p.FirstName, p.LastName, p.UidCode, p.UidSerie, cpl.EventTypeCode
ORDER BY Puntos DESC;

-- Q5: Análisis de fuente — PromotionId / ArticleId / SaleId / ManualAssignPointsId
SELECT
    PromotionId,
    ArticleId,
    SaleId,
    ManualAssignPointsId,
    EventTypeCode,
    COUNT(*)        AS Eventos,
    SUM(Points)     AS Puntos
FROM [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog
WHERE
    LogDate >= '2026-06-02T09:00:00.000'
    AND LogDate <  '2026-06-02T11:00:00.000'
    AND EventTypeCode NOT IN ('PointsByTransferSent', 'PointsByTransferReceived')
GROUP BY PromotionId, ArticleId, SaleId, ManualAssignPointsId, EventTypeCode
ORDER BY Puntos DESC;

-- Q6: Asignaciones manuales en ventana (señal insider)
SELECT
    cpl.Id,
    cpl.CustomerId,
    p.FirstName + ' ' + p.LastName AS Cliente,
    p.UidCode                       AS TipoDoc,
    p.UidSerie                      AS Documento,
    cpl.LogDate,
    cpl.Points,
    cpl.EventTypeCode,
    cpl.ManualAssignPointsId,
    cpl.Note
FROM [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog cpl
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person            p   ON p.Id = cpl.CustomerId
WHERE
    cpl.LogDate >= '2026-06-02T09:00:00.000'
    AND cpl.LogDate <  '2026-06-02T11:00:00.000'
    AND cpl.ManualAssignPointsId IS NOT NULL
ORDER BY cpl.LogDate;

-- Q7: Control de límite diario — día completo 2026-06-02 UTC-3
SELECT
    cpl.CustomerId,
    p.FirstName + ' ' + p.LastName AS Cliente,
    p.UidCode                       AS TipoDoc,
    p.UidSerie                      AS Documento,
    COUNT(*)                        AS Transacciones,
    SUM(cpl.Points)                 AS Puntos_Dia
FROM [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog cpl
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person            p   ON p.Id = cpl.CustomerId
WHERE
    cpl.LogDate >= '2026-06-02T03:00:00.000'
    AND cpl.LogDate <  '2026-06-03T03:00:00.000'
    AND cpl.EventTypeCode NOT IN ('PointsByTransferSent', 'PointsByTransferReceived')
    AND cpl.Points > 0
GROUP BY cpl.CustomerId, p.FirstName, p.LastName, p.UidCode, p.UidSerie
HAVING SUM(cpl.Points) > 3000
ORDER BY Puntos_Dia DESC;

-- Q8: Historial semanal/mensual — top receptores en ventana
WITH Earners AS (
    SELECT CustomerId
    FROM [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog
    WHERE
        LogDate >= '2026-06-02T09:00:00.000'
        AND LogDate <  '2026-06-02T11:00:00.000'
        AND EventTypeCode NOT IN ('PointsByTransferSent', 'PointsByTransferReceived')
        AND Points > 0
    GROUP BY CustomerId
    HAVING SUM(Points) >= 500
)
SELECT
    cpl.CustomerId,
    p.FirstName + ' ' + p.LastName AS Cliente,
    p.UidCode   AS TipoDoc,
    p.UidSerie  AS Documento,
    SUM(CASE
            WHEN cpl.LogDate >= '2026-05-26T03:00:00.000'
             AND cpl.LogDate <  '2026-06-03T03:00:00.000'
             AND cpl.EventTypeCode NOT IN ('PointsByTransferSent', 'PointsByTransferReceived')
             AND cpl.Points > 0
            THEN cpl.Points ELSE 0
        END) AS Puntos_Semana,
    SUM(CASE
            WHEN cpl.LogDate >= '2026-06-01T03:00:00.000'
             AND cpl.LogDate <  '2026-06-03T03:00:00.000'
             AND cpl.EventTypeCode NOT IN ('PointsByTransferSent', 'PointsByTransferReceived')
             AND cpl.Points > 0
            THEN cpl.Points ELSE 0
        END) AS Puntos_Mes
FROM [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog cpl
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person            p   ON p.Id = cpl.CustomerId
WHERE cpl.CustomerId IN (SELECT CustomerId FROM Earners)
GROUP BY cpl.CustomerId, p.FirstName, p.LastName, p.UidCode, p.UidSerie
ORDER BY Puntos_Semana DESC;

-- ============================================================
-- SECCIÓN B — Identificación de asignaciones manuales anómalas
-- ============================================================

-- Q9: Detalle transaccional de cuentas flaggeadas en Q7
SELECT
    cpl.Id,
    cpl.CustomerId,
    p.FirstName + ' ' + p.LastName       AS Cliente,
    p.UidCode                             AS TipoDoc,
    p.UidSerie                            AS Documento,
    cpl.LogDate,
    DATEADD(HOUR, -3, cpl.LogDate)        AS LogDate_UTC3,
    cpl.Points,
    cpl.EventTypeCode,
    cpl.SaleId,
    cpl.PromotionId,
    cpl.ArticleId,
    cpl.ManualAssignPointsId,
    cpl.Note
FROM [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog  cpl
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person             p   ON p.Id = cpl.CustomerId
WHERE
    cpl.CustomerId IN (
        'AEEBEE7F-FBCA-C18F-12C7-08D59A9863AA',  -- Facundo Martin Gabriele
        '03BD397B-1A6A-C4BD-6F7E-08D75A58CC66'   -- Gabriela Lubrano
    )
    AND cpl.LogDate >= '2026-06-02T03:00:00.000'
    AND cpl.LogDate <  '2026-06-03T03:00:00.000'
ORDER BY cpl.LogDate;

-- Q10: Perfil de cuenta — datos de registro y saldo actual
SELECT
    p.Id,
    p.FirstName + ' ' + p.LastName       AS Cliente,
    p.UidCode   AS TipoDoc,
    p.UidSerie  AS Documento,
    p.Email,
    p.BirthDate,
    p.UpdateDate,
    c.CreatedDate,
    c.FormDate,
    c.RegistrationChannel,
    c.RegisterById,
    c.EnrolledId,
    c.Country_Id,
    bal.Points                            AS Saldo_Actual,
    bal.LastLogDate
FROM [SmartFran.Solution.SmartLoyalty].sml.Person               p
JOIN [SmartFran.Solution.SmartLoyalty].sml.Customer             c   ON c.Id          = p.Id
JOIN [SmartFran.Solution.SmartLoyalty].smlst.CustomerPointsLog  bal ON bal.CustomerId = p.Id
WHERE p.Id IN (
    'AEEBEE7F-FBCA-C18F-12C7-08D59A9863AA',
    '03BD397B-1A6A-C4BD-6F7E-08D75A58CC66'
);

-- Q11: Registros de asignaciones manuales — IDs específicos
SELECT *
FROM [SmartFran.Solution.SmartLoyalty].sml.ManualAssignPoints
WHERE Id IN (9411, 9412);

-- Tablas auxiliares disponibles (para auditoría adicional):
-- SELECT TABLE_SCHEMA, TABLE_NAME
-- FROM [SmartFran.Solution.SmartLoyalty].INFORMATION_SCHEMA.TABLES
-- WHERE TABLE_NAME LIKE '%Manual%' OR TABLE_NAME LIKE '%Assign%' OR TABLE_NAME LIKE '%Compensat%';

-- Q12: Historial completo de asignaciones GSFERNANDEZ
SELECT
    map.Id,
    map.RegisterByUser,
    map.AssignmentConcept,
    map.Points,
    map.Status,
    map.AssignDate,
    DATEADD(HOUR, -3, map.AssignDate)    AS AssignDate_UTC3,
    map.ErrorLog,
    map.Catalog_Id,
    p.FirstName + ' ' + p.LastName       AS Cliente,
    p.UidCode                             AS TipoDoc,
    p.UidSerie                            AS Documento
FROM [SmartFran.Solution.SmartLoyalty].sml.ManualAssignPoints      map
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog       cpl ON cpl.ManualAssignPointsId = map.Id
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person                  p   ON p.Id = cpl.CustomerId
WHERE map.RegisterByUser = 'GSFERNANDEZ'
ORDER BY map.AssignDate DESC;

-- Q13: Actividad post-asignación en cuentas comprometidas (¿se canjearon los puntos?)
SELECT
    cpl.Id,
    cpl.CustomerId,
    p.FirstName + ' ' + p.LastName       AS Cliente,
    cpl.LogDate,
    DATEADD(HOUR, -3, cpl.LogDate)        AS LogDate_UTC3,
    cpl.Points,
    cpl.EventTypeCode,
    cpl.SaleId,
    cpl.ManualAssignPointsId
FROM [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog  cpl
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person             p   ON p.Id = cpl.CustomerId
WHERE
    cpl.CustomerId IN (
        'AEEBEE7F-FBCA-C18F-12C7-08D59A9863AA',
        '03BD397B-1A6A-C4BD-6F7E-08D75A58CC66'
    )
ORDER BY cpl.LogDate DESC;

-- Q14: Control día 2026-06-01 — verificar Oscar Stuht
SELECT
    cpl.CustomerId,
    p.FirstName + ' ' + p.LastName AS Cliente,
    p.UidCode   AS TipoDoc,
    p.UidSerie  AS Documento,
    COUNT(*)    AS Transacciones,
    SUM(cpl.Points) AS Puntos_Dia
FROM [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog cpl
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person            p   ON p.Id = cpl.CustomerId
WHERE
    cpl.CustomerId = '2D0F3972-7907-C101-0EFE-08DAABEF4518'
    AND cpl.LogDate >= '2026-06-01T03:00:00.000'
    AND cpl.LogDate <  '2026-06-02T03:00:00.000'
    AND cpl.Points > 0
GROUP BY cpl.CustomerId, p.FirstName, p.LastName, p.UidCode, p.UidSerie;

-- Saldo actual Oscar Stuht
SELECT p.Id, p.FirstName + ' ' + p.LastName AS Cliente, p.UidSerie, bal.Points AS Saldo_Actual
FROM [SmartFran.Solution.SmartLoyalty].sml.Person             p
JOIN [SmartFran.Solution.SmartLoyalty].smlst.CustomerPointsLog bal ON bal.CustomerId = p.Id
WHERE p.UidSerie = '40152484' AND p.UidCode IN ('Dni', 'DNI');

-- ============================================================
-- SECCIÓN C — Cuantificación del exploit histórico
-- ============================================================

-- Q_E1: Volumen total por concepto — todos los tipos
SELECT
    AssignmentConcept,
    COUNT(*)                                        AS Total_Asignaciones,
    SUM(Points)                                     AS Puntos_Total,
    AVG(Points)                                     AS Promedio,
    MAX(Points)                                     AS Maximo,
    CONVERT(DATE, DATEADD(HOUR, -3, MIN(AssignDate))) AS Primera_UTC3,
    CONVERT(DATE, DATEADD(HOUR, -3, MAX(AssignDate))) AS Ultima_UTC3
FROM [SmartFran.Solution.SmartLoyalty].sml.ManualAssignPoints
WHERE RegisterByUser = 'GSFERNANDEZ'
  AND Status        = 'Approved'
GROUP BY AssignmentConcept
ORDER BY Puntos_Total DESC;

-- Q_E2: Grants que superan el límite diario (> 3.000 pts) en un solo movimiento
SELECT
    COUNT(*)               AS Asignaciones_Excedentes,
    SUM(Points)            AS Puntos_Total_Brutos,
    SUM(Points - 3000)     AS Exceso_Sobre_Limite_Diario,
    MAX(Points)            AS Mayor_Grant,
    COUNT(CASE WHEN Points > 10000 THEN 1 END) AS Sobre_Limite_Mensual
FROM [SmartFran.Solution.SmartLoyalty].sml.ManualAssignPoints
WHERE RegisterByUser      = 'GSFERNANDEZ'
  AND AssignmentConcept   = 'CompensationalPoints'
  AND Status              = 'Approved'
  AND Points              > 3000;

-- Q_E3: Top 20 beneficiarios históricos por puntos totales recibidos
SELECT TOP 20
    p.FirstName + ' ' + p.LastName               AS Cliente,
    p.UidCode                                      AS TipoDoc,
    p.UidSerie                                     AS Documento,
    COUNT(*)                                       AS Asignaciones,
    SUM(map.Points)                                AS Puntos_Total,
    MAX(map.Points)                                AS Mayor_Grant,
    CONVERT(DATE, DATEADD(HOUR, -3, MIN(map.AssignDate))) AS Primera_UTC3,
    CONVERT(DATE, DATEADD(HOUR, -3, MAX(map.AssignDate))) AS Ultima_UTC3
FROM [SmartFran.Solution.SmartLoyalty].sml.ManualAssignPoints      map
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog       cpl ON cpl.ManualAssignPointsId = map.Id
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person                  p   ON p.Id = cpl.CustomerId
WHERE map.RegisterByUser    = 'GSFERNANDEZ'
  AND map.AssignmentConcept = 'CompensationalPoints'
  AND map.Status            = 'Approved'
GROUP BY p.FirstName, p.LastName, p.UidCode, p.UidSerie
ORDER BY Puntos_Total DESC;

-- Q_E4: Tendencia mensual — volumen, breaches por límite diario y mensual
SELECT
    FORMAT(DATEADD(HOUR, -3, AssignDate), 'yyyy-MM')    AS Mes_UTC3,
    COUNT(*)                                             AS Asignaciones,
    SUM(Points)                                          AS Puntos_Total,
    COUNT(CASE WHEN Points > 3000  THEN 1 END)           AS Sobre_Limite_Diario,
    COUNT(CASE WHEN Points > 10000 THEN 1 END)           AS Sobre_Limite_Mensual,
    MAX(Points)                                          AS Mayor_Grant
FROM [SmartFran.Solution.SmartLoyalty].sml.ManualAssignPoints
WHERE RegisterByUser    = 'GSFERNANDEZ'
  AND AssignmentConcept = 'CompensationalPoints'
  AND Status            = 'Approved'
GROUP BY FORMAT(DATEADD(HOUR, -3, AssignDate), 'yyyy-MM')
ORDER BY Mes_UTC3;

-- Q_E5: Combinaciones cliente-mes con > 10.000 pts recibidos en un mes calendario
WITH MonthlyTotals AS (
    SELECT
        cpl.CustomerId,
        FORMAT(DATEADD(HOUR, -3, map.AssignDate), 'yyyy-MM') AS Mes_UTC3,
        SUM(map.Points)  AS Puntos_Mes,
        COUNT(*)         AS Asignaciones_Mes
    FROM [SmartFran.Solution.SmartLoyalty].sml.ManualAssignPoints      map
    JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog       cpl ON cpl.ManualAssignPointsId = map.Id
    WHERE map.RegisterByUser    = 'GSFERNANDEZ'
      AND map.AssignmentConcept = 'CompensationalPoints'
      AND map.Status            = 'Approved'
    GROUP BY cpl.CustomerId,
             FORMAT(DATEADD(HOUR, -3, map.AssignDate), 'yyyy-MM')
)
SELECT
    p.FirstName + ' ' + p.LastName AS Cliente,
    p.UidCode                       AS TipoDoc,
    p.UidSerie                      AS Documento,
    mt.Mes_UTC3,
    mt.Asignaciones_Mes,
    mt.Puntos_Mes,
    mt.Puntos_Mes - 10000           AS Exceso_Mensual
FROM MonthlyTotals mt
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person p ON p.Id = mt.CustomerId
WHERE mt.Puntos_Mes > 10000
ORDER BY mt.Puntos_Mes DESC;

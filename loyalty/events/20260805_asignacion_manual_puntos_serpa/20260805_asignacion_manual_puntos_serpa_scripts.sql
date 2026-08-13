-- ============================================================
-- Asignación manual de puntos — Claudia Serpa (DNI 16762109)
-- Solicitante: Jacky | Motivo: Puntos por Premio (PrizePoints)
-- Fecha: 2026-08-05
-- ============================================================

-- Q1: Verificación previa — confirmar que el CustomerId corresponde al DNI informado
SELECT p.Id AS CustomerId, p.UidCode AS TipoDoc, p.UidSerie AS Documento,
       p.FirstName + ' ' + p.LastName AS Cliente
FROM [SmartFran.Solution.SmartLoyalty].sml.Person p
WHERE p.Id = '561BEF0E-3CE9-C29C-36D2-08DDF9361945';

-- OUTPUT (2026-08-05):
-- CustomerId                            | TipoDoc | Documento | Cliente
-- 561BEF0E-3CE9-C29C-36D2-08DDF9361945  | Dni     | 16762109  | Claudia Serpa

-- Q2: Asignación manual de puntos — INSERT en dos pasos dentro de una transacción explícita
BEGIN TRANSACTION;

DECLARE @CustomerId       UNIQUEIDENTIFIER = '561BEF0E-3CE9-C29C-36D2-08DDF9361945';
DECLARE @Points           INT              = 63580;
DECLARE @RegisterByUser   VARCHAR(50)      = 'dantep';
DECLARE @Now              DATETIMEOFFSET   = SYSDATETIMEOFFSET();
DECLARE @ManualAssignId   INT;

INSERT INTO [SmartFran.Solution.SmartLoyalty].sml.ManualAssignPoints
    (RegisterByUser, AssignmentConcept, Points, Status, AssignDate, ErrorLog, Catalog_Id)
VALUES
    (@RegisterByUser, 'PrizePoints', @Points, 'Approved', @Now, NULL, NULL);

SET @ManualAssignId = SCOPE_IDENTITY();

INSERT INTO [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog
    (LogDate, Note, Points, EventTypeCode, CustomerId, ManualAssignPointsId)
VALUES
    (@Now, 'Puntos por Premio', @Points, 'PrizePoints', @CustomerId, @ManualAssignId);

-- Nota: la primera ejecución quedó con @RegisterByUser sin reemplazar (placeholder
-- '<usuario_que_ejecuta>'). Se detectó antes del COMMIT vía Q3 (NOLOCK) y se volvió
-- a ejecutar Q2 con el valor correcto ('dantep') antes de confirmar.

COMMIT TRANSACTION;

-- Q3: Confirmación de estado — NOLOCK para no bloquear si la transacción seguía abierta
SELECT
    map.Id                      AS ManualAssignPointsId,
    map.RegisterByUser,
    map.AssignmentConcept,
    map.Points,
    map.Status,
    map.AssignDate,
    cpl.Id                      AS CustomerPointsLogId,
    cpl.CustomerId,
    cpl.Points                  AS PuntosLog,
    cpl.EventTypeCode,
    cpl.Note,
    cpl.LogDate
FROM [SmartFran.Solution.SmartLoyalty].sml.ManualAssignPoints map WITH (NOLOCK)
JOIN [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog  cpl WITH (NOLOCK)
    ON cpl.ManualAssignPointsId = map.Id
WHERE cpl.CustomerId = '561BEF0E-3CE9-C29C-36D2-08DDF9361945'
  AND cpl.EventTypeCode = 'PrizePoints'
  AND cpl.Points = 63580
ORDER BY cpl.LogDate DESC;

-- OUTPUT (2026-08-05, post-COMMIT):
-- ManualAssignPointsId | RegisterByUser | AssignmentConcept | Points | Status   | AssignDate                      | CustomerPointsLogId | CustomerId                           | PuntosLog | EventTypeCode | Note              | LogDate
-- 9835                 | dantep         | PrizePoints       | 63580  | Approved | 2026-08-05 19:32:07.1928919+00  | 390056929            | 561BEF0E-3CE9-C29C-36D2-08DDF9361945 | 63580     | PrizePoints   | Puntos por Premio | 2026-08-05 19:32:07.1928919+00

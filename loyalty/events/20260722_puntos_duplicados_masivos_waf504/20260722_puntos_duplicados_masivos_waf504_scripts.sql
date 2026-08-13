-- Eventos — 20260722_puntos_duplicados_masivos_waf504
-- Q1-Q10 son de solo lectura (SELECT), ejecutadas por el usuario contra SmartFran.Solution.SmartLoyalty.
-- Q11 es DML (INSERT) — reversión del incidente WAF-504. Q12 es DML (CREATE TABLE + BULK INSERT +
-- INSERT) — reasignación manual de la misma campaña ("corrida desde cero"), hecha a mano para no
-- repetir la falta de idempotencia de MassivePointsAssignment; ver nota antes de Q12. Ambas
-- generadas tras actualización de loyalty/CLAUDE.md (2026-07-22) que permite
-- DML/DDL cuando se solicita explícitamente.

-- Q1: Permisos efectivos del login sobre las tablas relevantes (Sml.ManualAssignPoints denegado, resto concedido)
SELECT * FROM fn_my_permissions('Sml.ManualAssignPoints', 'OBJECT');
SELECT * FROM fn_my_permissions('Sml.CustomerPointsLog', 'OBJECT');
SELECT * FROM fn_my_permissions('Sml.Person', 'OBJECT');
SELECT * FROM fn_my_permissions('Sml.Customer', 'OBJECT');

-- Q2: Descubrimiento de lotes (ManualAssignPointsId) de hoy, agrupado por Note
SELECT ManualAssignPointsId, EventTypeCode, Note, COUNT(*) AS Rows, SUM(Points) AS TotalPoints,
       MIN(LogDate) AS FirstLog, MAX(LogDate) AS LastLog
FROM Sml.CustomerPointsLog
WHERE LogDate >= '2026-07-22' AND LogDate < '2026-07-23'
  AND ManualAssignPointsId IS NOT NULL
GROUP BY ManualAssignPointsId, EventTypeCode, Note
ORDER BY FirstLog;

-- Q3: Detección de duplicados DENTRO del mismo Note (mismo listado, retry real)
;WITH TodayLog AS (
    SELECT CustomerId, ManualAssignPointsId, Note, Points
    FROM Sml.CustomerPointsLog
    WHERE LogDate >= '2026-07-22' AND LogDate < '2026-07-23'
      AND ManualAssignPointsId IS NOT NULL
      AND EventTypeCode = 'PrizePoints'
),
PerCustomerPerList AS (
    SELECT CustomerId, Note,
           COUNT(DISTINCT ManualAssignPointsId) AS TimesThisListHitThisCustomer,
           SUM(Points) AS PointsFromThisList
    FROM TodayLog
    GROUP BY CustomerId, Note
    HAVING COUNT(DISTINCT ManualAssignPointsId) > 1
)
SELECT Note,
       COUNT(*) AS CustomersDuplicatedWithinThisList,
       SUM(PointsFromThisList) AS TotalPointsGranted,
       SUM(PointsFromThisList - 10000) AS TotalExcessPoints
FROM PerCustomerPerList
GROUP BY Note
ORDER BY Note;

-- Q4: Solapamiento CRUZADO entre Notes distintos (confirma que son la misma población objetivo)
;WITH TodayLog AS (
    SELECT CustomerId, Note, ManualAssignPointsId, Points
    FROM Sml.CustomerPointsLog
    WHERE LogDate >= '2026-07-22' AND LogDate < '2026-07-23'
      AND ManualAssignPointsId IS NOT NULL
      AND EventTypeCode = 'PrizePoints'
),
PerCustomer AS (
    SELECT CustomerId,
           COUNT(DISTINCT Note) AS DistinctNotesHit,
           COUNT(DISTINCT ManualAssignPointsId) AS DistinctBatchesHit,
           SUM(Points) AS TotalPoints
    FROM TodayLog
    GROUP BY CustomerId
)
SELECT DistinctNotesHit, COUNT(*) AS CustomerCount, SUM(TotalPoints) AS SumPoints
FROM PerCustomer
GROUP BY DistinctNotesHit
ORDER BY DistinctNotesHit DESC;

-- Q5 (pendiente de ejecutar): detalle de los 20 clientes con DistinctNotesHit = 1 y total no múltiplo limpio de 10000
;WITH TodayLog AS (
    SELECT CustomerId, Note, ManualAssignPointsId, Points
    FROM Sml.CustomerPointsLog
    WHERE LogDate >= '2026-07-22' AND LogDate < '2026-07-23'
      AND ManualAssignPointsId IS NOT NULL
      AND EventTypeCode = 'PrizePoints'
),
PerCustomer AS (
    SELECT CustomerId,
           COUNT(DISTINCT Note) AS DistinctNotesHit,
           COUNT(DISTINCT ManualAssignPointsId) AS DistinctBatchesHit,
           SUM(Points) AS TotalPoints
    FROM TodayLog
    GROUP BY CustomerId
)
SELECT pc.CustomerId, p.UidCode AS DocumentType, p.UidSerie AS DocumentNumber,
       pc.DistinctBatchesHit, pc.TotalPoints
FROM PerCustomer pc
JOIN Sml.Person p ON p.Id = pc.CustomerId
WHERE pc.DistinctNotesHit = 1
ORDER BY pc.TotalPoints DESC;

-- Q6a (solo lectura — sanity check antes de Q6b): confirma sobre datos reales los EventTypeCode
-- de gasto/transferencia post-grant para la población implicada, y que el join a Sml.Customer
-- (para leer DeativatedDate, estado de cuenta) devuelve filas. Los literales de EventTypeCode
-- (DiscountPointsByExchange, DiscountPointsByPromotion, RemovePointsBySaleInvalidation,
-- PointsByTransferSent) vienen del código fuente (EventTypeTable.cs), no de un resultado de
-- query — confirmar contra datos reales antes de usarlos en Q6b.
;WITH GrantedToday AS (
    SELECT DISTINCT CustomerId
    FROM Sml.CustomerPointsLog
    WHERE LogDate >= '2026-07-22' AND LogDate < '2026-07-23'
      AND EventTypeCode = 'PrizePoints'
      AND ManualAssignPointsId IS NOT NULL
)
SELECT cpl.EventTypeCode, COUNT(*) AS Rows, COUNT(DISTINCT cpl.CustomerId) AS DistinctCustomers, SUM(cpl.Points) AS TotalPoints
FROM Sml.CustomerPointsLog cpl
JOIN GrantedToday g ON g.CustomerId = cpl.CustomerId
WHERE cpl.LogDate >= '2026-07-22' AND cpl.LogDate < '2026-07-23'
  AND cpl.EventTypeCode <> 'PrizePoints'
GROUP BY cpl.EventTypeCode
ORDER BY TotalPoints;

;WITH GrantedToday AS (
    SELECT DISTINCT CustomerId
    FROM Sml.CustomerPointsLog
    WHERE LogDate >= '2026-07-22' AND LogDate < '2026-07-23'
      AND EventTypeCode = 'PrizePoints'
      AND ManualAssignPointsId IS NOT NULL
)
SELECT TOP 20 c.Id, c.DeativatedDate
FROM Sml.Customer c
JOIN GrantedToday g ON g.CustomerId = c.Id;

-- Q6b (solo lectura): clasificación gastado/transferido/activo/retenido de los puntos otorgados
-- hoy, para la población completa de reversión (Query 10, cuatro listas). No es prerrequisito
-- de la reversión (ésta es total, no sólo el exceso) — es antecedente para dimensionar cuánto
-- del monto a revertir ya fue gastado/transferido antes de que se ejecute el ajuste.
-- EventTypeCode de gasto: DiscountPointsByExchange, DiscountPointsByPromotion,
-- RemovePointsBySaleInvalidation. De transferencia saliente: PointsByTransferSent.
-- Cuenta activa: Sml.Customer.DeativatedDate IS NULL (fuente: CustomerService.cs,
-- SpecCustomerActivated). Ejecutar sólo después de revisar el resultado de Q6a.
;WITH GrantedToday AS (
    SELECT CustomerId, SUM(Points) AS PointsGrantedToday
    FROM Sml.CustomerPointsLog
    WHERE LogDate >= '2026-07-22' AND LogDate < '2026-07-23'
      AND EventTypeCode = 'PrizePoints'
      AND ManualAssignPointsId IS NOT NULL
    GROUP BY CustomerId
),
MovementsSinceGrant AS (
    SELECT cpl.CustomerId,
           SUM(CASE WHEN cpl.EventTypeCode IN ('DiscountPointsByExchange','DiscountPointsByPromotion','RemovePointsBySaleInvalidation') THEN -cpl.Points ELSE 0 END) AS PointsSpentToday,
           SUM(CASE WHEN cpl.EventTypeCode = 'PointsByTransferSent' THEN -cpl.Points ELSE 0 END) AS PointsTransferredOutToday
    FROM Sml.CustomerPointsLog cpl
    JOIN GrantedToday g ON g.CustomerId = cpl.CustomerId
    WHERE cpl.LogDate >= '2026-07-22' AND cpl.LogDate < '2026-07-23'
      AND cpl.EventTypeCode <> 'PrizePoints'
    GROUP BY cpl.CustomerId
),
CurrentBalance AS (
    SELECT cpl.CustomerId, SUM(cpl.Points) AS CurrentBalance
    FROM Sml.CustomerPointsLog cpl
    JOIN GrantedToday g ON g.CustomerId = cpl.CustomerId
    GROUP BY cpl.CustomerId
)
SELECT
    g.CustomerId,
    p.UidCode  AS DocumentType,
    p.UidSerie AS DocumentNumber,
    g.PointsGrantedToday,
    ISNULL(m.PointsSpentToday, 0)          AS PointsSpentToday,
    ISNULL(m.PointsTransferredOutToday, 0) AS PointsTransferredOutToday,
    cb.CurrentBalance,
    CASE WHEN c.DeativatedDate IS NOT NULL THEN 'Retenido' ELSE 'Activo' END AS AccountStatus
FROM GrantedToday g
JOIN Sml.Person p ON p.Id = g.CustomerId
JOIN Sml.Customer c ON c.Id = g.CustomerId
LEFT JOIN MovementsSinceGrant m ON m.CustomerId = g.CustomerId
LEFT JOIN CurrentBalance cb ON cb.CustomerId = g.CustomerId
ORDER BY g.PointsGrantedToday DESC;

-- Q6c (solo lectura): igual que Q6b pero agregado por AccountStatus, para no tener que
-- transcribir manualmente miles de filas. Es la vista que efectivamente se necesita para
-- dimensionar cuánto del monto a revertir ya fue gastado/transferido.
;WITH GrantedToday AS (
    SELECT CustomerId, SUM(Points) AS PointsGrantedToday
    FROM Sml.CustomerPointsLog
    WHERE LogDate >= '2026-07-22' AND LogDate < '2026-07-23'
      AND EventTypeCode = 'PrizePoints'
      AND ManualAssignPointsId IS NOT NULL
    GROUP BY CustomerId
),
MovementsSinceGrant AS (
    SELECT cpl.CustomerId,
           SUM(CASE WHEN cpl.EventTypeCode IN ('DiscountPointsByExchange','DiscountPointsByPromotion','RemovePointsBySaleInvalidation') THEN -cpl.Points ELSE 0 END) AS PointsSpentToday,
           SUM(CASE WHEN cpl.EventTypeCode = 'PointsByTransferSent' THEN -cpl.Points ELSE 0 END) AS PointsTransferredOutToday
    FROM Sml.CustomerPointsLog cpl
    JOIN GrantedToday g ON g.CustomerId = cpl.CustomerId
    WHERE cpl.LogDate >= '2026-07-22' AND cpl.LogDate < '2026-07-23'
      AND cpl.EventTypeCode <> 'PrizePoints'
    GROUP BY cpl.CustomerId
),
Classified AS (
    SELECT
        g.CustomerId,
        g.PointsGrantedToday,
        ISNULL(m.PointsSpentToday, 0)          AS PointsSpentToday,
        ISNULL(m.PointsTransferredOutToday, 0) AS PointsTransferredOutToday,
        CASE WHEN c.DeativatedDate IS NOT NULL THEN 'Retenido' ELSE 'Activo' END AS AccountStatus
    FROM GrantedToday g
    JOIN Sml.Customer c ON c.Id = g.CustomerId
    LEFT JOIN MovementsSinceGrant m ON m.CustomerId = g.CustomerId
)
SELECT
    AccountStatus,
    COUNT(*)                                                  AS Customers,
    SUM(PointsGrantedToday)                                   AS TotalGranted,
    SUM(PointsSpentToday)                                     AS TotalSpentToday,
    SUM(PointsTransferredOutToday)                            AS TotalTransferredOutToday,
    SUM(CASE WHEN PointsSpentToday > 0 THEN 1 ELSE 0 END)          AS CustomersWithSpend,
    SUM(CASE WHEN PointsTransferredOutToday > 0 THEN 1 ELSE 0 END) AS CustomersWithTransfer
FROM Classified
GROUP BY AccountStatus;

-- Q7: Listado completo de clientes implicados (exceso > 0), con detalle para exportar y usar en la reversión
;WITH TodayLog AS (
    SELECT CustomerId, Note, ManualAssignPointsId, Points
    FROM Sml.CustomerPointsLog
    WHERE LogDate >= '2026-07-22' AND LogDate < '2026-07-23'
      AND ManualAssignPointsId IS NOT NULL
      AND EventTypeCode = 'PrizePoints'
),
PerCustomer AS (
    SELECT CustomerId,
           COUNT(DISTINCT Note) AS DistinctNotesHit,
           COUNT(DISTINCT ManualAssignPointsId) AS DistinctBatchesHit,
           SUM(Points) AS TotalPoints,
           STRING_AGG(CAST(ManualAssignPointsId AS VARCHAR(10)), ',') AS BatchIdsHit
    FROM TodayLog
    GROUP BY CustomerId
)
SELECT pc.CustomerId,
       p.UidCode AS DocumentType,
       p.UidSerie AS DocumentNumber,
       pc.DistinctNotesHit,
       pc.DistinctBatchesHit,
       pc.TotalPoints,
       pc.TotalPoints - 10000 AS ExcessPoints,
       pc.BatchIdsHit
FROM PerCustomer pc
JOIN Sml.Person p ON p.Id = pc.CustomerId
WHERE pc.TotalPoints > 10000
ORDER BY pc.TotalPoints DESC;

-- Q8: Conteo agregado por Note (listado) — clientes distintos, lotes distintos y puntos totales por cada lista de la campaña
SELECT Note,
       COUNT(DISTINCT CustomerId) AS DistinctCustomers,
       COUNT(DISTINCT ManualAssignPointsId) AS DistinctBatches,
       COUNT(*) AS TotalRows,
       SUM(Points) AS TotalPoints
FROM Sml.CustomerPointsLog
WHERE LogDate >= '2026-07-22' AND LogDate < '2026-07-23'
  AND ManualAssignPointsId IS NOT NULL
  AND EventTypeCode = 'PrizePoints'
GROUP BY Note
ORDER BY TotalPoints DESC;

-- Q9: Listado de todos los EventTypeCode distintos presentes en el log de hoy, con conteo y puntos
SELECT EventTypeCode, COUNT(*) AS Rows, SUM(Points) AS TotalPoints
FROM Sml.CustomerPointsLog
WHERE LogDate >= '2026-07-22' AND LogDate < '2026-07-23'
GROUP BY EventTypeCode
ORDER BY TotalPoints DESC;

-- Q10 (solo lectura — especificación de reversión, NO ejecuta ninguna escritura):
-- Reversión TOTAL (no sólo el exceso) de las CUATRO listas de la campaña, incluyendo
-- "Campaña recupero" (decisión ampliada 2026-07-22 — reemplaza el alcance anterior de
-- sólo tres listas). Grido va a volver a correr la campaña completa desde cero, así que
-- se retira también lo que hubiera sido la asignación "legítima" de cada lista.
-- Sin filtro por Note: se revierte todo lo otorgado hoy bajo EventTypeCode = 'PrizePoints'
-- con ManualAssignPointsId asignado (evita hardcodear el literal exacto de "Campaña
-- recupero", que no quedó capturado en ningún resultado de query previo de esta sesión).
-- Una fila = una transacción a revertir (CustomerId + ManualAssignPointsId), tal como
-- fue solicitado. El equipo con permisos de escritura usa esta salida como input directo
-- para generar las transacciones reales de ajuste.
SELECT
    cpl.CustomerId,
    p.UidCode    AS DocumentType,
    p.UidSerie   AS DocumentNumber,
    cpl.ManualAssignPointsId                                      AS BatchIdToReverse,
    cpl.Note                                                       AS OriginalNote,
    cpl.Points                                                     AS OriginalPoints,
    -cpl.Points                                                    AS PointsToReverse,
    'PointsAdjustmentBatchError-' + CAST(cpl.ManualAssignPointsId AS VARCHAR(10)) AS ReversalEventTypeCode,
    'Ajustamos tu saldo por un error de asignacion de puntos' AS ReversalNote
FROM Sml.CustomerPointsLog cpl
JOIN Sml.Person p ON p.Id = cpl.CustomerId
WHERE cpl.LogDate >= '2026-07-22' AND cpl.LogDate < '2026-07-23'
  AND cpl.EventTypeCode = 'PrizePoints'
  AND cpl.ManualAssignPointsId IS NOT NULL
ORDER BY cpl.CustomerId, cpl.ManualAssignPointsId;

-- Q11 (DML — INSERT, no es solo lectura): reversión real, generada tras actualización de
-- loyalty/CLAUDE.md (2026-07-22) que permite DML cuando se pide explícitamente.
--
-- SEGURIDAD — leer antes de ejecutar:
-- El trigger Sml.CustomerPointsLogAfterInsert (confirmado vía sys.triggers, 2026-07-22) recalcula
-- el saldo cacheado del cliente en SmlSt.CustomerPointsLog haciendo JOIN entre `inserted` y el
-- historial completo por CustomerId, sin condición de fila adicional. Si un mismo INSERT trae más
-- de una fila para el mismo cliente, el saldo recalculado se multiplica por esa cantidad de filas
-- (fan-out). Los clientes de esta reversión tienen entre 1 y 6 filas cada uno (confirmado sobre
-- query10_reversion.tsv), así que un INSERT masivo de las 37.645 filas corrompería el saldo
-- cacheado de ~7.930 de los 7.940 clientes.
-- Mitigación: 6 pasadas secuenciales, como máximo 1 fila por cliente por pasada
-- (ROW_NUMBER() OVER (PARTITION BY CustomerId ...)). Ejecutar una pasada a la vez, verificar
-- @@ROWCOUNT contra el valor esperado, y sólo hacer COMMIT si coincide antes de pasar a la
-- siguiente. EventTypeCode no tiene FK (confirmado vía sys.foreign_keys) — el valor dinámico
-- 'PointsAdjustmentBatchError-{batchid}' es seguro.
-- Esta sesión no tiene permisos de escritura sobre Sml.CustomerPointsLog (confirmado en Q1) —
-- la ejecución real queda a cargo de quien tenga esos permisos.

-- === PASADA 1 de 6 — esperar 7940 filas insertadas ===
BEGIN TRANSACTION;
;WITH ToReverse AS (
    SELECT
        cpl.CustomerId,
        cpl.ManualAssignPointsId,
        cpl.Points,
        ROW_NUMBER() OVER (PARTITION BY cpl.CustomerId ORDER BY cpl.ManualAssignPointsId) AS RowNum
    FROM Sml.CustomerPointsLog cpl
    WHERE cpl.LogDate >= '2026-07-22' AND cpl.LogDate < '2026-07-23'
      AND cpl.EventTypeCode = 'PrizePoints'
      AND cpl.ManualAssignPointsId IS NOT NULL
)
INSERT INTO Sml.CustomerPointsLog (CustomerId, LogDate, Note, Points, EventTypeCode)
SELECT CustomerId, SYSDATETIMEOFFSET(),
       'Ajustamos tu saldo por un error de asignacion de puntos',
       -Points,
       'PointsAdjustmentBatchError-' + CAST(ManualAssignPointsId AS VARCHAR(10))
FROM ToReverse WHERE RowNum = 1;
SELECT @@ROWCOUNT AS RowsInserted; -- esperar 7940
-- COMMIT;   -- sólo si RowsInserted = 7940
-- ROLLBACK; -- en caso contrario

-- === PASADA 2 de 6 — esperar 7930 filas insertadas (ejecutar sólo tras confirmar y COMMIT de la pasada 1) ===
BEGIN TRANSACTION;
;WITH ToReverse AS (
    SELECT
        cpl.CustomerId,
        cpl.ManualAssignPointsId,
        cpl.Points,
        ROW_NUMBER() OVER (PARTITION BY cpl.CustomerId ORDER BY cpl.ManualAssignPointsId) AS RowNum
    FROM Sml.CustomerPointsLog cpl
    WHERE cpl.LogDate >= '2026-07-22' AND cpl.LogDate < '2026-07-23'
      AND cpl.EventTypeCode = 'PrizePoints'
      AND cpl.ManualAssignPointsId IS NOT NULL
)
INSERT INTO Sml.CustomerPointsLog (CustomerId, LogDate, Note, Points, EventTypeCode)
SELECT CustomerId, SYSDATETIMEOFFSET(),
       'Ajustamos tu saldo por un error de asignacion de puntos',
       -Points,
       'PointsAdjustmentBatchError-' + CAST(ManualAssignPointsId AS VARCHAR(10))
FROM ToReverse WHERE RowNum = 2;
SELECT @@ROWCOUNT AS RowsInserted; -- esperar 7930
-- COMMIT;   -- sólo si RowsInserted = 7930
-- ROLLBACK; -- en caso contrario

-- === PASADA 3 de 6 — esperar 7920 filas insertadas (ejecutar sólo tras confirmar y COMMIT de la pasada 2) ===
BEGIN TRANSACTION;
;WITH ToReverse AS (
    SELECT
        cpl.CustomerId,
        cpl.ManualAssignPointsId,
        cpl.Points,
        ROW_NUMBER() OVER (PARTITION BY cpl.CustomerId ORDER BY cpl.ManualAssignPointsId) AS RowNum
    FROM Sml.CustomerPointsLog cpl
    WHERE cpl.LogDate >= '2026-07-22' AND cpl.LogDate < '2026-07-23'
      AND cpl.EventTypeCode = 'PrizePoints'
      AND cpl.ManualAssignPointsId IS NOT NULL
)
INSERT INTO Sml.CustomerPointsLog (CustomerId, LogDate, Note, Points, EventTypeCode)
SELECT CustomerId, SYSDATETIMEOFFSET(),
       'Ajustamos tu saldo por un error de asignacion de puntos',
       -Points,
       'PointsAdjustmentBatchError-' + CAST(ManualAssignPointsId AS VARCHAR(10))
FROM ToReverse WHERE RowNum = 3;
SELECT @@ROWCOUNT AS RowsInserted; -- esperar 7920
-- COMMIT;   -- sólo si RowsInserted = 7920
-- ROLLBACK; -- en caso contrario

-- === PASADA 4 de 6 — esperar 7907 filas insertadas (ejecutar sólo tras confirmar y COMMIT de la pasada 3) ===
BEGIN TRANSACTION;
;WITH ToReverse AS (
    SELECT
        cpl.CustomerId,
        cpl.ManualAssignPointsId,
        cpl.Points,
        ROW_NUMBER() OVER (PARTITION BY cpl.CustomerId ORDER BY cpl.ManualAssignPointsId) AS RowNum
    FROM Sml.CustomerPointsLog cpl
    WHERE cpl.LogDate >= '2026-07-22' AND cpl.LogDate < '2026-07-23'
      AND cpl.EventTypeCode = 'PrizePoints'
      AND cpl.ManualAssignPointsId IS NOT NULL
)
INSERT INTO Sml.CustomerPointsLog (CustomerId, LogDate, Note, Points, EventTypeCode)
SELECT CustomerId, SYSDATETIMEOFFSET(),
       'Ajustamos tu saldo por un error de asignacion de puntos',
       -Points,
       'PointsAdjustmentBatchError-' + CAST(ManualAssignPointsId AS VARCHAR(10))
FROM ToReverse WHERE RowNum = 4;
SELECT @@ROWCOUNT AS RowsInserted; -- esperar 7907
-- COMMIT;   -- sólo si RowsInserted = 7907
-- ROLLBACK; -- en caso contrario

-- === PASADA 5 de 6 — esperar 3961 filas insertadas (ejecutar sólo tras confirmar y COMMIT de la pasada 4) ===
BEGIN TRANSACTION;
;WITH ToReverse AS (
    SELECT
        cpl.CustomerId,
        cpl.ManualAssignPointsId,
        cpl.Points,
        ROW_NUMBER() OVER (PARTITION BY cpl.CustomerId ORDER BY cpl.ManualAssignPointsId) AS RowNum
    FROM Sml.CustomerPointsLog cpl
    WHERE cpl.LogDate >= '2026-07-22' AND cpl.LogDate < '2026-07-23'
      AND cpl.EventTypeCode = 'PrizePoints'
      AND cpl.ManualAssignPointsId IS NOT NULL
)
INSERT INTO Sml.CustomerPointsLog (CustomerId, LogDate, Note, Points, EventTypeCode)
SELECT CustomerId, SYSDATETIMEOFFSET(),
       'Ajustamos tu saldo por un error de asignacion de puntos',
       -Points,
       'PointsAdjustmentBatchError-' + CAST(ManualAssignPointsId AS VARCHAR(10))
FROM ToReverse WHERE RowNum = 5;
SELECT @@ROWCOUNT AS RowsInserted; -- esperar 3961
-- COMMIT;   -- sólo si RowsInserted = 3961
-- ROLLBACK; -- en caso contrario

-- === PASADA 6 de 6 — esperar 1987 filas insertadas (ejecutar sólo tras confirmar y COMMIT de la pasada 5) ===
BEGIN TRANSACTION;
;WITH ToReverse AS (
    SELECT
        cpl.CustomerId,
        cpl.ManualAssignPointsId,
        cpl.Points,
        ROW_NUMBER() OVER (PARTITION BY cpl.CustomerId ORDER BY cpl.ManualAssignPointsId) AS RowNum
    FROM Sml.CustomerPointsLog cpl
    WHERE cpl.LogDate >= '2026-07-22' AND cpl.LogDate < '2026-07-23'
      AND cpl.EventTypeCode = 'PrizePoints'
      AND cpl.ManualAssignPointsId IS NOT NULL
)
INSERT INTO Sml.CustomerPointsLog (CustomerId, LogDate, Note, Points, EventTypeCode)
SELECT CustomerId, SYSDATETIMEOFFSET(),
       'Ajustamos tu saldo por un error de asignacion de puntos',
       -Points,
       'PointsAdjustmentBatchError-' + CAST(ManualAssignPointsId AS VARCHAR(10))
FROM ToReverse WHERE RowNum = 6;
SELECT @@ROWCOUNT AS RowsInserted; -- esperar 1987
-- COMMIT;   -- sólo si RowsInserted = 1987
-- ROLLBACK; -- en caso contrario

-- Q12 (DML — CREATE TABLE + BULK INSERT + INSERT): reasignación manual de la campaña de premios
-- ("corrida desde cero" ya anunciada en la Decisión de reversión), 7.940 socios ganadores desde
-- assignment.csv. Hecha a mano vía SQL validado en vez de MassivePointsAssignment para no repetir
-- la falta de idempotencia que causó el incidente WAF-504. Coincide con la misma población de la
-- reversión porque son los mismos ganadores — confirmado explícitamente con el usuario (2026-07-22)
-- antes de generar el DML. Temp table en schema SmlTemp, aprobado explícitamente.
-- Cada cliente aparece una sola vez en assignment.csv (0 duplicados, verificado) — no aplica el
-- bug de fan-out del trigger CustomerPointsLogAfterInsert (ver Q11), un solo INSERT es seguro.

-- Paso 1: crear tabla de staging
CREATE TABLE SmlTemp.Assignment_20260722_VisitaFrecuente (
    CustomerId UNIQUEIDENTIFIER NOT NULL PRIMARY KEY
);

-- Paso 2: cargar assignment.csv. BULK INSERT falló (Msg 4860 — el path del cliente no es
-- visible para el motor de SQL Server en SFCG-DB01). Alternativa sin acceso a filesystem del
-- servidor: 8 lotes de INSERT...VALUES (tope de 1000 filas por sentencia en T-SQL), generados
-- localmente desde assignment.csv — ver 20260722_puntos_duplicados_masivos_waf504_q12_paso2_values.sql.
-- Ejecutar los 8 lotes de ese archivo en orden (independientes entre sí, no requieren transacción
-- — es una tabla de staging, no producción).

-- Paso 3: verificar carga — esperar 7940 filas
SELECT COUNT(*) AS StagingRowCount FROM SmlTemp.Assignment_20260722_VisitaFrecuente;

-- Paso 4: validar integridad referencial ANTES del INSERT real — esperar 0 filas.
-- Cualquier fila acá haría fallar el INSERT por FK_dbo.CustomerPointsLog_dbo.Customer_CustomerId.
SELECT a.CustomerId
FROM SmlTemp.Assignment_20260722_VisitaFrecuente a
WHERE NOT EXISTS (SELECT 1 FROM Sml.Customer c WHERE c.Id = a.CustomerId);

-- Paso 5: INSERT real — sólo si Paso 3 = 7940 y Paso 4 = 0 filas
BEGIN TRANSACTION;
INSERT INTO Sml.CustomerPointsLog (CustomerId, LogDate, Note, Points, EventTypeCode)
SELECT
    CustomerId,
    SYSDATETIMEOFFSET(),
    'Puntos por visita frecuente',
    10000,
    'ManualPrizePoints'
FROM SmlTemp.Assignment_20260722_VisitaFrecuente;
SELECT @@ROWCOUNT AS RowsInserted; -- esperar 7940
-- COMMIT;   -- sólo si RowsInserted = 7940
-- ROLLBACK; -- en caso contrario

-- Paso 6: verificación final por query, tras COMMIT — esperar 7940 filas, 79.400.000 pts
SELECT COUNT(*) AS TotalAssigned, SUM(Points) AS TotalPoints
FROM Sml.CustomerPointsLog
WHERE EventTypeCode = 'ManualPrizePoints'
  AND LogDate >= '2026-07-22' AND LogDate < '2026-07-23';

-- Paso 7: limpieza — sólo después de confirmar el Paso 6
DROP TABLE SmlTemp.Assignment_20260722_VisitaFrecuente;

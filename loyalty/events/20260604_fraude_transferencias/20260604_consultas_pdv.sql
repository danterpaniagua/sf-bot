-- ============================================================
-- Investigación PDV y email — 2026-06-04
-- Continuación de 20260604_consultas_investigacion.sql
-- ============================================================

-- EQ1: Columnas de sml.Person
SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
FROM [SmartFran.Solution.SmartLoyalty].INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'sml' AND TABLE_NAME = 'Person'
ORDER BY ORDINAL_POSITION;

-- EQ2: Tablas con "email", "verif" o "confirm" en el nombre
SELECT TABLE_SCHEMA, TABLE_NAME
FROM [SmartFran.Solution.SmartLoyalty].INFORMATION_SCHEMA.TABLES
WHERE TABLE_NAME LIKE '%mail%'
   OR TABLE_NAME LIKE '%verif%'
   OR TABLE_NAME LIKE '%confirm%'
   OR TABLE_NAME LIKE '%valid%'
ORDER BY TABLE_SCHEMA, TABLE_NAME;

-- EQ3: Columnas de SmlSt.CustomerMailing y Mlg.MailContact
SELECT TABLE_SCHEMA, TABLE_NAME, COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
FROM [SmartFran.Solution.SmartLoyalty].INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA IN ('SmlSt', 'Mlg')
  AND TABLE_NAME IN ('CustomerMailing', 'MailContact')
ORDER BY TABLE_SCHEMA, TABLE_NAME, ORDINAL_POSITION;

-- EQ4: StateId en SmlSt.CustomerMailing
SELECT StateId, COUNT(*) AS Clientes
FROM [SmartFran.Solution.SmartLoyalty].SmlSt.CustomerMailing
GROUP BY StateId
ORDER BY Clientes DESC;

-- EQ5: Muestra de Mlg.MailContact.ContactData
SELECT TOP 5 Id, ConsumerId, AppCode, ContactData
FROM [SmartFran.Solution.SmartLoyalty].Mlg.MailContact
WHERE ContactData IS NOT NULL;

-- EQ6: Email y estado de mailing para cuentas investigadas
SELECT
    p.Id            AS CustomerId,
    p.FirstName + ' ' + p.LastName AS Nombre,
    p.UidSerie      AS DNI,
    p.Email         AS Email_Person,
    cm.Email        AS Email_Mailing,
    cm.StateId      AS StateId
FROM [SmartFran.Solution.SmartLoyalty].sml.Person p
LEFT JOIN [SmartFran.Solution.SmartLoyalty].SmlSt.CustomerMailing cm
    ON cm.CustomerId = p.Id
WHERE p.Id IN (
    'E6CC99E8-368F-C66B-00A1-08DEB39859AC',  -- Dimon Briz
    '03B3D113-4208-C34E-8B20-08DE417DA574',  -- Simon Brizuela 46845173
    '95333272-6EBD-C5CC-0BAE-08DE555FC9DA',  -- Simon Brizuela 46845174
    'BF87EC69-C6F3-CDE1-6027-08D87DD1E54E',  -- María Celeste Mamanis
    '67F9F6D2-1EAC-CD0D-F0F6-08D212DCB98D'   -- Sergio Emanuel Cordero
);

-- MC1: Fecha de creación de cuentas conocidas
SELECT
    c.Id                                AS CustomerId,
    p.FirstName + ' ' + p.LastName      AS Nombre,
    p.UidSerie                          AS DNI,
    CAST(c.CreatedDate AS DATE)         AS Fecha_Creacion,
    c.RegistrationChannel
FROM [SmartFran.Solution.SmartLoyalty].sml.Customer c
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person p
    ON p.Id = c.Id
WHERE c.Id IN (
    '03B3D113-4208-C34E-8B20-08DE417DA574',  -- Simon Brizuela 46845173
    'E6CC99E8-368F-C66B-00A1-08DEB39859AC',  -- Dimon Briz
    '95333272-6EBD-C5CC-0BAE-08DE555FC9DA',  -- Simon Brizuela 46845174
    '195F3DA0-A2C0-C946-D282-08DEC0B8E1EF'   -- Carlos Daniel Sancho
)
   OR p.UidSerie IN ('43541207', '46374837', '44238411')  -- Homer Spo, Nahir Niz, Lucas Riquelme
ORDER BY Fecha_Creacion;

-- ============================================================
-- CANJES Y PDV
-- ============================================================

-- PX1: Tablas con "sale", "pdv", "branch", "franchise", "location" en el nombre
SELECT TABLE_SCHEMA, TABLE_NAME
FROM [SmartFran.Solution.SmartLoyalty].INFORMATION_SCHEMA.TABLES
WHERE TABLE_NAME LIKE '%Sale%'
   OR TABLE_NAME LIKE '%Pdv%'
   OR TABLE_NAME LIKE '%Local%'
   OR TABLE_NAME LIKE '%Branch%'
   OR TABLE_NAME LIKE '%Franchise%'
   OR TABLE_NAME LIKE '%Location%'
   OR TABLE_NAME LIKE '%Sucursal%'
ORDER BY TABLE_SCHEMA, TABLE_NAME;

-- PX2: Canjes (DiscountPointsByExchange) de las cuentas investigadas
SELECT
    FORMAT(DATEADD(HOUR, -3, cpl.LogDate), 'yyyy-MM-dd HH:mm:ss') AS Fecha_UTC3,
    p.FirstName + ' ' + p.LastName                                  AS Cliente,
    p.UidSerie                                                       AS DNI,
    cpl.Points                                                       AS Puntos,
    cpl.SaleId
FROM [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog cpl
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person p
    ON p.Id = cpl.CustomerId
WHERE cpl.CustomerId IN (
    '03B3D113-4208-C34E-8B20-08DE417DA574',  -- Simon Brizuela 46845173
    '95333272-6EBD-C5CC-0BAE-08DE555FC9DA',  -- Simon Brizuela 46845174
    'E6CC99E8-368F-C66B-00A1-08DEB39859AC',  -- Dimon Briz
    '9623AEEE-B858-C935-3414-08DEC0DE6CDE',  -- Santiago Cabral
    'BF87EC69-C6F3-CDE1-6027-08D87DD1E54E'   -- María Celeste Mamanis
)
  AND cpl.EventTypeCode = 'DiscountPointsByExchange'
ORDER BY cpl.LogDate;

-- PX3: Columnas de sml.Sale
SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE
FROM [SmartFran.Solution.SmartLoyalty].INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'sml' AND TABLE_NAME = 'Sale'
ORDER BY ORDINAL_POSITION;

-- PX4: PDV de los canjes — sucursal por SaleId
SELECT DISTINCT
    s.Id        AS SaleId,
    bo.Id       AS BranchOfficeId,
    bo.Code     AS Codigo,
    bo.Name     AS Sucursal
FROM [SmartFran.Solution.SmartLoyalty].sml.Sale s
JOIN [SmartFran.Solution.SmartLoyalty].sml.BranchOffice bo
    ON bo.Id = s.BranchOfficeId
WHERE s.Id IN (
    235596604, 237341901, 238645103, 251301637, 251828940,
    239802061, 241052255, 242008200, 243835696, 244342665,
    244599052, 245189719, 246440669, 246549237, 247670120,
    248035136, 248281694, 248428605, 249957518, 250195641
)
ORDER BY bo.Name;

-- PX5: Sucursal de la actividad POS de Dimon Briz (muestra SaleIds con puntos > 0)
SELECT DISTINCT
    s.Id        AS SaleId,
    bo.Code     AS Codigo,
    bo.Name     AS Sucursal,
    bo.Id       AS BranchOfficeId
FROM [SmartFran.Solution.SmartLoyalty].sml.Sale s
JOIN [SmartFran.Solution.SmartLoyalty].sml.BranchOffice bo
    ON bo.Id = s.BranchOfficeId
WHERE s.Id IN (
    251137101, 251157244, 251160075, 251165542, 251174284,
    251176999, 251178707, 251259327, 251259559, 251266529,
    251271449, 251445240, 251445824, 251446075, 251447363,
    251525013, 251529280, 251621105, 251621357, 251625242,
    251625849
)
ORDER BY bo.Name;

-- PX6: Columnas de sml.FranchiseStaff
SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE
FROM [SmartFran.Solution.SmartLoyalty].INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'sml' AND TABLE_NAME = 'FranchiseStaff'
ORDER BY ORDINAL_POSITION;

-- PX7: FranchiseGroup de las 4 sucursales involucradas en canjes y acumulación
SELECT
    bo.Code, bo.Name, bo.FranchiseGroupId,
    fg.Name     AS Franquicia,
    bo.ActivatedDate
FROM [SmartFran.Solution.SmartLoyalty].sml.BranchOffice bo
JOIN [SmartFran.Solution.SmartLoyalty].sml.FranchiseGroup fg
    ON fg.Id = bo.FranchiseGroupId
WHERE bo.Id IN (
    'B81F3B0F-BFD6-CF8B-9370-08D1C5B81E1E',  -- LICEO
    'CFBA9479-1221-CD2B-0510-08D1C257E9E0',  -- LICEO 2DA
    'D09761F2-D9C0-CE53-4155-08D2F1C1A5CC',  -- TERMINAL I
    '7DD9CD52-D49C-C6F2-3D54-08D73B88BD57'   -- FLORESTA IV
);

-- PX8: CustomerId y PlatformCode en ventas de Dimon Briz
SELECT
    s.Id            AS SaleId,
    bo.Name         AS Sucursal,
    s.CustomerId,
    s.PlatformCode,
    s.PaymentTypeCode,
    FORMAT(DATEADD(HOUR, -3, s.SaleDate), 'yyyy-MM-dd HH:mm') AS Fecha_UTC3
FROM [SmartFran.Solution.SmartLoyalty].sml.Sale s
JOIN [SmartFran.Solution.SmartLoyalty].sml.BranchOffice bo
    ON bo.Id = s.BranchOfficeId
WHERE s.Id IN (
    251137101, 251157244, 251160075, 251165542, 251174284,
    251176999, 251178707, 251259327, 251259559, 251266529,
    251271449, 251445240, 251445824, 251446075, 251447363,
    251525013, 251529280, 251621105, 251621357, 251625242,
    251625849
)
ORDER BY s.SaleDate;

-- PX9: Anomalía SaleId 251525013 — a quién pertenece esa venta
SELECT
    s.Id, s.CustomerId, s.PlatformCode, s.PaymentTypeCode,
    FORMAT(DATEADD(HOUR, -3, s.SaleDate), 'yyyy-MM-dd HH:mm') AS Fecha_UTC3,
    bo.Name AS Sucursal,
    p.FirstName + ' ' + p.LastName AS Cliente_Registrado,
    p.UidSerie AS DNI
FROM [SmartFran.Solution.SmartLoyalty].sml.Sale s
JOIN [SmartFran.Solution.SmartLoyalty].sml.BranchOffice bo
    ON bo.Id = s.BranchOfficeId
LEFT JOIN [SmartFran.Solution.SmartLoyalty].sml.Person p
    ON p.Id = s.CustomerId
WHERE s.Id = 251525013;

-- PX10: Personal activo en LICEO y FLORESTA IV
SELECT
    fg.Name        AS Franquicia,
    fs.StaffRoleCode,
    fs.CreatedDate,
    p.FirstName + ' ' + p.LastName AS Empleado,
    p.Email
FROM [SmartFran.Solution.SmartLoyalty].sml.FranchiseStaff fs
JOIN [SmartFran.Solution.SmartLoyalty].sml.FranchiseGroup fg
    ON fg.Id = fs.FranchiseGroupId
LEFT JOIN [SmartFran.Solution.SmartLoyalty].sml.Person p
    ON p.Id = fs.StaffId
WHERE fs.FranchiseGroupId IN (
    '726AFC3A-096D-C0FF-EB81-08D1BC1D812E',  -- LICEO (Aznarez)
    '83297948-DA3C-CD5E-D0E8-08D559F78815'   -- FLORESTA IV (Liberali)
)
  AND fs.DeactivatedDate IS NULL
ORDER BY fg.Name, fs.StaffRoleCode;

-- PX11: Volumen total de ventas con CustomerId = Dimon Briz por sucursal
SELECT
    bo.Code, bo.Name AS Sucursal,
    COUNT(*)             AS Ventas,
    MIN(FORMAT(DATEADD(HOUR, -3, s.SaleDate), 'yyyy-MM-dd')) AS Primera,
    MAX(FORMAT(DATEADD(HOUR, -3, s.SaleDate), 'yyyy-MM-dd')) AS Ultima
FROM [SmartFran.Solution.SmartLoyalty].sml.Sale s
JOIN [SmartFran.Solution.SmartLoyalty].sml.BranchOffice bo
    ON bo.Id = s.BranchOfficeId
WHERE s.CustomerId = 'E6CC99E8-368F-C66B-00A1-08DEB39859AC'
GROUP BY bo.Code, bo.Name
ORDER BY Ventas DESC;

-- PX12: FranchiseGroup de ORAN ×4, MARCOS PAZ, SANTIAGO DEL ESTERO II
SELECT
    bo.Code, bo.Name AS Sucursal,
    fg.Id AS FranchiseGroupId,
    fg.Name AS Franquicia
FROM [SmartFran.Solution.SmartLoyalty].sml.BranchOffice bo
JOIN [SmartFran.Solution.SmartLoyalty].sml.FranchiseGroup fg
    ON fg.Id = bo.FranchiseGroupId
WHERE bo.Code IN ('4358', '4216', '3262', '3812', '4357', '3598');

-- PX13: Tablas de usuarios y staff
SELECT TABLE_SCHEMA, TABLE_NAME
FROM [SmartFran.Solution.SmartLoyalty].INFORMATION_SCHEMA.TABLES
WHERE TABLE_NAME LIKE '%User%'
   OR TABLE_NAME LIKE '%Staff%'
   OR TABLE_NAME LIKE '%Login%'
   OR TABLE_NAME LIKE '%Account%'
ORDER BY TABLE_SCHEMA, TABLE_NAME;

-- PX14: Personal activo en franquicias de acumulación
SELECT
    fg.Name         AS Franquicia,
    fs.StaffRoleCode,
    fs.CreatedDate,
    p.FirstName + ' ' + p.LastName AS Empleado,
    p.Email
FROM [SmartFran.Solution.SmartLoyalty].sml.FranchiseStaff fs
JOIN [SmartFran.Solution.SmartLoyalty].sml.FranchiseGroup fg
    ON fg.Id = fs.FranchiseGroupId
LEFT JOIN [SmartFran.Solution.SmartLoyalty].sml.Person p
    ON p.Id = fs.StaffId
WHERE fs.FranchiseGroupId IN (
    '18766E1B-68C5-C3AC-F746-08D0BA833C48',  -- Cura, Juan Cruz (ORAN ×4)
    'A318B16F-88E7-CCA0-7A65-08D27596EAD8',  -- Zurro, Horacio (MARCOS PAZ)
    '31B146B2-4AE0-C099-85B9-08D223DBF13A',  -- Jawahar, Angel (SANTIAGO DEL ESTERO II)
    'BE71FA6A-2130-CA69-939B-08D80EDDBF24'   -- Mercado, Adrian (TERMINAL I)
)
  AND fs.DeactivatedDate IS NULL
ORDER BY fg.Name, fs.StaffRoleCode;

-- PX15: Columnas de Mbr.User
SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE
FROM [SmartFran.Solution.SmartLoyalty].INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'Mbr' AND TABLE_NAME = 'User'
ORDER BY ORDINAL_POSITION;

-- PX16: Resolver GUIDs de staff no resueltos por Mbr.User.Id
SELECT
    u.Id, u.UserName, u.MemberId,
    u.CreatedDate, u.LastLoginDate,
    p.FirstName + ' ' + p.LastName AS Nombre,
    p.Email
FROM [SmartFran.Solution.SmartLoyalty].Mbr.[User] u
LEFT JOIN [SmartFran.Solution.SmartLoyalty].sml.Person p
    ON p.Id = u.MemberId
WHERE u.Id IN (
    '4248A2B7-5C8F-C177-B5BF-08D208818CCB',
    'DC1CF375-A7E7-C4A9-EBCD-08D4D4610D57',
    '57A4EEBC-3F0B-C956-F2C4-08D24FD976C9',
    '269FA4D4-1D69-C5B9-6BF4-08D6DFB6D020'
);

-- PX17: Resolver GUIDs de staff no resueltos por Mbr.User.MemberId
SELECT
    u.Id, u.UserName, u.MemberId,
    u.CreatedDate, u.LastLoginDate,
    p.FirstName + ' ' + p.LastName AS Nombre,
    p.Email
FROM [SmartFran.Solution.SmartLoyalty].Mbr.[User] u
LEFT JOIN [SmartFran.Solution.SmartLoyalty].sml.Person p
    ON p.Id = u.MemberId
WHERE u.MemberId IN (
    '4248A2B7-5C8F-C177-B5BF-08D208818CCB',
    'DC1CF375-A7E7-C4A9-EBCD-08D4D4610D57',
    '57A4EEBC-3F0B-C956-F2C4-08D24FD976C9',
    '269FA4D4-1D69-C5B9-6BF4-08D6DFB6D020'
);

-- ============================================================
-- V3-8: Total de puntos desviados — cuantificación completa
-- ============================================================

-- V3-8: Puntos totales acreditados a Dimon Briz por POS por sucursal
-- (suma de todos los EarnPointsByBuying con SaleId != NULL)
SELECT
    bo.Code,
    bo.Name                          AS Sucursal,
    fg.Name                          AS Franquicia,
    COUNT(DISTINCT s.Id)             AS Ventas,
    SUM(cpl.Points)                  AS Puntos_Desviados,
    MIN(FORMAT(DATEADD(HOUR, -3, s.SaleDate), 'yyyy-MM-dd')) AS Primera,
    MAX(FORMAT(DATEADD(HOUR, -3, s.SaleDate), 'yyyy-MM-dd')) AS Ultima
FROM [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog cpl
JOIN [SmartFran.Solution.SmartLoyalty].sml.Sale s
    ON s.Id = cpl.SaleId
JOIN [SmartFran.Solution.SmartLoyalty].sml.BranchOffice bo
    ON bo.Id = s.BranchOfficeId
JOIN [SmartFran.Solution.SmartLoyalty].sml.FranchiseGroup fg
    ON fg.Id = bo.FranchiseGroupId
WHERE cpl.CustomerId = 'E6CC99E8-368F-C66B-00A1-08DEB39859AC'
  AND cpl.EventTypeCode = 'EarnPointsByBuying'
  AND cpl.SaleId IS NOT NULL
GROUP BY bo.Code, bo.Name, fg.Name
ORDER BY Puntos_Desviados DESC;

-- ============================================================
-- V3-7: Investigación doble-acreditación SaleId 251525013
-- ============================================================

-- V3-7: Todos los clientes acreditados en la venta de Federico Vidal
SELECT
    FORMAT(DATEADD(HOUR, -3, cpl.LogDate), 'yyyy-MM-dd HH:mm:ss') AS Fecha_UTC3,
    cpl.CustomerId,
    p.FirstName + ' ' + p.LastName                                  AS Cliente,
    p.UidSerie                                                       AS DNI,
    cpl.EventTypeCode,
    cpl.Points,
    cpl.SaleId
FROM [SmartFran.Solution.SmartLoyalty].sml.CustomerPointsLog cpl
JOIN [SmartFran.Solution.SmartLoyalty].sml.Person p
    ON p.Id = cpl.CustomerId
WHERE cpl.SaleId = 251525013
ORDER BY cpl.LogDate, cpl.CustomerId;

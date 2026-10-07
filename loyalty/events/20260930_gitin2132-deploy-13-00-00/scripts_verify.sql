/* =====================================================================================
   GITIN-2132 - Verificación posterior a la ejecución de los scripts v13.00.00
   SOLO LECTURA (SELECT). Ejecutar en la base SmartFran.Solution.SmartLoyalty del servidor
   donde se corrieron los scripts. Guardar Results + Messages en data/.
   ===================================================================================== */
SET NOCOUNT ON;

-- 0. Contexto: servidor y base (confirmar que es el que se espera)
SELECT DB_NAME() AS BaseActual, @@SERVERNAME AS Servidor, SYSDATETIMEOFFSET() AS Ahora;

-- 1. Historial de migraciones de EF (últimas 12). Si la tabla está en otro esquema, ajustar.
SELECT TOP 12 MigrationId FROM dbo.__MigrationHistory ORDER BY MigrationId DESC;

-- 2. Catálogo de insignias
SELECT Id, CategoryCode, Code, Name, [Rank], MinDays, MaxDays, IsActive
FROM Sml.Insignia
ORDER BY [Rank];

-- 3. Reglas por país (cantidad total / activas / DOWNGRADE activas)
SELECT
    R.CountryId,
    COUNT_BIG(*)                                                                    AS ReglasTotal,
    SUM(CASE WHEN R.IsActive = 1 THEN 1 ELSE 0 END)                                 AS ReglasActivas,
    SUM(CASE WHEN R.IsActive = 1 AND R.TransitionType = 'DOWNGRADE' THEN 1 ELSE 0 END) AS DowngradeActivas
FROM Sml.InsigniaTransitionRule R
GROUP BY R.CountryId
ORDER BY R.CountryId;

-- 4. Detalle de reglas DOWNGRADE activas por país (umbrales)
SELECT
    R.CountryId,
    FI.Code AS Desde,
    TI.Code AS Hacia,
    R.MinDaysSinceLastActivity
FROM Sml.InsigniaTransitionRule R
INNER JOIN Sml.Insignia FI ON FI.Id = R.FromInsigniaId
INNER JOIN Sml.Insignia TI ON TI.Id = R.ToInsigniaId
WHERE R.IsActive = 1 AND R.TransitionType = 'DOWNGRADE'
ORDER BY R.CountryId, R.MinDaysSinceLastActivity;

-- 5. Socios activos por país (referencia) y filas cargadas en CustomerInsignia por país
SELECT
    C.Country_Id AS CountryId,
    COUNT_BIG(*) AS SociosActivos
FROM Sml.Customer C
WHERE C.DeativatedDate IS NULL
GROUP BY C.Country_Id
ORDER BY C.Country_Id;

SELECT
    C.Country_Id AS CountryId,
    COUNT_BIG(*) AS FilasCustomerInsignia
FROM Sml.CustomerInsignia CI
INNER JOIN Sml.Customer C ON C.Id = CI.CustomerId
GROUP BY C.Country_Id
ORDER BY C.Country_Id;

-- 6. Distribución de insignias por país
SELECT
    C.Country_Id AS CountryId,
    I.Code       AS Insignia,
    COUNT_BIG(*) AS Cantidad
FROM Sml.CustomerInsignia CI
INNER JOIN Sml.Customer C ON C.Id = CI.CustomerId
INNER JOIN Sml.Insignia I ON I.Id = CI.InsigniaId
GROUP BY C.Country_Id, I.Code
ORDER BY C.Country_Id, I.Code;

-- 7. Controles de consistencia (todos deberían dar 0)
SELECT COUNT_BIG(*) AS SociosActivosSinCustomerInsignia
FROM Sml.Customer C
WHERE C.DeativatedDate IS NULL
  AND NOT EXISTS (SELECT 1 FROM Sml.CustomerInsignia CI WHERE CI.CustomerId = C.Id);

SELECT COUNT_BIG(*) AS CustomerInsigniaDeSociosDadosDeBaja
FROM Sml.CustomerInsignia CI
INNER JOIN Sml.Customer C ON C.Id = CI.CustomerId
WHERE C.DeativatedDate IS NOT NULL;

SELECT COUNT_BIG(*) AS InsigniaIdInexistente
FROM Sml.CustomerInsignia CI
WHERE NOT EXISTS (SELECT 1 FROM Sml.Insignia I WHERE I.Id = CI.InsigniaId);

SELECT COUNT_BIG(*) AS CurrentInsigniaSinceNull
FROM Sml.CustomerInsignia
WHERE CurrentInsigniaSinceDate IS NULL;

SELECT COUNT_BIG(*) AS InitializedDateNulaOCero
FROM Sml.CustomerInsignia
WHERE InitializedDate IS NULL OR InitializedDate < '2000-01-01';

SELECT COUNT_BIG(*) AS FilasDuplicadasPorSocio
FROM (SELECT CustomerId FROM Sml.CustomerInsignia GROUP BY CustomerId HAVING COUNT_BIG(*) > 1) D;

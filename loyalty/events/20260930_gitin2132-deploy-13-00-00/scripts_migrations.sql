/* =====================================================================================
   GITIN-2132 - Verificación de migraciones de EF (SOLO LECTURA)
   Base: SmartFran.Solution.SmartLoyalty en SFCG-DB01. Guardar Results en data/.
   Lista esperada tomada de origin/main (aef06a72a), Core/Data/Migrations.
   ===================================================================================== */
SET NOCOUNT ON;

-- 1. Dónde está la tabla de historial de migraciones (esquema)
SELECT s.name AS Esquema, t.name AS Tabla
FROM sys.tables t INNER JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE t.name = '__MigrationHistory';

-- 2. Esperadas vs aplicadas (historial del contexto SmartLoyalty: Sml.__MigrationHistory)
;WITH Esperadas(MigrationId) AS (
    SELECT '202510301922175_UpdateTimeZoneTable' UNION ALL
    SELECT '202606261242489_InsigniaDataModel' UNION ALL
    SELECT '202606261931518_CustomerInsigniaHistory_AddColumnIvalidateSale' UNION ALL
    SELECT '202606291424552_AddTableCustomerInsigniaHistoryReveresal' UNION ALL
    SELECT '202606301800179_RenameInsigniaIdToId' UNION ALL
    SELECT '202607061957378_AddLocationIdToMktEvent' UNION ALL
    SELECT '202609031427595_Merge_12_and_13' UNION ALL
    SELECT '202609141443543_UpdateInsigniaDatesToDateTimeOffset' UNION ALL
    SELECT '202609162023213_AddCountryIdToInsigniaTransitionRule' UNION ALL
    SELECT '202609231326210_AddInsigniaRollbackColumns'
)
SELECT E.MigrationId AS Esperada,
       CASE WHEN H.MigrationId IS NULL THEN 'FALTA' ELSE 'aplicada' END AS Estado,
       H.ContextKey
FROM Esperadas E
LEFT JOIN Sml.__MigrationHistory H ON H.MigrationId = E.MigrationId
ORDER BY E.MigrationId;

-- 3. Últimas 15 migraciones aplicadas (todas las claves de contexto)
SELECT TOP 15 MigrationId, ContextKey
FROM Sml.__MigrationHistory
ORDER BY MigrationId DESC;

-- 4. Efectos de las migraciones en el esquema: columnas nuevas y tipos
SELECT OBJECT_NAME(c.object_id) AS Tabla, c.name AS Columna, t.name AS Tipo, c.is_nullable AS Nulo
FROM sys.columns c INNER JOIN sys.types t ON t.user_type_id = c.user_type_id
WHERE c.object_id IN (OBJECT_ID('Sml.CustomerInsignia'), OBJECT_ID('Sml.CustomerInsigniaHistory'), OBJECT_ID('Sml.InsigniaTransitionRule'))
  AND c.name IN ('InitializedDate','PreviousInsigniaSinceDate','LastActivityTypeAtTransition','CountryId',
                 'LastActivityDate','CurrentInsigniaSinceDate','WindowStartDate','UpdatedDate','TransitionDate','LastActivityDateAtTransition')
ORDER BY Tabla, Columna;

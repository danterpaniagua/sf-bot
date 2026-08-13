-- PROPUESTA DE MEJORA — Etl.EtlOperationConfig, Id = 6 (ToTable = dbo.CustomerPointsLog)
-- Fuente actual: Other/SqlScript/Updates/v10.07.00/v10.07.00_UpdateETLConfigForSync.sql:399-431
-- (repo dev-src-sol-smartloyalty, rama main)
--
-- Problema: el predicado original combina con OR dos condiciones sobre columnas
-- distintas (c.CreatedDate y cpl.LogDate). Un OR entre columnas de tablas distintas
-- no es sargable: el optimizador no puede resolverlo con un seek por índice sobre
-- ninguna de las dos columnas y recurre a un scan del join completo. El costo escala
-- con el volumen total evaluado, no con el tamaño de la ventana [@LowerBoundary,
-- @UpperBoundary) — por eso un pico de altas en CustomerPointsLog (campaña push)
-- dispara un salto de CPU desproporcionado.
--
-- Las dos ramas del OR ya son mutuamente excluyentes:
--   Rama A: c.CreatedDate está en la ventana (cliente nuevo)  -> cualquier LogDate < @UpperBoundary
--   Rama B: c.CreatedDate < @LowerBoundary (cliente ya existente) -> cpl.LogDate en la ventana
-- Al ser excluyentes, se pueden separar en dos SELECT sargables unidos por UNION ALL
-- (no se necesita deduplicar). Cada rama puede resolverse con un seek dedicado:
--   Rama A -> índice sobre Sml.Customer(CreatedDate)
--   Rama B -> índice sobre Sml.CustomerPointsLog(LogDate)

-- ============================================================
-- Query propuesta (reemplaza el FromQuery de Id = 6)
-- ============================================================
SELECT cpl.Id as CustomerPointsLogId
      ,EventTypeCode
      ,CustomerId
      ,LogDate
      ,Points
      ,SYSDATETIMEOFFSET() as _SyncDate
FROM Sml.CustomerPointsLog cpl (nolock)
INNER JOIN Sml.Customer c (nolock) ON cpl.CustomerId = c.Id
WHERE (@LowerBoundary IS NULL OR c.CreatedDate >= @LowerBoundary)
  AND c.CreatedDate < @UpperBoundary
  AND cpl.LogDate < @UpperBoundary

UNION ALL

SELECT cpl.Id as CustomerPointsLogId
      ,EventTypeCode
      ,CustomerId
      ,LogDate
      ,Points
      ,SYSDATETIMEOFFSET() as _SyncDate
FROM Sml.CustomerPointsLog cpl (nolock)
INNER JOIN Sml.Customer c (nolock) ON cpl.CustomerId = c.Id
WHERE (@LowerBoundary IS NULL OR cpl.LogDate >= @LowerBoundary)
  AND cpl.LogDate < @UpperBoundary
  AND (@LowerBoundary IS NULL OR c.CreatedDate < @LowerBoundary)

ORDER BY CustomerPointsLogId

-- ============================================================
-- Notas / riesgos a validar antes de llevar esto a un script
-- versionado de Other/SqlScript/Updates/:
-- ============================================================
--
-- 1. El framework ETL (paquete externo SmartFran.Business.Etl.*, no incluido en
--    este repo) envuelve el FromQuery configurado en dos formas distintas:
--      a) un probe de conteo: SELECT TOP 1 COUNT(*) OVER() FROM ( <FromQuery> )
--         — para esto necesita poder quitar el ORDER BY final del FromQuery
--         (una derived table no admite ORDER BY sin TOP/OFFSET).
--      b) el fetch paginado real, agregando OFFSET/FETCH después del ORDER BY.
--    El FromQuery original terminaba en "ORDER BY cpl.Id" (referencia directa al
--    alias de tabla). En una consulta con UNION ALL, el ORDER BY solo puede
--    referirse a la columna de salida del SELECT final, por eso aquí se usa
--    "ORDER BY CustomerPointsLogId" en lugar de "ORDER BY cpl.Id". Si el framework
--    localiza/recorta el ORDER BY por texto exacto en vez de parsear el SQL,
--    este cambio de alias podría romper ese mecanismo — validar contra el
--    comportamiento real del framework (o con una captura en QA) antes de aplicar
--    en producción.
--
-- 2. Verificar índices existentes antes de asumir que faltan (no se accedió a
--    sys.indexes en esta investigación):
--      - Sml.Customer(CreatedDate) — soporta la Rama A.
--      - Sml.CustomerPointsLog(LogDate) — soporta la Rama B.
--    Si no existen, evaluar su creación como acción separada (DDL), coordinada
--    con el equipo de DBA — no incluida en esta propuesta.
--
-- 3. Validar en LUCAS-KIUVI (QA) que el resultado del UNION ALL es exactamente
--    equivalente al del OR original antes de reemplazar la config en producción
--    (comparar conteos y una muestra de filas para un mismo rango de fechas).

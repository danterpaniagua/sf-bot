/* ================================================================================================
   DIAGNÓSTICO DE IMPACTO - CARGA INICIAL DE INSIGNIAS V3
   ================================================================================================

   BASADO EN:
       CargaInicial_Insignia_Final_v3.sql

   OBJETIVO:
   ---------
   Simular en PRODUCCIÓN la carga inicial completa SIN crear ni modificar:

       Sml.Insignia
       Sml.InsigniaTransitionRule
       Sml.CustomerInsignia

   Se simulan mediante tablas temporales:

       #Insignia
       #InsigniaTransitionRule
       #CustomerInsigniaSimulada

   Se utilizan datos REALES de producción:

       Sml.Customer
       Sml.Sale
       Sml.SalePromotion
       Sml.Promotion

   IMPORTANTE:
   -----------
   - NO modifica tablas funcionales.
   - NO crea objetos permanentes.
   - SÍ realiza lecturas reales y potencialmente pesadas.
   - SÍ materializa el resultado final en tempdb para aproximar el costo del INSERT.
   - Guardar Results + Messages de SSMS.
   ================================================================================================ */

SET NOCOUNT ON;
SET NOEXEC ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

DECLARE @InicioTotal DATETIME2 = SYSDATETIME();
DECLARE @AsOfDate DATETIMEOFFSET = SYSDATETIMEOFFSET();

PRINT '=======================================================================';
PRINT 'DIAGNOSTICO CARGA INICIAL INSIGNIAS V3';
PRINT 'Fecha de corte: ' + CONVERT(VARCHAR(50), @AsOfDate, 121);
PRINT 'NO SE MODIFICARAN TABLAS FUNCIONALES';
PRINT '=======================================================================';


/* ================================================================================================
   PASO 0 - LIMPIEZA
   ================================================================================================ */

IF OBJECT_ID('tempdb..#Insignia') IS NOT NULL DROP TABLE #Insignia;
IF OBJECT_ID('tempdb..#InsigniaTransitionRule') IS NOT NULL DROP TABLE #InsigniaTransitionRule;
IF OBJECT_ID('tempdb..#PaisesAProcesar') IS NOT NULL DROP TABLE #PaisesAProcesar;
IF OBJECT_ID('tempdb..#ReglasDowngrade') IS NOT NULL DROP TABLE #ReglasDowngrade;
IF OBJECT_ID('tempdb..#UltimaVenta') IS NOT NULL DROP TABLE #UltimaVenta;
IF OBJECT_ID('tempdb..#Actividad') IS NOT NULL DROP TABLE #Actividad;
IF OBJECT_ID('tempdb..#CustomerInsigniaSimulada') IS NOT NULL DROP TABLE #CustomerInsigniaSimulada;


/* ================================================================================================
   PASO 1 - SIMULACIÓN DEL CATÁLOGO Sml.Insignia
   ================================================================================================ */

CREATE TABLE #Insignia
(
    Id       INT          NOT NULL PRIMARY KEY,
    Code     VARCHAR(30)  NOT NULL,
    Name     VARCHAR(100) NOT NULL,
    IsActive BIT          NOT NULL
);

INSERT INTO #Insignia (Id, Code, Name, IsActive)
VALUES
    (900001, 'NUEVO',      'Nuevo',      1),
    (900002, 'CONGELADO',  'Congelado',  1),
    (900003, 'DERRETIDO',  'Derretido',  1),
    (900004, 'ANTOJO',     'Antojo',     1),
    (900005, 'IMBATIBLE',  'Imbatible',  1);


DECLARE @InsigniaNuevoId INT =
    (SELECT Id FROM #Insignia WHERE Code = 'NUEVO');

DECLARE @InsigniaImbatibleId INT =
    (SELECT Id FROM #Insignia WHERE Code = 'IMBATIBLE');

DECLARE @InsigniaAntojoId INT =
    (SELECT Id FROM #Insignia WHERE Code = 'ANTOJO');

DECLARE @InsigniaDerretidoId INT =
    (SELECT Id FROM #Insignia WHERE Code = 'DERRETIDO');

DECLARE @InsigniaCongeladoId INT =
    (SELECT Id FROM #Insignia WHERE Code = 'CONGELADO');


PRINT '';
PRINT '--- CATALOGO SIMULADO ---';

SELECT *
FROM #Insignia
ORDER BY Id;


/* ================================================================================================
   PASO 2 - IDENTIFICAR PAÍSES REALES QUE PARTICIPARÍAN EN LA CARGA

   Como CustomerInsignia todavía no existe en producción, estamos simulando una primera carga:
   todos los socios activos forman parte del universo.
   ================================================================================================ */

SELECT DISTINCT
    C.Country_Id AS CountryId
INTO #PaisesAProcesar
FROM Sml.Customer C
WHERE C.DeativatedDate IS NULL;


PRINT '';
PRINT '--- PAISES A PROCESAR ---';

SELECT
    Country_Id AS CountryId,
    COUNT_BIG(*) AS SociosActivos
FROM Sml.Customer
WHERE DeativatedDate IS NULL
GROUP BY Country_Id
ORDER BY Country_Id;


/* ================================================================================================
   PASO 3 - VALIDACIÓN DE COUNTRY_ID

   Replica la validación fail-fast de V3.
   ================================================================================================ */

IF EXISTS
(
    SELECT 1
    FROM #PaisesAProcesar
    WHERE CountryId IS NULL
       OR CountryId <= 0
)
BEGIN
    PRINT '';
    PRINT 'ERROR: existen socios activos sin Country_Id válido.';

    SELECT
        C.Id AS CustomerId,
        C.Country_Id
    FROM Sml.Customer C
    WHERE C.DeativatedDate IS NULL
      AND (C.Country_Id IS NULL OR C.Country_Id <= 0);

    SET STATISTICS IO OFF;
    SET STATISTICS TIME OFF;

    RETURN;
END;


/* ================================================================================================
   PASO 4 - SIMULACIÓN DE Sml.InsigniaTransitionRule

   IMPORTANTE:
   La V3 es Country-Aware.

   Por eso generamos las reglas para TODOS los CountryId reales encontrados.

   Umbrales actuales simulados:
       IMBATIBLE -> ANTOJO     = 31 días
       ANTOJO    -> DERRETIDO  = 51 días
       DERRETIDO -> CONGELADO  = 121 días

   También incluimos NUEVO -> CONGELADO = 30 solamente para representar el catálogo completo,
   aunque LA CARGA INICIAL V3 NO UTILIZA ESA REGLA.
   ================================================================================================ */

CREATE TABLE #InsigniaTransitionRule
(
    RuleId                     INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    CountryId                  INT               NOT NULL,
    FromInsigniaId             INT               NOT NULL,
    ToInsigniaId               INT               NOT NULL,
    TransitionType             VARCHAR(20)       NOT NULL,
    MinDaysSinceLastActivity   INT               NULL,
    IsActive                   BIT               NOT NULL
);


/* NUEVO -> CONGELADO
   Existe conceptualmente, pero V3 NO la usa durante carga inicial */
INSERT INTO #InsigniaTransitionRule
(
    CountryId,
    FromInsigniaId,
    ToInsigniaId,
    TransitionType,
    MinDaysSinceLastActivity,
    IsActive
)
SELECT
    CountryId,
    @InsigniaNuevoId,
    @InsigniaCongeladoId,
    'DOWNGRADE',
    30,
    1
FROM #PaisesAProcesar;


/* IMBATIBLE -> ANTOJO */
INSERT INTO #InsigniaTransitionRule
(
    CountryId,
    FromInsigniaId,
    ToInsigniaId,
    TransitionType,
    MinDaysSinceLastActivity,
    IsActive
)
SELECT
    CountryId,
    @InsigniaImbatibleId,
    @InsigniaAntojoId,
    'DOWNGRADE',
    31,
    1
FROM #PaisesAProcesar;


/* ANTOJO -> DERRETIDO */
INSERT INTO #InsigniaTransitionRule
(
    CountryId,
    FromInsigniaId,
    ToInsigniaId,
    TransitionType,
    MinDaysSinceLastActivity,
    IsActive
)
SELECT
    CountryId,
    @InsigniaAntojoId,
    @InsigniaDerretidoId,
    'DOWNGRADE',
    51,
    1
FROM #PaisesAProcesar;


/* DERRETIDO -> CONGELADO */
INSERT INTO #InsigniaTransitionRule
(
    CountryId,
    FromInsigniaId,
    ToInsigniaId,
    TransitionType,
    MinDaysSinceLastActivity,
    IsActive
)
SELECT
    CountryId,
    @InsigniaDerretidoId,
    @InsigniaCongeladoId,
    'DOWNGRADE',
    121,
    1
FROM #PaisesAProcesar;


PRINT '';
PRINT '--- REGLAS SIMULADAS POR PAIS ---';

SELECT
    R.CountryId,
    FI.Code AS FromInsignia,
    TI.Code AS ToInsignia,
    R.MinDaysSinceLastActivity
FROM #InsigniaTransitionRule R
INNER JOIN #Insignia FI
    ON FI.Id = R.FromInsigniaId
INNER JOIN #Insignia TI
    ON TI.Id = R.ToInsigniaId
ORDER BY
    R.CountryId,
    R.MinDaysSinceLastActivity;


/* ================================================================================================
   PASO 5 - VALIDACIONES DE REGLAS POR PAÍS

   Replica conceptualmente los controles de V3.
   ================================================================================================ */

PRINT '';
PRINT '--- VALIDACION DE REGLAS POR PAIS ---';


/* 5.1 IMBATIBLE -> ANTOJO */
SELECT
    P.CountryId
FROM #PaisesAProcesar P
LEFT JOIN #InsigniaTransitionRule R
    ON R.CountryId = P.CountryId
   AND R.TransitionType = 'DOWNGRADE'
   AND R.FromInsigniaId = @InsigniaImbatibleId
   AND R.ToInsigniaId = @InsigniaAntojoId
   AND R.IsActive = 1
   AND R.MinDaysSinceLastActivity > 0
WHERE R.RuleId IS NULL;


/* 5.2 ANTOJO -> DERRETIDO */
SELECT
    P.CountryId
FROM #PaisesAProcesar P
LEFT JOIN #InsigniaTransitionRule R
    ON R.CountryId = P.CountryId
   AND R.TransitionType = 'DOWNGRADE'
   AND R.FromInsigniaId = @InsigniaAntojoId
   AND R.ToInsigniaId = @InsigniaDerretidoId
   AND R.IsActive = 1
   AND R.MinDaysSinceLastActivity > 0
WHERE R.RuleId IS NULL;


/* 5.3 DERRETIDO -> CONGELADO */
SELECT
    P.CountryId
FROM #PaisesAProcesar P
LEFT JOIN #InsigniaTransitionRule R
    ON R.CountryId = P.CountryId
   AND R.TransitionType = 'DOWNGRADE'
   AND R.FromInsigniaId = @InsigniaDerretidoId
   AND R.ToInsigniaId = @InsigniaCongeladoId
   AND R.IsActive = 1
   AND R.MinDaysSinceLastActivity > 0
WHERE R.RuleId IS NULL;


/* 5.4 Monotonía */
SELECT
    P.CountryId,
    RA.MinDaysSinceLastActivity AS AntojoMin,
    RD.MinDaysSinceLastActivity AS DerretidoMin,
    RC.MinDaysSinceLastActivity AS CongeladoMin
FROM #PaisesAProcesar P
INNER JOIN #InsigniaTransitionRule RA
    ON RA.CountryId = P.CountryId
   AND RA.FromInsigniaId = @InsigniaImbatibleId
   AND RA.ToInsigniaId = @InsigniaAntojoId
   AND RA.IsActive = 1
INNER JOIN #InsigniaTransitionRule RD
    ON RD.CountryId = P.CountryId
   AND RD.FromInsigniaId = @InsigniaAntojoId
   AND RD.ToInsigniaId = @InsigniaDerretidoId
   AND RD.IsActive = 1
INNER JOIN #InsigniaTransitionRule RC
    ON RC.CountryId = P.CountryId
   AND RC.FromInsigniaId = @InsigniaDerretidoId
   AND RC.ToInsigniaId = @InsigniaCongeladoId
   AND RC.IsActive = 1
WHERE NOT
(
    RA.MinDaysSinceLastActivity <
    RD.MinDaysSinceLastActivity
    AND
    RD.MinDaysSinceLastActivity <
    RC.MinDaysSinceLastActivity
);


/* ================================================================================================
   PASO 6 - TABLA DESTINO SIMULADA
   ================================================================================================ */

CREATE TABLE #CustomerInsigniaSimulada
(
    CustomerId                  UNIQUEIDENTIFIER NOT NULL,
    InsigniaId                  INT              NOT NULL,

    LastActivityDate            DATETIMEOFFSET   NULL,
    LastActivityType            VARCHAR(30)      NULL,

    CurrentInsigniaSinceDate    DATETIMEOFFSET   NOT NULL,
    InitializedDate             DATETIMEOFFSET   NOT NULL,

    WindowTransactionCount      INT              NOT NULL,
    UpdatedDate                 DATETIMEOFFSET   NOT NULL,
    IsActive                    BIT              NOT NULL,

    CONSTRAINT PK_TMP_CustomerInsignia
        PRIMARY KEY CLUSTERED (CustomerId)
);


/* ================================================================================================
   PASO 7 - VOLUMEN PRODUCTIVO
   ================================================================================================ */

PRINT '';
PRINT '=======================================================================';
PRINT 'VOLUMEN PRODUCTIVO';
PRINT '=======================================================================';


SELECT
    COUNT_BIG(*) AS TotalCustomers
FROM Sml.Customer;


SELECT
    COUNT_BIG(*) AS CustomersActivos
FROM Sml.Customer
WHERE DeativatedDate IS NULL;


SELECT
    Country_Id AS CountryId,
    COUNT_BIG(*) AS SociosActivos
FROM Sml.Customer
WHERE DeativatedDate IS NULL
GROUP BY Country_Id
ORDER BY Country_Id;


SELECT
    COUNT_BIG(*) AS TotalVentas
FROM Sml.Sale;


SELECT
    COUNT_BIG(*) AS VentasValidasHistoricas
FROM Sml.Sale
WHERE CustomerId IS NOT NULL
  AND InvalidatedPointsLogId IS NULL
  AND SaleDate < @AsOfDate;


SELECT
    COUNT_BIG(*) AS VentasAnuladasHistoricas
FROM Sml.Sale
WHERE CustomerId IS NOT NULL
  AND InvalidatedPointsLogId IS NOT NULL
  AND SaleDate < @AsOfDate;


/* ================================================================================================
   PASO 8 - CREAR FRANJAS DE DOWNGRADE POR PAÍS

   Replica exactamente la diferencia principal de V3:

       PARTITION BY CountryId
   ================================================================================================ */

SELECT
    CountryId,
    FromInsigniaId,
    ToInsigniaId,
    MinDaysSinceLastActivity,

    LEAD
    (
        MinDaysSinceLastActivity,
        1,
        999999
    )
    OVER
    (
        PARTITION BY CountryId
        ORDER BY MinDaysSinceLastActivity
    ) - 1 AS MaxDaysCalculated

INTO #ReglasDowngrade

FROM #InsigniaTransitionRule

WHERE TransitionType = 'DOWNGRADE'
  AND FromInsigniaId <> @InsigniaNuevoId
  AND MinDaysSinceLastActivity IS NOT NULL
  AND MinDaysSinceLastActivity > 0
  AND IsActive = 1;


CREATE NONCLUSTERED INDEX IX_TMP_ReglasDowngrade_Country_MinDays
ON #ReglasDowngrade
(
    CountryId,
    MinDaysSinceLastActivity
);


PRINT '';
PRINT '--- FRANJAS DE DOWNGRADE POR PAIS ---';

SELECT
    RD.CountryId,
    FI.Code AS FromInsignia,
    TI.Code AS ToInsignia,
    RD.MinDaysSinceLastActivity,
    RD.MaxDaysCalculated
FROM #ReglasDowngrade RD
LEFT JOIN #Insignia FI
    ON FI.Id = RD.FromInsigniaId
LEFT JOIN #Insignia TI
    ON TI.Id = RD.ToInsigniaId
ORDER BY
    RD.CountryId,
    RD.MinDaysSinceLastActivity;


/* ================================================================================================
   PASO 9 - ÚLTIMA VENTA VÁLIDA HISTÓRICA

   Replica:
       MAX(SaleDate)
       GROUP BY CustomerId

   y luego localiza el ticket exacto por fecha + mayor Id.
   ================================================================================================ */

PRINT '';
PRINT '=======================================================================';
PRINT 'CALCULO ULTIMA VENTA VALIDA';
PRINT '=======================================================================';

DECLARE @InicioUltimaVenta DATETIME2 = SYSDATETIME();


;WITH UltimaVentaFecha AS
(
    SELECT
        CustomerId,
        MAX(SaleDate) AS LastDate

    FROM Sml.Sale

    WHERE CustomerId IS NOT NULL
      AND InvalidatedPointsLogId IS NULL
      AND SaleDate < @AsOfDate

    GROUP BY CustomerId
)

SELECT
    U.CustomerId,
    U.LastDate AS LastActivityDate,

    (
        SELECT TOP 1
            S.Id

        FROM Sml.Sale S

        WHERE S.CustomerId = U.CustomerId
          AND S.SaleDate = U.LastDate
          AND S.InvalidatedPointsLogId IS NULL
          AND S.SaleDate < @AsOfDate

        ORDER BY S.Id DESC

    ) AS LastSaleId

INTO #UltimaVenta

FROM UltimaVentaFecha U;


DECLARE @FinUltimaVenta DATETIME2 = SYSDATETIME();


CREATE UNIQUE CLUSTERED INDEX IX_TMP_UltimaVenta_CustomerId
ON #UltimaVenta(CustomerId);


SELECT
    COUNT_BIG(*) AS SociosConVentaValida,
    DATEDIFF
    (
        MILLISECOND,
        @InicioUltimaVenta,
        @FinUltimaVenta
    ) AS TiempoUltimaVentaMs
FROM #UltimaVenta;


/* ================================================================================================
   PASO 10 - PURCHASE / EXCHANGE
   ================================================================================================ */

PRINT '';
PRINT '=======================================================================';
PRINT 'CLASIFICACION DE ACTIVIDAD';
PRINT '=======================================================================';

DECLARE @InicioActividad DATETIME2 = SYSDATETIME();


SELECT
    U.CustomerId,
    U.LastActivityDate,
    U.LastSaleId,

    CASE
        WHEN EXISTS
        (
            SELECT 1
            FROM Sml.SalePromotion SP
            INNER JOIN Sml.Promotion P
                ON P.Id = SP.PromotionId
            WHERE SP.SaleId = U.LastSaleId
              AND P.Points < 0
        )
        THEN 'EXCHANGE'
        ELSE 'PURCHASE'
    END AS LastActivityType

INTO #Actividad

FROM #UltimaVenta U;


DECLARE @FinActividad DATETIME2 = SYSDATETIME();


CREATE UNIQUE CLUSTERED INDEX IX_TMP_Actividad_CustomerId
ON #Actividad(CustomerId);


SELECT
    LastActivityType,
    COUNT_BIG(*) AS Cantidad
FROM #Actividad
GROUP BY LastActivityType;


SELECT
    DATEDIFF
    (
        MILLISECOND,
        @InicioActividad,
        @FinActividad
    ) AS TiempoClasificacionActividadMs;


/* ================================================================================================
   PASO 11 - INSERT SIMULADO V3

   Replica la lógica productiva de V3:

   - Sin ventas -> SIEMPRE NUEVO.
   - Con ventas -> reglas correspondientes al CountryId.
   - No participa NUEVO -> CONGELADO.
   ================================================================================================ */

PRINT '';
PRINT '=======================================================================';
PRINT 'INICIO INSERT SIMULADO V3';
PRINT '=======================================================================';

DECLARE @InicioInsert DATETIME2 = SYSDATETIME();


;WITH ClienteInactividad AS
(
    SELECT
        C.Id AS CustomerId,
        C.Country_Id AS CountryId,
        C.CreatedDate,

        A.LastActivityDate,
        A.LastActivityType,

        DATEDIFF
        (
            DAY,
            A.LastActivityDate,
            @AsOfDate
        ) AS DaysInactive

    FROM Sml.Customer C

    LEFT JOIN #Actividad A
        ON C.Id = A.CustomerId

    WHERE C.DeativatedDate IS NULL
)

INSERT INTO #CustomerInsigniaSimulada
(
    CustomerId,
    InsigniaId,
    LastActivityDate,
    LastActivityType,
    CurrentInsigniaSinceDate,
    InitializedDate,
    WindowTransactionCount,
    UpdatedDate,
    IsActive
)

SELECT

    CI.CustomerId,


    /* ============================================================================================
       1. INSIGNIA ASIGNADA
       ============================================================================================ */

    CASE

        /* V3: sin ventas válidas históricas => SIEMPRE NUEVO */
        WHEN CI.LastActivityDate IS NULL
            THEN @InsigniaNuevoId


        /* Compra reciente según umbral mínimo DEL PAÍS */
        WHEN CI.DaysInactive <
        (
            SELECT MIN(RD.MinDaysSinceLastActivity)
            FROM #ReglasDowngrade RD
            WHERE RD.CountryId = CI.CountryId
        )
        THEN @InsigniaImbatibleId


        /* Downgrade según franja DEL PAÍS */
        ELSE
        (
            SELECT TOP 1
                RD.ToInsigniaId

            FROM #ReglasDowngrade RD

            WHERE RD.CountryId = CI.CountryId
              AND CI.DaysInactive
                  BETWEEN RD.MinDaysSinceLastActivity
                      AND RD.MaxDaysCalculated
        )

    END AS AssignedInsigniaId,


    CI.LastActivityDate,

    CI.LastActivityType,


    /* ============================================================================================
       2. CURRENT INSIGNIA SINCE DATE
       ============================================================================================ */

    CASE

        /* V3: NUEVO desde CreatedDate */
        WHEN CI.LastActivityDate IS NULL
        THEN
            CASE
                WHEN CI.CreatedDate > @AsOfDate
                    THEN @AsOfDate
                ELSE CI.CreatedDate
            END


        /* IMBATIBLE desde última actividad */
        WHEN CI.DaysInactive <
        (
            SELECT MIN(RD.MinDaysSinceLastActivity)
            FROM #ReglasDowngrade RD
            WHERE RD.CountryId = CI.CountryId
        )
        THEN CI.LastActivityDate


        /* Downgrade: fecha exacta del umbral correspondiente al país */
        ELSE
        (
            SELECT TOP 1

                CASE
                    WHEN DATEADD
                    (
                        DAY,
                        RD.MinDaysSinceLastActivity,
                        CI.LastActivityDate
                    ) > @AsOfDate
                    THEN @AsOfDate

                    ELSE DATEADD
                    (
                        DAY,
                        RD.MinDaysSinceLastActivity,
                        CI.LastActivityDate
                    )
                END

            FROM #ReglasDowngrade RD

            WHERE RD.CountryId = CI.CountryId
              AND CI.DaysInactive
                  BETWEEN RD.MinDaysSinceLastActivity
                      AND RD.MaxDaysCalculated
        )

    END AS CurrentInsigniaSinceDate,


    @AsOfDate AS InitializedDate,

    0 AS WindowTransactionCount,

    @AsOfDate AS UpdatedDate,

    1 AS IsActive

FROM ClienteInactividad CI;


DECLARE @FinInsert DATETIME2 = SYSDATETIME();


/* ================================================================================================
   PASO 12 - RESULTADOS PRINCIPALES
   ================================================================================================ */

PRINT '';
PRINT '=======================================================================';
PRINT 'RESULTADOS DEL INSERT SIMULADO';
PRINT '=======================================================================';


SELECT
    COUNT_BIG(*) AS TotalRegistrosInsertadosSimulados,

    DATEDIFF
    (
        MILLISECOND,
        @InicioInsert,
        @FinInsert
    ) AS TiempoInsertSimuladoMs

FROM #CustomerInsigniaSimulada;


/* Distribución global */

SELECT
    I.Code AS Insignia,
    COUNT_BIG(*) AS Cantidad,

    CAST
    (
        COUNT_BIG(*) * 100.0 /
        NULLIF
        (
            (SELECT COUNT_BIG(*) FROM #CustomerInsigniaSimulada),
            0
        )
        AS DECIMAL(10,2)
    ) AS Porcentaje

FROM #CustomerInsigniaSimulada CI

LEFT JOIN #Insignia I
    ON I.Id = CI.InsigniaId

GROUP BY I.Code

ORDER BY Cantidad DESC;


/* Distribución POR PAÍS */

SELECT
    C.Country_Id AS CountryId,
    I.Code AS Insignia,
    COUNT_BIG(*) AS Cantidad

FROM #CustomerInsigniaSimulada CI

INNER JOIN Sml.Customer C
    ON C.Id = CI.CustomerId

LEFT JOIN #Insignia I
    ON I.Id = CI.InsigniaId

GROUP BY
    C.Country_Id,
    I.Code

ORDER BY
    C.Country_Id,
    I.Code;


/* ================================================================================================
   PASO 13 - CONTROLES ESPECÍFICOS DE V3
   ================================================================================================ */

PRINT '';
PRINT '=======================================================================';
PRINT 'CONTROLES DE CONSISTENCIA V3';
PRINT '=======================================================================';


/* Debe ser 0 */
SELECT
    COUNT_BIG(*) AS InsigniaNull
FROM #CustomerInsigniaSimulada
WHERE InsigniaId IS NULL;


/* Debe ser 0 */
SELECT
    COUNT_BIG(*) AS CurrentInsigniaSinceNull
FROM #CustomerInsigniaSimulada
WHERE CurrentInsigniaSinceDate IS NULL;


/* Debe ser 0 */
SELECT
    COUNT_BIG(*) AS CurrentInsigniaSinceFutura
FROM #CustomerInsigniaSimulada
WHERE CurrentInsigniaSinceDate > @AsOfDate;


/* Debe ser 0 */
SELECT
    COUNT_BIG(*) AS LastActivityPosteriorAlCorte
FROM #CustomerInsigniaSimulada
WHERE LastActivityDate >= @AsOfDate;


/* ================================================================================================
   CONTROL CRÍTICO V3:
   SOCIOS SIN VENTAS DEBEN QUEDAR SIEMPRE NUEVO
   Resultado esperado: 0.
   ================================================================================================ */

SELECT
    COUNT_BIG(*) AS SociosSinVentaQueNoQuedaronNuevo

FROM #CustomerInsigniaSimulada CI

WHERE CI.InsigniaId <> @InsigniaNuevoId

  AND NOT EXISTS
  (
      SELECT 1
      FROM Sml.Sale S
      WHERE S.CustomerId = CI.CustomerId
        AND S.InvalidatedPointsLogId IS NULL
        AND S.SaleDate < @AsOfDate
  );


/* Detalle si apareciera algún caso incorrecto */

SELECT TOP 100
    CI.CustomerId,
    C.Country_Id AS CountryId,
    I.Code AS InsigniaAsignada,
    CI.LastActivityDate,
    CI.CurrentInsigniaSinceDate

FROM #CustomerInsigniaSimulada CI

INNER JOIN Sml.Customer C
    ON C.Id = CI.CustomerId

LEFT JOIN #Insignia I
    ON I.Id = CI.InsigniaId

WHERE CI.InsigniaId <> @InsigniaNuevoId

  AND NOT EXISTS
  (
      SELECT 1
      FROM Sml.Sale S
      WHERE S.CustomerId = CI.CustomerId
        AND S.InvalidatedPointsLogId IS NULL
        AND S.SaleDate < @AsOfDate
  );


/* ================================================================================================
   PASO 14 - SOCIOS NUEVO POR ANTIGÜEDAD

   Esto sirve para verificar una diferencia clave con V2:
   aunque tengan años sin comprar, permanecen NUEVO durante la carga inicial.
   ================================================================================================ */

SELECT

    CASE
        WHEN DATEDIFF(DAY, C.CreatedDate, @AsOfDate) < 30
            THEN '0-29 dias'

        WHEN DATEDIFF(DAY, C.CreatedDate, @AsOfDate) < 365
            THEN '30-364 dias'

        WHEN DATEDIFF(DAY, C.CreatedDate, @AsOfDate) < 730
            THEN '1-2 años'

        ELSE '2+ años'
    END AS AntiguedadSinVenta,

    COUNT_BIG(*) AS Cantidad

FROM #CustomerInsigniaSimulada CI

INNER JOIN Sml.Customer C
    ON C.Id = CI.CustomerId

WHERE CI.InsigniaId = @InsigniaNuevoId

GROUP BY

    CASE
        WHEN DATEDIFF(DAY, C.CreatedDate, @AsOfDate) < 30
            THEN '0-29 dias'

        WHEN DATEDIFF(DAY, C.CreatedDate, @AsOfDate) < 365
            THEN '30-364 dias'

        WHEN DATEDIFF(DAY, C.CreatedDate, @AsOfDate) < 730
            THEN '1-2 años'

        ELSE '2+ años'
    END;


/* ================================================================================================
   PASO 15 - DISTRIBUCIÓN DE INACTIVIDAD DE SOCIOS CON VENTA
   ================================================================================================ */

SELECT

    C.Country_Id AS CountryId,

    CASE
        WHEN DATEDIFF(DAY, CI.LastActivityDate, @AsOfDate) <= 30
            THEN '0-30'

        WHEN DATEDIFF(DAY, CI.LastActivityDate, @AsOfDate) <= 50
            THEN '31-50'

        WHEN DATEDIFF(DAY, CI.LastActivityDate, @AsOfDate) <= 120
            THEN '51-120'

        ELSE '121+'
    END AS RangoInactividad,

    COUNT_BIG(*) AS Cantidad

FROM #CustomerInsigniaSimulada CI

INNER JOIN Sml.Customer C
    ON C.Id = CI.CustomerId

WHERE CI.LastActivityDate IS NOT NULL

GROUP BY

    C.Country_Id,

    CASE
        WHEN DATEDIFF(DAY, CI.LastActivityDate, @AsOfDate) <= 30
            THEN '0-30'

        WHEN DATEDIFF(DAY, CI.LastActivityDate, @AsOfDate) <= 50
            THEN '31-50'

        WHEN DATEDIFF(DAY, CI.LastActivityDate, @AsOfDate) <= 120
            THEN '51-120'

        ELSE '121+'
    END

ORDER BY
    C.Country_Id,
    RangoInactividad;


/* ================================================================================================
   PASO 16 - ÍNDICES REALES DE TABLAS CRÍTICAS
   ================================================================================================ */

PRINT '';
PRINT '=======================================================================';
PRINT 'INDICES PRODUCTIVOS';
PRINT '=======================================================================';


PRINT '';
PRINT '--- Sml.Sale ---';

EXEC sp_helpindex 'Sml.Sale';


PRINT '';
PRINT '--- Sml.Customer ---';

EXEC sp_helpindex 'Sml.Customer';


PRINT '';
PRINT '--- Sml.SalePromotion ---';

EXEC sp_helpindex 'Sml.SalePromotion';


/* ================================================================================================
   PASO 17 - RESUMEN DE TIEMPOS
   ================================================================================================ */

DECLARE @FinTotal DATETIME2 = SYSDATETIME();


PRINT '';
PRINT '=======================================================================';
PRINT 'RESUMEN DE TIEMPOS';
PRINT '=======================================================================';


SELECT
    DATEDIFF
    (
        MILLISECOND,
        @InicioUltimaVenta,
        @FinUltimaVenta
    ) AS UltimaVentaMs,

    DATEDIFF
    (
        MILLISECOND,
        @InicioActividad,
        @FinActividad
    ) AS ClasificacionActividadMs,

    DATEDIFF
    (
        MILLISECOND,
        @InicioInsert,
        @FinInsert
    ) AS InsertSimuladoMs,

    DATEDIFF
    (
        MILLISECOND,
        @InicioTotal,
        @FinTotal
    ) AS TotalDiagnosticoMs;


/* ================================================================================================
   PASO 18 - LIMPIEZA
   ================================================================================================ */

DROP TABLE #CustomerInsigniaSimulada;
DROP TABLE #Actividad;
DROP TABLE #UltimaVenta;
DROP TABLE #ReglasDowngrade;
DROP TABLE #InsigniaTransitionRule;
DROP TABLE #PaisesAProcesar;
DROP TABLE #Insignia;


SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
SET NOEXEC OFF;


PRINT '';
PRINT '=======================================================================';
PRINT 'FIN DEL DIAGNOSTICO V3';
PRINT 'NO SE MODIFICARON TABLAS FUNCIONALES';
PRINT '=======================================================================';
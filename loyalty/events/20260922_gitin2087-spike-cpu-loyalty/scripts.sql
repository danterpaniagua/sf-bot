-- Event: 20260922_gitin2087-spike-cpu-loyalty (GITIN-2087)

-- Q1 — confirmar recurrencia del patrón ASYNC_NETWORK_IO de mayo (2026-05-18)
USE PNSSRL;
SELECT *
FROM PNSSRL_AuditSysprocesses
WHERE fecha_hora_captura BETWEEN '2026-09-21 19:30:00' AND '2026-09-21 20:30:00'
  AND lastwaittype LIKE '%ASYNC_NETWORK%';
-- Resultado: data/webs_asyncnetworkio_20260921.txt

-- Q2 — cuantificar CPU total por wait type y host en la misma ventana
USE PNSSRL;
SELECT hostname, lastwaittype, status, SUM(cpu) AS cpu_total
FROM PNSSRL_AuditSysprocesses
WHERE fecha_hora_captura BETWEEN '2026-09-21 19:30:00' AND '2026-09-21 20:30:00'
GROUP BY hostname, lastwaittype, status
ORDER BY cpu_total DESC;
-- Resultado: data/webs_asyncnetworkio_20260921.txt

-- Q3 — obtener un ValidToDate real para usar como parámetro de prueba
USE [SmartFran.Solution.SmartLoyalty];
SELECT TOP 1 ValidToDate
FROM Sml.Promotion
WHERE ActivatedDate IS NOT NULL AND DeactivatedDate IS NULL AND ValidToDate IS NOT NULL
ORDER BY ValidToDate DESC;
-- Resultado: 2036-03-31 00:00:00.000

-- Q4 — query responsable, SIN paginado (baseline, tal como se captura en producción)
USE [SmartFran.Solution.SmartLoyalty];
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
DECLARE @p0 bit = 1;
DECLARE @p1 datetime2(7) = '2036-03-31 00:00:00.000';
SELECT [Project1].*
FROM (
    SELECT [Extent1].*
    FROM [Sml].[Promotion] AS [Extent1]
    WHERE (@p0 = 1) AND ([Extent1].[ActivatedDate] IS NOT NULL) AND ([Extent1].[DeactivatedDate] IS NULL) AND (@p1 <= [Extent1].[ValidToDate])
) AS [Project1]
ORDER BY row_number() OVER (ORDER BY [Project1].[Id] ASC)
OFFSET 0 ROWS FETCH NEXT 2147483647 ROWS ONLY;
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
-- Resultado: data/query_fix_validation_20260923.txt — 1 fila, 875 logical reads, 3ms

-- Q5 — misma query, CON paginado real (OFFSET/FETCH), para comparar
USE [SmartFran.Solution.SmartLoyalty];
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
DECLARE @p0 bit = 1;
DECLARE @p1 datetime2(7) = '2036-03-31 00:00:00.000';
DECLARE @PageSize INT = 50;
DECLARE @PageIndex INT = 0;
SELECT [Project1].*
FROM (
    SELECT [Extent1].*
    FROM [Sml].[Promotion] AS [Extent1]
    WHERE (@p0 = 1) AND ([Extent1].[ActivatedDate] IS NOT NULL) AND ([Extent1].[DeactivatedDate] IS NULL) AND (@p1 <= [Extent1].[ValidToDate])
) AS [Project1]
ORDER BY row_number() OVER (ORDER BY [Project1].[Id] ASC)
OFFSET (@PageIndex * @PageSize) ROWS FETCH NEXT @PageSize ROWS ONLY;
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
-- Resultado: data/query_fix_validation_20260923.txt — 1 fila, 875 logical reads, 4ms
-- (idéntico a Q4 — el paginado no redujo el costo de lectura)

-- Q6 — escala real de la tabla de soporte SmlSupp.PromotionBranchOffice
USE [SmartFran.Solution.SmartLoyalty];
SELECT COUNT(*) AS total_rows,
       COUNT(DISTINCT PromotionId) AS distinct_promotions,
       COUNT(DISTINCT BranchOfficeId) AS distinct_branch_offices
FROM SmlSupp.PromotionBranchOffice;
-- Resultado: data/promotionbranchoffice_scale_20260923.txt — 24.978.810 filas

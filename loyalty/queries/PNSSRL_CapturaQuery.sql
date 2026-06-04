-- Job:      PNSSRL_CapturaQuery
-- Step:     Step1
-- Database: master
-- Status:   enabled
-- WARNING:  Hardcoded file path filter — captures 0 rows if application path changes

INSERT INTO PNSSRL.dbo.PNSSRL_CapturaQuery (cant, text, last_execution_time)
SELECT DISTINCT
    qs.execution_count                                  AS cant,
    qt.text,
    CONVERT(VARCHAR(19), qs.last_execution_time, 121)   AS last_execution_time
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS qt
WHERE qt.text LIKE '(@p0 nvarchar(36))-- ContentResource: file:\C:\Smartfran\SmartLoyalty.WebSite\bin\Domain\Query\Query078-sql.xml%'
ORDER BY qs.execution_count DESC

-- Job:      PNSSRL_CapturaCheckDB
-- Step:     Step1
-- Database: master
-- Status:   enabled
-- Schedule: weekly at 07:00 (server is UTC+3 relative to Argentina)
-- Runs DBCC CHECKDB on all non-system databases

DECLARE @DB SYSNAME

DECLARE cDatabases CURSOR FOR
    SELECT name
    FROM sys.sysdatabases
    WHERE name NOT IN ('master', 'model', 'tempdb')
    ORDER BY name

OPEN cDatabases
    FETCH FROM cDatabases INTO @DB
    WHILE (@@FETCH_STATUS = 0)
    BEGIN
        EXEC ('DBCC CHECKDB(''' + @DB + ''') WITH ALL_ERRORMSGS')
        FETCH FROM cDatabases INTO @DB
    END
CLOSE cDatabases
DEALLOCATE cDatabases

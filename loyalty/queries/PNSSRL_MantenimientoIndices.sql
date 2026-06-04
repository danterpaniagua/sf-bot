-- Job:      PNSSRL_MantenimientoIndices
-- Database: PNSSRL / msdb
-- Status:   enabled

-- ============================================================
-- Step 1: Index maintenance — all modules
-- ============================================================
USE PNSSRL
GO

DECLARE @base      VARCHAR(100) = NULL
DECLARE @modulo    VARCHAR(100) = NULL
DECLARE @tabla     VARCHAR(100) = NULL
DECLARE @fillfactor TINYINT     = NULL

EXEC PNSSRL_MantenimientoModulos @base, @modulo, @tabla, @fillfactor

GO

-- ============================================================
-- Step 2: Restart Backup_Log if not already running/retrying
-- ============================================================
USE msdb
GO

IF NOT EXISTS (
    SELECT j.name, h.run_status
    FROM msdb.dbo.sysjobs          j
    INNER JOIN msdb.dbo.sysjobhistory h ON j.job_id = h.job_id
    WHERE j.enabled = 1
      AND j.name = 'Operaciones_MaintenancePlan_Backups.Backup_Log'
      AND h.run_status IN (2, 4)  -- 2=Retry, 4=In progress
)
    EXEC dbo.sp_start_job N'Operaciones_MaintenancePlan_Backups.Backup_Log'

GO

-- ============================================================
-- Step 3: Purge PNSSRL_DetallesEjecucionTablasModulos (>20 days)
-- ============================================================
USE PNSSRL
GO

SET ROWCOUNT 5000
SET NOCOUNT ON

SELECT 1
WHILE @@ROWCOUNT <> 0
BEGIN
    WAITFOR DELAY '00:00:00.100'
    DELETE FROM PNSSRL.[dbo].[PNSSRL_DetallesEjecucionTablasModulos]
    WHERE fecha_hora_captura < DATEADD(DAY, -20, GETDATE())
END

SET ROWCOUNT 0
SET NOCOUNT OFF

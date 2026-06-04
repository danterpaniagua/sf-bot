-- Job:      PNSSRL - Depura Tabla Captura Tempdb
-- Database: PNSSRL
-- Status:   enabled
-- Retention: 90 days on all three tables
-- WARNING:  Step 3 purges PNSSRL_Usage_CpuMemory whose feeder job is DISABLED

-- ============================================================
-- Step 1: Depura Tabla - TempdbProc
-- ============================================================
WHILE 1 = 1
BEGIN
    ;WITH CTE AS
    (
        SELECT TOP 1000 *
        FROM [dbo].[PNSSRL_TempdbProc]
        WHERE hora_captura < GETDATE() - 90
    )
    DELETE FROM CTE;

    IF @@ROWCOUNT = 0 BREAK;
END;

GO

-- ============================================================
-- Step 2: Depura Tabla - PNSSRL_AuditSysprocesses
-- ============================================================
WHILE 1 = 1
BEGIN
    ;WITH CTE AS
    (
        SELECT TOP 1000 *
        FROM [dbo].[PNSSRL_AuditSysprocesses]
        WHERE fecha_hora_captura < GETDATE() - 90
    )
    DELETE FROM CTE;

    IF @@ROWCOUNT = 0 BREAK;
END;

GO

-- ============================================================
-- Step 3: Depura Tabla - PNSSRL_Usage_CpuMemory
-- ============================================================
WHILE 1 = 1
BEGIN
    ;WITH CTE AS
    (
        SELECT TOP 1000 *
        FROM [dbo].[PNSSRL_Usage_CpuMemory]
        WHERE fecha_hora_captura < GETDATE() - 90
    )
    DELETE FROM CTE;

    IF @@ROWCOUNT = 0 BREAK;
END;

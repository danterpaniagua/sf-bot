/* =====================================================================================
   GITIN-2132 - Backup completo de SmartFran.Solution.SmartLoyalty (SFCG-DB01)
   PARTE A: verificaciones de SOLO LECTURA.
   PARTE B: BACKUP A AZURE BLOB (modifica estado: escribe un blob en el contenedor de backups).
   Guardar Results + Messages en data/.
   Revisión 2026-10-01: la Parte B original escribía en la ruta local por defecto (C:) y se descartó;
   los backups de esta instancia van a https://strgsqlbkp.blob.core.windows.net/sfcgvm07-mssqlserver
   (credencial SAS con el nombre de la URL del contenedor, ya existente).
   ===================================================================================== */

/* ---------------------------------- PARTE A (solo lectura) ---------------------------------- */
SET NOCOUNT ON;

-- A1. Servidor, base, modelo de recuperación y ruta de backup por defecto de la instancia
SELECT @@SERVERNAME AS Servidor, DB_NAME() AS BaseActual,
       (SELECT recovery_model_desc FROM sys.databases WHERE name = DB_NAME()) AS ModeloRecuperacion,
       CONVERT(nvarchar(260), SERVERPROPERTY('InstanceDefaultBackupPath')) AS RutaBackupPorDefecto,
       SYSDATETIMEOFFSET() AS Ahora;

-- A2. Tamaño de la base (datos + log) en GB (asignado)
SELECT type_desc, CAST(SUM(size) * 8.0 / 1024 / 1024 AS DECIMAL(12,2)) AS TamanoGB
FROM sys.database_files GROUP BY type_desc;

-- A3. Últimos backups COMPLETOS (tipo D): destino, tamaño y duración
SELECT TOP 5 bs.backup_start_date, bs.backup_finish_date,
       DATEDIFF(MINUTE, bs.backup_start_date, bs.backup_finish_date) AS DuracionMin,
       bs.type, bs.is_copy_only,
       CAST(bs.backup_size / 1073741824.0 AS DECIMAL(12,2)) AS TamanoGB,
       CAST(bs.compressed_backup_size / 1073741824.0 AS DECIMAL(12,2)) AS ComprimidoGB,
       bmf.physical_device_name
FROM msdb.dbo.backupset bs
INNER JOIN msdb.dbo.backupmediafamily bmf ON bmf.media_set_id = bs.media_set_id
WHERE bs.database_name = DB_NAME() AND bs.type = 'D'
ORDER BY bs.backup_start_date DESC;

-- A4. Credenciales existentes (solo nombre e identidad, sin secretos)
SELECT name, credential_identity FROM sys.credentials;

/* ---------------------------------- PARTE B (BACKUP A URL) ---------------------------------- */
-- COPY_ONLY: no altera la base diferencial ni la cadena de logs de los jobs del plan de mantenimiento.
-- El backup completo programado comprime a ~111 GB en un solo blob (MAXTRANSFERSIZE de 4 MB permite hasta ~200 GB por blob).
DECLARE @sello nvarchar(20)  = FORMAT(SYSUTCDATETIME(), 'yyyyMMdd_HHmmss');
DECLARE @url   nvarchar(400) = N'https://strgsqlbkp.blob.core.windows.net/sfcgvm07-mssqlserver/'
                             + N'SmartFran.Solution.SmartLoyalty_FULL_COPYONLY_GITIN2132_' + @sello + N'.bak';
PRINT 'Destino del backup: ' + @url;

BACKUP DATABASE [SmartFran.Solution.SmartLoyalty]
TO URL = @url
WITH COPY_ONLY, COMPRESSION, CHECKSUM, MAXTRANSFERSIZE = 4194304, STATS = 5,
     NAME = N'SmartLoyalty FULL COPY_ONLY GITIN-2132';

-- Verificación del blob recién creado (lee el backup y valida checksums; no restaura)
RESTORE VERIFYONLY FROM URL = @url WITH CHECKSUM;

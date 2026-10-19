-- Event: 20261014_gitin2223_taskoperator-preprod-appsettings-xml (GITIN-2223)
-- C14 - CAMBIA ESTADO (UPDATE sobre Sch.Task de PREPROD). No ejecutar sin confirmar el entorno. Solo se entrega al usuario si lo pide.
--       Adelanta la proxima corrida del job ETL 7965 (tarea 139104, hoy programada 2026-10-15 10:00 -03:00) a ahora + 2 minutos,
--       para ver ya el resultado de la entrada EtlContext agregada a las 14:16 UTC en lugar de esperar a manana 13:00 UTC.
--       Guarda: solo toca la fila si sigue sin iniciar y con su ExecuteOn original. La reversion devuelve el ExecuteOn original
--       (solo si la tarea todavia no inicio). Mismo tipo de cambio que hizo QA con la tarea 139102.
USE [SmartFran.Solution.SmartLoyalty-PREPROD];
GO
-- antes
SELECT Id, JobId, ExecuteOn, ExecutionStarted, Done, Failed FROM Sch.Task WHERE Id = 139104;
GO
-- cambio
UPDATE Sch.Task SET ExecuteOn = DATEADD(MINUTE, 2, SYSDATETIMEOFFSET())
WHERE Id = 139104 AND JobId = 7965 AND ExecutionStarted IS NULL AND Done IS NULL AND ExecuteOn = '2026-10-15 10:00:00.0000000 -03:00';
SELECT @@ROWCOUNT AS filas_modificadas;  -- debe ser 1
GO
-- despues
SELECT Id, JobId, ExecuteOn, ExecutionStarted, Done, Failed FROM Sch.Task WHERE Id = 139104;
GO
-- REVERSION (solo si la tarea todavia no inicio):
-- UPDATE Sch.Task SET ExecuteOn = '2026-10-15 10:00:00.0000000 -03:00' WHERE Id = 139104 AND JobId = 7965 AND ExecutionStarted IS NULL;

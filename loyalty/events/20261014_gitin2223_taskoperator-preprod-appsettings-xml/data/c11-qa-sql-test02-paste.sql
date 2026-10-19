-- Pegado por el usuario el 2026-10-14: el mismo procedimiento en TEST02, que segun el usuario funciona (solo las sentencias; no se pego el resultado).
SELECT TOP (1000) [Id]
      ,[ExecuteOn]
      ,[ExecutionStarted]
      ,[Done]
      ,[DeactivatedDate]
      ,[DeactivateNote]
      ,[TimeTableId]
      ,[Failed]
      ,[JobId]
      ,[CanceledDate]
      ,[CanceledNote]
  FROM [SmartFran.Solution.SmartLoyalty-TEST02].[Sch].[Task]
  where jobid= 8529
  ORDER BY 1 DESC

  update [SmartFran.Solution.SmartLoyalty-TEST02].[Sch].[Task]
  set ExecuteOn='2026-10-14 10:44:00.0000000 -03:00' 
  where id=196433

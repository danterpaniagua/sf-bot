-- Pegado por el usuario el 2026-10-14: SQL que corrio QA contra PREPROD (solo las sentencias; no se pego el resultado de la consulta).
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
  FROM [SmartFran.Solution.SmartLoyalty-PREPROD].[Sch].[Task]
  where jobid=7996
  ORDER BY 1 DESC

  update [SmartFran.Solution.SmartLoyalty-PREPROD].[Sch].[Task]
  set ExecuteOn='2026-10-14 10:45:00.0000000 -03:00' 
  where id=139102

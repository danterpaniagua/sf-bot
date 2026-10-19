Asunto: [SML] Mobile: episodio del 15-10 por la mañana — hallazgos preliminares

Hola,

Les compartimos lo que encontramos sobre el episodio más corto que Grido informó el 15-10 por la mañana, antes de la caída posterior de ese mismo día ([GITIN-2238](https://smartit-ar.atlassian.net/browse/GITIN-2238)). El detalle está en [GITIN-2241](https://smartit-ar.atlassian.net/browse/GITIN-2241). Horarios en hora de Argentina (UTC−3).

*Qué observamos:*

   - Nuestro monitoreo registró fallas en el inicio de sesión de Mobile entre las 06:15 y las 06:56, unos 41 minutos, y el servicio se recuperó solo. Coincide con la franja que informó Grido (06:14 a 06:55).
   - Durante esa franja la verificación de estado del servicio siguió respondiendo con normalidad; lo que no respondía era el inicio de sesión. El control de disponibilidad del balanceador de carga tampoco registró caída en esa franja.
   - En esa franja Mobile funcionaba con un solo servidor por el apagado programado del otro (dato informado; las métricas de Azure muestran el otro servidor sin actividad entre las 01:05 y las 08:45).

*Qué coincide con el episodio:*

   - A las 06:15 corre una tarea programada de mantenimiento de la base de datos de SmartLoyalty (los lunes, martes, jueves y sábados). El 15-10 se ejecutó de 06:15 a 06:57, y el fin de las fallas coincide con el fin de la tarea.
   - Durante esos minutos, la base de datos registró decenas de consultas esperando sobre la tabla que esa tarea reconstruye.
   - En la semana revisada hubo fallas en los cuatro días con tarea programada y ninguna en los tres días sin ella. La duración de las fallas varió entre 3 y 41 minutos según el día.

   Consulta de la tarea involucrada: `ALTER INDEX [IX_CustomerId] ON [Sml].[CustomerPointsLog] REBUILD PARTITION = @PartitionNumber;`. Origen: trabajo del agente de SQL Server (`SQLAgent - TSQL JobStep (Job 0x7014325CA61B284982001445D05AC776 : Step 1)`) en el servidor de base de datos de SmartLoyalty; el usuario con el que se ejecuta no figura en lo que revisamos.

*Qué todavía no está comprobado:*

   - Que esa tarea sea la causa: es una coincidencia de horarios y de la tabla bloqueada, pero no probamos que el inicio de sesión espere sobre esa misma tabla.
   - Qué mantenía bloqueada a la propia tarea durante esos minutos.
   - Por qué la duración de las fallas cambia de un día a otro.

*Próximos pasos:*

   - Seguimos verificando si el inicio de sesión espera sobre esa tabla y qué mantenía bloqueada a la tarea.

Más información en [GITIN-2241](https://smartit-ar.atlassian.net/browse/GITIN-2241).

Saludos.

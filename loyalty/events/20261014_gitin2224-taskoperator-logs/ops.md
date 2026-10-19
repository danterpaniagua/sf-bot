# GITIN-2224 — [SML] Task Operator Logs

**Tags:** SmartLoyalty, TaskOperator

## Resumen

Subtarea de [GITIN-2223](https://smartit-ar.atlassian.net/browse/GITIN-2223) (TaskOperator de PREPROD sin ejecutar tareas). Por falta de logs fue difícil detectar los problemas de GITIN-2223. El síntoma era que TaskOperator de PREPROD no ejecutaba tareas, y ningún registro del servicio permitía distinguir si el servicio estaba detenido, si la tarea todavía no estaba vencida o si la fila estaba bloqueada: la prueba de QA (una tarea cuyo `ExecuteOn` se movió y que no se ejecutó, con el cambio invisible desde otras sesiones, posiblemente por una transacción abierta sin `COMMIT`) se reconstruyó consultando `Sch.Task`, el inicio del proceso del servicio y las sesiones de SQL Server, y se resolvió con un reinicio de SFDEV02. Además, un job ETL falló en las 445 corridas que tuvo en PREPROD entre 2025-01-21 y 2026-10-14 sin que quedara registrado el motivo en la base ni en un log que se haya podido consultar, y la falla de arranque del servicio por un comentario XML inválido solo se conoció por el mensaje que mostró Windows. Se leyó el código de TaskOperatorService (rama `main`, commit aef06a72a del 2026-09-29; no se verificó que sea la versión desplegada en PREPROD) y se proponen diez mejoras de logging y monitoreo. No se implementó ningún cambio ni se ejecutó ningún comando contra sistemas para este ticket.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2224](https://smartit-ar.atlassian.net/browse/GITIN-2224) |
| Tickets relacionados | [GITIN-2223](https://smartit-ar.atlassian.net/browse/GITIN-2223) (ticket padre: TaskOperator de PREPROD) |
| Caso | Recomendación de nuevos logs para TaskOperator |
| Sistema | TaskOperatorService (Windows Service), SmartLoyalty; código en la rama `main` de la aplicación (commit aef06a72a) |
| Severidad | Por definir |
| Detectado | 2026-10-14, durante GITIN-2223 |
| Resuelto | No. Es una recomendación; no se modificó código ni configuración |
| Responsable | Dev (implementación); SRE (monitoreo y verificación) |

## Causa raíz

NA

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Logs propios del servicio: solo tres líneas (`Instancing Service`, `Starting Service`, `Stopping Service`). `OnStart` ejecuta la recuperación de tareas interrumpidas (`ServiceCrashed()`) de forma síncrona y sin `try/catch`; no registra cuántas tareas encontró ni qué hizo con cada una (el único rastro es la nota "Service crashed, task being reprogrammed." en la base y un correo a IT). El hilo principal no registra latidos ni iteraciones. | Alto |
| H2 | Las fallas de las tareas llegan por correo: el callback de `RunSchedule` envía correos al soporte y a IT con el texto de la excepción. Si la configuración de correo o el SMTP de un ambiente no funcionan, la falla no se ve; el código no registra si el correo se envió o falló. El texto de error de GITIN-2223 llegó en el formato que produce ese correo, pero no se verificó de dónde se leyó. | Alto |
| H3 | Una falla en una tarea no deja el motivo en la base: el job ETL `EtlDwGridoPointsTransferenceProcessor` figura con `Failed = 1` en `Sch.Task`, sin mensaje, y `Sch.TaskEvent` no guarda texto. Como la falla ocurre antes de crear la ejecución de la operación ETL, tampoco hay fila en `Etl.EtlOperationExecution`. En PREPROD fueron 445 corridas fallidas seguidas, de 43 a 74 s cada una, sin alerta. | Alto |
| H4 | Si el arranque falla, `Program.cs` escribe `Log.txt` en el directorio del servicio con `FileMode.Create`: cada falla sobrescribe la anterior; registra el mensaje y la traza de la excepción y solo un nivel de excepción interna, en UTF-16. Las excepciones lanzadas dentro de `OnStart` no pasan por ese `catch`. | Medio |
| H5 | `Logg` ignora silenciosamente las llamadas si el logger no se inicializó (`LoggerFactory.MainLogger?`). Dónde escribe el logger principal (archivo, Registro de eventos, otro destino) depende del proveedor y de `Config\SystemDiagnostics.config`; no se determinó en PREPROD ni en producción. | Medio |
| H6 | De los 44 archivos de procesadores en `Core/Application.TaskBridge/TaskProcess`, 27 no tienen ninguna llamada directa a `Logg`. El procesador ETL solo registra una advertencia cuando la operación no está activa; una falla en `GetActiveOperation` o `ExecuteOperation` sube a `RunSchedule` y termina en el correo. | Medio |
| H7 | La causa de GITIN-2223 (falta de la cadena de conexión de `EtlContext` en `ConnectionStrings.config` de PREPROD) se encontró tras unas diez consultas de lectura a la configuración, `Unity.config`, las tablas `Sch` y `Etl` y la comparación con TEST02. Un chequeo al inicio de los contextos registrados contra las cadenas disponibles la habría mostrado desde el primer día. | Informativo |
| H8 | Las reprogramaciones "Service crashed, task being reprogrammed." aparecen los lunes a las 09:03 UTC y en lotes (20 tareas el 14-10 entre las 02:06 y las 12:04 UTC) sin registro de la causa de cada inicio del servicio. | Medio |
| H9 | La prueba de QA de GITIN-2223 (cambio de `ExecuteOn` no visible, tarea sin ejecutar) no dejó ningún registro que distinguiera entre servicio detenido, tarea no vencida y fila bloqueada. El servicio no registra la duración de su consulta de tareas ejecutables ni de la actualización de cada tarea, ni por qué una tarea vencida no se toma. Si el servicio esperó por el bloqueo durante ese período no se sabe. | Medio |

No se leyó el código de las bibliotecas externas (`RunSchedule`, el envío de correo y el proveedor del logger), por lo que qué registran no se conoce.

## Recomendaciones

| # | Recomendación | Habría mostrado |
|---|---|---|
| R1 | Al iniciar, registrar una huella: versión y fecha de compilación del ensamblado, host, directorio base y, de cada archivo de `Config\`, nombre, fecha de modificación y un hash corto; leer cada `.config` y registrar cuál falla y en qué línea. Envolver `OnStart` en `try/catch`: registrar la cadena completa de excepciones en el logger y en el Registro de eventos de Windows y volver a lanzarla. | La falla del comentario XML al instante, con archivo y línea, y qué cambió en el despliegue del 13-10 |
| R2 | En `ServiceCrashed()`, registrar cuántas tareas hay en cada grupo (ejecutables, iniciadas válidas sin terminar, iniciadas inválidas sin terminar) y, por tarea, `JTS[job-tarea-paso]`, nombre del job, acción (cancelar, desactivar, reprogramar) y nueva fecha de ejecución; advertir cuando una tarea no pudo reprogramarse. | Por qué se desactivaron 20 tareas el 14-10 y el patrón de los lunes |
| R3 | Latido cada N minutos (por ejemplo 5): servicio vivo, tareas en ejecución, tareas vencidas sin iniciar y hora del último inicio de tarea; advertencia cuando hay tareas vencidas y ninguna inició en M minutos. | La pregunta "TaskOperator no ejecuta tareas" se respondía con una mirada al log |
| R4 | Por tarea: una línea `Info` al iniciar (`JTS`, nombre del job) y otra al terminar (duración, resultado), y un `Error` con la cadena completa de excepciones (tipo, mensaje, internas, traza) cuando falla, con el id de tarea en cada línea. Guardar también el texto del error en la base (mensaje en `TaskEvent` o una columna de `Sch.Task`) para que `Failed = 1` tenga motivo. | Las 445 fallas del job ETL, con un mensaje explícito en cada una |
| R5 | Al crear o resolver un contexto de Entity Framework, registrar qué cadena de conexión con nombre usa y su servidor y base (nunca usuario ni contraseña); si no existe una cadena con el nombre del contexto, fallar con un mensaje explícito ("no existe cadena de conexión X") en lugar de dejar el error del controlador. Al iniciar, comparar los contextos de `Unity.config` con los nombres de `ConnectionStrings.config` y advertir de los que falten. | La falta de la entrada de `EtlContext` el primer día (2025-01-21) |
| R6 | `Log.txt` de `Program.cs`: agregar en lugar de sobrescribir, escribir la cadena completa de excepciones internas, usar UTF-8 y rotar. | Fallas de arranque repetidas ya no se borrarían entre sí |
| R7 | No depender solo del correo: registrar "correo enviado" o "correo fallido" por cada notificación y enviar los mismos eventos al log central (Graylog) con campos de host y ambiente. | Un ambiente donde el correo no llega seguiría mostrando el error |
| R8 | No escribir nunca cadenas de conexión ni credenciales en ningún log (registrar solo servidor y base). | Evita exponer credenciales en los logs |
| R9 | Sin cambios de código: un monitoreo sobre `Sch.Task` para tareas vencidas por más de N minutos sin `ExecutionStarted`, y para jobs con `Failed = 1` en varias corridas seguidas, más una alerta cuando el servicio no tiene latido. | Las 445 fallas consecutivas habrían generado una alerta en la primera semana |
| R10 | En el ciclo de sondeo del planificador, registrar la duración de la consulta de tareas ejecutables y de la actualización de cada tarea al tomarla, con una advertencia si superan un umbral (espera por un bloqueo) y, cuando hay tareas vencidas que no se toman, el motivo (desactivada, cancelada, ya iniciada, fila bloqueada). | Por qué una tarea con `ExecuteOn` vencido no se ejecutaba, y si el servicio estuvo esperando un bloqueo |

## Recursos afectados

| Componente | Estado |
|---|---|
| TaskOperatorService (`Front/TaskOperatorService`, `Core/Application.TaskBridge`) | Sin cambios; es el objetivo de las recomendaciones R1 a R8 |
| Monitoreo de `Sch.Task` (Zabbix/Graylog) | No existe hoy; R9 |

## Comandos ejecutados

No se ejecutó ningún comando contra sistemas para este ticket; la evidencia proviene de la lectura del código de la aplicación (rama `main`, commit aef06a72a del 2026-09-29) y de las mediciones de GITIN-2223.

| # | Script | Propósito |
|---|---|---|
| C1 | `scripts/scripts.ps1` (preparado, no ejecutado) | Leer en PREPROD la configuración de diagnóstico, los archivos de log del servicio y los eventos del Registro de Windows para saber dónde escribe hoy el logger principal |

## Acciones propuestas

1. (Dev / SRE) Definir qué recomendaciones entran en el alcance y su prioridad; R9 no requiere código; R10 requiere un cambio en el ciclo de sondeo.
2. (SRE) Ejecutar C1 en PREPROD para conocer dónde escribe hoy el logger principal y si algo envía esos logs a Graylog (H5).
3. (SRE) Confirmar qué direcciones de correo y qué SMTP tiene configurados PREPROD y si los correos de error llegan a alguien (H2).
4. (Dev) Implementar R1 a R8 y R10 en TaskOperatorService y verificar contra la versión desplegada, ya que se leyó `main` y no se verificó que sea la desplegada.
5. (SRE) Implementar el monitoreo R9 sobre `Sch.Task` y la alerta de latido.
6. (Dev) Revisar el registro de las bibliotecas externas (`RunSchedule`, correo, proveedor del logger) para saber qué ya se registra.

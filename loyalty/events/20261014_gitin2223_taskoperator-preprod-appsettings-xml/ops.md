# GITIN-2223 — [SML] TO No funciona en PREPRO

**Tags:** SmartLoyalty, TaskOperator

## Resumen

TaskOperator de PREPROD (servicio `SmartLoyalty.TaskOperator.Service.Preprod`, host SFDEV02, base `SmartFran.Solution.SmartLoyalty-PREPROD`) no ejecutaba tareas. Para probarlo, QA modificó con un `UPDATE` el `ExecuteOn` de la tarea 139102 (job 7996), pero el cambio no se veía desde otras sesiones, un `UPDATE` de otra sesión sobre la misma fila dejaba colgado SSMS y la tarea no se ejecutó. El problema se resolvió reiniciando SFDEV02 (sistema y SQL Server se reiniciaron alrededor de las 15:49 UTC): después del reinicio el `UPDATE` se aplicó y la tarea se ejecutó a las 16:01 UTC. La explicación más consistente es una transacción abierta sin `COMMIT` (`BEGIN TRAN` o `IMPLICIT_TRANSACTIONS`) en la sesión de quien hizo el primer `UPDATE`: las bases SmartLoyalty de SFDEV02 leen con versionado de filas (`READ_COMMITTED_SNAPSHOT`), por lo que un `SELECT` muestra el último valor confirmado sin esperar, mientras que un segundo `UPDATE` de la misma fila espera el bloqueo. Esa primera ocurrencia no se pudo confirmar en el servidor, porque las sesiones de ese momento desaparecieron con el reinicio. El mismo cuadro se repitió esa tarde (QA actualizó el `ExecuteOn` de la tarea 139118 y el `UPDATE` de otra sesión sobre la misma tabla quedó colgado) y esta vez se capturó en el servidor: la sesión de una estación de QA mantenía una transacción abierta desde las 19:13 UTC con bloqueos exclusivos de fila, y el `UPDATE` esperó más de 13 minutos (`LCK_M_X`) detrás de ella. El bloqueo se liberó, sin reiniciar nada, cuando QA ejecutó `COMMIT`; QA tenía un `BEGIN TRAN` que no había visto (según lo informado por QA). El tamaño del log de transacciones se descartó como causa (2 % usado, nada lo retenía). Durante la investigación se encontraron además dos fallas independientes: un comentario XML inválido en `Config\AppSettings.config` que impidió el arranque del servicio hasta que se corrigió a mano a las 12:04 UTC, y el job ETL `EtlDwGridoPointsTransferenceProcessor`, que falló en las 445 corridas que tuvo en PREPROD (desde 2025-01-21) porque `Config\ConnectionStrings.config` no tenía la cadena de conexión de `EtlContext`; la entrada se agregó a las 14:16 UTC y una corrida forzada a las 15:07 UTC terminó sin error. Está pendiente verificar la primera corrida programada del job ETL (2026-10-15 13:00 UTC).

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2223](https://smartit-ar.atlassian.net/browse/GITIN-2223) |
| Tickets relacionados | [GITIN-2224](https://smartit-ar.atlassian.net/browse/GITIN-2224) (recomendación de logs de TaskOperator), [GITIN-2126](https://smartit-ar.atlassian.net/browse/GITIN-2126) (TaskOperator en SFDEV02: servicio y SQL Server local para test02 y preprod) |
| Caso | TaskOperator de PREPROD no ejecuta tareas; la actualización de QA no era visible |
| Base de datos | `SmartFran.Solution.SmartLoyalty-PREPROD` en SFDEV02 (también `SmartFran.Solution.SmartLoyalty-TEST02` para comparar) |
| Severidad | Por definir |
| Detectado | 2026-10-14 |
| Resuelto | Sí: tras el reinicio de SFDEV02 la actualización se aplicó y las tareas se ejecutan; falta verificar la primera corrida programada del job ETL (2026-10-15 13:00 UTC). La causa del cambio no visible y del `UPDATE` colgado (transacción abierta sin `COMMIT` en otra sesión) se confirmó en la segunda ocurrencia del 14-10 por la tarde (H9); en la primera ocurrencia sigue siendo la explicación más consistente |
| Responsable | SRE |

## Causa raíz

1. **La actualización de QA no se veía, el `UPDATE` de otra sesión quedaba colgado y la tarea no se ejecutaba: una transacción abierta sin `COMMIT`** (confirmada en la segunda ocurrencia, H9; en la primera, antes del reinicio de las 15:49 UTC, es la explicación más consistente pero no se capturó en el servidor): una sesión con un `BEGIN TRAN` sin cerrar mantiene bloqueos exclusivos de fila sobre `Sch.Task`; el cambio existe solo dentro de esa sesión, las lecturas de otras sesiones no esperan (`READ_COMMITTED_SNAPSHOT`) y muestran el valor anterior, y un `UPDATE` de otra sesión sobre la misma fila espera el bloqueo. En la segunda ocurrencia el dueño de la sesión ejecutó `COMMIT` y el bloqueo se liberó sin reiniciar. TaskOperator y el log de transacciones no intervinieron.
2. **El servicio no arrancaba hasta las 12:04 UTC** (confirmado): el comentario `<!-- 13/10/2026 --- v13.01.00 -->` en la línea 132 de `Config\AppSettings.config` contenía `---`; XML no admite `--` dentro de un comentario y el servicio no inició (mensaje informado: "An XML comment cannot contain '--', and '-' cannot be the last character. Line 132, position 18"). Quién o qué escribió esa línea no se determinó.
3. **El job ETL fallaba en cada corrida** (respaldado, falta la primera corrida programada): `Config\ConnectionStrings.config` de PREPROD tenía 7 entradas y no la de `SmartFran.Business.Etl.Data.Context.EtlContext`, presente en DEV y TEST02 (8 entradas); el acceso falló con "error: 26 - Error Locating Server/Instance Specified" tras cerca de un minuto. Respaldado por la comparación con TEST02 y por la corrida forzada exitosa tras agregar la entrada.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | El servicio dejó de arrancar por el comentario XML inválido en `Config\AppSettings.config` línea 132 (texto original informado: `<!-- 13/10/2026 --- v13.01.00 -->`). El archivo se reescribió el 14-10 a las 12:04:13 UTC y hoy se lee como XML válido; el servicio inició y a las 12:04:39 UTC recuperó tareas interrumpidas (nota "Service crashed, task being reprogrammed."). El resto de los archivos del servicio se escribieron el 13-10 a las 16:50 UTC (despliegue). Si el comentario con `---` proviene del proceso de release o de una plantilla, el próximo despliegue lo repetiría; no se verificó. | Alto |
| H2 | El job 7965 (`EtlDwGridoPointsTransferenceProcessor`, diario 10:00 -03:00) falló en las 445 corridas que tuvo en PREPROD, la primera el 2025-01-21 y la última el 2026-10-14 13:00 UTC, de 43 a 74 s cada una. En TEST02 el mismo job (id 8451) terminó bien en todas las corridas listadas (1 a 2 s, `Failed = 0`). En PREPROD no hay ninguna ejecución registrada de la operación ETL 15 (`PointsTransference`) antes de la corrida forzada, y las últimas ejecuciones de la tabla `Etl.EtlOperationExecution` son del 2022-12-26. | Alto |
| H3 | `ConnectionStrings.config` de PREPROD se escribió por última vez el 2023-10-11 hasta el cambio del 14-10 a las 14:16:28 UTC. Esa fecha es anterior a la creación del job 7965 (2025-01-20), de modo que la entrada nunca estuvo. Tras agregarla, el archivo tiene 8 entradas; la nueva tiene los mismos atributos, `providerName`, servidor, usuario y claves de cadena que la de TEST02 (el catálogo es el de PREPROD). El servicio se reinició a las 14:16:40 UTC, 12 s después. | Medio |
| H4 | Corrida forzada del job ETL (tarea 139104 adelantada con un `UPDATE` de `ExecuteOn`): inició a las 15:07:00 UTC y terminó en 1 s con `Failed = 0`; creó la ejecución 9061 de la operación 15 con 0 filas (igual que las corridas de TEST02) y el planificador creó la siguiente tarea (139107, 2026-10-15 10:00 -03:00 = 13:00 UTC). Las cuatro tablas del esquema `Etl` existen en PREPROD y TEST02, y la base `SmartFran.Solution.DwTest-PREPROD` existe. | Informativo |
| H5 | La prueba de QA (mover `ExecuteOn` de la tarea 139102 a 10:45 -03:00) no se reflejaba en la base: `ExecuteOn` seguía en 2026-10-15 02:00 -03:00 y la tarea no estaba vencida; un `UPDATE` de otra sesión sobre la misma fila dejaba colgado SSMS, mientras QA sí podía actualizar. SFDEV02 se reinició el 14-10 alrededor de las 15:49 UTC (sistema 15:49:40, SQL Server 15:51:46). Después, el `UPDATE` con `ExecuteOn = 2026-10-14 13:00 -03:00` (16:00 UTC) se aplicó y la tarea 139102 se ejecutó a las 16:01:59 UTC en 7 s con `Failed = 0`; el planificador creó la siguiente (139109) y no había sesiones con transacción abierta a las 16:04 UTC. Las bases SmartLoyalty de SFDEV02 (PREPROD, TEST02 y DEV) tienen `READ_COMMITTED_SNAPSHOT` activo: una lectura no espera un `UPDATE` sin confirmar y muestra el último valor confirmado, mientras que un segundo `UPDATE` de la misma fila espera. Todo es consistente con una transacción abierta sin `COMMIT` (el estado previo al reinicio no se capturó; la repetición del cuadro, capturada en el servidor, está en H9). El mismo login SQL se usa desde varias estaciones y por los servicios; cada conexión es una sesión distinta. | Medio |
| H6 | La configuración de `AppSettings.config` contiene, en un bloque comentado (líneas 104 a 106), la credencial en texto claro del login de un servidor Azure SQL del DW; esa credencial además se mostró en claro durante el diagnóstico del 14-10. | Alto |
| H7 | Los cambios de configuración del 14-10 se hicieron a mano sin copia de respaldo en la carpeta `Config`: la versión previa de `ConnectionStrings.config` se conserva solo como `ConnectionStrings_local.config` (mismo tamaño y mismo hash en la medición previa al cambio). | Medio |
| H8 | El servicio registra solo tres líneas propias ("Instancing Service", "Starting Service", "Stopping Service"); los errores de las tareas llegan por correo; 27 de 44 procesadores de tareas no registran nada y la falla del job ETL no dejó mensaje en la base (`Failed = 1` sin texto). Detalle y recomendaciones: GITIN-2224. | Medio |
| H9 | Segunda ocurrencia (14-10, tarde): QA actualizó con un `UPDATE` el `ExecuteOn` de la tarea 139118 (job 7996) y vio el cambio; el mismo `UPDATE` desde SFDEV02 quedó colgado y el cambio no se veía desde esa sesión. Captura con `scripts-c16.sql` a las 19:39 UTC: la sesión 65 (login `sltest01`, SSMS, estación de trabajo externa a SFDEV02) estaba inactiva con `open_transaction_count = 1`, transacción iniciada a las 19:13:09 UTC, 4 bloqueos exclusivos de fila (`KEY X`) y `DBCC OPENTRAN` la señalaba como la transacción activa más antigua; la sesión 56 (SSMS en SFDEV02) ejecutaba `UPDATE [Sch].[Task] SET [ExecuteOn] = @1 WHERE [id] = @2` esperando con `LCK_M_X` bloqueada por la 65 (643 s a las 19:39, 802 s a las 19:41). A las 19:46 UTC no había ninguna sesión con transacción abierta. QA ejecutó `COMMIT` y tenía un `BEGIN TRAN` que no había visto (informado por QA). El log de transacciones no era el motivo: base en recuperación SIMPLE, 2 % usado, `log_reuse_wait_desc = NOTHING` y 228 GB libres en `E:\`. No se verificó cuál quedó como valor final de `ExecuteOn` de la tarea 139118 ni si el `UPDATE` que esperaba se aplicó o se canceló. | Medio |

## Cambios realizados (hora UTC)

| # | Hora | Cambio |
|---|---|---|
| 1 | 2026-10-14 12:04 | Corrección a mano del comentario de la línea 132 de `Config\AppSettings.config`; el servicio inició y a las 12:04:39 recuperó tareas interrumpidas |
| 2 | 2026-10-14 14:16 | Se agregó la entrada `SmartFran.Business.Etl.Data.Context.EtlContext` a `Config\ConnectionStrings.config` de PREPROD; el servicio se reinició a las 14:16:40 |
| 3 | 2026-10-14 15:03 | `UPDATE` de `Sch.Task` id 139104 (job 7965): `ExecuteOn` adelantado a 15:05:47 UTC (1 fila); la tarea ejecutó a las 15:07:00 |
| 4 | 2026-10-14 ~16:00 | `UPDATE` de `Sch.Task` id 139102 (job 7996): `ExecuteOn = 2026-10-14 13:00 -03:00`; la tarea ejecutó a las 16:01:59 |
| 5 | 2026-10-14 ~15:49 | Reinicio de SFDEV02 (sistema 15:49 UTC, SQL Server 15:51 UTC); después de él la actualización de la tarea 139102 se aplicó |
| 6 | 2026-10-14 19:42–19:46 | QA ejecutó `COMMIT` en su sesión (informado por QA); el bloqueo sobre `Sch.Task` se liberó sin reiniciar nada |

## Recursos afectados

| Recurso | Estado |
|---|---|
| Servicio `SmartLoyalty.TaskOperator.Service.Preprod` (SFDEV02, `E:\SmartFran\PREPROD\SmartLoyalty.TaskOperatorService`) | En ejecución desde las 14:16:40 UTC; ejecuta tareas |
| Job 7965 `EtlDwGridoPointsTransferenceProcessor` (PREPROD) | 445 corridas fallidas hasta el 14-10 13:00 UTC; una corrida correcta a las 15:07 UTC |
| `Config\AppSettings.config` y `Config\ConnectionStrings.config` de PREPROD | Modificados a mano el 14-10 (12:04 y 14:16 UTC) |
| Servicio de TEST02 | Sin cambios en esta investigación (usado como referencia) |

## Consultas ejecutadas

Todos los comandos están en la carpeta `scripts/` del evento; las salidas, en `data/`.

| # | Script | Propósito |
|---|---|---|
| C1 | `scripts.ps1` | Línea 132 de `AppSettings.config`, fecha del archivo y estado de los servicios |
| C2 | `scripts-c2.ps1` | Validez del XML, archivos `.config`, cadenas de conexión (contraseñas enmascaradas), DNS y puerto 1433 |
| C3 | `scripts-c3.ps1` | Líneas ETL de `AppSettings.config`, nombres de cadenas de `ConnectionStrings.config`, registro de `EtlContext` en `Unity.config`, servicios SQL |
| C4 | `scripts-c4.ps1` | Comparación entre entornos de `E:\SmartFran`: servicios, versiones, fechas y hashes de `Config`, nombres y destinos de las cadenas |
| C7 / C8 / C9 | `scripts-c7.ps1`, `scripts-c8.ps1`, `scripts-c9.ps1` | Verificación de la entrada `EtlContext` agregada: estado del archivo, hora de inicio de los servicios y comparación con TEST02 (C7 en modo `dry` se detuvo en su guarda porque el archivo ya tenía 8 entradas) |
| C10 | `scripts.sql` | Estado de `Sch.Task` en PREPROD y TEST02 y estructura del esquema `Sch` |
| C11 | `scripts-c11.sql` | Jobs, calendarios, tarea fallida y tareas desactivadas |
| C12 / C13 | `scripts-c12.sql`, `scripts-c13.sql` | Historial del job 7965 en PREPROD y TEST02, tablas y ejecuciones del esquema `Etl` |
| C14 | `scripts-c14.sql` | Cambia estado: adelanta la tarea 139104 (corrida forzada del job ETL), con guarda y reversión |
| C15 | `scripts-c15.sql` | Resultado de la corrida forzada |
| C17 | `scripts-c17.sql` | Verificación de la tarea 139102 (confirmación del `UPDATE` y ejecución) |
| C18 | `scripts-c18.sql` | Inicio de SQL Server y del sistema, aislamiento de lectura de las bases y sesiones abiertas por login y equipo |
| C16 | `scripts-c16.sql` | Sesiones con transacción abierta, peticiones bloqueadas, bloqueos, lectura confirmada vs sin bloqueo de la tarea y `DBCC OPENTRAN` (capturado con el `UPDATE` colgado, H9) |
| C19 | `scripts-c19.sql` | Uso, reutilización y espacio libre del log de transacciones (descarta el tamaño del log; la sección de tamaño de archivos falló por desbordamiento aritmético en la copia ejecutada y no se usa) |
| C20 | `scripts-c20.sql` | Origen de cada sesión (equipo, dirección del cliente, programa, hora de conexión) y última sentencia de la sesión 65 |

Los scripts `scripts-c5.ps1`, `scripts-c6.ps1` y `scripts-c21.sql` (resultado de la tarea 139118) se prepararon y no se ejecutaron o no se recibió su salida; `scripts-c22.sql` se ejecutó en una ventana distinta a la de QA y no aporta al hallazgo. Ninguno sustenta un hallazgo.

## Acciones propuestas

1. (SRE) Verificar la primera corrida programada del job 7965 (tarea 139107, 2026-10-15 13:00 UTC): `Failed = 0` y una fila nueva en `Etl.EtlOperationExecution` para la operación 15.
2. (SRE) Rotar la credencial del login del servidor Azure SQL del DW y retirarla de `AppSettings.config` (H6).
3. (SRE / Dev) Revisar si el proceso de release o una plantilla escribe el comentario de versión en `AppSettings.config` y si un despliegue puede sobrescribir `AppSettings.config` o `ConnectionStrings.config`; corregir el origen del `---` (H1, H3).
4. (SRE) Guardar una copia fechada de `Config\*.config` antes de cada cambio manual (H7).
5. (Dev) Implementar las recomendaciones de logs de GITIN-2224, en particular la validación al inicio de los contextos de `Unity.config` contra los nombres de `ConnectionStrings.config` y el registro del motivo de cada falla de tarea (H8).
6. (SRE) Agregar un monitoreo sobre `Sch.Task`: tareas vencidas sin iniciar por más de N minutos y jobs con fallas consecutivas; las 445 fallas del job 7965 no generaron alerta.
7. (QA / SRE) Acordar que todo `BEGIN TRAN` manual termine en `COMMIT` o `ROLLBACK`, usar `SET XACT_ABORT ON`, ejecutar `SELECT @@TRANCOUNT` antes de modificar datos en PREPROD/TEST02 y verificar que SSMS tenga `SET IMPLICIT_TRANSACTIONS` desactivado (Tools > Options > Query Execution > SQL Server > ANSI) (H5, H9).
8. (SRE) Investigar los reinicios del servicio (notas "Service crashed, task being reprogrammed." los lunes a las 09:03 UTC y 20 tareas entre las 02:06 y las 12:04 UTC del 14-10) y su posible relación con el apagado nocturno de la VM descrito en GITIN-2126; no se verificó.
9. (SRE) Si vuelve a ocurrir un cambio que no se ve o un `UPDATE` colgado, ejecutar `scripts-c16.sql` antes de hacer cualquier otra cosa: identifica la sesión con la transacción abierta (login, equipo, programa); el dueño de esa sesión ejecuta `COMMIT` o `ROLLBACK` y no hace falta reiniciar el servidor (H9).
10. (SRE) Usar un login por persona o autenticación de Windows para poder rastrear a quién pertenece un bloqueo; hoy un mismo login SQL se usa desde varias estaciones.

## Archivos de evidencia

| Archivo | Contenido |
|---|---|
| `data/c0-sqlexception-paste.txt` | Extracto de la excepción de SQL Server (error 26) del job ETL |
| `data/c1-c2-outs-sfdev02.txt`, `data/c3-full-outs-sfdev02.txt`, `data/c3-tail-outs-sfdev02.txt` | Archivos de configuración y cadenas de conexión (contraseñas enmascaradas) |
| `data/c4-outs-sfdev02.txt`, `data/c8-outs-sfdev02.txt`, `data/c9-outs-sfdev02.txt` | Comparación entre entornos y verificación de la entrada `EtlContext` |
| `data/c10-outs-sfdev02.txt`, `data/c11-outs-sfdev02.txt`, `data/c12-outs-sfdev02.txt`, `data/c13-outs-sfdev02.txt` | Estado de tareas, jobs, historial del job ETL y tablas `Etl` |
| `data/c14-force-outs.txt`, `data/c15-after-outs.txt`, `data/c15-too-early-outs.txt` | Corrida forzada del job ETL y su resultado (la segunda es una lectura anterior a la hora de ejecución) |
| `data/c17-check-outs.txt`, `data/c18-start-outs.txt` | Ejecución de la tarea 139102; inicio de SQL Server y del sistema, aislamiento de lectura y sesiones abiertas |
| `data/c16-blocking-live-outs-sfdev02.txt`, `data/c16-still-blocked-1941-outs-sfdev02.txt` | Captura del bloqueo con el `UPDATE` colgado (19:39 y 19:41 UTC) |
| `data/c19-log-outs-sfdev02.txt`, `data/c20-session-origin-outs-sfdev02.txt` | Estado del log de transacciones; origen de las sesiones y bloqueo ya liberado (19:46 UTC) |
| `data/c10-qa-sql-paste.sql`, `data/c11-qa-sql-test02-paste.sql`, `data/c7-dry-guard-paste.txt`, `data/c10-sql-error-206-paste.txt`, `data/c4-parse-error-outs-sfdev02.txt` | SQL de las pruebas de QA y salidas de errores de los scripts de diagnóstico |

## Hallazgos secundarios

- En PREPROD, la tabla `Etl.EtlOperationExecution` no registra ejecuciones desde 2022-12-26; si otras operaciones ETL dejaron de ejecutarse en esa fecha no se examinó.
- La tarea 135700 del job 7995 (`MktEventAvailableBranchOfficeUpdater`, válido hasta 2026-07-31) quedó vencida y sin ejecutar desde 2026-08-01.
- `Config\AppSettings.config` de TEST02 también se escribió el 14-10 a las 12:44 UTC; no se determinó el motivo.

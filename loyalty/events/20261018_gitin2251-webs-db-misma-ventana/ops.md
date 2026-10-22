# GITIN-2251 — [SML] Chequeo de uso WEBS02

**Tags:** `SmartLoyalty`, `SQLServer`, `SRE`, `PROD`

## Qué pasó

- Revisar la base de datos de SmartLoyalty en la ventana de [GITIN-2250](https://smartit-ar.atlassian.net/browse/GITIN-2250), en que SFCG-WEBS-02 se saturó (14:03 a 15:28 y 16:34 a 17:10, UTC-3) y tuvo un aumento de peticiones POST (17:10 a 18:20), el domingo 2026-10-18.

## Resumen

Se revisó la base de datos de SmartLoyalty (servidor SFCG-DB01, capturas de la base de monitoreo `PNSSRL`) en las cuatro ventanas de GITIN-2250 y, después, los logs IIS de los tres servidores web en Graylog para la ventana de mayor consumo. En la primera ventana (saturación de WEBS-02, 17:03 a 18:28 GMT) WEBS-02 fue el origen de mayor CPU en la base, unas 14 veces el siguiente, y una sola sesión explica el 97,5 % de ese valor; la última captura de esa sesión la muestra dentro del trigger `[Sml].[CustomerPointsLogAfterInsert]`, lo que es compatible con que el trigger haya sido el consumidor, pero no lo prueba. No se encontró bloqueo, esperas de bloqueo, inserciones masivas ni historiales de clientes grandes que expliquen ese consumo, y la base no está saturada de CPU en términos absolutos. Con los datos disponibles (Query Store apagado, caché de planes que no llega al 18-10, capturas cada unos 5 minutos) el consumo no se puede atribuir con certeza, y el vínculo entre la CPU de la base y la saturación del servidor web WEBS-02 no quedó demostrado. Las acciones propuestas apuntan a conseguir esa evidencia si el evento se repite.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2251](https://smartit-ar.atlassian.net/browse/GITIN-2251) (subtarea de [GITIN-2250](https://smartit-ar.atlassian.net/browse/GITIN-2250)) |
| Caso | Revisión de la base de datos en las ventanas de saturación de SFCG-WEBS-02 |
| Base de datos | `PNSSRL` (capturas) y `SmartFran.Solution.SmartLoyalty` (lecturas de catálogo y de historial), servidor SFCG-DB01 |
| Severidad | NA (revisión de uso, sin cambios en producción) |
| Detectado | 2026-10-18 (ver GITIN-2250) |
| Resuelto | No: causa no confirmada |
| Responsable | SRE |

## Causa raíz

NA

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Ventana 1 (saturación de WEBS-02): WEBS-02 fue el origen de mayor CPU en la base, 100.038 ms contra 6.890 ms del siguiente origen (CLUB-01), unas 14 veces. Una sola sesión (117) suma 97.555 ms (97,5 %); las demás sesiones de WEBS-02 suman 2.483 ms, la mayor 625 ms. En las ventanas 2 y 4 WEBS-02 no fue el mayor origen y en la 3 lo superó WEBS-01. | Medio |
| H2 | La sesión 117 tenía 0 ms de CPU acumulada hasta las 17:11 GMT y 97.555 ms a las 17:16 GMT (14:16 UTC-3), es decir, todo ese consumo cayó en esos 5 minutos (como máximo 300 s de reloj, no necesariamente más de un núcleo). Las capturas de las 17:01, 17:06 y 17:11 muestran sentencias comunes y la de las 17:16 muestra el trigger `[Sml].[CustomerPointsLogAfterInsert]` (estado ejecutable, espera `SOS_SCHEDULER_YIELD`, sin bloqueo). Es compatible con que el trigger sea el consumidor, pero es un instante: no se descartan otras sentencias de esa sesión dentro de los mismos 5 minutos. | Medio |
| H3 | El trigger suma todo el historial de cada cliente insertado y hace un MERGE en `SmlSt.CustomerPointsLog`; la tabla `Sml.CustomerPointsLog` tiene unos 404 millones de filas en 16 particiones anuales y ningún índice contiene `CustomerId` junto con `Points`, por lo que cada ejecución hace búsquedas por clave en el índice agrupado. Pero en los 5 minutos de la ventana 1.349 clientes tuvieron inserciones, el mayor historial es de 1.171 filas y contar el historial de todos costó 296 ms de CPU; las inserciones fueron constantes (509 a 700 filas por minuto, sin pico ni inserción masiva). El tamaño del historial de los clientes insertados no explica 97,5 s. | Medio |
| H4 | La base no está saturada de CPU en ninguna ventana (100 s en 85 minutos en la ventana 1), sin bloqueos (0 filas en las cuatro ventanas) y sin esperas `LCK_*`. La espera dominante en todas las ventanas es `MEMORY_ALLOCATION_EXT` (de fondo); `ASYNC_NETWORK_IO` (el cliente lee lento) es la mayor en la ventana 3 (15 filas, contra 6, 3 y 2 en las otras). | Bajo |
| H5 | En las ventanas 2 y 3 la sentencia de mayor CPU en los tres servidores web es una consulta de Entity Framework con un parámetro `bit` (columnas `Id, Name, Description, DisabledDate, DisableNote, ForSale…`; qué lista no se confirmó). En la ventana 3 suma 49.100 ms en WEBS-01, 44.042 ms en WEBS-02 (el 99,5 % de su CPU de la ventana) y 18.428 ms en WEBS-03; un análisis anterior (pico del 2026-09-20) encontró una consulta del mismo tipo como la principal. | Medio |
| H6 | Los logs IIS en Graylog (17:11 a 17:16 GMT) muestran un volumen parecido de POST a `/Service/SaleProvider.svc` en los tres servidores (WEBS-01 4.360, WEBS-02 2.194, WEBS-03 2.418) y que las peticiones de más de 10 s no fueron propias de WEBS-02 (WEBS-01 29, WEBS-03 22, WEBS-02 8). `healthcheck.ashx` respondió 400 en 11 de 23 llamadas en WEBS-02, 1 de 18 en WEBS-03 y 0 de 20 en WEBS-01, lo esperado con WEBS-02 bajo presión de CPU (ver GITIN-2250). Los HTTP 500 (12 a 17 % de los POST) no se cuentan como fallas: se informó que son una respuesta de negocio del servicio y el código es compatible (las excepciones de negocio se devuelven como falla WCF); no se revisó el mapeo HTTP del enlace. | Bajo |
| H7 | Qué operaciones de `SaleProvider` generan las inserciones en `CustomerPointsLog`, y si los 2.194 POST de WEBS-02 las incluyen, no se pudo determinar: el servicio mezcla lecturas y escrituras y el log IIS no registra la acción SOAP. El recorrido desde `AddSale` hasta el insert no se trazó en el código. | Medio |
| H8 | No hay forma de atribuir la CPU a una sentencia con la evidencia disponible: Query Store está apagado en `SmartFran.Solution.SmartLoyalty`, la caché de planes del trigger arranca el 2026-10-19 10:07 (115 ejecuciones, máximo 11 ms) y las tablas de captura toman una muestra cada unos 5 minutos con la CPU acumulada por sesión (la diferencia entre dos capturas incluye todo lo que hizo la sesión). | Medio |

## Recursos afectados

| Componente | Estado |
|---|---|
| SFCG-WEBS-02 | Saturado el 18-10 (GITIN-2250); origen de mayor CPU en la base en la ventana 1 |
| SFCG-WEBS-01 / SFCG-WEBS-03 | Sin hallazgos propios en este ticket; WEBS-01 fue el mayor origen de CPU en la base en la ventana 3 |
| SFCG-DB01 (`SmartFran.Solution.SmartLoyalty`) | Sin saturación de CPU, sin bloqueos; consumo de la sesión 117 sin atribuir |
| `Sml.CustomerPointsLog` y trigger `[Sml].[CustomerPointsLogAfterInsert]` | Sospechoso de la sesión 117, no probado |

## Métricas del evento

CPU de la base por origen (suma de los incrementos positivos entre capturas, en ms; ventanas en GMT):

| Ventana | WEBS-02 | WEBS-01 | WEBS-03 | Siguiente origen |
|---|---|---|---|---|
| 1 — saturación (17:03 a 18:28) | 100.038 | 3.111 | 968 | CLUB-01 6.890 |
| 2 — segunda saturación (19:34 a 20:10) | 2.930 | 7.310 | 6.265 | CLUB-01 7.719 |
| 3 — aumento de POST (20:10 a 21:20) | 44.276 | 58.892 | 18.491 | CLUB-02 6.000 |
| 4 — pico en Mobile 02 (22:02 a 22:18) | 359 | 16 | 5.160 | CLUB-01 2.889 |

| Métrica | Valor |
|---|---|
| Capturas de la tabla de procesos por ventana | 17 / 7 / 14 / 3 (una cada unos 5 minutos) |
| Bloqueos vistos en las capturas | 0 en las cuatro ventanas |
| CPU de la sesión 117 (WEBS-02) | 97.555 ms entre las 17:11 y las 17:16 GMT |
| Clientes con inserciones entre las 17:11 y las 17:16 GMT | 1.349 (mayor historial: 1.171 filas) |
| Costo de contar el historial de esos clientes | 296 ms de CPU |
| Filas insertadas por minuto (17:00 a 17:30 GMT) | 509 a 700 |
| Filas de `Sml.CustomerPointsLog` | 404.460.588 (16 particiones) |

## Acciones Tomadas

| # | Hora (UTC) | Acción |
|---|---|---|
| 1 | 2026-10-19 12:16 a 12:33 | Consultas de solo lectura sobre `PNSSRL`: disponibilidad de capturas, CPU por origen, bloqueos, esperas, sentencias principales y sesiones con lecturas de tempdb para las cuatro ventanas. |
| 2 | 2026-10-19 12:37 a 12:59 | Lectura de la definición del trigger en el servidor, de los índices y particiones de `Sml.CustomerPointsLog`, de las capturas del trigger, del estado de Query Store y de la caché de planes (solo lectura). |
| 3 | 2026-10-19 19:14 a 19:19 | Repetición de las consultas de CPU y bloqueos, capturas de la sesión 117 alrededor de las 17:16 GMT y historial de los clientes insertados en esos 5 minutos (solo lectura). |
| 4 | 2026-10-19 19:22 a 19:27 | Consulta de los logs IIS de los tres servidores web en Graylog para las 17:11 a 17:16 GMT (solo lectura). |
| 5 | 2026-10-19 | Revisión del código fuente de SmartLoyalty (rama principal, commit del 2026-10-14; lo desplegado no se comprobó): definición del trigger y operaciones de `SaleProvider`. |

No se hizo ningún cambio en producción en este ticket.

## Acciones propuestas

| # | Responsable | Acción | Estado |
|---|---|---|---|
| 1 | SRE | Evaluar activar Query Store en `SmartFran.Solution.SmartLoyalty` (con tamaño máximo y modo de captura acotados) para tener CPU por consulta en el próximo evento. Requiere medir el costo en producción antes de decidir. | Por decidir |
| 2 | SRE | Definir una captura más fina de los procesos activos (por ejemplo cada 30 a 60 s, con la sentencia en ejecución y no solo la CPU acumulada) mientras haya una alerta de CPU en WEBS. | Por decidir |
| 3 | SRE | Agregar la acción SOAP a los campos que IIS registra y que llegan a Graylog, para poder distinguir las operaciones de `SaleProvider` en los logs. | Por decidir |
| 4 | Dev | Trazar `AddSale` hasta la inserción en `CustomerPointsLog` y evaluar si el trigger puede evitar la suma de todo el historial del cliente (por ejemplo, una actualización incremental) o si conviene un índice con `CustomerId` e `Points`. No se probó ningún cambio. | Por decidir |
| 5 | SRE | Si la saturación de WEBS-02 se repite, tomar en el momento las capturas de las acciones 1 y 2 y volver a revisar este punto. | Pendiente |

## Hallazgos secundarios

| # | Hallazgo | Riesgo |
|---|---|---|
| S1 | Fuera de las ventanas, el 2026-10-19 entre las 05:06 y las 10:06 GMT la caché de planes registra lecturas de `Sml.CustomerPointsLog` de tipo sincronización (`_SyncDate`) de 2,9 a 3,4 millones de ms de CPU (en paralelo, no tiempo de reloj) y unos 3.500 millones de lecturas lógicas por ejecución, y consultas similares sobre `Sml.Sale`. No se identificó quién las ejecuta (los DMV no guardan el host). | Medio |
| S2 | El índice `IX_CustomerPointsLog_Points` de `Sml.CustomerPointsLog` tuvo 338 búsquedas y 0 recorridos frente a 1.214.569 actualizaciones desde el reinicio del servicio (2026-10-14): costo de escritura con muy poca lectura. No se analizó más. | Bajo |

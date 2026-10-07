# GITIN-1866 — [SML] Impacto Campañas — salud de queries durante picos de tráfico en MobileAppService y WebServiceV2

## Resumen

Ticket de alcance general: impacto de campañas de marketing tanto sobre **recursos de VM** (consumo de CPU en los hosts involucrados) como sobre **la base de datos** (`PNSSRL`/`SmartFran.Solution.SmartLoyalty`) — cubriendo MobileAppService (`SFCG-MOBI-01/02`) y WebServiceV2 (`SFCG-WSV2-01`). Cubre dos ocurrencias hasta el momento:

**2026-08-16** — Club Grido envió una campaña masiva de marketing que generó un pico de tráfico reportado de hasta 80 req/s POST y 100 req/s GET. Se investigó la salud de las queries en `PNSSRL` durante la ventana de tráfico real confirmada por Graylog (16:00–21:00 UTC).

**2026-08-19** — pico adicional reportado sobre MobileAppService, ~100 req/s, ventana 21:00–22:00 UTC-3 (2026-08-20 00:00–01:00 UTC).

En ambas ocurrencias, el lado de base de datos se mantuvo saludable durante toda la ventana. Sin embargo, el análisis de logs IIS de MobileAppService reveló una tasa de respuestas 400 (Bad Request) concentrada en los mismos tres endpoints (`SaveNewMember`, `Login`, `RecoveryPassword`) **en ambas ocurrencias**, con orden de magnitud similar — hallazgo no visible desde el lado de base de datos, y que dos repeticiones independientes hacen más probable que sea un defecto real de validación y no ruido esperado a escala. La causa raíz de la tasa de 400 y la capacidad disponible para una campaña de mayor escala quedan como líneas de investigación abiertas (ver "Acciones propuestas").

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-1866](https://smartit-ar.atlassian.net/browse/GITIN-1866) |
| Caso | Impacto de campañas sobre `PNSSRL` — MobileAppService y WebServiceV2, 2 ocurrencias (2026-08-16, 2026-08-19) |
| Base de datos | `SmartFran.Solution.SmartLoyalty` (monitoreo vía `PNSSRL`) |
| Severidad | Media |
| Detectado | 2026-08-18 (retrospectivo, evento 2026-08-16); 2026-08-20 (retrospectivo, evento 2026-08-19) |
| Resuelto | No aplica — ticket abierto, ver acciones propuestas |
| Responsable | Dante Paniagua, SRE |

## Causa raíz

No se identificó ninguna causa raíz de incidente en `PNSSRL` en ninguna de las dos ocurrencias: no se detectó bloqueo alguno en las ventanas investigadas y el costo de CPU atribuible a MobileAppService fue marginal en todo momento.

Respecto de la tasa de respuestas 400 en `Login`, `SaveNewMember` y `RecoveryPassword`: **el mecanismo que genera el 400 está confirmado por revisión de código fuente** (`repo/dev-src-sol-smartloyalty/Front/MobileAppService/`, ver detalle en `investigation.md` → "Source-code root-cause analysis"). Dos filtros de acción producen el 400: `ModelValidatorFilter` (campos requeridos/formato inválido en el request, antes de ejecutar la acción) y `Logger` (convierte **cualquier** excepción lanzada durante la acción, incluyendo reglas de negocio como socio menor de edad, cuenta ya existente o tarjeta vencida, en un 400 genérico). El detalle completo endpoint por endpoint — cada código `st` y su disparador — está documentado en `investigation.md`.

**Lo que sigue sin confirmarse** es la atribución real: qué proporción de los 400 observados corresponde a cada causa (dato malformado del cliente vs. regla de negocio vs. error real de la app) — requiere muestreo del campo `st` en el cuerpo de respuesta de tráfico real, no evaluado en este ticket. Además, una parte de los flujos de `SaveNewMember` y `RecoveryPassword` (validación de teléfono, `InvalidUserName`) devuelve el fallo en el cuerpo con HTTP 200, no 400 — la tasa de fallo real percibida por el cliente es mayor a la que muestra el código de estado HTTP solo.

Sí se confirma que el patrón de 400 **se repite** en ambas ocurrencias (mismos tres endpoints, mismo orden de magnitud) — dos repeticiones independientes hacen menos probable que sea ruido puntual de una sola campaña.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Sin bloqueos en `PNSSRL` durante toda la ventana de pico real (16:00–21:00 UTC, cubierta en dos tramos: 15:00–20:00 y 20:00–21:00) | Bajo |
| H2 | MobileAppService (`SFCG-MOBI-01/02`) generó el mayor volumen de sesiones/conexiones de cualquier host, pero con costo de CPU marginal por query (~8.6ms promedio) — sin estrés medible sobre `PNSSRL` | Bajo |
| H3 | Tasa sostenida de respuestas 400 en logs IIS de MobileAppService: 21.7% del tráfico total (65.796 de 302.748 requests). Concentrada en `SaveNewMember` (66.5%), `Login` (52.1%) y `RecoveryPassword` (33.6%). Presente desde el inicio de la ventana, no es un pico puntual. Causa no confirmada | Medio |
| H4 | Único evento aislado de degradación: bucket 20:55–20:58 UTC con la peor latencia de cola de toda la ventana (máx. 6.573ms) y el único error 500 de las 302.748 requests (`GetCustomerProfile`, `SFCG-MOBI-02`). Coincide en el tiempo (no confirmado como relacionado) con un pico de intensidad de CPU en `SFCG-WEBS-03`, host distinto al de MobileAppService | Bajo |
| H5 | Volumen sostenido pico observado (~30 req/s en el bucket de 5 min más cargado) está por debajo del pico reportado de 80 POST + 100 GET req/s combinados — no reconciliado; puede tratarse de un pico de sub-5 minutos no resuelto por la granularidad usada, o de una estimación | Bajo |
| H6 | (2026-08-19) Sin bloqueos en `PNSSRL` durante la ventana del pico reportado (2026-08-20 00:00–01:00 UTC). MobileAppService con costo de CPU marginal (`MOBI-02` 156ms/144 filas, `MOBI-01` 0ms/26 filas) | Bajo |
| H7 | (2026-08-19) **Se repite la misma tasa elevada de 400** en los mismos tres endpoints y mismo orden de magnitud que el 2026-08-16: `SaveNewMember` 71.4%, `Login` 65.2%, `RecoveryPassword` 36.5% (14.8% general sobre 28.028 requests IIS). Dos ocurrencias con la misma huella refuerzan la hipótesis de defecto real, no ruido puntual | Medio |
| H8 | (2026-08-19) Volumen medido (pico ~4,7 req/s en el bucket de 5 min más cargado) muy por debajo del pico reportado de ~100 req/s — mismo patrón de discrepancia no reconciliada que el 2026-08-16 | Bajo |
| H9 | Mecanismo del 400 confirmado por código fuente: `ModelValidatorFilter` (campos inválidos/faltantes) y `Logger` (cualquier excepción de negocio → 400 genérico, incluyendo casos como socio menor de edad o cuenta ya existente). Atribución real por causa aún no confirmada — requiere muestreo del campo `st` en tráfico real. Además, parte de los fallos de `SaveNewMember`/`RecoveryPassword` (validación de teléfono, `InvalidUserName`) devuelve HTTP 200 con el fallo solo en el cuerpo — no capturado por la métrica de tasa de 400 usada en este ticket | Medio |
| H10 | (2026-08-19) Atribución parcial vía campo `Action` de eventos `svclog_input` en Graylog — **es una extracción por regex del log crudo, no un registro general de cada código `st`**, solo captura los patrones para los que fue escrita. De los 5 valores que existen (`LoginSuccess` 4.658, `InvalidPassword` 2.276, `customerEmailNotCompatible` 648, `PointsTransfer` 88, `Exception` 1), dos coinciden con causas identificadas en el código fuente (`InvalidPassword` ≈ falla de autenticación en `Login`; `customerEmailNotCompatible` = código exacto de `RecoveryPassword` por email no coincidente), ambos sostenidos parejo en toda la ventana, sin concentración puntual. **Ninguno de los códigos de `SaveNewMember` aparece** — sigue sin visibilidad alguna, sea porque no ocurrieron esos fallos en la ventana o porque el extractor no los captura (no distinguible con este dato) | Bajo |
| H11 | Confirmado por configuración real de NXLog y `SystemDiagnostics.config` de `SFCG-MOBI-01`: la brecha de atribución de `SaveNewMember` es **estructural, no de consulta**. El pipeline NXLog→Graylog descarta el contenido crudo de cualquier línea que no matchee uno de sus 5 regex (de 56.398 filas `svclog_input`, 48.728 llegan a Graylog sin ningún campo extraído — el texto original se pierde en el salto NXLog→Graylog, no en Graylog). El dato sí existe completo en el servidor: `SourceSwitch value="All"` en la app confirma que se traza todo, sin filtrar, hacia dos archivos — el CSV que lee NXLog (`D:\Log\SmartLoyalty.MobileAppService\csv\SmartLoyalty.MobileAppService.csv`) y un XML paralelo nunca leído por NXLog (`D:\Log\SmartLoyalty.MobileAppService\SmartLoyalty.MobileAppService.svclog`). Este último se escribe como fragmentos XML sueltos sin elemento raíz — por eso NXLog Community nunca lo ingiere (limitación de producto, no un descuido de config); igual sirve para extracción manual (grep/regex, o envolverlo en una raíz sintética antes de parsear) | Medio |
| H12 | **Mecanismo de atribución de `SaveNewMember` confirmado y validado contra un archivo `.svclog` real** de `SFCG-MOBI-01` (6,4MB, ventana 2026-08-20 05:00–12:33 UTC — **no coincide con ninguna ventana de campaña**, solo sirve para validar el método). Cada evento `BusinessReport-{code}` lleva el endpoint embebido como prefijo literal `[OP] {endpoint}: ` en el mismo mensaje — atribución directa sin necesidad de correlacionar por hilo/`Id`. En esta ventana (no de campaña) aparecieron los 7 códigos: `Login`→`InvalidPassword` (93)/`InvalidUserName` (41), `RecoveryPassword`→`customerEmailNotCompatible` (58), `SaveNewMember`→`EmailAlreadyExist` (4)/`CustomerExists` (4)/`PendingCustomerExists` (1)/`DocumentTooShort` (1) — incluyendo `SaveNewMember`, resolviendo la duda de H11 sobre si el dato era recuperable manualmente (sí lo es, una vez que se consigue el archivo correcto). También apareció `InvalidUserName`, un código que el código fuente clasifica como retorno 200 sin excepción — confirma que el tag `BusinessReport` se escribe independientemente de si el flujo termina en 400 o en 200 con fallo en el cuerpo | Bajo |
| H13 | `SFCG-CLUB-01` (sitio Club Grido) ejecutó repetidamente **Query077** (`AvailablePromotion` — fuente: `Core/Domain.Query/Domain/Query/Query077-sql.xml`, `SmartLoyalty.WebService`, clon local del repo) — 14+ veces en la ventana del 2026-08-16, ~4.000–6.700ms de CPU y ~12.000 lecturas lógicas cada vez (vía `PNSSRL_TempdbProc`), explicando la totalidad de los 49.706ms de CPU delta de ese host. Costo fijo por llamada, causado por un `CROSS JOIN` entre dos table-valued params (`@BranchOfficeTableTmp × @PromotionTmp`) dentro de `SmlSupp.PromotionBranchOffice`. **Detalle adicional confirmado en el texto fuente:** cuando no se filtra por sucursal específica (o se pasa un `cId`/país), `@BranchOfficeTableTmp` se puebla con *todas* las sucursales activas de ese país — el tamaño real del `CROSS JOIN` depende de cuántas sucursales entren en ese filtro, no es un costo fijo estructural sino proporcional al catálogo de sucursales/promociones pasado. No genera bloqueos ni escala en el tiempo dentro de esta ventana — no es un incidente, es una consulta cara de forma consistente | Bajo (candidato de optimización, no bloqueante) |
| H14 | `SFCG-WSV2-01` (WebServiceV2) fue el mayor consumidor de CPU de toda la ventana del 2026-08-16 (306.890ms, ~mitad del total de todos los hosts) pero no aparece en el top 20 de `PNSSRL_TempdbProc` — sin huella en tempdb, la query responsable no pudo identificarse con las tablas de captura usadas en este ticket. Carga sostenida durante toda la ventana 15:00–20:00, no concentrada en el patrón puntual de tráfico de la campaña — consistente con carga base, pero WebServiceV2 está dentro del alcance de este ticket | Medio (mayor consumidor de CPU de la ventana, sin visibilidad de la query) |

## Consultas SQL identificadas (H13/H14)

### Query077 — `AvailablePromotion` (H13)

Fuente: `Core/Domain.Query/Domain/Query/Query077-sql.xml`, `SmartLoyalty.WebService` (clon local del repo, confirmado 2026-09-09).

```sql
DECLARE @params XML = {0}
DECLARE @BranchOfficeTableTmp TABLE (BranchOfficeId UNIQUEIDENTIFIER)
DECLARE @PromotionTmp TABLE (PromotionId INT)
DECLARE @branchOfficeCountryId INT;
DECLARE @Counter INT

SELECT @branchOfficeCountryId = n.value('cId[1][not(@xsi:nil = "true")]', 'int')
FROM @params.nodes('params') AS p(n)

INSERT INTO @BranchOfficeTableTmp
SELECT n.value('.', 'uniqueidentifier')
FROM @params.nodes('params/bo') AS p(n)

SELECT @Counter = @@ROWCOUNT

INSERT INTO @PromotionTmp
SELECT n.value('.', 'int')
FROM @params.nodes('params/pId') AS p(n)

DECLARE @branchOfficeCount INT
SELECT @branchOfficeCount = COUNT(*) FROM @BranchOfficeTableTmp

IF (@branchOfficeCountryId IS NOT NULL OR @branchOfficeCount = 0)
BEGIN
     INSERT INTO @BranchOfficeTableTmp
     SELECT BO.Id
     FROM Sml.BranchOffice BO WITH (NOLOCK)
     INNER JOIN Sml.[Address] A WITH (NOLOCK) ON A.Id = BO.AddressId
     INNER JOIN Sml.[Location] CITY WITH (NOLOCK) ON CITY.Id = A.LocationId
     INNER JOIN Sml.[Location] [STATE] WITH (NOLOCK) ON [STATE].Id = CITY.ParentLocationId
     INNER JOIN SML.[Location] COUNTRY WITH (NOLOCK) ON COUNTRY.Id = [STATE].ParentLocationId
     WHERE BO.ActivatedDate IS NOT NULL
     AND BO.DeactivatedDate IS NULL
     AND (@branchOfficeCountryId IS NULL OR COUNTRY.Id = @branchOfficeCountryId)

     SELECT @Counter = @@ROWCOUNT
END

IF((SELECT COUNT(*) FROM @PromotionTmp) > 0)
BEGIN
     SELECT  PBO.PromotionId
     FROM SmlSupp.PromotionBranchOffice PBO WITH (NOLOCK)
     INNER JOIN (SELECT BranchOfficeId, PromotionId
                 FROM @BranchOfficeTableTmp
                 CROSS JOIN @PromotionTmp) temp ON temp.PromotionId = PBO.PromotionId
                                               AND temp.BranchOfficeId = PBO.BranchOfficeId
     GROUP BY PBO.PromotionId
END
ELSE
BEGIN
     SELECT  PBO.PromotionId
     FROM SmlSupp.PromotionBranchOffice PBO WITH (NOLOCK)
     INNER JOIN @BranchOfficeTableTmp temp ON temp.BranchOfficeId = PBO.BranchOfficeId
     GROUP BY PBO.PromotionId
     HAVING COUNT(DISTINCT PBO.BranchOfficeId) = @Counter
END
```

**Punto clave para la optimización (ítem 8):** `@BranchOfficeTableTmp` se puebla con *todas* las sucursales activas del país cuando la llamada no especifica sucursales puntuales (`IF (@branchOfficeCountryId IS NOT NULL OR @branchOfficeCount = 0)`). El `CROSS JOIN` contra `@PromotionTmp` escala con ese universo de sucursales, no es un costo fijo — acotar la lista de sucursales antes de invocar la query es la palanca real, no un índice.

### WebServiceV2 — query sin identificar (H14)

No hay texto de query para mostrar acá — ese es justamente el hallazgo pendiente. `SFCG-WSV2-01` no aparece en el top 20 de `PNSSRL_TempdbProc` (sin huella en tempdb), así que ninguna de las tablas de captura usadas en este ticket devolvió el texto de la consulta responsable. Identificarla (acción propuesta 9) requiere otra fuente — `sys.dm_exec_query_stats` o extended events sobre `SFCG-WSV2-01`, no evaluado todavía.

## Métricas del evento

### 2026-08-16

| Métrica | Valor |
|---|---|
| Ventana investigada (GMT/UTC) | 2026-08-16 15:00–21:00 |
| Ventana de pico real confirmada (Graylog) | 2026-08-16 16:00–21:00 UTC |
| Snapshots `PNSSRL_AuditSysprocesses` cubiertos | 72 (60 + 12, ~5 min de cadencia, sin huecos) |
| Bloqueos detectados | 0 |
| Requests IIS totales (MobileAppService) | 302.748 |
| Respuestas 200 | 236.201 |
| Respuestas 400 | 65.796 (21.7%) |
| Respuestas 404 | 750 |
| Respuestas 500 | 1 |
| Pico sostenido observado | ~30 req/s (bucket de 5 min más cargado, 16:05 UTC) |
| CPU total (todos los hosts, ventana 15:00–20:00) | 584.929 ms |
| CPU atribuible a MobileAppService (`MOBI-01/02`) | 14.185 ms (2.4% del total) |

### 2026-08-19 (follow-up)

| Métrica | Valor |
|---|---|
| Pico reportado (UTC-3) | 21:00–22:00 (100 req/s) |
| Ventana investigada (UTC) | 2026-08-20 00:00–01:00 (equivalente); export IIS analizado cubre 00:00–02:00 |
| Snapshots `PNSSRL_AuditSysprocesses` cubiertos | 12 (~5 min de cadencia, sin huecos) |
| Bloqueos detectados | 0 |
| Requests IIS totales (`iis_w3c_mobile`, MobileAppService) | 28.028 |
| Respuestas 200 | 23.787 |
| Respuestas 400 | 4.144 (14,8%) |
| Respuestas 404 | 97 |
| Respuestas 500 | 0 |
| Pico sostenido observado | ~4,7 req/s (bucket de 5 min más cargado, 01:25) |
| CPU atribuible a MobileAppService (`MOBI-01/02`) | 156 ms (`MOBI-02`) + 0 ms (`MOBI-01`) |
| Host dominante en CPU (no vinculado a MobileAppService) | `SFCG-WSV2-01`, 63.320 ms — tasa consistente con su carga base ya observada el 2026-08-16 |

## Consultas ejecutadas

| # | Query | Propósito |
|---|---|---|
| Q1 | Disponibilidad de datos (ventana principal) | Confirmar cobertura de snapshots 15:00–20:00 UTC |
| Q2 | Delta de CPU por SPID (top 50) | Identificar las sesiones con mayor consumo de CPU en la ventana |
| Q3 | Desglose de CPU por host | Atribuir el consumo de CPU a cada servicio/aplicación |
| Q4 | Verificación de bloqueos | Confirmar ausencia de bloqueos en toda la ventana |
| Q5 | Top sesiones por CPU con texto de query (`PNSSRL_TempdbProc`) | Identificar la query responsable del consumo en `SFCG-CLUB-01` (Query077) |
| Q6 | Chequeo de hora faltante (20:00–21:00 UTC) | Cerrar la cobertura hasta el final de la ventana de pico real confirmada por Graylog |
| Q7 | Disponibilidad de datos (ventana pico 2026-08-19) | Confirmar cobertura de snapshots 2026-08-20 00:00–01:00 UTC |
| Q8 | Verificación de bloqueos (ventana pico 2026-08-19) | Confirmar ausencia de bloqueos en la ventana del pico reportado |
| Q9 | Desglose de CPU por host (ventana pico 2026-08-19) | Atribuir el consumo de CPU a cada servicio/aplicación, foco en `SFCG-MOBI-01/02` |

Ver `scripts.sql`.

## Acciones propuestas

1. ~~Para `SaveNewMember` (sin visibilidad en Graylog, ver H11): conseguir el archivo `.svclog` o una copia archivada/rotada que cubra las ventanas de campaña~~ — **cerrado como no recuperable**. El mecanismo de atribución quedó **validado end-to-end** contra un archivo `.svclog` real (ver H12), pero el usuario confirmó que no existe ninguna copia rotada/archivada de `SmartLoyalty.MobileAppService.svclog` que alcance las ventanas de campaña (2026-08-16 15:00–20:56 UTC / 2026-08-20 00:00–01:00 UTC). El único archivo disponible (rotación única, sin backups numerados, ~10MB de capacidad) ya había rotado más allá de ambas ventanas para cuando se pudo extraer. Este dato específico no es recuperable para este ticket.
2. Para `Login`/`RecoveryPassword`: contrastar el campo `Action` de `svclog_input` (Graylog, ver H10 — señal parcial, no sustituye el muestreo real) contra la tabla de causas de `investigation.md`, para estimar qué proporción corresponde a dato malformado del cliente (p. ej. `UidSerie` fuera del formato esperado por el regex de `Login`) vs. regla de negocio vs. credenciales inválidas. Prioridad elevada: mecanismo ya confirmado por código fuente, dos ocurrencias independientes con el mismo patrón (2026-08-16 y 2026-08-19), solo falta la atribución real.
3. Evaluar si conviene que `SaveNewMember`/`RecoveryPassword` devuelvan códigos de error HTTP no-200 en los flujos que hoy responden 200 con fallo solo en el cuerpo (validación de teléfono, `InvalidUserName`) — actualmente invisibles a cualquier métrica basada en código de estado HTTP. Cambio de comportamiento de API, requiere validación con el equipo de desarrollo de la app — no evaluado en este ticket.
4. Ampliar el regex de NXLog en `SFCG-MOBI-01`/`02` a una captura genérica `<BusinessReport-([A-Za-z]+)>` para que todos los códigos de negocio lleguen a Graylog a futuro, no solo `customerEmailNotCompatible` — cambio de configuración en un agente de shipping de logs productivo, requiere aprobación explícita antes de aplicarse. No evaluado en este ticket.
5. Análisis de capacidad/límites de `PNSSRL` ante una campaña de mayor escala que las observadas hasta ahora — evaluar reutilizar precedentes existentes de pruebas de carga en `events/` (`20260727_cpu_peaks_loadtest`, `20260803_cpu_peaks_loadtest`, `20260723_bloqueo_customerpointslog_loadtest`) en lugar de partir de cero. No evaluado en este ticket.
6. Reconciliar el pico de tráfico reportado (~100 req/s, ambas ocurrencias) contra el medido en logs IIS (~30 req/s el 2026-08-16, ~4,7 req/s el 2026-08-19) — determinar si la cifra reportada proviene de otro punto de medición (gateway/LB) no capturado por este log. No evaluado en este ticket.
7. **Para cualquier ocurrencia futura similar**: el mecanismo de atribución vía `.svclog` (tag `[OP] {endpoint}: ...<BusinessReport-{code}>`, ver H12) ya está validado y listo para usar — pero el archivo tiene retención corta (~11–12h desde vacío hasta los ~10MB de rotación, sin backups numerados). Para que sea útil, debe extraerse de `SFCG-MOBI-01`/`02` dentro de ese margen desde el evento, no días después como en este ticket. No evaluado en este ticket.
8. **(H13) Optimizar Query077 (`AvailablePromotion`)** — el texto fuente (`Core/Domain.Query/Domain/Query/Query077-sql.xml`) confirma que el costo no es fijo: cuando la llamada no especifica sucursales puntuales (o pasa un filtro de país), `@BranchOfficeTableTmp` se puebla con *todas* las sucursales activas de ese país antes del `CROSS JOIN` contra `@PromotionTmp`. Evaluar con el equipo de desarrollo si el caller (`/api/Catalog/AvailablePromotion`) puede acotar la lista de sucursales antes de invocar la query, en vez de dejar que la query traiga el universo completo de sucursales del país. Reduciría el costo de ~4.000–6.700ms CPU / ~12.000 lecturas lógicas por llamada de forma proporcional al filtro real usado. No bloqueante ni vinculado a la campaña — candidato de mejora de performance.
9. **(H14) Identificar la query real detrás del consumo de CPU de `SFCG-WSV2-01`** (306.890ms en la ventana del 2026-08-16, ~mitad del total) — al no tener huella en tempdb, requiere otra fuente de captura (p. ej. `sys.dm_exec_query_stats` o extended events, ya que `$indexStats`-equivalente en `PNSSRL_TempdbProc` no la captura) para identificarla antes de poder evaluar si amerita optimización. Prioridad: WebServiceV2 está dentro del alcance de este ticket y es el mayor consumidor de CPU de la ventana — no evaluado todavía.

## Archivos de evidencia

| Archivo | Contenido |
|---|---|
| `investigation.md` | Notas de trabajo completas, en inglés — teoría de trabajo, hallazgos y conclusión final |
| `scripts.sql` | Las 6 queries ejecutadas contra `PNSSRL` durante la investigación |
| `Untitled-Message-Table-search-result(1).csv` | Exportación cruda de logs IIS de Graylog, ocurrencia 2026-08-16 (302.748 filas, `SFCG-MOBI-01/02`, ventana 15:25–20:55 UTC) |
| `Messages-search-result.csv` | Exportación cruda de logs Graylog, ocurrencia 2026-08-19 (84.428 filas totales, 28.028 de tipo `iis_w3c_mobile`; ventana `EventReceivedTime` 00:00:00–01:59:58 UTC del 2026-08-20) |
| `repo/dev-src-sol-smartloyalty/Front/MobileAppService/` (clon local, no versionado en este ticket) | Fuente revisada para el mecanismo de los 400: `Controllers/{Account,Customer,Benefits}Controller.cs`, `Filters/{Logger,ModelValidatorFilter}.cs`, `Core/Shared/Code/BusinessRulesCode.cs`, `Models/Request/{LoginRequest,NewMemberRequest,AccountPasswordRequest}.cs` |

## Hallazgos secundarios

- Los dos hallazgos de consultas SQL detectados durante este análisis (Query077 en `SFCG-CLUB-01`, query no identificada en `SFCG-WSV2-01`) están reportados como H13/H14 en la tabla de Hallazgos, con sus acciones propuestas correspondientes (ítems 8-9) — no se detallan acá para evitar duplicación.

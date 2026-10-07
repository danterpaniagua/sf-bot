# 01-09-2026_mongo-to-s3-lambda-utc3-fix-broke-production

**Tags:** SmartPedidos, MongoDB, AWS, DEPLOY, PROD

## Resumen

El 31/08/2026 se desplegó en `mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO` (Lambda que exporta la colección `news` de MongoDB Atlas a S3, insumo para el envío de datos a Grido — GITIN-1872) la corrección de límite de día UTC-3 correspondiente a GITIN-1970. La primera ejecución bajo el código nuevo, el 01/09/2026 a las 03:30 UTC, falló de inmediato por un error de conexión a MongoDB no relacionado con el fix de límite de día. La remediación reveló tres bugs adicionales, encontrados y corregidos en la misma jornada: un segundo bug de conexión (parseo de `daysBefore`), un agotamiento de memoria (`Runtime.OutOfMemory`) por diseño de la función, y un bug de mapeo de esquema preexistente. Los cuatro fixes quedaron desplegados y validados con una ejecución real exitosa el mismo día, incluyendo un backfill del rango de datos que estaba por expirar bajo el TTL de 15 días de la colección `news`.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-1970 |
| ID alerta | — (detectado durante validación manual post-despliegue, sin alerta automática) |
| Sistema | mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO (Lambda, SmartPedidos) |
| Severidad | Alta |
| Detectado | 2026-09-01 03:30 UTC (00:30 -03:00) |
| Resuelto | 2026-09-02 — desplegado y validado íntegramente en producción (incluye los campos `originalid`/`displayid`/`canje` agregados el 01/09, confirmados en un export real del 02/09), con una excepción permanente, ver H6 |
| Responsable | Dante Paniagua, SRE |

## Causa raíz

Cuatro defectos independientes, todos en `mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO`. (1) La cadena de conexión a MongoDB (`connString`) es un template literal sin interpolación (`${}`) — conecta contra el string literal `HOST` en lugar del valor real de `process.env.HOST`, provocando `MongoParseError` en cada invocación. (2) `daysBefore` pasó a leerse de la variable de entorno `DAYSBEFORE` (string) sin convertir a número — la aritmética `daysBefore + 1` concatena en lugar de sumar, dejando vacío el arreglo de días a procesar y produciendo una ejecución silenciosa sin escrituras ni error. (3) La función original acumulaba en memoria los datos de los ~15 días del rango antes de iniciar cualquier escritura a S3 (`Promise.all` sobre todo el rango, seguido de un ciclo de subida secuencial) — con archivos diarios de hasta ~180 MB, esto agotaba la memoria máxima configurada (4096 MB) una vez resueltos los dos bugs anteriores. (4) `orderMapper()` construye un objeto con el esquema mapeado (claves en minúscula) pero retorna el objeto original sin mapear (`return order` en lugar de `return parsedOrder`) — defecto de código muerto, presente en todas las versiones del handler revisadas en esta investigación, no introducido por el despliegue de GITIN-1970.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | `connString` sin interpolación de template literal — bloqueaba toda conexión a MongoDB desde el despliegue del 31/08 hasta la corrección. | Alto |
| H2 | `daysBefore` leído de variable de entorno sin parsear a número — produce ejecuciones silenciosas sin exportar datos ni lanzar error, incluso con la conexión corregida. | Alto |
| H3 | Diseño de `run()` que acumula todo el rango de días en memoria antes de escribir a S3 — causa `Runtime.OutOfMemory` con archivos diarios grandes. Corregido mediante procesamiento y escritura secuencial por día. | Alto |
| H4 | `orderMapper()` retorna el objeto sin mapear (código muerto) — todo registro exportado históricamente usa el esquema crudo de Mongoose en lugar del esquema con claves en minúscula que la función construye pero descarta. No confirmado si esto afectó la ingesta de datos por parte de Grido. | Medio |
| H5 | La colección `news` en MongoDB tiene TTL de 15 días (GITIN-1965) — cualquier ventana de datos afectada por un bug de exportación solo es recuperable mientras esté vigente esa retención; pasado ese plazo, el dato de origen ya no existe. | Medio |
| H6 | **El backfill del rango 17-31/08 dejó un vacío permanente de 3 horas.** Al reescribir `news20260817.json` con el límite de día corregido (Argentina), se excluyó estructuralmente la ventana `08-17 00:00–03:00 UTC` — el spillover de la noche del `08-16` (21:00–24:00 hora Argentina) que la versión anterior del archivo sí contenía. `news20260816.json` (no tocado por el backfill) tampoco la contiene, ya que su propio límite termina exactamente en ese punto. Confirmado sin posibilidad de recuperación: `db.news.countDocuments()` para esa ventana exacta devolvió `0` (implausible para el horario pico de cena en Argentina) y `list-object-versions` sobre `news20260817.json` muestra una única versión (`VersionId: "null"`, versioning del bucket en estado "Suspended", sin versión previa retenida). Ni Mongo (TTL vencido) ni S3 (sobrescrito, sin versión previa) conservan el dato. | Alto (irreversible, sin mitigación posible) |
| H7 | **Compatibilidad retroactiva agregada y validada:** `saveS3()`/`run()` se modificaron para escribir ambos archivos por día — `newsYYYYMMDD.json` (límite UTC0, restaura el comportamiento previo a esta corrección) y `newsYYYYMMDD-3.json` (límite Argentina, corrección actual) — cada uno desde su propia consulta a MongoDB. Validado sobre datos reales de producción (`08-28` a `08-31`, ~285k registros): cero registros fuera de límite en ningún archivo (`utc0_out_of_bounds` / `arg3_out_of_bounds` = 0 en los 4 días). El solapamiento entre ambos archivos (~40-60% de registros compartidos por día) es consistente con el desplazamiento de ~3 horas entre ambas convenciones, no una anomalía. | Bajo (cambio validado, sin hallazgos) |

## Recursos afectados

| Componente | Impacto |
|---|---|
| mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO (Lambda) | Sin exportaciones exitosas entre el despliegue del 31/08 y la corrección completa el 01/09 ~13:24 UTC. |
| S3 (`smartfranbkp/news/`) | Archivos del rango 2026-08-17 a 2026-08-31 reescritos con datos corregidos (día UTC-3 y esquema mapeado) tras el backfill. Archivos anteriores al 17/08/2026 permanecen con el formato/lógica previa, sin posibilidad de regeneración — el TTL de Mongo ya purgó el dato de origen. **Excepción: `news20260816.json` quedó con un vacío permanente de 3 horas (ver H6), no recuperable.** |
| MongoDB Atlas (colección `news`) | TTL de 15 días — ventana de recuperación limitada; el backfill se ejecutó antes de perder el rango 17-21/08. |
| Grido (consumidor downstream, GITIN-1872) | No confirmado si el esquema sin mapear (H4) afectó la ingesta antes de esta corrección — fuera del alcance de esta investigación. |

## Comandos ejecutados

Detalle completo en `investigation.md` y en las salidas guardadas en `data/`.

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | `aws lambda get-function-configuration` (múltiples pulls) | Confirmar configuración desplegada, variables de entorno y `LastUpdateStatus` en cada etapa |
| C2 | `aws logs describe-log-streams` / `filter-log-events` | Confirmar el error `MongoParseError` en la primera invocación post-despliegue |
| C3 | `aws s3 ls s3://smartfranbkp/news/ --recursive` | Confirmar cobertura de archivos diarios y ausencia de archivos posteriores al despliegue |
| C4 | `aws s3api get-object` (range request) | Verificar contenido real exportado — timestamps y esquema de campos |
| C5 | `aws lambda invoke` (manual, iterativo) | Reproducir y validar cada corrección — `connString`, `daysBefore`, OOM, `orderMapper` |
| C6 | `aws lambda update-function-configuration` | Ajustar `DAYSBEFORE` a 15 para el backfill temporal, y luego a 2 como valor definitivo |
| C7 | `aws s3 cp` (8 archivos, `08-28` a `08-31`, ambas variantes) + análisis en Python | Verificar consistencia de contenido entre `newsYYYYMMDD.json` (UTC0) y `newsYYYYMMDD-3.json` (Argentina) tras el cambio de doble escritura |

## Acciones propuestas

1. **(SRE)** Confirmar en la ejecución programada del cron (03:30 UTC) del 02/09/2026 que el comportamiento se mantiene sin necesidad de invocación manual.
2. **(Dev)** Confirmar si los bugs de `connString`/`REGION` observados previamente en el handler de la función hermana `mongoAllCollections-to-s3-CFN-ScheduledMongoToS3-MRO2H3EOSN6E` son reales o artefactos de copia — pendiente de confirmación.
3. **(Dev)** Revisar `mongoAllCollections-to-s3-CFN-ScheduledMongoToS3-MRO2H3EOSN6E` por posibles bugs compartidos con los cuatro encontrados en esta investigación (H1-H4) — no evaluado en esta sesión.
4. **(Dev)** Confirmar con Grido si el esquema exportado sin mapear (H4) afectó la ingesta de datos antes de esta corrección.
5. **(PM/Dev)** Notificar a Grido (u otro consumidor downstream) sobre el vacío permanente de datos de H6 — 3 horas de registros del 16/08/2026 (ventana 21:00-24:00 hora Argentina) no están disponibles en ningún archivo y no son recuperables.

## Hallazgos secundarios

`DAYSBEFORE=2` quedó como valor de estado estable — más angosto que los 10-15 días usados durante la remediación. Con ese valor, una falla o ejecución omitida por más de 2 días consecutivos dejaría un vacío permanente que no se autocorrige en la siguiente ejecución exitosa, a diferencia de la ventana más amplia usada durante el backfill de esta investigación.

- **Deriva de configuración detectada (02/09/2026):** `DAYSBEFORE` seguía en `15` un día después de haberse usado temporalmente para validar la escritura dual UTC0/`-3` — nunca se revirtió a `2`. Esto hizo que la corrida no atendida de la madrugada reescribiera 5+ días en lugar de los 2 esperados (más trabajo del Lambda del previsto, pero sin incorrección de datos, dado que la reescritura es idempotente). Corregido manualmente, confirmado vía `get-function-configuration`.
- **Brecha de despliegue detectada (02/09/2026):** los campos `originalid`/`displayid`/`canje` agregados a `orderMapper()` el 01/09 (después de que el despliegue de escritura dual ya estaba confirmado en producción) nunca llegaron a desplegarse. Confirmado descargando la exportación real del 01/09 (`data/consistency_check_20260902/`): ambos campos ausentes en el 100% de los registros de ambas variantes de archivo. El `handler.js` local en esta carpeta de evento tiene la corrección; producción todavía no.

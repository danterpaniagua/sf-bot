# Eventos — 20260901_grido-redacted-etl-lambda

## 2026-09-01 — Apertura del evento, identidad de ticket señalada como ambigua

He identificado una inconsistencia entre dos investigaciones previas de la misma sesión: ambas asumían que GITIN-1874 correspondía al Lambda Node.js existente (`mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO`, ya corregido bajo GITIN-1970). El título "Creación de ETL -> S3" encaja mejor con un pipeline nuevo que con una corrección a uno existente. He procedido bajo el supuesto de que GITIN-1874 corresponde a este nuevo Lambda Python, pendiente de confirmación.

## 2026-09-01 — Criterio de filtro corregido tres veces hasta converger

He detectado que `extraData.platform: "PediGrido"` habría excluido silenciosamente ~80% del volumen real de Grido — confirmado con datos reales de 4 días (144.964 registros): PedidosYa representa 66.3% del volumen, PediGrido solo 19.4%. He verificado además que `order.tenant.name` está completamente ausente de los archivos `-3`/UTC0 — cero ocurrencias en 4 archivos reales descargados, confirmado tanto por revisión de código como empíricamente. He confirmado `extradata.chain == "Grido"` como el criterio correcto: presente en el 100% de los registros, identifica correctamente órdenes de Grido sin importar la plataforma de origen.

## 2026-09-01 — Lista de campos v1 corregida contra la salida real de orderMapper()

He detectado que la lista de campos confirmada en la investigación de GITIN-1880 fue escrita contra el esquema crudo de Mongoose, no contra la salida real de `orderMapper()`. He encontrado tres campos completamente ausentes del export (`originalId`, `displayId`, `details[].canje`) y he confirmado, vía consulta a MongoDB, que existen y están 100% poblados en los documentos crudos — simplemente `orderMapper()` nunca los copia. He agregado los tres campos a `orderMapper()` en `handler.js`. El resto de los campos de la lista v1 existen pero con nombres en minúscula distintos a los listados originalmente.

## 2026-09-01 — Auditoría completa de campos, sin hallazgos de riesgo

He redactado `scripts.js` con seis consultas de inventario de campos (`$objectToArray` en cada nivel del documento) y he ejecutado la auditoría completa contra datos reales de Grido. He encontrado 12 campos adicionales clasificados SEND (sin PII) ausentes del export, ninguno clasificado REDACT. Al confirmar contra el pedido real de Grido, ninguno de esos 12 campos resultó ser necesario — la lista de campos quedó finalizada sin cambios adicionales a `orderMapper()`.

## 2026-09-01 — Decisión de negocio: dni incluido pese a clasificación REDACT

`customer.dni` queda incluido en el export, pese a su clasificación REDACT en `field-classification.md` ("campo de mayor sensibilidad de la colección"), por necesidad operativa de correlación con la base de datos de Grido. He dejado registrado que esta justificación es de negocio, no un sign-off confirmado de Legal/PM — ese sign-off nunca fue verificado independientemente.

## 2026-09-01 — Handler construido y validado contra datos reales

He redactado `handler.py`, implementando el filtro, la lista de campos finalizada, y las transformaciones de formato acordadas (fechas envueltas en formato MongoDB Extended JSON, ids como string). He redactado `test_local.py` para validar `transform()` sin llamadas a AWS, contra los archivos `-3` reales ya descargados en la investigación de GITIN-1970 (145.389 registros totales, 144.964 de Grido). Primera corrida: 0 errores de esquema, 0 fugas de campos REDACT, pero he detectado que `order.id`/`customer.id` salían como número en lugar de string en algunos registros. Corregido con coerción explícita; segunda corrida sin errores.

## 2026-09-01 — Ticket y bitácora redactados

He redactado `ops.md` y este archivo de eventos.

## 2026-09-02 — Identidad de ticket confirmada, correcciones cruzadas

Se confirmó la URL de Jira para GITIN-1874. He actualizado `investigation.md` y `ops.md` de esta carpeta, y he corregido la referencia incorrecta en las investigaciones de GITIN-1970 y GITIN-1880, que asumían que GITIN-1874 era el Lambda Node.js existente en lugar de este Lambda Python nuevo.

## 2026-09-02 — Riesgo de memoria por día señalado, mismo patrón que el OOM de GITIN-1970

He verificado en `handler.py` que `process_day()`, si bien procesa correctamente un día a la vez entre días, carga el archivo fuente completo en memoria dentro de un mismo día y arma la lista completa de salida antes de escribir. Con archivos fuente observados de hasta ~180 MB y este Lambda nunca desplegado (memoria nunca configurada ni probada), he documentado el riesgo de repetir la misma clase de falla de memoria ya encontrada una vez esta sesión, antes de que ocurra en un despliegue real.

## 2026-09-02 — Soporte de ejecución local agregado (DRY_RUN, rango explícito, resume)

He agregado a `handler.py` las variables de entorno `DRY_RUN`, `START_DATE`/`END_DATE` (rango explícito, sobre-escribe la ventana rotativa `DAYSBEFORE`) y `RESUME`/`PROGRESS_FILE` (checkpoint local, mismo patrón que `scripts.py` de GITIN-1980), más un punto de entrada `if __name__ == "__main__"` para poder ejecutarlo directamente. Mantiene la firma `event`/`context` intacta para seguir siendo válido como handler real de Lambda. Verificado con `py_compile` — sintaxis correcta.

## 2026-09-02 — Rol de ejecución IAM creado y confirmado

He confirmado la creación de `grido-redacted-etl-lambda-role` (`arn:aws:iam::382381053403:role/grido-redacted-etl-lambda-role`) vía `data/iam_role_list_policies.json`, `data/iam_role_s3_policy.json` y `data/iam_role_attached_policies.json`: política inline `grido-etl-s3-access` con permisos mínimos (`s3:GetObject` en `smartfranbkp/news/*`, `s3:PutObject` en `smartpedidos-orders/grido/*`) y la política administrada `AWSLambdaBasicExecutionRole` para CloudWatch Logs. He actualizado `investigation.md` y `ops.md` con el detalle.

## 2026-09-02 — Primera escritura real ejecutada y validada

He ejecutado `handler.py` localmente contra datos reales de S3 (`2026-08-28`–`2026-08-31`, perfil `dpaniagua.smartfran`), primero en `DRY_RUN` y luego en modo real. He encontrado un problema de credenciales en el camino: un intento anterior con el placeholder literal `<your-profile-name>` (nunca sustituido) produjo `InvalidAccessKeyId` — no era un problema de permisos, sino credenciales inválidas por defecto. Lo he resuelto usando el nombre de perfil real (`aws configure list-profiles`). He descargado y validado los 4 archivos escritos (`data/first_write_validation/`) contra el esquema confirmado: 144.818 registros totales, 0 errores de esquema, 0 fugas de campos REDACT, `observations` nunca no-vacío, 0 errores de formato `$date`. Los conteos coinciden exactamente con los de `DRY_RUN`.

## 2026-09-02 — Correlación de dni por plataforma, sin ID de transacción dedicado

He cruzado la salida del 08-28 contra el campo `extradata.platform` del archivo `-3` fuente y he confirmado que `dni` solo está presente en registros de PediGrido (5.034) e I+D (997) — nunca en PedidosYa, Rappi, UberEats, MercadoPago o Toque. He verificado en `platforms/interfaces/*.js` que no existe ningún campo de ID de transacción/pago dedicado (`paymentId` en `pedidosYa.js` es un enum de tipo de pago, no una referencia única); el equivalente más cercano disponible es `order.id`. He confirmado `order.id` presente en el 100% de los 144.818 registros escritos.

## 2026-09-02 — Función Lambda creada y desplegada

He creado la función `grido-redacted-etl` vía `aws lambda create-function` (`data/lambda_create_function_output.json`): `arn:aws:lambda:us-east-1:382381053403:function:grido-redacted-etl`, runtime `python3.12`, rol `grido-redacted-etl-lambda-role`, handler `handler.handle`, `Timeout=900`, `MemorySize=4096` (mismo valor que el Lambda Node.js de GITIN-1970, como mitigación del riesgo de memoria señalado — no la corrección de streaming real, que sigue sin implementarse). Variables de entorno: `SOURCE_BUCKET=smartfranbkp`, `DEST_BUCKET=smartpedidos-orders`, `DAYSBEFORE=2`, `REGION=us-east-1`. He confirmado `CodeSha256` contra el zip subido. Sin trigger de EventBridge todavía — solo invocable manualmente.

## 2026-09-02 — Confirmado: dni no está oculto en observations para las plataformas sin dni

He verificado, con `scripts_dni_check.js` sobre 20 órdenes reales de las 7 plataformas (`data/dni_observations_check.txt`), si `dni` podría estar embebido en `order.observations` en texto libre para las plataformas donde el campo estructurado viene null/vacío. Resultado limpio: ninguno de los 20 valores de `observations` contiene nada con forma de DNI — son notas de medio de pago, referencias de pedido o números de recibo propios de Toque. Confirmado que `dni` genuinamente no se recolecta para esas plataformas, no que esté presente en otro lugar del documento.

## 2026-09-02 — CHAIN_FILTER y DEST_PREFIX vueltos configurables

He hecho configurables vía variables de entorno `CHAIN_FILTER` (antes hardcodeado a `"Grido"`) y `DEST_PREFIX` (antes hardcodeado a `"grido"`), sin cambiar el comportamiento por defecto. Esto permite reusar el mismo código para otra plataforma mediante un despliegue Lambda separado con variables distintas, sin tocar el código fuente — aclarado que `transform()` y la lista de campos siguen sin validarse contra ningún dato que no sea el de Grido.

## 2026-09-02 — Lista de campos reducida en 4 campos, redesplegado

La versión actualizada del pedido de campos de Grido difiere de la original solo en la ausencia de cuatro campos `order.*`: `pickupDateOnShop`, `preOrder`, `observations`, `ownDelivery`. He confirmado la diferencia con un diff directo antes de tocar código. He actualizado `transform()` para omitir los cuatro campos (esto también vuelve innecesaria la lógica previa de blanqueo de `observations`, ya que el campo ahora no se envía en absoluto) y he actualizado el esquema esperado en `test_local.py`, agregando además una verificación explícita de que esas cuatro claves nunca reaparecen. He re-ejecutado la validación local: 0 errores de esquema sobre los 144.964 registros reales de Grido. He redesplegado con `zip -f function.zip handler.py` + `update-function-code` (`data/lambda_update_code_output_2.json`) y he confirmado `State: Active`, `LastUpdateStatus: Successful` (`data/lambda_update_code_confirm.json`). Pendiente: no he vuelto a correr una escritura real de validación contra esta versión desplegada específicamente — la validación de 144.964 registros fue previa al despliegue, y la validación de escritura real (`data/first_write_validation/`) fue contra el esquema anterior, que todavía incluía los cuatro campos ahora eliminados.

## 2026-09-02 — Primer backfill real invocado (DAYSBEFORE=124), dos invocaciones superpuestas detectadas

He configurado `DAYSBEFORE=124` en la función desplegada vía `update-function-configuration` para intentar un backfill hasta el 2026-05-01, y confirmé `LastUpdateStatus: Successful` antes de invocar (`data/lambda_update_config_daysbefore_124_confirm.json`). La invocación con `aws lambda invoke` tuvo un timeout de lectura del lado del cliente (~60s por defecto, la ejecución real tomó 3.6–4.3 min). He confirmado vía CloudWatch (`data/lambda_invoke_daysbefore_124_log_tail.txt`) que en realidad corrieron **dos invocaciones distintas y superpuestas en el tiempo** (RequestIds diferentes), casi con certeza por el reintento automático del AWS CLI tras el timeout de lectura. Ambas reportaron el mismo resultado (`written: 16, no-grido-records: 108`). He verificado directamente contra S3 (`aws s3 ls`, `data/s3_grido_backfill_listing.txt`) que esto no causó corrupción ni duplicación — existen exactamente 16 objetos, ya que las escrituras son idempotentes por clave de día y ambas corridas transformaron los mismos datos fuente sin cambios entre sí.

## 2026-09-02 — Hallazgo real: datos de cadena Grido no existen antes de 2026-08-17

De los 124 días solicitados, he confirmado que solo 16 produjeron registros con `extradata.chain == "Grido"` — los 16 objetos escritos cubren exactamente 2026-08-17 a 2026-09-01, consecutivos, sin huecos (`data/s3_grido_backfill_listing.txt`). El resto de los días visibles en el log (2026-05-01 a 2026-06-26) muestran `0/N registros Grido` en cada uno, con N entre ~10.000 y ~47.000 registros totales por día. Esto no es un bug del filtro ni de `transform()` — es un hecho sobre los datos fuente. Pendiente: revertir `DAYSBEFORE` a `2` para el futuro schedule de EventBridge — aún no hecho.

## 2026-09-02 — Causa raíz precisada: falta la clave extradata completa, no solo chain

He escrito `scripts_chain_field_check.py` y lo he corrido contra archivos `-3` reales descargados de S3: `2026-05-01` (46.959 registros) y `2026-08-01` (34.178 registros) tienen `records with extradata key: 0` — la clave `extradata` está completamente ausente en el 100% de los registros, no solo su subcampo `chain`. Contra el archivo de control `2026-08-28` (ya descargado bajo `20260831_lambda-s3-export-utc3/data/consistency_check/`), `extradata` está presente en el 100% de los 29.460 registros, con valores `chain` de `Grido: 29.325` / `Weiss: 135`. He confirmado así que `extradata` se agregó al esquema del registro en algún punto entre 2026-08-01 y 2026-08-28 (acotado a 2026-08-17 por los resultados día a día del backfill) — no es un campo que siempre existió y recién empezó a etiquetarse "Grido" (`data/chain_field_check_summary.txt`).

## 2026-09-02 — Causa raíz real encontrada: bug de sensibilidad a mayúsculas, no ausencia de datos

He verificado directamente contra los archivos `-3` reales descargados que `2026-05-01` y `2026-08-01` sí tienen la clave `extraData` (con D mayúscula) presente en el 100% de los registros — 46.959/46.959 y 34.178/34.178. Parseando con el nombre correcto, `2026-05-01` tiene `chain: "Grido"` en 46.917 de 46.959 registros (99,9%). He confirmado que estos archivos están en el formato crudo de MongoDB (`platformId`, `originalId`, `tenant` presentes; cero ocurrencias de `platformid` minúscula) — un formato completamente distinto al que produce `orderMapper()` (`extradata`, `originalid`, sin `tenant`). Mi propio script de diagnóstico y `handler.py` (el Lambda desplegado) solo buscaban la clave en minúscula, por lo que ambos reportaban ausencia de datos donde en realidad había datos reales bajo un nombre de clave distinto.

## 2026-09-02 — handler.py corregido para reconocer ambos formatos, redesplegado, backfill completo exitoso

He agregado a `handler.py` un helper `get_ci()` que prueba múltiples nombres de clave en orden, aplicado a cada campo cuyo nombre difiere entre los dos formatos (`platformid`/`platformId`, `ordertime`/`orderTime`, `totalamount`/`totalAmount`, `createdat`/`createdAt`, etc.), más `get_extradata()` para el filtro de cadena. He validado localmente contra los archivos reales antes de desplegar: `2026-05-01` pasó de 0/46.959 a 46.917/46.959 coincidencias, `2026-08-01` de 0/34.178 a 34.044/34.178, y el archivo de control `2026-08-28` se mantuvo sin cambios en 29.325/29.460 (`data/handler_shape_fix_local_validation.txt`). He redesplegado (`CodeSha256` nuevo confirmado), configurado `DAYSBEFORE=123`, e invocado con `--cli-read-timeout 900` para evitar la duplicación de invocaciones del intento anterior.

**Resultado: los 123 de 123 días solicitados fueron escritos, no 16.** La tasa de coincidencia con Grido es consistentemente ~99% en todo el rango (2026-05-02 a 2026-09-01). He confirmado el estado final real de S3: exactamente 123 objetos, consecutivos, sin huecos (`data/s3_grido_backfill_listing_after_fix.txt`). Esto revierte por completo la conclusión original de H8 — nunca existió un piso de datos en 2026-08-17, era el Lambda fallando en leer datos reales que sí estaban presentes.

## 2026-09-02 — Día faltante 2026-05-01 completado, configuración revertida

He verificado que el rango de `DAYSBEFORE=123` cubrió 2026-05-02 a 2026-09-01 — un día menos que el 2026-05-01 originalmente pedido. Lo he completado con una invocación de un solo día (`START_DATE=2026-05-01`, `END_DATE=2026-05-01`): 46.917/46.959 registros Grido escritos en `grido/2026/05/news20260501.json`, coincidiendo exactamente con la validación local previa. Rango final completo: 2026-05-01 a 2026-09-01, 124 días consecutivos, sin huecos. He revertido la configuración a `DAYSBEFORE=2` (confirmado `LastUpdateStatus: Successful`), quedando lista para un futuro schedule de EventBridge con la ventana rotativa normal.

## 2026-09-02 — Validación final: salida real confirmada 100% Grido, chain y tenant consistentes

He descargado la salida real escrita (`grido/2026/05/news20260501.json`) y he cruzado cada `order.id` contra el conjunto filtrado por `chain` del archivo fuente. Un primer intento mostró 8.678 IDs "no encontrados" — he rastreado la causa a una inconsistencia de tipo en mi propio script de verificación (el `order.id` del origen es `int` para 8.678 registros y `str` para el resto; la salida transformada siempre lo convierte a string), no un problema real. Normalizado y re-verificado: 46.917 registros de salida coinciden exactamente con el conteo filtrado por Grido del origen, 0 registros de otras cadenas (`Weiss`) filtrados hacia la salida, 0 duplicados, 0 registros de salida sin un registro Grido correspondiente en el origen. He confirmado además que `chain` y `tenant.name` son 100% consistentes como señal de filtro — 0 discrepancias en 81.137 registros verificados entre `2026-05-01` y `2026-08-01`.

## 2026-09-03 — Operación normal confirmada y schedule de EventBridge creado

He ejecutado la primera invocación real con `DAYSBEFORE=2` desde la reversión a la ventana normal, tras todas las correcciones del bug de formato dual. He confirmado 2/2 días escritos sin errores (`2026-09-01`: 18.836/18.897 Grido; `2026-09-02`: 22.668/22.735 Grido), 5,2 segundos de duración total. He creado el schedule de EventBridge (`grido-redacted-etl-daily`, `cron(0 4 * * ? *)`, con margen de ~29 minutos después del cron del Lambda fuente), otorgado el permiso correspondiente y configurado el target. Confirmado `State: ENABLED` y target correctamente apuntando a `grido-redacted-etl`. GITIN-1874 queda completamente operativo y automatizado, con las alertas de fallo de GITIN-1979 ya conectadas.

## 2026-09-02 — Código de orderMapper() revisado, hallazgo de causa raíz por código

He revisado el código fuente actual de `orderMapper()` (Lambda `mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO`, compartido en la conversación): el bloque `extradata` se asigna sin ninguna guarda (`order.extraData.chain`, etc.), a diferencia del subobjeto `rejected` dos líneas más abajo, que sí tiene `if (order.extraData.rejected)`. He confirmado que si `order.extraData` fuera `undefined`, esto lanzaría una excepción dentro del `.map()` y abortaría todo el backfill restante (el `try/catch` de `run()` envuelve todo el bucle de días, no cada día individualmente) — no produciría silenciosamente un registro con `extradata` vacío. Dado que los exports pre-corte existen completos y solo les falta la clave `extradata` por completo (no presente como `{}`), he concluido que la versión de `orderMapper()` que generó esos exports más viejos no tenía este bloque de código en absoluto — se agregó después.

## 2026-09-02 — Intento de verificar MongoDB crudo, inconcluso por necesidad: la ventana de retención no llega tan atrás

He ejecutado `db.news.countDocuments()` contra el 2026-08-01 y obtuve 0. He verificado la causa: `db.news.find({}, {createdAt:1,_id:0}).sort({createdAt:1}).limit(1)` muestra que el `createdAt` más antiguo en la colección viva es 2026-08-18T13:08:43.302Z — MongoDB retiene aproximadamente una ventana móvil de 15 días a partir de hoy (2026-09-02). He revisado `db.news.getIndexes()` y confirmado que no existe ningún índice TTL (ninguno de los 13 índices tiene `expireAfterSeconds`) — esta retención está impuesta por algo externo a MongoDB, no por una expiración nativa. Con esto he confirmado que el documento crudo de origen para 2026-08-01 ya no existe en MongoDB, sin importar qué `extraData` tuviera — el export S3 es el único registro sobreviviente para cualquier fecha anterior a la ventana de retención, y carece de `extradata` antes de 2026-08-17. He dejado establecido 2026-08-17 como piso duro para el backfill de Grido, no una limitación de código evitable reexportando desde Mongo.

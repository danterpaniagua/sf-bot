# 01-09-2026_grido-redacted-etl-lambda

**Tags:** SmartPedidos, MongoDB, AWS, DEPLOY

## Resumen

Se construyó y desplegó un nuevo Lambda Python (`grido-redacted-etl`, GITIN-1874, "[SP] Creación de ETL -> S3", identidad confirmada 2026-09-02) que lee los archivos `-3` ya exportados en `smartfranbkp/news/` (GITIN-1970/1980), filtra los registros de la cadena Grido, aplica una lista de campos permitidos con redacción de PII confirmada contra el pedido real de Grido, y escribe el resultado en el bucket `smartpedidos-orders` (creado bajo GITIN-1880). El criterio de filtro y la lista de campos pasaron por varias correcciones reales antes de converger en una versión validada contra 144.964 registros reales, desplegada y validada con escrituras reales de producción. Un primer intento de backfill histórico (hasta 2026-05-01) pareció confirmar que los datos de cadena Grido solo existían en el origen desde 2026-08-17 — esa conclusión resultó **incorrecta**: era un bug real en `handler.py` (comparación de nombres de campo sensible a mayúsculas/minúsculas contra dos formatos de archivo distintos coexistiendo bajo el mismo sufijo `-3`), no una limitación de datos. Corregido, redesplegado, y el backfill completo (2026-05-01 a 2026-09-01, 124 días) se ejecutó exitosamente — ver H8.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-1874](https://smartit-ar.atlassian.net/browse/GITIN-1874) |
| ID alerta | — (tarea planificada, no incidente) |
| Sistema | Lambda `grido-redacted-etl` (`arn:aws:lambda:us-east-1:382381053403:function:grido-redacted-etl`) → `smartpedidos-orders` |
| Severidad | — (construcción de ETL, no incidente) |
| Detectado | — (no aplica) |
| Resuelto | 2026-09-03 — desplegado, bug de formato de campo corregido, backfill histórico completo (2026-05-01 a 2026-09-01), operación normal confirmada, schedule de EventBridge activo, alertas de fallo conectadas (GITIN-1979). Quedan pendientes items menores de `Acciones propuestas` (confirmación de esquema con Grido, sign-off de `dni`) |
| Responsable | Dante Paniagua, SRE |

## Causa raíz

No aplica en sentido de incidente — este es un desarrollo nuevo. El trabajo relevante fue de diseño/corrección: el criterio de filtro y la lista de campos originalmente definidos (en la investigación de GITIN-1880) no coincidían con la estructura real de los datos fuente (`orderMapper()` en `handler.js`), lo cual se detectó y corrigió íntegramente en esta sesión antes de construir el handler.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | El criterio de filtro pasó por tres candidatos antes de converger en `extradata.chain == "Grido"`: `extraData.platform: "PediGrido"` habría descartado ~80% del volumen real de Grido (confirmado con datos reales: PediGrido es solo 19.4% del volumen); `order.tenant.name` está completamente ausente de los archivos `-3`/UTC0 (`orderMapper()` nunca lo copia). | Alto (evitado antes de desplegar) |
| H2 | La lista de campos v1 (definida en GITIN-1880) fue escrita contra el esquema crudo de Mongoose, no contra la salida real de `orderMapper()`. Tres campos (`originalId`, `displayId`, `details[].canje`) estaban completamente ausentes del export; el resto tenía nombres en minúscula distintos a los listados. Corregido antes de construir el handler. | Alto (evitado antes de desplegar) |
| H3 | `customer.dni` está clasificado REDACT en `field-classification.md` ("campo de mayor sensibilidad de la colección"), requiriendo confirmación de Legal/PM para su inclusión. Usuario decidió incluirlo de todas formas por necesidad operativa (correlación con la base de datos propia de Grido) — el sign-off de Legal/PM en sí nunca fue confirmado, solo la justificación de negocio. Documentado como decisión deliberada, no como omisión. | Medio (decisión de negocio explícita, riesgo de compliance no resuelto) |
| H4 | Bug real encontrado en pruebas locales: `order.id`/`customer.id` salían como número en algunos registros (datos fuente inconsistentes entre plataformas) en lugar del string que exige el esquema de Grido. Corregido con coerción explícita a string; revalidado sin errores. | Medio (corregido antes de desplegar) |
| H5 | `orderTime`/`pickupDateOnShop` de un registro real de muestra tiene formato no estándar (sin sufijo `Z`, segundos fraccionarios no convencionales) — presente en el dato fuente, no introducido por este código. No corregido — causa raíz no investigada, podría afectar el parseo de fechas del lado de Grido. | Bajo (observado, no resuelto) |
| H6 | `customer.dni` solo está disponible en el dato fuente para las plataformas PediGrido e I+D (nunca para PedidosYa, Rappi, UberEats, MercadoPago, Toque), y ni siquiera de forma garantizada dentro de esas dos. No existe ningún campo de ID de transacción/pago dedicado en el dato fuente — `order.id` es el único identificador disponible, enviado tres veces (`id`/`originalId`/`displayId`). | Bajo (limitación de datos, documentada) |
| H7 | Primer intento de backfill histórico (`DAYSBEFORE=124`, hasta 2026-05-01) produjo dos invocaciones Lambda superpuestas, casi con certeza por reintento automático del AWS CLI tras un timeout de lectura del lado del cliente (~60s por defecto, ejecución real de 3.6–4.3 min). Verificado vía `aws s3 ls` que el resultado final no tiene corrupción ni duplicación (exactamente 16 objetos, escritura idempotente por clave de día). | Bajo (evitable en próximas invocaciones manuales con `--cli-read-timeout` mayor o `--invocation-type Event`) |
| H8 | **Bug real en `handler.py`, corregido — no era una limitación de datos.** El primer backfill (`DAYSBEFORE=124`) reportó solo 16 de 124 días con registros `extradata.chain == "Grido"`. Investigado inicialmente como si fuera ausencia real de datos (tres líneas de evidencia parecían confirmarlo — ver detalle en `investigation.md`), pero la causa real, confirmada por inspección directa de los archivos `-3` reales: bajo el mismo sufijo `-3` coexisten **dos formatos de archivo distintos** — uno crudo de MongoDB (`extraData` con D mayúscula, `originalId`, `platformId`, `tenant`) para fechas anteriores a ~2026-08-17, y uno transformado por `orderMapper()` (`extradata` minúscula, `originalid`, `platformid`, sin `tenant`) para fechas posteriores. `handler.py` solo reconocía el segundo formato — cada `.get()` sobre el formato crudo devolvía `None` silenciosamente (Python no lanza error sobre una clave ausente), tratando registros con datos reales de Grido como si no existieran. Confirmado con `2026-05-01`: 46.917 de 46.959 registros (99,9%) tenían `chain: "Grido"`, no 0. | Alto (bug de producción que descartaba silenciosamente ~99% de los datos de un rango extenso — corregido y verificado, ver Acciones propuestas) |

## Recursos afectados

| Componente | Impacto |
|---|---|
| Lambda `grido-redacted-etl` | Desplegado y activo (`python3.12`, `Timeout=900`, `MemorySize=4096`). Sin trigger EventBridge — solo invocable manualmente. |
| `grido-redacted-etl-lambda-role` (IAM) | Rol de ejecución con permisos mínimos (`s3:GetObject` en `smartfranbkp/news/*`, `s3:PutObject` en `smartpedidos-orders/grido/*`) más `AWSLambdaBasicExecutionRole`. |
| `smartfranbkp/news/` (S3) | Solo lectura — este Lambda no modifica los archivos fuente. |
| `smartpedidos-orders` (S3) | Destino de escritura — backfill histórico completo el 2026-09-02: 124 objetos, `grido/2026/05/` a `grido/2026/09/`, cubriendo 2026-05-01 a 2026-09-01 sin huecos, tras corregir el bug de H8. |
| MongoDB (`news` collection) | No consultada directamente por este Lambda — toda la lógica opera sobre los archivos `-3` ya exportados. |

## Comandos ejecutados

Detalle completo en `investigation.md`, `scripts.js` y `test_local.py`.

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | `mongosh` — conteo de plataformas por cadena | Confirmar que `extradata.chain` identifica correctamente órdenes de Grido en múltiples plataformas (PedidosYa, Rappi, UberEats, etc.), no solo PediGrido |
| C2 | `grep`/`python3` sobre archivos `-3` descargados | Confirmar ausencia total del campo `tenant` en los datos ya exportados |
| C3 | `mongosh` — conteo de campos `originalId`/`displayId`/`canje` | Confirmar que existen y están 100% poblados en los documentos crudos de Mongo |
| C4 | `scripts.js` (6 queries `$objectToArray`) | Auditoría completa de campos presentes en cada nivel del documento, para detectar cualquier campo omitido por `orderMapper()` |
| C5 | `test_local.py` | Validar `transform()` contra 145.389 registros reales (144.964 de Grido) sin llamadas a AWS — 0 errores de esquema, 0 fugas de campos REDACT |
| C6 | `handler.py` (ejecución local, `DRY_RUN` y real) | Primera escritura real de producción, 2026-08-28 a 2026-08-31: 144.818 registros, 0 errores de esquema, 0 fugas REDACT (`data/first_write_validation/`) |
| C7 | `aws lambda create-function` / `update-function-code` | Creación y redespliegue del Lambda (`data/lambda_create_function_output.json`, `data/lambda_update_code_output_2.json`) |
| C8 | `scripts_dni_check.js` | Confirmar que `dni` no está embebido en `observations` para las plataformas donde el campo estructurado viene vacío (`data/dni_observations_check.txt`) |
| C9 | `aws lambda update-function-configuration` + `invoke` (`DAYSBEFORE=124`) | Primer backfill histórico real hasta 2026-05-01 (`data/lambda_update_config_daysbefore_124_confirm.json`, `data/lambda_invoke_daysbefore_124_log_tail.txt`) |
| C10 | `aws s3 ls s3://smartpedidos-orders/grido/ --recursive` | Confirmar el estado final real de S3 tras el backfill — 16 objetos, 2026-08-17 a 2026-09-01 (`data/s3_grido_backfill_listing.txt`) |
| C11 | `scripts_chain_field_check.py` sobre archivos `-3` reales (`2026-05-01`, `2026-08-01`, `2026-08-28`) | Confirmar causa raíz de H8: la clave `extradata` completa está ausente antes de 2026-08-17, no solo su subcampo `chain` (`data/chain_field_check_summary.txt`) |
| C12 | `mongosh` — `db.news.countDocuments()`, `find().sort().limit(1)`, `getIndexes()` para 2026-08-01 | Confirmar retención de MongoDB (~15 días, sin índice TTL) — relevante para la pregunta de re-exportación directa desde Mongo, no para la causa raíz final de H8 (ver C13) |
| C13 | `grep`/`python3` directo sobre `2026-05-01-3.json`/`2026-08-01-3.json` reales | Encontrar la causa raíz real de H8: `extraData` (D mayúscula) presente en el 100% de los registros, `chain: "Grido"` en 46.917/46.959 (99,9%) — refuta la conclusión previa de ausencia de datos |
| C14 | `handler.py` corregido (`get_ci()`/`get_extradata()`), validación local contra archivos reales | Confirmar el fix antes de desplegar: 0 → 46.917/46.959 y 0 → 34.044/34.178 coincidencias Grido, sin regresión en el archivo de control (`data/handler_shape_fix_local_validation.txt`) |
| C15 | `aws lambda update-function-code` + `update-function-configuration` (`DAYSBEFORE=123`) + `invoke --cli-read-timeout 900` | Redespliegue y backfill completo tras el fix — 123/123 días escritos (`data/lambda_invoke_daysbefore_123_log_tail.txt`) |
| C16 | `aws lambda update-function-configuration` (`START_DATE`/`END_DATE=2026-05-01`) + `invoke` | Completar el día faltante 2026-05-01 (el rango de `DAYSBEFORE=123` había quedado un día corto) — 46.917/46.959 registros escritos |
| C17 | `aws s3 ls s3://smartpedidos-orders/grido/ --recursive` (post-fix, antes del día faltante) | Confirmar estado tras el backfill de 123 días — 123 objetos, 2026-05-02 a 2026-09-01, sin huecos (`data/s3_grido_backfill_listing_after_fix.txt`); el día 2026-05-01 se agregó después (C16) — no se re-corrió este listado tras ese último write individual |
| C18 | Verificación cruzada `order.id` salida real vs. origen filtrado por `chain` (`data/output_vs_source_grido_only_check.txt`) | Confirmar que la salida real escrita es 100% Grido: 46.917/46.917 coinciden con el origen filtrado, 0 registros de otras cadenas filtrados, 0 duplicados |
| C19 | Verificación `chain` vs. `tenant.name` sobre 81.137 registros reales (`data/chain_vs_tenant_consistency_check.txt`) | Confirmar que `extradata.chain == "Grido"` y `order.tenant.name == "grido"` son 100% consistentes como criterio de filtro — 0 discrepancias |
| C20 | `aws lambda invoke` con `DAYSBEFORE=2` (ventana normal, post-fix) | Confirmar operación normal diaria, no solo el backfill histórico — 2/2 días escritos sin errores (`data/lambda_invoke_normal_run_log_tail.txt`) |
| C21 | `aws events put-rule`/`put-targets` + `aws lambda add-permission` | Crear el schedule de EventBridge (`grido-redacted-etl-daily`, `cron(0 4 * * ? *)`), confirmado `ENABLED` y correctamente targeteado (`data/eventbridge_describe_rule.json`) |

## Acciones propuestas

1. ~~Confirmar la identidad real del ticket GITIN-1874 y obtener la URL de Jira~~ — **hecho (02/09/2026)**.
2. **(Dev)** Confirmar contra un documento de especificación real de Grido (no solo el ejemplo único provisto) el formato `$date` de MongoDB Extended JSON y la coerción de tipos en `details[]` (`count`/`price`/`sku` a string, `groupId` a número).
3. **(Dev)** Confirmar la convención de nombre de archivo de destino (`smartpedidos-orders/grido/YYYY/MM/newsYYYYMMDD.json`, sin sufijo `-3`) — está en producción tal como quedó definida, pero nunca se confirmó formalmente con Grido.
4. ~~Revertir `DAYSBEFORE` de `124`/`123` a `2`~~ — **hecho (02/09/2026)**: configuración revertida tras completar el backfill histórico, `START_DATE`/`END_DATE` eliminados, lista para un schedule regular.
5. **(PM/Legal)** Confirmar si existe sign-off real para incluir `customer.dni` en el export a Grido, más allá de la justificación operativa ya registrada.
6. ~~Desplegar el Lambda~~ — **hecho (02/09/2026)**: función `grido-redacted-etl` creada, validada con una primera escritura real (144.818 registros, 0 errores), redesplegada con la lista de campos final narrowed. **Redesplegada nuevamente el mismo día** con el fix de H8 (soporte para ambos formatos de archivo), tras lo cual el backfill histórico real cubrió los 124 días completos (2026-05-01 a 2026-09-01), no solo 16.
7. ~~Crear rol de ejecución IAM~~ — **hecho (02/09/2026)**: `grido-redacted-etl-lambda-role`, permisos mínimos (`s3:GetObject` en `smartfranbkp/news/*`, `s3:PutObject` en `smartpedidos-orders/grido/*`, más `AWSLambdaBasicExecutionRole` para logs).
8. ~~Definir y crear el trigger de EventBridge para el schedule regular~~ — **hecho (2026-09-03)**: `grido-redacted-etl-daily`, `cron(0 4 * * ? *)`, con margen de ~29 minutos después del cron `30 3 * * ? *` del Lambda fuente. Confirmado `State: ENABLED`, target correctamente configurado. Debe programarse después del cron `30 3 * * ? *` (03:30 UTC) del Lambda `mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO` (fuente de los archivos `-3`), con margen suficiente sobre su finalización real (~03:31:46 UTC observado, ver `20260831_lambda-s3-export-utc3/investigation.md`) — en progreso.
9. **(Dev)** Decidir el fix de memoria por día (riesgo de OOM señalado, ver `investigation.md`) — actualmente mitigado con `MemorySize=4096` (mismo valor que el Lambda Node.js de GITIN-1970), no con streaming real.
10. **(SRE)** En invocaciones manuales largas futuras, usar `--cli-read-timeout` alto o `--invocation-type Event` en `aws lambda invoke` para evitar el reintento automático del CLI que produjo dos invocaciones superpuestas en el primer intento de backfill (ver H7) — sin impacto esta vez, pero evitable. Aplicado correctamente en el backfill posterior al fix.
11. **(Dev)** Aplicar el mismo fix de detección de formato dual (H8) a `scripts_chain_field_check.py` si se va a reutilizar como diagnóstico independiente — actualmente solo reconoce el formato transformado.

## Hallazgos secundarios

Desafíos que condicionaron el enfoque de esta tarea, sin ser hallazgos de causa raíz en sí mismos:

- **Identidad de ticket ambigua, resuelta:** dos investigaciones previas de la misma sesión (GITIN-1970, GITIN-1880) asumían que GITIN-1874 correspondía al Lambda Node.js ya existente y corregido — confirmado incorrecto el 02/09/2026, GITIN-1874 es este Lambda Python nuevo. Ambos archivos corregidos para referenciar esta carpeta en su lugar.
- **Cadena de dependencias entre tres tickets previos:** esta construcción dependió de artefactos de GITIN-1873 (`field-classification.md`), GITIN-1880 (bucket `smartpedidos-orders`, lista de campos v1) y GITIN-1970 (los archivos `-3` como fuente de datos) — cada uno con inconsistencias propias (criterio de filtro, campos ausentes en el export real) que debieron reconciliarse antes de poder construir el handler con confianza.
- **La documentación existente no bastó — cada decisión de diseño necesitó verificación contra datos reales:** tanto el criterio de filtro como la lista de campos "confirmados" en sesiones anteriores resultaron no coincidir con la realidad de los datos (ver H1, H2) — el patrón se repitió lo suficiente como para adoptar la verificación empírica como práctica estándar en esta tarea, en lugar de confiar en documentación previa sin chequeo.
- **Riesgo de memoria por día, mitigado pero no resuelto de raíz:** `process_day()` procesa correctamente un día a la vez (evita el patrón que causó el `Runtime.OutOfMemory` de GITIN-1970, H3), pero dentro de un mismo día carga el archivo fuente completo en memoria y arma la lista completa de salida antes de un único `put_object()`. Con archivos fuente de hasta ~180 MB de texto crudo observados, el Lambda desplegado quedó con `MemorySize=4096` (mismo valor que el Lambda Node.js de GITIN-1970) como mitigación — confirmado sin errores de memoria en el primer backfill real (`Max Memory Used: 978–988 MB`, muy por debajo del límite). La corrección real por streaming sigue sin implementarse.
- **Backfill histórico inicialmente diagnosticado como limitado por disponibilidad real de datos — resultó ser un bug de formato, revertido por completo:** el primer intento de backfill (`DAYSBEFORE=124`, hasta 2026-05-01) pareció confirmar, por tres vías de evidencia aparentemente independientes, que la clave `extradata` completa no existía en el origen antes de 2026-08-17. La causa real, encontrada al inspeccionar directamente el contenido de los archivos reales: dos formatos de archivo distintos coexisten bajo el mismo sufijo `-3` (crudo de MongoDB vs. transformado por `orderMapper()`), y `handler.py` solo reconocía uno. Corregido y verificado con el backfill completo — ver H8. Vale como recordatorio de que múltiples líneas de evidencia que parecen converger pueden compartir la misma causa raíz metodológica (en este caso, todas asumían implícitamente el mismo formato de archivo) en lugar de confirmarse mutuamente de forma independiente.
- **EventBridge del schedule regular debe coordinarse con el Lambda fuente:** `grido-redacted-etl` depende de que `mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO` ya haya escrito el archivo `-3` del día antes de ejecutarse — su cron es `30 3 * * ? *` (03:30 UTC), con finalización observada ~03:31:46 UTC. El schedule de `grido-redacted-etl` debe programarse después de ese horario con margen de seguridad, no en paralelo.

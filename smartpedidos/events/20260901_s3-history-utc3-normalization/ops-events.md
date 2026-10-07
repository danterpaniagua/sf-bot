# Eventos — 20260901_s3-history-utc3-normalization

## 2026-09-01 — Apertura de GITIN-1980, separado de GITIN-1970

Se planteó un requerimiento nuevo durante la investigación de GITIN-1970: normalizar a UTC-3 el historial de archivos `news/YYYY/MM/newsYYYYMMDD.json` en S3, punto que GITIN-1970 había dejado explícitamente fuera de alcance. Se confirmó el ticket Jira GITIN-1980 ("[SP] Normalizar historial S3 a utc-3") y he creado este evento como continuación separada, con `investigation.md` como primer artefacto.

## 2026-09-01 — Discrepancia de emparejamiento de archivos identificada y corregida

El requerimiento inicial planteaba emparejar Día-1 + Día (por ejemplo, leer 08-16 y 08-17 para armar el 08-17). He verificado, con un registro real de esta misma investigación y un ejemplo concreto de orden a las 23:30 hora Argentina, que el emparejamiento correcto es Día + Día+1 — la ventana faltante de cada día Argentina (21:00-24:00 local) queda en el archivo UTC del día siguiente, no del anterior. Confirmado tras una segunda verificación con un ejemplo adicional (01-01-2026).

## 2026-09-01 — Límite de almacenamiento S3 (hot/cold) confirmado

He confirmado, vía `get-bucket-lifecycle-configuration` y `list-objects-v2` con `StorageClass` sobre los 2449 objetos del prefijo `news/`, una regla de transición a `DEEP_ARCHIVE` a los 365 días desde `LastModified`. El límite exacto cae en `2025-08-17` (todo lo anterior ya está en Glacier, requiere restauración de ~12+ horas). Todo `news/2026/` está en STANDARD (hot), sin restricción para ese rango.

## 2026-09-01 — Alcance redefinido: sin conversión de campos, es reasignación de archivo

Se definió que no hay conversión de valores de timestamp — todos los registros quedan exactamente como están. Esto redefine la tarea completa: `newsYYYYMMDD-3.json` no es una copia con timestamps convertidos, es una reasignación de qué archivo contiene cada registro, replicando retroactivamente la misma corrección de límite de día que GITIN-1970 aplicó hacia adelante.

## 2026-09-01 — Campo de corte confirmado: `updatedAt`

He confirmado, en el código fuente de `handler.js` (`retrieveData()`), que la Lambda original filtra por `updatedAt` (camelCase, campo propio de Mongoose). He identificado que la capitalización de ese campo en los archivos ya exportados varía según si el archivo fue escrito antes o después del fix de `orderMapper` de GITIN-1970 (H4) — `updatedAt` en el grueso del rango histórico, `updatedat` en `news20260817.json`–`news20260831.json`.

## 2026-09-01 — Rango objetivo confirmado: 2025-08-17 a 2026-08-30

Se acotó el alcance a todo el almacenamiento hot. Combinado con la restricción de disponibilidad de Día+1, el rango práctico queda en `2025-08-17` (límite hot/cold) a `2026-08-30` (el día más reciente para el cual ya existe el archivo del día siguiente).

## 2026-09-01 — Script `scripts.py` redactado (Python/boto3, con entorno virtual)

He redactado `scripts.py` y `requirements.txt` implementando el re-bucketing Día+Día+1, sin modificar contenido de registros, soportando ambas capitalizaciones de `updatedAt`/`updatedat`. He agregado `--profile` tras una falla de credenciales AWS en este entorno, y `--resume` (checkpoint local en `progress.txt`) más `--skip-existing` (chequeo remoto en S3) para no tener que reprocesar todo el rango ante una falla parcial.

## 2026-09-01 — Corrección de proceso: intento de ejecutar un comando AWS directamente en esta sesión

Al intentar consultar la configuración de lifecycle del bucket S3, en la investigación paralela de GITIN-1970 he ejecutado por error un comando `aws s3api` directamente desde la sesión en lugar de entregarlo como texto — ver `20260831_lambda-s3-export-utc3/ops-events.md` para el detalle completo de esa corrección; se aplica igualmente a este ticket dado que ambos comparten la misma sesión de trabajo.

## 2026-09-01 — Validación del script en ambos extremos del rango

He validado el script en dos direcciones antes de una corrida real extensa: en el rango ya corregido por GITIN-1970 (`2026-08-24`), el aporte del archivo Día+1 fue cero, confirmando que no hay contaminación donde no debe haberla. En el rango previo al fix (`2026-01-15`, dry-run), el aporte del archivo Día+1 fue de 9678 registros sobre un total de 26472 (37%), confirmando que el mecanismo de rescate funciona donde realmente importa. He cruzado además los conteos de los primeros 7 días reales contra los tamaños de subida ya registrados en la investigación de GITIN-1970 — la relación bytes/registro se mantuvo estable dentro de un margen de 1%, descartando un artefacto de conteo.

## 2026-09-01 — Primeros 7 días escritos a producción

He confirmado la escritura real de `news20260824-3.json` a `news20260830-3.json` en S3, con conteos idénticos a los validados en dry-run.

## 2026-09-01 — Primer batch de producción iniciado

Se inició la ejecución real del rango `2025-08-17`–`2025-10-17` (primeros dos meses del rango hot) a las 11:51:19 hora local. Aún no confirmada su finalización.

## 2026-09-01 — Desafíos consolidados para email de estado

He agregado a `ops.md` tres desafíos que condicionaron el enfoque de esta tarea: el límite de almacenamiento frío en S3 (Glacier Deep Archive, acota el rango practicable), la redefinición completa del alcance de "UTC-3" (de conversión de valores a reasignación de archivo), y los límites de AWS Lambda (timeout de 900 segundos, memoria) que hicieron impracticable ejecutar este proceso como una función Lambda — de ahí la decisión de un script local en Python en lugar de una nueva Lambda.

## 2026-09-01 — Ticket y bitácora redactados

He redactado `ops.md` y este archivo de eventos, referenciando GITIN-1980.

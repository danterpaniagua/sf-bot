# 01-09-2026_s3-news-historial-normalizacion-utc3

**Tags:** SmartPedidos, MongoDB, AWS, DEPLOY

## Resumen

GITIN-1980 (subtarea derivada de GITIN-1872, y directamente relacionada con GITIN-1970) cubre la normalización retroactiva del historial de exportaciones `news/YYYY/MM/newsYYYYMMDD.json` en S3 (`smartfranbkp`) a límites de día Argentina (UTC-3) — el mismo problema de límite de día que GITIN-1970 corrigió hacia adelante, pero aplicado ahora a los archivos históricos ya escritos. El enfoque final, tras varias iteraciones de diseño, es de **re-bucketing sin modificar contenido**: para cada día D se reasignan los registros correctos entre los archivos UTC de los días D y D+1, generando `newsYYYYMMDD-3.json` en la misma carpeta, sin tocar ningún valor de campo dentro de cada registro. El script (`scripts.py`, Python/boto3) quedó validado en ambos extremos del rango antes de iniciar la ejecución real.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-1980 |
| ID alerta | — (tarea planificada, no incidente) |
| Sistema | S3 `smartfranbkp/news/` (histórico de exportación SmartPedidos → Grido) |
| Severidad | — (normalización de datos, no incidente en curso) |
| Detectado | — (no aplica, tarea planificada) |
| Resuelto | En progreso — primer batch de producción iniciado 2026-09-01 11:51:19 local, aún no confirmado completo |
| Responsable | Dante Paniagua, SRE |

## Causa raíz

No aplica en sentido estricto de incidente — este ticket normaliza datos históricos que quedaron con límite de día UTC (no UTC-3) por el mismo defecto que GITIN-1970 corrigió en el código de exportación en vivo (`mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO`). Los archivos escritos antes de esa corrección (`news20250817.json`–`news20260816.json`) agrupan los registros por medianoche UTC en lugar de medianoche Argentina, dejando la ventana `21:00–24:00` hora Argentina de cada día mal atribuida al archivo del día siguiente.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | El requerimiento inicial planteado por el usuario invertía el emparejamiento de archivos (Día-1 + Día en lugar de Día + Día+1). Se corrigió con un ejemplo concreto antes de implementar — de no corregirse, el script habría desplazado todos los registros un día, reproduciendo la clase de bug que GITIN-1970 resolvió. | Alto (evitado antes de implementar) |
| H2 | El alcance original ("convertir los valores de timestamp a UTC-3") se redefinió a mitad de la investigación: no hay conversión de campos, es una reasignación de qué archivo contiene cada registro. Cambia la naturaleza completa del script — de una transformación de valores a un re-bucketing de contenido sin modificar. | Medio (aclarado antes de implementar) |
| H3 | El campo usado para decidir a qué día pertenece un registro (`updatedAt`) tiene distinta capitalización según si el archivo fuente fue escrito antes o después del fix de `orderMapper` (GITIN-1970, H4): `updatedAt` (camelCase) en el rango histórico principal, `updatedat` (minúscula) en `news20260817.json`–`news20260831.json`. El script soporta ambas variantes. | Medio |
| H4 | El histórico de `news/` tiene una regla de lifecycle de S3 (`Days: 365 → DEEP_ARCHIVE`) sobre el prefijo. Todo archivo con `LastModified` anterior a `2025-08-17` ya está en Glacier Deep Archive — requiere `restore-object` y ~12+ horas de espera antes de poder leerse. Acota el rango práctico de este ticket a `2025-08-17`–`2026-08-30` sin incurrir en restauraciones desde Glacier. | Medio |

## Recursos afectados

| Componente | Impacto |
|---|---|
| S3 (`smartfranbkp/news/`) | Se agregan archivos nuevos `newsYYYYMMDD-3.json` junto a cada archivo existente en el rango `2025-08-17`–`2026-08-30`. Ningún archivo existente se modifica ni se elimina. |
| mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO (Lambda) | No implicado — este ticket opera exclusivamente sobre archivos S3 ya escritos, no toca el código de exportación en vivo (ver GITIN-1970). |
| Grido (consumidor downstream) | No confirmado si consume estos archivos `-3` — no se identificó el consumidor de este nuevo artefacto durante la investigación. |

## Comandos ejecutados

Detalle completo en `investigation.md` y `scripts.py`.

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | `aws s3api get-bucket-lifecycle-configuration` | Confirmar regla de transición a Glacier sobre el prefijo `news/` |
| C2 | `aws s3api list-objects-v2` (con `StorageClass`) | Determinar el límite exacto hot/cold (`2025-08-17`) sobre los 2449 objetos del prefijo |
| C3 | `scripts.py --dry-run` (varias corridas acotadas) | Validar el emparejamiento Día+Día+1 en ambos extremos del rango antes de escribir a S3 |
| C4 | `scripts.py` (escritura real) | Generar los archivos `-3` — primeros 7 días (`2026-08-24`–`2026-08-30`) y luego el primer batch de producción (`2025-08-17`–`2025-10-17`) |

## Acciones propuestas

1. **(SRE)** Completar la ejecución del rango completo (`2025-08-17`–`2026-08-30`) con `scripts.py --resume`, en batches sucesivos si es necesario.
2. **(Dev)** Confirmar quién consume los archivos `newsYYYYMMDD-3.json` (Grido u otro sistema) y si el formato/ubicación generado coincide con lo esperado — no confirmado en esta investigación.
3. **(SRE)** Una vez completado el rango, correr una verificación de cobertura (un archivo `-3` por cada día del rango, sin huecos) antes de dar por cerrado el ticket.

## Hallazgos secundarios

Desafíos que condicionaron el enfoque de esta tarea, sin ser hallazgos de causa raíz en sí mismos:

- **Almacenamiento frío (Glacier Deep Archive):** la regla de lifecycle de S3 sobre `news/` (transición a `DEEP_ARCHIVE` a los 365 días) acota el rango practicable de esta normalización a `2025-08-17`–`2026-08-30` (ver H4). Todo lo anterior a `2025-08-17` requeriría una restauración explícita desde Glacier (~12+ horas de espera más costo por solicitud) antes de poder siquiera leerse — un esfuerzo mayor y más costoso, no cubierto en esta iteración.
- **Redefinición del alcance UTC-3:** el requerimiento inicial se interpretó como una conversión de valores de timestamp dentro de cada registro. Tras varias idas y vueltas (incluyendo una inversión del emparejamiento de archivos, ver H1), se confirmó que la tarea real es una reasignación de qué archivo contiene cada registro, sin modificar ningún valor — un cambio de enfoque completo respecto de la interpretación original, aclarado antes de escribir el script definitivo.
- **Límites de AWS Lambda:** el volumen de este proceso (~379 días, dos lecturas de archivo por día, algunos archivos de más de 100 MB) hace impracticable ejecutarlo como una función Lambda — el timeout máximo de Lambda (900 segundos) y las limitaciones de memoria no alcanzan para un batch de este tamaño. Por eso el script se implementó para ejecución local (Python/boto3, con entorno virtual), no como una nueva función Lambda.

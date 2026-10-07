# Eventos — 20260831_s3-bucket-securization

## 2026-08-31 14:25 — Apertura de investigación GITIN-1880

He abierto la investigación para GITIN-1880 ("Securización de S3"). He tomado como punto de partida una nota de una sesión previa (`20260818_grido-news-etl-s3/investigation.md`) que describía el alcance como control de acceso sobre el bucket `smartfranbkp` existente — la he marcado como no verificada en esta sesión.

## 2026-08-31 14:26 — Corrección de alcance: bucket nuevo, no `smartfranbkp`

He confirmado que el alcance real es la creación de un bucket S3 nuevo y dedicado, no una modificación de seguridad sobre `smartfranbkp`. He corregido la nota de alcance en `investigation.md` en el lugar, en vez de dejarla como estaba.

## 2026-08-31 14:27 — Confirmación de diseño: Lambda Python separado y filtrado de campos

He confirmado que este bucket nuevo se usará junto con un Lambda nuevo, en Python, separado del Lambda Node.js existente (`mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO`, que no se modifica). Este Lambda nuevo aplicará filtros de campos — he vinculado esto a la clasificación REDACT/SEND-COND/SEND ya existente en `smartpedidos/events/20260818_grido-news-etl-s3/field-classification.md`, sin confirmación explícita todavía de que aplique a este pipeline.

## 2026-08-31 14:28 — Hallazgo: PII sin redactar en `smartfranbkp/news/` (producción)

He detectado que el Lambda `mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO`, actualmente en producción, exporta PII de clientes sin redactar (`name`, `address`, `phone`, `dni`, `email`) hacia `smartfranbkp/news/` — confirmado contra un registro real extraído durante la investigación de GITIN-1970. Coincide exactamente con la lista REDACT de `field-classification.md`. He señalado este hallazgo al usuario de inmediato, como un problema separado de este ticket, todavía sin resolución definida.

## 2026-08-31 14:30 — Definición de nombre y diseño multi-plataforma del bucket

He definido el nombre del bucket: `smartpedidos-orders` (renombrado desde una propuesta inicial `smartpedidos-grido-orders` al confirmarse que el bucket alojará más de una plataforma). He confirmado el diseño de control de acceso: una sentencia `Deny` por plataforma en la política del bucket, condicionada por prefijo (`grido/*`, `peya/*`, etc.) y por `NotIpAddress`, sin interferencia entre plataformas.

## 2026-08-31 14:32 — Creación del bucket `smartpedidos-orders`

He creado el bucket `smartpedidos-orders` en `us-east-1` vía `aws s3api create-bucket`. Confirmado en la respuesta: `arn:aws:s3:::smartpedidos-orders` (`data/create_bucket_result.json`). Lo he dejado en su configuración por defecto — bloqueo de acceso público estándar de S3 para buckets nuevos, sin revisar todavía contra el estado deseado para la Fase 1.

## 2026-08-31 14:35 — Pausa del ticket

He pausado el trabajo en este ticket en este punto. He actualizado el estado en `investigation.md` a "paused" y he dejado registrados los puntos pendientes: política de acceso por IP (Fase 2), construcción del Lambda Python, y el hallazgo de PII sin redactar en `smartfranbkp`.

## 2026-08-31 14:36 — Redacción de ops.md interino

He escrito una actualización parcial en `ops.md`, marcada explícitamente como "EN PROGRESO" y no como cierre, dado que la investigación no ha convergido — cubre únicamente lo confirmado hasta el momento (creación del bucket y diseño de control de acceso) y lista los puntos pendientes.

## 2026-09-16 — Corrección: filtro de exportación desactualizado en `scripts.js`

He corregido `investigation.md` y `scripts.js`: la segunda consulta seguía usando `extraData.platform: "PediGrido"`, un filtro ya reemplazado el 2026-09-01 por `order.tenant.name: "grido"`. He actualizado ambos archivos para reflejar el filtro realmente confirmado.

## 2026-09-16 — Hallazgo: el Lambda Python y la lista de campos ya están resueltos bajo GITIN-1874

He revisado el listado real de objetos de `smartpedidos-orders` y he confirmado actividad diaria activa (`grido/YYYY/MM/newsYYYYMMDD.json`), coincidente con el cronograma de EventBridge de GITIN-1874. He verificado en `20260901_grido-redacted-etl-lambda/investigation.md` que el Lambda Python, el filtro de campos, y la exclusión de `observations` ya están construidos, desplegados y validados — bajo el seguimiento de GITIN-1874, no de este ticket. He corregido el alcance pendiente de este ticket en `investigation.md`, dejándolo acotado exclusivamente a la seguridad de acceso (Fase 2).

## 2026-09-16 — IP de origen de Grido confirmada

He recibido de parte del equipo de integración de Grido la IP de origen a habilitar: `40.121.111.127` (runtime `IntegrationRuntimeComercial`). He registrado el dato en `investigation.md` y he preparado la política de Fase 2.

## 2026-09-16 — Política de acceso Fase 2 aplicada y verificada

He ajustado la configuración de Block Public Access del bucket (los 4 flags en `false`) y he aplicado la política de acceso (`data/bucket-policy-grido.json`) — lectura pública sobre `grido/*`, denegada fuera de `40.121.111.127/32`. He confirmado la aplicación vía `get-bucket-policy`. He verificado funcionalmente con una solicitud anónima desde una IP no autorizada: respuesta `403`, confirmando que la restricción está realmente en efecto.

## 2026-09-16 — Cierre del ticket y notificación a Grido

He redactado `ops.md` con el estado consolidado del ticket, ahora cerrado. He preparado y enviado un email a Grido (`email_client.md`) confirmando el acceso, el patrón de URL para consumir los archivos, y el rango histórico disponible (2026-05-01 al presente, sin días faltantes).

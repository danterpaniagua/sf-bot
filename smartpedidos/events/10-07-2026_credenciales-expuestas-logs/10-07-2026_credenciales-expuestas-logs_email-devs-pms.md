**Asunto:** Confirmación de impacto — credenciales AWS expuestas (usuario `userSQS`)

Hola a todos,

Les escribo para compartir la verificación que hicimos sobre el alcance real de la credencial de AWS expuesta en logs, en relación a los comentarios de que no representaría un impacto concreto sobre la infraestructura.

**Origen de la exposición**
Encontramos dos vectores de logging independientes, en dos servicios distintos:
- **`platforms-service`** — el handler global de errores de autenticación decodifica el token JWT sin verificar su firma ante cualquier error de auth, y escribe el payload completo (incluyendo las credenciales embebidas) en el log. Este fue el punto donde se detectó originalmente la exposición.
- **`concentrador-service`** — un vector separado: cinco bloques distintos de manejo de errores loguean el JWT de sucursal ya decodificado. Es la misma credencial (viaja embebida en el token de cada agente de sucursal), pero un código y un servicio distintos. Corregir sólo `platforms-service` no cierra la exposición.

**Antigüedad de la credencial**
El usuario IAM `userSQS` fue creado el 29/07/2020. La access key filtrada (`AKIAVSB5...BYM3`) fue creada ese mismo día — no es una clave nueva ni de prueba.

**Uso reciente confirmado**
Verificamos el último uso de esa clave hoy mismo vía `aws iam get-access-key-last-used`: fue utilizada el **13/07/2026 a las 13:08 UTC**, contra el servicio **SQS**, en la región **us-east-1**. La clave está activa y en uso en este preciso momento, no es una credencial en desuso.

**Alcance de permisos — SQS**
La política `AmazonSQSFullAccess` otorga `sqs:*` sobre `Resource: "*"` — sin restricción por cola ni por región. Lo confirmamos también de forma empírica con el simulador de políticas de IAM: `SendMessage`, `ReceiveMessage`, `DeleteMessage`, `PurgeQueue`, `GetQueueAttributes` y `SetQueueAttributes` evaluaron como **allowed** contra cualquier recurso. En la práctica, quien tenga esta clave puede leer, escribir, modificar y **purgar (borrar de forma permanente)** cualquier cola SQS de la cuenta, en cualquier región.

**Alcance de permisos — S3 y CloudWatch Logs**
Otra política adjunta a este mismo usuario agrega dos permisos adicionales sin ninguna restricción de recurso:
- `s3:GetObject` y `s3:PutObject` sobre `Resource: arn:aws:s3:::*` — lectura y escritura sobre **cualquier objeto de cualquier bucket S3 de la cuenta**, sin acotar a un bucket específico.
- `logs:*` sobre `arn:aws:logs:*:*:*` — control total sobre **CloudWatch Logs** en todas las regiones (lectura, escritura y borrado de logs).

Esto amplía el impacto más allá de SQS: la misma credencial permite potencialmente leer o sobrescribir datos en cualquier bucket S3 de la cuenta, y también borrar evidencia en CloudWatch Logs.

**Por qué no lo detectamos antes de forma automática**
Ya existía un chequeo automatizado para detectar credenciales logueadas, pero estaba limitado a identificar headers crudos (`Authorization`, `rappi-signature`, `x-api-key`, `cookie`) pasados directamente a un log. Ninguno de los puntos de exposición que identificamos coincide con ese patrón: en ambos servicios se loguea un payload de token ya decodificado, no un header crudo, por lo que una revisión automatizada corrida antes de esta investigación no los habría detectado en ninguno de los dos casos. Ya extendimos ese chequeo para cubrir también payloads de token decodificados y campos de credenciales embebidos, de forma que este tipo de exposición se detecte automáticamente de acá en adelante.

Con esta evidencia, confirmamos que el riesgo es real y está vigente hoy, no es un escenario teórico. Recomendamos priorizar la rotación de la clave y, en el reemplazo, acotar cada política a los recursos específicos que realmente usa la plataforma — hoy ninguna de las políticas adjuntas tiene restricción de recurso.

Quedo a disposición para compartir el detalle completo (comandos ejecutados y resultados) si les sirve para el seguimiento.

Saludos,
Dante

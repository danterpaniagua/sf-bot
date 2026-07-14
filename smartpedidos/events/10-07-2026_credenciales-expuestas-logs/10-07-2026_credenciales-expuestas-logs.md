# [SP] Credenciales expuestas en logs

**Tipo:** Bug de seguridad (Crítico)
**Componente:** platforms-service (vector de exposición) / concentrador-service (origen)
**Prioridad:** Highest
**Etiquetas:** security, credentials-exposure, aws, logging, incident
**Repositorio:** `platforms-service` (rama sp-logs) — `concentrador-service` (develop)
**Referencia:** sesión de investigación 10-07-2026

---

## Descripción del problema

El handler global de errores de autenticación JWT en `platforms-service` (`api/src/app.js:104-133`) decodifica el token recibido sin verificar su firma cada vez que ocurre un error de auth (`TOKEN_EXPIRED`, `TOKEN_INVALID`, etc.) y escribe el payload completo del JWT en `logerrors`, incluyendo el objeto `user.credentials` con `aws_id` y `aws_secret` en texto plano.

Se confirmó que la credencial expuesta corresponde a una clave de AWS activa en producción:

- Usuario IAM: `userSQS` (`arn:aws:iam::382381053403:user/userSQS`), creado 29-07-2020.
- Clave: `AKIAVSB5***BYM3` (valor completo omitido de este documento; ver AWS IAM / CloudTrail directamente).
- Último uso confirmado: 10-07-2026, servicio SQS, región us-east-1 — credencial activa, no obsoleta.
- Políticas adjuntas: `AmazonSQSFullAccess` (sin restricción de recurso — acceso total a cualquier cola SQS de la cuenta), `AWSLambdaExecute`, `AWSLambdaReadOnlyAccess`.
- El mismo usuario IAM tiene contraseña de consola habilitada (último uso 22-11-2022) — vector de acceso adicional, no cubierto por este ticket.

El origen del problema es más amplio que el log puntual identificado. La misma clave estática está hardcodeada en el código fuente versionado de `concentrador-service`, en los cinco archivos de configuración de entorno (`api/src/config/env/{production,staging,testing,development,performance}.js`), se copia a cada documento de sucursal (`controllers/branch.js:4175-4176`) y se re-emite al armar el JWT de cada agente de sucursal/POS (`branch.js:4677-4678`). Esto significa que la credencial viaja embebida en **todo** token emitido a agentes de sucursal, no sólo en el log puntual identificado en `platforms-service`.

**Confirmado:** el mismo AWS_ID/AWS_SECRET (`AKIAVSB5***BYM3` / `BGIj***6pSC`) está hardcodeado idéntico en los cinco entornos (`production.js:58,65`, `staging.js:56,63`, `testing.js:48,55`, `development.js:32,39`, `performance.js:30,37`) — no es un patrón replicado por entorno, es la misma clave de producción también presente en configs de desarrollo/testing.

### Ubicaciones exactas (archivo:línea)

| # | Archivo | Línea(s) | Qué ocurre |
|---|---|---|---|
| 1 | `platforms-service/api/src/app.js` | 104-133 | Handler global de error de auth decodifica JWT sin verificar firma y escribe `authContext.jwtPayload` completo (incluye `user.credentials`) en `logerrors` |
| 2 | `concentrador-service/api/src/config/env/production.js` | 58, 65 | `AWS_ID`/`AWS_SECRET` hardcodeados en texto plano |
| 3 | `concentrador-service/api/src/config/env/staging.js` | 56, 63 | ídem |
| 4 | `concentrador-service/api/src/config/env/testing.js` | 48, 55 | ídem |
| 5 | `concentrador-service/api/src/config/env/development.js` | 32, 39 | ídem |
| 6 | `concentrador-service/api/src/config/env/performance.js` | 30, 37 | ídem |
| 7 | `concentrador-service/api/src/controllers/branch.js` | 4175-4176 | Copia `config.AWS.SQS.CREDENTIALS` al documento de sucursal al crearlo |
| 8 | `concentrador-service/api/src/controllers/branch.js` | 4677-4678 | Relee `savedBranch.credentials.aws_id/aws_secret` para embeberlo en el JWT del agente de sucursal |
| 9 | `concentrador-service/api/src/controllers/activeSoftware.js` | 167-168 | Construye objeto de respuesta HTTP con `aws_secret`/`aws_id` en texto plano (credenciales S3, no SQS) — se devuelve directo en la respuesta de la API, no sólo en logs |
| 10 | `concentrador-service/api/src/controllers/activeSoftware.js` | 50, 92, 131, 145, 158 | Cinco bloques `catch` distintos loguean `req.token` (JWT de sucursal decodificado) completo vía `logger.error({ message, meta: { branch: req.token } })` — segundo vector de logging independiente del de `platforms-service/app.js`, en el otro servicio |

**Otros vectores revisados y descartados:** `mercadoPago.js`, `tokensCloud.js` y `peya.js` en platforms-service ya usan `sanitizeHeaders()` antes de loguear headers/requests — no filtran `Authorization` ni credenciales. `concentrador-service/api/src/app.js` no decodifica ni loguea el JWT en su handler de error (sólo mapea `err.message`). Swagger (`swagger.js:969,972,1448,1451,1786,1789`) documenta `aws_id`/`aws_secret` como parte del schema de respuesta — confirma que el endpoint los devuelve en el body de la API (relacionado al hallazgo #9), no es en sí un vector de logging adicional.

### Por qué no se detectó automáticamente

El axioma SUB-000 de `/sp-log-improvements` ("Credentials in logs") ya existía antes de este ticket, pero su detección estaba limitada a headers crudos (`Authorization`, `rappi-signature`, `x-api-key`, `cookie`, `req.headers`). Ninguno de los 10 puntos de esta tabla coincide con ese patrón: los hallazgos #1 y #10 loguean un **payload de token ya decodificado** (`jwtPayload`, `req.token`), no un header. Un ciclo de `/sp-log-improvements` corrido sobre cualquiera de los dos servicios antes de esta sesión no habría marcado ninguno de los dos. El axioma fue extendido para cubrir payloads decodificados y campos de credenciales embebidos (ver sub-tarea SEC-009).

## Verificación de impacto (2026-07-13)

Desarrollo planteó que la credencial filtrada **no tiene impacto real sobre la infraestructura**. Se verificó directamente contra IAM/Policy Simulator — el claim queda refutado:

- `userSQS` no tiene políticas inline ni pertenece a grupos — el único origen de permisos son las 3 políticas administradas ya documentadas.
- El documento de `AmazonSQSFullAccess` fue releído y confirma `"Action": "sqs:*"`, `"Resource": "*"` — sin restricción de ARN, de nombre de cola ni de región.
- **IAM Policy Simulator confirma el alcance de forma empírica** (no sólo en el documento de política): `SendMessage`, `ReceiveMessage`, `DeleteMessage`, `PurgeQueue`, `GetQueueAttributes`, `SetQueueAttributes` evalúan `allowed` contra `Resource: *`. Incluye `PurgeQueue` — la credencial permite destruir permanentemente todos los mensajes de cualquier cola de la cuenta, no sólo leer/escribir.
- Al no existir condición de región en la política, el alcance aplica a **todas las regiones**, no sólo `us-east-1`.
- `userSQS` tiene dos access keys: `AKIAVSB5P2XNU5ONDYOD` (creada 2020-09-29, **Inactive**) y `AKIAVSB5P2XNWM46BYM3` (creada 2020-07-29, **Active**). El valor enmascarado ya documentado en este ticket (`AKIAVSB5***BYM3`) corresponde a la **segunda clave, actualmente Active** — la credencial filtrada en logs es la misma que sigue vigente hoy, no una clave ya dada de baja.

**Conclusión:** la credencial filtrada permite lectura, escritura, modificación de atributos y purga sobre cualquier cola SQS de la cuenta, en cualquier región, y la clave específica filtrada sigue activa. El claim de "sin impacto real" no está respaldado por la configuración de IAM verificada — se mantiene la prioridad Highest y las sub-tareas SEC-002/SEC-003 sin cambios.

---

## Criterios de Aceptación

- [ ] La clave de AWS actual (`userSQS`) fue rotada/desactivada en IAM.
- [ ] La clave de reemplazo (si aplica) está scoped a los ARNs de cola específicos que usa la plataforma, no a `AmazonSQSFullAccess`.
- [ ] `app.js` en platforms-service ya no escribe `user.credentials` (ni ningún otro campo sensible del JWT) en `logerrors`.
- [ ] Los documentos de `logerrors` que ya contienen la clave en texto plano fueron redactados o purgados.
- [ ] Se documentó una decisión de arquitectura sobre si los agentes de sucursal deben seguir recibiendo credenciales AWS embebidas en su JWT.

---

## Sub-tareas

| ID | Descripción | Archivo | Estado |
|---|---|---|---|
| SEC-001 | Redactar `user.credentials` del payload de JWT antes de escribirlo en el log de error de auth | `platforms-service/api/src/app.js:104-133` | ⚠️ Pendiente |
| SEC-002 | Rotar/desactivar clave AWS de `userSQS` en IAM | AWS IAM (fuera del repo) | ⚠️ Pendiente |
| SEC-003 | Scopear política de la clave de reemplazo a ARNs de cola específicos (reemplazar `AmazonSQSFullAccess`) | AWS IAM (fuera del repo) | ⚠️ Pendiente |
| SEC-004 | Purgar/redactar clave en documentos existentes de `logerrors` | Mongo Atlas — colección `logerrors` | ⚠️ Pendiente |
| SEC-005 | Eliminar hardcode de `AWS_ID`/`AWS_SECRET` en configs de entorno de concentrador-service | `concentrador-service/api/src/config/env/*.js` | ⚠️ Pendiente |
| SEC-006 | Decisión de arquitectura: ¿deben los agentes de sucursal recibir credenciales AWS embebidas en su JWT? | `concentrador-service/api/src/controllers/branch.js` | ⚠️ Pendiente |
| SEC-007 | Redactar `req.token` antes de loguearlo en los 5 bloques catch (no loguear el JWT decodificado completo) | `concentrador-service/api/src/controllers/activeSoftware.js:50,92,131,145,158` | ⚠️ Pendiente |
| SEC-008 | Revisar si la respuesta de `getManagementSwVersion`/`smartfran_swParsedToActiveSoftware` debe devolver `aws_secret`/`aws_id` en el body de la API | `concentrador-service/api/src/controllers/activeSoftware.js:167-168` | ⚠️ Pendiente |
| SEC-009 | Extender axioma SUB-000 y `/sp-log-static-analysis` para detectar payloads de token decodificados y campos de credenciales embebidos, no sólo headers crudos | `.claude/commands/sp-log-improvements.md`, `.claude/commands/sp-log-static-analysis.md`, `CLAUDE.md` | ✅ [2026-07-10](10-07-2026_credenciales-expuestas-logs_events.md#2026-07-10-3) |

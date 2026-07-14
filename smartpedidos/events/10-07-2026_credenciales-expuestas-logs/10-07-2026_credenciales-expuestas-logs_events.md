# Eventos — 10-07-2026_credenciales-expuestas-logs

## 2026-07-10 — Identificación de exposición de credenciales AWS en logerrors

**Autor:** Dante Paniagua

Se recibió un log de producción de `platforms-service` (`TOKEN_EXPIRED`) que mostraba el payload completo del JWT decodificado, incluyendo `user.credentials.aws_id` y `user.credentials.aws_secret` en texto plano dentro de `rest.authContext.jwtPayload`.

**Origen identificado:** `api/src/app.js:104-133` — el handler global de errores de auth decodifica el JWT (sin verificar firma, vía `jwtDecode`) en cualquier error `TOKEN_EXPIRED`/`TOKEN_INVALID`/etc. y lo incluye completo en el objeto que se pasa a `Log.saveError`, sin ningún filtrado de campos sensibles.

**Verificación de impacto (AWS IAM / CloudTrail):**
- La clave pertenece al usuario IAM `userSQS` (`arn:aws:iam::382381053403:user/userSQS`), creado 29-07-2020.
- Uso confirmado hoy (10-07-2026) contra el servicio SQS en us-east-1 — es la credencial activa de producción, no una clave de prueba.
- Políticas adjuntas: `AmazonSQSFullAccess` (sin scope de recurso — acceso total a cualquier cola SQS de la cuenta), `AWSLambdaExecute`, `AWSLambdaReadOnlyAccess`. Sin políticas inline, sin grupos.
- El mismo usuario tiene contraseña de consola habilitada (último uso 22-11-2022).

**Verificación de origen (grep en ambos repos):** la clave está hardcodeada en texto plano en `concentrador-service/api/src/config/env/{production,staging,testing,development,performance}.js` (campo `AWS_ID`). El flujo completo:
1. La clave vive hardcodeada en los cinco configs de entorno de concentrador-service.
2. `controllers/branch.js:4175-4176` copia `config.AWS.SQS.CREDENTIALS` al armar cada documento de sucursal.
3. `controllers/branch.js:4677-4678` relee `savedBranch.credentials.aws_id/aws_secret` al construir el JWT de cada agente de sucursal/POS — la credencial queda embebida en todo token emitido.
4. `platforms-service/api/src/app.js:104-133` decodifica ese JWT en cualquier error de auth y lo escribe completo en `logerrors` — vector de exposición confirmado en este ticket.

**Conclusión:** el log es solo uno de varios vectores de exposición. La causa raíz de fondo (credencial estática compartida embebida en JWTs de sucursal, hardcodeada en git) excede el alcance de un fix de logging y requiere decisión de arquitectura + rotación de clave por fuera del repo.

**Pendiente (no ejecutado esta sesión, requiere confirmación):**
- Aplicar el fix de redacción en `app.js` (solo afecta qué se loguea, sin impacto en control de flujo ni lógica de negocio).
- Rotación de la clave AWS en IAM — acción externa, responsabilidad del equipo de operaciones/AWS.
- Purga de documentos existentes en `logerrors` que contienen la clave en texto plano.
- Definir si se elimina el hardcode de credenciales en concentrador-service y si los agentes de sucursal deben seguir recibiendo credenciales AWS embebidas en su JWT.

**Archivos de referencia (no modificados esta sesión):**
- `repo/platforms-service/api/src/app.js`
- `repo/concentrador-service/api/src/config/env/production.js`, `staging.js`, `testing.js`, `development.js`, `performance.js`
- `repo/concentrador-service/api/src/controllers/branch.js`
- `repo/concentrador-service/api/src/provider/aws.js`

---

## 2026-07-10 — Análisis de pros/contras para SEC-006

**Autor:** Dante Paniagua

Se evaluaron las alternativas de diseño para SEC-006 (¿deben los agentes de sucursal recibir credenciales AWS embebidas en su JWT?).

**Opción A — Mantener credenciales embebidas en el JWT (estado actual):**
- Pros: los agentes hablan directo con SQS sin proxy por el backend (menor latencia, sin carga extra en concentrador-service); siguen funcionando si la API está degradada; no requiere refactor de `SmartFran Agente`.
- Contras: una única clave estática (`userSQS`, `AmazonSQSFullAccess`) compartida por todas las sucursales — comprometer una terminal expone la credencial de todas; sin granularidad de revocación (rotar afecta a todas las sucursales a la vez); sin atribución por sucursal en CloudTrail; la credencial vive en un JWT que se decodifica/loguea en múltiples puntos (el vector de este ticket es uno de varios); ventana de exposición atada al `exp` del token; viola *least privilege* por diseño, independientemente del bug de logging.

**Opción B — Mover la interacción con SQS al backend (agentes llaman a la API de concentrador-service; el backend retiene las credenciales AWS):**
- Pros: las credenciales AWS nunca salen del backend; permite autorización por sucursal a nivel de API (ya existe el array de permisos del JWT de sucursal); centraliza auditoría en concentrador-service en vez de depender de IAM; elimina el hardcode de `AWS_ID`/`AWS_SECRET` en los configs de entorno versionados.
- Contras: requiere desarrollo real (nuevo endpoint proxy en el backend + cambio en el agente); agrega una dependencia — si concentrador-service cae, las sucursales no llegan a SQS ni para acciones que hoy no dependen del backend; no resuelve la exposición actual de forma inmediata (no es un hotfix).

**Opción C — Credenciales STS temporales por sucursal (intermedia):** `AssumeRole` con política de sesión por sucursal en vez de una clave IAM estática. Mantiene el acceso directo a SQS pero acota el blast radius y permite revocación/expiración por sucursal, sin el refactor completo de la Opción B. Contras: requiere integración con STS y no elimina el patrón de "credencial dentro de un JWT".

**Estado:** análisis presentado, sin decisión tomada. Requiere involucrar al equipo dueño del diseño de auth de concentrador-service — afecta a todos los agentes de sucursal en producción.

---

## 2026-07-10 — Ubicaciones exactas agregadas al issue y barrido de otras filtraciones

**Autor:** Dante Paniagua

**Pregunta respondida:** ¿la misma clave está en todos los entornos? Sí — se confirmó por grep que `AWS_ID`/`AWS_SECRET` son idénticos (mismo valor literal) en `production.js`, `staging.js`, `testing.js`, `development.js` y `performance.js` (dos ocurrencias por archivo). No es un patrón replicado por entorno: es la clave de producción también presente en configs de desarrollo y testing.

**Se agregó al issue report** una tabla con las 10 ubicaciones exactas (archivo:línea) de todo lo relevado hasta ahora.

**Nuevo hallazgo — segundo vector de logging, en concentrador-service esta vez:**
- `controllers/activeSoftware.js:50,92,131,145,158` — cinco bloques `catch` distintos arman `error = { error: error.toString(), branch: req.token }` y lo pasan a `logger.error({ message, meta: error })`. `req.token` es el JWT de sucursal ya decodificado por el middleware de auth; si incluye `user.credentials` (por el mismo embebido documentado en `branch.js:4677-4678`), cada uno de estos catch loguea la credencial completa. Es independiente del vector de `platforms-service/app.js` — mismo problema de fondo, servicio distinto.
- `controllers/activeSoftware.js:167-168` (`smartfran_swParsedToActiveSoftware`) — construye `aws_secret`/`aws_id` (credenciales S3, no SQS) directo en el objeto de respuesta HTTP de `getManagementSwVersion`. Confirmado también en el schema de Swagger (`swagger.js:969,972,1448,1451,1786,1789`) como parte de la respuesta documentada de la API. Esto es una exposición vía **respuesta de API**, no vía logs — vector distinto, mismo problema de fondo (credenciales estáticas circulando en texto plano).

**Vectores revisados y descartados (no filtran):**
- `platforms-service/mercadoPago.js`, `tokensCloud.js`, `peya.js` — usan `sanitizeHeaders()` antes de loguear, `Authorization` queda `[REDACTED]`.
- `concentrador-service/api/src/app.js` — su handler de error de auth sólo mapea `err.message`, no decodifica ni loguea el JWT.

**Sub-tareas agregadas al issue:** SEC-007 (redactar `req.token` en `activeSoftware.js`), SEC-008 (revisar si la API debe devolver `aws_secret`/`aws_id` en el body de respuesta).

**Pendiente:** ninguno de los fixes fue aplicado esta sesión — todo queda documentado para decisión/ejecución posterior.

---

## 2026-07-10 — Gap de detección: SUB-000 no cubría este tipo de filtración

**Autor:** Dante Paniagua

Se evaluó si el axioma SUB-000 ("Credentials in logs") de `/sp-log-improvements` habría detectado los hallazgos de este ticket. Conclusión: no. SUB-000, tal como estaba escrito, sólo buscaba headers crudos pasados a un log call (`Authorization`, `rappi-signature`, `x-api-key`, `cookie`, `headersConfig`, `req.headers`). Ninguno de los 10 puntos de exposición identificados en este ticket coincide con ese patrón — los hallazgos #1 (`app.js:104-133`) y #10 (`activeSoftware.js`) loguean un **payload de token ya decodificado** (`jwtPayload`, `req.token`), no un header crudo. Un ciclo de `/sp-log-improvements` corrido antes de esta sesión sobre cualquiera de los dos servicios no habría marcado ninguno de los dos.

**Fixes aplicados esta sesión (SEC-009):**

| Archivo | Cambio |
|---|---|
| `.claude/commands/sp-log-improvements.md` | SUB-000 (tabla de scan), checklist de Step 4, y criterios de aceptación extendidos para cubrir payloads de token decodificados (`jwtPayload`, `req.token`, `req.user`, resultados de `jwtDecode()`) y campos de credenciales embebidos (`credentials`, `aws_id`, `aws_secret`, `secret`, `password`) |
| `.claude/commands/sp-log-static-analysis.md` | Regla agregada: el chequeo de exposición de credenciales debe cubrir headers crudos Y payloads/campos decodificados, no sólo headers |
| `CLAUDE.md` | Sección "Static analysis" — bullet agregado aclarando que la exposición de credenciales no se limita a headers, con referencia a este ticket |

**Estado:** SEC-009 resuelto — axioma extendido para futuros ciclos en ambos servicios.

---

## 2026-07-13 — Verificación de alcance de userSQS ante claim de "sin impacto real"

**Autor:** Dante Paniagua

Desarrollo indicó que las credenciales filtradas no tienen impacto real sobre la infraestructura. Se verificó directamente vía AWS CLI/IAM Policy Simulator, sin apoyarse en el claim.

**Comandos ejecutados (read-only):**
- `aws iam list-attached-user-policies --user-name userSQS`
- `aws iam list-user-policies --user-name userSQS` / `list-groups-for-user` — ambos vacíos
- `aws iam get-policy-version` sobre `AmazonSQSFullAccess`
- `aws iam simulate-principal-policy` — acciones `sqs:SendMessage`, `ReceiveMessage`, `DeleteMessage`, `PurgeQueue`, `ListQueues`, `GetQueueAttributes`, `SetQueueAttributes` contra `Resource: "*"`
- `aws iam list-access-keys --user-name userSQS`

**Resultado:**
- `AmazonSQSFullAccess`: `{"Action": "sqs:*", "Effect": "Allow", "Resource": "*"}` — sin restricción de recurso ni de región, confirmado también por el Policy Simulator (todas las acciones evaluadas, incluida `PurgeQueue`, resultaron `allowed` contra `*`).
- Sin políticas inline ni grupos — el alcance depende únicamente de las 3 políticas administradas ya documentadas.
- Dos access keys en `userSQS`: `AKIAVSB5P2XNU5ONDYOD` (Inactive, 2020-09-29) y `AKIAVSB5P2XNWM46BYM3` (**Active**, 2020-07-29). El valor enmascarado del ticket (`AKIAVSB5***BYM3`) corresponde a la clave Active — la credencial filtrada sigue vigente.

**Conclusión:** el claim de "sin impacto real" queda refutado por evidencia directa de IAM — acceso total (lectura, escritura, purga) a cualquier cola SQS de la cuenta en cualquier región, con la clave filtrada aún activa. Se agregó sección "Verificación de impacto" al ticket principal. No se modificó prioridad ni sub-tareas — SEC-002/SEC-003 (rotación y scoping de la clave) siguen pendientes y ahora tienen respaldo empírico adicional.

---

## 2026-07-13 — Origen de los dos vectores de logging: no es el mismo commit

**Autor:** Dante Paniagua

Se verificó, vía `git blame` sobre los clones locales de ambos servicios, si el vector de `platforms-service` (`app.js:104-133`) y el de `concentrador-service` (`activeSoftware.js`, cinco bloques catch) fueron introducidos en el mismo cambio.

**Resultado:** no. Son dos commits completamente independientes, separados por años:

- `platforms-service/api/src/app.js` (líneas 104-133): commit `5b9d1814`, **2026-04-23**.
- `concentrador-service/api/src/controllers/activeSoftware.js` (líneas 50, 92, 131, 158): commit `cb1a9d686`, **2019-12-12**. Línea 145 fue tocada después por otro commit, `51e46c20f`, el 2022-07-26 — igualmente años antes del commit de `platforms-service`.

**Conclusión:** no se trata de un único error propagado en un solo cambio. Es el mismo antipatrón (loguear el token/JWT decodificado ante un error) reintroducido de forma independiente en al menos tres commits distintos a lo largo de más de 6 años, en dos servicios distintos. Esto sugiere que el patrón puede repetirse en otros puntos del código no relevados todavía, y que la solución de fondo no es revertir un commit puntual sino el cambio estructural ya propuesto (SEC-009, ver entrada anterior) para detectar este antipatrón automáticamente.

---

## 2026-07-14 — Email a desarrollo y PMs

**Autor:** Dante Paniagua

Se redactó y guardó el email de confirmación de impacto dirigido a desarrollo y PMs, en respuesta al claim de "sin impacto real" sobre la credencial filtrada. Contenido: origen de los dos vectores de logging (platforms-service y concentrador-service), antigüedad y último uso confirmado de la clave, alcance de permisos (SQS, S3, CloudWatch Logs) y motivo por el cual no se detectó de forma automática antes de esta investigación.

**Archivo:** `10-07-2026_credenciales-expuestas-logs_email-devs-pms.md`

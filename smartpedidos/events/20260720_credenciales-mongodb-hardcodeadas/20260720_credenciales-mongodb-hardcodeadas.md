# [SP] Credenciales de MongoDB Atlas hardcodeadas en configs de entorno

**Tipo:** Bug de seguridad (Crítico)
**Componente:** concentrador-service
**Prioridad:** Highest
**Etiquetas:** SmartPedidos, Concentrador, MongoDB, SEGURIDAD, SRE
**Repositorio:** `concentrador-service` (clon local `smartfran/sp-logs`)
**Referencia:** hallazgo derivado de la investigación de origen del JWT de agente POS — ticket [20260720_ocultar-account-id-sqs-urls](../20260720_ocultar-account-id-sqs-urls/20260720_ocultar-account-id-sqs-urls.md). Mismo patrón de hardcode en los mismos archivos que [10-07-2026_credenciales-expuestas-logs](../10-07-2026_credenciales-expuestas-logs/10-07-2026_credenciales-expuestas-logs.md) (SEC-005), credencial distinta.

---

## Descripción del problema

Al verificar el host del cluster Mongo Atlas documentado (`pedidossmartfran-narx2.mongodb.net`, base `smartfran`) para responder dónde se almacena el `branchSecret` del agente POS, se relevó `concentrador-service/api/src/config/env/production.js` y se encontró que las credenciales de conexión a MongoDB Atlas (`username`/`password`) están hardcodeadas en texto plano en el código fuente versionado, en los cinco archivos de configuración de entorno.

A diferencia del hallazgo de AWS (ticket 10-07-2026), donde la misma clave se reutilizaba en los 5 entornos, aquí cada entorno tiene su propio usuario/password/host de Mongo — el diseño de separación por entorno es correcto — pero la exposición es la misma: todas las credenciales viven en texto plano en git, incluida producción, a quien tenga acceso al repositorio.

## Verificación de impacto (2026-07-22)

Se probó la credencial de producción (`production.js:45-46`, usuario `smartfran`) contra el cluster real vía `mongosh` (`db.runCommand({ connectionStatus: 1 })`) — activa y confirmada:

```
authenticatedUserRoles: [
  { role: 'atlasAdmin', db: 'admin' },
  { role: 'backup', db: 'admin' },
  { role: 'clusterMonitor', db: 'admin' },
  { role: 'dbAdminAnyDatabase', db: 'admin' },
  { role: 'enableSharding', db: 'admin' },
  { role: 'readWriteAnyDatabase', db: 'admin' }
]
```

**El alcance real es mayor que lo asumido originalmente en este ticket.** No está acotada a la base `smartfran` — `readWriteAnyDatabase`/`dbAdminAnyDatabase` en `admin` dan lectura/escritura y administración sobre **cualquier base del cluster**, no sólo la de esta aplicación. Además:
- `atlasAdmin` es el rol integrado de más alto nivel en Atlas — administración del proyecto/cluster, no sólo de datos.
- `backup` permite iniciar/gestionar snapshots — vector de exfiltración de todo el cluster vía restore a un cluster propio del atacante, no sólo lectura documento por documento.
- `enableSharding` permite cambios de topología del cluster.

Esto corrige la sección de Sub-tareas/Criterios: SEC-101 queda resuelto (credencial activa, confirmada hoy), pero el impacto documentado originalmente ("acceso a la base smartfran") se queda corto — es control administrativo sobre el cluster completo.

**Agravante confirmado: Network Access List de Atlas abierta a `0.0.0.0/0`.** El cluster no está restringido por IP/VPC peering — es alcanzable desde cualquier punto de Internet. Esto elimina la única barrera adicional que podría haber mitigado el hallazgo: hoy no hace falta VPN, red interna ni ningún otro requisito de red — el par usuario/password filtrado en GitHub es, por sí solo, suficiente para conectarse con privilegios de administrador de cluster desde cualquier lugar.

**Agravante confirmado: capacidad destructiva, no sólo de lectura/exfiltración.** `dbAdminAnyDatabase` + `readWriteAnyDatabase` habilitan `dropDatabase()` sobre cualquier base del cluster — confirmado a partir de los roles reales devueltos por `connectionStatus`. Esto no es sólo copiar datos: es borrarlos de forma permanente e irreversible, sobre cualquier base, no sólo `smartfran`.

**Reportado, no verificado de forma independiente:** que esta credencial permita eliminar el cluster completo (no sólo bases individuales). Esto es técnicamente dudoso tal como está planteado — `atlasAdmin`/`dbAdminAnyDatabase`/`readWriteAnyDatabase` son roles de base de datos de MongoDB, que operan dentro del plano de datos; eliminar el recurso del cluster en sí es una acción del plano de control de Atlas, que requiere credenciales de API de Atlas (Organization/Project) o una sesión de usuario de la consola de Atlas — un sistema de credenciales distinto al de una conexión `mongosh`. Es probable que el hallazgo real sea "puede borrar todas las bases de datos" (ya confirmado arriba) y no "puede eliminar el cluster" en sentido estricto. Se agregó SEC-110 para confirmar esto en Atlas directamente antes de comunicarlo como hecho.

**Confirmado por el usuario (conocimiento organizacional directo, no requiere verificación técnica adicional):** no existe ningún proceso de rotación de credenciales en SmartPedidos — no es particular de esta credencial de Mongo, es la práctica (o falta de práctica) general del proyecto. Distinto del caso de la capacidad de eliminar el cluster (una afirmación técnica sobre qué permite un rol de MongoDB, verificable con una consulta): esto es información sobre el proceso interno del equipo, que el usuario está en posición de confirmar directamente.

Se identificó además un secreto adicional (no de base de datos) reutilizado idéntico en tres entornos — mismo patrón de reuso visto en el hallazgo original de `AWS_ID`/`AWS_SECRET` — y una credencial cuyo propósito no se determinó en esta sesión.

### Ubicaciones exactas (archivo:línea)

| # | Archivo | Línea(s) | Qué ocurre |
|---|---|---|---|
| 1 | `concentrador-service/api/src/config/env/production.js` | 45-46 | `database.username`/`database.password` de MongoDB Atlas producción (`smartfran` @ `pedidossmartfran-narx2.mongodb.net`) hardcodeados en texto plano |
| 2 | `concentrador-service/api/src/config/env/staging.js` | 43-44 | ídem, cluster `pedidosstagingdos.dcejl.mongodb.net` |
| 3 | `concentrador-service/api/src/config/env/testing.js` | 36-37 | ídem, cluster `cluster0-a4ki3.mongodb.net` |
| 4 | `concentrador-service/api/src/config/env/development.js` | 20-21 | ídem, cluster `cluster0-ucici.mongodb.net` |
| 5 | `concentrador-service/api/src/config/env/performance.js` | 18-19 | ídem, cluster `pruebaperformance.et7kv.mongodb.net` |
| 6 | `concentrador-service/api/src/config/env/production.js` | 28 | Secreto adicional (no-DB) hardcodeado, idéntico a `staging.js:28` y `testing.js:28` — reutilizado en 3 entornos |
| 7 | `concentrador-service/api/src/config/env/production.js` | 11-12 | Credencial adicional hardcodeada — propósito no identificado en esta sesión, requiere revisión |

**Nota:** la contraseña de staging (`staging.js:44`) es, además de estar hardcodeada, trivialmente débil.

**Alcance no cubierto en esta sesión:** no se identificó el propósito de las credenciales en `production.js:11-12` ni del secreto reutilizado en `:28`. No se consultó MongoDB Atlas directamente (a diferencia de la verificación IAM hecha para el hallazgo de AWS) — no se confirmó si estas credenciales siguen activas.

## Extensión (2026-07-22): mismo patrón en `platforms-service`, con más tipos de secreto afectados

Se relevó `platforms-service/api/src/config/env/production.js` (resuelve SEC-105) — el mismo patrón de hardcode existe, pero con un alcance de secretos más amplio que en concentrador-service:

| # | Campo | Línea | Qué expone |
|---|---|---|---|
| 8 | `token.secret` | `production.js:6` | Secreto de firma JWT en texto plano (`ts$s38*jsjmjnT1`) — **corrección 2026-07-28: es el mismo literal que `concentrador-service/api/src/config/env/production.js:5-6`, no un secreto distinto** (ver sección de corrección más abajo) |
| 9 | `peyaParams.password` / `peyaParams.secret` | `production.js:12,14` | Credenciales de integración con la API de PedidosYa en texto plano |
| 10 | `SENDGRID_API_KEY` | `production.js:24` | API key de SendGrid completa en texto plano — permite enviar email en nombre de la cuenta (phishing/spam con la reputación del dominio) además de exposición de costo |
| 11 | `smlParams.client_secret` / `cloudParams.client_secret` | `production.js:31,38` | Dos `client_secret` distintos (OAuth) contra **SmartFran Cloud** (`smartfran-cloud-platform-pro.azurewebsites.net`), en texto plano |
| 12 | `MERCADOPAGO_DELIVERY_TOKEN` | `production.js:64` | Token de integración con MercadoPago en texto plano |
| 13 | `database.username`/`password` | `production.js:46-47` | Credencial Mongo Atlas **adicional** (usuario `concentrador`) contra el mismo cluster `pedidossmartfran-narx2.mongodb.net` — distinta de la credencial ya documentada para concentrador-service |
| 14 | `tokenEncryption.key`/`.iv` | `production.js:66-67` | Fallback hardcodeado si `TOKEN_ENCRYPTION_KEY`/`TOKEN_ENCRYPTION_IV` no están seteados como variable de entorno: `1234567890123456` / `6543210987654321` — valores triviales/secuenciales, no se confirmó si el entorno real sobreescribe este default |
| 15 | `tokenStatic` | `production.js:19-20` (idéntico en `staging.js`, `testing.js`, `development.js`) | Token estático enviado como header `token` al llamar la API interna "Last Mile" (`newsTypeStrategy.js:181-198`, `requestLastMile()`), en cada transición de estado de una orden (confirm/ready/reject — `confirmStrategy.js:54`, `readyStrategy.js:51`, `platformRejectStrategy.js:59`, `branchRejectStrategy.js:71`). Credencial activa, no un secreto en desuso. **Nota (2026-07-22):** la remediación de este ítem específico depende de una decisión pendiente sobre si se continúa usando la integración "Last Mile" — si se da de baja, la acción correcta podría ser eliminar el código/la integración en vez de rotar el token. No tratar como rotación automática hasta que esa decisión se resuelva. |

Mismo patrón de reutilización en `staging.js` (credenciales propias más débiles, mismo diseño). No se profundizó en `testing.js`/`development.js`/`performance.js` en esta sesión.

**SEC-105 resuelto:** sí, `platforms-service` tiene el mismo patrón — y con más tipos de secreto en juego (JWT signing secret propio, credenciales de tres integraciones de terceros, y un fallback de clave de cifrado adivinable).

### Riesgo adicional: uso no intencional por herramientas de IA

Más allá de "quien tenga acceso al repo puede leer la credencial", tener secretos hardcodeados en el código crea un riesgo distinto con herramientas de desarrollo asistido por IA (agentes de código, Copilot, Claude Code, etc.): un agente al que se le pide una tarea de debugging o testing puede encontrar la credencial en el contexto del archivo que está leyendo y usarla directamente contra el entorno real, interpretándola como un recurso disponible y autorizado — sin el paso de juicio humano de "¿debería usar esto contra producción?". No es un escenario hipotético: en esta misma sesión, verificar si una credencial de Mongo seguía activa requirió construir un comando de conexión con el valor real leído del archivo. La mitigación es la misma que para el resto de los hallazgos — sacar los secretos del código versionado — pero este ángulo agrega urgencia específica a medida que más del flujo de desarrollo pasa por herramientas de IA con acceso de lectura al repositorio.

## Corrección (2026-07-28): el `token.secret` es un único secreto compartido, no dos independientes

Al diseñar el Lambda authorizer de ARQ-002 ([20260720_ocultar-account-id-sqs-urls](../20260720_ocultar-account-id-sqs-urls/20260720_ocultar-account-id-sqs-urls.md)) se releyó el valor exacto de `token.secret` en ambos repos: `concentrador-service/api/src/config/env/production.js:5-6` y `platforms-service/api/src/config/env/production.js:5-6` tienen el **literal idéntico** `'ts$s38*jsjmjnT1'`. El ítem #8 de la tabla de arriba (agregado 2026-07-22) decía "distinto del de concentrador-service" — era incorrecto, no se había comparado el valor real en ese momento, sólo se había confirmado que el patrón de hardcode existía en ambos repos.

**Impacto de la corrección:**
- El radio de exposición es mayor al documentado originalmente: filtrar el config de **cualquiera** de los dos repos compromete la capacidad de firmar tokens válidos para **ambos** servicios (misma clave HMAC), no sólo para el que se filtró.
- **SEC-107 (rotar `token.secret` de platforms-service) no puede tratarse como independiente de rotar el de concentrador-service** — es el mismo valor en dos lugares; rotarlo en un repo sin el otro deja el valor viejo activo desde el segundo repo, o rompe la emisión/verificación de tokens si algo asume que coinciden. Se agregó SEC-118 para dejar esto explícito como acción coordinada.
- Confirma además, mirando `platforms-service`, que no hay evidencia de que este servicio verifique específicamente los JWT de sucursal emitidos por `branch.js` de concentrador-service (verifica los suyos propios, firmados en `_helpers.js:114`) — pero al ser la misma clave, un JWT de sucursal válido (firmado por concentrador-service) sería técnicamente válido también contra la verificación de `platforms-service` si esta no chequea claims adicionales — no confirmado en esta sesión, señalado como pendiente de revisión (SEC-119).

## Arquitectura de remediación propuesta (2026-07-22)

Servicios de AWS relevantes para sacar estos secretos del código y agregar rotación (ninguno requiere activación — ambos están disponibles por defecto en la cuenta; la disponibilidad real depende de permisos IAM, no de habilitación del servicio):

| Servicio | Rol en la remediación |
|---|---|
| **Secrets Manager** | Almacena los secretos (Mongo, claves AWS, PedidosYa, SendGrid, SmartFran Cloud, MercadoPago, `tokenStatic`). Tiene *scheduling* de rotación integrado — pero la rotación nativa sin código sólo existe para RDS/DocumentDB/Redshift. Para todo lo demás (Mongo Atlas, APIs de terceros) hace falta una **Lambda de rotación a medida** que genere el nuevo secreto y llame a la API de rotación propia de cada servicio (API de Atlas para el usuario de Mongo, el flow de refresh de cada integración de terceros). |
| **SSM Parameter Store** | Alternativa más económica sólo para *almacenar* (SecureString, cifrado con KMS) — sin scheduler de rotación propio; habría que construirlo con EventBridge + Lambda. |
| **KMS** | Cifrado en reposo subyacente para ambas opciones. |
| **Lambda** | Ejecuta la lógica real de rotación (con cualquiera de las dos opciones de almacenamiento) — necesaria en ambos casos, ya que ninguno de estos secretos es un tipo de recurso rotable nativamente por AWS. |
| **IAM** | Acota qué task/rol puede leer qué secreto (p. ej. el rol de tarea de `concentrador-service` sólo con acceso a los secretos de Mongo/AWS que usa, no a los de SendGrid/PedidosYa que son de `platforms-service`) — también la forma correcta de eliminar el patrón actual de copiar credenciales dentro del JWT de sucursal (SEC-006 del ticket 10-07-2026): dejar de embeber credenciales y leerlas de Secrets Manager en el punto de uso. |
| Bloque `secrets` de la task definition de ECS | Punto de integración: tanto Secrets Manager como SSM se referencian ahí directamente — el contenedor recibe el valor inyectado como variable de entorno al arrancar, sin tocar nunca el archivo de config versionado. |

**Recomendación:** Secrets Manager, dado que SEC-112 (no existe ningún proceso de rotación hoy) ya está en este ticket — conviene que el scheduling viva en la plataforma en vez de depender de un runbook manual. De cualquier forma, ambas opciones requieren escribir la Lambda de rotación a medida para Mongo Atlas y las integraciones de terceros — no es un fix de "sólo configuración".

## Implementación de SEC-114 (2026-07-30)

A pedido del PM, tras la presentación de cierre del PoC ARQ-009/ARQ-002 ([20260728_recursos-aws-poc-arq009_cierre.md](../20260728_recursos-aws-poc-arq009/20260728_recursos-aws-poc-arq009_cierre.md)), el rollout real de SEC-114 (migración a AWS Secrets Manager) pasa a trackearse en su propio ticket: **[20260730_secrets-manager-implementation](../20260730_secrets-manager-implementation/20260730_secrets-manager-implementation_investigation.md)** — mismo criterio de separación que `20260728_recursos-aws-poc-arq009` respecto de `20260720_ocultar-account-id-sqs-urls`: este ticket es el registro de hallazgo/auditoría, el nuevo es el registro de rollout.

Alcance del Stage 1 de ese ticket: sólo `token.secret` (único secreto ya validado de punta a punta en el PoC), vía inyección por bloque `secrets` de la task definition ECS — sin dependencias npm nuevas. Bloqueado hoy por SEC-117 (execution role de ECS sin confirmar). Detalle completo, comparación de caminos de implementación y pasos en el ticket nuevo.

## Criterios de aceptación

- [ ] Se confirmó si las credenciales de Mongo Atlas de los 5 entornos están activas.
- [ ] Se rotaron las credenciales de producción y staging como mínimo (prioridad sobre testing/development/performance).
- [ ] Se identificó el propósito de la credencial en `production.js:11-12` y del secreto reutilizado en `:28`.
- [ ] Los configs de entorno dejaron de tener credenciales en texto plano — se migraron a variables de entorno / secret manager.
- [ ] Se estableció si el mismo patrón existe en `platforms-service` (no relevado en esta sesión).

## Sub-tareas

| ID | Descripción | Archivo | Estado |
|---|---|---|---|
| SEC-101 | Confirmar actividad/vigencia de las credenciales Mongo Atlas de los 5 entornos | Atlas (fuera del repo) | 🔄 Producción confirmada activa 2026-07-22 (ver "Verificación de impacto") — staging/testing/development/performance sin confirmar |
| SEC-102 | Rotar credenciales de Mongo Atlas — prioridad producción y staging | Atlas (fuera del repo) | ⚠️ Pendiente |
| SEC-103 | Eliminar hardcode de `database.username`/`database.password` en los 5 configs de entorno | `concentrador-service/api/src/config/env/*.js` | ⚠️ Pendiente |
| SEC-104 | Identificar propósito y alcance de la credencial `production.js:11-12` y del secreto reutilizado en `:28` | `concentrador-service/api/src/config/env/*.js` | ⚠️ Pendiente |
| SEC-105 | Relevar si `platforms-service` tiene el mismo patrón de credenciales hardcodeadas en sus configs de entorno | `platforms-service` (no relevado) | ✅ [2026-07-22](20260720_credenciales-mongodb-hardcodeadas_events.md#2026-07-22) — mismo patrón confirmado, alcance mayor |
| SEC-106 | Reemplazar contraseña débil de staging al rotar | `concentrador-service/api/src/config/env/staging.js:44` | ⚠️ Pendiente |
| SEC-107 | Rotar secretos de `platforms-service` production: `token.secret`, `peyaParams` (password+secret), `SENDGRID_API_KEY`, `smlParams.client_secret`, `cloudParams.client_secret`, `MERCADOPAGO_DELIVERY_TOKEN`, credencial Mongo adicional (`concentrador`) — `tokenStatic` excluido de esta rotación, ver SEC-113 | `platforms-service/api/src/config/env/production.js` | ⚠️ Pendiente |
| SEC-113 | Decidir continuidad de la integración "Last Mile" antes de rotar `tokenStatic` — si se da de baja, eliminar la integración en vez de rotar | `platforms-service/api/src/platforms/management/strategies/newsTypeStrategy.js` | ⚠️ Pendiente — depende de decisión de producto/arquitectura |
| SEC-108 | Confirmar si `TOKEN_ENCRYPTION_KEY`/`TOKEN_ENCRYPTION_IV` están seteados como variable de entorno en producción, o si corre con el fallback hardcodeado trivial (`1234...`/`6543...`) | `platforms-service/api/src/config/env/production.js:66-67` | ⚠️ Pendiente |
| SEC-109 | Restringir la Network Access List de Atlas (hoy `0.0.0.0/0`) a los rangos de IP/VPC que realmente necesitan conectividad | Atlas (fuera del repo) | ⚠️ Pendiente |
| SEC-110 | Confirmar si la eliminación del cluster es realmente posible con esta credencial (rol de base de datos) o si el hallazgo real es "puede dropear cualquier base" (ya confirmado) — reportado, no verificado | Atlas (fuera del repo) | ⚠️ Pendiente |
| SEC-111 | Confirmado (2026-07-22, por el usuario): no existe proceso de rotación de credenciales en SmartPedidos — general del proyecto, no sólo de esta credencial | — | ✅ Confirmado |
| SEC-112 | Establecer una política de rotación periódica de credenciales/secretos (Mongo, AWS, y los de `platforms-service`) | Proceso, no código | ⚠️ Pendiente |
| SEC-114 | Migrar los secretos de `concentrador-service`/`platforms-service` a AWS Secrets Manager (o SSM Parameter Store), referenciados desde el bloque `secrets` de la task definition de ECS | `*/api/src/config/env/*.js`, task definitions ECS | 🔄 Rollout trackeado en ticket propio [20260730_secrets-manager-implementation](../20260730_secrets-manager-implementation/20260730_secrets-manager-implementation_investigation.md) — Stage 1 (`token.secret`) diseñado, implementación pendiente |
| SEC-115 | Escribir la Lambda de rotación a medida (Mongo Atlas vía API de Atlas; APIs de terceros vía su propio flow de refresh) — ninguno de estos secretos tiene rotación nativa de AWS | Nuevo — Lambda | ⚠️ Pendiente |
| SEC-116 | Acotar por IAM qué rol de tarea ECS puede leer qué secreto (scoping por servicio, no un secreto compartido con acceso total) | IAM (fuera del repo) | ⚠️ Pendiente |
| SEC-117 | Confirmar permisos IAM del rol de ejecución de tarea (`ecsTaskExecutionRole`, ver hallazgo Fargate en `smartpedidos/docs/infrastructure.md`) para `secretsmanager:GetSecretValue`/`ssm:GetParameter` — prerrequisito de SEC-114 | AWS IAM (fuera del repo) | ⚠️ Pendiente — bloquea el paso 3 del Stage 1 (arriba); el execution role real de las task definitions todavía no está confirmado, sólo el task role (`smartfran-task-role`) |
| SEC-118 | Rotar `token.secret` como acción única coordinada en ambos repos simultáneamente (no como dos rotaciones independientes) — es el mismo literal en `concentrador-service` y `platforms-service` | `concentrador-service/api/src/config/env/production.js:5-6`, `platforms-service/api/src/config/env/production.js:5-6` | ⚠️ Pendiente — corrige el alcance de SEC-107 |
| SEC-119 | Confirmar si `platforms-service` acepta como válido un JWT de sucursal emitido por `branch.js` de concentrador-service (misma clave HMAC, claims distintos) — determina si hay una superficie de cross-auth no intencional entre servicios | `platforms-service/api/src/middlewares/route-permissions.js`, `app.js:67` | ⚠️ Pendiente |

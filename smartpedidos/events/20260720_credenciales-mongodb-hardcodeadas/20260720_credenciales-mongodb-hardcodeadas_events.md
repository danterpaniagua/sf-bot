# Eventos — 20260720_credenciales-mongodb-hardcodeadas

## 2026-07-20 — Hallazgo durante investigación de origen del JWT del agente POS

**Autor:** Dante Paniagua

Al responder dónde se almacena el `branchSecret` usado en `POST /branches/login` (ticket [20260720_ocultar-account-id-sqs-urls](../20260720_ocultar-account-id-sqs-urls/20260720_ocultar-account-id-sqs-urls.md)), se leyó `concentrador-service/api/src/config/env/production.js` para confirmar el host de Mongo Atlas documentado. Se encontraron credenciales de conexión (`username`/`password`) hardcodeadas en texto plano en los cinco archivos de configuración de entorno.

**Verificación adicional (grep sobre los 5 configs):** a diferencia del hallazgo de AWS (mismo valor reutilizado en los 5 entornos), aquí cada entorno tiene usuario/password/host propio — diseño correcto de separación, pero mismo problema de exposición: todo en texto plano en git. Se identificó además un secreto no-DB reutilizado idéntico en `production.js:28`, `staging.js:28` y `testing.js:28`, y una credencial sin propósito identificado en `production.js:11-12`.

**Estado:** ticket abierto con hallazgo, ubicaciones exactas y sub-tareas (SEC-101 a SEC-106). Sin ejecución — ninguna credencial fue rotada ni se consultó Atlas para confirmar vigencia en esta sesión. Se decidió, a pedido del usuario, abrir esta investigación como ticket independiente en vez de anexarla a 10-07-2026_credenciales-expuestas-logs, dado que es una credencial distinta (Mongo Atlas, no AWS/SQS) con alcance de impacto mayor (toda la base `smartfran`, no sólo SQS).

**Archivo principal:** `20260720_credenciales-mongodb-hardcodeadas.md`

---

## 2026-07-22 — Extensión: mismo patrón confirmado en `platforms-service`, con más tipos de secreto

**Autor:** Dante Paniagua

Se relevó `platforms-service/api/src/config/env/production.js` (clon local `smartpedidos/repos/dev-scr-smartPedidos-platformsService/`) para resolver SEC-105. Confirmado: mismo patrón de hardcode, alcance mayor que en concentrador-service — en un único archivo aparecen en texto plano el secreto de firma JWT propio de platforms-service, credenciales de integración con PedidosYa, una API key completa de SendGrid, dos `client_secret` OAuth contra SmartFran Cloud, un token de MercadoPago, una credencial Mongo Atlas adicional (usuario `concentrador`, mismo cluster), y un fallback de clave/IV de cifrado trivial si las variables de entorno correspondientes no están seteadas.

Se agregó sección "Extensión (2026-07-22)" al ticket con la tabla de ubicaciones, se marcó SEC-105 como resuelto, y se agregaron SEC-107 (rotación) y SEC-108 (confirmar si el fallback de cifrado está activo en producción).

**Pendiente:** email a PMs/devs consolidando este hallazgo junto con el de AWS (10-07-2026) y el riesgo de vigencia del Bearer JWT (ocultar-account-id-sqs-urls) — en curso.

Se agregó también una nota sobre riesgo adicional: herramientas de IA con acceso de lectura al repo pueden interpretar una credencial hardcodeada como un recurso disponible y usarla directamente contra el entorno real, sin el paso de juicio humano de si corresponde hacerlo — riesgo distinto al de "alguien con acceso al repo la lee", relevante en la medida en que más del flujo de desarrollo pasa por agentes de código.

---

## 2026-07-22 — Verificación de impacto: credencial de Mongo Atlas producción confirmada activa, alcance mayor al asumido

**Autor:** Dante Paniagua

Se probó la credencial de producción de concentrador-service (`production.js:45-46`, usuario `smartfran`) contra el cluster real, vía `mongosh` (`db.runCommand({ connectionStatus: 1 })`). Resultado: activa, y con un alcance de privilegios mayor al documentado originalmente en el ticket — `authenticatedUserRoles` incluye `atlasAdmin`, `backup`, `clusterMonitor`, `dbAdminAnyDatabase`, `enableSharding` y `readWriteAnyDatabase`, todos en `db: 'admin'`.

Esto significa que la credencial no está acotada a la base `smartfran` como se había asumido — da lectura/escritura y administración sobre cualquier base del cluster, control de nivel proyecto/cluster (`atlasAdmin`), capacidad de iniciar backups/restores (vector de exfiltración completo del cluster) y cambios de topología (`enableSharding`).

Se corrigió la sección "Descripción del problema" del ticket, se agregó sección "Verificación de impacto (2026-07-22)" con la evidencia, y se actualizó SEC-101 (producción confirmada activa; staging/testing/development/performance sin confirmar todavía).

**Agravante adicional confirmado por el usuario:** la Network Access List de Atlas está abierta a `0.0.0.0/0` — el cluster no tiene restricción de IP/VPC, es alcanzable desde cualquier punto de Internet. Combinado con la credencial de alcance admin de cluster ya confirmada activa, no existe ninguna barrera de red adicional — el usuario/password filtrado en GitHub alcanza por sí solo. Se agregó SEC-109 (restringir Network Access List) y se agregó el agravante a la sección de impacto del ticket.

**Dos agravantes más reportados por el usuario:** (1) la credencial permite eliminar el cluster completo; (2) no existe período de rotación establecido. Se documentaron inicialmente como "confirmados", pero al preguntarme directamente si había validado esos postulados, la respuesta honesta fue que no — los transcribí sin verificación independiente.

**Corrección (2026-07-22):** se revisó cada uno.
- Capacidad destructiva: sí está confirmada, pero acotada a `dropDatabase()` sobre cualquier base (verificado a partir de los roles reales de `connectionStatus`). La eliminación del cluster en sí es técnicamente dudosa tal como se planteó — es una acción de plano de control de Atlas (API/consola de Organization o Project), distinta de los roles de base de datos de esta credencial (`atlasAdmin` y afines operan en el plano de datos). Se dejó como pendiente de confirmar (SEC-110), no como hallazgo cerrado.
- Falta de rotación: para AWS sí hay evidencia directa (ticket 10-07-2026, `aws iam get-access-key-last-used`). Para Mongo no se había corrido una verificación técnica equivalente — pero el usuario aclaró que esto no es específico de una credencial: **no existe ningún proceso de rotación de credenciales en SmartPedidos**, un hecho organizacional que el usuario puede confirmar directamente sin requerir un comando de verificación (a diferencia de la afirmación sobre qué permite un rol de MongoDB, que sí es una claim técnica verificable). SEC-111 se marcó como confirmado en base a esa aclaración; SEC-112 (establecer una política de rotación) queda como acción pendiente separada.

Se corrigió el ticket y el email para reflejar qué está confirmado con evidencia y qué es reportado/pendiente de verificar, sin mezclar ambos niveles de certeza. El usuario indicó como regla general: **validar siempre** antes de documentar un postulado como hallazgo confirmado — distinguiendo entre afirmaciones técnicas verificables con un comando y conocimiento organizacional que el usuario puede confirmar directamente.

---

## 2026-07-22 — Hallazgo adicional en platforms-service: `tokenStatic` (API Last Mile)

**Autor:** Dante Paniagua

Se identificó `config.tokenStatic` (usado como header `token` al llamar la API interna "Last Mile", `newsTypeStrategy.js:181-198`) como un secreto adicional no cubierto en el relevamiento anterior de `platforms-service`. Es un token estático, idéntico en `production.js`, `staging.js`, `testing.js` y `development.js`, y activo — se usa en cada transición de estado de una orden (confirm/ready/reject). Se agregó a la tabla de ubicaciones (#15).

**Aclaración del usuario:** la remediación de este ítem puntual depende de una decisión pendiente sobre si se sigue usando la integración "Last Mile" — si se da de baja, corresponde eliminar la integración en vez de rotar el token. Se excluyó `tokenStatic` de SEC-107 (rotación general) y se agregó SEC-113, condicionado a esa decisión de producto/arquitectura.

---

## 2026-07-22 — Arquitectura de remediación propuesta: Secrets Manager / SSM Parameter Store

**Autor:** Dante Paniagua

Se agregó al ticket una sección de arquitectura de remediación, cubriendo qué servicios de AWS aplican para sacar estos secretos del código y agregar rotación: Secrets Manager (almacenamiento + scheduler de rotación, pero rotación nativa sin código sólo para RDS/DocumentDB/Redshift), SSM Parameter Store (almacenamiento más económico, sin scheduler propio), KMS (cifrado subyacente), Lambda (lógica de rotación a medida, necesaria en ambos casos ya que ninguno de estos secretos es un tipo de recurso rotable nativamente), IAM (scoping de acceso por servicio) y el bloque `secrets` de la task definition de ECS como punto de integración.

**Recomendación registrada:** Secrets Manager, dado que ya está SEC-112 (no existe proceso de rotación hoy) — conviene que el scheduling viva en la plataforma. Se agregaron sub-tareas SEC-114 a SEC-117 (migración, Lambda de rotación a medida, scoping IAM por servicio, y confirmar permisos del rol de ejecución de tarea ECS como prerrequisito).

---

## 2026-07-28 — Corrección: `token.secret` de platforms-service y concentrador-service es el mismo literal

**Autor:** Dante Paniagua

Al diseñar el Lambda authorizer de ARQ-002 (ticket [20260720_ocultar-account-id-sqs-urls](../20260720_ocultar-account-id-sqs-urls/20260720_ocultar-account-id-sqs-urls.md)) se releyó el valor exacto de `token.secret` en ambos repos para decidir de dónde debía leerlo el authorizer en una implementación real. Resultado: `concentrador-service/api/src/config/env/production.js:5-6` y `platforms-service/api/src/config/env/production.js:5-6` tienen el literal idéntico `'ts$s38*jsjmjnT1'` — no son dos secretos distintos como se había registrado el 2026-07-22 (ítem #8 de la tabla, "distinto del de concentrador-service").

Se corrigió el ítem #8 de la tabla y se agregó una sección de corrección explicando el impacto: el radio de exposición es mayor (filtrar cualquiera de los dos repos compromete la firma de tokens de ambos servicios), y SEC-107 no puede tratarse como dos rotaciones independientes — es el mismo valor en dos lugares. Se agregaron SEC-118 (rotación coordinada, no independiente) y SEC-119 (confirmar si esto habilita una superficie de cross-auth no intencional entre concentrador-service y platforms-service, dado que comparten la clave HMAC).

También se detectó que `platforms-service` firma y verifica sus propios JWT (`_helpers.js:114`, `route-permissions.js:17-40`, middleware global `express-jwt` en `app.js:67`) — no hay evidencia de que verifique específicamente los JWT de sucursal de concentrador-service, pero al compartir la clave, uno sería técnicamente válido contra el otro si no se chequean claims adicionales (sin confirmar, SEC-119).

**Asunto:** Credenciales hardcodeadas en GitHub (Mongo, PedidosYa, SendGrid, SmartFran Cloud, MercadoPago) + riesgo de vigencia del Bearer token de sucursal

Hola a todos,

Les escribo para consolidar varios hallazgos relacionados que fuimos encontrando en la misma línea de investigación, para que quede todo junto y con la evidencia concreta.

Antes de entrar en el detalle, quiero ser claro sobre el origen de esto: no es código que se haya escrito así recientemente ni una decisión de nadie del equipo actual. Son patrones que vienen de código heredado — plataformas y servicios que adoptamos tal como estaban, sin haber tenido todavía el tiempo de revisarlos y llevarlos a un estándar de manejo de secretos. La credencial de AWS, por ejemplo, existe sin cambios desde 2020. Esto no es una lista de errores recientes — es deuda técnica que ya estaba ahí y que recién ahora estamos teniendo la visibilidad para dimensionar.

**1. MongoDB Atlas — credenciales hardcodeadas en concentrador-service**

Los cinco archivos de configuración de entorno de `concentrador-service` (`production.js`, `staging.js`, `testing.js`, `development.js`, `performance.js`) tienen usuario/password de Mongo Atlas en texto plano, uno distinto por entorno — el diseño de separación por entorno es correcto, pero las cinco credenciales, incluida producción, están versionadas en texto plano en GitHub. La contraseña de staging, además, es trivialmente débil.

**Verificamos el impacto real de la credencial de producción, y es mayor de lo que asumíamos.** Probamos la conexión hoy contra el cluster real: está activa, y sus roles (`atlasAdmin`, `backup`, `dbAdminAnyDatabase`, `readWriteAnyDatabase`, `enableSharding`, todos sobre `admin`) no la acotan a la base `smartfran` de esta aplicación — dan lectura/escritura y administración sobre **cualquier base del cluster**, capacidad de iniciar backups/restores (un vector de exfiltración de todo el cluster, no sólo de esta app) y cambios de topología. Es, en la práctica, una credencial de administrador del cluster completo, no una credencial de aplicación.

**Y no hay ninguna barrera de red que lo frene.** La Network Access List de Atlas está abierta a `0.0.0.0/0` — el cluster es alcanzable desde cualquier punto de Internet, sin VPN ni restricción de IP/VPC. En conjunto con lo anterior: el usuario/password que está en texto plano en GitHub alcanza, por sí solo, para conectarse con privilegios de administrador de cluster desde cualquier lugar del mundo. No hace falta ningún otro acceso.

**Y no es sólo un riesgo de robo de datos — es destructivo.** Los roles confirmados permiten borrar bases de datos completas (`dropDatabase`) de forma permanente, sobre cualquier base del cluster. No es sólo "alguien podría leer nuestros datos" — es "alguien podría borrarlos por completo, sin posibilidad de deshacerlo".

**No tenemos ningún proceso de rotación de credenciales en SmartPedidos.** No es un problema puntual de esta clave de Mongo — es general del proyecto. Para la clave de AWS lo confirmamos técnicamente además (activa sin cambios desde su creación en 2020). Es una de las cosas más simples de arreglar de todo lo que juntamos acá, y probablemente la de mayor impacto por esfuerzo: sin rotación periódica, cualquier secreto que se filtre (como los que ya encontramos) queda expuesto indefinidamente.

**2. Lo mismo, pero más grande de lo que pensábamos: platforms-service**

Al revisar si `platforms-service` tenía el mismo problema (pregunta que habíamos dejado abierta), confirmamos que sí — y con más secretos en juego que en concentrador-service. En un solo archivo (`platforms-service/api/src/config/env/production.js`) están en texto plano:
- El **secreto de firma de JWT propio de platforms-service** (distinto del de concentrador-service) — cualquiera con el repo puede firmar tokens válidos para este servicio.
- Credenciales de la integración con **PedidosYa** (usuario/password + secret de OAuth).
- Una **API key completa de SendGrid** — con eso se puede enviar email en nombre de nuestro dominio (riesgo de phishing/reputación), además del costo.
- Dos `client_secret` de OAuth contra **SmartFran Cloud** (distintas audiencias/scopes).
- Un token de integración con **MercadoPago**.
- Un **token estático** enviado a una API interna ("Last Mile") en cada confirmación/entrega/rechazo de orden — mismo valor hardcodeado en producción, staging, testing y development.
- Una credencial de Mongo Atlas **adicional** (usuario `concentrador`), sobre el mismo cluster de producción.
- Un **fallback de clave/IV de cifrado trivial** (`1234567890123456` / `6543210987654321`) si las variables de entorno `TOKEN_ENCRYPTION_KEY`/`TOKEN_ENCRYPTION_IV` no están seteadas — no confirmamos todavía si el entorno real las sobreescribe.

Esto es además del hallazgo de AWS que ya habíamos compartido (usuario IAM `userSQS`, clave activa hoy, `AmazonSQSFullAccess` sin restricción de recurso ni región) — mismo patrón, repositorio, y causa raíz: secretos de producción versionados en texto plano en GitHub en vez de vivir en variables de entorno o un secret manager.

**3. Cuánto dura un Bearer token de sucursal filtrado, y qué puede hacer alguien con él**

De forma independiente, en el análisis del proxy de API Gateway (ticket ocultar-account-id-sqs-urls) surgió otro ángulo del mismo problema. El JWT que recibe cada agente POS al hacer login (`POST /branches/login`) tiene una vigencia de **2000 horas (~83 días, casi tres meses)**, y al ser un JWT stateless, **no hay forma de revocarlo antes de tiempo** — si se filtra, sigue siendo válido todo ese tiempo.

Con ese token filtrado, un atacante puede:
- **Leerlo sin ningún secreto.** Un JWT está firmado, no cifrado — cualquiera puede decodificar el payload (`jwt.io` o una línea de código) y ver en texto plano las credenciales AWS embebidas (`aws_id`/`aws_secret`) que ya reportamos en el hallazgo de `userSQS`.
- **Usar esas credenciales AWS directamente**, sin pasar por ningún servicio nuestro, para leer, escribir o purgar cualquier cola SQS de la cuenta — no sólo la de la sucursal dueña del token.
- **Presentar el mismo JWT contra concentrador-service** para autenticarse como esa sucursal en la API de gestión.

En resumen: el Bearer token de una sola sucursal, si se filtra, ya equivale hoy a una clave de AWS de alcance total sobre la cuenta, válida por casi tres meses sin forma de cortarla antes. Esto refuerza que la prioridad no es sólo rotar las credenciales puntuales que encontramos, sino también revisar el diseño de cuánto tiempo vive este token y qué va embebido en él.

**4. Un riesgo más, específico de trabajar con herramientas de IA**

Un punto aparte pero relevante: tener secretos hardcodeados no sólo es un riesgo de "alguien con acceso al repo los lee". Un agente de IA (Claude Code, Copilot, etc.) al que se le pida debuggear o testear algo puede encontrar la credencial en el archivo que está leyendo y usarla directamente contra el entorno real, tratándola como un recurso disponible — sin el paso de juicio humano de si corresponde. No es hipotético: en esta misma investigación, confirmar que la credencial de Mongo seguía activa requirió construir un comando con el valor real leído del archivo. Es un argumento más para sacar los secretos del código, en la medida en que más del flujo de desarrollo pasa por este tipo de herramientas.

Ninguno de estos hallazgos es una sorpresa por negligencia — es lo esperable de sistemas heredados que nunca tuvieron una revisión de seguridad dedicada, y que se fueron adoptando y extendiendo (nuevas integraciones, nuevos entornos) sobre la misma base sin oportunidad de corregirla. Lo que cambia ahora es que tenemos la evidencia concreta para priorizar arreglarlo.

**Qué proponemos**

- Rotar las credenciales listadas en los hallazgos (Mongo — con prioridad alta dado el alcance de administrador de cluster confirmado —, AWS, y el conjunto de `platforms-service`), priorizando producción.
- Restringir la Network Access List de Atlas a los rangos de IP/VPC que realmente necesitan conectividad — hoy está en `0.0.0.0/0`.
- Migrar estos configs de entorno a variables de entorno o un secret manager (Secrets Manager/SSM), no archivos versionados.
- Confirmar si el fallback de cifrado trivial está realmente activo en producción hoy.
- Establecer un proceso de rotación periódica para todas las credenciales/secretos — hoy ninguna lo tiene.
- Como parte del trabajo de ocultar el Account ID de las URLs de SQS (que ya veníamos conversando), evaluar si conviene también acortar la vigencia del Bearer token o agregar un mecanismo de revocación — no es parte del alcance original de ese ticket, pero quedó en evidencia que es un riesgo relacionado.

Tenemos el detalle completo (archivo:línea de cada credencial) documentado si les sirve para el seguimiento — se los paso apenas lo necesiten.

Saludos,
Dante

# Eventos — 20260720_ocultar-account-id-sqs-urls

## 2026-07-20 — Apertura de análisis: ocultar Account ID de AWS en URLs de SQS

**Autor:** Dante Paniagua

Se planteó la pregunta de si existe un servicio de AWS que permita ocultar el Account ID en las URLs de SQS distribuidas a los agentes POS (hoy con el formato `https://sqs.<region>.amazonaws.com/<account-id>/<cola>`), dado el contexto ya documentado en [10-07-2026_credenciales-expuestas-logs](../10-07-2026_credenciales-expuestas-logs/10-07-2026_credenciales-expuestas-logs.md) de credenciales AWS estáticas embebidas en el JWT de cada agente.

**Propuesta registrada:** Amazon API Gateway con integración de servicio nativa a SQS, expuesto bajo un dominio propio (`colas.smartpedidos.com`) con una ruta/URL por cola. El Account ID y el nombre real de la cola quedan del lado del servidor, nunca visibles al cliente. Se documentó además que esta propuesta resuelve, como efecto colateral, la Opción B de SEC-006 (mover la interacción con SQS al backend), permitiendo eliminar la credencial AWS estática del agente.

**Aclaración registrada:** el requisito planteado de "no debe ser un CNAME" no es correcto como criterio de seguridad — ningún dominio custom de AWS (API Gateway, CloudFront, Route 53 ALIAS) expone el Account ID vía DNS ni resolución inversa, independientemente del tipo de registro usado. Lo que oculta el Account ID es dejar de exponer `sqs.<region>.amazonaws.com/<account-id>/...` directamente, no el tipo de registro DNS del dominio custom.

**Estado:** ticket creado con propuesta técnica y sub-tareas de análisis (ARQ-001 a ARQ-005). Sin ejecución — pendiente de validación con el equipo dueño del diseño de auth de concentrador-service, en coordinación con SEC-006.

**Archivo principal:** `20260720_ocultar-account-id-sqs-urls.md`

---

## 2026-07-20 — Descartada reutilización de CloudFront existente

**Autor:** Dante Paniagua

Se relevó `aws cloudfront get-distribution-config --id EN17DHYYWUZ8X` para evaluar si la distribución CloudFront ya en uso podía reutilizarse para el proxy de SQS. Resultado: no es candidata — sirve `boprodpedidos.smartfran.com` (frontend estático de back-office) sobre un único origen S3, con `DefaultCacheBehavior` limitado a `GET`/`HEAD` (sin soporte de `POST`, necesario para `SendMessage` a SQS).

Se agregó sección al ticket descartando la reutilización y recomendando publicar `colas.smartpedidos.com` directamente sobre el *custom domain* nativo de API Gateway, sin CloudFront de por medio (las respuestas de SQS no son cacheables, por lo que CloudFront no agrega valor). Se agregó sub-tarea ARQ-006.

---

## 2026-07-20 — Tabla comparativa API Gateway vs. CloudFront + API Gateway

**Autor:** Dante Paniagua

Se agregó al ticket una tabla de pros/contras (latencia, caching, WAF, complejidad operativa, certificado ACM, logging, costo, aislamiento) comparando "solo API Gateway" contra "CloudFront + API Gateway". Lectura preliminar: para tráfico transaccional no cacheable, "solo API Gateway" es la opción de menor costo y complejidad; CloudFront sólo se justificaría ante un requisito concreto de WAF/Shield a nivel edge no cubierto por el WAF regional de API Gateway.

---

## 2026-07-20 — Estimación de costo vía AWS Cost Explorer + Pricing API

**Autor:** Dante Paniagua

**Comandos ejecutados (read-only, por el usuario):**
- `aws ce get-cost-and-usage` (filtro `SERVICE=Amazon Simple Queue Service`, agrupado por `USAGE_TYPE`, junio 2026) → volumen real: 147.761.190 requests SQS FIFO, costo real $73,38 (requests) + $0,11 (data transfer, 1,43 GB) = $73,49/mes.
- `aws ce get-dimension-values` → confirmó nombre exacto del servicio en Cost Explorer (`Amazon Simple Queue Service`).
- `aws pricing describe-services` (`AmazonApiGateway`, `AmazonCloudFront`) → atributos válidos para filtrar (`regionCode`, `productFamily`, `location`, etc.).
- `aws pricing get-products --service-code AmazonApiGateway --filters regionCode=us-east-2` → tarifa HTTP API Ohio: $1,00/millón de requests (tramo 0–300M/mes), SKU `9R977R3Z4DEQKWJB`.
- `aws pricing get-attribute-values` (`AmazonCloudFront`, `productFamily` y `location`) → confirmó familias de producto (`Request`, `Data Transfer`, etc.) y valor `United States`.
- `aws pricing get-products --service-code AmazonCloudFront --filters productFamily=Request,location="United States"` → tarifa proxy HTTPS (POST/PUT/PATCH/DELETE/OPTIONS): $1,00/millón de requests, SKU `DCX5PSWXNPZDK63Q`.
- `aws pricing get-products --service-code AmazonCloudFront --filters productFamily="Data Transfer",location="United States"` → sin resultados (la familia `Data Transfer` de CloudFront se filtra por `fromLocation`/`toLocation`, no por `location`). No se profundizó — con ~1,4 GB/mes de transferencia el impacto es marginal y no cambia la conclusión.

**Resultado agregado al ticket (sección "Estimación de costo"):**
- Baseline real (SQS directo): $73,49/mes.
- Opción A (solo API Gateway): ~$147,76/mes (+$74,27 vs. baseline, +101%).
- Opción B (CloudFront + API Gateway): ~$295,52/mes (+$222,03 vs. baseline, +302%; +$147,76 vs. Opción A — prácticamente el doble, sin beneficio de cacheo).

**Conclusión:** el dato de costo confirma la lectura preliminar de la tabla comparativa — Opción A es la recomendada. Se marcó ARQ-007 como resuelto.

---

## 2026-07-20 — Corrección: integración nativa a SQS sólo existe en REST API, no en HTTP API

**Autor:** Dante Paniagua

Al preparar el PoC se identificó un error en la estimación de costo previa: la integración de servicio nativa a SQS sin Lambda (`AWS`/VTL, no `AWS_PROXY`) sólo está disponible en **REST API (API Gateway v1)**. Las **HTTP API (v2)** — cuya tarifa de $1,00/millón se había usado por error en "Opción A" — no soportan integración directa a un servicio AWS; sólo Lambda proxy, HTTP proxy o integración privada a ALB/NLB/CloudMap.

**Recalculado con la tarifa real de REST API** (`$3,50/millón`, SKU `6GJWQNG8KBVT7A5U`, ya obtenida en la consulta original a Pricing API):
- Opción A (REST nativo, sin Lambda): ~$517,16/mes (+604% vs. baseline $73,49).
- Opción A' (HTTP API + Lambda liviana, nueva alternativa): ~$180,39/mes (+145% vs. baseline) — técnicamente válida y más económica, pero agrega Lambda como componente.
- Opción B (CloudFront + REST nativo): ~$664,92/mes (+805% vs. baseline).

Se corrigió la sección "Estimación de costo" y la fila de costo de la tabla comparativa en el ticket. Se agregó ARQ-008 (decisión pendiente entre Opción A y A') y se dejó explícito que **ninguna variante es más barata que el acceso directo a SQS** — el objetivo del ticket es seguridad, no ahorro.

---

## 2026-07-20 — Aclaración de alcance: ocultar Account ID no reemplaza SEC-002/003/006

**Autor:** Dante Paniagua

En respuesta a una pregunta directa sobre si ocultar el Account ID es en sí una buena práctica: se documentó en el ticket que es una medida de *defense-in-depth* (reduce valor de reconocimiento de una URL interceptada) pero no mitiga la vulnerabilidad de fondo — la credencial estática `userSQS`/`AmazonSQSFullAccess` embebida en el JWT de sucursal sigue siendo explotable independientemente del Account ID visible. El valor real de esta propuesta es habilitar la eliminación de credenciales AWS del agente POS (resuelve SEC-006), no el ocultamiento del Account ID en sí mismo.

También se corrigió el diseño de "una URL por cola": dado que las colas siguen la convención `{branchId}_PlatformMessages.fifo` (una por sucursal), se documentó que el recurso de API Gateway debe ser parametrizado (`/{branchId}`) en vez de un recurso literal fijo por cola, para no requerir redeploy por cada sucursal nueva.

---

## 2026-07-20 — Inicio de PoC: REST API + SQS nativo, cuenta 382381053403, región us-west-2

**Autor:** Dante Paniagua

Se acordó construir un PoC para validar el mecanismo. Confirmado con el usuario: cuenta `382381053403` (misma cuenta que producción — no existe cuenta sandbox separada para AWS de SmartPedidos), región `us-west-2` (aislada de `us-east-2`, donde viven las colas reales de producción/staging). Se mostró el banner de comando destructivo antes de proceder, dado que la creación de recursos escribe estado en la cuenta.

Se optó por **REST API con integración nativa** (Opción A) para el PoC, no HTTP API + Lambda, para probar primero el mecanismo sin componentes adicionales. El PoC usará una cola SQS de prueba desechable (no una cola `_STG_`/`_PRD_` real) y un recurso parametrizado `/{branchId}` para validar el diseño de escalabilidad documentado en ARQ-001.

**Pendiente:** comandos de creación (cola de prueba, rol IAM scopeado, REST API, integración, deploy) — se proveen en la siguiente entrada de este log conforme se ejecuten.

---

## 2026-07-20 — Verificación de origen del JWT del agente POS (código fuente)

**Autor:** Dante Paniagua

Se respondió, con verificación directa en el clon local de `concentrador-service` (`smartfran/sp-logs/repo/`), la pregunta de si el JWT del agente POS lo emite una plataforma de delivery (PedidosYa/Uber Eats/Rappi) o concentrador-service.

**Resultado:** lo emite concentrador-service — `controllers/branch.js:4562` (`login`), ruteado en `POST /branches/login` (`routes/branches.js:82`). El agente se autentica con `branchId`/`branchSecret` propios; el JWT se firma con `jwt.sign({ user: savedBranch }, settings.token.secret, { expiresIn: '2000h' })` (`branch.js:4665-4672`). Sin participación de terceros.

**Hallazgo nuevo agregado al ticket:** las credenciales AWS se duplican en el body de la respuesta HTTP sin firmar (`branch.js:4674-4681`, objeto `data` con `aws_id`/`aws_secret` explícitos), además de viajar dentro del JWT. Segundo vector de exposición no documentado en el ticket 10-07-2026_credenciales-expuestas-logs.

Se agregó sección "Origen del JWT del agente POS (verificado en código fuente)" al ticket, confirmando que la migración propuesta no requiere coordinación con plataformas de delivery.

---

## 2026-07-22 — Decisión ARQ-002: reutilizar JWT de sucursal vía Lambda authorizer, con binding de `branchId` obligatorio

**Autor:** Dante Paniagua

Se definió el mecanismo de autenticación del agente POS contra el nuevo proxy (ARQ-002): reutilizar el JWT de sucursal ya emitido por `POST /branches/login`, validado mediante un Lambda TOKEN authorizer (REST API v1 no soporta autorizador JWT nativo para HS256 simétrico). Se aclaró que este Lambda es distinto del descartado en la Opción A' — sólo corre en la decisión de autorización (cacheada, TTL 300s por defecto), no en el *data path* de cada mensaje, por lo que no reabre el trade-off de costo "sin Lambda".

**Caveats agregados al ticket:**
- Sin mecanismo de revocación: el JWT es stateless, sigue siendo válido hasta su vencimiento natural (`expiresIn: '2000h'`, ~83 días) si se filtra — la migración no acorta esa ventana de exposición.
- Binding de `branchId` obligatorio: el authorizer debe comparar el claim `user.branchId` del JWT contra el path parameter `{branchId}` de la request y rechazar si no coinciden, para evitar que un JWT filtrado de una sucursal se use contra la cola de otra sucursal.
- El secreto de firma (`settings.token.secret`) no debe duplicarse como literal en el Lambda authorizer — debe obtenerse de Secrets Manager/SSM.

Se agregó sección "Autenticación del POS contra el proxy — decisión ARQ-002, con caveat de binding obligatorio" al ticket y se actualizó el estado de ARQ-002 en la tabla de sub-tareas.

---

## 2026-07-28 — ARQ-009: PoC construido y validado end-to-end

**Autor:** Dante Paniagua

Se retomó y completó el PoC de ARQ-009 (cuenta `382381053403`, región `us-west-2`). Scripts en `smartpedidos/repos/ocultar-accountid/` (`poc_arq009.sh`, `validate_arq009.sh`). Recursos creados: dos colas SQS FIFO desechables (`poc-arq009-branchA.fifo`, `poc-arq009-branchB.fifo`), rol IAM `poc-arq009-apigw-sqs-role` (scopeado a `sqs:SendMessage` sólo sobre esas dos colas), REST API (API Gateway v1) con recurso parametrizado `POST /{branchId}`, integración nativa `AWS` (no proxy) contra `arn:aws:apigateway:us-west-2:sqs:action/SendMessage` con plantilla VTL que construye el `QueueUrl` del lado del servidor a partir del path parameter. Autorización `NONE` para esta fase — el authorizer Lambda de ARQ-002 queda diferido a una segunda fase, como estaba previsto.

**Resultado: mecanismo validado.** `POST /poc/branchA` entregó el mensaje a `poc-arq009-branchA.fifo` (`MessageId 516c0182-...`) y `POST /poc/branchB` a `poc-arq009-branchB.fifo` (`MessageId f3b34ecf-...`) — confirmado en ambos casos haciendo coincidir el `MessageId` de la respuesta del `curl` con el mensaje efectivamente presente en la cola correcta. El Account ID de AWS nunca aparece en la URL que ve el cliente.

**Tres problemas reales encontrados y corregidos durante la construcción** (documentados en `investigation.md` para que ARQ-001 los incorpore a la plantilla VTL definitiva):
1. La integración `sqs:action/SendMessage` requiere el parámetro `Version=2012-11-05` explícito en el body — sin él, SQS devuelve `NonExistentQueue: ... for this wsdl version` para colas FIFO específicamente, aunque la cola y el `QueueUrl` sean correctos.
2. `aws apigateway put-integration` reemplaza el objeto de integración completo, **borrando silenciosamente** cualquier `put-integration-response` previamente configurado — cada vez que se actualiza la integración hay que re-emitir `put-integration-response`, o el cliente recibe `Internal server error` genérico aunque el llamado real a SQS haya sido exitoso (sólo visible habilitando logs de ejecución en CloudWatch, apagados por defecto).
3. Sintaxis VTL: `$input.params('branchId').fifo` interpreta `.fifo` como un acceso de propiedad encadenado sobre la referencia (se resuelve a vacío silenciosamente) en vez de texto literal — hace falta la forma "formal" `${input.params('branchId')}.fifo`.

También se detectó y resolvió, en el camino, un duplicado accidental de REST API vacío (`create-rest-api` ejecutado dos veces) que causaba el error inicial `create-deployment: The REST API doesn't contain any methods` — se identificó cuál de los dos IDs tenía el método realmente adjunto antes de decidir cuál desplegar.

**Pendiente de limpieza (no ejecutado aún):** el REST API duplicado vacío (`5t5c2si3s3`), los mensajes de prueba acumulados en ambas colas, y —una vez que ARQ-001/ARQ-008 ya no necesiten el PoC vivo como referencia— el API funcional, ambas colas y ambos roles IAM (`poc-arq009-apigw-sqs-role`, `apigateway-cloudwatch-logs-poc`). Todo esto son operaciones destructivas, requieren el banner correspondiente y confirmación explícita antes de ejecutarse.

Se marcó ARQ-009 como resuelto en la tabla de sub-tareas del ticket.

---

## 2026-07-28 — Mapeo de la superficie de integración en concentrador-service

**Autor:** Dante Paniagua

Se relevó contra el clon local de `concentrador-service` (`smartpedidos/repos/dev-src-smartPedidos-concentradorService/`) qué código real hay que tocar para integrar el mecanismo validado en ARQ-009. Único endpoint que hoy entrega credenciales AWS al agente POS: `login` (`POST /branches/login`, `branch.js:4917-4925`) — devuelve `region`, `aws_id`, `aws_secret`, `platform_queue`, todos innecesarios una vez que el agente hable contra `colas.smartpedidos.com/{branchId}` en vez de SQS directo (ya recibe `accessToken`, que carga `branchId`). `api/src/provider/aws.js` no requiere cambios — es el acceso propio de concentrador-service a SQS (ciclo de vida de colas, consumidor de dead-letter) vía el rol de tarea ECS, no la credencial estática que se entrega al POS.

**Hallazgo nuevo:** `credentials.aws_id`/`aws_secret` no son realmente por-sucursal — `saveOne` (creación de sucursal, `branch.js` ~4419) asigna el mismo par de claves estático (`config.AWS.SQS.CREDENTIALS`, idéntico en los 5 archivos de config de entorno) a cada sucursal nueva. Sin aislamiento real de credenciales por sucursal pese a estar guardadas por-sucursal en el schema. Refuerza SEC-006 — se recomienda agregarlo también al ticket de origen (10-07-2026_credenciales-expuestas-logs).

**Mecanismo de rollout ya existe:** `login` ya lee `agent-version` del header y lo compara contra `smartfran_sw.agent.installedVersion` (`branch.js:4890-4906`) como parte del flujo de actualización de software existente — es el punto natural para gatear la respuesta (agentes viejos siguen recibiendo credenciales AWS sin cambios; agentes nuevos, a partir de una versión de corte, sólo reciben `accessToken`). La lógica de gateo en sí no existe todavía, hay que escribirla.

**Confirmado pendiente:** el Lambda TOKEN authorizer de ARQ-002 (validación del bearer JWT — extracción, verificación de firma contra `settings.token.secret` vía Secrets Manager/SSM, binding obligatorio `user.branchId` == `{branchId}` del path, respuesta IAM Allow/Deny) sigue sin construirse — el PoC corrió con `authorizationType: NONE`. Dependencia cruzada: quien construya el Lambda necesita acceso de lectura al secreto de firma de concentrador-service en Secrets Manager/SSM.

Se actualizó el estado de ARQ-003 en la tabla de sub-tareas — falta todavía el lado del agente POS (repo fuera de este monorepo, no relevado).

---

## 2026-07-28 — ARQ-009 extendido: GET /{branchId} para lectura de mensajes (ReceiveMessage)

**Autor:** Dante Paniagua

Se agregó el método `GET` al mismo recurso `/{branchId}` (id `468mau`) del REST API del PoC, mapeado a `sqs:action/ReceiveMessage`, reusando el mismo rol IAM (`poc-arq009-apigw-sqs-role`, extendido con el permiso `sqs:ReceiveMessage` sobre las mismas 2 colas — sin ampliar el alcance más allá de eso) y la misma plantilla VTL con la sintaxis `${input.params('branchId')}` y `Version=2012-11-05` ya validadas en el `POST`. Al aplicar esos dos fixes desde el principio, funcionó en el primer despliegue, sin necesidad de debugging.

**Resultado:** `GET /poc/branchA` devolvió el mensaje correcto de `poc-arq009-branchA.fifo` (`MessageId 516c0182-...`, el mismo mensaje del test de `SendMessage` anterior) y `GET /poc/branchB` devolvió el de `poc-arq009-branchB.fifo` (`MessageId f3b34ecf-...`). Queda probado el ciclo completo de lectura y escritura a través del proxy sin exponer el Account ID, en ambas direcciones.

---

## 2026-07-28 — ARQ-002 implementado y validado: Lambda TOKEN authorizer

**Autor:** Dante Paniagua

Se construyó el Lambda authorizer pendiente de ARQ-002 (`smartpedidos/repos/ocultar-accountid/authorizer/index.js`, verificación HS256 con `crypto` nativo de Node — sin dependencia de `jsonwebtoken`, sin necesidad de bundling ya que `@aws-sdk/client-secrets-manager` viene incluido en el runtime `nodejs20.x` de Lambda). Recursos creados: secreto en Secrets Manager `poc-arq009/jwt-secret`, rol IAM `poc-arq009-authorizer-lambda-role`, función Lambda `poc-arq009-jwt-authorizer`, autorizador `TOKEN` `1arn20` en el REST API (`o0o4lrn2hg`), TTL de caché 300s.

**Decisión del usuario:** el secreto en Secrets Manager contiene el `token.secret` real de producción (`'ts$s38*jsjmjnT1'`), no un valor de prueba — justificado porque ya es un secreto hardcodeado sin rotación en dos repos (ver [20260720_credenciales-mongodb-hardcodeadas](../20260720_credenciales-mongodb-hardcodeadas/20260720_credenciales-mongodb-hardcodeadas.md)), y permite validar el authorizer contra tokens realmente compatibles con concentrador-service.

**Bug encontrado y corregido:** la política inline `poc-arq009-secrets-read` (permiso `secretsmanager:GetSecretValue`) nunca quedó adjunta al rol durante el batch inicial de comandos — no se verificó su éxito individual en su momento. Síntoma: `500` en toda request con token (vs. `401` correcto en request sin token, ya que ese camino no llega a Secrets Manager). Diagnosticado invocando el Lambda directamente (`aws lambda invoke`, sin pasar por API Gateway), que expuso el `AccessDeniedException` real en vez del `500` genérico de API Gateway. Corregido re-aplicando `put-role-policy`.

**Resultado — 5 escenarios probados, todos correctos:**
1. Token de `branchA` contra `/branchA` → `200`.
2. Token de `branchA` contra `/branchB` (firma válida, `branchId` no coincide) → `403` — binding obligatorio funciona.
3. Sin token → `401`.
4. Token con firma inválida (secreto incorrecto) → `401`.
5. Token de `branchB` contra `POST /branchB` → `200` — funciona en ambos métodos.

La política generada por el authorizer autoriza `.../poc/*/{branchId}` (wildcard de método) — un mismo token habilita tanto `GET` como `POST` para su propia sucursal, nada más. Se marcó ARQ-002 como resuelto en la tabla de sub-tareas.

---

## 2026-07-28 — ARQ-010: nuevo análisis de costos (Lambda authorizer + Secrets Manager + CloudWatch Logs)

**Autor:** Dante Paniagua

Se abrió ARQ-010 para extender el análisis de costo de ARQ-007, que sólo contemplaba API Gateway + SQS — no incluía el Lambda authorizer, Secrets Manager ni CloudWatch Logs, agregados durante la construcción del PoC (ARQ-002/ARQ-009). Se aprovechó además para corregir la región de pricing: ARQ-007 usó `us-east-2`, pero la corrección del 2026-07-27 estableció que producción real es `us-east-1`.

Se solicitaron al usuario: conteo real de sucursales/agentes activos (`db.branches.countDocuments`) — necesario porque el costo del authorizer depende de tokens únicos por ventana de caché de 300s, no del volumen total de requests — y 6 consultas de `aws pricing get-products` (API Gateway REST en `us-east-1`, Lambda requests + duration, Secrets Manager, CloudWatch Logs ingestion + storage). En curso, a la espera de esos datos.

**Movido a ticket propio 2026-07-28:** [20260728_nuevo-analisis-costos](../20260728_nuevo-analisis-costos/20260728_nuevo-analisis-costos.md) — mismo alcance, se separa para no mezclar seguimiento de análisis de costo con el ticket de diseño/PoC. Continuar ahí.

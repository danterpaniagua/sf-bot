# Análisis de Seguridad — Fraude Confirmado (2026-06-03)

## Contexto del incidente

El 3 de junio de 2026 se confirmaron dos patrones de fraude en producción:

**Patrón A — Credential stuffing + vaciado automático de cuentas (canal WEB):**
12 cuentas de clientes legítimos tuvieron sus saldos de puntos transferidos completamente en pocos minutos. Los montos transferidos eran irregulares y no redondeados (ej.: 8.660 / 4.119 / 1.425 pts), consistente con una lógica de "enviar todo el saldo disponible". Todas las transferencias se originaron desde el canal WEB y apuntaron a la misma cuenta agregadora. Dicha cuenta luego realizó una única transferencia de 30.000 pts a las 01:52 hora local.

**Patrón B — Transferencias rápidas que evaden el límite diario (canal APP):**
Una cuenta realizó 4 transferencias al mismo destinatario en 93 segundos (8.000 + 8.000 + 8.000 + 6.000 pts). El límite diario configurado para clientes regulares es de 8.000 pts, pero el sistema aceptó las cuatro sin bloquear ninguna.

---

## Alcance de este análisis

Este documento cubre los proyectos **ClubSiteG2** (portal del cliente, canal WEB) y la capa de dominio compartida que invoca. El proyecto MobileAppService está excluido del alcance por restricciones de red (NSG). WebSite no expone endpoints de transferencia de puntos.

---

## Location attribute keys reference

These keys are stored in `Sml.LocationAttributeValue` and drive the transfer and earning logic. LocationId 1 = Argentina, LocationId 9 = second country instance.

| AttributeCode | Used in | Purpose |
|---|---|---|
| `CustomerPointsMinLimit` | `Core/Domain/Domain/SaleContext/SaleService.cs:2091` | Daily cap on points **earned** per sale |
| `CustomerPointsMidLimit` | `SaleService.cs:2092` | Weekly cap on points **earned** per sale |
| `CustomerPointsMaxLimit` | `SaleService.cs:2093` | Monthly cap on points **earned** per sale |
| `PointsTransferActive` | `Front/ClubSiteG2/Controllers/CustomerController.cs:255` | Master switch — value `"1"` enables the transfer feature for that location |
| `CustomerPointsMinLimitTransfer` | `Core/Domain/Domain/CustomerContext/CustomerService.cs:568` (fallback only) | Daily cap on points **sent** by a regular customer — currently unreachable due to Hallazgo 1 |
| `CustomerPointsMidLimitTransfer` | `CustomerService.cs:569` (fallback only) | Weekly cap on points **sent** by a regular customer — currently unreachable |
| `CustomerPointsMaxLimitTransfer` | `CustomerService.cs:570` (fallback only) | Monthly cap on points **sent** by a regular customer — currently unreachable |
| `ColaboratorPointsMinLimitTransfer` | `CustomerService.cs:562` | Daily cap on points **sent** by a contributor — applied to **all** customers due to Hallazgo 1 |
| `ColaboratorPointsMidLimitTransfer` | `CustomerService.cs:561` | Weekly cap on points **sent** — same issue |
| `ColaboratorPointsMaxLimitTransfer` | `CustomerService.cs:560` | Monthly cap on points **sent** — same issue |

---

## Hallazgos

---

### Hallazgo 1 — Los límites del colaborador se aplican a todos los clientes, independientemente del tipo de cuenta

**Archivo:** `Core/Domain/Domain/CustomerContext/CustomerService.cs`, líneas 550–590

**Área:** Dominio compartido (invocado por ClubSiteG2 y MobileAppService)

**Severidad:** Crítica — explica directamente el Patrón B y parte del Patrón A

#### ¿Qué ocurre?

La función `GetAvailablePointsTransfer` recibe el parámetro `isCustomerContributor` (línea 550) para distinguir entre clientes regulares y colaboradores. Sin embargo, ese parámetro **nunca se usa** dentro de la función para decidir qué límites aplicar.

En cambio, la función siempre lee los atributos `ColaboratorPointsMinLimitTransfer`, `ColaboratorPointsMidLimitTransfer` y `ColaboratorPointsMaxLimitTransfer` de la ubicación Argentina (id=1 hardcodeado, línea 556), sin importar el tipo de cliente.

Los valores configurados en base de datos para esos atributos son:

| Atributo | Valor en DB (colaborador) | Valor esperado para cliente regular (AppSettings) |
|---|---|---|
| `ColaboratorPointsMinLimitTransfer` | 30.000 pts/día | `CustomerPointsMinLimitTransfer` = 8.000 pts/día |
| `ColaboratorPointsMidLimitTransfer` | 40.000 pts/semana | `CustomerPointsMidLimitTransfer` = 10.000 pts/semana |
| `ColaboratorPointsMaxLimitTransfer` | 60.000 pts/mes | `CustomerPointsMaxLimitTransfer` = 13.000 pts/mes |

La condición de fallback en la línea 566 que leería los valores correctos del AppSettings solo se ejecuta si `location?.Attributes == null`. Como Argentina sí tiene atributos configurados, el fallback nunca se activa y los límites del colaborador se aplican a todos.

#### ¿Cómo lo explotó el atacante?

**Patrón B:** El script envió transferencias de 8.000 pts (el límite diario del cliente regular según las reglas de negocio) repetidamente. El sistema validaba cada una contra el límite del colaborador (30.000 pts/día en lugar de 8.000), por lo que las aprobaba. La suma 8.000 + 8.000 + 8.000 + 6.000 = **30.000 pts** coincide exactamente con el límite diario del colaborador. La última transferencia de 6.000 pts corresponde al saldo restante después de tres envíos de 8.000.

**Patrón A:** La cuenta agregadora, independientemente de su tipo, pudo enviar una única transferencia de 30.000 pts en un solo request porque ese monto estaba dentro del límite diario del colaborador aplicado incorrectamente.

#### ¿Qué debe resolverse?

La función debe usar el parámetro `isCustomerContributor` para decidir qué límites aplicar. Si el cliente es colaborador, usar los atributos `ColaboratorPoints*` de la ubicación. Si es cliente regular, usar las claves `CustomerPoints*LimitTransfer` del AppSettings. La decisión sobre los valores concretos de cada límite corresponde al negocio.

---

### Hallazgo 2 — El endpoint de transferencia obsoleto omite completamente la validación de límites

**Archivo:** `Front/ClubSiteG2/Controllers/CustomerController.cs`, líneas 183–215

**Área:** ClubSiteG2 (canal WEB)

**Severidad:** Crítica — habilita vaciado de saldo sin pasar por ningún control de límites

#### ¿Qué ocurre?

Existen dos endpoints de transferencia de puntos en ClubSiteG2:

- `POST /Customer/PointsTransferSecurity` (línea 224): el endpoint actual, que llama a `GetAvailablePointsToTransfer` antes de procesar la transferencia.
- `POST /Customer/PointsTransfer` (línea 183): marcado como `[Obsolete]` pero **todavía enrutado y funcional**. Llama directamente a `AddPointsTransference` sin invocar ninguna validación de límites.

El endpoint obsoleto recibe el monto a transferir directamente desde el cuerpo del request HTTP (`model.Pt`) y lo envía sin restricción al servicio de dominio. Las únicas verificaciones que aplica son que el remitente tenga sesión activa y que la transferencia esté habilitada para su ubicación.

Este endpoint omite tanto la validación del Hallazgo 1 como cualquier corrección futura que se haga sobre ella, ya que la bypasea por completo.

#### ¿Cómo lo explotó el atacante?

Con una sesión válida (obtenida por credential stuffing), el atacante pudo apuntar a `/Customer/PointsTransfer` enviando como `Pt` el saldo exacto de la cuenta víctima. Los montos irregulares del Patrón A (8.660 / 4.119 / 1.425 pts) son consistentes con este vector: corresponden al saldo total de cada cuenta al momento del ataque.

#### ¿Qué debe resolverse?

El método `PointsTransfer` marcado `[Obsolete]` (línea 183) debe eliminarse o deshabilitarse de modo que el endpoint deje de responder. Antes de hacerlo se debe confirmar si alguna versión activa de cliente todavía llama a esa URL.

---

### Hallazgo 3 — El contador de intentos fallidos de login está en sesión y se resetea por request

**Archivo:** `Front/ClubSiteG2/Controllers/AccountController.cs`, líneas 2847–2857 (método `AddInvalidLoginAttempt`) y líneas 1294–1299 (lectura en `LoginUser`)

**Área:** ClubSiteG2 (canal WEB)

**Severidad:** Alta — facilita el credential stuffing del Patrón A

#### ¿Qué ocurre?

Cuando un intento de login falla, el sistema incrementa un contador almacenado en la sesión ASP.NET (`Session["InvalidLoginAttemptsCount"]`). La sesión se identifica mediante una cookie. Si el cliente no envía esa cookie, ASP.NET crea una sesión nueva con el contador en cero.

El contador se lee en `LoginUser` (línea 1294) pero **nunca se usa para bloquear el intento del lado del servidor**. Su único efecto es controlar si el frontend solicita un token de CAPTCHA. El bloqueo efectivo de la cuenta o del intento no ocurre en el servidor.

#### ¿Cómo lo explotó el atacante?

El atacante utilizó un cliente HTTP que no reusa cookies entre requests, obteniendo una sesión nueva en cada intento. El contador siempre partía de cero, por lo que el sistema nunca alcanzaba el umbral `MaxInvalidLoginAttempts = 3`. El CAPTCHA estaba activo (SecurityCaptcha = True en base de datos), pero el atacante lo resolvió externamente — servicios de resolución de CAPTCHA automatizados tienen un costo de fracciones de centavo por resolución y son de uso extendido en ataques de credential stuffing. La ausencia de bloqueo basado en IP o en cuenta dejó el endpoint de login abierto a intentos ilimitados.

#### ¿Qué debe resolverse?

El contador de intentos fallidos debe almacenarse en un mecanismo que el atacante no pueda resetear descartando una cookie: por dirección IP, por nombre de usuario, o ambos, usando cache de aplicación o base de datos. El servidor debe aplicar el bloqueo antes de invocar al servicio de autenticación, no solo informarlo al frontend.

---

### Hallazgo 4 — El estado del CAPTCHA es consultable de forma anónima y controlable desde base de datos sin trazabilidad

**Archivo:** `Front/ClubSiteG2/Controllers/AccountController.cs`, líneas 172–193 (método `GetSecurityCaptcha`) y líneas 1304–1307 (uso en `LoginUser`)

**Área:** ClubSiteG2 (canal WEB)

**Severidad:** Media

#### ¿Qué ocurre?

La decisión de validar o no el CAPTCHA en el login está controlada por el parámetro `SecurityCaptcha` en la tabla `Sml.Param` de la base de datos. Al momento del ataque ese valor era `True`, por lo que el CAPTCHA estaba activo.

Sin embargo, ese valor es modificable en tiempo de ejecución desde el backoffice sin requerir un redespliegue y sin dejar trazabilidad de auditoría en el repositorio. Un cambio a `False` desactiva la validación del CAPTCHA globalmente para todos los usuarios de forma inmediata.

Adicionalmente, el endpoint `GET /Account/GetSecurityCaptcha` (líneas 172–173) está decorado con `[AllowAnonymous]`, lo que permite a cualquier actor externo consultar si el CAPTCHA está activo antes de intentar un ataque, sin necesidad de autenticación.

#### ¿Qué debe resolverse?

El endpoint `GetSecurityCaptcha` no debe ser accesible sin autenticación. Si la gestión del CAPTCHA requiere un mecanismo de activación/desactivación, ese cambio debe quedar registrado en un log de auditoría y, preferentemente, requerir un redespliegue para modificarse, de modo que no pueda ser alterado silenciosamente desde el backoffice.

---

## Resumen

| # | Archivo principal | Líneas | Relación con el ataque confirmado |
|---|---|---|---|
| 1 | `Core/Domain/Domain/CustomerContext/CustomerService.cs` | 550–590 | Límites del colaborador aplicados a clientes regulares → 30.000 pts/día en lugar de 8.000 → Patrón B y transferencia agregadora del Patrón A |
| 2 | `Front/ClubSiteG2/Controllers/CustomerController.cs` | 183–215 | Endpoint obsoleto activo sin validación de límites → vaciado directo de saldo → montos irregulares del Patrón A |
| 3 | `Front/ClubSiteG2/Controllers/AccountController.cs` | 2847–2857, 1294–1299 | Contador de intentos reseteado por sesión → credential stuffing sin bloqueo → 12 cuentas comprometidas |
| 4 | `Front/ClubSiteG2/Controllers/AccountController.cs` | 172–193, 1304–1307 | Estado del CAPTCHA públicamente consultable y modificable sin auditoría → riesgo de desactivación silenciosa |

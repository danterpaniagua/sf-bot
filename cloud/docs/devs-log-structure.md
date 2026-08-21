# Estructura de los logs en consola

> Documento de referencia interno. Define la **forma exacta** del JSON que cada
> host de SmartFran.Cloud (APIs, Client.Web, Functions, Pos.Wasm Relay) emite
> por **stdout** a través del sink de consola de Serilog.
>
> **Fuentes de verdad:**
> - `Source/Common/Providers/SmartFran.Cloud.Provider.Logger.Core/SerilogBootstrap.cs`
> - `Source/Common/Providers/SmartFran.Cloud.Provider.Logging.AspNetCore/Middleware/EnrichmentMiddleware.cs`
> - `Source/Common/Providers/SmartFran.Cloud.Provider.Logging.Abstractions/Envelope/LogEnvelope.cs`
> - `Source/Common/Providers/SmartFran.Cloud.Provider.Logging.Abstractions/Logging/SmartFranLogExtensions.cs`
> - Memory `logenvelope-contract.md`, `logging-standard.md`, `logging-architecture-eventhub-scope.md`.
>
> **Estado actual:** este doc describe el JSON efectivamente emitido hoy por el
> pipeline en ejecución: `Serilog.Sinks.Console` con `Serilog.Formatting.Json.JsonFormatter`
> por default (claves `Timestamp / Level / MessageTemplate / Exception / Properties`,
> `Exception` como string plano).
>
> **Corrección 2026-08-19 (GITIN-1892):** §3.3/§3.6/§6.3/§6.4/§6.6/§6.7/§9
> tenían nombres de clave incorrectos para 5 propiedades del scope de los
> helpers (`ErrorCode`/`Recovered`/`Handled`/`AuditAction`/`AuditOutcome`
> documentados como PascalCase; el código real en `SmartFranLogExtensions.cs`
> usa `_error_code`/`_recovered`/`_handled`/`_audit_action`/`_audit_outcome`
> con prefijo `_`). Corregido tras validar directamente contra el código
> fuente — ver detalle en cada sección afectada y en
> `cloud/events/20260819_promote-remaining-clef-fields/`.

---

## 1. Pipeline resumido

```
┌─────────────────────────┐    ┌────────────────────┐    ┌──────────────────┐    ┌────────────┐
│ ILogger<T>.LogX(...)    │ →  │ Serilog pipeline   │ ──→│ Console (stdout) │ ──→│ AppService │
│ (6 helpers estándar)    │    │ (enrichers, scope) │    │ JSON línea       │    │ ConsoleLogs│
└─────────────────────────┘    └────────────────────┘    └──────────────────┘    └─────┬──────┘
                                       │                                            │ Azure Event Hub
                                       ▼                                            ▼
                              ┌──────────────────────┐                       ┌─────────────────────┐
                              │ (mismo template,     │ opt-in (claves        │ Consumer (Azure Func)│ → Graylog
                              │  JsonFormatter)      │ Serilog:Sinks:
                              │                      │ AzureEventHub:*
                              └──────────────────────┘ ConnectionString +
                                                       EventHubName)
```

- **Sink 5a siempre activo**: `Serilog.Sinks.Console`. Serializa con
  `Serilog.Formatting.Json.JsonFormatter` (default).
- **Sink 5b opt-in**: `Serilog.Sinks.AzureEventHub` directo. Se activa **solo
  si** están las dos claves `Serilog:Sinks:AzureEventHub:ConnectionString` y
  `:EventHubName` en appsettings / App Configuration. Caso de uso: Windows
  container de Sales.API, donde stdout no es capturado por AppService
  ConsoleLogs → Diagnostic Settings no llega al EventHub, entonces el sink
  emite directo al mismo namespace/EventHub para mantener el contrato
  `LogEnvelope` → consumer → Graylog. En Linux App Service queda OFF.
- **Igualdad de formato entre sinks**: ambos usan **el mismo** template, por
  lo que el JSON emitido es **byte-equivalente**. El consumer no distingue
  origen.
- Cada línea de stdout es **un único objeto JSON** (no NDJSON multi-objeto).

---

## 2. Formato real emitido hoy

Cada línea tiene exactamente estas 5 claves top-level, **en este orden**:

| Clave             | Tipo             | Origen                              | Ejemplo                                    |
|-------------------|------------------|-------------------------------------|--------------------------------------------|
| `Timestamp`       | `DateTimeOffset` (ISO 8601) | `LogEvent.Timestamp`                | `"2026-08-14T13:05:10.6272627-03:00"`      |
| `Level`           | `string`         | `LogEventLevel` → texto             | `"Information"`, `"Warning"`, `"Error"`    |
| `MessageTemplate` | `string`         | `LogEvent.MessageTemplate` (con `{}` nombrados sin reemplazar)| `"Closed sale {SaleId} for shift {ShiftId}"` |
| `Exception`       | `string?`        | concatenación de tipo + mensaje + stack | `null` o `"SpecsBusiness.ApiException: ..."` |
| `Properties`      | `object`         | `LogEvent.Properties` aplanado      | `{"SaleId":"abc-123", "Service":"Sales", ...}` |

Notas operativas:

- **No hay `SchemaVersion`** hoy.
- **`MessageTemplate` no se renderiza** — los `{}` se mantienen literalmente.
  El render queda del lado del consumer (con `Serilog.Formatting.Display` /
  MessageTemplateParser) cuando quiere el texto final.
- **`Exception` es un string plano** con el formato tradicional de .NET:
  `<Tipo>: <Mensaje>` + stack con `at ...` líneas separadas por `\r\n`. No es
  un objeto estructurado, lo cual es exactamente el formato por defecto de
  `Serilog.Formatting.Json.JsonFormatter`.
- El `Timestamp` se serializa con **offset horario** de la máquina (no UTC
  puro). En servidores BUE se ve `-03:00`.

---

## 3. `Properties` (el sub-objeto que más mira el consumer)

`Properties` es un diccionario plano `string → object?` que sale tal cual se
armó en el LogEvent. Hay **cuatro orígenes** que se fusionan (later-wins).

### 3.1 Enrichers a nivel proceso (`SerilogBootstrap.ApplyProcessEnrichers`)

Añadidos por `.Enrich.WithProperty(...)` al construir el logger. Están
presentes **en todo log del proceso** — incluso los emitidos fuera del
request HTTP (e.g. logs de arranque, eventos de Kestrel Hosting).

| Clave          | Origen                                                  | Valor típico                              |
|----------------|---------------------------------------------------------|-------------------------------------------|
| `Service`      | parámetro `serviceName` de `SerilogBootstrap.Configure`  | `"Sales"`, `"SmartFran.Cloud.Catalog.API"`|
| `Environment`  | env-var `ASPNETCORE_ENVIRONMENT` (default `"Production"`)| `"Production"`, `"Development"`           |
| `Version`      | `Assembly.GetName().Version` (`typename of SerilogBootstrap`) | `"1.0.0.0"`                         |

> Convención **PascalCase** del codebase C# (sin prefijo `_` GELF). El
> `EnrichmentMiddleware` los **sobreescribe por request** con los mismos
> nombres resueltos en runtime **más** las claves `TraceKey`, `TenantId`,
> `UserId`, `ProcessType`, `Component` (ver §3.2).

### 3.2 Scope del `EnrichmentMiddleware` (sobreescribe por request HTTP)

`Provider.Logging.AspNetCore/Middleware/EnrichmentMiddleware.cs` arma un
`ILogger.BeginScope` con este diccionario, que está activo durante toda la
ejecución del request:

> **Verificado 2026-08-19 (GITIN-1892):** esta sección coincide exactamente
> con el código real (`EnrichmentMiddleware.cs`, confirmado en `dev` y en
> `main`) — a diferencia de §3.3, acá no hubo que corregir nada. Los 8
> llamados a `UseSmartFranLogEnrichment` (Business/Catalog/Orders/Person/
> Platform/Sales/Security/Client.Web) pasan el nombre real de dominio de
> negocio como `component` (ej. `component: "Business"`), igual que el
> ejemplo de la fila `Component` de abajo.
>
> Dato sin resolver, no una corrección de este doc: muestras reales de
> tráfico tomadas el mismo día (ver GITIN-1892, hallazgo H2) mostraron
> `Component: "Api"` (5/6 servicios) o `Component: "Web"` (Admin) en vez del
> nombre de dominio esperado. El commit que introdujo `component: "<dominio>"`
> es de 2026-08-05 (`311862afb7`, GSFC-LOG-1) — reciente, lo que sugiere que
> el binario corriendo en producción podría ser anterior a ese cambio, pero
> **no se confirmó** eso como causa (el middleware legacy que reemplaza,
> `TracingMiddleware`, tampoco setea `Component` en el código que sí se
> pudo inspeccionar — no explica el valor observado). Queda para que Dev
> confirme qué versión/build está efectivamente desplegada.

| Clave          | Origen                                                                  | Valor típico                                |
|----------------|-------------------------------------------------------------------------|---------------------------------------------|
| `Service`      | `env.ApplicationName` / parámetro explícito                            | `"SmartFran.Cloud.Sales.API"`               |
| `Environment`  | `ASPNETCORE_ENVIRONMENT` (default `"Production"`)                       | `"Production"`                              |
| `Version`      | `AssemblyInformationalVersionAttribute` del entry-asm                   | `"1.0.0.0"`                                 |
| `TraceKey`     | header HTTP `TraceKey` del caller **o** W3C `Activity.TraceId`          | `"SFCADMWEB.POS:6.2026-08-14T16:05:09..."`  |
| `TenantId`     | header `TenantId` **o** `HttpContext.Items["tenantId"]` (TenantHandlingMiddleware) | `"d3186bc6d7b2"`                  |
| `UserId`       | claim `sub` de Auth0 **o** `NameIdentifier`                             | `"auth0|sale-007"`                          |
| `ProcessType`  | parámetro `processType` en `UseSmartFranLogEnrichment` (default `"Api"`)| `"Api"` (Client.Web usa `"Web"`)            |
| `Component`    | parámetro `component` (módulo de negocio: `Sales`, `Catalog`, ...)      | `"Sales"`                                   |

> Los logs de `Microsoft.AspNetCore.Hosting.Diagnostics` se emiten **fuera
> del scope del middleware** (vienen del `HostingApplicationDiagnostics`
> que dispara eventos de Kestrel) ⇒ **no traen** `TraceKey / TenantId /
> UserId / ProcessType / Component`. Sí traen los enrichers de proceso
> §3.1 (`Service / Environment / Version`).

### 3.3 Scopes (`BeginScope`) puestos por los helpers

Cada helper de `SmartFranLogExtensions` abre un scope ambient que añade
**al menos** `Category`. Algunos añaden más.

> **Corrección 2026-08-19 (GITIN-1892):** la afirmación previa de esta
> sección ("todo en PascalCase, sin prefijo `_`") es **falsa** para 5 de
> estas claves — verificado leyendo `SmartFranLogExtensions.cs` directamente
> (`cloud/repo/SmartFran.Cloud`, rama `dev`). El código real agrega
> `_error_code`/`_operation`/`_attempt`/`_recovered`/`_handled`/
> `_audit_action`/`_audit_outcome` al diccionario de `BeginScope` — con
> prefijo `_`, pese a que §3.6 (más abajo) documenta la convención opuesta.
> Es una inconsistencia real del propio código, no un error de este doc que
> se esté corrigiendo — GITIN-1892 promovió estos campos a Graylog leyendo
> primero los nombres PascalCase equivocados (según la versión anterior de
> esta tabla), lo cual no producía ningún dato porque esas claves
> simplemente no existen en el `Properties` real.

| Helper                          | Claves de scope (`BeginScope`, nombre real en código)         | Claves adicionales vía placeholder de mensaje |
|----------------------------------|-----------------------------------------------------------------|------------------------------------------------|
| `LogBusinessEvent`              | `Category = "Business"`                                        | —                                                |
| `LogSystemEvent`                | `Category = "System"`                                          | —                                                |
| `LogDomainError`                | `Category = "Error"`, `_error_code = code`                     | — (`message` es libre, `code` no se referencia como placeholder) |
| `LogTransientFailure`           | `Category = "Error"`, `_operation = op`, `_attempt = N`, `_recovered = bool` | `Operation`, `Attempt` (placeholders `{Operation}`/`{Attempt}`, ambas líneas) — `_recovered` no tiene equivalente PascalCase, solo existe con prefijo `_` |
| `LogUnrecoverableFailure`       | `Category = "Error"`, `_operation = op`, `_handled = false`    | `Operation` (placeholder `{Operation}`, ambas líneas) — `_handled` no tiene equivalente PascalCase |
| `LogSecurityAudit`              | `Category = "Security"`, `_audit_action = ...`, `_audit_outcome = ...` | `Action`, `Outcome` (placeholders `{Action}`/`{Outcome}`, ambas líneas — valor del enum, ej. `"Login"`/`"Success"`) — **no existen** `AuditAction`/`AuditOutcome` como tales en `Properties`, solo `_audit_action`/`_audit_outcome` (scope) y `Action`/`Outcome` (placeholder) |

`Operation` y `Category` son las únicas dos claves de esta sección que
coinciden exactamente con lo que un consumer esperaría en PascalCase sin
prefijo. Las otras 5 requieren leer la clave con `_` desde `Properties`.

### 3.4 Propiedades del call site (las que vos pasás)

Cada helper recibe `params (string Key, object? Value)[] properties`. Esas
tuplas se:

1. Filtran por `LogRedactor.RedactProperties` (ver §4).
2. Se inyectan en el mensaje con el operador `@` (`@Properties`), lo que le
   dice a Serilog que **destructure** el dict y aplanen sus claves dentro
   de `Properties`.

> En `LogTransientFailure`, `LogUnrecoverableFailure` y `LogSecurityAudit`
> el helper emite **dos líneas** con el mismo scope: la primera con la
> excepción o el outcome, la segunda con el payload estructurado
> (`{Operation} {@Properties}` o `{Action} {Outcome} {@Properties}`).

### 3.5 Claves "automáticas" de Hosting / MEL (siempre que apliquen)

Cuando el log proviene de un evento del framework (no de un controller),
`Serilog.Extensions.Logging` añade estas propiedades automáticamente:

| Clave                       | Origen                                                  | Aparece en                            |
|-----------------------------|---------------------------------------------------------|---------------------------------------|
| `SourceContext`             | `ILogger<T>` ⇒ nombre del `T`                          | todo log del framework                |
| `ActionId`                  | `IHttpContextAccessor` + DI de ASP.NET Core             | Controllers (mvc)                     |
| `ActionName`                | nombre del método del controller                        | Controllers (mvc)                     |
| `RequestId`                 | `HttpContext.TraceIdentifier`                           | cualquier log dentro del pipeline HTTP|
| `RequestPath`               | ruta del request (`/api/v1/Sale/Cancel`)                | cualquier log dentro del pipeline HTTP|
| `ConnectionId`              | id de conexión de Kestrel                               | cualquier log dentro del pipeline HTTP|
| `HostingRequestFinishedLog` | mensaje canónico de `HostingApplicationDiagnostics`     | sólo al finalizar el request         |
| `ElapsedMilliseconds`       | duración del request (ms)                               | sólo al finalizar el request         |
| `StatusCode`                | código de respuesta                                     | sólo al finalizar el request         |
| `ContentType`               | content-type de la respuesta                            | sólo al finalizar el request         |
| `Protocol`, `Scheme`, `Host`, `Method` | info del request                                 | sólo al finalizar el request         |

> Estas claves viven en el **mismo** `Properties` que las claves canónicas
> (3.1–3.4). El consumer las ignora salvo que las necesite (e.g.
> correlacionar logs por `RequestId`).

### 3.6 Convención de nombres (regla pretendida, con una inconsistencia real conocida)

**La intención** es que toda propiedad se emita en PascalCase, sin prefijo
`_` ni separadores. Eso es cierto para:

- `Service`, `Environment`, `Version`, `TraceKey`, `TenantId`, `UserId`,
  `ProcessType`, `Component` — los canónicos (§3.1/§3.2).
- `Category`, `Operation` — del scope de los helpers (§3.3). Correctos en
  PascalCase.
- `SourceContext`, `ActionId`, `ActionName`, `RequestId`, `RequestPath`,
  `ConnectionId` — los automáticos del framework (§3.5).

**No es cierto**, verificado contra `SmartFranLogExtensions.cs` (GITIN-1892,
2026-08-19), para 5 claves del scope de los helpers: `_error_code`,
`_attempt`, `_recovered`, `_handled`, `_audit_action`, `_audit_outcome`
existen **con prefijo `_`** en el código real, no como `ErrorCode`/
`Attempt`/`Recovered`/`Handled`/`AuditAction`/`AuditOutcome`. Es una
inconsistencia real dentro del propio código de `SmartFranLogExtensions.cs`
respecto a la convención que el resto del archivo sí sigue — no algo que
dependa de este doc. Cualquier consumer, pipeline, o código nuevo que
necesite leer estas 5 claves debe usar el nombre real con `_`, no el
PascalCase que esta sección documentaba antes.

Si en algún momento aparece una clave nueva para un helper, la intención
sigue siendo PascalCase (e.g. `RetryCount`, no `_retry_count`) — pero
verificar contra el código real antes de asumirlo, dado el precedente de
esta sección.

---

## 4. Redacción de PII

Antes de emitirse, **toda propiedad** pasa por `LogRedactor.RedactProperties`:

1. **Por nombre de clave** (`SensitiveKeyRegex`, case-insensitive):
   `email, password, passwd, token, secret, cvv, pan, dni, cuit,
   authorization, apikey, api_key, pin, cardnumber, card, creditcard,
   credit_card, tarjeta, tarjetanumero` → valor reemplazado por `***`.

2. **Por tipo** (`[NotLoggedAttribute]`): si la propiedad o algún campo público
   del tipo está marcado con `[NotLogged]`, todo el valor se redacta.

3. **Por forma (shape-based)**:
   - Número de tarjeta (13–19 dígitos, opcionalmente separado por espacio/guión).
   - Email (`user@domain.tld`).

La máscara es siempre la cadena literal `***`.

---

## 5. Excepciones (`Exception`)

Hoy es un **string plano** con la concatenación tradicional .NET:

```
SpecsBusiness.ApiException: The HTTP status code of the response was not expected (403).

Status: 403
Response: 

   at SpecsBusiness.BusinessV1.StockOffsetMovementAsync(String tenantId, StockOffsetCmd body, CancellationToken cancellationToken) in D:\a\SmartFran.Cloud\SmartFran.Cloud\Source\Services\Sales\SmartFran.Cloud.Sales.Application\obj\businessv1Client.cs:line 21137
   at SmartFran.Cloud.Sales.Application.Services.SaleService.CancelAsync(SaleCancelCmd saleCancelCmd) in D:\a\SmartFran.Cloud\SmartFran.Cloud\Source\Services\Sales\SmartFran.Cloud.Sales.Application\Services\SaleService.cs:line 424
```

Reglas de la app:

- La excepción **siempre** se pasa como **primer argumento** del método
  (`LogError(ex, "template", args)`), nunca como string.
- Nunca se sustituye `ex` por `ex.Message` en el template.
- Si no hay excepción, `Exception` es `null` (no se omite la clave — la
  posición es fija para que el parser no se rompa).

---

## 6. Ejemplos completos por helper

> Los ejemplos están **formateados con indentación** solo para legibilidad.
> En stdout / EventHub la línea viene **compacta** (sin saltos, sin espacios
> extra entre claves), terminada en `\n`.
>
> **Premisa común a 6.1–6.4 y 6.6:** el log se emite desde un controller de
> `SmartFran.Cloud.Sales.API` durante un request HTTP. Por eso `Properties`
> ya trae el scope del `EnrichmentMiddleware` (§3.2): `Service`,
> `Environment`, `Version`, `TraceKey`, `TenantId`, `UserId`, `ProcessType`,
> `Component`. Los logs de `Microsoft.AspNetCore.Hosting.Diagnostics`
> (ejemplo 6.5) **no** traen ese scope (ver §3.2 nota).

### 6.1 `LogBusinessEvent`

```csharp
logger.LogBusinessEvent("SaleClosed",
    ("SaleId", saleId),
    ("ShiftId", shiftId),
    ("Total",   total));
```

```json
{
  "Timestamp": "2026-08-14T13:05:10.6272627-03:00",
  "Level": "Information",
  "MessageTemplate": "SaleClosed {@Properties}",
  "Exception": null,
  "Properties": {
    "SaleId": "9f3a...",
    "ShiftId": "shift-7",
    "Total": 1234.56,

    "Service": "SmartFran.Cloud.Sales.API",
    "Environment": "Production",
    "Version": "1.0.0.0",
    "TraceKey": "SFCADMWEB.POS:6.2026-08-14T13:05:09.4490000-03:00",
    "TenantId": "d3186bc6d7b2",
    "UserId": "auth0|sale-007",
    "ProcessType": "Api",
    "Component": "Sales",
    "Category": "Business",

    "SourceContext": "SmartFran.Cloud.Sales.Application.Services.SaleService",
    "ActionId": "0093d63d-0e22-4ef6-9816-dc21c30ffa6d",
    "ActionName": "SmartFran.Cloud.Sales.API.Controllers.v1.SaleController.CancelAsync (SmartFran.Cloud.Sales.API)",
    "RequestId": "400076ec-0000-a400-b63f-84710c7967bb",
    "RequestPath": "/api/v1/Sale/Cancel"
  }
}
```

### 6.2 `LogSystemEvent`

```csharp
logger.LogSystemEvent("AppStarted",
    ("BuildId", buildId),
    ("Region",  region));
```

> Sale **sin** el scope del middleware (log emitido antes / fuera del
> pipeline HTTP). Sólo aparecen los enrichers de proceso (§3.1) y el scope
> del helper (§3.3).

```json
{
  "Timestamp": "2026-08-14T08:23:00.0000000-03:00",
  "Level": "Information",
  "MessageTemplate": "AppStarted {@Properties}",
  "Exception": null,
  "Properties": {
    "BuildId": "abc-1",
    "Region": "AR",

    "Service": "SmartFran.Cloud.Sales.API",
    "Environment": "Production",
    "Version": "1.0.0.0",
    "Category": "System"
  }
}
```

### 6.3 `LogDomainError`

```csharp
logger.LogDomainError(ex,
    "PAYMENT_PROVIDER_FAILED",
    "Sale {SaleId} failed at payment step",
    ("SaleId",   saleId),
    ("Provider", "MercadoPago"));
```

```json
{
  "Timestamp": "2026-08-14T13:05:10.6272627-03:00",
  "Level": "Error",
  "MessageTemplate": "Sale {SaleId} failed at payment step",
  "Exception": "SmartFran.Cloud.Payments.ProviderTimeoutException: Provider MercadoPago did not respond in 30s.\r\n   at SmartFran.Cloud.Payments.MercadoPago.ChargeAsync(...)",
  "Properties": {
    "SaleId": "9f3a...",
    "Provider": "MercadoPago",
    "Message": "Sale 9f3a... failed at payment step",

    "Service": "SmartFran.Cloud.Sales.API",
    "Environment": "Production",
    "Version": "1.0.0.0",
    "TraceKey": "SFCADMWEB.POS:6.2026-08-14T13:05:09.4490000-03:00",
    "TenantId": "d3186bc6d7b2",
    "UserId": "auth0|sale-007",
    "ProcessType": "Api",
    "Component": "Sales",
    "Category": "Error",
    "_error_code": "PAYMENT_PROVIDER_FAILED",

    "SourceContext": "SmartFran.Cloud.Sales.Infrastructure.Repositories.Domain.Entities.Sale",
    "ActionId": "0093d63d-0e22-4ef6-9816-dc21c30ffa6d",
    "ActionName": "SmartFran.Cloud.Sales.API.Controllers.v1.SaleController.CancelAsync (SmartFran.Cloud.Sales.API)",
    "RequestId": "400076ec-0000-a400-b63f-84710c7967bb",
    "RequestPath": "/api/v1/Sale/Cancel"
  }
}
```

### 6.4 `LogTransientFailure` (con `recovered = true`)

```csharp
logger.LogTransientFailure(ex,
    op:        "SyncCatalog",
    recovered: true,
    attempt:   3,
    ("Vendor", "ACME"));
```

Emite **dos líneas** con el mismo scope (mismo `Category = "Error"`).

**Línea 1** (con la excepción; `recovered = true` ⇒ `Warning`):

```json
{
  "Timestamp": "2026-08-14T13:05:11.0000000-03:00",
  "Level": "Warning",
  "MessageTemplate": "Transient failure recovered on {Operation} (attempt {Attempt}): {Message}",
  "Exception": "SmartFran.Cloud.Catalog.TransientHttpException: ACME returned 503\r\n   at SmartFran.Cloud.Catalog.Sync.SyncCatalog(...)",
  "Properties": {
    "Operation": "SyncCatalog",
    "Attempt": 3,
    "Message": "ACME returned 503",
    "Vendor": "ACME",

    "Service": "SmartFran.Cloud.Sales.API",
    "Environment": "Production",
    "Version": "1.0.0.0",
    "TraceKey": "SFCADMWEB.POS:6.2026-08-14T13:05:09.4490000-03:00",
    "TenantId": "d3186bc6d7b2",
    "UserId": "auth0|sale-007",
    "ProcessType": "Api",
    "Component": "Sales",
    "Category": "Error",
    "_recovered": true,

    "SourceContext": "SmartFran.Cloud.Catalog.Sync.SyncCatalogService",
    "RequestId": "400076ec-0000-a400-b63f-84710c7967bb",
    "RequestPath": "/api/v1/Sale/Cancel"
  }
}
```

**Línea 2** (payload estructurado; siempre `Information`, `Exception: null`):

```json
{
  "Timestamp": "2026-08-14T13:05:11.0500000-03:00",
  "Level": "Information",
  "MessageTemplate": "{Operation} {@Properties}",
  "Exception": null,
  "Properties": {
    "Operation": "SyncCatalog",
    "Properties": {
      "Vendor": "ACME"
    },

    "Service": "SmartFran.Cloud.Sales.API",
    "Environment": "Production",
    "Version": "1.0.0.0",
    "TraceKey": "SFCADMWEB.POS:6.2026-08-14T13:05:09.4490000-03:00",
    "TenantId": "d3186bc6d7b2",
    "UserId": "auth0|sale-007",
    "ProcessType": "Api",
    "Component": "Sales",
    "Category": "Error",
    "_recovered": true,

    "SourceContext": "SmartFran.Cloud.Catalog.Sync.SyncCatalogService",
    "RequestId": "400076ec-0000-a400-b63f-84710c7967bb",
    "RequestPath": "/api/v1/Sale/Cancel"
  }
}
```

> Si `recovered = false`, la primera línea baja a `"Level": "Error"` y el
> `MessageTemplate` cambia a:
> `"Transient failure on {Operation} (attempt {Attempt}) not recovered: {Message}"`.
> La segunda línea es idéntica.

### 6.5 Logs de `Microsoft.AspNetCore.Hosting.Diagnostics` (Kestrel)

Estos vienen del `HostingApplicationDiagnostics`, **no del controller**:
no llevan `TraceKey / TenantId / UserId / ProcessType / Component /
Category`, pero sí los enrichers de proceso y los campos automáticos de
ASP.NET Core.

```json
{
  "Timestamp": "2026-08-14T13:33:00.0907884-03:00",
  "Level": "Information",
  "MessageTemplate": "Request finished HTTP/1.1 GET http://localhost:5888/swagger/v1/swagger.json - - - 200 - application/json;charset=utf-8 89.5196ms",
  "Exception": null,
  "Properties": {
    "ElapsedMilliseconds": 89.5196,
    "StatusCode": 200,
    "ContentType": "application/json;charset=utf-8",
    "ContentLength": null,
    "Protocol": "HTTP/1.1",
    "Method": "GET",
    "Scheme": "http",
    "Host": "localhost:5888",
    "PathBase": "",
    "Path": "/swagger/v1/swagger.json",
    "QueryString": "",
    "HostingRequestFinishedLog": "Request finished HTTP/1.1 GET http://localhost:5888/swagger/v1/swagger.json - - - 200 - application/json;charset=utf-8 89.5196ms",
    "EventId": { "Id": 2 },
    "SourceContext": "Microsoft.AspNetCore.Hosting.Diagnostics",
    "RequestId": "0HNNQ46OA67C8:00000002",
    "RequestPath": "/swagger/v1/swagger.json",
    "ConnectionId": "0HNNQ46OA67C8",
    "Service": "SmartFran.Cloud.Catalog.API",
    "Environment": "Development",
    "Version": "1.0.0.0"
  }
}
```

### 6.6 `LogUnrecoverableFailure`

```csharp
logger.LogUnrecoverableFailure(ex,
    "ReconcileAccount",
    ("Account", "ACC-0001"));
```

Dos líneas con `Category = "Error"`. La primera con la excepción
(`"Level": "Error"`, `MessageTemplate` = `"Unrecoverable failure on {Operation}: {Message}"`),
la segunda con `"Level": "Information"`, `MessageTemplate` =
`"{Operation} {@Properties}"`, `Exception: null`. Comparten el scope del
controller más `Category = "Error"`, `_handled = false` (no `Handled` —
ver §3.3/§3.6), `Account = "ACC-0001"`. `Operation` sí aparece en
PascalCase, vía el placeholder `{Operation}` de ambas líneas.

### 6.7 `LogSecurityAudit`

```csharp
logger.LogSecurityAudit(
    action:  SecurityAuditAction.Login,
    outcome: SecurityAuditOutcome.Success,
    ("UserId",   userId),
    ("ClientIp", ip));
```

Dos líneas con `Category = "Security"`:

- **Línea 1**: `"MessageTemplate"` =
  `"Security audit: {Action} succeeded"` (`Failure` / `Blocked` ⇒
  `"... failed"` / `"... blocked"`, en `Warning`).
- **Línea 2**: `"Level": "Information"`,
  `"MessageTemplate" = "{Action} {Outcome} {@Properties}"`.

Comparten: scope HTTP, `Category = "Security"`, `_audit_action = "Login"`,
`_audit_outcome = "Success"` (o `Failure`/`Blocked`) — no `AuditAction`/
`AuditOutcome`, ver §3.3/§3.6. Los placeholders `{Action}`/`{Outcome}` de
ambas líneas sí producen `Action = "Login"`/`Outcome = "Success"` en
PascalCase (nombres genéricos, no confundir con `AuditAction`/
`AuditOutcome`, que no existen). Más las props del call site (`ClientIp`, etc.).

---

## 7. Anti-patrones en lo que **no** debe imprimirse

Ninguna de estas líneas debe aparecer en stdout / EventHub:

- `LogInformation($"Closed sale {saleId}")` → mensaje plano, no estructurado.
- `LogError("Failed: " + ex.Message)` → pierde stack trace, mensaje en lenguaje natural.
- `Console.WriteLine("Something happened")` → no va por el pipeline, no se
  redacta, no se enruta a Graylog.
- `logger.LogInformation(ex.Message)` → cambia el primer argumento, no se
  adjunta la `Exception`.
- Headers `Authorization`, `Cookie`, `X-API-Key` en cualquier propiedad.
- PAN / email / DNI / CUIT en cualquier propiedad (deben pasar por el redactor
  y llegar como `"***"` al log).

Si una llamada a `ILogger` no encaja en los 6 helpers, **no** se agregan
helpers ad-hoc por servicio — se evalúa ampliar el conjunto.

---

## 8. Activación del sink AzureEventHub (opt-in, app settings)

Hosts que **no** pueden capturar stdout por AppService ConsoleLogs (caso
típico: Windows container de `Sales.API`) agregan estas dos claves a
`appsettings.{Env}.json` / App Configuration:

```jsonc
"Serilog": {
  "Sinks": {
    "AzureEventHub": {
      "ConnectionString": "Endpoint=sb://...;SharedAccessKeyName=...;SharedAccessKey=...",
      "EventHubName":     "smartfran-cloud-logs"
    }
  }
}
```

Con ambas claves presentes, el constructor configura el segundo sink con el
**mismo** template, por lo que el contrato es byte-equivalente al del Console
y el consumer recibe el envelope sin distinguir origen.

> � En Linux App Service (caso normal), **dejar las dos claves vacías**;
> el sink opt-in queda OFF y solo se usa Console + Diagnostic Settings →
> EventHub.

---

## 9. Cómo lo lee el consumer (hoy)

```csharp
// Hoy el consumer del EventHub parsea cada línea con Serilog .NET directamente
// (no usa LogEnvelope.Parse en runtime, porque el top-level es
// Timestamp/Level/MessageTemplate/Exception/Properties, no @t/@l/@m/@x/@p).
// Pero el consumer Graylog indexa los campos de Properties, así que las búsquedas
// son por nombre canónico — PascalCase sin prefijo "_" para la mayoría,
// salvo 5 claves del scope de los helpers que existen con prefijo "_" en el
// código real (corrección 2026-08-19, GITIN-1892 — ver §3.3/§3.6). Lista
// completa (corrección 2026-08-19, GITIN-1892): faltaba "Version" — el
// mismo campo que nunca se había promovido a nivel superior en Graylog
// hasta ese ticket (ver graylog-log-fields.md H10) — y las 3 claves que
// llegan vía placeholder de mensaje junto a sus pares de scope (§3.3):

// --- Enrichers de proceso (§3.1) ---
log.Properties["Service"];        // "SmartFran.Cloud.Sales.API"
log.Properties["Environment"];    // "Production"
log.Properties["Version"];        // "1.0.0.0" — faltaba en esta lista hasta 2026-08-19

// --- Scope del EnrichmentMiddleware (§3.2) ---
log.Properties["TenantId"];       // "d3186bc6d7b2"
log.Properties["UserId"];         // "auth0|..." — vacío en casi toda muestra real vista hasta ahora
log.Properties["TraceKey"];       // header HTTP TraceKey o W3C TraceId
log.Properties["Component"];      // "Sales", "Catalog", ... según el código — valores reales observados (Api/Web) no coinciden, ver §3.2
log.Properties["ProcessType"];    // "Api" / "Web"

// --- Scope de los helpers (§3.3) — Category y Operation en PascalCase correcto ---
log.Properties["Category"];       // "Business" / "System" / "Error" / "Security"
log.Properties["Operation"];      // "SyncCatalog", "ReconcileAccount", etc. — PascalCase correcto (placeholder de mensaje)
log.Properties["Attempt"];        // int (LogTransientFailure) — PascalCase correcto (placeholder de mensaje), sin equivalente promovido a nivel superior en Graylog aún
log.Properties["Action"];         // "Login", etc. (LogSecurityAudit) — PascalCase correcto (placeholder de mensaje), nombre genérico, no confundir con _audit_action
log.Properties["Outcome"];        // "Success" / "Failure" / "Blocked" (LogSecurityAudit) — ídem, no confundir con _audit_outcome

// --- Scope de los helpers (§3.3) — con prefijo "_", NO el nombre PascalCase esperado ---
log.Properties["_error_code"];    // "PAYMENT_PROVIDER_FAILED", etc. — NO "ErrorCode"
log.Properties["_recovered"];     // bool (LogTransientFailure) — NO "Recovered"
log.Properties["_handled"];       // bool (LogUnrecoverableFailure) — NO "Handled"
log.Properties["_audit_action"];  // "Login", "TokenRefresh", ... — NO "AuditAction"
log.Properties["_audit_outcome"]; // "Success" / "Failure" / "Blocked" — NO "AuditOutcome"

// --- Automáticas de Hosting/MEL (§3.5) — solo las dos más consultadas, ver §3.5 para el resto ---
log.Properties["RequestId"];      // ASP.NET Core TraceIdentifier
log.Properties["SourceContext"];  // nombre del ILogger<T> — presencia varía según el call site, ver §3.5

log.Exception;                   // string plano (no objeto)
```

---

## 10. Convenciones operativas

- **Todo es PascalCase**, sin prefijo `_`. Si aparece una propiedad nueva,
  va en PascalCase (ver §3.6).
- **No modificar el nombre de una propiedad canónica** (`TenantId`,
  `TraceKey`, `ProcessType`, `Component`) sin bumpear `SchemaVersion` y
  coordinar con el consumer.

---

## 11. Cómo se aplana `Properties` (destructuring)

El template de Serilog usa `@Properties` con el operador `@`, que
**destructure** el `Dictionary<string, object?>` y vuelca cada par como una
clave plana dentro del `LogEvent.Properties`. Luego el `JsonFormatter`
subre ese diccionario como sub-objeto `Properties` en el output JSON.

En la práctica, lo que ve el consumer es (caso HTTP, fusionado §3.1 + §3.2 +
§3.3 + §3.4 + §3.5):

```jsonc
"Properties": {
  // Payload del call site (§3.4)
  "SaleId":  "9f3a...",
  "ShiftId": "shift-7",
  "Total":   1234.56,

  // Scope del helper de extensión (§3.3)
  "Category": "Business",
  "EventName":"SaleClosed",     // Serilog lo agrega como {EventName} en el template

  // Enrichers de proceso (§3.1) + scope del middleware (§3.2)
  "Service":     "SmartFran.Cloud.Sales.API",
  "Environment": "Production",
  "Version":     "1.0.0.0",
  "TraceKey":    "SFCADMWEB.POS:...",
  "TenantId":    "d3186bc6d7b2",
  "UserId":      "auth0|sale-007",
  "ProcessType": "Api",
  "Component":   "Sales",

  // Plumbing automático del framework (§3.5)
  "SourceContext": "SmartFran.Cloud.Sales.Application.Services.SaleService",
  "ActionId":      "0093d63d-0e22-4ef6-9816-dc21c30ffa6d",
  "ActionName":    "SmartFran.Cloud.Sales.API.Controllers.v1.SaleController.CancelAsync (...)",
  "RequestId":     "400076ec-0000-a400-b63f-84710c7967bb",
  "RequestPath":   "/api/v1/Sale/Cancel",
  "ConnectionId":  "0HNNQ46OA67C8"
}
```
# GITIN-1637 — [CLOUD] Análisis Health en las APIs (medición de SLA)

**Tags:** SmartFran Cloud, Azure, App Service, CosmosDB, Redis, SRE

## Resumen

Ninguna de las APIs de SmartFran Cloud exponía un endpoint de healthcheck con chequeos reales — existía una ruta (`api/v1/Status/Health`) pero no hacía nada más que responder `Ok`. Este ticket diseña e implementa un endpoint real, `api/v1/Status/healthcheck`, alcanzado primero a **Sales.API** antes de extenderlo al resto de los 8 App Services.

La arquitectura multi-tenant de SmartFran Cloud (una única instancia sirviendo a todas las franquicias) separa el diseño en dos capas independientes: si la instancia en sí está sobrecargada, afecta a todos los tenants por igual y escalar/sacarla de rotación tiene sentido; si Cosmos o Redis cae para un tenant puntual, escalar la instancia no resuelve nada — el impacto es por tenant. Por eso:

- **El código de estado HTTP** refleja solo la salud de la instancia (CPU%, RAM%, HTTP Queue) — es la señal que le sirve a un balanceador o a un autoscaler.
- **El body JSON** reporta esos mismos valores de instancia (`CPU`/`RAM`/`HTTP_QUEUE`/`GENERAL_STATUS`) más `REDIS` a nivel raíz (Redis es instance-wide, no por-tenant), y el estado de Cosmos por tenant — con 3 niveles (OK/WARN/PROBLEM) en todos los casos. Es la señal que le sirve a la herramienta de medición de SLA.

Un solo endpoint sirve ambas necesidades. Umbrales configurables vía variables de entorno del App Service, no hardcodeados.

Se incorporó además un requisito relacionado y genuinamente ligado al mismo mecanismo: shutdown prolijo por instancia, para que el propio endpoint de health señale al balanceador que una instancia está drenando en el instante en que arranca una parada planificada, no solo cuando el proceso ya terminó.

Diseño e implementación completos y validados (build + tests) en una rama local; despliegue real pendiente.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-1637](https://smartit-ar.atlassian.net/browse/GITIN-1637) |
| Sistema | SmartFran Cloud — Azure App Services (`SmartFran-Cloud-Sales-PRO` primero) |
| Severidad | Baja — "Nice to have" explícito en el ticket, trabajo proactivo |
| Alcance | Diseño e implementación completos para **Sales.API**; réplica a los otros 7 App Services pendiente |
| Consumidores previstos | Load balancer interno; proxy Zabbix en `sfcloud-monitoreo.smartfran.com` (**no implementado todavía**) |
| Responsable | Dante Paniagua |

## Causa raíz

No aplica — ticket proactivo, no hay incidente que lo origine. La brecha era la ausencia total de visibilidad de salud a nivel de proceso/dependencias para medir SLA, más allá de lo que Application Insights captura de forma pasiva.

## Hallazgos

| # | Hallazgo | Detalle |
|---|---|---|
| H1 | La ruta `api/v1/Status/Health` existe pero no hace nada útil | `StatusController.Health()` responde siempre `Ok("Its alive!")` — sin chequeo de CPU, RAM, Cosmos ni Redis. Ya es anónima y ya es ignorada por `TenantHandlingMiddleware`. Se mantiene sin tocar por retrocompatibilidad; el chequeo real vive en la nueva acción `HealthCheck()` (`api/v1/Status/healthcheck`), en el mismo controller |
| H2 | El patrón `Status`/`Health` (más `SimulateCpuLoad`/`SimulateMemoryLoad`) es una convención compartida entre servicios | Confirmado en los specs cacheados de Business/Catalog/Person/Platform — todos exponen `api/v1/Status/Health`. Mantener la nueva ruta bajo el mismo controller facilita reusar el patrón al extender esto a los otros 7 App Services |
| H3 | Un endpoint de health bajo `/api/*` queda bloqueado por auth si no se marca explícitamente anónimo | El pipeline de Sales.API aplica `UseAuthentication`/`UseAuthorization` antes de `UseTenantHandlingMiddleware` — un prober de infraestructura (LB, Zabbix) no manda JWT de Auth0, así que el endpoint se mapea con `[AllowAnonymous]` explícito |
| H4 | CosmosDB es genuinamente por-tenant en Sales — no hay "la" conexión Cosmos a chequear | Cada franquicia tiene su **propia cuenta CosmosDB dedicada** (`smartfran-cloud-cosmos-<tenantId>`); `CosmosClientPool` crea un `CosmosClient` distinto por tenant. El chequeo recorre todos los tenants onboarded (vía `ITenantConfigurationResolver.GetAllTenants()`) y reporta una respuesta por tenant, en paralelo — ver Diseño §3 |
| H5 | Sales.API no tiene ninguna dependencia de Redis | Sin `ProjectReference` al proveedor de Redis en ningún `.csproj` de Sales, sin `IConnectionMultiplexer` registrado en DI, sin conexión SQL activa tampoco (el único `AddDbContext` está comentado en `Program.cs`) — el único cache real es `AddMemoryCache()` (in-process) y la única base de datos real es Cosmos, ya cubierta por tenant. El bloque `REDIS` se mantiene en el body, a nivel raíz (no por tenant — Redis es instance-wide), reportando `N/A` para Sales — no un chequeo inventado ni un `OK` falso |
| H6 | CPU no es un valor instantáneo — requiere una ventana de muestreo | `Process.TotalProcessorTime` es un contador acumulado, no un porcentaje. Se muestrea en background cada 10s en vez de adentro del propio request, para no agregarle latencia a cada llamada |
| H7 | Falta shutdown prolijo por instancia — issue relacionado, incorporado a este ticket | Evidencia real: `cloud/events/20260913_pos-net-http-timeout/investigation.md` confirmó Event ID 1005 ("Failed to gracefully shutdown application") en Sales-PRO desde el 2026-09-12T23:15:26Z, escalando a recycles cada 10-90 min durante el 09-13 — kills forzados después de vencer la ventana de gracia (`shutdownTimeLimit`, default 10s). El endpoint de health es el mecanismo que el balanceador usa para saber que una instancia está drenando — ambos temas están genuinamente ligados. Ver Diseño §6 |
| H8 | El código de estado HTTP y el body del JSON responden preguntas distintas, para audiencias distintas | Ver Resumen — es el principio rector de todo el diseño |

## Diseño

### 1. Endpoint

**Ruta: `GET api/v1/Status/healthcheck`** — nueva acción en el `StatusController` existente, junto a `Health()` (H1), que se mantiene intacta por retrocompatibilidad. Al vivir bajo `api/v1/Status/*`, respeta la convención compartida con Business/Catalog/Person/Platform (H2) y ya queda cubierta por la exclusión de `TenantHandlingMiddleware` (cualquier path que contenga `"/health"`, sin necesidad de tocar esa clase — `"healthcheck"` la contiene).

```csharp
// StatusController.cs
[HttpGet("healthcheck", Name = "HealthCheck")]
[AllowAnonymous]
[ProducesResponseType(StatusCodes.Status200OK)]
[ProducesResponseType(StatusCodes.Status503ServiceUnavailable)]
public async Task<IActionResult> HealthCheck(
    [FromServices] InstanceHealthEvaluator instanceHealth,
    [FromServices] CosmosHealthCheck cosmosCheck,
    [FromServices] RedisHealthCheck redisCheck,
    [FromServices] ITenantConfigurationResolver tenantConfig,
    [FromServices] IOptionsMonitor<TenantSettings> tenantSettings)
{
    var instance = await instanceHealth.EvaluateAsync(); // CPU/RAM/HTTP Queue + GENERAL_STATUS — ver §2
    var redisResult = await redisCheck.CheckAsync(); // una sola vez, a nivel raíz — ver §4
    var organizations = tenantSettings.CurrentValue.Organizations;

    var body = new Dictionary<string, object>
    {
        ["CPU"] = instance.CpuPercent,
        ["RAM"] = instance.RamPercent,
        ["HTTP_QUEUE"] = instance.HttpQueueLength,
        ["GENERAL_STATUS"] = instance.GeneralStatus.ToString(),
        ["REDIS"] = new { STATUS = redisResult.Status.ToString(), RESPONSE_TIME = redisResult.LatencyMs }
    };

    foreach (var (tenantId, cosmosSettings) in tenantConfig.GetAllTenants())
    {
        var cosmosResult = await cosmosCheck.CheckAsync(tenantId, cosmosSettings);
        var tenantName = organizations.FirstOrDefault(o => o.tenantId == tenantId)?.name ?? tenantId;

        body[tenantName] = new
        {
            STATUS = cosmosResult.Status.ToString(),
            COSMOS = new { STATUS = cosmosResult.Status.ToString(), RESPONSE_TIME = cosmosResult.LatencyMs }
        };
    }

    return instance.IsHealthy ? Ok(body) : StatusCode(StatusCodes.Status503ServiceUnavailable, body);
}
```

Motor interno: `Microsoft.Extensions.Diagnostics.HealthChecks` no se usó como middleware nativo — la respuesta se arma a mano para lograr la forma exacta pedida (status HTTP de instancia + body por tenant). Ningún NuGet nuevo: todos los chequeos usan SDKs ya referenciados (`Microsoft.Azure.Cosmos`, `System.Diagnostics.Metrics`).

**Código de estado**: 503 Service Unavailable cuando la instancia no está sana (en vez de 400, que no aplica, o 500, que implica excepción no manejada) — es el código estándar para "no estoy listo para tráfico ahora mismo".

Umbrales configurables vía variables de entorno (`HEALTHCHECK_*`), con default si no están seteadas:

```csharp
public class HealthCheckThresholds
{
    public double CpuWarnPercent { get; }       // default 70, env HEALTHCHECK_CPU_WARN_PERCENT
    public double CpuProblemPercent { get; }    // default 90, env HEALTHCHECK_CPU_PROBLEM_PERCENT
    public double RamWarnPercent { get; }        // default 75, env HEALTHCHECK_RAM_WARN_PERCENT
    public double RamProblemPercent { get; }     // default 90, env HEALTHCHECK_RAM_PROBLEM_PERCENT
    public int HttpQueueWarnCount { get; }       // default 50, env HEALTHCHECK_HTTP_QUEUE_WARN_COUNT
    public int HttpQueueProblemCount { get; }    // default 200, env HEALTHCHECK_HTTP_QUEUE_PROBLEM_COUNT
    public int CosmosLatencyWarnMs { get; }      // default 200, env HEALTHCHECK_COSMOS_LATENCY_WARN_MS
    public int CosmosLatencyProblemMs { get; }   // default 1000, env HEALTHCHECK_COSMOS_LATENCY_PROBLEM_MS
    public int RedisLatencyWarnMs { get; }       // default 50, env HEALTHCHECK_REDIS_LATENCY_WARN_MS
    public int RedisLatencyProblemMs { get; }    // default 300, env HEALTHCHECK_REDIS_LATENCY_PROBLEM_MS
}
```

Valores default son un punto de partida razonable, no medidos contra tráfico real de Sales — a validar con datos reales antes de confiar en ellos en producción.

### 2. Instancia — CPU%, RAM%, HTTP Queue (maneja el status HTTP)

CPU: sampler en background (H6), sin agregar latencia al request. RAM: `Process.WorkingSet64` contra el límite efectivo de memoria (`WEBSITE_MEMORY_LIMIT_MB` si está seteado en el App Service, o el límite que el propio GC de .NET calcula — container/cgroup-aware — si no). HTTP Queue: `kestrel.queued_requests`, instrumento nativo del `Meter` `Microsoft.AspNetCore.Server.Kestrel` (`System.Diagnostics.Metrics`, estable desde .NET 8, disponible en el proyecto que corre `net10.0`), leído con un `MeterListener` sin dependencias nuevas.

```csharp
public class InstanceHealthEvaluator
{
    public async Task<InstanceHealthResult> EvaluateAsync()
    {
        if (_shutdownState.IsShuttingDown)
            return new InstanceHealthResult(DependencyStatus.PROBLEM);

        var cpuStatus = StatusFor(cpuPercent, t.CpuWarnPercent, t.CpuProblemPercent);
        var ramStatus = StatusFor(ramPercent, t.RamWarnPercent, t.RamProblemPercent);
        var httpQueueStatus = StatusFor(httpQueueLength, t.HttpQueueWarnCount, t.HttpQueueProblemCount);
        var generalStatus = new[] { cpuStatus, ramStatus, httpQueueStatus }.WorstOf();

        return new InstanceHealthResult(generalStatus, cpuPercent, ramPercent, httpQueueLength);
    }

    // GENERAL_STATUS: mismos 3 niveles que Cosmos/Redis (OK/WARN/PROBLEM), evaluados contra los
    // mismos pares Warn/Problem por métrica (§1) — IsHealthy (el status HTTP) es PROBLEM ? 503 : 200.
    private static DependencyStatus StatusFor(double value, double warn, double problem)
        => value >= problem ? DependencyStatus.PROBLEM
            : value >= warn ? DependencyStatus.WARN
            : DependencyStatus.OK;
}
```

### 3. Cosmos — una respuesta por tenant, 3 niveles

El chequeo recorre todos los tenants onboarded (vía `ITenantConfigurationResolver.GetAllTenants()`) y llama `ReadAccountAsync()` (nivel de cuenta, sin costo de RU) contra el `CosmosClient` de cada uno, en paralelo para no sumar latencias — trade-off aceptado: N round-trips por llamada al healthcheck (hoy 4 tenants), a cambio de visibilidad real de SLA por franquicia, que es lo que el ticket pide medir. El estado se evalúa contra los umbrales de latencia configurables (OK/WARN/PROBLEM).

### 4. Redis — N/A para Sales, a nivel raíz

Sales.API no tiene esta dependencia (H5). El chequeo es un stub explícito que reporta `N/A`, no un chequeo inventado, y se ubica a nivel raíz de la respuesta, no dentro de cada tenant — Redis es instance-wide (una sola instancia detrás de todo el servicio), a diferencia de Cosmos, que es genuinamente por-tenant. Repetirlo dentro de cada bloque de tenant sería el mismo resultado copiado N veces sin agregar información.

### 5. Formato de respuesta

`CPU`, `RAM`, `HTTP_QUEUE` y `GENERAL_STATUS` van a nivel raíz — son valores de la instancia, no de ningún tenant en particular. `REDIS` también va a nivel raíz, no repetido dentro de cada tenant — Redis es instance-wide, no tenant-scoped (a diferencia de Cosmos), así que no tiene sentido duplicar el mismo resultado en cada bloque de tenant. Cada tenant solo lleva `COSMOS`, que es lo único genuinamente por-tenant.

```json
{
  "CPU": 12.4,
  "RAM": 45.2,
  "HTTP_QUEUE": 0,
  "GENERAL_STATUS": "OK",
  "REDIS": { "STATUS": "N/A", "RESPONSE_TIME": null },
  "grido": {
    "STATUS": "OK",
    "COSMOS": { "STATUS": "OK", "RESPONSE_TIME": 18 }
  },
  "weiss": {
    "STATUS": "WARN",
    "COSMOS": { "STATUS": "WARN", "RESPONSE_TIME": 245 }
  }
}
```

`GENERAL_STATUS` usa los mismos 3 niveles que el resto del documento (`OK`/`WARN`/`PROBLEM`, no `ERROR`) — es el peor de CPU/RAM/HTTP Queue contra sus umbrales configurables (§1). El código de estado HTTP es 503 solo cuando `GENERAL_STATUS` es `PROBLEM` (o la instancia está en shutdown) — `WARN` sigue devolviendo 200: es una señal para la herramienta de SLA, no un motivo para que el balanceador saque la instancia de rotación.

`REDIS: N/A` para Sales, no un `OK` falso — Sales no tiene esta dependencia (H5).

El futuro proxy Zabbix podría parsear esto vía JSONPath, siguiendo el mismo patrón ya usado para FEPE (`operations/events/20260714_fepe_zabbix_healthcheck/`) — pendiente hasta que `sfcloud-monitoreo.smartfran.com` exista.

### 6. Shutdown prolijo por instancia (H7)

4 pasos, mapeados a mecanismos concretos de ASP.NET Core/ANCM:

| Paso | Mecanismo | Estado |
|---|---|---|
| 1. Cerrar puertos | `ApplicationStopping` dispara el cierre de Kestrel a nuevas conexiones; el endpoint de health reporta no-sano en el mismo instante (flag `ShutdownState`), no recién cuando el puerto cierra | Implementado |
| 2. Terminar de procesar lo que se está procesando | Comportamiento default de ASP.NET Core dentro de `shutdownTimeLimit` (default 10s, in-process) | Sin código adicional; drenaje real de los 5 hubs de SignalR mapeados no confirmado todavía |
| 3. Cerrar conexiones a DB/Redis | Disposal de `CosmosClientPool` en `ApplicationStopped` — después de que el drenaje del paso 2 termine, no junto al paso 1 (hacerlo ahí rompería requests todavía en vuelo) | Implementado (`CosmosClientPool.DisposeAll()`) |
| 4. Kill forzado | Comportamiento existente de ANCM si `shutdownTimeLimit` se vence — no es código a implementar, es la red de seguridad ya presente; el objetivo de los pasos 1-3 es que rara vez haga falta | Ya existe, sin cambios |

```csharp
// Program.cs
lifetime.ApplicationStopping.Register(() => shutdownState.IsShuttingDown = true); // paso 1
lifetime.ApplicationStopped.Register(() =>
    app.Services.GetRequiredService<CosmosClientPool>().DisposeAll()); // paso 3, después del drenaje
```

Precedente real en el repo para este patrón de hook: `Source/Common/Functions/SmartFran.Cloud.Pos.Wasm.Relay/Program.cs`, usado para flushear el logger antes de salir.

**Abierto:**
- Si el `shutdownTimeLimit` default (10s) alcanza para drenar el tráfico real de Sales.API — el patrón de Event ID 1005 es evidencia circunstancial de que podría no alcanzar. Cualquier aumento debe seguir evidencia real de tiempo de drenaje necesario, no ser un ajuste especulativo.
- Confirmar el comportamiento real de drenaje de los 5 hubs de SignalR mapeados.

## Recursos afectados

| Recurso | Detalle |
|---|---|
| `SmartFran-Cloud-Sales-PRO` | Primer App Service en implementar el endpoint |
| `SmartFran.Cloud.Sales.API/Controllers/v1/StatusController.cs` | Nueva acción `HealthCheck()`, `Health()` sin cambios |
| `SmartFran.Cloud.Sales.API/Program.cs` | Registro de DI y hooks de shutdown |
| `SmartFran.Cloud.Sales.Infrastructure/HealthCheck/` (nuevo) | `HealthCheckThresholds`, `CpuUsageSampler`, `HttpQueueSampler`, `InstanceHealthEvaluator`, `CosmosHealthCheck`, `RedisHealthCheck`, `ShutdownState`, `DependencyStatus`/`DependencyStatusExtensions` |
| Cuentas CosmosDB de cada tenant onboarded | Origen del chequeo de Cosmos (H4) |
| `sfcloud-monitoreo.smartfran.com` | Host del futuro proxy Zabbix — **no implementado**, fuera de alcance de este ticket |
| Windows Event Log de `SmartFran-Cloud-Sales-PRO` | Fuente de la evidencia de shutdowns forzados (Event ID 1005), ver `cloud/events/20260913_pos-net-http-timeout/` |

## Acciones propuestas

1. **(SRE) Diseño completado** — Endpoint `api/v1/Status/healthcheck` en `SmartFran.Cloud.Sales.API`: status HTTP de instancia, `CPU`/`RAM`/`HTTP_QUEUE`/`GENERAL_STATUS`/`REDIS` a nivel raíz, `COSMOS` por tenant. Implementación en curso en una rama local, todavía no recompilada/retesteada contra esta última versión del formato — no desplegado.
2. **(Dev) Pendiente** — Revisar el diseño y la implementación; confirmar dónde se registra `IConnectionMultiplexer` en DI en los servicios que sí usan Redis (para cuando este patrón se replique ahí, ver H5).
3. **(SRE) Pendiente, antes de exponer el endpoint** — Restringir el acceso a nivel de red (Access Restrictions del App Service) al subnet del load balancer interno y, más adelante, a la IP del proxy Zabbix — el endpoint expone CPU/RAM/estado de dependencias sin autenticación (por diseño, H3), así que la única protección real es de red.
4. **(SRE) Bloqueado** — La integración con Zabbix (script UserParameter en el proxy, item maestro, dependientes, macros, triggers, mismo patrón que FEPE) no puede empezar hasta que `sfcloud-monitoreo.smartfran.com` exista.
5. **(SRE/Dev) Futuro** — Replicar el mismo patrón en los 7 App Services restantes (Admin, Business, Orders, Platform, Person, Catalog, Pos), ajustando el chequeo de Cosmos/Redis según la arquitectura de cada uno.
6. **(Dev) Pendiente** — Confirmar el drenaje real de los 5 hubs de SignalR mapeados durante un shutdown planificado (H7, paso 2), y si el `shutdownTimeLimit` default (10s) alcanza para el tráfico real de Sales.API antes de considerar aumentarlo.

## Hallazgos secundarios

El bypass de `/health` en `TenantHandlingMiddleware` está duplicado en al menos 3 archivos (`Sales.API`, `Functions.Sales.TicketProcessAsync`, `Functions.Business.CodeGenerator.LiteEdition`) — sugiere que este endpoint fue planeado en algún momento a nivel de plataforma, no solo para Sales. Vale la pena confirmar con el equipo de desarrollo si hay contexto/diseño previo no documentado en este repo.

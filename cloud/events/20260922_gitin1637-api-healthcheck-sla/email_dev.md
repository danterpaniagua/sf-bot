Para: Dev — SmartFran Cloud Sales
De: Dante Paniagua, SRE
Asunto: Health endpoint para Sales (GITIN-1637) — caveat de Cosmos multi-tenant, cómo lo vamos a resolver

Hola equipo,

Estamos diseñando el healthcheck de [GITIN-1637](https://smartit-ar.atlassian.net/browse/GITIN-1637) (CPU, RAM, conexión Cosmos, conexión Redis) arrancando por Sales.API. Encontramos un caveat real sobre cómo chequear Cosmos, y quiero avisarles cómo lo vamos a resolver antes de que se empiece a implementar — griten si ven un problema.

## El caveat: Cosmos en Sales es genuinamente por-tenant

Confirmado en el código (`CosmosClientPool.cs`, `Source/Services/Sales/SmartFran.Cloud.Sales.Infrastructure/Repositories/Domain/CosmosSDK/`): cada franquicia tiene su **propia cuenta CosmosDB dedicada** (`smartfran-cloud-cosmos-<tenantId>`), y `CosmosClientPool` crea un `CosmosClient` distinto por tenant, cacheado en un `ConcurrentDictionary`, resuelto desde `ITenantProvider` — que solo se popula durante un request real, vía el claim `org_id` del JWT o el header `TenantId` (ver `TenantHandlingMiddleware.cs`).

Un healthcheck invocado por un prober de infraestructura (load balancer interno, o el futuro proxy Zabbix) no manda JWT ni header de tenant — no hay contexto de tenant disponible fuera de un request real de la app. Así que no existe "la" conexión Cosmos de Sales para chequear tal cual está el mecanismo hoy.

## Cómo lo vamos a resolver: una respuesta por tenant

En vez de chequear un solo tenant de referencia, el healthcheck va a recorrer **todos los tenants onboarded** (hoy: GRIDO, WEISS, lodejacinto, ultracai) y reportar el estado de cada cuenta Cosmos por separado, en paralelo (`Task.WhenAll`, para no sumar latencias). Es la única opción que da visibilidad real de SLA por franquicia, que es justamente lo que pide el ticket — la alternativa más barata (un solo tenant fijo) la descartamos por no cumplir ese objetivo.

Un detalle importante: si el Cosmos de un solo tenant está caído, el healthcheck global va a reportar `Degraded`, no `Unhealthy` — no queremos que el load balancer tumbe Sales.API entero por la caída puntual de la cuenta de una franquicia.

**Lo único que nos falta confirmar de su lado:** si `ITenantConfigurationResolver` ya expone algún método para listar todos los tenants onboarded, o si hay que agregarlo — no lo encontramos en esta sesión. También necesitamos saber dónde se registra `IConnectionMultiplexer` en DI (para el chequeo de Redis), no lo vimos en `Program.cs` directamente.

El resto del diseño (endpoint `GET /api/health`, `HealthChecks` nativo de ASP.NET Core sin agregar dependencias nuevas, sampler de CPU en background) está en el ticket. Avisen si ven algún problema con el enfoque de Cosmos antes de que arranquemos la implementación.

Saludos,
Dante

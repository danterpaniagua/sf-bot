# SmartFran Cloud — Infrastructure Reference

**Subscription:** SmartIT Cloud (`85c76dea-3304-4310-8656-bf21b28e4f4b`) — production/shared services; everything below unless noted.

**Non-prod lives in a different subscription:** RG `SmartFran.Cloud` (no suffix) under **Smart IT - Grido** (`0190fa7d-4ccf-4e3d-beb1-323b5780bfc8`, the same subscription as the SmartLoyalty prod VMs/NSGs, see `docs/azure_nsg.md`) holds 33 App Services across DEV, DEV2, STG, TEST and POC for the same 8 domains (found during GITIN-1794). Out of scope here; inventory in `cloud-graylog/CLAUDE.md` → "App Services — DEV" (separate repo).

---

## Resource groups

| Resource group | Purpose |
|---|---|
| `SmartFran.Cloud.PRO` | Shared services: all App Services, Key Vault, App Configuration, Redis, SignalR, Cosmos, networking, logging |
| `SmartFran.Cloud.PRO.<TENANT>` | Per-franchise persistent data: dedicated SQL Server, elastic pool, `<Domain>_<TENANT>` databases. One per onboarded franchise (confirmed `GRIDO`, `WEISS`) |
| `SmartFran.Cloud` (Smart IT - Grido) | Non-prod, see above |

---

## Multi-tenant architecture

Multiple franchises share the same App Services; there is no deployment per franchise. Front-end branding is served per custom hostname; backend tenant resolution is a separate mechanism (below). Do not conflate the two.

**Shared App Services** (all in `SmartFran.Cloud.PRO`): `SmartFran-Cloud-{Pos,Admin,Business,Sales,Orders,Platform,Person,Catalog}-PRO`, each on server farm `SmartFran-Cloud-<X>-Plan-PRO`. Application Insights: the component suffixed `_new` is the active one (`SmartFran-Cloud-<X>-PRO_new`); non-suffixed duplicates (e.g. `SmartFran-Cloud-Business-PRO_Insights`) are legacy, so confirm which is wired before trusting query results.

**Function Apps** (GITIN-2042, from a live Portal listing): 4 Linux Function Apps on one App Service Plan (`P0v3`, 1 instance, RG `SmartFran.Cloud.PRO`): `SFC-CodeGenerator-PRO`, `SFC-PosWasmRelay-PRO` (log relay for `smartfran-pos-wasm`, `cloud/events/20260913_pos-net-http-timeout/`), `SFC-ScheduledJobs-PRO`, `SFC-TicketProcess-PRO`. They likely back the `SFC.CodeGeneratorFunction` / `SFC.BusinessLog` HttpClients below (which one backs which is unconfirmed). Older names (`SmartFranCloudBusinessFunPro`, `SmartFranCloudTicketProcessAsync-pro`, `SmartFranCloudFunctionsScheduledJobs-pro`) may appear in old tickets and logs; they are not the current apps.

### Per-franchise hostname pattern

`<tenant>.pos.smartfran.com` and `<tenant>.admin.smartfran.com`, each with its own SNI-enabled cert, all bound to the same shared `SmartFran-Cloud-Pos-PRO` / `-Admin-PRO`. Onboarded tenants (2026-07-11): `grido`, `weiss`, `lodejacinto`, `ultracai`. Hostname routing only selects which front-end build/branding is served; a `Verified`/`SniEnabled` binding says nothing about whether tenant-specific config or content is deployed for that host.

### Tenant resolution mechanism (confirmed from source, `repo/SmartFran.Cloud/`)

Every backend service (Business, Catalog, Sales, Orders, Person, Platform, plus the Function apps) carries the same `Organization` model: `name` (e.g. `grido`), `orgId` (Auth0 organization id, e.g. `org_g4qPlLbxcJZx5e7U`), `tenantId` (opaque 12-char alphanumeric, e.g. `d3186bc6d7b2`).

The full list loads at startup from a **single App Configuration key `organizations`** (a JSON array) via `builder.Configuration.GetValue<string>("organizations")`, with the `AzureAppConfiguration` provider on `SmartFran-Cloud-Settings-PRO`. There is no per-tenant label or key-prefix scheme.

`TenantHandlingMiddleware` (only `/api/*`, skips `/health`) resolves per request, in order:
1. Authenticated (Auth0 JWT): the `org_id` claim matched against `Organizations[].orgId`.
2. Else the `TenantId` header, validated against `Organizations[].tenantId`.
3. Else (OAuth callback, e.g. MercadoPago): the `state` query parameter parsed as `<tenantId>:<franchiseeId>`.
4. `tenantId` must match `^[a-zA-Z0-9]{12}$`, else `ApiTenantException(TenantNotAvailable)`.

Confirmed tenant ids: GRIDO `d3186bc6d7b2`, WEISS `kt76igzny9ql`. The 12-char hash (not the franchise name) is the suffix downstream:

| Config key pattern | Resolves to |
|---|---|
| `ConnectionStrings:TenantConnection_<tenantId>` | Tenant's main SQL connection |
| `ConnectionStrings:TenantSynapseConnection_<tenantId>` | Synapse serverless SQL |
| `ConnectionStrings:TenantFabricSqlConnection_<tenantId>` | Fabric Lakehouse SQL (`SmartFranCloudFabric_<TENANT>`) |
| `ConnectionSettings:Tenant_<tenantId>:BusinessCosmosSettings` | Tenant's dedicated CosmosDB account settings |
| Storage account | `cloudstorage<tenantId>` |
| CosmosDB account | `smartfran-cloud-cosmos-<tenantId>` (see the WEISS exception under Core shared services) |

Each franchise has its own CosmosDB account, separate from the shared platform account `smartfran-cloud-cosmos-platform-pro`.

> **Diagnostic implication:** a `manifest.webmanifest` 404 is a front-end static-content deployment problem (Client applications below), unrelated to the `organizations` key. A backend `ApiTenantException` / `TenantNotAvailable` means the `organizations` array lacks an entry, has a malformed id, or the caller's `org_id` / `TenantId` header matches nothing: read the `organizations` value directly.

### Identity provider (Auth0, not Azure AD DS)

Auth0, via `Auth0:Domain` / `Auth0UserManagement` config. Multi-tenancy uses **Auth0 Organizations**, each mapped 1:1 to a `tenantId` through the `organizations` entry. Unrelated to the `smartit.azure` AADDS domain SmartLoyalty uses.

**`Platform.API` `TenantController` authorization (GSFC-1005, PRO release `v02.46.00`, `d969856fa`; GITIN-2134):** class-level `[Authorize]` is active; `GET /api/Tenant/{identifier}` needs `[RequiredScope("read:tenant")]`, write endpoints `write:tenant`; `Organization/*` endpoints are `[AllowAnonymous]`; the `dashboards` PUT needs `write:tenant` + role `Owner`. A valid token without the scope gets 403 (general ASP.NET behavior, not observed here). The POS Blazor WASM client requests scopes from `Source/Pos/.../SmartFran.Cloud.Pos.Wasm/wwwroot/SmartFran.Cloud.Pos.Wasm_{DEV,STG,TEST}.json` (all include `read:tenant`); **there is no `_PRO` file in the repo**, so the PRO client's requested scopes are not visible from source.

**PRO tenant `smartfran-cloud.us.auth0.com`** (Management API read, 2026-09-30, GITIN-2134):
- API `SmartFran.Cloud.API_PROD`, audience **`smartfran-cloud-prod`** (RS256, RBAC on, permissions in `access_token`, offline access on, token lifetime 86400 s / 7200 s web), 139 permissions including `read:tenant` and `write:tenant`.
- Applications: SPAs `SFC PoS`, `SFC Manager`; machine-to-machine `Business.API_PROD`, `Sales.API_PROD`, `API_PROD (Test Application)`, `Functions.Scheduler`, `SmartPedidos`, `BOT Wise CX`, `SmartFran.Loyalty.WebServiceCG`, `Auth0 Management`, `READ_API`.
- Organizations (4): `grido` (`org_z72xsKwcFsVLHF3c`), `jacinto`, `ultracai`, `weiss`.
- Roles (8, direct members): Collaborator 146, Franchisee 72, Franchisor 1, FranchisorExecutive 2, FranchiseeExecutive 0, Kitchen 2, Owner 36, Wholesale 2. All hold `read:tenant`; only Owner holds `write:tenant`.
- The code's `RequiredScope` values include 7 permissions the PRO API lacks: `delete:accountcategory`, `delete:chartofaccountsassignment`, `delete:chartofaccountsconcept`, `delete:chartofaccountsgroup`, `delete:moneywarehouse`, `write:franchisororderrequests`, `write:franchisororderresponses`.
- The `AUTH0_*_PROD` Management API credentials used had scopes `read:client_grants/clients/resource_servers/roles/role_members/organizations/organization_members` (no organization-member roles, no logs).

**Dev tenant `dev-wzt4q1xqoe7cwz0f.us.auth0.com`** (LOCAL/DEV/TEST/STG/DEMO/DEV2; same read): APIs `SmartFran.Cloud.Catalog.API_{LOCAL,DEV,TEST,STG,DEMO,DEV2}` (RBAC on; `read:tenant`/`write:tenant` exist on LOCAL/DEV/TEST/STG), per-environment applications (`POS_*`, `Client.Web_*`, `Platform.API_*`, `Business.API_*`, `Sales.API_*`, ...), 15 roles (Collaborator, Delegated Admin ×4, Franchisee, FranchiseeExecutive, FRANCHISEE TEST, Franchisor, FranchisorExecutive, Kiri, Kitchen, Owner, Test, Wholesale). **It has no PRO API or application**; PRO is the separate `smartfran-cloud` tenant (the Platform API's checked-in `appsettings.json` still points at this dev domain). `GET /api/v2/roles/{id}/permissions` is capped at 100 per page: use `page=` (5 roles hit exactly 100). The POS SPA receives scopes at user login (requested `Scopes` ∩ the user's role permissions); client grants apply to machine-to-machine apps only.

### Per-franchise persistent data

Each tenant's databases live in `SmartFran.Cloud.PRO.<TENANT>`. WEISS (tenantId `kt76igzny9ql`): SQL Server `t102-smartfran-cloud-weiss`, elastic pool `SmartFran.Cloud.SqlElastic.WEISS`, databases `SmartFran.Cloud.Business_WEISS`, `SmartFran.Cloud.Catalog_WEISS`, `SmartFranCloudFabric_WEISS`, storage account `cloudstoragekt76igzny9q`.

`Business_<TENANT>` and `Catalog_<TENANT>` are separate **Azure SQL Databases** on the same elastic pool, not databases on one classic SQL Server. `USE [OtherDatabase];` is a silent no-op in Azure SQL (each database is its own connection scope): change the database in the query tool itself. Table/column reference for both: `/cloud-invalid-sale`.

### Client applications (`repo/SmartFran.Cloud/Source/`)

| Project | Type | Notes |
|---|---|---|
| `Pos/SmartFran.Cloud.Pos/SmartFran.Cloud.Pos.Wasm` | Blazor WebAssembly PWA | Serves `wwwroot/manifest.webmanifest` (the file behind the 2026-07-11 WEISS 404): a missing/stale manifest is a static-content deployment problem, not tenant config |
| `Pos/.../SmartFran.Cloud.Pos.Component` | Razor component library | Shared UI consumed by the Wasm host |
| `Client/SmartFran.Cloud.Client.Web` | Web (Admin front-end, presumed) | |
| `Client/SmartFran.Cloud.Client.Wasm`, `.Mobile`, `.Component` | Blazor WASM, mobile client, shared component library | |

### Named HttpClient convention

Internal service-to-service clients are registered as `SFC.<Target>` (visible in .NET logs as `System.Net.Http.HttpClient.Sfc.<Target>.LogicalHandler`):

| Caller | Registers |
|---|---|
| `Pos.Wasm` | `SFC.Catalog`, `SFC.Business`, `SFC.Sale`, `SFC.Person`, `SFC.Order`, `SFC.Platform`, `SFC.Loyalty` (→ SmartLoyalty WebServiceV2), `SFC.CouponPedigrido`, `SFC.CodeGeneratorFunction`, `SFC.BusinessLog` |
| `Business.API` | `SFC.Catalog`, `SFC.Person`, `SFC.Platform`, `SFC.Grido` (external franchise API), `SFC.CodeGeneratorFunction` |
| `Catalog.API` | `SFC.Business`, `SFC.Platform`, `SFC.CodeGeneratorFunction` |
| `Sales.API` | `SFC.WsFeAr/Pe/Py/Uy` (fiscal webservices per country), `SFC.Business`, `SFC.Catalog`, `SFC.Platform`, `SFC.Person`, `SFC.CodeGeneratorFunction` |

`SFC.Loyalty` is a direct POS integration with SmartLoyalty's `WebServiceV2` (`loyalty/docs/infrastructure.md`): consider it in cross-project incidents touching POS and points.

### Logging (GSFC-LOG-1)

All services share one Serilog pipeline (`SmartFran.Cloud.Provider.Logger.Core.SerilogBootstrap`, `Source/Common/Providers/`): a single `Console` sink writing CLEF-style JSON → stdout → `AppServiceConsoleLogs` (Diagnostic Settings) → Event Hub → Graylog (`cloud-graylog` repo). Field-level detail: `docs/graylog-log-fields.md`.

- **It cannot work for Windows App Services (Sales, Pos)** (GITIN-1811): `AppServiceConsoleLogs` is not supported for .NET on Windows at all (Microsoft supports it only for JavaSE/Tomcat there). A platform limitation, not a config bug. Linux App Services (Business, Platform, Person, Admin, Catalog, Orders; container-hosted) work.
- **Real prerequisites found on `Sales-DEV`** (necessary but not sufficient): `stdoutLogEnabled="false"` in the SDK-generated `web.config` (none is checked into `SmartFran.Cloud.Sales.API`; ANCM discards stdout unless `"true"`, with `stdoutLogFile` outside `wwwroot`, `\\?\%home%\LogFiles\stdout`); `applicationLogs.fileSystem` was `"Off"` (`az webapp log config --application-logging filesystem`); ANCM `hostingModel="inprocess"` buffering left the redirect file at 0 bytes until an `az webapp restart`. With all three fixed the CLEF JSON is visible in Kudu Log Stream but never reaches Graylog.
- **Workaround in place:** Sales uses a direct Serilog→Event-Hub CLEF sink (`graylog-log-fields.md`). The `AppServiceAppLogs` + `AzureMonitorTraceListener` path is marked unsupported for ASP.NET Core in the source found (unconfirmed either way).
- **"Works on my machine" proves nothing:** Visual Studio F5 / IIS Express / Kestrel attaches to the process and captures `Console.Out`, bypassing IIS/ANCM stdout redirection.
- **Scope of confirmation:** `Sales-DEV` confirmed; `Pos-DEV` shares the same build pattern (`windows-latest`, `dotnet publish`, no `web.config` override) and is almost certainly affected, unconfirmed; `Sales-PRO` / `Pos-PRO` unverified (also Windows/.NET). Full investigation: `events/20260810_sales-serilog-console-logs/`.
- **Diagnostic settings (GITIN-1937):** `AppServiceHTTPLogs` and `AppServiceAppLogs` are enabled on all 8 PRO and all 8 DEV App Services (16 settings). Delivery to Graylog was confirmed for `AppServiceHTTPLogs` on `Business-PRO` (Linux) only, not per app and not for `AppServiceAppLogs` on the Windows apps. Detail: `events/20260825_webapps-console-app-http-logs-graylog/`.

Read-only check of whether ANCM captures stdout on another app (Kudu VFS with a short-lived AAD token, no publishing-credential passwords):
```bash
APP=SmartFran-Cloud-Sales-DEV   # or -Pos-DEV, or the -PRO equivalents
TOKEN=$(az account get-access-token --resource https://management.azure.com/ --query accessToken -o tsv)
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://$(echo "$APP" | tr '[:upper:]' '[:lower:]').scm.azurewebsites.net/api/vfs/site/wwwroot/web.config"
```

Sources: Microsoft Q&A "Azure Web app (Windows) console logs not showing in AppServiceConsoleLogs"; Azure App Service blog "AppServiceAppLogs is now available for ASP.NET apps on Windows".

---

## Core Shared Services

| Resource | Name | Notes |
|---|---|---|
| Key Vault | `SmartFran-Cloud-KV-Pro2` | Certs and secrets, likely including per-tenant DB connection strings |
| App Configuration | `SmartFran-Cloud-Settings-PRO` | Holds the `organizations` key |
| Redis | `SmartFran-Cloud-Platform-Cache-PRO` | |
| SignalR | `SmartFran-Cloud-SignalR-PRO` | |
| CosmosDB (platform) | `smartfran-cloud-cosmos-platform-pro` | eastus |
| CosmosDB (WEISS) | `smartfran-cloud-cosmos-pro-kt76igzny9q` | eastus2, in the tenant RG. **Does not follow the plain `smartfran-cloud-cosmos-<tenantId>` pattern**: extra `-pro-` segment and the tenant id truncated to 11 chars (`kt76igzny9q`, not `kt76igzny9ql`). Check this table before guessing a name |
| CosmosDB (GRIDO) | `smartfran-cloud-cosmos-pro-3186bc6d7b2` | RG `SmartFran.Cloud.PRO.GRIDO`. Same `-pro-` pattern, but the truncation drops the **first** char of `d3186bc6d7b2` (WEISS drops the last): the truncation side is not predictable, always read the real name |
| Logging VM (Graylog) | `smartfran-graylog-pro` | eastus2, own VNet/NSG/disks |
| SendGrid | `sf-cloud-sendgrid` | Email delivery through a single `IEmailProvider` (`SendGridEmailService`); failures are logged and dropped (no retry or queue); no attachments. Sender domain for a replacement: `smartfran.com` (user-stated, DNS access available). Alternatives: GITIN-2201 |
| VNets | `sfc_vnet`, `vnet_smartfrancloud` | eastus |
| NAT Gateways | `sfc_nat_ngw`, `sfc_nat_fabric`, `sfc_nat_appservice_pro` | Outbound egress per workload tier |
| WAF | **None** | Confirmed absent (GITIN-1938): retail App Services are reached directly through the per-tenant hostname / SNI binding |
| Azure APIM | **None** | Confirmed absent (GITIN-1938): requests hit the App Service directly |

**Cosmos firewall (GRIDO account, GITIN-2083, 2026-09-18; remediation was pending when last recorded, so re-read before relying on it):** the account's `ipRules` held only 4 entries unrelated to SmartFran Cloud (the Azure sentinel `0.0.0.0` for Portal/Data Explorer and 3 static office/VPN IPs), with `isVirtualNetworkFilterEnabled: false`, `virtualNetworkRules: []` and `networkAclBypass: "None"`. None of the 14 outbound IPs of the 7 App Services and 3 Function Apps (`SFC-CodeGenerator-PRO`, `SFC-TicketProcess-PRO`, `SFC-ScheduledJobs-PRO`) that use the account was allowed: zero coverage. Observed effect: 49 `CosmosException Forbidden (403)` in a ~2-minute burst (2026-09-18 21:08-21:09:56 UTC) on Business, Person and Orders API. Options: allow-list `possibleOutboundIpAddresses` (the full pool, not only the active IPs, or an outbound IP rotation reopens the gap), `networkAclBypass=AzureServices`, or VNet integration. Sales' Service Bus consumers (`MoneyMovementConsumer`/`StockMovementConsumer`) have a retry-storm circuit breaker that a sustained Cosmos failure would trigger (possible link to the Sales CPU spike of GITIN-2073, unconfirmed). Diagnose with Graylog `firewall AND Cosmos AND NOT message:AppServiceHTTPLogs` (a bare full-text query returned 891,990 generic hits) and `az cosmosdb show` for the rules. Detail: `events/20260918_sales-cosmos-403-firewall/`.

**Sales CosmosDB layout (WEISS):** SQL API databases per tenant follow `<Domain>-<TENANT>`: `Sales-WEISS`, `Orders-WEISS`, `Business-WEISS`, `PersonsDB-WEISS`, `Audit-WEISS` (these Cosmos "Business"/"Orders" are separate from the same-named SQL databases). `Sales-WEISS` containers: `Sales`, `SaleOrders`, `Shifts`, `Movements`, `MovementCurrentAccount`, `PaymentMethods`, `KdsOrders`, `DeliveryRoutes`, `WalletNotifications`. The `Sales` container partition key is `MultiHash` on `[/FranchiseeCode, /FranchiseCode, /PosCode]` (`az cosmosdb sql container show`). `az cosmosdb sql *` manages only account/database/container metadata; for ad-hoc document queries use Data Explorer in the Portal or the SDK.

### Service findings worth knowing before investigating (from solved or open events)

- **Sales-PRO crashes with `System.OutOfMemoryException`** (GITIN-2040, then `events/20260920_sales-oom-48h/`): Azure's Proactive Crash Monitoring detector logs `0xE0434352 - CLR Exception` (18 crashes in 48 h). `SmartFran-Cloud-Sales-PRO` is Windows, plan P3v3 (~32 GB per instance, about USD 1.26/h per instance), 3 instances, autoscale 1-4 on CPU, .NET v10. The worker ran with `use32BitWorkerProcess: true` (a 32-bit process addresses only ~2-4 GB regardless of plan RAM); setting it to `false` was necessary but **not sufficient** (a 64-bit crash followed 5 h 45 min later at 2026-09-21 06:00 GMT, 15 min after one instance hit 87 % memory), and the setting later **flipped back to `true` on its own** (the PRO deploy workflow `SmartFran.Cloud.Sales.PRO_win.yml` does not touch App Service config; mechanism unconfirmed). Re-read `az webapp config show` after every deploy. Suspected memory pattern: unbounded `Movement/POSGetAll` (13,745 requests in 48 h, max 230,015 ms, the Azure 230 s ceiling; `AccessRepository.GetByConditionsAsync` / `MovementServices.POSGetAllAsync` have no `Take(n)`; identical on `dev` and `origin/main`). Crashes leave requests hanging until the client timeout, so 0 of 640,105 requests were 5xx. Check memory per instance (a 30-minute live window after the peak misses it). `az monitor activity-log --resource-id` does not filter by resource, see `cloud/CLAUDE.md`.
- **Health endpoint design (GITIN-1637, implemented and tested on a local branch for `Sales.API`; production rollout not confirmed):** `api/v1/Status/healthcheck` replaces `api/v1/Status/Health` (which only answered `Ok`). HTTP status reflects **instance** health only (503 when `GENERAL_STATUS` is `PROBLEM`): the signal for a balancer or autoscaler. The JSON body adds the same instance values (`CPU`, `RAM`, `HTTP_QUEUE`, `GENERAL_STATUS`), root-level `REDIS`, and Cosmos **per tenant** (each tenant's `CosmosClient.ReadAccountAsync()`, no RU cost, in parallel), all with levels `OK` / `WARN` / `PROBLEM`: the signal for SLA tooling. Thresholds (warn/problem) come from App Service environment variables: `HEALTHCHECK_CPU_WARN_PERCENT` 70 / `…_PROBLEM_PERCENT` 90, `HEALTHCHECK_RAM_*` 75 / 90, `HEALTHCHECK_HTTP_QUEUE_*_COUNT` 50 / 200, `HEALTHCHECK_COSMOS_LATENCY_*_MS` 200 / 1000, `HEALTHCHECK_REDIS_LATENCY_*_MS` 50 / 300. A `ShutdownState` flag makes the endpoint report the instance as draining when a planned shutdown starts. Detail: `events/20260922_gitin1637-api-healthcheck-sla/`.
- **Peru order delay (GITIN-2084; related report GITIN-2109, `CRS: 409` marking PedidosYa orders ready on branches 5470/5424):** SQS-to-POS delay on Peru branches 5396/5481/5523 (`events/20260919_grido-order-delay-peru-5396-5481/`). Root cause **not confirmed** when last recorded. Best-evidenced lead: per-instance CPU saturation on `SmartFran-Cloud-Sales-Plan-PRO` plus manual hosting-plan changes on 2026-09-18 21:06-22:06 UTC, followed by a Sales-wide HTTP timeout cascade (21:50-22:00 UTC, ~20 endpoints, 500s on `Sale/Create` and `Sale/Close`) that coincided with delay peaks in branches 5396 and 5481. No code dependency between Sales-PRO and the Orders/SQS bridge was traced, and equivalent CPU spikes on 2026-09-19 and 2026-09-20 did not reproduce the cascade. Treat 2084 and 2109 as separate until proven otherwise. The bridge itself is described under "SmartPedidos bridge".

---

## SmartCloud Graylog — retention, index sets and volume (GITIN-2209, GITIN-2228)

Read from the Graylog API (`GET /api/system/indices/index_sets?stats=true`) and OpenSearch (`_cat/indices`), not from the repo. API gotcha: with `?stats=true` the statistics sit in the top-level `stats` object keyed by index set id, not inside each `index_sets` entry. Field-level and stream detail: `docs/graylog-log-fields.md`, `cloud/CLAUDE.md`.

| Item | Value |
|---|---|
| Index sets | 25: an application set `SFC-<Service>-prod` per service plus, for Admin, Business, Catalog, Orders, Person, Platform, Pos and Sales, a second `SFC-<Service>-prod-http`; CodeGenerator, PosWasmRelay, ScheduledJobs and TicketProcess have the application set only; plus `DEV`, `DEV-http`, `Default index set`, `Graylog Events`, `Graylog System Events` |
| Streams → sets | `PROD-<Service>-AppServicePlan` → `SFC-<Service>-prod`; `PROD-<Service>-AppServiceHTTPLogs` → `SFC-<Service>-prod-http`; Function App streams → their own sets. All have "remove from default stream" on; the Default set still holds 20.6 GB (12 million documents) whose content was not examined. A stream writes to exactly one set; several can share one |
| Retention | Data Tiering `hot_only`: index lifetime **P30D to P40D** for the application, default and events sets; **P7D to P9D** for the `*-http` sets and `DEV`. The legacy `rotation_strategy` / `retention_strategy` (`max_number_of_indices: 20`) are inherited and do not govern while `data_tiering` is present (`use_legacy_rotation: false`) |
| VM and disks | VM `sfcloud-monitoreo` (Azure `smartfran-graylog-pro`, `Standard_D8s_v6`; the two names are matched by disk size, not confirmed on the VM). OpenSearch disk `nvme0n3`: 768 GB (grown to 768 on 2026-10-09, GITIN-2209), Premium P30 (5,000 IOPS / 200 MB/s, no bursting), host caching `ReadOnly`. MongoDB disk 64 GB, P6, host caching `ReadWrite`. `read_ahead_kb` is 65,536 on all three NVMe devices (usual 128; no definition found) |
| Stored size | 2026-10-14: 571 GB in 101 indices (113.5 million documents): Business 217 GB (38 %), Orders 111, Sales 53, ScheduledJobs 43, CodeGenerator 26, Default 19, PosWasmRelay 16; `*-http` sets about 36 GB. 2026-10-21: 583 GB; Business 226.7, Orders 117.8, Sales 51.0, ScheduledJobs 49.3, CodeGenerator 28.3, TicketProcess 21.1, Default 20.6, Platform 17.9, PosWasmRelay 17.7, Catalog 12.8, Admin 9.1, Pos 8.0, Person 2.5 (the 8 business applications total 445.8 GB); `*-http` sets and `DEV` about 6 GB — **not reconciled with the ~36 GB of 10-14** |
| Volume (estimates from stored index size spread over each index's active period; not raw ingest) | About 9-12 GB/day on 1-6 October; 37-52 GB/day on 8-12 October. Business about 1.8 GB/day before 7 October, about 30 at the peak; Orders 2-3 GB/day before 7 October, 6-8 after (cause not determined) |
| Sizing at project time (June 2026, cloud-graylog repo) | About 37 million records/day measured on 7 services (Orders excluded), 30 days of retention, 1 TB for the fleet, 350 bytes/event (about 13-16 GB/day) |
| Level field | `AppLevel`. `Unknown` is a real value (HTTP access records, the `-http` sets); `Information` is ~96 % of application messages. 24 h counts (8 services): 2.74 million messages, `Information` 60.9 %, `Warning` + `Error` + `Fatal` 2.6 %, `Unknown` 36.5 % (counted by `name:`, which undercounts; see `cloud/CLAUDE.md`) |
| `Information` older than 7 days (OpenSearch `_count` dry run) | 50.7 million of 79.0 million documents (64 %) in the 8 application sets; about 286 GB of 446 GB by document share (assumes equal document size). Older non-`Information` documents that would stay: 10.0 million (Business 6.5, Platform 2.8) |
| Search limits (`SearchesClusterConfig`) | Range limit `P15D`, timeout 60 s (`cancel_after_seconds`) |
| Search time baseline (first run, 15 days, ms) | `Information`: Business 24,864, Orders 36,196, Sales 12,522. `Warning`/`Error`: Business 3,577, Orders 2,683, Sales 3,667. Repeated runs are served from cache and are much faster |
| Alerting | A Zabbix low-disk alert triggered GITIN-2209 (user statement; threshold and firing time not checked). A per-index-set ingest-rate alert is an idea, not decided |
| Open | Cause of the disk latency (candidates: `read_ahead_kb`, host caching `ReadOnly`, per-request disk latency); retention decision (7 days `Information` and 30 days `Warning` and above via new streams and index sets, or a daily deletion of old `Information`). Evidence: GITIN-2228 event folder |

### Graylog VM operations (`smartfran-graylog-pro` / `sfcloud-monitoreo`, GITIN-2128)

- **Everything runs as native systemd services, not containers** (`graylog-server`, `opensearch`, `logstash`, MongoDB, nginx in front, `/graylog/` prefix); `cloud-graylog/docs/architecture.md` still describes Graylog as a container (stale).
- **OpenSearch data volume:** `/var/lib/opensearch` is a dedicated XFS data disk (`nvme0n3p1`, UUID `c40ff0c4-04ca-4f94-9dc5-bf4831316fd4`; 512 GB at the incident, 768 GB later, see the Graylog table above), mounted through `/etc/fstab` with `nofail`; MongoDB has its own mount `/var/lib/mongodb`. Terraform (`cloud-graylog/terraform/disks.tf`) manages the Azure disk and its attachment, **not** the `fstab` inside the OS.
- **502 diagnosis chain:** nginx `502 Bad Gateway` with `Connection refused` on port 9000 → `graylog-server` is up as a process but never finished initializing → `opensearch.service` failed with `Result: timeout` → `AccessDeniedException` writing `/var/lib/opensearch/nodes` because the data volume was not mounted and the empty mount point is `root:root`. Check in this order: `/var/log/nginx/error.log`, `systemctl status opensearch`, `/var/log/opensearch/graylog.log`, `ls -la /var/lib/opensearch/`, `cat /etc/fstab`, `lsblk -f` / `blkid`, then `curl http://127.0.0.1:9200/_cluster/health` and `:9000/api/`. `nofail` is why the VM boots anyway with the volume missing. The `systemd-fstab-generator` logs `Failed to create unit file '/run/systemd/generator/var-lib-opensearch.mount', as it already exists. Duplicate entry in '/etc/fstab'?` on a duplicate entry.
- **Disk full / flood-stage watermark** (`events/20260818_disk-flood-watermark/`): above the OpenSearch flood-stage watermark (95 %) every index with a shard on the single node gets `index.blocks.read_only_allow_delete`, Graylog stops indexing (journal fills: "Uncommitted messages deleted from journal", "Journal utilization is too high", "Indices blocked"), and the block **does not lift by itself** when usage drops: after freeing space, `PUT _all/_settings` with `index.blocks.read_only_allow_delete: null`, then confirm `docs.count` grows. Growing the data disk takes two steps: Azure disk resize (to 768 GB on 2026-10-09) **and** extending the partition and the XFS filesystem inside the VM (the resize alone left `/var/lib/opensearch` at 512 GB; done online, without stopping OpenSearch, `events/20261009_gitin2209-graylog-poco-espacio-disco/scripts/scripts-grow.sh`). Cause of that week's growth: Business `GET /api/v1/WalletCredentials/{userId}` refreshes a credential with ≤7 days left; when MercadoPago rejects the refresh (`invalid_grant`) the service logs a Warning and leaves the credential active and inside the renewal window, so every call retries the same rejected refresh token (about 4.5 million messages/day against ~170 thousand before, ~8.8 failures/s, ~6 log lines each, from 2026-10-07 ~22:30 UTC-3). Why MercadoPago rejects the tokens is not determined; when this volume reappears, count by `Path` / `NormalizedPath`.
- **Incident 2026-09-29 (GITIN-2128):** 502 from 18:00:36 to 21:54:27 UTC (~4 h; the first nginx sample misled, read the full log). Trigger: an Azure protective shutdown (Resource Health RCA `vma_rca_io_timeout_nodereboot_generic_e17`, `VirtualMachineStorageOffline`, 17:48:33-17:54:35 UTC; no Activity Log trace because it is platform-initiated; kernel back 17:56:45). The `fstab` held four conflicting lines for the OpenSearch mount (one with an empty `UUID=`, two duplicates of the real UUID), so the volume mounted neither at that boot nor after the manual `restart` at 21:00:50 (which was not the cause). Fix: backup `/etc/fstab.bak-20260929`, delete the empty-UUID line and the duplicate without `nofail`, leaving one `UUID=… defaults,nofail` line; remount, `systemctl reset-failed opensearch.service && systemctl start opensearch.service`. No index data was lost (~326 GB used on the disk). Logstash reconnected to Event Hub by itself. Single-node cluster stays `yellow` while indices keep `replicas: 1` (unassigned shards, unrelated). Detail: `events/20260929_gitin2128-graylog-502-opensearch-mount/`.
- **Volume cliff and `event_original` indexing failures, 2026-07-28 (`operations/events/20260729_graylog_sin_datos/`, `20260730_graylog_indexing_failure/`):** Business and Sales volume fell ~97 % at 06:00 UTC (03:00 ART) with no Azure activity-log entry; Logstash had restarted at 06:06:40 UTC, and the same hour began indexing failures `Document contains at least one immense term in field="event_original"` (32,766-byte Lucene limit, observed 131 KB, decoded prefix `{"records": [{ "time": ...`, i.e. the Azure batch wrapper, not one record: the largest single Business record in Log Analytics was ~2.9 KB). Event Hub `IncomingMessages` counts batches, not records, so it stayed flat. The 2026-07-02 `event.set("event_original", record.to_json)` fix sits inside `if record.is_a?(Hash)` with no `else`, and `decorate_events => true` fills `event_original` with the whole batch first; with `pipeline.ecs_compatibility: v8` a nested `[event][original]` may also exist. A patch on the flat field alone had no effect; patch v2 (2026-07-31, truncation of both fields plus an `else` tag) showed 0 failures in the first 79 s, soak not confirmed. Volume recovered at 14:00 UTC on 2026-07-31 right after the day's first Logstash restart, so the original collapse was most likely a stuck consumer state that a restart clears (circumstantial, no isolation test). `stdout { codec => rubydebug }` on events of this size exhausts the 1 GB Logstash heap and crash-loops it: never enable it unscoped. `EnableSensitiveDataLogging(true)` is hardcoded in Business, Catalog, Sales and Platform `Program.cs` (blame: 2023-10-25). Always `logstash -t` before a restart and confirm no restart loop afterwards.
- **Memory and swap (`GITIN-2167`, 2026-10-05; the ticket reached the host as `sf-monitoreo.smartfran.com`, see `../../docs/graylog_infrastructure.md`):** 31 GiB RAM; JVM heaps logstash 4 GB, graylog 4 GB, OpenSearch 12 GB (`/etc/opensearch/jvm.options.d/heap.options` overrides the packaged `1g` pair in `jvm.options`, the later flag wins: expected, confirmed `heap.max` = 12gb); swap 4 GiB `/swapfile` plus a 4 GiB file added on the XFS MongoDB volume (both in `/etc/fstab`), `vm.swappiness` 10; 3.4 GiB swapped before and after, mostly cold pages (logstash ~1.8 GB, graylog ~1.2 GB, opensearch ~0.4 GB; `vmstat` si/so ~0), so more swap clears an absolute-usage alert only if its threshold allows it (the Zabbix trigger was not read). OpenSearch `ram.percent` 99 counts page cache.

- **API tokens (Graylog 7.1.3, GITIN-2329, 2026-10-27):** token creation is governed by the cluster config `org.graylog2.users.UserConfiguration` (`GET/PUT system/cluster_config/org.graylog2.users.UserConfiguration`, the PUT resends the whole object). With `restrict_access_token_to_admins: true` an ordinary user keeps `users:tokenlist`/`tokenremove` on themselves but is not offered "create token" (no `users:tokencreate`); the setting was changed to `false` and stays so (any user can create tokens that act as them). Other keys: `allow_access_token_for_external_user: false`, `default_ttl_for_new_tokens: PT720H`. All 16 built-in roles are read-only (including `Reader`, which has no stream permissions); per-stream access is `streams:read:<id>`, either directly on the user's permissions or through a custom role (`POST /api/roles`). `POST /api/authz/shares/entities/{grn}` replaces the whole grant set (see the `cloud-azure` skill). Remote MCP access is off (`org.graylog.mcp.config.McpConfiguration`: `enable_remote_access: false`). Event: `cloud/events/20261027_gitin2329-graylog-user-token-creation/`.


## Service Bus

| Field | Value |
|---|---|
| Namespace | `SmartFran-Cloud-ServiceBus-Grido-PRO` |
| RG | `SmartFran.Cloud.PRO.GRIDO` |
| Action group | `Service_Bus_Group` (RG `SmartFran.Cloud.PRO`) |

DLQ alert rule baseline: metric `Dead-lettered messages`, threshold `> 0`, aggregation `Total`, evaluation window ≥ 5 min.

---

## SmartPedidos bridge (AWS SQS, not Service Bus)

Confirmed from source (GITIN-2068); easy to wrongly assume it goes through the Service Bus namespace above. `SmartFran.Cloud.Orders.Application.Services.Aws.MessageProcessor.PollOnceAsync` polls **AWS SQS directly** (AWS SDK; no Azure Service Bus, no Function App relay) from the Azure-hosted Orders API:

- **Producer (SmartPedidos):** `concentrador-service` creates one per-branch FIFO queue (`<branchId>PRD_PlatformMessages.fifo`, account `382381053403`, `us-east-1`); `platforms-service` pushes each new order there.
- **Consumer (SmartCloud):** `MessageProcessor` polls that queue from Orders-PRO, routes to `ProcessGridoOrderAsync` / `ProcessNonGridoOrderAsync` via `OrderSQSVersionSettings.GetVersion(tenantId)` (live App Configuration key `OrderSQSVersion`; unregistered tenants default to Grido's `v1` mapping), persists to Cosmos, and acks to SmartPedidos through a second SQS queue.
- **Failure handling:** an unhandled exception in either path leaves the message undeleted, retried until the queue's `MessageRetentionPeriod` (3 days) expires, silently: it rarely reaches the DLQ (`maxReceiveCount: 1000`) and SmartPedidos is never told. GITIN-2068's root cause (a `TimeZoneCountries.cs` Windows-timezone-ID bug for any country outside its 4-entry dictionary) lived here.
- A separate pull-based path exists (`/api/v1/Queue/Heartbeat` → SmartPedidos' `/branches/heartbeat`); its precedence relative to the SQS path is unresolved (see Open questions).

## Open questions

- Whether the Service Bus namespace `...-Grido-PRO` is Grido-specific or shared by all franchises despite the name.
- The full current `organizations` list: only GRIDO and WEISS ids are confirmed, from source, not from a live App Configuration read.
- The `Security` service (`Source/Services/Security/`) has no App Service confirmed in the Azure inventory: embedded elsewhere or unmapped?
- Which of the SQS bridge and the `/api/v1/Queue/Heartbeat` pull path is authoritative for order delivery to POS terminals in production, or whether both are load-bearing for different purposes.

---

## Source code reference

A local working copy (edit and pull allowed, never commit or push) is at `cloud/repo/SmartFran.Cloud/` (`.gitignore`d from this monorepo):

```
Source/
  Services/{Business,Catalog,Orders,Person,Platform,Sales,Security}/   one .NET solution per service (Application/API/Infrastructure)
  Pos/SmartFran.Cloud.Pos/{...Wasm,...Component}                       POS Blazor WASM PWA
  Client/{...Web,...Wasm,...Mobile,...Component}                       Admin/other front-ends
  Common/{Functions,Helpers,Providers}                                 Azure Functions, shared libraries
```

> **Security:** `Services/Business/SmartFran.Cloud.Business.API/appsettings.json` is git-tracked in that clone with 42 commits of history and contains plaintext credentials (DB/Synapse/Fabric passwords, Cosmos keys, Storage keys, Redis password, Auth0 client secret, encryption key). A recent commit added it to `.gitignore`, which removes neither the history nor the current index entry. Never echo values from it into any doc or output: architecture patterns only. It needs credential rotation and a history rewrite in that repo, independent of documentation work here.

---

## Related

- Skill `/cloud-azure`: investigation workflow and CLI commands for this infrastructure.
- `docs/azure_nsg.md` (repo root): the Smart IT - Grido subscription (SmartLoyalty prod VMs/NSGs), which also hosts the `SmartFran.Cloud` non-prod App Services: two unrelated workloads sharing one subscription.
- `loyalty/docs/infrastructure.md`: SmartLoyalty side of the `SFC.Loyalty` / WebServiceV2 integration.

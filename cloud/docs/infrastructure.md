# SmartFran Cloud — Infrastructure Reference

**Last updated:** 2026-08-10
**Subscription:** SmartIT Cloud (`85c76dea-3304-4310-8656-bf21b28e4f4b`) — production/shared services, everything in this doc unless noted otherwise.

**Non-prod environments exist in a different subscription** — discovered 2026-08-10 in the separate `cloud-graylog` project (ticket GITIN-1794, log-ingestion onboarding, not app diagnostics): RG `SmartFran.Cloud` (no suffix) under subscription **Smart IT - Grido** (`0190fa7d-4ccf-4e3d-beb1-323b5780bfc8` — same subscription used for SmartLoyalty prod VMs/NSGs, see `docs/azure_nsg.md` note below) holds 33 App Services across DEV, DEV2, STG, TEST, and POC tiers for the same 8 domains listed below. Out of scope for this project; full inventory documented in `cloud-graylog/CLAUDE.md` → "App Services — DEV" (separate repo, not part of this monorepo).

---

## Resource Groups

| Resource Group | Purpose |
|---|---|
| `SmartFran.Cloud.PRO` | Shared services — all App Services, Key Vault, App Configuration, Redis, SignalR, Cosmos, networking, logging |
| `SmartFran.Cloud.PRO.<TENANT>` | Per-franchise persistent data — dedicated SQL Server, elastic pool, `<Domain>_<TENANT>` databases. One RG per onboarded franchise. Confirmed: `GRIDO`, `WEISS`. |
| `SmartFran.Cloud` (different subscription — Smart IT - Grido) | Non-prod: DEV/DEV2/STG/TEST/POC App Services for the same 8 domains. Out of scope for this project — see note above. |

---

## Multi-tenant Architecture

SmartFran Cloud hosts **multiple franchises on the same shared App Services** — there is no separate deployment per franchise. Front-end branding/content is served per custom hostname; backend API tenant resolution is a separate mechanism entirely (see "Tenant resolution mechanism" below) — don't conflate the two.

**Shared App Services** (all in `SmartFran.Cloud.PRO`):

| App Service | Server Farm | App Insights (`_new` = active) |
|---|---|---|
| `SmartFran-Cloud-Pos-PRO` | `SmartFran-Cloud-Pos-Plan-PRO` | `SmartFran-Cloud-Pos-PRO_new` |
| `SmartFran-Cloud-Admin-PRO` | `SmartFran-Cloud-Admin-Plan-PRO` | `SmartFran-Cloud-Admin-PRO_new` |
| `SmartFran-Cloud-Business-PRO` | `SmartFran-Cloud-Business-Plan-PRO` | `SmartFran-Cloud-Business-PRO_new` (legacy dupe: `SmartFran-Cloud-Business-PRO_Insights`) |
| `SmartFran-Cloud-Sales-PRO` | `SmartFran-Cloud-Sales-Plan-PRO` | `SmartFran-Cloud-Sales-PRO_new` |
| `SmartFran-Cloud-Orders-PRO` | `SmartFran-Cloud-Orders-Plan-PRO` | `SmartFran-Cloud-Orders-PRO_new` |
| `SmartFran-Cloud-Platform-PRO` | `SmartFran-Cloud-Platform-Plan-PRO` | `SmartFran-Cloud-Platform-PRO_new` |
| `SmartFran-Cloud-Person-PRO` | `SmartFran-Cloud-Person-Plan-PRO` | `SmartFran-Cloud-Person-PRO_new` |
| `SmartFran-Cloud-Catalog-PRO` | `SmartFran-Cloud-Catalog-Plan-PRO` | `SmartFran-Cloud-Catalog-PRO_new` |

**Function Apps:** `SmartFranCloudBusinessFunPro` (+ `-stg` slot), `SmartFranCloudTicketProcessAsync-pro`, `SmartFranCloudFunctionsScheduledJobs-pro`.

**App Insights naming convention:** components suffixed `_new` are the active ones each app service actually sends telemetry to. Non-suffixed duplicates (e.g. `SmartFran-Cloud-Business-PRO_Insights`) are legacy — confirm which one is wired up before trusting query results.

### Per-franchise hostname pattern

`<tenant>.pos.smartfran.com` and `<tenant>.admin.smartfran.com`, each with its own SNI-enabled SSL cert, all bound to the **same** shared `SmartFran-Cloud-Pos-PRO` / `SmartFran-Cloud-Admin-PRO` App Services.

**Confirmed onboarded tenants (2026-07-11):** `grido`, `weiss`, `lodejacinto`, `ultracai`.

**Hostname routing only determines which front-end build/branding is served — it is not how the backend resolves the tenant.** Confirmed by source (`repo/SmartFran.Cloud/`, 2026-07-12): hostname/cert binding being `Verified`/`SniEnabled` says nothing about whether tenant-specific app config or content is deployed for that host.

### Tenant resolution mechanism (confirmed from source, 2026-07-12)

Every backend service (Business, Catalog, Sales, Orders, Person, Platform, plus the Function apps) carries an identical `TenantSettings`/`Organization` model:

```csharp
public class Organization {
  public string name { get; set; }      // e.g. "grido", "weiss"
  public string orgId { get; set; }      // Auth0 organization id, e.g. "org_g4qPlLbxcJZx5e7U"
  public string tenantId { get; set; }   // opaque 12-char alphanumeric id, e.g. "d3186bc6d7b2"
}
```

The full `Organization` list is loaded at startup from a **single App Configuration key named `organizations`** (a JSON array) — `builder.Configuration.GetValue<string>("organizations")` — via the `AzureAppConfiguration` provider pointing at `SmartFran-Cloud-Settings-PRO`. **This is the actual per-tenant config convention** — there is no per-tenant label/key-prefix scheme in App Configuration; it's one array holding every onboarded tenant's `name`/`orgId`/`tenantId` triplet.

**Per-request resolution** (`TenantHandlingMiddleware`, applies to `/api/*` paths only, skips `/health`):
1. If the caller is authenticated (Auth0 JWT): read the `org_id` claim → match against `Organizations[].orgId` → resolves `tenantId`.
2. Else: read the `TenantId` HTTP header directly, validated against `Organizations[].tenantId`.
3. Else (OAuth callback flow, e.g. MercadoPago): parse the `state` query parameter as `<tenantId>:<franchiseeId>`.
4. `tenantId` must match `^[a-zA-Z0-9]{12}$` (exactly 12 alphanumeric chars) or the request fails with `ApiTenantException(TenantNotAvailable)`.

**Confirmed tenant IDs:** GRIDO = `d3186bc6d7b2`, WEISS = `kt76igzny9ql`.

Once resolved, `tenantId` (the 12-char hash — **not** the franchise name) is the suffix used everywhere downstream:

| Config key pattern | Resolves to |
|---|---|
| `ConnectionStrings:TenantConnection_<tenantId>` | Tenant's main SQL connection |
| `ConnectionStrings:TenantSynapseConnection_<tenantId>` | Tenant's Synapse serverless SQL connection |
| `ConnectionStrings:TenantFabricSqlConnection_<tenantId>` | Tenant's Fabric Lakehouse SQL connection (→ `SmartFranCloudFabric_<TENANT>` DB) |
| `ConnectionSettings:Tenant_<tenantId>:BusinessCosmosSettings` | Tenant's **dedicated** CosmosDB account settings |
| Storage account name | `cloudstorage<tenantId>` |
| CosmosDB account name | `smartfran-cloud-cosmos-<tenantId>` |

Each franchise has its **own dedicated CosmosDB account** (named by tenantId), separate from the shared platform Cosmos account (`smartfran-cloud-cosmos-platform-pro`).

> **Diagnostic implication:** a `manifest.webmanifest` 404 is a front-end/static-content deployment problem (see Client Applications below) — it has nothing to do with the `organizations` App Configuration key. A backend `ApiTenantException`/`TenantNotAvailable` error, by contrast, means the `organizations` array is missing an entry, has a malformed 12-char id, or the caller's `org_id`/`TenantId` header doesn't match anything in it — check the App Configuration `organizations` key value directly, not per-tenant labels.

### Identity Provider

**Auth0**, not Azure AD DS — confirmed via `Auth0:Domain` / `Auth0UserManagement` config. Multi-tenancy at the auth layer uses **Auth0 Organizations**, each mapped 1:1 to a `tenantId` via the `organizations` App Configuration entry above. Do not confuse with the `smartit.azure` AADDS domain used by SmartLoyalty — they are unrelated identity systems.

### Per-franchise persistent data

Each tenant's databases live in its own RG, named `SmartFran.Cloud.PRO.<TENANT>`. Example (WEISS, tenantId `kt76igzny9ql`):

| Resource | Type |
|---|---|
| `t102-smartfran-cloud-weiss` | SQL Server |
| `t102-smartfran-cloud-weiss/SmartFran.Cloud.SqlElastic.WEISS` | Elastic pool |
| `t102-smartfran-cloud-weiss/SmartFran.Cloud.Business_WEISS` | Database |
| `t102-smartfran-cloud-weiss/SmartFran.Cloud.Catalog_WEISS` | Database |
| `t102-smartfran-cloud-weiss/SmartFranCloudFabric_WEISS` | Database |
| `cloudstoragekt76igzny9q` | Storage account (tenant-scoped, name = `cloudstorage<tenantId>`) |

**Note (confirmed 2026-08-02, `20260802_promocion-invalida-weiss-franui`):** `Business_<TENANT>` and `Catalog_<TENANT>` are separate **Azure SQL Database** databases on the same elastic pool — not separate databases on a single classic SQL Server instance. A `USE [OtherDatabase];` statement inside a query is a silent no-op in Azure SQL (each database is its own connection scope); switching between them requires reconnecting/changing the database in the query tool itself, not issuing `USE`. See `/cloud-invalid-sale` for the full table/column reference for both databases.

### Client Applications (source: `repo/SmartFran.Cloud/Source/`)

| Project | Type | Notes |
|---|---|---|
| `Pos/SmartFran.Cloud.Pos/SmartFran.Cloud.Pos.Wasm` | Blazor WebAssembly PWA | Serves `wwwroot/manifest.webmanifest` — the exact file behind the 2026-07-11 WEISS 404. A missing/stale manifest is a static-content deployment problem for this project specifically, not a tenant-config issue. |
| `Pos/SmartFran.Cloud.Pos/SmartFran.Cloud.Pos.Component` | Razor component library | Shared UI: Pages, Services, Theme, Shared — consumed by the Wasm host. |
| `Client/SmartFran.Cloud.Client.Web` | Web (Admin front-end, presumed) | |
| `Client/SmartFran.Cloud.Client.Wasm` | Blazor WASM | |
| `Client/SmartFran.Cloud.Client.Mobile` | Mobile client | |
| `Client/SmartFran.Cloud.Client.Component` | Shared component library | |

### Named HttpClient convention

Every service registers internal service-to-service `HttpClient`s under an `SFC.<Target>` naming convention (this is what appears in .NET logs as `System.Net.Http.HttpClient.Sfc.<Target>.LogicalHandler`). Confirmed registrations:

| Caller | Registers |
|---|---|
| `Pos.Wasm` | `SFC.Catalog`, `SFC.Business`, `SFC.Sale`, `SFC.Person`, `SFC.Order`, `SFC.Platform`, `SFC.Loyalty` (→ SmartLoyalty WebServiceV2), `SFC.CouponPedigrido`, `SFC.CodeGeneratorFunction`, `SFC.BusinessLog` |
| `Business.API` | `SFC.Catalog`, `SFC.Person`, `SFC.Platform`, `SFC.Grido` (external franchise API), `SFC.CodeGeneratorFunction` |
| `Catalog.API` | `SFC.Business`, `SFC.Platform`, `SFC.CodeGeneratorFunction` |
| `Sales.API` | `SFC.WsFeAr/Pe/Py/Uy` (fiscal webservices per country), `SFC.Business`, `SFC.Catalog`, `SFC.Platform`, `SFC.Person`, `SFC.CodeGeneratorFunction` |

`SFC.Loyalty` on the POS front-end confirms a direct integration point with SmartLoyalty's `WebServiceV2` (see `loyalty/docs/infrastructure.md`) — cross-project incidents touching POS + points should consider this call path.

### Logging (GSFC-LOG-1) — broken by design for Windows apps, not a config bug

All services share one Serilog pipeline (`SmartFran.Cloud.Provider.Logger.Core.SerilogBootstrap`, in `repo/SmartFran.Cloud/Source/Common/Providers/`): single `Console` sink writing CLEF-style JSON → stdout → `AppServiceConsoleLogs` (Diagnostic Settings) → Event Hub → Graylog (see `cloud-graylog` repo, separate project). No file/blob/heterogeneous sinks by design.

**This pipeline structurally cannot work for Windows App Services (Sales, Pos) — confirmed 2026-08-11 (GITIN-1811).** `AppServiceConsoleLogs`, the Diagnostic Settings category the whole pipeline exports through, **is not supported for .NET applications on Windows at all** (Microsoft only supports it for JavaSE/Tomcat there). No amount of correct configuration fixes this — it's a platform limitation, not a bug. **Linux** App Services (Business, Platform, Person, Admin, Catalog, Orders — container-hosted) work fine, because that category *is* supported for containers.

Three real, legitimate config gates were found and fixed along the way for `Sales-DEV` — worth knowing about since they're genuine prerequisites even though they don't solve the actual problem on their own:
- `stdoutLogEnabled="false"` in the SDK's default-generated `web.config` (no `web.config` is checked into `SmartFran.Cloud.Sales.API`) — IIS/ANCM silently discards stdout unless this is `"true"`, with `stdoutLogFile` pointed outside `wwwroot` (`\\?\%home%\LogFiles\stdout`, the platform-managed directory — confirmed to pre-exist, no folder-creation code needed).
- `applicationLogs.fileSystem` was `"Off"` — the platform won't collect the redirected stdout file's content unless this is enabled (`az webapp log config --application-logging filesystem`).
- ANCM's `hostingModel="inprocess"` had a stdout buffering quirk — the redirect file was created but stayed at 0 bytes until an `az webapp restart` forced a fresh flush.

All three fixed and confirmed — real CLEF JSON is now visible live via Kudu Log Stream. It still never reaches Graylog, even after an hour of real business traffic, because `AppServiceConsoleLogs` itself never ships data off a Windows/.NET App Service, regardless of how correctly everything upstream is configured.

**Resolution requires a dev/architecture decision**, not further SRE config work: most likely a direct GELF sink added to Serilog (bypassing Diagnostic Settings/Event Hub entirely — the exact thing GSFC-LOG-1 removed), or the documented `AppServiceAppLogs` + `AzureMonitorTraceListener` + `System.Diagnostics.Trace` path (explicitly marked unsupported for ASP.NET Core in the source found, unconfirmed either way), or something else. See `ops.md` in the event folder for the options as presented to dev.

**"Works on my machine" is not evidence against any of this** — running via Visual Studio (F5/IIS Express/Kestrel debug profile) attaches directly to the process and captures `Console.Out` live; it never goes through IIS/ANCM's stdout redirection at all.

Confirmed for `Sales-DEV` specifically. `Pos-DEV` shares the same CI/CD build pattern (`windows-latest` runner, `dotnet publish`, no `web.config` override) and is almost certainly affected the same way, unconfirmed. Both were onboarded to Graylog in GITIN-1794 (Event Hub/Diagnostic Settings confirmed working there for `AppServiceHTTPLogs`, which is platform-generated and unaffected by any of this). **`Sales-PRO`/`Pos-PRO` status is entirely separate and unverified** — same platform limitation would apply if checked (both are also Windows/.NET), but nothing has actually confirmed it there.

Diagnostic command (read-only, Kudu VFS via short-lived AAD token — avoids exposing publishing-credentials passwords) if checking whether ANCM is capturing stdout on another app:
```bash
APP=SmartFran-Cloud-Sales-DEV   # or -Pos-DEV, or the -PRO equivalents if checking those separately
TOKEN=$(az account get-access-token --resource https://management.azure.com/ --query accessToken -o tsv)
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://$(echo "$APP" | tr '[:upper:]' '[:lower:]').scm.azurewebsites.net/api/vfs/site/wwwroot/web.config"
```

Full investigation: `events/20260810_sales-serilog-console-logs/`.

Sources: [Azure Web app (Windows) console logs not showing in AppServiceConsoleLogs — Microsoft Q&A](https://learn.microsoft.com/en-us/answers/questions/2147544/azure-web-app-(window)-asp-net-api-console-logs-ar), [AppServiceAppLogs is now available for ASP .NET apps on Windows](https://azure.github.io/AppService/2020/08/31/AzMon-AppServiceAppLogs.html).

---

## Core Shared Services

| Resource | Name | Notes |
|---|---|---|
| Key Vault | `SmartFran-Cloud-KV-Pro2` | Certs + secrets, likely including per-tenant DB connection strings |
| App Configuration | `SmartFran-Cloud-Settings-PRO` | Holds the `organizations` key (JSON array of all tenants) — see "Tenant resolution mechanism" above |
| Redis | `SmartFran-Cloud-Platform-Cache-PRO` | |
| SignalR | `SmartFran-Cloud-SignalR-PRO` | |
| CosmosDB (platform) | `smartfran-cloud-cosmos-platform-pro` | eastus |
| CosmosDB (shared, per-tenant storage listed separately) | `smartfran-cloud-cosmos-pro-kt76igzny9q` | eastus2 — appears in tenant RG (WEISS). **Check this table for the account name before guessing** — the naming isn't the plain `smartfran-cloud-cosmos-<tenantId>` pattern implied by the "Tenant resolution mechanism" section above: it has an extra `-pro-` segment and the tenant ID is truncated to 11 chars (`kt76igzny9q`, not the full 12-char `kt76igzny9ql`). |
| Logging VM (Graylog) | `smartfran-graylog-pro` | eastus2, own VNet/NSG/disks |
| SendGrid | `sf-cloud-sendgrid` | Email delivery |
| VNets | `sfc_vnet`, `vnet_smartfrancloud` | eastus |
| NAT Gateways | `sfc_nat_ngw`, `sfc_nat_fabric`, `sfc_nat_appservice_pro` | Outbound egress per workload tier |

**Sales CosmosDB layout (confirmed 2026-08-03, `20260802_promocion-invalida-weiss-franui`), WEISS:** SQL API databases per tenant follow `<Domain>-<TENANT>` (confirmed: `Sales-WEISS`, `Orders-WEISS`, `Business-WEISS`, `PersonsDB-WEISS`, `Audit-WEISS` — note these Cosmos "Business"/"Orders" databases are separate from the same-named SQL Server databases, don't conflate). `Sales-WEISS` containers: `Sales`, `SaleOrders`, `Shifts`, `Movements`, `MovementCurrentAccount`, `PaymentMethods`, `KdsOrders`, `DeliveryRoutes`, `WalletNotifications`. `Sales` container partition key confirmed via `az cosmosdb sql container show`: `MultiHash` on `[/FranchiseeCode, /FranchiseCode, /PosCode]`. No `az` CLI command exists for ad-hoc SQL API queries against document content — use Data Explorer in the Azure Portal (or the SDK) for that; `az cosmosdb sql *` commands only manage account/database/container *metadata*.

---

## Service Bus

| Field | Value |
|---|---|
| Namespace | `SmartFran-Cloud-ServiceBus-Grido-PRO` |
| RG | `SmartFran.Cloud.PRO.GRIDO` |
| Action group | `Service_Bus_Group` (RG: `SmartFran.Cloud.PRO`) |

DLQ alert rule baseline: metric `Dead-lettered messages`, threshold `> 0`, aggregation `Total`, evaluation window ≥ 5 min.

---

## Open Questions

- Whether the Service Bus namespace (`...-Grido-PRO`) is Grido-specific or shared across all franchises despite the name — worth checking before assuming other tenants use the same namespace.
- Full list of current `organizations` entries (all onboarded tenants' `name`/`orgId`/`tenantId`) — not pulled from a live App Configuration read; only GRIDO and WEISS tenant IDs are confirmed (from source, not from a runtime query).
- `Security` service (`Source/Services/Security/`) exists in the codebase but has no corresponding App Service confirmed in the Azure inventory yet — check whether it's embedded in another service or genuinely unmapped.

---

## Source Code Reference

A local read-only clone of the application codebase is available at `cloud/repo/SmartFran.Cloud/` (`.gitignore`d from this monorepo — present locally, not committed here). Solution layout:

```
Source/
  Services/{Business,Catalog,Orders,Person,Platform,Sales,Security}/   — one .NET solution per service (Application/API/Infrastructure)
  Pos/SmartFran.Cloud.Pos/{...Wasm,...Component}                       — POS Blazor WASM PWA
  Client/{...Web,...Wasm,...Mobile,...Component}                       — Admin/other front-ends
  Common/{Functions,Helpers,Providers}                                 — Azure Functions, shared libraries
```

> **Security note (2026-07-11):** `Services/Business/SmartFran.Cloud.Business.API/appsettings.json` is git-tracked in that clone with 42 commits of history and contains plaintext credentials (DB/Synapse/Fabric passwords, Cosmos keys, Storage keys, Redis password, Auth0 client secret, encryption key). A recent commit added it to `.gitignore`, which does not remove it from history or the current index. Do not echo values from this file into any doc or output — architecture *patterns* only. This needs credential rotation and a history rewrite in that repo, independent of documentation work here.

---

## Related

- Skill: `/cloud-azure` — investigation workflow and CLI commands for this infrastructure.
- `docs/azure_nsg.md` (repo root `docs/`) — separate subscription (Smart IT - Grido, `0190fa7d...`), covers SmartLoyalty prod VMs/NSGs — do not confuse with this subscription. That same subscription also hosts the `SmartFran.Cloud` DEV/DEV2/STG/TEST/POC App Services (see note at top of this file) — two unrelated workloads sharing one subscription, not a sign either belongs to the other's project.
- `loyalty/docs/infrastructure.md` — SmartLoyalty side of the `SFC.Loyalty` / WebServiceV2 integration point.

# SmartFran Cloud — Infrastructure Reference

**Last updated:** 2026-07-12
**Subscription:** SmartIT Cloud (`85c76dea-3304-4310-8656-bf21b28e4f4b`)

---

## Resource Groups

| Resource Group | Purpose |
|---|---|
| `SmartFran.Cloud.PRO` | Shared services — all App Services, Key Vault, App Configuration, Redis, SignalR, Cosmos, networking, logging |
| `SmartFran.Cloud.PRO.<TENANT>` | Per-franchise persistent data — dedicated SQL Server, elastic pool, `<Domain>_<TENANT>` databases. One RG per onboarded franchise. Confirmed: `GRIDO`, `WEISS`. |

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

---

## Core Shared Services

| Resource | Name | Notes |
|---|---|---|
| Key Vault | `SmartFran-Cloud-KV-Pro2` | Certs + secrets, likely including per-tenant DB connection strings |
| App Configuration | `SmartFran-Cloud-Settings-PRO` | Holds the `organizations` key (JSON array of all tenants) — see "Tenant resolution mechanism" above |
| Redis | `SmartFran-Cloud-Platform-Cache-PRO` | |
| SignalR | `SmartFran-Cloud-SignalR-PRO` | |
| CosmosDB (platform) | `smartfran-cloud-cosmos-platform-pro` | eastus |
| CosmosDB (shared, per-tenant storage listed separately) | `smartfran-cloud-cosmos-pro-kt76igzny9q` | eastus2 — appears in tenant RG (WEISS) |
| Logging VM (Graylog) | `smartfran-graylog-pro` | eastus2, own VNet/NSG/disks |
| SendGrid | `sf-cloud-sendgrid` | Email delivery |
| VNets | `sfc_vnet`, `vnet_smartfrancloud` | eastus |
| NAT Gateways | `sfc_nat_ngw`, `sfc_nat_fabric`, `sfc_nat_appservice_pro` | Outbound egress per workload tier |

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
- `docs/azure_nsg.md` (repo root `docs/`) — separate subscription (Smart IT - Grido, `0190fa7d...`), covers SmartLoyalty prod VMs/NSGs — do not confuse with this subscription.
- `loyalty/docs/infrastructure.md` — SmartLoyalty side of the `SFC.Loyalty` / WebServiceV2 integration point.

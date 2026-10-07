# Investigation — 20261002_gitin2158-appconfiguration-migration

**Status:** in progress — scoping; nothing has been changed anywhere; waiting for the real `Config` contents of the SmartLoyalty.WebService nodes
**Jira:** GITIN-2158 "Migrate loyalty appsettings to an azure App Configuration" — https://smartit-ar.atlassian.net/browse/GITIN-2158

## Goal

Move the SmartLoyalty application settings out of per-server `Config\` files into Azure App Configuration. The ticket text gives no further scope; the user named SmartLoyalty.WebService as the first service to analyse and described the setting files as the ones in its `Config` folder (`AppSettings.config`, `ConnectionStrings.config`, `ServiceModel.Services.config`, `SystemDiagnostics.config`, `Unity.config`).

## Confirmed facts

Source facts come from a read-only inspection of the local clone of the SmartLoyalty source: working tree of branch `main` @ `aef06a72a` (merge of PR #1038, 2026-09-29), clean. Key-name inventory (names only, no values): `data/appsettings-inventory-names.txt`.

- **Runtime:** every web/service project targets .NET Framework 4.7.2 (IIS, ASP.NET MVC/WebApi, WCF services, a Windows service host); the only .NET 5 project is a test data provider. The applications do not use `appsettings.json`.
- **Configuration is externalised per project with `configSource`:** each `Web.config`/`App.config` points `<appSettings>`, `<connectionStrings>`, `<unity>`, `<system.diagnostics>` (and for some projects WCF, authentication, session state, custom errors) to files under `Config\`.
- **The real files are not in git.** `.gitignore` excludes `Config/AppSettings.config` and `Config/Settings.xml`; only the `*-Template` versions are tracked. The real values live on each server, so drift between servers cannot be seen from the repository.
- **appSettings surface (templates only):** 17 templates, 701 entries, 214 distinct key names. Largest: WebServiceV2 121, WebServiceCG 110, WebSite 97, TaskOperatorService 74, MailingEmblue 60, ClubSiteG2 59, WebService 39, MobileAppService 31; BackOfficeService and DeliveryService have none. 122 key names appear in three or more projects, 83 in exactly one (shared names include the SMTP settings, `DefaultEmailFrom/To`, `CustomerMinAge`, `PendingCustomerDataVigency`, `UrlToPublicShared`).
- **Sensitive-looking names:** 17 distinct key names match a password/secret/token/key pattern (SMTP, FTP, reCAPTCHA, Facebook, Identel and other tokens). This is a heuristic on names; no value was inspected. Connection strings are a separate file (`ConnectionStrings.config`), also not in git.
- **How the code reads configuration:** `ConfigurationManager.AppSettings` in 73 source files and `ConfigurationManager.ConnectionStrings` in 15 — static access spread through the shared libraries and the front ends; no `GetSection`, no Key Vault and no App Configuration use anywhere in the source.
- **A second store (XML read by PowerShell):** the back-office script host (`Front/SmlBackScript`, script set `SmartLoyalty.SmlBackScript`) reads `Config\Settings.xml` through `Lib\GetConfigValue.ps1`; the tracked template has 80 elements and 32 distinct element names (SMTP, ConnectionString, report and notification sections, `UrlToPublic`, `StartAzureService`, …). No file called `appsettings.xml` exists in either clone; the file the user meant is `AppSettings.config`. A .NET configuration builder would not reach PowerShell scripts, so this store needs another mechanism if it is in scope (to be verified).
- **SmartLoyalty.WebService:** its `Web.config` points eight sections at `Config\` fragments — `ConnectionStrings`, `Unity`, `AppSettings`, `SystemDiagnostics`, plus four WCF ones (`ServiceHostingEnvironment`, `ServiceModel.Services`, `Bindings`, `Behaviors`). Its `AppSettings-Template.config` has 39 keys, one with a sensitive-looking name. The user's listing of the server `Config` folder shows five files and not `Bindings`, `Behaviors` or `ServiceHostingEnvironment`; since `configSource` requires those files, the listing is probably partial (not verified). The service runs on SFCG-WEBS-01/02/03, so per-node drift can be checked across three servers.
- **Where each service runs** (from `loyalty/docs/infrastructure.md`): MobileAppService on SFCG-MOBI-01/02, WebService on SFCG-WEBS-01/02/03, WebServiceV2 on SFCG-WSV2-01/02, WebServiceCG on SFCG-WSCG-01, WebSite on SFCG-WSIT-01, ClubSite on SFCG-CLUB-01/02, TaskOperatorService on SFCG-TO-01. The Jira tag set lists PROD, PREPRO and TEST02 as environments; which of them have their own servers is not recorded here.

## Current working theory

Because the code reads settings through the static `ConfigurationManager.AppSettings` and every project already isolates them in one `Config\AppSettings.config`, the lowest-risk path is a provider that fills `appSettings` before the application starts, leaving the 73 call sites unchanged. Two options to evaluate (library behavior to be checked against current documentation before relying on it):
1. **Configuration builder for .NET Framework** (`Microsoft.Configuration.ConfigurationBuilders.AzureAppConfiguration`, needs .NET Framework 4.7.1 or later — satisfied by 4.7.2): attached to the appSettings section, no change in the call sites, settings read at application start (a change needs an app-pool recycle). Open point: how the builder attribute combines with the existing `configSource` indirection.
2. **`Microsoft.Extensions.Configuration.AzureAppConfiguration`** (netstandard2.0): supports refresh and Key Vault references but needs code to build and expose an `IConfiguration`, which does not reach the static call sites without a bridge.

Scope proposal (not decided): `AppSettings.config` is the main candidate; `ConnectionStrings.config` holds secrets and would go through Key Vault references if included; `Unity`, `ServiceModel.*` and `SystemDiagnostics` are structural XML rather than key-value settings and stay as files. WebService is a reasonable first service: 39 keys, one sensitive-looking name, three nodes to compare.

## Ruled out

- A separate `appsettings.xml` as the target — no such file exists; the settings are in `Config\AppSettings.config`.

## Open questions / next steps

- **Real contents of WebService:** key names (and counts) of `Config\AppSettings.config` and the connection-string names on SFCG-WEBS-01, -02 and -03, plus the file list of each `Config` folder, to compare with the template and between nodes without copying any value; a read-only PowerShell block that prints names only has been prepared and is waiting for output.
- **Scope from the ticket owner:** which services/templates (all 17 or production only); appSettings only or also connection strings and the other fragments; whether secrets go to Key Vault with App Configuration references; whether the PowerShell `Settings.xml` is in scope.
- **Infrastructure:** whether an App Configuration store exists; one store per environment or labels; network path from the DMZ VMs (private endpoint vs public, NSG/firewall); authentication from IaaS VMs (service principal or managed identity on the VM — they are not App Service); credential ownership and rotation.
- **Behavior:** failure mode when the store is unreachable at start (local fallback), refresh vs recycle, caching, key naming and labels (`<Service>:<Key>` or shared vs service-specific), sentinel key if refresh is wanted.
- **Rollout and rollback:** order of services (low-risk first), keeping the old `Config\AppSettings.config` until verified, how to revert an app pool.
- **Rules for this event:** no secret value is written into this repository or the ticket; only key names and counts are recorded.

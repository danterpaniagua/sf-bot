# Investigation — 20260908_netcore-stack-upgrade-analysis

**Jira:** none yet — analysis requested ahead of ticket creation ("no ticket for now").

## Purpose

Cloud is planning a .NET stack upgrade: some `SmartFran.Cloud` services run on .NET 7, others on .NET 8; the goal is to move straight to .NET 10, skipping .NET 9 entirely (a reasonable choice independent of anything found here — .NET 9 is STS and its extended-support end date, November 10 2026, is the same date .NET 8's Azure Functions in-process support also ends, so landing on 9 first would just mean migrating again almost immediately). This investigation inventories the actual current state, checks reachability of .NET 10 for each project group, and flags concrete migration risks — not a Jira ticket yet, pure analysis.

## Confirmed facts

**Repo:** `cloud/repo/SmartFran.Cloud`, branch `dev`, fetched/pulled clean 2026-09-08 before analysis (`git fetch origin && git pull --ff-only origin dev` — no changes, already current).

**Stack inventory** (reusable command below) — of 62 `.csproj` files, ~48 are already `net10.0`. Four outlier groups remain:

| Group | Projects | TFM |
|---|---|---|
| Azure Functions, **in-process model** | `Catalog.Azure.Functions`, `Functions.Business.CodeGenerator.LiteEdition`, `Internal.Azure.Functions.Business.Balance` | net7.0 / net8.0 / net8.0 |
| Azure Functions, isolated worker | `Catalog.Azure.Functions.Isolated`, `Internal.Azure.Functions.Support`, `Internal.Azure.Functions.Isolated` | net7.0 / net7.0 / net8.0 |
| Client | `Client.Wasm` (net7.0), `Client.Mobile` (net7.0, MAUI android/ios/maccatalyst) | net7.0 |
| Web API triplet | `Security.Application`/`.Infrastructure`/`.API` | net8.0 |

Inventory command (re-run periodically to track progress):
```bash
find . -name "*.csproj" -not -path "*/bin/*" -not -path "*/obj/*" -print0 \
  | xargs -0 -I{} sh -c 'tf=$(grep -oE "<TargetFramework[s]?>[^<]*</TargetFramework[s]?>" "{}" | head -1); echo "$tf | {}"'
```

**Sourced external facts (2026-09-08, via WebSearch/WebFetch against Microsoft Learn):**
- In-process Azure Functions model **cannot run .NET 10 at all** — Microsoft's explicit guidance is to migrate to isolated worker first. [Compare Azure Functions Runtime Versions](https://learn.microsoft.com/en-us/azure/azure-functions/functions-versions)
- **In-process model support ends November 10, 2026** — ~2 months from today, independent of this initiative.
- Isolated worker .NET 10: GA, supported until November 14, 2028.
- **Linux Consumption plan does not support .NET 10** — .NET 9 was the last version added there. Hosting plan per Function App not yet confirmed for this repo.
- **.NET MAUI 10.0.0 is GA** ([release](https://github.com/dotnet/maui/releases/tag/10.0.0)) — target is reachable for `Client.Mobile`, but MAUI ships as a version-locked workload; jumping MAUI 7→10 skips 2 major MAUI releases' framework-level changes.
- Checked `Security.*` source against [ASP.NET Core 9](https://learn.microsoft.com/en-us/aspnet/core/breaking-changes/9/overview?view=aspnetcore-10.0) and [ASP.NET Core 10](https://learn.microsoft.com/en-us/aspnet/core/breaking-changes/10/overview?view=aspnetcore-10.0) breaking-changes lists via grep — none of the source-incompatible patterns present (no `WebHostBuilder`/`IWebHost`, no `IActionContextAccessor`, no `WithOpenApi`, no `KnownNetworks`/`IPNetwork`, no `AddRazorRuntimeCompilation`, no cookie auth in this service at all).
- The only cookie-auth usage in the whole repo is `Client.Web` (already net10.0) — ASP.NET Core 10's "cookie login redirects disabled for known API endpoints" behavioral change already applies there; worth a regression check independent of this migration.

**Package-level findings (grep against `.csproj` files, not yet cross-checked against actual NuGet registry for latest/compatible versions):**
- Isolated Functions outliers pin `Microsoft.Azure.Functions.Worker`/`.Sdk` at 1.x (1.7.0–1.18.0) vs. `2.52.0`/`2.1.0` in an already-migrated net10.0 sibling (`Functions.ScheduledJobs`) — a **major SDK version jump required alongside the TFM change**, not a version-number edit alone.
- Two isolated Functions projects pin `Microsoft.AspNetCore.Http` at `2.2.2` — a vestigial pre-shared-framework-era package reference, likely removable rather than upgradable.
- `Internal.Azure.Functions.Support` (isolated, net7.0) references `Microsoft.AspNet.Mvc 5.3.0` (classic .NET Framework MVC, not ASP.NET Core) alongside ASP.NET Core 2.2-era `Mvc.Abstractions`/`.ViewFeatures`, plus `RazorLight`, `System.Drawing.Common`, `Neodynamic.Blazor.JSPrintManager`, `QRCoder` — reads like legacy Razor-based PDF/receipt generation; needs understanding what it actually does before deciding migrate-vs-rewrite.
- In-process `Catalog.Azure.Functions` uses `Microsoft.Azure.WebJobs.Extensions.SignalRService` — in-process-only package; isolated worker needs the different `Microsoft.Azure.Functions.Worker.Extensions.SignalRService` with a different binding API.
- In-process `Functions.Business.CodeGenerator.LiteEdition` uses `Microsoft.Azure.Functions.Extensions` (in-process `IFunctionsHostBuilder` DI pattern) — isolated worker requires the `FunctionsApplication.CreateBuilder`/`IHostBuilder` pattern instead, a rewrite not a port. Also has a sibling `...LiteEditionV2` already on isolated worker + net10.0 — worth confirming whether the old one is dead code before spending migration effort on it.
- `Client.Mobile` pins `MudBlazor 6.15.0` and `MudBlazor.Markdown 0.1.0` — MudBlazor has real breaking changes across majors (v6→v7→v8, theming/parameter renames); the `0.x` markdown add-on is worth an independent maintenance-risk check regardless of .NET 10.
- Version drift noted, not a blocker: `AutoMapper` is `12.0.1` in `Security.*` vs. `13.0.1` in `Functions.Business.CodeGenerator.LiteEdition` — worth reconciling while touching these projects.

**Unverified, needs a real build to confirm — potential live problem, not created by this migration:** `Security.API`/`Security.Application` (net8.0) have direct `ProjectReference`s to three Common/Providers libraries that are already `net10.0` (`Provider.Authorization`, `Provider.Logger.Core`, `Provider.Logging.AspNetCore`). A net8.0 project referencing a net10.0-only class library is not normally accepted by NuGet's TFM compatibility resolution (`NU1201`) unless something else is going on (e.g. the providers actually multi-target, which the single-tag `<TargetFramework>` in our inventory didn't show). Handed the user a `dotnet build` command to confirm; **not yet confirmed either way**. If real, this means `Security` may not build cleanly on `dev` today, independent of any .NET 10 work — and also means bumping `Security` to net10.0 might *fix* an existing problem rather than create new risk.

## Current working theory

This is not one migration, it's four with different blocker types:
1. **In-process Functions (3)** — architecture migration required before .NET 10 is even reachable; time-boxed by the Nov 10, 2026 in-process retirement, independent of this initiative's own timeline.
2. **Isolated Functions (3)** — TFM bump coupled with a mandatory Worker SDK major-version bump; otherwise straightforward.
3. **Client (2)** — `Client.Wasm` low risk; `Client.Mobile` (MAUI) needs real device-testing budget and a MudBlazor major-version bump, not just a MAUI bump.
4. **Security triplet (3)** — lowest risk of the four per source-level breaking-change checks, *if* the TFM-mismatch build question above resolves cleanly.

## Ruled out

- Nothing formally ruled out — this is a first-pass analysis, not a converged investigation.

## Open questions / next steps

1. **Confirm the `Security`/net10.0-provider TFM-compatibility question** via the `dotnet build` command already handed to the user — determines whether Security has a pre-existing build break.
2. **Confirm hosting plan** (Consumption/Flex/App Service Plan, and OS) for each currently-deployed Function App — determines whether the Linux Consumption .NET 10 cap actually applies to any of them. `docs/infrastructure.md` only lists 3 deployed Function Apps by name (`SmartFranCloudBusinessFunPro`, `SmartFranCloudTicketProcessAsync-pro`, `SmartFranCloudFunctionsScheduledJobs-pro`) — all three map to projects already on net10.0. Unclear whether the 3 in-process/3 isolated outlier projects are even currently deployed as live Function Apps, or dormant/legacy code not in active production use — needs confirming before prioritizing their migration urgency.
3. **Confirm whether `Functions.Business.CodeGenerator.LiteEdition` (in-process, net8.0) is dead code** now that `...LiteEditionV2` exists on isolated worker + net10.0 — if dead, delete rather than migrate.
4. **Understand what `Internal.Azure.Functions.Support` actually does** (the Razor/PDF/printing package mix) before deciding migrate vs. rewrite.
5. No ticket exists yet — ask for a Jira ID once this moves from analysis to actual planned work, per the cross-project "External References" convention.

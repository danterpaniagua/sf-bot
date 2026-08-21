# Investigation — route SFC-PosWasmRelay-DEV console logs to Graylog via Event Hub (GITIN-1901, parent GITIN-1835)

**Status:** Diagnostic Settings deployed 2026-08-20 (`terraform apply`, `gitin-1901.tfplan`, "1 added, 0 changed, 0 destroyed" — `azurerm_monitor_diagnostic_setting.poswasmrelay_dev`, category `FunctionAppLogs`, target `SFC-PosWasmRelay-DEV`, subscription Smart IT - Grido). Infra side of this ticket is done. **Not closed** — end-to-end log delivery is unverified and can't be verified yet: this Function App has zero deployed code, so there's nothing to log. See "Open risk" section below for the unresolved question of whether `FunctionAppLogs` will even capture the dev's planned Serilog/stdout output once code exists.

## Scope (confirmed 2026-08-20, final)

Flow (confirmed by the user):

```
POS (SPA) → Function App (SFC-PosWasmRelay-DEV) → Event Hub → Graylog
```

**This ticket is Diagnostic Settings / infra plumbing only:** configure the `SFC-PosWasmRelay-DEV` Function App to send its console logs to the same Event Hub that the 6 App Service APIs already use (per `azure-eventhub-to-graylog.conf`, GITIN-1883/1892/1835) — same mechanism as those services' `AppServiceConsoleLogs` category, just for this Function App instead.

Earlier framing in this same investigation (payload/field-mapping design for a POS business-log relay, fan-out from the Blazor WASM client, GELF vs. Event Hub delivery choice, relationship to `LogEndpoints.RegisterLog`/Cosmos) was **explicitly ruled out by the user** — none of that is in scope. What the relay's own application code will eventually do with received POS logs is a separate concern; this ticket only needs its **console/stdout output** reaching Graylog, the same way the API services' does.

## What's already confirmed

- **Function App:** `SFC-PosWasmRelay-DEV`, resource group `SmartFran.Cloud`, subscription `0190fa7d-4ccf-4e3d-beb1-323b5780bfc8` (Smart IT - Grido). Kind `functionapp,linux`, state `Running`. Confirmed via `az functionapp list` (2026-08-20).
- **No function code deployed yet** (`az functionapp function list` returned empty, no error) — confirmed by the user this is expected, not a misconfiguration. Diagnostic Settings can still be configured ahead of code deployment; the log category will simply have no data until something actually logs.
- **Repository split (confirmed 2026-08-20 by the user):** event/investigation tracking (this file, `ops.md`, `ops-events.md`) stays in **this repo** (`bots/cloud/events/20260820_azure-functions-to-graylog/`), matching the established pattern for GITIN-1794/1834 (see their own entries in `bots/cloud/events/20260810_dev-environment-onboarding/` and `20260812_prod-full-onboarding/`). The **actual Terraform implementation** lives in the separate `~/Documentos/git/cloud-graylog/` repo — that repo's own `CLAUDE.md` is the source of truth for infra conventions, naming, and the Event Hub/Graylog architecture; this file only needs to reference it, not duplicate it.

## Exact Terraform pattern to follow (from `cloud-graylog/terraform/app_services_dev.tf`, GITIN-1794 precedent)

`SFC-PosWasmRelay-DEV` lives in the same subscription/resource group (`Smart IT - Grido` / `SmartFran.Cloud`) as the 8 DEV-tier App Services GITIN-1794 already wired up — same `provider = azurerm.development`, same target Event Hub. Each existing DEV app follows this exact two-block pattern (Sales shown, `app_services_dev.tf:14-30`):

```hcl
data "azurerm_windows_web_app" "sales_dev" {
  provider            = azurerm.development
  name                = "SmartFran-Cloud-Sales-DEV"
  resource_group_name = data.azurerm_resource_group.dev.name
}

resource "azurerm_monitor_diagnostic_setting" "sales_dev" {
  provider                       = azurerm.development
  name                           = "SmartFran.Cloud.DEV.Sales_DiagnosticSettings"
  target_resource_id             = data.azurerm_windows_web_app.sales_dev.id
  eventhub_name                  = azurerm_eventhub.app_logs.name
  eventhub_authorization_rule_id = azurerm_eventhub_namespace_authorization_rule.diagnostic_settings.id

  enabled_log { category = "AppServiceConsoleLogs" }
}
```

For `SFC-PosWasmRelay-DEV`, the data source type differs — it's a Function App, not a Web App, so it needs `data "azurerm_linux_function_app"` instead of `data "azurerm_linux_web_app"`/`azurerm_windows_web_app` — everything else (provider, resource group data source, target Event Hub `azurerm_eventhub.app_logs`, auth rule `azurerm_eventhub_namespace_authorization_rule.diagnostic_settings`) carries over unchanged. **Not yet confirmed:** whether `AppServiceConsoleLogs` is even a valid category for a Function App resource, or whether Function Apps expose a different category set (e.g. `FunctionAppLogs`) — Web Apps and Function Apps are both `Microsoft.Web/sites` under the hood but their available Diagnostic Settings categories can differ by `kind`. Must check `az monitor diagnostic-settings categories list` against this specific resource before drafting the Terraform block, not assume parity with the Web App pattern above.

**Likely no new Graylog stream/index set needed:** GITIN-1794 already created a `DEV` stream/index set keyed on `field: name`, `type: 2` (regex), `value: .*-DEV` (no anchors — Lucene `regexp` is fullmatch-implicit, see `cloud-graylog/CLAUDE.md`). Since `SFC-PosWasmRelay-DEV`'s resourceId will extract a `name` field of `SFC-PosWasmRelay-DEV` (same Logstash `resourceId`-splitting logic already in place), it should land in the existing `DEV` stream automatically — confirm post-deploy rather than assume, but no new stream/index set work is expected.

**Claude never runs `terraform` commands in that repo** (per its `CLAUDE.md`) — any `plan`/`apply` gets handed to the user as a copy-paste block, same as this repo's own no-run-commands rule.

## Terraform drafted and category confirmed (2026-08-20)

`cloud-graylog/terraform/function_app_dev.tf` — `data.azurerm_linux_function_app` + `azurerm_monitor_diagnostic_setting`, following the exact `app_services_dev.tf` pattern, in its own file per the user's direction (not appended to `app_services_dev.tf`).

**Category confirmed via Azure Portal, not CLI.** `az monitor diagnostic-settings categories list` against `SFC-PosWasmRelay-DEV`'s resource ID returned empty, no error — the same CLI quirk `service_bus.tf` already documents for the Service Bus Grido namespace ("a Standard-tier API quirk — categoryGroup-based settings don't enumerate their underlying categories via that endpoint"), apparently not limited to that one resource type. Unlike Service Bus, there was no existing out-of-band setting or log data to cross-check via KQL either (zero deployed code, zero prior Diagnostic Settings on this Function App). The user checked the Portal's own "Add diagnostic setting" category list directly, which showed: **Function Application Logs**, Site Content Change Audit Logs, Access Audit Logs, IPSecurity Audit logs, App Service Authentication logs (preview) — confirming `FunctionAppLogs` (the API name for "Function Application Logs") is valid for this resource, and confirming Function Apps have a genuinely different category set than Web Apps (`AppServiceConsoleLogs`/`AppServiceAppLogs`, used in `app_services_dev.tf`, aren't options here at all). `function_app_dev.tf` updated to state this as confirmed, not a guess.

## Open risk: does `FunctionAppLogs` actually capture Serilog stdout output? (flagged 2026-08-20, unresolved)

`devs-log-structure.md`'s own header groups "Functions" together with the API hosts as emitting the same Serilog Console-sink JSON to stdout ("cada host de SmartFran.Cloud (APIs, Client.Web, Functions, Pos.Wasm Relay)... por stdout a través del sink de consola de Serilog"). If the dev builds `SFC-PosWasmRelay-DEV` the same way — Serilog → Console sink → stdout — the open question is whether the `FunctionAppLogs` Diagnostic Settings category actually surfaces **raw stdout**, the same way `AppServiceConsoleLogs` does for a Web App, or whether it's scoped to the Functions host's own `ILogger`-mediated invocation/execution logs instead. These are not guaranteed to be the same capture point — a Function App runs user code inside a host process that mediates logging differently than a Web App's direct stdout passthrough, especially under the isolated worker model. Not confirmed either way by anything checked this session (Portal only exposed the category *name*, not what it captures at the byte level).

**Compounding risk, per the user (2026-08-20):** the dev is believed to be testing the function locally as a standalone code block, not against a real deployed Azure Function App / Diagnostic Settings pipeline — inferred from the dev never having asked for any actual Azure resources for this work (no request for `SFC-PosWasmRelay-DEV` access, deployment credentials, or similar), which is consistent with local-only development so far. Local execution (Azure Functions Core Tools or a bare local run) doesn't go through the real Functions host's Diagnostic Settings capture path at all — so even if the dev's local testing shows Serilog output printing to their terminal successfully, that's **no signal whatsoever** about whether the same output will actually reach `FunctionAppLogs` once deployed to the real `SFC-PosWasmRelay-DEV` resource. The only way to actually confirm this is an end-to-end test against the real deployed Function App, after both the Diagnostic Settings (this ticket) and real code are in place — local-only validation would give false confidence.

**Practical implication:** if this turns out not to work as assumed, it manifests as "nothing shows up in Graylog" post-deploy, which would look like a Diagnostic Settings/Event Hub/Logstash pipeline failure (this ticket's territory) when the actual cause could be that the capture point itself doesn't include raw stdout for Function Apps. Worth ruling this in/out with a minimal real deployment early, rather than waiting for the dev's full implementation to be "done" before finding out.

## Not yet done

- Haven't run `az monitor diagnostic-settings list` against `SFC-PosWasmRelay-DEV` to positively confirm zero pre-existing Diagnostic Settings (assumed empty from the app being brand-new, not independently verified).
- `terraform plan` not yet run against `function_app_dev.tf` itself (only against the unrelated disk-drift fix in `main.tf` so far).
- Confirm post-apply whether the resource lands in the existing `DEV` Graylog stream automatically (expected, via the `.*-DEV` regex on the pipeline-extracted `name` field) — blocked until code is actually deployed to this Function App (currently zero code, so there's nothing to log yet regardless of Diagnostic Settings being wired).
- `infrastructure.md:37`'s documented PROD Function App names (`SmartFranCloudBusinessFunPro`, `SmartFranCloudTicketProcessAsync-pro`, `SmartFranCloudFunctionsScheduledJobs-pro`) still don't match anything in this subscription's `az functionapp list` output — unrelated to this ticket's core scope, flagged separately.
- Pending, unrelated to this ticket, found via the same `terraform plan` that confirmed the disk-drift fix: 16 pre-existing uncommitted `metric` block diffs across `app_services.tf`/`app_services_dev.tf`, and a new, already-drafted-but-unapplied `azurerm_monitor_diagnostic_setting.service_bus_grido` resource (`service_bus.tf`, untracked). Neither was touched this session — flagged to the user, decision on whether/when to apply them is theirs.

## Next steps

1. `az monitor diagnostic-settings list --resource /subscriptions/0190fa7d-4ccf-4e3d-beb1-323b5780bfc8/resourceGroups/SmartFran.Cloud/providers/Microsoft.Web/sites/SFC-PosWasmRelay-DEV --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8` — confirm no pre-existing Diagnostic Settings.
2. `terraform plan` (from `cloud-graylog/terraform/`) — review the diff for `function_app_dev.tf` specifically; decide whether to apply alongside the pending unrelated changes (service_bus_grido, metric blocks) or scope with `-target=azurerm_monitor_diagnostic_setting.poswasmrelay_dev` (and its `data` dependency).
3. `terraform apply` — hand to the user as a copy-paste block, never run directly; needs the destructive-command banner since it writes real Azure state.
4. Post-deploy: once code is eventually deployed to this Function App, confirm a log actually reaches the existing `DEV` Graylog stream.

Jira: `https://smartit-ar.atlassian.net/browse/GITIN-1901` (parent GITIN-1835, per user).

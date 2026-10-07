# Investigation — route PROD Function Apps' console logs to Graylog via Event Hub (GITIN-1914)

**Status:** converged — deployed. Diagnostic Settings live for 3 PROD + 2 DEV targets (`terraform apply`, `gitin-1914.tfplan`, "5 added, 0 changed, 0 destroyed"). **Not closed** — end-to-end delivery unverified (see "Not yet done" below).

## Objective

Add Diagnostic Settings for three PROD Function Apps so their console output reaches Graylog via the existing Event Hub pipeline, same mechanism already applied to the 6 App Service APIs (GITIN-1883/1892/1835) and to `SFC-PosWasmRelay-DEV` (GITIN-1901):

- `SmartFranCloudBusinessFunPro` (+ `-stg` slot, per `cloud/docs/infrastructure.md:37`)
- `SmartFranCloudFunctionsScheduledJobs-pro`
- `SmartFranCloudTicketProcessAsync-pro`

User asked to cover **production and dev, if a dev equivalent exists** for each.

## Context — resolves a discrepancy flagged in a prior ticket

`20260820_azure-functions-to-graylog` (GITIN-1901, this repo) flagged that these three names, documented in `cloud/docs/infrastructure.md:37` as PROD Function Apps, didn't match anything in `az functionapp list` against the **Smart IT - Grido** subscription (`0190fa7d-4ccf-4e3d-beb1-323b5780bfc8`).

That search was scoped wrong for this question, not a doc error: per `cloud/docs/infrastructure.md:4`, PROD SmartFran Cloud resources (including these three, listed under the "Shared App Services" section, RG `SmartFran.Cloud.PRO`) live in the **SmartIT Cloud** subscription (`85c76dea-3304-4310-8656-bf21b28e4f4b`), not Grido. GITIN-1901 only ever queried Grido, because that ticket's own target (`SFC-PosWasmRelay-DEV`) lives there. This ticket queries the correct subscription for the first time.

## Confirmed against live Azure (2026-08-21)

**C1 — PROD (SmartIT Cloud sub, RG `SmartFran.Cloud.PRO`):** all three exist, all `functionapp,linux`, all `Running`. No `-stg` slot returned for `SmartFranCloudBusinessFunPro` by this query (the `-stg` slot mentioned in `infrastructure.md:37` wasn't matched — likely a deployment slot, not a separate Function App resource; not pursued further, out of scope for this ticket which targets the primary PROD apps only).

- `SmartFranCloudBusinessFunPro`
- `SmartFranCloudFunctionsScheduledJobs-pro`
- `SmartFranCloudTicketProcessAsync-pro`

**C2 — Grido sub (RG `SmartFran.Cloud`), filtered to these three names:** confirms DEV exists for two of the three, not the third:

- `SmartFranCloudBusinessFun-DEV` — Running (DEV exists)
- `SmartFranCloudFunctionsScheduledJobs-dev` — Running (DEV exists)
- **No DEV match for TicketProcessAsync.** Only STG-tier resources found: `SFC-TicketProcessAsync-STG` (Stopped, older naming convention) and `SmartFranCloudTicketProcessAsync-stg` (Running). Per user's "dev if exists" scoping, TicketProcessAsync is **PROD-only** for this ticket — no DEV target.
- Other tiers returned (DEV2, STG, TEST for BusinessFun/FunctionsScheduledJobs) are out of scope — user asked for prod + dev only.

Resource IDs (constructed from confirmed subscription/RG/name, standard `Microsoft.Web/sites` pattern — matches what GITIN-1901 confirmed for the same resource type):

| App | Resource ID |
|---|---|
| `SmartFranCloudBusinessFunPro` | `/subscriptions/85c76dea-3304-4310-8656-bf21b28e4f4b/resourceGroups/SmartFran.Cloud.PRO/providers/Microsoft.Web/sites/SmartFranCloudBusinessFunPro` |
| `SmartFranCloudFunctionsScheduledJobs-pro` | `/subscriptions/85c76dea-3304-4310-8656-bf21b28e4f4b/resourceGroups/SmartFran.Cloud.PRO/providers/Microsoft.Web/sites/SmartFranCloudFunctionsScheduledJobs-pro` |
| `SmartFranCloudTicketProcessAsync-pro` | `/subscriptions/85c76dea-3304-4310-8656-bf21b28e4f4b/resourceGroups/SmartFran.Cloud.PRO/providers/Microsoft.Web/sites/SmartFranCloudTicketProcessAsync-pro` |
| `SmartFranCloudBusinessFun-DEV` | `/subscriptions/0190fa7d-4ccf-4e3d-beb1-323b5780bfc8/resourceGroups/SmartFran.Cloud/providers/Microsoft.Web/sites/SmartFranCloudBusinessFun-DEV` |
| `SmartFranCloudFunctionsScheduledJobs-dev` | `/subscriptions/0190fa7d-4ccf-4e3d-beb1-323b5780bfc8/resourceGroups/SmartFran.Cloud/providers/Microsoft.Web/sites/SmartFranCloudFunctionsScheduledJobs-dev` |

Since all five confirmed targets are `functionapp,linux`, the `FunctionAppLogs` category confirmed in GITIN-1901 (for a Linux Function App in the same Grido subscription) is reused here — not independently re-verified via Portal per-app for these five specifically, only inferred from matching resource type/kind.

**C3 — pre-existing Diagnostic Settings check.** First attempt (multi-line command with a `<RESOURCE_ID>` placeholder) failed with a bash syntax error and an `az` usage error, root cause not diagnosed — reissued as single-line commands with real resource IDs substituted. Confirmed 2026-08-21: all 5 targets return empty — no pre-existing Diagnostic Settings, no conflict risk.

## Terraform drafted and applied (2026-08-21)

- `cloud-graylog/terraform/function_app_pro.tf` (new file) — 3 PROD resources, default provider (no alias), `var.resource_group_name` (`SmartFran.Cloud.PRO`), category `FunctionAppLogs`.
- `cloud-graylog/terraform/function_app_dev.tf` (appended, not a new file — keeps all DEV-tier Function Apps together per the file's existing scope) — 2 DEV resources (`businessfun_dev`, `functionsscheduledjobs_dev`), `provider = azurerm.development`, `data.azurerm_resource_group.dev.name`, same category.
- No entry for TicketProcessAsync DEV — confirmed not to exist (see C2 above).

**C4 — `terraform plan` confirmed:** `Plan: 5 to add, 0 to change, 0 to destroy` — scoped via `-target` to the 5 new resources + their data sources, saved to `gitin-1914.tfplan`. Standard `-target` usage warning only.

**C5 — `terraform apply gitin-1914.tfplan` confirmed:** `Apply complete! Resources: 5 added, 0 changed, 0 destroyed.` Standard `-target`-scoped-apply warning only (recommends a follow-up unscoped `terraform plan` to check for other pending changes — not run this session, would surface the pre-existing unrelated drift from GITIN-1901, out of scope here). Diagnostic Settings live for all 3 PROD + 2 DEV targets.

## Not yet done — end-to-end delivery unverified

1. Confirm real messages from each of the 5 resources actually reach Graylog — a successful `apply` only proves the Diagnostic Setting exists, not that data is flowing (same caveat `app_services.tf`'s Business entry documents for VNet-integrated apps).
2. **DEV stream case-sensitivity risk (open):** the existing `DEV` stream's rule (`field: name`, regex `.*-DEV`, per `cloud-graylog/CLAUDE.md`) — not confirmed whether case-sensitive. `SmartFranCloudFunctionsScheduledJobs-dev` has a lowercase `-dev` suffix; if the regex is case-sensitive, this app's messages will reach the Event Hub but land in the Default Stream instead of `DEV` — a misrouting, not a delivery failure. `SmartFranCloudBusinessFun-DEV` (uppercase) is not at risk.
3. Whether PROD messages from these 3 land in the existing PRO stream/index routing or need their own — not yet checked against current PRO stream rules.
4. Optional, not blocking: unscoped `terraform plan` to see current full drift state of the repo (would surface the pre-existing GITIN-1901-flagged items — 16 `metric` block diffs, untracked `service_bus_grido` resource — untouched this session).

Jira: `https://smartit-ar.atlassian.net/browse/GITIN-1914`

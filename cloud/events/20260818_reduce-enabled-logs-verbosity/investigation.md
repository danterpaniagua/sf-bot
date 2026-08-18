# Investigation — reduce enabled_logs verbosity (GITIN-1882, parent GITIN-1835)

**Status:** Closed 2026-08-18 (GITIN-1882). Terraform applied and verified on all 16 resources — Console-only confirmed via `az monitor diagnostic-settings list` per app. Graylog-side volume check and the `cloud-graylog/CLAUDE.md` update (ops.md actions 5–6) remain as follow-up, not blocking closure.

## Objective

Reduce the App Service Diagnostic Settings log categories sent from Azure to the shared Event Hub (and, for 4 apps, also to Log Analytics) — down from the current set to `AppServiceConsoleLogs` only. Requested directly by the user, parent ticket GITIN-1835. Terraform files in scope: `cloud-graylog/terraform/app_services.tf` (PROD) and `cloud-graylog/terraform/app_services_dev.tf` (DEV) — separate repo, `~/Documentos/git/cloud-graylog/`, not part of this monorepo.

## Confirmed facts (read directly from both Terraform files, 2026-08-18)

**PROD (`app_services.tf`) — 8 `azurerm_monitor_diagnostic_setting` resources:**

| Resource | Categories enabled | `log_analytics_workspace_id` present |
|---|---|---|
| `sales` | Console, HTTP, App, Platform (4) | No — Event Hub only |
| `business` | Console, HTTP, App, Platform (4) | No — Event Hub only |
| `pos` | Console, HTTP, App, Platform + 5 audit categories (9) | **Yes** |
| `platform` | Console, HTTP, App, Platform + 5 audit categories (9) | **Yes** |
| `person` | Console, HTTP, App, Platform (4) | No — Event Hub only |
| `admin` | Console, HTTP, App, Platform + 5 audit categories (9) | **Yes** |
| `catalog` | Console, HTTP, App, Platform + 5 audit categories (9) | **Yes** |
| `orders` | Console, HTTP, App, Platform (4) | No — Event Hub only |

**DEV (`app_services_dev.tf`) — 8 resources, all matching the simple 4-category / Event-Hub-only shape:** `sales_dev`, `pos_dev`, `catalog_dev`, `platform_dev`, `admin_dev`, `person_dev`, `business_dev`, `orders_dev`.

## Discrepancy found and resolved with the user

The user's request described the current state as "sending 4 categories" (Console, HTTP, App, Platform) uniformly. That's accurate for 12 of the 16 resources, but **`pos`, `platform`, `admin`, `catalog` (PROD) actually send 9 categories**, and — critically — their `enabled_log` list is shared between the Event Hub *and* `log_analytics_workspace_id` in the same resource block (a single Azure Diagnostic Setting can't have different category sets per destination). That dual destination was deliberately restored on these 4 apps during GITIN-1834, after an earlier Terraform apply had silently overwritten their pre-existing Log Analytics setting (see `bots/cloud/events/20260812_prod-full-onboarding/`).

Trimming these 4 resources to `AppServiceConsoleLogs` only therefore also removes HTTP/App/Platform/audit-log visibility from **Log Analytics**, not just from the Event Hub/Graylog path — a materially larger change than a pure Graylog-verbosity reduction on these 4 apps specifically.

**Asked the user directly; confirmed answer: apply Console-only uniformly across all 16 resources, both destinations included where present (`pos`/`platform`/`admin`/`catalog`).** No split-destination approach, no carve-out — full 16 in scope.

## Planned change

For all 16 `azurerm_monitor_diagnostic_setting` resources across both files, replace the `enabled_log` block set with a single:

```hcl
enabled_log { category = "AppServiceConsoleLogs" }
```

removing `AppServiceHTTPLogs`, `AppServiceAppLogs`, `AppServicePlatformLogs` everywhere, and additionally the 5 audit categories (`AppServiceAntivirusScanAuditLogs`, `AppServiceFileAuditLogs`, `AppServiceAuditLogs`, `AppServiceIPSecAuditLogs`, `AppServiceAuthenticationLogs`) on `pos`/`platform`/`admin`/`catalog`.

**Applied to the Terraform source 2026-08-18** — all 16 resources in `app_services.tf` and `app_services_dev.tf` now have a single `enabled_log { category = "AppServiceConsoleLogs" }` block, each tagged with a `# GITIN-1882` comment. `terraform fmt -check -diff` on both files reports no formatting changes needed. Not yet run through `plan`/`apply` against Azure — that requires Azure credentials/context this session doesn't have; the commands are staged in `scripts.sh` for the user to run. Note: `app_services_dev.tf` shows as untracked (`??`) in `git status`, and `app_services.tf` as modified (`M`) — the untracked-file state on the DEV file predates this change (already flagged in GITIN-1834's investigation as pre-existing uncommitted repo state), not caused by this edit.

## Note worth flagging to whoever approves this (not a blocker, not overriding the confirmed decision)

Per `cloud-graylog/CLAUDE.md` volume findings (measured 2026-06-25, fleet-wide): `AppServiceConsoleLogs` is itself the dominant volume category (70.5% of total), with `AppServiceAppLogs` second (28.0%) and HTTP/Platform together under 1.5%. Catalog specifically was flagged in GITIN-1834 for a 160:1 `AppServiceConsoleLogs`:`AppServiceHTTPLogs` ratio, attributed to console-log verbosity decoupled from real traffic — not a pipeline issue. Keeping only `AppServiceConsoleLogs` while dropping the other categories removes the least-voluminous ~29.5% of current traffic and keeps the most-voluminous category untouched. This may be intentional (Console is presumably the category actually used for debugging), but it's the opposite of what the raw volume numbers alone would suggest for a "reduce verbosity" goal — worth a one-line confirmation from whoever reviews GITIN-1882 that this is the intended trade-off, not just documented here as an assumption.

## Open questions / next steps

- Terraform edit itself not yet made — do in `cloud-graylog/terraform/app_services.tf` and `app_services_dev.tf`.
- `terraform fmt` / `validate` / targeted `plan` before any `apply`, per `cloud-graylog/CLAUDE.md` working guidelines.
- Confirm post-apply that Log Analytics on `pos`/`platform`/`admin`/`catalog` genuinely drops to Console-only as intended (not another full-replace surprise like GITIN-1834's regression) — re-check via `az monitor diagnostic-settings list` per app.
- `cloud-graylog` repo has pre-existing uncommitted state unrelated to this ticket (noted in GITIN-1834 investigation, item 8) — confirm before committing this change on top of it.

# Investigation — send Console/Application/HTTP Logs from all PRO Web Apps to Graylog (GITIN-1937)

**Status:** converged — `ops.md`/`ops-events.md` written, `infrastructure.md` corrected. Terraform applied (2026-08-25) — `Apply complete! Resources: 0 added, 16 changed, 0 destroyed.` Matches the plan exactly (verified via `terraform show -json` before apply — every resource's `after` state had exactly `AppServiceConsoleLogs`/`AppServiceAppLogs`/`AppServiceHTTPLogs`, confirming the 4 drifted PRO apps were trimmed as intended). Remaining open item: the unmanaged duplicate Log Analytics settings on `Business-PRO`/`Person-PRO`/`Sales-PRO` (H3 in `ops.md`) — explicitly out of scope for this ticket, left as a follow-up candidate.

**False-alarm outage investigated and resolved (2026-08-25, same session):** `az monitor metrics list --metric IncomingMessages` on the `smartfran-graylog-evhns-pro` namespace read as flat `0.0` for ~30-48 minutes shortly after `apply` (checked 3 times), and `ThrottledRequests` was flat `0.0` throughout — ruling out capacity throttling as a cause. This looked like a real pipeline outage and reverting the apply was seriously considered. **Confirmed false alarm** via a direct Graylog search (`GET /api/search/universal/relative?query=*&range=1800`): `total_results: 109414` in the same 30-minute window the Event Hub metric claimed was silent, with the most recent message timestamped essentially at query time. Conclusion: the Azure Monitor `IncomingMessages` namespace-level metric has a real reporting lag/reliability quirk for this resource and should **not** be trusted alone for delivery verification going forward — query Graylog directly instead (`api/search/universal/relative`) for any future delivery checks in this project.

Also worth noting, found but not chased further: the same `apply` triggered a `Microsoft.Web/sites` "operation Update — Succeeded" Activity Log entry for all 8 PRO App Services (19:11:33–19:12:20Z), alongside the expected `Microsoft.Insights/diagnosticSettings` writes — likely because `AppServiceHTTPLogs`/`AppServiceAppLogs` are backed by the same legacy site-level logging config as classic App Service Logs, so enabling them via Diagnostic Settings can cause Azure to write the site's config internally (potentially a brief worker restart). Not confirmed as the actual mechanism, and given the Graylog check shows the pipeline healthy, not investigated further — noting only in case it's relevant context for a future ticket.

**New-category delivery confirmed (2026-08-25):** direct Graylog search (`name:SMARTFRAN-CLOUD-BUSINESS-PRO`) returned real, current `AppServiceHTTPLogs`-category messages from `Business-PRO` (Linux) — full HTTP request detail (`CsUriStem`/`CsMethod`/`ScStatus`/etc.), timestamped `2026-08-25T19:41:5x`, well after the apply and the metric false-alarm. This is concrete end-to-end proof the actual change this ticket made (not just the pre-existing pipeline) is delivering. `AppServiceAppLogs` and the other 7 apps not individually re-checked the same way — reasonable to treat as working by extension given the settings are identical in shape and the shared pipeline is confirmed healthy, but noting this isn't independently verified per-app if that matters for ticket closure rigor.

## Objective

For all 8 shared App Services in `SmartFran.Cloud.PRO`, confirm/enable Diagnostic Settings coverage for three categories, routed to the existing Event Hub → Graylog pipeline:

- `AppServiceConsoleLogs`
- `AppServiceAppLogs`
- `AppServiceHTTPLogs`

User confirmed scope: **all** Web Apps (not a subset) — `cloud/events/20260825_webapps-console-app-http-logs-graylog/` chat, 2026-08-25.

**Scope expanded 2026-08-25 (same session):** also cover DEV tier, across both subscriptions (SmartIT Cloud `85c76dea...` and Smart IT - Grido `0190fa7d...`).

## Confirmed live state (2026-08-25) — PRO, SmartIT Cloud subscription

Full output: `pro-diagnostic-settings.json` (local, gitignored). Cross-checked against `cloud-graylog/terraform/app_services.tf`.

**Root cause of the pattern found:** all 8 apps' Terraform config still carries only `enabled_log { category = "AppServiceConsoleLogs" }` (the GITIN-1882 verbosity reduction, never reverted in code). 4 of them (Admin/Platform/Catalog/Pos) additionally declare `log_analytics_workspace_id` in the same resource (GITIN-1834, consolidating a pre-existing out-of-band Log Analytics setting into the Terraform-managed one to stop `apply` from clobbering it). Live Azure state doesn't match this for those 4 — see below.

| App Service | Live: Console | Live: AppLogs | Live: HTTPLogs | vs Terraform | Notes |
|---|---|---|---|---|---|
| `Business-PRO` | ✅ | ❌ | ❌ | matches (Console-only, EventHub-only) | **Plus an unmanaged 2nd setting** (leading-space name typo, workspace `d6ab1add-4bc8-40b0-8cf8-e7291f7171b0` — a 3rd, previously-undocumented subscription/tenant-scope ID) — all 9 categories `true`, points at Log Analytics only, **not** the Graylog Event Hub. Not declared anywhere in Terraform — an out-of-band leftover GITIN-1834 didn't consolidate for this app. |
| `Admin-PRO` | ✅ | ✅ | ✅ | **DRIFT** — Terraform says Console-only, live has 7/9 categories `true` (missing only AntivirusScanAuditLogs, FileAuditLogs) | Single combined setting (EventHub + Log Analytics workspace `85c76dea...`, same sub as the app). A plain `terraform apply` today would revert this to Console-only. |
| `Platform-PRO` | ✅ | ✅ | ✅ | **DRIFT** — Terraform says Console-only, live has **all 9** categories `true` | Same combined-setting pattern, same drift risk. |
| `Person-PRO` | ✅ | ❌ | ❌ | matches | Same unmanaged 2nd setting as Business (all 9 categories `true`, workspace `d6ab1add...`, not routed to Event Hub). |
| `Catalog-PRO` | ✅ | ✅ | ✅ | **DRIFT** — Terraform says Console-only, live has **all 9** categories `true` | Same combined-setting pattern, same drift risk. |
| `Orders-PRO` | ✅ | ❌ | ❌ | matches | Only 1 setting exists at all (matches Terraform comment: "no existing Diagnostic Settings... before this"). No duplicate. |
| `Sales-PRO` | ✅ (config only — **AppServiceConsoleLogs doesn't actually ship data on Windows/.NET**, GITIN-1811) | ❌ | ❌ | matches | Same unmanaged 2nd setting as Business/Person (all 9 categories `true`, workspace `d6ab1add...`). |
| `Pos-PRO` | ✅ (same GITIN-1811 caveat) | ✅ | ✅ | **DRIFT** — Terraform says Console-only, live has 7/9 categories `true` (missing only AntivirusScanAuditLogs, FileAuditLogs) | Single combined setting, same drift risk. |

**Open question, not yet resolved:** `Pos-PRO` has `AppServiceAppLogs: true` live — `infrastructure.md:142` calls this path "unconfirmed... explicitly marked unsupported for ASP.NET Core in the source found." Config existing doesn't prove data flows (same caveat noted in `20260821_functionapps-prod-to-graylog`) — whether real messages are actually landing in Graylog via this category for Pos/Sales is unverified, not assumed either way.

**Decision needed before drafting Terraform changes:** for Admin/Platform/Catalog/Pos, do we (a) codify what's already live by adding the 2 needed categories to Terraform (and decide whether to also formalize or strip the extra audit/platform/authentication categories that are on but were never requested by this ticket), or (b) strictly match ticket scope (Console+AppLogs+HTTPLogs only) and let `apply` trim the others back down? Not deciding this unilaterally — see question to user.

## Confirmed live state (2026-08-25) — DEV, Grido subscription

Full output: `dev-diagnostic-settings.json`. No drift found — live state matches `app_services_dev.tf` exactly for all 8: **`AppServiceConsoleLogs` only**, single Event-Hub-only setting per app, no duplicates.

This contradicts `infrastructure.md:146`'s claim that `AppServiceHTTPLogs` is "confirmed working for `-DEV` (GITIN-1794)" — that was true when GITIN-1794 landed, but GITIN-1882's later verbosity reduction turned it back off for all 8 DEV apps (Sales/Pos included). `infrastructure.md` needs a correction once this ticket closes, not before (avoid rewriting mid-investigation).

**C2 confirmed:** zero `-DEV`-named App Services exist in the SmartIT Cloud subscription (`smartitcloud-dev-scan.json` — empty result). DEV only exists in the Grido subscription, as documented.

**Implication to flag back to the ticket:** `AppServiceConsoleLogs` cannot ship real data for `Sales`/`Pos` (PRO or DEV) regardless of Diagnostic Settings config — platform limitation, root-caused in GITIN-1811, not fixable by this ticket's scope. If the ticket expects uniform 3-category coverage across all apps, Sales/Pos need an explicit call-out that Console is configured-but-inert for them specifically.

## DEV tier — known baseline (from local `~/Documentos/git/cloud-graylog/` repo, not part of this monorepo)

**Grido subscription (`0190fa7d...`), RG `SmartFran.Cloud`:** Diagnostic Settings already exist for all 8 domains (`terraform/app_services_dev.tf`, GITIN-1794) — `sales_dev`, `pos_dev`, `catalog_dev`, `platform_dev`, `admin_dev`, `person_dev`, `business_dev`, `orders_dev`. **Currently scoped to `AppServiceConsoleLogs` only** — every resource block carries an explicit comment: "GITIN-1882 — verbosity reduction: HTTP/App/Platform categories dropped, Console only." This means GITIN-1937 for DEV is **reversing a prior deliberate reduction**, not adding from a blank state — worth flagging on the ticket so whoever requested GITIN-1882's reduction is aware it's being undone.

**SmartIT Cloud subscription (`85c76dea...`):** no DEV-suffixed RG documented anywhere (only `SmartFran.Cloud.PRO` and `SmartFran.Cloud.TEST`). `cloud-graylog/data/webapps.json` (a data snapshot, possibly stale) lists 2 orphaned apps in `SmartFran.Cloud.TEST` — `SmartFran-Cloud-Sales-PRO2` (Brazil South) and `SmartFran-Cloud-Sales-PRO3` (East US 2) — outside the standard 8-domain/East US pattern. Not DEV, not investigated further here. Not assuming "no DEV apps in this subscription" from docs alone — confirming live via `scripts.sh` C2 below.

## Plan

1. ✅ Live-checked current Diagnostic Settings on all 8 PRO App Services — see "Confirmed live state" above.
2. ✅ Confirmed zero `-DEV` App Services in the SmartIT Cloud subscription.
3. ✅ Live-checked current Diagnostic Settings on the 8 Grido-subscription DEV apps — matches Terraform exactly, no drift.
4. ✅ User decision (2026-08-25): for the 4 PRO apps with live drift (Admin/Platform/Catalog/Pos), codify exactly the 3 requested categories in Terraform — `apply` will trim the other live-but-unrequested categories back off, not preserve them.
5. ✅ Terraform edited — `cloud-graylog/terraform/app_services.tf` (all 8 PRO resources) and `app_services_dev.tf` (all 8 DEV resources): added `enabled_log { category = "AppServiceAppLogs" }` and `enabled_log { category = "AppServiceHTTPLogs" }` alongside the existing Console block, replacing each GITIN-1882 comment with a GITIN-1937 one. Not yet planned/applied.
6. Not yet done: `terraform plan`/`apply` (needs user to run — copy-paste, destructive-command banner required for apply). Post-apply: verify real messages actually reach Graylog for the newly-added categories (a successful apply only proves the setting exists, not that data flows — same caveat as every prior ticket in this series).
7. Flag explicitly in the ticket rather than silently handling: (a) Sales/Pos `AppServiceConsoleLogs` platform limitation (PRO and DEV alike, GITIN-1811); (b) DEV's GITIN-1882 reduction being reversed; (c) the unmanaged out-of-band Log Analytics duplicate settings on `Business-PRO`/`Person-PRO`/`Sales-PRO` (workspace sub `d6ab1add-4bc8-40b0-8cf8-e7291f7171b0`, previously undocumented) — not touched, flagged as a separate cleanup candidate, not in this ticket's scope; (d) `infrastructure.md` needs a correction for the stale "`AppServiceHTTPLogs` confirmed working for DEV" claim — do at ticket close, not now.

**Note on `cloud-graylog` repo state:** that repo (separate from this monorepo) has substantial pre-existing uncommitted changes unrelated to this ticket (`CLAUDE.md`, `docs/architecture.md`, `main.tf`, `network.tf`, several `operations/events/` files, stray `terraform/sarasa*.txt`, multiple `.tfplan` binaries) — not touched, not this ticket's concern, but means `git diff --stat` there is noisy and `terraform/app_services_dev.tf` itself is untracked (never committed) even though the resources it defines were already applied in GITIN-1794. Don't commit anything in that repo as part of this ticket unless separately asked.

Jira: `https://smartit-ar.atlassian.net/browse/GITIN-1937`

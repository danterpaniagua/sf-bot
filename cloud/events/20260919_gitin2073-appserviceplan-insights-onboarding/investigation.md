# Investigation — 20260919_gitin2073-appserviceplan-insights-onboarding

**Status:** SFD (Jira state as stated by the user on 2026-10-05) — scope defined, change not executed.
**Jira ticket:** [GITIN-2073](https://smartit-ar.atlassian.net/browse/GITIN-2073)

## Scope

- Original (user, 2026-09-19): connect App Service Plan(s) to Insights to add alerts.
- Current (user, 2026-10-05): send the App Service Plans to Insights — wiring only; alerts are not in scope.
- Decisions left as proposed (user, 2026-10-05, "leave as is"): all 9 Plans in `SmartFran.Cloud.PRO` (including the Linux Functions plan `SFC-FunctionAPP-Linux-Plan-PRO`); destination Log Analytics workspace `SmartFranCloudPro`; Diagnostic Setting name `plan-allmetrics-to-SmartFranCloudPro`.

## Background

Grew out of `cloud/events/20260918_sales-cpu-live-metrics-discrepancy/`, which confirmed that `Sales_CPU_Alert` (Azure Monitor Metric Alert scoped to `SmartFran-Cloud-Sales-Plan-PRO`, metric `CpuPercentage`) is real and correctly configured — Metric Alerts read the platform metric store directly and do not depend on Diagnostic Settings to fire — while the Sales Plan resource (`Microsoft.Web/serverfarms`) had zero Diagnostic Settings. A check against the `cloud-graylog` repo (authoritative source for Graylog onboarding, GITIN-1834, 2026-08-12) found no Terraform resource or documentation that targets an App Service Plan: only the 8 App Services and 4 Function Apps are onboarded to the Event Hub → Graylog pipeline. Plan-level host metrics appear never to have been routed anywhere.

## Confirmed facts

All from this investigation's data files (`data/`), RG `SmartFran.Cloud.PRO`, subscription SmartIT Cloud (`85c76dea-3304-4310-8656-bf21b28e4f4b`).

1. **No Plan has any Diagnostic Setting — fleet-wide.** All 9 Plans return 0 settings, checked 2026-10-05 (`data/diagsettings_plan_*_oct5.json`): Pos, Sales, Platform, Business, Person, Admin, Catalog, Orders, and `SFC-FunctionAPP-Linux-Plan-PRO`. SKUs: Sales P1v3, all others P0v3 (`data/plans_now_oct5.json`).
2. **"Connect a Plan to Insights" is not a literal Azure operation.** App Insights components attach to a Site's instrumentation key; there is no Plan-level component. The mechanism for Plan host metrics is a Diagnostic Setting on the Plan.
3. **A Plan can send exactly one thing: `AllMetrics`.** The Sales Plan's Diagnostic Settings categories are one entry, `AllMetrics` (type Metrics), no log categories (`data/diag_categories_sales_plan_oct5.json`).
4. **Single destination candidate.** The RG has one Log Analytics workspace, `SmartFranCloudPro` (eastus, `pergb2018`, 30 days retention, no daily ingestion cap — `workspaceCapping.dailyQuotaGb` -1; tag `SF.Scope: Monitoreo`), which also receives Sales-PRO's Site-level Diagnostic Setting (`20260915_sales-appservice-perf-report/investigation.md`) (`data/loganalytics_workspaces_list_oct5.json`).
5. **App Insights components in the RG:** 17, all `IngestionMode` `LogAnalytics` (workspace-based) (`data/appinsights_components_workspace_oct5.json`). Which workspace each one points to is **not known**: the `workspaceResourceId` field came back null in the query used, which is an artifact of the query (a workspace-based component necessarily has a workspace), not evidence of no link. No component exists for any Plan, nor for `SFC-PosWasmRelay-PRO`; Business has only the legacy `SmartFran-Cloud-Business-PRO_Insights` while `docs/infrastructure.md` documents `SmartFran-Cloud-Business-PRO_new` as active (a gap unrelated to Plans, not pursued).
6. **No Diagnostic Setting write on any Plan** appears in the Activity Log events retrieved (Sep 19 → Oct 5); the only diagnostic-settings writes are on Redis (Sep 29 16:14Z) and a Cosmos account (Oct 1 11:37Z). Coverage limit: one-day pulls hit the 1000-event cap on Sep 21, 22, 23, 24, 28, 29 and 30 and only cover the later part of those days (earliest event retrieved: Sep 21 19:51Z, Sep 22 19:28Z, Sep 23 20:00Z, Sep 24 17:28Z, Sep 28 17:19Z, Sep 29 05:48Z, Sep 30 09:51Z; `data/activitylog_daily_counts_oct5.txt`); absence of an event in the earlier hours of those days is not evidence of absence.

## Planned change (not executed)

For each of the 9 Plans create a Diagnostic Setting `plan-allmetrics-to-SmartFranCloudPro` with `AllMetrics` enabled, destination workspace `SmartFranCloudPro`. Safeguards in the apply block: abort with no change if the workspace is missing, if the Plan list differs from the expected 9, or if any Plan already has a Diagnostic Setting; a before-snapshot is taken; an after-check requires on every Plan exactly one matching setting with `AllMetrics` enabled and the right workspace. Rollback deletes only that setting by exact name. Metrics land in the workspace's `AzureMetrics` table. Ingestion is billed per GB and the workspace has no daily cap; the volume of Plan platform metrics was not estimated.

## Context outside this ticket's scope (Plans and alerting)

Kept because it affects how the wiring will be used; alerts are not part of this ticket.

- **Autoscale.** The earlier "`DividePerInstance: false` is the problem" conclusion (2026-09-19) was retracted on 2026-09-21: Microsoft documents `false` as correct for an Average-aggregated metric such as `CpuPercentage` (`20260918_sales-cpu-live-metrics-discrepancy/investigation.md`); the dilution of a single hot instance in a Plan-wide average is expected behavior. Compared with the Sales autoscale snapshot of Sep 19 14:42 ART (`data/autoscale_full_settings_sales_plan.json` vs `data/autoscale_settings_list_oct5.json`): the weekday fixed profile went from 2/2/2 at 12:00 ART to 3/3/3 at 11:00 ART, and the weekend profile and default weekend profile changed timezone from UTC to Argentina Standard Time (weekend profile still 3/3/3 at 15:00); the default profile is still 1/4/1, so the higher floor comes from scheduled profiles, not from `Capacity.Minimum`. User writes to the Sales autoscale setting appear in the Activity Log on Sep 19 02:29Z, Sep 19 18:06Z and Sep 21 22:26Z (which write caused which difference is not determined). Business has scheduled 2/2/2 profiles over a 1/4/1 default; Orders is fixed 4/4/4 (4 instances); the other Plans are 1/4/1 with 1 instance.
- **Existing Plan-level metric alerts (22 rules in the RG on Oct 5 10:15 ART, `data/metric_alerts_list_oct5.json`):** `CpuPercentage`/`MemoryPercentage` > 80 (Average, severity 2) exist for 3 of the 9 Plans — Sales, Business and Orders — and for none of Pos, Platform, Person, Admin, Catalog or the Functions plan. `PRO_Business_Memory_Alert` and `PRO_Orders_Memory_Alert` have no action group (raw `actions: []`), as do the site health-check alerts `PRO-Orders-HealthCheck-Error` and `PRO-POS-HealthCheck-Error`; `Sales_CPU_Alert` uses action group `Correos-Cloud` (1 email receiver), the others use `AG-SmartFran-PRO-Alerts` (4 email receivers); both groups are email-only (`data/actiongroup_*_oct5.json`, counts only). An alert with no action group fires in Azure Monitor but notifies nobody. These alerts were created on Sep 19 12:21Z–13:20Z (users); the action group was edited on Sep 30 and Oct 2.
- **Plan writes:** two `serverfarms/write` by a user on the Sales Plan on Sep 20 02:18:56Z and 02:28:54Z (matching the GITIN-2084 CPU windows); the other 173 `serverfarms/write` events in the retrieved range come from the autoscale service.

## Open questions

1. Which workspace each App Insights component points to (raw ARM `properties.WorkspaceResourceId`), to confirm that Plan metrics land in the same workspace as the app telemetry.
2. Whether 30 days retention on `SmartFranCloudPro` is enough for the Plan metrics, and the expected added ingestion cost (workspace has no daily cap).
3. After the change is applied: confirm `AzureMetrics` receives rows for each of the 9 Plans (e.g. a query on `ResourceProvider == "MICROSOFT.WEB"` filtered by Plan name), since a created Diagnostic Setting alone does not prove data arrives.
4. Whether the Business App Insights gap (`_new` component absent) should be raised separately.

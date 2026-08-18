#!/usr/bin/env bash
# Event: 20260818_reduce-enabled-logs-verbosity (GITIN-1882, parent GITIN-1835)
# C1 has been run (terraform fmt -check, clean). C2 onward still pending —
# require Azure credentials this session doesn't have. Commands are grouped
# by phase: Validation / Remediation / Verification.
# ⚠️ ACTION commands are clearly marked.

# === VALIDATION (run from cloud-graylog/terraform/) ===
# C1 — fmt-check the two edited files — RUN 2026-08-18, exit 0, no diff
terraform fmt -check -diff app_services.tf app_services_dev.tf

# C1b — validate (not yet run — requires `terraform init` / provider state)
terraform validate

# C2 — plan scoped to the 16 affected resources (PROD) — not yet run
terraform plan \
  -target=azurerm_monitor_diagnostic_setting.sales \
  -target=azurerm_monitor_diagnostic_setting.business \
  -target=azurerm_monitor_diagnostic_setting.pos \
  -target=azurerm_monitor_diagnostic_setting.platform \
  -target=azurerm_monitor_diagnostic_setting.person \
  -target=azurerm_monitor_diagnostic_setting.admin \
  -target=azurerm_monitor_diagnostic_setting.catalog \
  -target=azurerm_monitor_diagnostic_setting.orders

# C3 — plan scoped to the 8 DEV resources
terraform plan \
  -target=azurerm_monitor_diagnostic_setting.sales_dev \
  -target=azurerm_monitor_diagnostic_setting.pos_dev \
  -target=azurerm_monitor_diagnostic_setting.catalog_dev \
  -target=azurerm_monitor_diagnostic_setting.platform_dev \
  -target=azurerm_monitor_diagnostic_setting.admin_dev \
  -target=azurerm_monitor_diagnostic_setting.person_dev \
  -target=azurerm_monitor_diagnostic_setting.business_dev \
  -target=azurerm_monitor_diagnostic_setting.orders_dev

# === REMEDIATION (only after C1-C3 plans show exactly "16 changed, 0 added, 0 destroyed") ===
# ⚠️ C4 — apply the reduced enabled_log sets (all 16 resources, same -target list as C2+C3 combined)
# terraform apply -target=... (repeat all 16 -target flags from C2/C3)

# === VERIFICATION (per app, PROD and DEV subscriptions respectively) ===
# C5 — confirm each Diagnostic Setting now has exactly one enabled_log category
az monitor diagnostic-settings list \
  --resource "/subscriptions/85c76dea-3304-4310-8656-bf21b28e4f4b/resourceGroups/SmartFran.Cloud.PRO/providers/Microsoft.Web/sites/<AppName>-PRO" \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  -o json

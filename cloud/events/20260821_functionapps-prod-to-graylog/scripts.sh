#!/usr/bin/env bash
# Event: 20260821_functionapps-prod-to-graylog (GITIN-1914)
# Commands grouped by phase: Investigation / Terraform (repo cloud-graylog/terraform/)
# Commands marked ⚠️ modify real state (Azure)

SMARTIT_CLOUD_SUB="85c76dea-3304-4310-8656-bf21b28e4f4b"   # PROD SmartFran Cloud
GRIDO_SUB="0190fa7d-4ccf-4e3d-beb1-323b5780bfc8"           # Non-prod SmartFran Cloud + SmartLoyalty prod

# === INVESTIGATION ===

# C1 — confirm the three PROD Function Apps exist in SmartIT Cloud sub, capture id/kind/state
az functionapp list \
  --subscription "$SMARTIT_CLOUD_SUB" \
  --query "[?contains(name, 'SmartFranCloudBusinessFunPro') || contains(name, 'SmartFranCloudFunctionsScheduledJobs') || contains(name, 'SmartFranCloudTicketProcessAsync')].{name:name, resourceGroup:resourceGroup, state:state, kind:kind, id:id}" \
  -o table
# Result: all three confirmed — SmartFranCloudBusinessFunPro, SmartFranCloudFunctionsScheduledJobs-pro,
# SmartFranCloudTicketProcessAsync-pro — RG SmartFran.Cloud.PRO, functionapp,linux, Running.

# C2 — search Grido sub for DEV equivalents of these three specific apps (GITIN-1901's full listing
# didn't check for these by name — it was hunting -pro suffixes)
az functionapp list \
  --subscription "$GRIDO_SUB" \
  --query "[?contains(name, 'BusinessFun') || contains(name, 'FunctionsScheduledJobs') || contains(name, 'TicketProcessAsync')].{name:name, resourceGroup:resourceGroup, state:state, kind:kind, id:id}" \
  -o table
# Result: DEV exists for BusinessFun (SmartFranCloudBusinessFun-DEV) and FunctionsScheduledJobs
# (SmartFranCloudFunctionsScheduledJobs-dev). NOT for TicketProcessAsync — only STG-tier resources
# found (SFC-TicketProcessAsync-STG, SmartFranCloudTicketProcessAsync-stg) — TicketProcessAsync is
# PROD-only for this ticket. Other tiers returned (DEV2/STG/TEST) out of scope.

# C3 — check pre-existing Diagnostic Settings on each of the 5 confirmed in-scope targets
az monitor diagnostic-settings list --subscription "$SMARTIT_CLOUD_SUB" --resource "/subscriptions/$SMARTIT_CLOUD_SUB/resourceGroups/SmartFran.Cloud.PRO/providers/Microsoft.Web/sites/SmartFranCloudBusinessFunPro" -o table

az monitor diagnostic-settings list --subscription "$SMARTIT_CLOUD_SUB" --resource "/subscriptions/$SMARTIT_CLOUD_SUB/resourceGroups/SmartFran.Cloud.PRO/providers/Microsoft.Web/sites/SmartFranCloudFunctionsScheduledJobs-pro" -o table

az monitor diagnostic-settings list --subscription "$SMARTIT_CLOUD_SUB" --resource "/subscriptions/$SMARTIT_CLOUD_SUB/resourceGroups/SmartFran.Cloud.PRO/providers/Microsoft.Web/sites/SmartFranCloudTicketProcessAsync-pro" -o table

az monitor diagnostic-settings list --subscription "$GRIDO_SUB" --resource "/subscriptions/$GRIDO_SUB/resourceGroups/SmartFran.Cloud/providers/Microsoft.Web/sites/SmartFranCloudBusinessFun-DEV" -o table

az monitor diagnostic-settings list --subscription "$GRIDO_SUB" --resource "/subscriptions/$GRIDO_SUB/resourceGroups/SmartFran.Cloud/providers/Microsoft.Web/sites/SmartFranCloudFunctionsScheduledJobs-dev" -o table
# Result: all 5 empty — no pre-existing Diagnostic Settings, clear to draft Terraform.

# === TERRAFORM (repo cloud-graylog/terraform/) ===
# function_app_pro.tf (new, 3 PROD resources) + function_app_dev.tf (appended, 2 DEV resources)
# drafted 2026-08-21, following the function_app_dev.tf pattern established in GITIN-1901.

# C4 — plan scoped to only the 5 new resources (+ their data sources), to avoid
# mixing in the pre-existing unrelated drift flagged in GITIN-1901 (16 metric
# block diffs, untracked service_bus_grido resource)
cd ~/Documentos/git/cloud-graylog/terraform
terraform plan \
  -target=data.azurerm_linux_function_app.businessfun_pro \
  -target=azurerm_monitor_diagnostic_setting.businessfun_pro \
  -target=data.azurerm_linux_function_app.functionsscheduledjobs_pro \
  -target=azurerm_monitor_diagnostic_setting.functionsscheduledjobs_pro \
  -target=data.azurerm_linux_function_app.ticketprocessasync_pro \
  -target=azurerm_monitor_diagnostic_setting.ticketprocessasync_pro \
  -target=data.azurerm_linux_function_app.businessfun_dev \
  -target=azurerm_monitor_diagnostic_setting.businessfun_dev \
  -target=data.azurerm_linux_function_app.functionsscheduledjobs_dev \
  -target=azurerm_monitor_diagnostic_setting.functionsscheduledjobs_dev \
  -out=gitin-1914.tfplan
# Result: Plan: 5 to add, 0 to change, 0 to destroy. Saved to gitin-1914.tfplan.

# ⚠️ C5 — apply the saved plan (writes real Azure state)
terraform apply gitin-1914.tfplan
# Result: Apply complete! Resources: 5 added, 0 changed, 0 destroyed.

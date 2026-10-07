#!/usr/bin/env bash
# Event: 20260825_webapps-console-app-http-logs-graylog (GITIN-1937)
# Commands grouped by phase: Investigation
# PRO apps: SmartFran.Cloud.PRO, SmartIT Cloud subscription.
# DEV apps: SmartFran.Cloud, Smart IT - Grido subscription.

SMARTIT_CLOUD_SUB="85c76dea-3304-4310-8656-bf21b28e4f4b"   # PROD SmartFran Cloud
GRIDO_SUB="0190fa7d-4ccf-4e3d-beb1-323b5780bfc8"           # Non-prod SmartFran Cloud + SmartLoyalty prod

# === INVESTIGATION ===
# Output redirected to local .json files (gitignored, see repo root .gitignore) —
# too large for chat paste-back, Claude reads the files directly instead.

OUT_DIR="$(dirname "$0")"

# C1 — current Diagnostic Settings on all 8 shared PRO App Services (read-only)
: > "$OUT_DIR/pro-diagnostic-settings.json"
for APP in SmartFran-Cloud-Business-PRO SmartFran-Cloud-Admin-PRO SmartFran-Cloud-Platform-PRO \
           SmartFran-Cloud-Person-PRO SmartFran-Cloud-Catalog-PRO SmartFran-Cloud-Orders-PRO \
           SmartFran-Cloud-Sales-PRO SmartFran-Cloud-Pos-PRO; do
  echo "=== $APP ===" >> "$OUT_DIR/pro-diagnostic-settings.json"
  az monitor diagnostic-settings list \
    --subscription "$SMARTIT_CLOUD_SUB" \
    --resource "/subscriptions/$SMARTIT_CLOUD_SUB/resourceGroups/SmartFran.Cloud.PRO/providers/Microsoft.Web/sites/$APP" \
    -o json >> "$OUT_DIR/pro-diagnostic-settings.json"
done

# C2 — confirm no "-DEV" App Service exists in the SmartIT Cloud subscription (docs say no; verifying live)
az webapp list \
  --subscription "$SMARTIT_CLOUD_SUB" \
  --query "[?contains(name, '-DEV') || contains(name, '-dev')].{name:name, resourceGroup:resourceGroup, location:location, kind:kind}" \
  -o table > "$OUT_DIR/smartitcloud-dev-scan.json"

# C3 — current Diagnostic Settings on the 8 known Grido-subscription DEV App Services (read-only)
# Expected AppServiceConsoleLogs only, per app_services_dev.tf's GITIN-1882 comment — confirming live.
: > "$OUT_DIR/dev-diagnostic-settings.json"
for APP in SmartFran-Cloud-Business-DEV SmartFran-Cloud-Admin-DEV SmartFran-Cloud-Platform-DEV \
           SmartFran-Cloud-Person-DEV SmartFran-Cloud-Catalog-DEV SmartFran-Cloud-Orders-DEV \
           SmartFran-Cloud-Sales-DEV SmartFran-Cloud-Pos-DEV; do
  echo "=== $APP ===" >> "$OUT_DIR/dev-diagnostic-settings.json"
  az monitor diagnostic-settings list \
    --subscription "$GRIDO_SUB" \
    --resource "/subscriptions/$GRIDO_SUB/resourceGroups/SmartFran.Cloud/providers/Microsoft.Web/sites/$APP" \
    -o json >> "$OUT_DIR/dev-diagnostic-settings.json"
done

echo "Done. Files written under $OUT_DIR:"
echo "  pro-diagnostic-settings.json"
echo "  smartitcloud-dev-scan.json"
echo "  dev-diagnostic-settings.json"

# === REMEDIATION ===
# Terraform edits made directly in ~/Documentos/git/cloud-graylog/terraform/
# (app_services.tf — 8 PRO resources; app_services_dev.tf — 8 DEV resources):
# added enabled_log blocks for AppServiceAppLogs and AppServiceHTTPLogs
# alongside the existing AppServiceConsoleLogs block, on all 16 resources.

# C4 — plan scoped to only the 16 diagnostic-setting resources touched by this ticket
cd ~/Documentos/git/cloud-graylog/terraform
terraform plan \
  -target=azurerm_monitor_diagnostic_setting.sales \
  -target=azurerm_monitor_diagnostic_setting.business \
  -target=azurerm_monitor_diagnostic_setting.pos \
  -target=azurerm_monitor_diagnostic_setting.platform \
  -target=azurerm_monitor_diagnostic_setting.person \
  -target=azurerm_monitor_diagnostic_setting.admin \
  -target=azurerm_monitor_diagnostic_setting.catalog \
  -target=azurerm_monitor_diagnostic_setting.orders \
  -target=azurerm_monitor_diagnostic_setting.sales_dev \
  -target=azurerm_monitor_diagnostic_setting.pos_dev \
  -target=azurerm_monitor_diagnostic_setting.catalog_dev \
  -target=azurerm_monitor_diagnostic_setting.platform_dev \
  -target=azurerm_monitor_diagnostic_setting.admin_dev \
  -target=azurerm_monitor_diagnostic_setting.person_dev \
  -target=azurerm_monitor_diagnostic_setting.business_dev \
  -target=azurerm_monitor_diagnostic_setting.orders_dev \
  -out=gitin-1937.tfplan
# Result: Plan: 0 to add, 16 to change, 0 to destroy.

# C5 — uncollapsed JSON plan, to verify exact after-state per resource (human-readable
# plan collapses "unchanged" blocks, hiding whether drifted categories get trimmed)
terraform show -json gitin-1937.tfplan > gitin1937-plan-full.json
# Result: every resource's `after.enabled_log` = exactly AppServiceAppLogs/
# AppServiceConsoleLogs/AppServiceHTTPLogs, confirming the 4 drifted PRO apps
# (admin/platform/catalog/pos) get trimmed back to the 3 requested categories.

# ⚠️ C6 — apply
terraform apply gitin-1937.tfplan
# Result: Apply complete! Resources: 0 added, 16 changed, 0 destroyed.

# === VALIDATION ===

# C7 — re-check Business-PRO's Diagnostic Setting post-apply (confirm healthy, not errored)
az monitor diagnostic-settings list \
  --subscription "$SMARTIT_CLOUD_SUB" \
  --resource "/subscriptions/$SMARTIT_CLOUD_SUB/resourceGroups/SmartFran.Cloud.PRO/providers/Microsoft.Web/sites/SmartFran-Cloud-Business-PRO" \
  -o json
# Result: exactly AppServiceConsoleLogs/AppServiceAppLogs/AppServiceHTTPLogs = true, rest false. Healthy.

# C8 — Event Hub ingress metric (checked 3x post-apply; produced a false-alarm zero
# reading for ~30-48 min — see investigation.md, do not trust this metric alone)
az monitor metrics list \
  --subscription "$SMARTIT_CLOUD_SUB" \
  --resource "/subscriptions/$SMARTIT_CLOUD_SUB/resourceGroups/SmartFran.Cloud.PRO/providers/Microsoft.EventHub/namespaces/smartfran-graylog-evhns-pro" \
  --metric IncomingMessages \
  --interval PT5M \
  --start-time "$(date -u -d '-30 minutes' +%Y-%m-%dT%H:%M:%SZ)" \
  -o table

# C9 — Event Hub throttling metric (ruled out throttling as the cause of the false-alarm zero)
az monitor metrics list \
  --subscription "$SMARTIT_CLOUD_SUB" \
  --resource "/subscriptions/$SMARTIT_CLOUD_SUB/resourceGroups/SmartFran.Cloud.PRO/providers/Microsoft.EventHub/namespaces/smartfran-graylog-evhns-pro" \
  --metric ThrottledRequests \
  --interval PT5M \
  --start-time "$(date -u -d '-40 minutes' +%Y-%m-%dT%H:%M:%SZ)" \
  -o table
# Result: flat 0.0 throughout — throttling ruled out.

# C10 — Activity Log for the RG around the apply window (checked for any other
# concurrent change that could explain the false-alarm zero reading)
az monitor activity-log list \
  --subscription "$SMARTIT_CLOUD_SUB" \
  --resource-group SmartFran.Cloud.PRO \
  --start-time "$(date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%SZ)" \
  -o table
# Result: only this ticket's own Microsoft.Insights/diagnosticSettings writes and a
# paired Microsoft.Web/sites "operation Update" per app (side effect of enabling
# AppServiceHTTPLogs/AppServiceAppLogs, not investigated further) — nothing else changed.

# C11 — direct Graylog message-count check, last 30 min, all sources (the check that
# actually disproved the false-alarm outage — Event Hub metric said 0, Graylog itself
# showed real, current traffic)
curl -s -u "$GRAYLOG_API_KEY:token" \
  "https://sfcloud-monitoreo.smartfran.com/graylog/api/search/universal/relative?query=*&range=1800&limit=1" \
  -H "Accept: application/json" | python3 -m json.tool
# Result: total_results: 109414, most recent message at query time.

# C12 — direct Graylog search for the new AppServiceHTTPLogs category specifically,
# from Business-PRO (Linux) — end-to-end proof of this ticket's actual change delivering
curl -s -u "$GRAYLOG_API_KEY:token" \
  "https://sfcloud-monitoreo.smartfran.com/graylog/api/search/universal/relative?query=name%3ASMARTFRAN-CLOUD-BUSINESS-PRO&range=900&limit=5" \
  -H "Accept: application/json" | python3 -m json.tool
# Result: real, current AppServiceHTTPLogs messages (CsUriStem/CsMethod/ScStatus/etc.),
# timestamped ~19:41Z, confirming delivery.

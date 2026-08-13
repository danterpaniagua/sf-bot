#!/usr/bin/env bash
# Event: 20260810_sales-serilog-console-logs (GITIN-1811)
# All read-only. Commands are grouped by phase.
#
# CORRECTION (2026-08-11): this ticket originally assumed Sales-PRO
# (subscription SmartIT Cloud, RG SmartFran.Cloud.PRO). Confirmed with the
# user that every command below actually targeted Sales-DEV all along
# (subscription Smart IT - Grido, RG SmartFran.Cloud) — same environment
# onboarded to Graylog in GITIN-1794. Corrected below.

SUB="0190fa7d-4ccf-4e3d-beb1-323b5780bfc8"   # Smart IT - Grido
RG="SmartFran.Cloud"                          # DEV — not SmartFran.Cloud.PRO

# === INVESTIGATION ===

# C1 — Application Logging (Filesystem) config for Sales-DEV — the legacy/
# simpler site-level setting that gates whether ANCM's stdout capture (if
# enabled) actually reaches AppServiceConsoleLogs. Separate from Diagnostic
# Settings.
az webapp log show --name SmartFran-Cloud-Sales-DEV --resource-group "$RG" --subscription "$SUB" -o json

# C2 — Same, for Business-DEV — comparison baseline (known working).
az webapp log show --name SmartFran-Cloud-Business-DEV --resource-group "$RG" --subscription "$SUB" -o json

# C3 — App settings filtered to logging-related keys only (avoids dumping
# unrelated secrets/connection strings into output).
az webapp config appsettings list --name SmartFran-Cloud-Sales-DEV --resource-group "$RG" --subscription "$SUB" \
  --query "[?contains(name, 'LOG') || contains(name, 'ANCM') || contains(name, 'STDOUT')]" -o table

# C4 — Live web.config on the Sales-DEV App Service (Kudu VFS, AAD-token auth
# — avoids fetching/exposing publishing-credentials password). Looking
# specifically for stdoutLogEnabled on the <aspNetCore> element.
TOKEN=$(az account get-access-token --resource https://management.azure.com/ --query accessToken -o tsv)
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://smartfran-cloud-sales-dev.scm.azurewebsites.net/api/vfs/site/wwwroot/web.config"

# === REMEDIATION ===

# ⚠️ C5 — RUN, 2026-08-11. Enabled fileSystem application logging (fixed H4)
# and cleared the broken azureBlobStorage config (H8) in the same call —
# confirmed post-run: fileSystem.level "Information", azureBlobStorage.level "Off".
az webapp log config --name SmartFran-Cloud-Sales-DEV --resource-group "$RG" --subscription "$SUB" \
  --application-logging filesystem --level information

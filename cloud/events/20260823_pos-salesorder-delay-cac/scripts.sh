#!/usr/bin/env bash
# Event: 20260823_pos-salesorder-delay-cac (GITIN-1917)
# Commands are grouped by phase: Investigation
# No remediation commands — this event closes with a dev handoff, no Azure-side state change.

SUB=85c76dea-3304-4310-8656-bf21b28e4f4b   # SmartIT Cloud (PRO)
RG=SmartFran.Cloud.PRO

# === INVESTIGATION ===

# C1 — resolver tenant CAC/Canning contra el App Configuration `organizations` (bloqueado, ver H5)
az appconfig kv show --name SmartFran-Cloud-Settings-PRO --auth-mode login \
  --key organizations --subscription "$SUB" --output json

# C2 — confirmar el gap de permisos vía REST directo (bypass del bug de la CLI)
ENDPOINT=$(az appconfig show --name SmartFran-Cloud-Settings-PRO --resource-group "$RG" --subscription "$SUB" --query endpoint -o tsv)
TOKEN=$(az account get-access-token --resource https://azconfig.io --query accessToken -o tsv)
curl -s -i -H "Authorization: Bearer $TOKEN" "$ENDPOINT/kv?key=organizations&api-version=2023-11-01"

# C3 — App Insights: intento inicial de requests SaleOrder/pay (vacío — ver H4, gap de sampling)
az monitor app-insights query \
  --app SmartFran-Cloud-Sales-PRO_new -g "$RG" --subscription "$SUB" \
  --analytics-query "requests | where timestamp > ago(24h) and name has 'SaleOrder' and name has 'pay' | project timestamp, name, duration, resultCode, operation_Id, cloud_RoleInstance | order by duration desc | take 50" \
  --output table

# C4 — App Service Sales-PRO: métricas de plataforma (HttpResponseTime/Requests/Http5xx), 2026-08-22
az monitor metrics list \
  --resource "/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Web/sites/SmartFran-Cloud-Sales-PRO" \
  --metric "HttpResponseTime" "Requests" "Http5xx" \
  --aggregation Average Maximum Total \
  --interval PT15M \
  --start-time "2026-08-22T13:00:00Z" --end-time "2026-08-22T23:59:00Z" \
  --output json

# C5 — CosmosDB: verificación de throttling (429) en la cuenta compartida, mismo período (resultado: cero)
az monitor metrics list \
  --resource "/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.DocumentDB/databaseAccounts/smartfran-cloud-cosmos-platform-pro" \
  --metric "TotalRequests" --filter "StatusCode eq '429'" --aggregation Total --interval PT15M \
  --start-time "2026-08-22T13:00:00Z" --end-time "2026-08-22T23:59:00Z" --output json

# C6 — Log Analytics workspace (SmartFranCloudPro): desglose real por operación (AppRequests nativo,
# bypass del gap de la API de compatibilidad de App Insights — ver H4)
WORKSPACE_ID=$(az monitor log-analytics workspace show \
  --resource-group "$RG" --workspace-name SmartFranCloudPro --subscription "$SUB" --query customerId -o tsv)
az monitor log-analytics query \
  --workspace "$WORKSPACE_ID" \
  --analytics-query "AppRequests | where TimeGenerated between (datetime(2026-08-22T13:00:00Z) .. datetime(2026-08-22T23:59:00Z)) and AppRoleName == 'smartfran-cloud-sales-pro' | summarize count(), avg(DurationMs), max(DurationMs) by Name | order by max_DurationMs desc" \
  --output table

# C7 — verificación de rama: repo local estaba en dev, 181 commits detrás de main (real PRO)
git fetch origin && git checkout main && git pull --ff-only origin main
git diff origin/dev origin/main --stat -- \
  Source/Services/Sales/SmartFran.Cloud.Sales.Application/Services/SaleService.cs \
  Source/Services/Sales/SmartFran.Cloud.Sales.Application/Services/SaleClose/StockMovementCreator.cs

# C8 — análisis de dos capturas HAR reales (navegador, terminal POS real de Canning) —
# entrega/timing por request, ventana de silencio de red, y correlación con la ráfaga de assets
# posterior al Sale/Close (logo/fuentes/LogoTicket) — análisis local, sin llamadas a Azure
python3 -c "import json; d=json.load(open('weiss.pos.smartfran.com.har')); print(len(d['log']['entries']))"

# === LECTURA DE CÓDIGO FUENTE (repo/SmartFran.Cloud, verificado contra origin/main) ===
# No son comandos de diagnóstico contra Azure — trazado del código cliente POS que confirma
# la causa raíz. Ver investigation.md para el detalle completo con líneas de archivo.
# - Sale.razor.cs: SaleCloseAsync se despacha fire-and-forget (nunca se espera)
# - Sale.razor.cs: PrintOrderIfNeeded() se ejecuta incondicionalmente en todo cierre de venta
# - Sale.razor.cs:Print() -> _js.InvokeAsync("window.getBase64", ...)
# - clientPrint.js: getBase64() usa html2canvas con useCORS:true, logging:true, sin timeout

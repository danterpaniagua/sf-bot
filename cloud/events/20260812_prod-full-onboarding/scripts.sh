#!/usr/bin/env bash
# Event: 20260812_prod-full-onboarding (GITIN-1834)
# Terraform commands run in a SEPARATE repo (~/Documentos/git/cloud-graylog/terraform/),
# noted inline. Graylog API commands run against https://sfcloud-monitoreo.smartfran.com/graylog/api
# (separate SmartCloud-dedicated instance, not the Docker stack). Commands grouped by phase.
# ⚠️ ACTION commands are clearly marked

# === TERRAFORM — onboard the 6 remaining PROD apps ===

# C1 — validate + plan (cloud-graylog/terraform/), acotado a los 6 recursos nuevos
#   cd ~/Documentos/git/cloud-graylog/terraform
#   terraform fmt -check
#   terraform validate
#   terraform plan \
#     -target=azurerm_monitor_diagnostic_setting.pos \
#     -target=azurerm_monitor_diagnostic_setting.platform \
#     -target=azurerm_monitor_diagnostic_setting.person \
#     -target=azurerm_monitor_diagnostic_setting.admin \
#     -target=azurerm_monitor_diagnostic_setting.catalog \
#     -target=azurerm_monitor_diagnostic_setting.orders
# OUTPUT: Plan: 6 to add, 0 to change, 0 to destroy.

# ⚠️ C2 — apply de los 6 recursos nuevos
#   terraform apply \
#     -target=azurerm_monitor_diagnostic_setting.pos \
#     -target=azurerm_monitor_diagnostic_setting.platform \
#     -target=azurerm_monitor_diagnostic_setting.person \
#     -target=azurerm_monitor_diagnostic_setting.admin \
#     -target=azurerm_monitor_diagnostic_setting.catalog \
#     -target=azurerm_monitor_diagnostic_setting.orders
# OUTPUT: Apply complete! Resources: 6 added, 0 changed, 0 destroyed.

# === VERIFICACIÓN — entrega real de datos ===

# C3 — métrica IncomingMessages del Event Hub compartido (agregada, no distingue por app)
az monitor metrics list \
  --resource "/subscriptions/85c76dea-3304-4310-8656-bf21b28e4f4b/resourceGroups/SmartFran.Cloud.PRO/providers/Microsoft.EventHub/namespaces/smartfran-graylog-evhns-pro" \
  --metric IncomingMessages \
  --interval PT5M \
  --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --aggregation Total \
  -o table
# OUTPUT: ventana de 0.0 sostenida ~20 min poco después del apply (~15:01-15:22 UTC).

# C4 — descarta throttling por capacidad del namespace (1 TU, phase=pilot)
az monitor metrics list \
  --resource "/subscriptions/85c76dea-3304-4310-8656-bf21b28e4f4b/resourceGroups/SmartFran.Cloud.PRO/providers/Microsoft.EventHub/namespaces/smartfran-graylog-evhns-pro" \
  --metric ThrottledRequests \
  --interval PT5M \
  --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --aggregation Total \
  -o table
# OUTPUT: 0.0 plano durante toda la ventana — descarta throttling.

# === HALLAZGO — Log Analytics sobrescrito ===

# C5 — confirma que Pos/Platform/Admin/Catalog perdieron el destino Log Analytics
for app in Pos Platform Admin Catalog; do
  echo "--- SmartFran-Cloud-${app}-PRO ---"
  az monitor diagnostic-settings list \
    --resource "/subscriptions/85c76dea-3304-4310-8656-bf21b28e4f4b/resourceGroups/SmartFran.Cloud.PRO/providers/Microsoft.Web/sites/SmartFran-Cloud-${app}-PRO" \
    --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
    -o json
done
# OUTPUT: un solo objeto por app, solo Event Hub, sin workspaceId — confirma la sobrescritura.

# C6 — confirma que la referencia de workspace del setting sobreviviente de Person es inválida
az account show --query "{name:name, id:id, user:user.name}" -o table
az account list --query "[].{name:name, id:id}" -o table
az resource show \
  --ids "/subscriptions/d6ab1add-4bc8-40b0-8cf8-e7291f7171b0/resourceGroups/SmartFran.Cloud.PRO/providers/Microsoft.OperationalInsights/workspaces/SmartFranCloudPro" \
  -o table
# OUTPUT: SubscriptionNotFound — la subscripción no existe, no es un problema de permisos.

# C7 — confirma el workspace real (misma subscripción que todo lo demás en este proyecto)
az monitor log-analytics workspace show \
  --resource-group SmartFran.Cloud.PRO \
  --workspace-name SmartFranCloudPro \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --query "{id:id, customerId:customerId}" -o table
# OUTPUT: customerId 76536d4a-5616-44ae-bee4-0aa6963b5d28 — coincide con lo ya documentado en CLAUDE.md.

# ⚠️ C8 — re-apply tras corregir local.log_analytics_workspace_id en terraform/main.tf
#   cd ~/Documentos/git/cloud-graylog/terraform
#   terraform validate
#   terraform plan \
#     -target=azurerm_monitor_diagnostic_setting.pos \
#     -target=azurerm_monitor_diagnostic_setting.platform \
#     -target=azurerm_monitor_diagnostic_setting.admin \
#     -target=azurerm_monitor_diagnostic_setting.catalog
#   terraform apply \
#     -target=azurerm_monitor_diagnostic_setting.pos \
#     -target=azurerm_monitor_diagnostic_setting.platform \
#     -target=azurerm_monitor_diagnostic_setting.admin \
#     -target=azurerm_monitor_diagnostic_setting.catalog
# OUTPUT: Apply complete! Resources: 0 added, 4 changed, 0 destroyed.

# C9 — verificación independiente post-fix
for app in Pos Platform Admin Catalog; do
  echo "--- SmartFran-Cloud-${app}-PRO ---"
  az monitor diagnostic-settings list \
    --resource "/subscriptions/85c76dea-3304-4310-8656-bf21b28e4f4b/resourceGroups/SmartFran.Cloud.PRO/providers/Microsoft.Web/sites/SmartFran-Cloud-${app}-PRO" \
    --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
    --query "[].{name:name, eventHub:eventHubName, workspaceId:workspaceId}" -o table
done
# OUTPUT: los 4 apps con ambos destinos poblados correctamente.

# === GRAYLOG API — conteos por app y por categoría ===
# Views Search API (Graylog 7.1.3 no tiene los endpoints legacy de búsqueda universal).
# Flujo de 3 pasos: crear búsqueda -> ejecutar -> poll del resultado (asíncrono).
# Auth: -u "$GRAYLOG_API_KEY:token"

# C10 — conteo por app (pivot sobre "name", últimos 15 min)
BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
SEARCH_ID=$(curl -s -u "${GRAYLOG_API_KEY}:token" \
  -H "Content-Type: application/json" -H "Accept: application/json" \
  -H "X-Requested-By: cli" \
  -d '{
    "queries": [{
      "id": "q1",
      "query": {"type": "elasticsearch", "query_string": "*"},
      "timerange": {"type": "relative", "range": 900},
      "search_types": [{
        "id": "agg1", "type": "pivot",
        "row_groups": [{"type": "values", "field": "name", "limit": 20}],
        "series": [{"type": "count", "id": "count()"}],
        "rollup": true
      }]
    }]
  }' \
  "${BASE}/views/search" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
JOB_ID=$(curl -s -u "${GRAYLOG_API_KEY}:token" \
  -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
  -d '{}' "${BASE}/views/search/${SEARCH_ID}/execute" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
curl -s -i -u "${GRAYLOG_API_KEY}:token" -H "Accept: application/json" \
  "${BASE}/views/search/status/${JOB_ID}"
# OUTPUT (primera corrida, ~15:10 UTC): Pos/Platform/Person/Admin/Catalog en 0, solo Orders/Business/Sales con datos.
# OUTPUT (segunda corrida, ~17:17 UTC): los 6 apps con datos reales. Catalog domina: 62.809 de 72.485 (86.7%).

# C11 — desglose de Catalog por categoría (mismo patrón, query_string "name:SMARTFRAN-CLOUD-CATALOG-PRO", pivot sobre "category")
# OUTPUT: AppServiceConsoleLogs 44.904 vs AppServiceHTTPLogs 280 — ratio 160:1, verbosidad de logging, no tráfico real.

# C12 — indexer failures (endpoint conocido por devolver resultados obsoletos/cacheados, no un tail en vivo)
curl -s -u "${GRAYLOG_API_KEY}:token" -H "Accept: application/json" \
  "${BASE}/system/indexer/failures?limit=10" | python3 -m json.tool
curl -s -u "${GRAYLOG_API_KEY}:token" -H "Accept: application/json" \
  "${BASE}/system/indexer/failures?limit=10&offset=62873" | python3 -m json.tool
# OUTPUT: ambas corridas devolvieron solo entradas del 31/07 en business__7 (incidente histórico ya documentado en CG-005),
# total sin cambios (62883) entre ambas consultas — inconcluso sobre el estado actual de Catalog.

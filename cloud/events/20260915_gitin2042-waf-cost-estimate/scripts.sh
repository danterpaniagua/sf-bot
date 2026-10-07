#!/usr/bin/env bash
# Event: 20260915_gitin2042-waf-cost-estimate
# Commands are grouped by phase: Pricing / Traffic (App Services) / Traffic (Functions)
# Read-only throughout — no ⚠️ ACTION commands in this ticket.

EVT="/home/dpaniagua/Documentos/git/bots/cloud/events/20260915_gitin2042-waf-cost-estimate"

# === PRICING (Azure Retail Prices API, public, no auth) ===

# C1 — Azure Front Door Premium pricing (Base Fee, Requests, Data Transfer In/Out), all regions/zones (paginated)
curl -s "https://prices.azure.com/api/retail/prices?\$filter=serviceName%20eq%20%27Azure%20Front%20Door%20Service%27" -o page1.json
# ... paginated via NextPageLink, merged into:
# > ${EVT}/data/pricing_frontdoor.json  (389 items)

# C2 — Application Gateway WAF_v2 pricing, eastus2 (Fixed Cost, Capacity Units)
curl -s "https://prices.azure.com/api/retail/prices?\$filter=serviceName%20eq%20%27Application%20Gateway%27%20and%20armRegionName%20eq%20%27eastus2%27" -o page1.json
# ... paginated, merged into:
# > ${EVT}/data/pricing_appgw.json  (27 items)

# === TRAFFIC — 8 production App Services (Graylog, PROD-{App}-AppServiceHTTPLogs streams) ===
# Window: 2026-09-11T18:20:00.000Z - 2026-09-15T14:00:00.000Z (91.667h), same for all 8 services.
# Sales-PRO pulled earlier in cloud/events/20260913_pos-net-http-timeout/ (different ticket, referenced not duplicated).

# C3-C9 — raw export + local aggregation, one pass per app (Admin/Business/Catalog/Orders/Person/Platform/Pos)
START="2026-09-11T18:20:00.000Z"
END="2026-09-15T14:00:00.000Z"
declare -A STREAMS=(
  [admin]=6a8edbc94814bcaed323ede1
  [business]=6a8edd554814bcaed323f891
  [catalog]=6a8edd584814bcaed323f8c8
  [orders]=6a8edd5c4814bcaed323f903
  [person]=6a8edd5f4814bcaed323f934
  [platform]=6a8edd624814bcaed323f968
  [pos]=6a8edd664814bcaed323f9a8
)
for app in "${!STREAMS[@]}"; do
  STREAM_ID="${STREAMS[$app]}"
  OUT_DIR="${EVT}/data/${app}"
  curl -s -u "${GRAYLOG_API_KEY}:token" \
    --data-urlencode 'query=*' \
    --data-urlencode "filter=streams:${STREAM_ID}" \
    --data-urlencode 'fields=timestamp,properties' \
    --data-urlencode "from=${START}" --data-urlencode "to=${END}" \
    -G "https://sfcloud-monitoreo.smartfran.com/graylog/api/search/universal/absolute/export" \
    -H 'Accept: text/csv' \
    -o "${OUT_DIR}/httplogs_raw_export.csv"
  python3 /home/dpaniagua/Documentos/git/bots/cloud/scripts/appservice_perf_report.py \
    --raw-csv "${OUT_DIR}/httplogs_raw_export.csv" \
    --stream-id "${STREAM_ID}" --from "${START}" --to "${END}" \
    --app-label "${app^}-PRO" \
    --data-dir "${OUT_DIR}" --report-dir "${OUT_DIR}" \
    > "${OUT_DIR}/report_build_log.txt" 2>&1
done
# > ${EVT}/data/{admin,business,catalog,orders,person,platform,pos}/timetaken_by_path_aggregated.csv

# === TRAFFIC — Function Apps (Azure Monitor platform metrics, no Graylog stream exists for these) ===

# C10 — Discovery: App Insights components in the RG + available metric names for a Function App resource
SUB="85c76dea-3304-4310-8656-bf21b28e4f4b"
RG="SmartFran.Cloud.PRO"
OUT_DIR="${EVT}/data/functions"
az resource list --resource-group "$RG" --subscription "$SUB" \
  --resource-type "microsoft.insights/components" -o json \
  > "${OUT_DIR}/app_insights_components.json"
az monitor metrics list-definitions \
  --resource "/subscriptions/${SUB}/resourceGroups/${RG}/providers/Microsoft.Web/sites/SFC-CodeGenerator-PRO" \
  --subscription "$SUB" -o json \
  > "${OUT_DIR}/metric_definitions_codegenerator.json"

# C11 — FunctionExecutionCount (Total, PT1H), same window as the App Service pulls, all 4 Function Apps
START="2026-09-11T18:20:00Z"
END="2026-09-15T14:00:00Z"
for app in SFC-CodeGenerator-PRO SFC-ScheduledJobs-PRO SFC-TicketProcess-PRO SFC-PosWasmRelay-PRO; do
  az monitor metrics list \
    --resource "/subscriptions/${SUB}/resourceGroups/${RG}/providers/Microsoft.Web/sites/${app}" \
    --subscription "$SUB" \
    --metric "FunctionExecutionCount" --aggregation Total \
    --interval PT1H --start-time "$START" --end-time "$END" \
    --output json \
    > "${OUT_DIR}/${app}_execution_count.json"
done

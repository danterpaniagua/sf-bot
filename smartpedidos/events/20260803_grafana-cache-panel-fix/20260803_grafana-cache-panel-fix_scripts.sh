#!/bin/bash
# Reference commands used during 20260803_grafana-cache-panel-fix (GITIN-1748)
# Requires GRAFANA_API_KEY to be set (see ~/.grafana_vars, sourced from ~/.bashrc — not stored in this repo).

# C1 — sanity check: confirm the Grafana API key works
curl -H "Authorization: Bearer $GRAFANA_API_KEY" \
  http://monitoreosp.smartfran.com:3000/api/dashboards/home

# C2 — replicate the failing panel query directly against Grafana's query endpoint,
# to see the raw HTTP response body (bypasses the panel/browser error toast).
curl -s -X POST "http://monitoreosp.smartfran.com:3000/api/tsdb/query" \
  -H "Authorization: Bearer $GRAFANA_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
  "queries": [
    {
      "queryType": "query",
      "refId": "A",
      "type": "timeserie",
      "datasourceId": 2,
      "projectId": "5e29fa1e9ccf64d7ef306b9c",
      "projectName": "ProductionPedidos",
      "clusterId": "5f80da02db0b99737e15d74b",
      "clusterName": "PedidosSmartfran",
      "metricId": "process_measurements",
      "dimensionId": "CACHE_USAGE_USED",
      "dimensionName": "Cache usage used",
      "database": "",
      "mongoId": "pedidossmartfran-shard-00-00-narx2.mongodb.net:27017",
      "disk": "",
      "intervalMs": 15000,
      "maxDataPoints": 1303
    }
  ],
  "from": "<epoch_ms_from>",
  "to": "<epoch_ms_to>"
}' | jq .
# Result: {"message": "Metric request error"} — no further detail in the HTTP body itself.

# C3 — identify the exact datasource plugin (id, version, GitHub link) without needing
# Admin/Editor rights (the direct /api/datasources/{id} endpoint returned "Permission denied"
# for this Viewer-scoped key).
curl -s "http://monitoreosp.smartfran.com:3000/api/frontend/settings" \
  -H "Authorization: Bearer $GRAFANA_API_KEY" | jq '.datasources'
# Result: datasource id 2 = "grafana-mongodb-atlas-datasource" v1.0.0 (2019-04-10),
# GitHub: https://github.com/valiton/grafana-mongodb-atlas-datasource

# C4 — cross-reference plugin source against MongoDB's actual API (no auth needed, public repos)
curl -s "https://raw.githubusercontent.com/valiton/grafana-mongodb-atlas-datasource/master/src/types.ts" \
  | grep -n -i "cache"

curl -sL "https://raw.githubusercontent.com/mongodb/openapi/main/openapi/v2.json" -o /tmp/atlas_openapi.json
python3 -c "
import json
with open('/tmp/atlas_openapi.json') as f:
    spec = json.load(f)
path = spec['paths']['/api/atlas/v2/groups/{groupId}/processes/{processId}/measurements']
for param in path['get']['parameters']:
    if param.get('name') == 'm':
        print([e for e in param['schema']['items']['enum'] if 'CACHE' in e])
"
# Result: real enum has CACHE_USED_BYTES / CACHE_DIRTY_BYTES, not CACHE_USAGE_USED / CACHE_USAGE_DIRTY.

# C5 — the fix (applied via Grafana UI: panel dropdown ▾ → More ▸ Panel JSON, not via API):
# changed dimensionId "CACHE_USAGE_USED" → "CACHE_USED_BYTES" (and dimensionName to match)
# on all 3 replica targets of the "MongoDB: Cache" panel. No API call needed for the fix itself
# since the plugin backend forwards dimensionId to Atlas with no local validation.

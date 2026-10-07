#!/usr/bin/env bash
# Event: 20260825_pos-wasm-duplicate-stream-messages (GITIN-1933)
# Commands grouped by phase: Investigation / Audit / Remediation
# ⚠️ ACTION commands are clearly marked — write/state-changing.

# === INVESTIGATION ===

# C1 — Recent smartfran-pos-wasm/Production messages, full stream membership + timestamp
# (Views Search API, 3-step pattern: submit search -> execute -> poll status)
BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
SEARCH_ID=$(curl -s -u "${GRAYLOG_API_KEY}:token" \
  -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
  -d '{"queries":[{"id":"q1","query":{"type":"elasticsearch","query_string":"Service:\"smartfran-pos-wasm\" AND Environment:\"Production\""},"timerange":{"type":"relative","range":604800},"search_types":[{"id":"msgs1","type":"messages","fields":["timestamp","streams","_id","Service","Environment"],"sort":[{"field":"timestamp","order":"DESC"}],"limit":25}]}]}' \
  "${BASE}/views/search" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
JOB_ID=$(curl -s -u "${GRAYLOG_API_KEY}:token" -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
  -d '{}' "${BASE}/views/search/${SEARCH_ID}/execute" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
curl -s -u "${GRAYLOG_API_KEY}:token" -H "Accept: application/json" "${BASE}/views/search/status/${JOB_ID}"

# C2 — Confirm stream name for the id seen in C1's streams array
curl -s -u "${GRAYLOG_API_KEY}:token" -H "Accept: application/json" \
  "${BASE}/streams/6a7cb1884814bcaed30a8744" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['title'], '-', d.get('index_set_id'))"
# OUTPUT (2026-08-25): PROD-Pos-AppServicePlan - 6a7cb1874814bcaed30a873d — confirmed, matches ticket's named stream.

# C3 — Current live text of the two GITIN-1924 pipeline rules (confirm route_to_stream() vs remove_from_stream())
curl -s -u "${GRAYLOG_API_KEY}:token" -H "Accept: application/json" "${BASE}/system/pipelines/rule" \
  | python3 -c "import json,sys; [print(r['id'], '-', r['title'], '\n', r['source'], '\n---') for r in json.load(sys.stdin) if 'GITIN-1924' in r['title']]"
# OUTPUT (2026-08-25): both rules confirmed unchanged from GITIN-1924 — route_to_stream() only, no remove_from_stream().

# === REMEDIATION ===

# ⚠️ C4 — Add remove_from_stream(Default Stream) to the DEV rule
curl -s -u "${GRAYLOG_API_KEY}:token" -H "Content-Type: application/json" -H "X-Requested-By: cli" -X PUT \
  -d '{"title":"GITIN-1924: smartfran-pos-wasm to DEV","description":"Route POS WASM relay traffic (Service+Environment) into the DEV stream, GITIN-1924","source":"rule \"GITIN-1924: smartfran-pos-wasm to DEV\"\nwhen\n  to_string($message.Service) == \"smartfran-pos-wasm\" && to_string($message.Environment) == \"Development\"\nthen\n  route_to_stream(name: \"DEV\");\n  remove_from_stream(id: \"000000000000000000000001\");\nend"}' \
  "${BASE}/system/pipelines/rule/6a8c60ae4814bcaed31a5560"

# ⚠️ C5 — Add remove_from_stream(Default Stream) to the PROD rule
curl -s -u "${GRAYLOG_API_KEY}:token" -H "Content-Type: application/json" -H "X-Requested-By: cli" -X PUT \
  -d '{"title":"GITIN-1924: smartfran-pos-wasm to PROD-Pos-AppServicePlan","description":"Route POS WASM relay traffic (Service+Environment) into the PROD-Pos-AppServicePlan stream, GITIN-1924","source":"rule \"GITIN-1924: smartfran-pos-wasm to PROD-Pos-AppServicePlan\"\nwhen\n  to_string($message.Service) == \"smartfran-pos-wasm\" && to_string($message.Environment) == \"Production\"\nthen\n  route_to_stream(name: \"PROD-Pos-AppServicePlan\");\n  remove_from_stream(id: \"000000000000000000000001\");\nend"}' \
  "${BASE}/system/pipelines/rule/6a8c60bf4814bcaed31a559d"

# C6 — Verification: next real message on either environment should carry only its target stream, not Default
# (same 3-step Views Search pattern as C1, fields includes "streams", filter to a recent timestamp post-fix)
SEARCH_ID=$(curl -s -u "${GRAYLOG_API_KEY}:token" \
  -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
  -d '{"queries":[{"id":"q1","query":{"type":"elasticsearch","query_string":"Service:\"smartfran-pos-wasm\""},"timerange":{"type":"absolute","from":"2026-08-25T12:46:28.744Z","to":"2026-08-26T00:00:00.000Z"},"search_types":[{"id":"msgs1","type":"messages","fields":["timestamp","streams","_id","Environment"],"sort":[{"field":"timestamp","order":"ASC"}],"limit":10}]}]}' \
  "${BASE}/views/search" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
JOB_ID=$(curl -s -u "${GRAYLOG_API_KEY}:token" -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
  -d '{}' "${BASE}/views/search/${SEARCH_ID}/execute" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
curl -s -u "${GRAYLOG_API_KEY}:token" -H "Accept: application/json" "${BASE}/views/search/status/${JOB_ID}"

# C7 — Verification: DEV side, post-fix, explicit Environment:"Development" filter
# (unfiltered C6 was dominated by Production traffic — narrows to confirm DEV routing specifically)
SEARCH_ID=$(curl -s -u "${GRAYLOG_API_KEY}:token" \
  -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
  -d '{"queries":[{"id":"q1","query":{"type":"elasticsearch","query_string":"Service:\"smartfran-pos-wasm\" AND Environment:\"Development\""},"timerange":{"type":"absolute","from":"2026-08-25T12:45:44.302Z","to":"2026-08-26T00:00:00.000Z"},"search_types":[{"id":"msgs1","type":"messages","fields":["timestamp","streams","_id","Environment"],"sort":[{"field":"timestamp","order":"ASC"}],"limit":10}]}]}' \
  "${BASE}/views/search" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
JOB_ID=$(curl -s -u "${GRAYLOG_API_KEY}:token" -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
  -d '{}' "${BASE}/views/search/${SEARCH_ID}/execute" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
curl -s -u "${GRAYLOG_API_KEY}:token" -H "Accept: application/json" "${BASE}/views/search/status/${JOB_ID}"

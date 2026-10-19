#!/usr/bin/env bash
# GITIN-2250 — rollback of zabbix-httptest6-add-step.sh: resends the original (single) step list of scenario 6 from the run's BEFORE snapshot, which removes the added step.
# Usage: zabbix-httptest6-add-step-rollback.sh <run dir>   (APPLY=1 to apply; otherwise prints the payload)
set -euo pipefail
RUN=${1:?usage: $0 <run dir>}
API=${API:-http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php}
: "${ZABBIX_API_KEY:?ZABBIX_API_KEY not set}"
APPLY=${APPLY:-0}
[ -s "$RUN/before-httptest6.json" ] || { echo "no before-httptest6.json in $RUN" >&2; exit 1; }

rpc() {
  local r
  r=$(jq -nc --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,id:1,auth:$a}' \
      | curl -s -X POST "$API" -H 'Content-Type: application/json' -d @-)
  if [ "$(jq 'has("error")' <<<"$r")" = true ]; then echo "ERROR $1: $(jq -c .error <<<"$r")" >&2; return 1; fi
  jq -c .result <<<"$r"
}
cur=$(rpc httptest.get '{"httptestids":["6"],"output":["name"],"selectSteps":["httpstepid","name","no"]}')
[ "$(jq -r '.[0].name' <<<"$cur")" = "[PROD] API POS / Gestion" ] || { echo "GUARD FAILED: httptest 6 name" >&2; exit 1; }
jq -e '[.[0].steps[]|select(.httpstepid=="9")]|length==1' <<<"$cur" >/dev/null || { echo "GUARD FAILED: step 9 not present" >&2; exit 1; }
PARAMS=$(jq -c '.[0] | {httptestid:"6",steps:[.steps[]|{httpstepid,name,no,url,timeout,status_codes,follow_redirects,retrieve_mode,required}]}' "$RUN/before-httptest6.json")
if [ "$APPLY" = 1 ]; then echo "restore: $(rpc httptest.update "$PARAMS")"; else echo "would send: $PARAMS"; fi

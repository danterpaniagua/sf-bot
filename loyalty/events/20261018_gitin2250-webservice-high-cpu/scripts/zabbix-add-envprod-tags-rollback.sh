#!/usr/bin/env bash
# GITIN-2250 — rollback of zabbix-add-envprod-tags.sh: resends every trigger with the tag list saved in the run's BEFORE snapshot.
# Usage: zabbix-add-envprod-tags-rollback.sh <run dir>   (APPLY=1 to apply; otherwise prints the first payload)
set -euo pipefail
RUN=${1:?usage: $0 <run dir>}
API=${API:-http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php}
: "${ZABBIX_API_KEY:?ZABBIX_API_KEY not set}"
APPLY=${APPLY:-0}
[ -s "$RUN/before-triggers.json" ] || { echo "no before-triggers.json in $RUN" >&2; exit 1; }
rpc() {
  local r
  r=$(jq -nc --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,id:1,auth:$a}' \
      | curl -s -X POST "$API" -H 'Content-Type: application/json' -d @-)
  if [ "$(jq 'has("error")' <<<"$r")" = true ]; then echo "ERROR $1: $(jq -c .error <<<"$r")" >&2; return 1; fi
  jq -c .result <<<"$r"
}
PAYLOAD=$(jq -c '[.[] | {triggerid, tags}]' "$RUN/before-triggers.json")
[ "$(jq length <<<"$PAYLOAD")" = 84 ] || { echo "GUARD FAILED: snapshot does not hold 84 triggers" >&2; exit 1; }
if [ "$APPLY" = 1 ]; then echo "restore: $(rpc trigger.update "$PAYLOAD")"; else jq -c '.[0]' <<<"$PAYLOAD"; echo "(84 triggers) would be sent"; fi

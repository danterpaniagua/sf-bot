#!/usr/bin/env bash
# Rollback of zabbix-burst-macro-apply.sh: sets global macro 128 back to the value saved in the run's before-macros.json (60).
# Usage: zabbix-burst-macro-rollback.sh <run dir>   (APPLY=1 to apply; otherwise prints the plan)
set -euo pipefail
RUN=${1:?usage: $0 <run dir>}
API=${API:-http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php}
: "${ZABBIX_API_KEY:?ZABBIX_API_KEY not set}"
APPLY=${APPLY:-0}
[ -s "$RUN/before-macros.json" ] && [ -s "$RUN/update-result.json" ] || { echo "run dir lacks before-macros.json or update-result.json (nothing was applied)" >&2; exit 1; }
OLD=$(jq -r '.[]|select(.globalmacroid=="128")|.value' "$RUN/before-macros.json")
[[ "$OLD" =~ ^[0-9]+$ ]] || { echo "GUARD FAILED: saved value not numeric" >&2; exit 1; }
rpc() {
  local r
  r=$(jq -nc --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,id:1,auth:$a}' \
      | curl -s -X POST "$API" -H 'Content-Type: application/json' -d @-)
  if [ "$(jq 'has("error")' <<<"$r")" = true ]; then echo "ERROR $1: $(jq -c .error <<<"$r")" >&2; return 1; fi
  jq -c .result <<<"$r"
}
P=$(jq -nc --arg v "$OLD" '{globalmacroid:"128",value:$v}'); echo "restore: $P"
if [ "$APPLY" = 1 ]; then echo "result: $(rpc usermacro.updateglobal "$P")"; else echo "(dry run; APPLY=1 to apply)"; fi

#!/usr/bin/env bash
# GITIN-2250 — rollback of zabbix-healthcheck-trigger-v1-tags.sh: deletes the Healthcheck trigger it created (id read from the run's create-result.json)
# and restores the tag list of 25746/25753 from the BEFORE snapshot (empty lists).
# Usage: zabbix-healthcheck-trigger-v1-tags-rollback.sh <run dir>   (APPLY=1 to apply; otherwise prints the plan)
set -euo pipefail
RUN=${1:?usage: $0 <run dir>}
API=${API:-http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php}
: "${ZABBIX_API_KEY:?ZABBIX_API_KEY not set}"
APPLY=${APPLY:-0}
[ -s "$RUN/before-v1-triggers.json" ] || { echo "no before-v1-triggers.json in $RUN" >&2; exit 1; }
[ -s "$RUN/create-result.json" ] || { echo "no create-result.json in $RUN (nothing was created)" >&2; exit 1; }
rpc() {
  local r
  r=$(jq -nc --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,id:1,auth:$a}' \
      | curl -s -X POST "$API" -H 'Content-Type: application/json' -d @-)
  if [ "$(jq 'has("error")' <<<"$r")" = true ]; then echo "ERROR $1: $(jq -c .error <<<"$r")" >&2; return 1; fi
  jq -c .result <<<"$r"
}
TID=$(jq -r '.triggerids[0]' "$RUN/create-result.json")
[[ "$TID" =~ ^[0-9]+$ ]] || { echo "GUARD FAILED: no trigger id in create-result.json" >&2; exit 1; }
d=$(rpc trigger.get "$(jq -nc --arg t "$TID" '{triggerids:[$t],output:["description"]}')" | jq -r '.[0].description')
[ "$d" = "WebService: healthcheck.ashx HTTP code not 200 (via LB)" ] || { echo "GUARD FAILED: trigger $TID is '$d'" >&2; exit 1; }
PAYLOAD=$(jq -c '[.[] | {triggerid, tags}]' "$RUN/before-v1-triggers.json")
echo "delete trigger $TID; restore tags: $PAYLOAD"
if [ "$APPLY" = 1 ]; then
  echo "restore: $(rpc trigger.update "$PAYLOAD")"
  echo "delete: $(rpc trigger.delete "[\"$TID\"]")"
else echo "(dry run; APPLY=1 to apply)"; fi

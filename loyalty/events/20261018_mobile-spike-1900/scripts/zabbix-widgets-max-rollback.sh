#!/usr/bin/env bash
# Rollback of zabbix-widgets-max-apply.sh: resends dashboard 337 as saved in the run's before-dashboard.json (original titles, Sum / 10m, unit "reqs").
# Usage: zabbix-widgets-max-rollback.sh <run dir>   (APPLY=1 to apply; otherwise prints the widget count)
set -euo pipefail
RUN=${1:?usage: $0 <run dir>}
API=${API:-http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php}
: "${ZABBIX_API_KEY:?ZABBIX_API_KEY not set}"
APPLY=${APPLY:-0}
[ -s "$RUN/before-dashboard.json" ] && [ -s "$RUN/update-result.json" ] || { echo "run dir lacks before-dashboard.json or update-result.json (nothing was applied)" >&2; exit 1; }
rpc() {
  local r
  r=$(jq -nc --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,id:1,auth:$a}' \
      | curl -s -X POST "$API" -H 'Content-Type: application/json' -d @-)
  if [ "$(jq 'has("error")' <<<"$r")" = true ]; then echo "ERROR $1: $(jq -c .error <<<"$r")" >&2; return 1; fi
  jq -c .result <<<"$r"
}
[ "$(jq -r '.[0].name' "$RUN/before-dashboard.json")" = "SmartLoyalty" ] || { echo "GUARD FAILED: snapshot is not SmartLoyalty" >&2; exit 1; }
PAYLOAD=$(jq -c '{dashboardid:.[0].dashboardid,pages:[.[0].pages[]|{dashboard_pageid,name,display_period,widgets:[.widgets[]|{widgetid,type,name,x,y,width,height,view_mode,fields:[.fields[]|{type,name,value}]}]}]}' "$RUN/before-dashboard.json")
echo "widgets to restore: $(jq '[.pages[].widgets[]]|length' <<<"$PAYLOAD")"
if [ "$APPLY" = 1 ]; then echo "restore: $(rpc dashboard.update "$PAYLOAD")"; else echo "(dry run; APPLY=1 to apply)"; fi

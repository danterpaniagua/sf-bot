#!/usr/bin/env bash
# Read-only (dashboard.get, item.get): raw widgets of dashboard 337 (widget "GET Requests / 10m") and the items they reference.
set -euo pipefail
API=${API:-http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php}
: "${ZABBIX_API_KEY:?ZABBIX_API_KEY not set}"
rpc() {
  local r
  r=$(jq -nc --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,id:1,auth:$a}' \
      | curl -s -X POST "$API" -H 'Content-Type: application/json' -d @-)
  if [ "$(jq 'has("error")' <<<"$r")" = true ]; then echo "ERROR $1: $(jq -c .error <<<"$r")" >&2; return 1; fi
  jq -c .result <<<"$r"
}
echo "== now: $(date '+%F %T %z') =="
D=$(rpc dashboard.get '{"dashboardids":["337"],"output":["dashboardid","name"],"selectPages":"extend"}')
jq -c '.[]|{dashboardid,name,pages:(.pages|length)}' <<<"$D"
echo "-- widgets (raw)"
jq -c '.[].pages[].widgets[]|{type,name,view_mode,width,height,fields:[.fields[]|{type,name,value}]}' <<<"$D"
echo "-- items referenced (field type 4 = item)"
for i in $(jq -r '[.[].pages[].widgets[].fields[]|select(.type=="4")|.value]|unique|.[]' <<<"$D"); do
  rpc item.get "$(jq -nc --arg i "$i" '{itemids:[$i],output:["itemid","name","key_","value_type","delay","units"],selectHosts:["host"]}')" | jq -c '.[]|{itemid,host:.hosts[0].host,name,key_,delay,units}'
done

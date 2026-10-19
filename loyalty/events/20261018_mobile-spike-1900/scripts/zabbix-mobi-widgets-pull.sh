#!/usr/bin/env bash
# Read-only (dashboard.get / item.get / host.get): lists dashboards and the widgets that point at SFCG-MOBI-01/02 (hostids 10659/10660) or at their items,
# with the raw widget fields (aggregation function, time period, item/host references). Nothing is written.
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
D=$(rpc dashboard.get '{"output":["dashboardid","name"],"selectPages":"extend"}')
echo "-- dashboards: $(jq length <<<"$D")"; jq -c '.[]|{dashboardid,name,pages:(.pages|length),widgets:([.pages[].widgets[]]|length)}' <<<"$D"
IT=$(rpc item.get '{"hostids":["10659","10660"],"output":["itemid"]}' | jq -c '[.[].itemid]')
echo "-- widgets referencing MOBI hosts (10659/10660) or one of their $(jq length <<<"$IT") items"
jq -c --argjson it "$IT" '.[] | . as $d | .pages[]?.widgets[]? | select([.fields[]?|select(.type=="3" or .type=="4" or .type=="1" or .type=="0" or true)|.value]|map(tostring)|any(.=="10659" or .=="10660" or (. as $v|$it|index($v)))) | {dashboard:$d.name,type,name,fields:[.fields[]|"\(.name)=\(.value)"]}' <<<"$D"
echo "-- every graph/data widget name on dashboards whose name contains Mobile or MOBI"
jq -c '.[]|select(.name|test("mobi";"i"))|. as $d|.pages[]?.widgets[]?|{dashboard:$d.name,type,name,fields:[.fields[]|"\(.name)=\(.value)"]}' <<<"$D"
echo "-- BURST macros (global and MOBI hosts; the first pull searched only SPIKE)"
rpc usermacro.get '{"globalmacro":true,"search":{"macro":"MOBILE_PCOUNT_BURST"},"output":["macro","value"]}' | jq -c '.[]'
rpc usermacro.get '{"hostids":["10659","10660"],"search":{"macro":"MOBILE_PCOUNT_BURST"},"output":["macro","value","hostid"]}' | jq -c '.[]'

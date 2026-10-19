#!/usr/bin/env bash
# Read-only (usermacro.get, host.get): {$MOBILE_PCOUNT_BURST*} at global, host (MOBI-01/02) and linked-template level. Nothing is written.
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
echo "-- global"; rpc usermacro.get '{"globalmacro":true,"search":{"macro":"BURST"},"output":["macro","value"]}' | jq -c '.[]'
echo "-- host level (10659 MOBI-01, 10660 MOBI-02)"; rpc usermacro.get '{"hostids":["10659","10660"],"search":{"macro":"BURST"},"output":["macro","value","hostid"]}' | jq -c '.[]'
T=$(rpc host.get '{"hostids":["10659","10660"],"output":["host"],"selectParentTemplates":["templateid","host"]}')
echo "-- linked templates"; jq -c '.[]|{host,templates:[.parentTemplates[]|"\(.templateid):\(.host)"]}' <<<"$T"
TIDS=$(jq -c '[.[].parentTemplates[].templateid]|unique' <<<"$T")
echo "-- template level"; rpc usermacro.get "$(jq -nc --argjson t "$TIDS" '{hostids:$t,search:{macro:"BURST"},output:["macro","value","hostid"]}')" | jq -c '.[]'
echo "-- burst triggers (raw functions; 26909 MOBI-01, 26910 MOBI-02)"
rpc trigger.get '{"triggerids":["26909","26910"],"output":["triggerid","expression","recovery_expression","value","lastchange"],"selectFunctions":"extend"}' | jq -c '.[]|{triggerid,expr:.expression,rec:.recovery_expression,v:.value,last:(.lastchange|tonumber|strftime("%F %T UTC")),fn:[.functions[]|"\(.itemid):\(.function)(\(.parameter))"]}'

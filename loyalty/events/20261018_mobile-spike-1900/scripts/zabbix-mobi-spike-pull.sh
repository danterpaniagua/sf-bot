#!/usr/bin/env bash
# Read-only (Zabbix *.get only): MOBI "IIS Spike" triggers, their macro values and the request-rate history they read, window 18:30-19:45 UTC-3 (21:30-22:45 UTC) on 2026-10-18.
# Triggers are read with raw functions (no expandExpression: it would also expand macros and hide them). History times print in UTC.
set -euo pipefail
API=${API:-http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php}
: "${ZABBIX_API_KEY:?ZABBIX_API_KEY not set}"
FROM=$(date -u -d '2026-10-18 21:30:00' +%s); TILL=$(date -u -d '2026-10-18 22:45:00' +%s)
rpc() {
  local r
  r=$(jq -nc --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,id:1,auth:$a}' \
      | curl -s -X POST "$API" -H 'Content-Type: application/json' -d @-)
  if [ "$(jq 'has("error")' <<<"$r")" = true ]; then echo "ERROR $1: $(jq -c .error <<<"$r")" >&2; return 1; fi
  jq -c .result <<<"$r"
}
echo "== now: $(date '+%F %T %z') =="
echo "-- spike triggers on MOBI-01/02 (raw)"
TR=$(rpc trigger.get '{"hostids":["10659","10660"],"search":{"description":"Spike"},"output":["triggerid","description","expression","recovery_expression","priority","value","lastchange","status"],"selectFunctions":"extend","selectTags":["tag","value"],"selectHosts":["host"]}')
jq -c '.[]|{triggerid,host:.hosts[0].host,d:.description,expr:.expression,rec:.recovery_expression,p:.priority,v:.value,st:.status,last:(.lastchange|tonumber|strftime("%F %T UTC")),fn:[.functions[]|"\(.itemid):\(.function)(\(.parameter))"],tags:[.tags[]|"\(.tag):\(.value)"]}' <<<"$TR"
echo "-- macros MOBILE_PCOUNT_SPIKE (host level, then global)"
rpc usermacro.get '{"hostids":["10659","10660"],"search":{"macro":"MOBILE_PCOUNT_SPIKE"},"output":["macro","value","hostid"]}' | jq -c '.[]'
rpc usermacro.get '{"globalmacro":true,"search":{"macro":"MOBILE_PCOUNT_SPIKE"},"output":["macro","value"]}' | jq -c '.[]'
echo "-- request-rate history for the items those triggers read"
for i in $(jq -r '[.[].functions[].itemid]|unique|.[]' <<<"$TR"); do
  it=$(rpc item.get "$(jq -nc --arg i "$i" '{itemids:[$i],output:["itemid","name","key_","value_type","units"],selectHosts:["host"]}')" | jq -c '.[0]|{itemid,host:.hosts[0].host,name,key_,vt:.value_type,units}')
  echo "item $it"; vt=$(jq -r .vt <<<"$it")
  rpc history.get "$(jq -nc --arg i "$i" --argjson vt "$vt" --argjson f "$FROM" --argjson t "$TILL" '{itemids:[$i],history:$vt,time_from:$f,time_till:$t,output:["clock","value"],sortfield:"clock"}')" \
   | jq -r '.[]|"\(.clock|tonumber|strftime("%H:%M")) \(.value|tonumber*10|round/10)"' | paste -sd' ' | fold -w 180
done
echo "-- problem events for these triggers since 2026-10-16 (any time)"
rpc event.get "$(jq -nc --argjson t "$(jq -c '[.[].triggerid]' <<<"$TR")" --argjson f "$(date -u -d '2026-10-16' +%s)" '{objectids:$t,source:0,object:0,time_from:$f,output:["eventid","clock","value","name"],sortfield:["clock"]}')" | jq -c '.[]|{id:.eventid,at:(.clock|tonumber|strftime("%F %T UTC")),v:.value}'
echo "-- GET request items on MOBI-01/02 (name or key contains 'get') and their history in the window"
GI=$(rpc item.get '{"hostids":["10659","10660"],"output":["itemid","name","key_","value_type","units"],"selectHosts":["host"],"search":{"name":"get"},"searchWildcardsEnabled":false}')
jq -c '.[]|{itemid,host:.hosts[0].host,name,key_,vt:.value_type,units}' <<<"$GI"
for i in $(jq -r '.[]|select(.key_|test("iis|perf_counter|web";"i"))|.itemid' <<<"$GI" | head -12); do
  vt=$(jq -r --arg i "$i" '.[]|select(.itemid==$i)|.value_type' <<<"$GI"); echo "item $i ($(jq -r --arg i "$i" '.[]|select(.itemid==$i)|.hosts[0].host' <<<"$GI"))"
  rpc history.get "$(jq -nc --arg i "$i" --argjson vt "$vt" --argjson f "$FROM" --argjson t "$TILL" '{itemids:[$i],history:$vt,time_from:$f,time_till:$t,output:["clock","value"],sortfield:"clock"}')" \
   | jq -r '.[]|"\(.clock|tonumber|strftime("%H:%M")) \(.value|tonumber*10|round/10)"' | paste -sd' ' | fold -w 180
done

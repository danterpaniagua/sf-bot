#!/usr/bin/env bash
# Read-only (Zabbix *.get only): what Zabbix saw on SFCG-MOBI-01/02 around 19:00 UTC-3 on 2026-10-18 and whether any alert was generated.
# Window 18:30-19:45 UTC-3 = 21:30-22:45 UTC. Output goes to stdout; redirect it into data/.
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
echo "== now: $(date '+%F %T %z') window UTC $FROM-$TILL =="
HOSTS=$(rpc host.get '{"filter":{"host":["SFCG-MOBI-01","SFCG-MOBI-02"]},"output":["hostid","host"]}'); echo "-- hosts"; echo "$HOSTS"
IDS=$(jq -c '[.[].hostid]' <<<"$HOSTS")
echo "-- triggers in PROBLEM now or changed in the window (raw functions, no expandExpression)"
rpc trigger.get "$(jq -nc --argjson h "$IDS" --argjson f "$FROM" '{hostids:$h,output:["triggerid","description","priority","value","lastchange","status"],selectFunctions:"extend",selectTags:["tag","value"],selectHosts:["host"],filter:{status:0}}')" \
  | jq -c --argjson f "$FROM" '.[] | select((.value=="1") or ((.lastchange|tonumber)>=$f)) | {triggerid,d:.description,p:.priority,v:.value,last:(.lastchange|tonumber|strftime("%H:%M:%S UTC")),host:.hosts[0].host,tags:[.tags[]|"\(.tag):\(.value)"],fn:[.functions[]|"\(.function)(\(.parameter))"]}'
echo "-- events in window"
EV=$(rpc event.get "$(jq -nc --argjson h "$IDS" --argjson f "$FROM" --argjson t "$TILL" '{hostids:$h,time_from:$f,time_till:$t,source:0,object:0,output:["eventid","name","clock","value","severity","r_eventid"],selectTags:"extend",sortfield:["clock"]}')")
jq -c '.[]|{id:.eventid,n:.name,at:(.clock|tonumber|strftime("%H:%M:%S UTC")),v:.value,sev:.severity}' <<<"$EV"
echo "-- alerts for those events"
EIDS=$(jq -c '[.[].eventid]' <<<"$EV")
if [ "$(jq length <<<"$EIDS")" = 0 ]; then echo "(no events)"; else
  rpc alert.get "$(jq -nc --argjson e "$EIDS" '{eventids:$e,output:["alertid","eventid","actionid","mediatypeid","status","error","clock"]}')" | jq -c '.[]|{eventid,actionid,media:.mediatypeid,status,error,at:(.clock|tonumber|strftime("%H:%M:%S UTC"))}'
fi
echo "-- CPU util items and history (1 point per minute)"
ITEMS=$(rpc item.get "$(jq -nc --argjson h "$IDS" '{hostids:$h,output:["itemid","key_","hostid"],search:{key_:"system.cpu.util"},selectHosts:["host"]}')"); jq -c '.[]|{itemid,key_,host:.hosts[0].host}' <<<"$ITEMS"
for i in $(jq -r '.[].itemid' <<<"$ITEMS"); do
  echo "item $i"; rpc history.get "$(jq -nc --arg i "$i" --argjson f "$FROM" --argjson t "$TILL" '{itemids:[$i],history:0,time_from:$f,time_till:$t,output:["clock","value"],sortfield:"clock"}')" \
   | jq -r '.[]|"\(.clock|tonumber|strftime("%H:%M")) \(.value|tonumber*10|round/10)"' | paste -sd' ' | fold -w 180
done

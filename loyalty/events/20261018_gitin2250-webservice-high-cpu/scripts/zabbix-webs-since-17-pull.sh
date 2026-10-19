#!/usr/bin/env bash
# GITIN-2250 — read-only (*.get only): WEBS-01/02/03 from FROM (default 17:00 UTC-3 = 20:00 UTC on 2026-10-18) until now.
#  1. triggers raw (no expandExpression) that are in PROBLEM or changed since FROM
#  2. events since FROM with value (1 = problem, 0 = recovery) and the alerts behind them (action / media / status / error)
#  3. spike triggers (POST/GET/Total requests) raw, with the macro values they read
#  4. CPU util, POST, GET and Total requests per second, max per 5-minute bucket (UTC times)
set -euo pipefail
API=${API:-http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php}
: "${ZABBIX_API_KEY:?ZABBIX_API_KEY not set}"
FROM=${FROM:-$(date -u -d '2026-10-18 20:00:00' +%s)}; TILL=$(date -u +%s)
rpc() {
  local r
  r=$(jq -nc --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,id:1,auth:$a}' \
      | curl -s -X POST "$API" -H 'Content-Type: application/json' -d @-)
  if [ "$(jq 'has("error")' <<<"$r")" = true ]; then echo "ERROR $1: $(jq -c .error <<<"$r")" >&2; return 1; fi
  jq -c .result <<<"$r"
}
echo "== now: $(date '+%F %T %z'); window UTC $(date -u -d @"$FROM" '+%F %T') to $(date -u -d @"$TILL" '+%T') =="
HOSTS=$(rpc host.get '{"filter":{"host":["SFCG-WEBS-01","SFCG-WEBS-02","SFCG-WEBS-03"]},"output":["hostid","host"]}'); echo "-- hosts"; echo "$HOSTS"
IDS=$(jq -c '[.[].hostid]' <<<"$HOSTS")
echo "-- 1. triggers in PROBLEM now or changed since FROM"
TR=$(rpc trigger.get "$(jq -nc --argjson h "$IDS" '{hostids:$h,output:["triggerid","description","priority","value","lastchange"],selectFunctions:"extend",selectTags:["tag","value"],selectHosts:["host"],filter:{status:0}}')")
jq -c --argjson f "$FROM" '.[]|select(.value=="1" or (.lastchange|tonumber)>=$f)|{triggerid,host:.hosts[0].host,d:.description,p:.priority,v:.value,last:(.lastchange|tonumber|strftime("%H:%M:%S UTC")),routed:(.tags|any(.tag=="action" and .value=="GCHAT")),env_prod:(.tags|any(.tag=="env" and .value=="PROD"))}' <<<"$TR"
echo "-- 2. events since FROM"
EV=$(rpc event.get "$(jq -nc --argjson h "$IDS" --argjson f "$FROM" '{hostids:$h,time_from:$f,source:0,object:0,output:["eventid","name","clock","value","severity","r_eventid","objectid"],selectHosts:["host"],sortfield:["clock"]}')")
jq -c '.[]|{id:.eventid,at:(.clock|tonumber|strftime("%H:%M:%S UTC")),host:.hosts[0].host,v:(if .value=="1" then "PROBLEM" else "ok" end),n:.name,sev:.severity,trigger:.objectid}' <<<"$EV"
EIDS=$(jq -c '[.[].eventid]' <<<"$EV")
echo "alerts for those events (per event: action:media:status):"
if [ "$(jq length <<<"$EIDS")" = 0 ]; then echo "(no events)"; else
  rpc alert.get "$(jq -nc --argjson e "$EIDS" '{eventids:$e,output:["eventid","actionid","mediatypeid","status","error"],limit:1000}')" | jq -c 'group_by(.eventid)[]|{eventid:.[0].eventid,alerts:(map("\(.actionid):\(.mediatypeid):\(.status)")|join(" ")),errors:(map(select(.error!=""))|length)}'
fi
echo "-- 3. spike triggers (raw) and their macros"
rpc trigger.get "$(jq -nc --argjson h "$IDS" '{hostids:$h,search:{description:"IIS Method"},output:["triggerid","description","expression","recovery_expression","priority","value"],selectFunctions:"extend",selectTags:["tag","value"],selectHosts:["host"]}')" \
 | jq -c '.[]|{triggerid,host:.hosts[0].host,d:.description,expr:.expression,rec:.recovery_expression,p:.priority,v:.value,fn:[.functions[]|"\(.itemid):\(.function)(\(.parameter))"],tags:[.tags[]|"\(.tag):\(.value)"]}' | cut -c1-600
rpc usermacro.get '{"hostids":'"$IDS"',"output":["macro","value","hostid"]}' | jq -c '.[]|select(.macro|test("SPIKE|BURST|POST|GET|REQ";"i"))'
rpc usermacro.get '{"globalmacro":true,"search":{"macro":"POST"},"output":["macro","value"]}' | jq -c '.[]'
echo "-- 4. series, max per 5-minute bucket (HH:MM UTC value)"
IT=$(rpc item.get "$(jq -nc --argjson h "$IDS" '{hostids:$h,output:["itemid","name","key_","value_type"],selectHosts:["host"],filter:{status:0}}')" \
  | jq -c '[.[]|select((.key_=="system.cpu.util") or (.name|test("^IIS: Method (POST|GET) requests per second$")) or (.name=="IIS: Method Total requests per second") or (.key_=="iis_requests.total-requests"))|select(.value_type=="0")]')
for row in $(jq -c '.[]|{i:.itemid,h:.hosts[0].host,n:.name}|@base64' <<<"$IT" | tr -d '"'); do
  r=$(base64 -d <<<"$row"); i=$(jq -r .i <<<"$r"); echo "item $i $(jq -r '.h+" | "+.n' <<<"$r")"
  rpc history.get "$(jq -nc --arg i "$i" --argjson f "$FROM" --argjson t "$TILL" '{itemids:[$i],history:0,time_from:$f,time_till:$t,output:["clock","value"],sortfield:"clock"}')" \
   | jq -r 'group_by((.clock|tonumber)/300|floor)[]|"\(.[0].clock|tonumber|(./300|floor*300)|strftime("%H:%M")) \(map(.value|tonumber)|max*10|round/10)"' | paste -sd' ' | fold -w 170
done

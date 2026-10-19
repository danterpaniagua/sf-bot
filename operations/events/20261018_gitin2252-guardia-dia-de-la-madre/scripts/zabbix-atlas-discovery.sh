#!/usr/bin/env bash
# GITIN-2252 — read-only (*.get only): which MongoDB Atlas items and triggers does Zabbix hold for the PedidosSmartfran shards (host "Zabbix server"), and did any trigger open since 2026-10-16 00:00 UTC-3.
# Raw trigger functions (no expandExpression). Output to stdout; redirect to data/.
set -euo pipefail
API=${API:-http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php}
: "${ZABBIX_API_KEY:?ZABBIX_API_KEY not set}"
FROM=$(date -u -d '2026-10-16 03:00:00' +%s)
rpc() {
  local r
  r=$(jq -nc --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,id:1,auth:$a}' \
      | curl -s -X POST "$API" -H 'Content-Type: application/json' -d @-)
  if [ "$(jq 'has("error")' <<<"$r")" = true ]; then echo "ERROR $1: $(jq -c .error <<<"$r")" >&2; return 1; fi
  jq -c .result <<<"$r"
}
echo "== now: $(date '+%F %T %z'); events from $(date -u -d @"$FROM" '+%F %T UTC') =="
H=$(rpc host.get '{"filter":{"host":["Zabbix server"]},"output":["hostid","host"]}'); echo "-- host: $H"; HID=$(jq -r '.[0].hostid' <<<"$H")
echo "-- items whose name contains pedidossmartfran (name | key | units | state | last value | last time UTC)"
rpc item.get "$(jq -nc --arg h "$HID" '{hostids:[$h],search:{name:"pedidossmartfran"},output:["itemid","name","key_","units","state","lastvalue","lastclock","value_type","delay"],sortfield:"name"}')" \
 | jq -r '.[]|"\(.itemid) | \(.name) | \(.key_) | \(.units) | st\(.state) | \(.lastvalue) | \(if .lastclock=="0" then "never" else (.lastclock|tonumber|strftime("%F %H:%M")) end) | vt\(.value_type) | \(.delay)"' | cut -c1-260
echo "-- triggers on those items (raw)"
TR=$(rpc trigger.get "$(jq -nc --arg h "$HID" '{hostids:[$h],search:{description:"narx2"},output:["triggerid","description","priority","value","lastchange","status"],selectFunctions:"extend",selectTags:["tag","value"]}')")
jq -c '.[]|{triggerid,d:.description,p:.priority,v:.value,st:.status,last:(if .lastchange=="0" then "never" else (.lastchange|tonumber|strftime("%F %H:%M UTC")) end),fn:[.functions[]|"\(.itemid):\(.function)(\(.parameter))"],tags:(.tags|length)}' <<<"$TR" | cut -c1-300
echo "-- events of those triggers since FROM"
TIDS=$(jq -c '[.[].triggerid]' <<<"$TR")
rpc event.get "$(jq -nc --argjson t "$TIDS" --argjson f "$FROM" '{objectids:$t,source:0,object:0,time_from:$f,output:["eventid","name","clock","value","severity"],sortfield:["clock"]}')" \
 | jq -c '.[]|{id:.eventid,at:(.clock|tonumber|strftime("%F %H:%M:%S UTC")),v:(if .value=="1" then "PROBLEM" else "ok" end),n:.name,sev:.severity}' | cut -c1-260
echo "-- macros ATLAS (global)"
rpc usermacro.get '{"globalmacro":true,"search":{"macro":"ATLAS"},"output":["macro","value"]}' | jq -c '.[]'

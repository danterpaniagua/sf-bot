#!/usr/bin/env bash
# Dashboard 337 "SmartLoyalty": changes two widgets from Sum over 10m to Max over ${INTERVAL} (default 5m), Y unit "reqs" -> "req/s", title updated to match:
#   "GET Requests / 10m"          -> "GET Requests max / <INTERVAL>"
#   "Mobile POST Requests / 10m"  -> "Mobile POST Requests max / <INTERVAL>"
# Not touched: "Mobile: POST + GET" (two items in one data set, Max would drop the meaning of POST + GET), the Webservice / WebserviceV2 "POST + GET" widgets (item is already an average) and every other widget.
# dashboard.update replaces the whole widget list, so every widget is resent unchanged with its widgetid, position and fields; the after-snapshot is compared with the before-snapshot for the untouched ones.
# Without APPLY=1: read-only guards + BEFORE snapshot + plan, then stops. Rollback: zabbix-widgets-max-rollback.sh <run dir>.
set -euo pipefail
EV=${EV:-/home/dpaniagua/Documentos/git/bots/loyalty/events/20261018_mobile-spike-1900}
API=${API:-http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php}
: "${ZABBIX_API_KEY:?ZABBIX_API_KEY not set}"
APPLY=${APPLY:-0}; INTERVAL=${INTERVAL:-5m}
OUT=$EV/data/widgets-max-run-$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"
rpc() {
  local r
  r=$(jq -nc --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,id:1,auth:$a}' \
      | curl -s -X POST "$API" -H 'Content-Type: application/json' -d @-)
  if [ "$(jq 'has("error")' <<<"$r")" = true ]; then echo "ERROR $1: $(jq -c .error <<<"$r")" >&2; return 1; fi
  jq -c .result <<<"$r"
}
die() { echo "GUARD FAILED: $*" >&2; exit 1; }
getdash() { rpc dashboard.get '{"dashboardids":["337"],"output":["dashboardid","name"],"selectPages":"extend"}'; }
# whole-dashboard payload with the widgets resent as they are
PAYLOAD_JQ='{dashboardid:.[0].dashboardid,pages:[.[0].pages[]|{dashboard_pageid,name,display_period,widgets:[.widgets[]|{widgetid,type,name,x,y,width,height,view_mode,fields:[.fields[]|{type,name,value}]}]}]}'

echo "== run dir: $OUT =="
getdash > "$OUT/before-dashboard.json"
[ "$(jq -r '.[0].name' "$OUT/before-dashboard.json")" = "SmartLoyalty" ] || die "dashboard 337 is not 'SmartLoyalty'"
for n in "GET Requests / 10m" "Mobile POST Requests / 10m"; do
  [ "$(jq --arg n "$n" '[.[0].pages[].widgets[]|select(.name==$n)]|length' "$OUT/before-dashboard.json")" = 1 ] || die "widget '$n' not found exactly once"
  jq -e --arg n "$n" '.[0].pages[].widgets[]|select(.name==$n)|(.fields|map(select(.name=="ds.aggregate_function.0" and .value=="5"))|length==1) and (.fields|map(select(.name=="ds.aggregate_interval.0" and .value=="10m"))|length==1)' "$OUT/before-dashboard.json" | grep -q true || die "widget '$n' is not Sum / 10m now"
done
echo "guards passed" | tee "$OUT/guards.txt"
jq -c "$PAYLOAD_JQ" "$OUT/before-dashboard.json" > "$OUT/payload-unchanged.json"

jq -c --arg iv "$INTERVAL" '
  def retitle: if .name=="GET Requests / 10m" then "GET Requests max / \($iv)" elif .name=="Mobile POST Requests / 10m" then "Mobile POST Requests max / \($iv)" else .name end;
  def fix: if (.name=="GET Requests / 10m" or .name=="Mobile POST Requests / 10m") then
      {widgetid,type,x,y,width,height,view_mode,name:retitle,
       fields:([.fields[]|select(.name!="ds.aggregate_function.0" and .name!="ds.aggregate_interval.0" and .name!="lefty_static_units")]
               + [{type:"0",name:"ds.aggregate_function.0",value:"2"},{type:"1",name:"ds.aggregate_interval.0",value:$iv},{type:"1",name:"lefty_static_units",value:"req/s"}])}
    else . end;
  .pages |= map(.widgets |= map(fix))' "$OUT/payload-unchanged.json" > "$OUT/payload-new.json"
jq -e '[.pages[].widgets[]]|length' "$OUT/payload-new.json" > "$OUT/widget-count.txt"
[ "$(cat "$OUT/widget-count.txt")" = "$(jq '[.[0].pages[].widgets[]]|length' "$OUT/before-dashboard.json")" ] || die "widget count differs between payloads"
if [ "$APPLY" != 1 ]; then
  echo "== plan (APPLY!=1, nothing changed): widgets that differ from the current dashboard =="
  jq -c -n --slurpfile a "$OUT/payload-unchanged.json" --slurpfile b "$OUT/payload-new.json" '[$a[0].pages[].widgets[]] as $x | [$b[0].pages[].widgets[]] as $y | [range(0;$x|length)|select($x[.]!=$y[.])|{before:$x[.],after:$y[.]}]'
  echo "dry run done; re-run with APPLY=1"; exit 0
fi
rpc dashboard.update "$(cat "$OUT/payload-new.json")" | tee "$OUT/update-result.json"
getdash > "$OUT/after-dashboard.json"
echo "-- untouched widgets identical to before? (name, type, position, fields)"
norm='[.[0].pages[].widgets[]|select(.name!="GET Requests / 10m" and .name!="Mobile POST Requests / 10m" and (.name|test("max / ")|not))|{name,type,x,y,width,height,fields:[.fields[]|{type,name,value}]}]'
if [ "$(jq -c "$norm" "$OUT/before-dashboard.json")" = "$(jq -c "$norm" "$OUT/after-dashboard.json")" ]; then echo "yes"; else echo "NO - compare before/after in $OUT"; fi
echo "done: $OUT (rollback: zabbix-widgets-max-rollback.sh $OUT)"

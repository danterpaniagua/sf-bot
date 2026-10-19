#!/usr/bin/env bash
# GITIN-2250 — memory commit-ratio alerting aligned with healthcheck.ashx (which answers 400 above 80 % of Committed Bytes / Commit Limit).
# Per host (14 SFCG loyalty hosts): item perf_counter_en["\Memory\% Committed Bytes In Use"] (active agent, 1m) + 3 triggers Warning 70 / Average 75 / High 80,
# avg over 10m; recovery only when max over 15m is below 60. Routed to Operaciones Chat (action 7 tags). Creates only. Rollback: zabbix-mem-commit-rollback.sh <run dir>.
# Without APPLY=1: read-only guards + plan, then stops.
set -euo pipefail
EV=${EV:-/home/dpaniagua/Documentos/git/bots/loyalty/events/20261018_gitin2250-webservice-high-cpu}
API=${API:-http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php}
: "${ZABBIX_API_KEY:?ZABBIX_API_KEY not set}"
APPLY=${APPLY:-0}
OUT=$EV/data/mem-commit-run-$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"

HOSTS=(SFCG-CLUB-01 SFCG-CLUB-02 SFCG-JENKINS-01 SFCG-MOBI-01 SFCG-MOBI-02 SFCG-SMTP-01 SFCG-TO-01
       SFCG-WEBS-01 SFCG-WEBS-02 SFCG-WEBS-03 SFCG-WSCG-01 SFCG-WSIT-01 SFCG-WSV2-01 SFCG-WSV2-02)
KEY='perf_counter_en["\Memory\% Committed Bytes In Use"]'
MACROS='[{"macro":"{$MEM.COMMIT.WARN}","value":"70"},{"macro":"{$MEM.COMMIT.AVG}","value":"75"},{"macro":"{$MEM.COMMIT.HIGH}","value":"80"},{"macro":"{$MEM.COMMIT.TIME}","value":"10m"},{"macro":"{$MEM.COMMIT.OK}","value":"60"},{"macro":"{$MEM.COMMIT.OK.TIME}","value":"15m"}]'
TAGS='[{"tag":"scope","value":"performance"},{"tag":"scope","value":"GIT-SML-OPE"},{"tag":"service_group","value":"LOYALTY"},{"tag":"action","value":"GCHAT"},{"tag":"SVC_FRIENDLYNAME","value":"Memory commit"}]'

rpc() {
  local r
  r=$(jq -nc --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,id:1,auth:$a}' \
      | curl -s -X POST "$API" -H 'Content-Type: application/json' -d @-)
  if [ "$(jq 'has("error")' <<<"$r")" = true ]; then echo "ERROR $1: $(jq -c .error <<<"$r")" >&2; return 1; fi
  jq -c .result <<<"$r"
}
die() { echo "GUARD FAILED: $*" >&2; exit 1; }
item_params() { jq -nc --arg id "$1" --arg k "$KEY" '{hostid:$id,name:"Windows: Committed bytes in use (%)",key_:$k,type:7,value_type:0,delay:"1m",history:"30d",trends:"90d",units:"%"}'; }
tier() { # host tier
  local host=$1 t=$2 prio macro
  case $t in High) prio=4; macro='{$MEM.COMMIT.HIGH}';; Average) prio=3; macro='{$MEM.COMMIT.AVG}';; Warning) prio=2; macro='{$MEM.COMMIT.WARN}';; esac
  jq -nc --arg d "Memory committed above $macro% for {\$MEM.COMMIT.TIME} ($t)" \
         --arg e "avg(/$host/$KEY,{\$MEM.COMMIT.TIME})>$macro" \
         --arg r "max(/$host/$KEY,{\$MEM.COMMIT.OK.TIME})<{\$MEM.COMMIT.OK}" \
         --argjson p "$prio" --argjson tags "$TAGS" \
    '{description:$d,expression:$e,recovery_mode:1,recovery_expression:$r,priority:$p,tags:$tags,manual_close:0}'
}

echo "== run dir: $OUT =="
n=$(rpc usermacro.get '{"globalmacro":true,"output":["macro"],"search":{"macro":"MEM.COMMIT"}}' | jq length)
[ "$n" = 0 ] || die "global macros matching MEM.COMMIT already exist ($n)"
declare -A HID
for h in "${HOSTS[@]}"; do
  hs=$(rpc host.get "$(jq -nc --arg h "$h" '{filter:{host:[$h]},output:["hostid","host","status"]}')")
  [ "$(jq length <<<"$hs")" = 1 ] || die "$h: host not found or ambiguous"
  [ "$(jq -r '.[0].status' <<<"$hs")" = 0 ] || die "$h: host not monitored"
  hid=$(jq -r '.[0].hostid' <<<"$hs"); HID[$h]=$hid
  it=$(rpc item.get "$(jq -nc --arg id "$hid" '{hostids:[$id],search:{key_:"Committed Bytes"},output:["itemid","key_"]}')")
  [ "$(jq length <<<"$it")" = 0 ] || die "$h: an item with 'Committed Bytes' in its key already exists: $(jq -c . <<<"$it")"
  tr=$(rpc trigger.get "$(jq -nc --arg id "$hid" '{hostids:[$id],search:{description:"Memory committed above"},output:["triggerid"]}')")
  [ "$(jq length <<<"$tr")" = 0 ] || die "$h: 'Memory committed above' triggers already exist"
  jq -nc --arg h "$h" --arg id "$hid" '{host:$h,hostid:$id}' >> "$OUT/before-hosts.jsonl"
done
echo "guards passed for ${#HOSTS[@]} hosts" | tee "$OUT/guards.txt"

if [ "$APPLY" != 1 ]; then
  { echo "== plan (APPLY!=1, nothing created) =="; echo "$MACROS" | jq -c '.[]'
    h=${HOSTS[0]}; echo "-- item (per host)"; item_params "${HID[$h]}" | jq -c .
    for t in High Average Warning; do echo "-- $h $t"; tier "$h" "$t" | jq -c '{description,expression,recovery_expression,priority}'; done
    echo "(same item and 3 triggers on each of the ${#HOSTS[@]} hosts)"; } | tee "$OUT/plan.txt"
  echo "dry run done; re-run with APPLY=1 to create"; exit 0
fi

mids=$(rpc usermacro.createglobal "$MACROS"); echo "$mids" > "$OUT/created-globalmacroids.json"; echo "macros created: $mids"
: > "$OUT/created.tsv"
for h in "${HOSTS[@]}"; do
  iid=$(rpc item.create "$(item_params "${HID[$h]}")" | jq -r '.itemids[0]')
  hi=$(rpc trigger.create "$(tier "$h" High)" | jq -r '.triggerids[0]')
  av=$(rpc trigger.create "$(tier "$h" Average | jq -c --arg d "$hi" '.dependencies=[{triggerid:$d}]')" | jq -r '.triggerids[0]')
  wa=$(rpc trigger.create "$(tier "$h" Warning | jq -c --arg d "$hi" --arg a "$av" '.dependencies=[{triggerid:$a},{triggerid:$d}]')" | jq -r '.triggerids[0]')
  printf '%s\t%s\t%s\t%s\t%s\n' "$h" "$iid" "$wa" "$av" "$hi" | tee -a "$OUT/created.tsv"
done
ids=$(awk -F'\t' '{print "\""$3"\",\""$4"\",\""$5"\""}' "$OUT/created.tsv" | paste -sd, -)
rpc trigger.get "{\"triggerids\":[$ids],\"output\":[\"triggerid\",\"description\",\"priority\",\"status\"],\"selectFunctions\":\"extend\",\"selectHosts\":[\"host\"],\"selectTags\":[\"tag\",\"value\"],\"selectDependencies\":[\"triggerid\"]}" > "$OUT/after-triggers.json"
echo "done: $OUT (rollback: zabbix-mem-commit-rollback.sh $OUT)"

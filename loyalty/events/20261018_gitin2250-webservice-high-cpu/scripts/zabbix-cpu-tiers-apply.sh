#!/usr/bin/env bash
# GITIN-2250 — three-tier CPU utilization triggers (Warning 70 / Average 80 / High 85, avg over 10m) on the SFCG loyalty hosts, routed to Operaciones Chat (action 7).
# Zabbix 6.0 API. Creates only (7 global macros + 3 triggers per host); changes no existing trigger. Rollback: zabbix-cpu-tiers-rollback.sh <run dir>.
# Without APPLY=1 it runs the read-only guards, writes the BEFORE snapshot and the plan, and stops. With APPLY=1 it creates.
set -euo pipefail
EV=${EV:-/home/dpaniagua/Documentos/git/bots/loyalty/events/20261018_gitin2250-webservice-high-cpu}
API=${API:-http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php}
: "${ZABBIX_API_KEY:?ZABBIX_API_KEY not set}"
APPLY=${APPLY:-0}
OUT=$EV/data/cpu-tiers-run-$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"

HOSTS=(SFCG-CLUB-01 SFCG-CLUB-02 SFCG-JENKINS-01 SFCG-MOBI-01 SFCG-MOBI-02 SFCG-SMTP-01 SFCG-TO-01
       SFCG-WEBS-01 SFCG-WEBS-02 SFCG-WEBS-03 SFCG-WSCG-01 SFCG-WSIT-01 SFCG-WSV2-01 SFCG-WSV2-02)
KEY=system.cpu.util
MACROS='[{"macro":"{$CPU.UTIL.WARN}","value":"70"},{"macro":"{$CPU.UTIL.AVG}","value":"80"},{"macro":"{$CPU.UTIL.HIGH}","value":"85"},{"macro":"{$CPU.UTIL.TIME}","value":"10m"},{"macro":"{$CPU.UTIL.WARN.OK}","value":"60"},{"macro":"{$CPU.UTIL.AVG.OK}","value":"70"},{"macro":"{$CPU.UTIL.HIGH.OK}","value":"75"}]'
TAGS='[{"tag":"scope","value":"performance"},{"tag":"scope","value":"GIT-SML-OPE"},{"tag":"service_group","value":"LOYALTY"},{"tag":"action","value":"GCHAT"},{"tag":"SVC_FRIENDLYNAME","value":"CPU utilization"}]'

rpc() { # method, params-json -> prints .result, aborts on .error
  local r
  r=$(jq -nc --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,id:1,auth:$a}' \
      | curl -s -X POST "$API" -H 'Content-Type: application/json' -d @-)
  if [ "$(jq 'has("error")' <<<"$r")" = true ]; then echo "ERROR $1: $(jq -c .error <<<"$r")" >&2; return 1; fi
  jq -c .result <<<"$r"
}
die() { echo "GUARD FAILED: $*" >&2; exit 1; }

echo "== run dir: $OUT =="
# --- guards (read only): nothing is written if any of these fails ---
n=$(rpc usermacro.get '{"globalmacro":true,"output":["macro"],"search":{"macro":"CPU.UTIL"}}' | jq 'length')
[ "$n" = 0 ] || die "global macros matching CPU.UTIL already exist ($n)"
declare -A HID
for h in "${HOSTS[@]}"; do
  hs=$(rpc host.get "$(jq -nc --arg h "$h" '{filter:{host:[$h]},output:["hostid","host","status"]}')")
  [ "$(jq 'length' <<<"$hs")" = 1 ] || die "$h: host not found or ambiguous"
  [ "$(jq -r '.[0].status' <<<"$hs")" = 0 ] || die "$h: host not monitored (status != 0)"
  hid=$(jq -r '.[0].hostid' <<<"$hs"); HID[$h]=$hid
  it=$(rpc item.get "$(jq -nc --arg id "$hid" --arg k "$KEY" '{hostids:[$id],filter:{key_:[$k]},output:["itemid","name","status","state"]}')")
  [ "$(jq 'length' <<<"$it")" = 1 ] || die "$h: item $KEY not found or ambiguous"
  [ "$(jq -r '.[0].status' <<<"$it")" = 0 ] || die "$h: item $KEY disabled"
  tr=$(rpc trigger.get "$(jq -nc --arg id "$hid" '{hostids:[$id],output:["triggerid","description"],search:{description:"CPU utilization above"}}')")
  [ "$(jq 'length' <<<"$tr")" = 0 ] || die "$h: a trigger 'CPU utilization above ...' already exists"
  jq -nc --arg h "$h" --arg id "$hid" --argjson it "$it" '{host:$h,hostid:$id,item:$it[0]}' >> "$OUT/before-hosts.jsonl"
done
echo "guards passed for ${#HOSTS[@]} hosts" | tee "$OUT/guards.txt"

tier() { # host tier -> trigger.create params (dependencies filled by caller)
  local host=$1 t=$2 prio name macro okmacro
  case $t in High) prio=4; macro='{$CPU.UTIL.HIGH}'; okmacro='{$CPU.UTIL.HIGH.OK}';;
             Average) prio=3; macro='{$CPU.UTIL.AVG}'; okmacro='{$CPU.UTIL.AVG.OK}';;
             Warning) prio=2; macro='{$CPU.UTIL.WARN}'; okmacro='{$CPU.UTIL.WARN.OK}';; esac
  name="CPU utilization above $macro% for {\$CPU.UTIL.TIME} ($t)"
  jq -nc --arg d "$name" --arg e "avg(/$host/$KEY,{\$CPU.UTIL.TIME})>$macro" --arg r "max(/$host/$KEY,{\$CPU.UTIL.TIME})<$okmacro" \
         --argjson p "$prio" --argjson tags "$TAGS" \
    '{description:$d,expression:$e,recovery_mode:1,recovery_expression:$r,priority:$p,tags:$tags,manual_close:0}'
}

if [ "$APPLY" != 1 ]; then
  { echo "== plan (APPLY!=1, nothing created) =="; echo "$MACROS" | jq -c '.[]'
    for h in "${HOSTS[@]}"; do for t in High Average Warning; do echo "$h $t: $(tier "$h" "$t" | jq -c '{description,expression,recovery_expression,priority}')"; done; done; } | tee "$OUT/plan.txt"
  echo "dry run done; re-run with APPLY=1 to create"; exit 0
fi

# --- apply ---
rpc usermacro.get '{"globalmacro":true,"output":["globalmacroid","macro","value"],"search":{"macro":"CPU.UTIL"}}' > "$OUT/before-global-macros.json"
mids=$(rpc usermacro.createglobal "$MACROS"); echo "$mids" > "$OUT/created-globalmacroids.json"
echo "macros created: $mids"
: > "$OUT/created-triggerids.tsv"
for h in "${HOSTS[@]}"; do
  hi=$(rpc trigger.create "$(tier "$h" High)" | jq -r '.triggerids[0]')
  av=$(rpc trigger.create "$(tier "$h" Average | jq -c --arg d "$hi" '.dependencies=[{triggerid:$d}]')" | jq -r '.triggerids[0]')
  wa=$(rpc trigger.create "$(tier "$h" Warning | jq -c --arg d "$hi" --arg a "$av" '.dependencies=[{triggerid:$a},{triggerid:$d}]')" | jq -r '.triggerids[0]')
  printf '%s\t%s\t%s\t%s\n' "$h" "$wa" "$av" "$hi" | tee -a "$OUT/created-triggerids.tsv"
done
# --- AFTER snapshot (raw expressions, not expanded) ---
ids=$(awk -F'\t' '{print "\""$2"\",\""$3"\",\""$4"\""}' "$OUT/created-triggerids.tsv" | paste -sd, -)
rpc trigger.get "{\"triggerids\":[$ids],\"output\":[\"triggerid\",\"description\",\"expression\",\"recovery_expression\",\"priority\",\"status\"],\"selectHosts\":[\"host\"],\"selectTags\":[\"tag\",\"value\"],\"selectDependencies\":[\"triggerid\"]}" > "$OUT/after-triggers.json"
echo "done: $OUT (rollback: zabbix-cpu-tiers-rollback.sh $OUT)"

#!/usr/bin/env bash
# GITIN-2250 — disk alerting on template 10351 "Windows by Zabbix agent active" (reaches the 14 prod hosts and the 4 disabled ones linked to it):
#  1. global-template macro {$VFS.FS.PUSED.MAX.HIGH}=95 on the template;
#  2. new trigger prototype "Disk space is very high" (priority 4): used % > {$VFS.FS.PUSED.MAX.HIGH} (bound to rule 42546 through the item prototype in the expression; the API takes no ruleid);
#  3. routing tags added to the stock prototypes 22495-22497 (latency) and 22499-22500 (space) and to the new one. Existing tags are kept (tags update REPLACES the list).
# Routing tags: scope:GIT-SML-OPE, service_group:LOYALTY, action:GCHAT (action 7, Operaciones Chat). env:PROD (action 12, Telegram) only with ENVPROD=1; default off because 9-15 disk triggers per host would reach Telegram.
# Stock thresholds (80 / 90 % and free space) are not changed. No dependency is set between the 90 % critical and the new 95 % trigger.
# Without APPLY=1: read-only guards + BEFORE snapshot + plan, then stops. Rollback: zabbix-disk-template-rollback.sh <run dir>.
set -euo pipefail
EV=${EV:-/home/dpaniagua/Documentos/git/bots/loyalty/events/20261018_gitin2250-webservice-high-cpu}
API=${API:-http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php}
: "${ZABBIX_API_KEY:?ZABBIX_API_KEY not set}"
APPLY=${APPLY:-0}; ENVPROD=${ENVPROD:-0}
OUT=$EV/data/disk-template-run-$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"
TPL_ID=10351; TPL_NAME='Windows by Zabbix agent active'; LLD_FS=42546
PIDS='["22495","22496","22497","22499","22500"]'
rpc() {
  local r
  r=$(jq -nc --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,id:1,auth:$a}' \
      | curl -s -X POST "$API" -H 'Content-Type: application/json' -d @-)
  if [ "$(jq 'has("error")' <<<"$r")" = true ]; then echo "ERROR $1: $(jq -c .error <<<"$r")" >&2; return 1; fi
  jq -c .result <<<"$r"
}
die() { echo "GUARD FAILED: $*" >&2; exit 1; }
ROUTE='[{"tag":"scope","value":"GIT-SML-OPE"},{"tag":"service_group","value":"LOYALTY"},{"tag":"action","value":"GCHAT"}]'
[ "$ENVPROD" = 1 ] && ROUTE=$(jq -c '. + [{tag:"env",value:"PROD"}]' <<<"$ROUTE")

echo "== run dir: $OUT =="
[ "$(rpc template.get "$(jq -nc --arg i "$TPL_ID" '{templateids:[$i],output:["host"]}')" | jq -r '.[0].host')" = "$TPL_NAME" ] || die "template $TPL_ID is not '$TPL_NAME'"
rpc triggerprototype.get "$(jq -nc --argjson p "$PIDS" '{triggerids:$p,output:["triggerid","description","priority"],selectTags:["tag","value"],selectFunctions:"extend"}')" > "$OUT/before-prototypes.json"
[ "$(jq length "$OUT/before-prototypes.json")" = 5 ] || die "expected 5 stock prototypes"
jq -e 'all(.[]; .tags|any(.tag=="scope" and .value=="GIT-SML-OPE")|not)' "$OUT/before-prototypes.json" >/dev/null || die "a prototype already has routing tags"
[ "$(rpc triggerprototype.get '{"hostids":["'$TPL_ID'"],"filter":{"description":["{#FSLABEL}({#FSNAME}): Disk space is very high"]},"output":["triggerid"]}' | jq length)" = 0 ] || die "very-high prototype already exists"
# the macro may be left over from a first attempt that failed after creating it (2026-10-18 20:33, id 7484): reuse it if it is exactly 95
rpc usermacro.get '{"hostids":["'$TPL_ID'"],"filter":{"macro":["{$VFS.FS.PUSED.MAX.HIGH}"]},"output":["hostmacroid","value"]}' > "$OUT/before-macro.json"
jq -e 'length==0 or (length==1 and .[0].value=="95")' "$OUT/before-macro.json" >/dev/null || die "macro exists with another value"
echo "guards passed" | tee "$OUT/guards.txt"

NEWTP=$(jq -nc --arg e "last(/$TPL_NAME/vfs.fs.size[{#FSNAME},pused])>{\$VFS.FS.PUSED.MAX.HIGH:\"{#FSNAME}\"}" --argjson r "$ROUTE" \
  '{description:"{#FSLABEL}({#FSNAME}): Disk space is very high",expression:$e,priority:4,
    tags:([{tag:"scope",value:"capacity"},{tag:"SVC_FRIENDLYNAME",value:"Disk space of {#FSLABEL}({#FSNAME})"}] + $r)}')
UPD=$(jq -c --argjson r "$ROUTE" '[.[] | {triggerid, tags: (.tags + $r)}]' "$OUT/before-prototypes.json")
{ echo "macro {\$VFS.FS.PUSED.MAX.HIGH}=95 on $TPL_ID"; echo "$NEWTP"; echo "$UPD"; } > "$OUT/plan.txt"
if [ "$APPLY" != 1 ]; then echo "== plan (APPLY!=1, nothing changed) =="; cat "$OUT/plan.txt"; echo "dry run done; re-run with APPLY=1"; exit 0; fi

if [ "$(jq length "$OUT/before-macro.json")" = 0 ]; then
  rpc usermacro.create "{\"hostid\":\"$TPL_ID\",\"macro\":\"{\$VFS.FS.PUSED.MAX.HIGH}\",\"value\":\"95\"}" | tee "$OUT/macro-result.json"
else
  jq -c '{hostmacroids:[.[0].hostmacroid]}' "$OUT/before-macro.json" | tee "$OUT/macro-result.json"
fi
rpc triggerprototype.create "$NEWTP" | tee "$OUT/create-result.json"
rpc triggerprototype.update "$UPD" | tee "$OUT/update-result.json"
rpc triggerprototype.get "$(jq -nc '{hostids:["'$TPL_ID'"],search:{description:"Disk"},output:["triggerid","description","priority","expression"],selectTags:["tag","value"]}')" > "$OUT/after-prototypes.json"
echo "done: $OUT (rollback: zabbix-disk-template-rollback.sh $OUT)"

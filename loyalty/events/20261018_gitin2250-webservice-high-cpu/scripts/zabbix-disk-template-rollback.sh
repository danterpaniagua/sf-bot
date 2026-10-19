#!/usr/bin/env bash
# GITIN-2250 — rollback of zabbix-disk-template-apply.sh: restores the tag lists of the 5 stock prototypes from the BEFORE snapshot,
# deletes the "Disk space is very high" prototype and the macro {$VFS.FS.PUSED.MAX.HIGH} (ids read from the run's result files).
# Usage: zabbix-disk-template-rollback.sh <run dir>   (APPLY=1 to apply; otherwise prints the plan)
set -euo pipefail
RUN=${1:?usage: $0 <run dir>}
API=${API:-http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php}
: "${ZABBIX_API_KEY:?ZABBIX_API_KEY not set}"
APPLY=${APPLY:-0}
for f in before-prototypes.json create-result.json macro-result.json; do [ -s "$RUN/$f" ] || { echo "no $f in $RUN" >&2; exit 1; }; done
rpc() {
  local r
  r=$(jq -nc --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,id:1,auth:$a}' \
      | curl -s -X POST "$API" -H 'Content-Type: application/json' -d @-)
  if [ "$(jq 'has("error")' <<<"$r")" = true ]; then echo "ERROR $1: $(jq -c .error <<<"$r")" >&2; return 1; fi
  jq -c .result <<<"$r"
}
TP=$(jq -r '.triggerids[0]' "$RUN/create-result.json"); MID=$(jq -r '.hostmacroids[0]' "$RUN/macro-result.json")
[[ "$TP" =~ ^[0-9]+$ && "$MID" =~ ^[0-9]+$ ]] || { echo "GUARD FAILED: ids not found in result files" >&2; exit 1; }
d=$(rpc triggerprototype.get "$(jq -nc --arg t "$TP" '{triggerids:[$t],output:["description"]}')" | jq -r '.[0].description')
[ "$d" = "{#FSLABEL}({#FSNAME}): Disk space is very high" ] || { echo "GUARD FAILED: prototype $TP is '$d'" >&2; exit 1; }
PAYLOAD=$(jq -c '[.[] | {triggerid, tags}]' "$RUN/before-prototypes.json")
echo "restore tags: $PAYLOAD"; echo "delete prototype $TP and macro $MID"
if [ "$APPLY" = 1 ]; then
  echo "restore: $(rpc triggerprototype.update "$PAYLOAD")"
  echo "delete prototype: $(rpc triggerprototype.delete "[\"$TP\"]")"
  echo "delete macro: $(rpc usermacro.delete "[\"$MID\"]")"
else echo "(dry run; APPLY=1 to apply)"; fi

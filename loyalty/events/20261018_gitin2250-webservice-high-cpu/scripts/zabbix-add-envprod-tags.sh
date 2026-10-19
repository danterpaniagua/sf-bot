#!/usr/bin/env bash
# GITIN-2250 — adds tag env:PROD to the new CPU (42) and RAM commit (42) tier triggers so that action 12 (Chat + Telegram, condition env = PROD) also matches them.
# They keep their current tags (action 7 still matches). trigger.update with tags REPLACES the tag list, so each trigger is resent with its existing tags plus env:PROD.
# Without APPLY=1: read-only guards + BEFORE snapshot + plan, then stops. Rollback: zabbix-add-envprod-tags-rollback.sh <run dir>.
set -euo pipefail
EV=${EV:-/home/dpaniagua/Documentos/git/bots/loyalty/events/20261018_gitin2250-webservice-high-cpu}
API=${API:-http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php}
: "${ZABBIX_API_KEY:?ZABBIX_API_KEY not set}"
APPLY=${APPLY:-0}
OUT=$EV/data/envprod-tags-run-$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"
rpc() {
  local r
  r=$(jq -nc --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,id:1,auth:$a}' \
      | curl -s -X POST "$API" -H 'Content-Type: application/json' -d @-)
  if [ "$(jq 'has("error")' <<<"$r")" = true ]; then echo "ERROR $1: $(jq -c .error <<<"$r")" >&2; return 1; fi
  jq -c .result <<<"$r"
}
die() { echo "GUARD FAILED: $*" >&2; exit 1; }
echo "== run dir: $OUT =="
get() { rpc trigger.get "$(jq -nc --arg s "$1" '{search:{description:$s},output:["triggerid","description"],selectTags:["tag","value"],selectHosts:["host"]}')"; }
{ get "CPU utilization above"; get "Memory committed above"; } | jq -s 'add' > "$OUT/before-triggers.json"
n=$(jq length "$OUT/before-triggers.json")
[ "$n" = 84 ] || die "expected 84 triggers (42 CPU + 42 RAM), found $n"
jq -e 'all(.[]; (.tags|any(.tag=="scope" and .value=="GIT-SML-OPE")))' "$OUT/before-triggers.json" >/dev/null || die "a trigger lacks scope:GIT-SML-OPE (not one of ours)"
jq -e 'any(.[]; .tags|any(.tag=="env"))' "$OUT/before-triggers.json" >/dev/null && die "a trigger already has an env tag"
echo "guards passed: 84 triggers" | tee "$OUT/guards.txt"
# payload: every trigger resent with its existing tags plus env:PROD
jq -c '[.[] | {triggerid, tags: (.tags + [{tag:"env",value:"PROD"}])}]' "$OUT/before-triggers.json" > "$OUT/plan.json"
if [ "$APPLY" != 1 ]; then echo "== plan (APPLY!=1, nothing changed) =="; jq -c '.[0]' "$OUT/plan.json"; echo "(+83 more); re-run with APPLY=1"; exit 0; fi
rpc trigger.update "$(cat "$OUT/plan.json")" | tee "$OUT/update-result.json"
{ get "CPU utilization above"; get "Memory committed above"; } | jq -s 'add' > "$OUT/after-triggers.json"
echo "done: $OUT (rollback: zabbix-add-envprod-tags-rollback.sh $OUT)"

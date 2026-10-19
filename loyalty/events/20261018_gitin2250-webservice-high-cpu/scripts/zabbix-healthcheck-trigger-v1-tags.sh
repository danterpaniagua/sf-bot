#!/usr/bin/env bash
# GITIN-2250 — (1) creates ONE trigger on host sfcg-monitoreo for step Healthcheck of web scenario 6 ("[PROD] API POS / Gestion"): problem when 3 of the last 5 checks are not HTTP 200;
# (2) adds routing tags to the untagged V1 triggers 25746 (HTTP Code not 200) and 25753 (Response Time > 300ms). Expressions of 25746/25753 are NOT changed.
# trigger.update with tags REPLACES the tag list; both triggers have tags [] now (guarded). No env:PROD tag here (not decided for these).
# Without APPLY=1: read-only guards + BEFORE snapshot + plan, then stops. Rollback: zabbix-healthcheck-trigger-v1-tags-rollback.sh <run dir> (not written yet).
set -euo pipefail
EV=${EV:-/home/dpaniagua/Documentos/git/bots/loyalty/events/20261018_gitin2250-webservice-high-cpu}
API=${API:-http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php}
: "${ZABBIX_API_KEY:?ZABBIX_API_KEY not set}"
APPLY=${APPLY:-0}
OUT=$EV/data/hc-trigger-v1-tags-run-$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"
MON_HOST=sfcg-monitoreo; MON_ID=10610
SCEN='[PROD] API POS / Gestion'
KEY="web.test.rspcode[\"$SCEN\",Healthcheck]"
FAILS=3; LAST=5
tags_for() { jq -nc --arg s "$1" --arg f "$2" '[{tag:"scope",value:$s},{tag:"scope",value:"GIT-SML-OPE"},{tag:"service_group",value:"LOYALTY"},{tag:"action",value:"GCHAT"},{tag:"SVC_FRIENDLYNAME",value:$f}]'; }

rpc() {
  local r
  r=$(jq -nc --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,id:1,auth:$a}' \
      | curl -s -X POST "$API" -H 'Content-Type: application/json' -d @-)
  if [ "$(jq 'has("error")' <<<"$r")" = true ]; then echo "ERROR $1: $(jq -c .error <<<"$r")" >&2; return 1; fi
  jq -c .result <<<"$r"
}
die() { echo "GUARD FAILED: $*" >&2; exit 1; }

echo "== run dir: $OUT =="
# --- guards (read only) ---
[ "$(rpc host.get "$(jq -nc --arg h "$MON_HOST" '{filter:{host:[$h]},output:["hostid"]}')" | jq -r '.[0].hostid')" = "$MON_ID" ] || die "$MON_HOST is not hostid $MON_ID"
[ "$(rpc item.get "$(jq -nc --arg k "$KEY" --arg h "$MON_ID" '{hostids:[$h],webitems:true,filter:{key_:[$k]},output:["itemid"]}')" | jq length)" = 1 ] || die "item $KEY not found exactly once"
[ "$(rpc trigger.get "$(jq -nc --arg d "WebService: healthcheck.ashx HTTP code not 200 (via LB)" '{filter:{description:[$d]},output:["triggerid"]}')" | jq length)" = 0 ] || die "healthcheck trigger already exists"
rpc trigger.get '{"triggerids":["25746","25753"],"output":["triggerid","description","expression","recovery_expression","priority"],"selectTags":["tag","value"],"selectFunctions":"extend"}' > "$OUT/before-v1-triggers.json"
[ "$(jq length "$OUT/before-v1-triggers.json")" = 2 ] || die "25746/25753 not both found"
jq -e 'all(.[]; .tags|length==0)' "$OUT/before-v1-triggers.json" >/dev/null || die "a V1 trigger already has tags"
jq -e '[.[]|.description]|sort==["WebServiceV1 Response Time > 300ms","WebServiceV1. HTTP Code not 200"]' "$OUT/before-v1-triggers.json" >/dev/null || die "V1 trigger names differ"
echo "guards passed" | tee "$OUT/guards.txt"

NEWTRIG=$(jq -nc --arg k "$KEY" --argjson f "$FAILS" --argjson n "$LAST" --arg m "$MON_HOST" --argjson tags "$(tags_for availability 'WebService healthcheck (LB)')" \
  '{description:"WebService: healthcheck.ashx HTTP code not 200 (via LB)",
    expression:"count(/\($m)/\($k),#\($n),\"ne\",200)>=\($f)",
    recovery_mode:1, recovery_expression:"count(/\($m)/\($k),#\($n),\"ne\",200)=0",
    priority:4, tags:$tags, manual_close:0}')
UPD=$(jq -nc --argjson a "$(tags_for availability 'WebService V1 HTTP code')" --argjson b "$(tags_for performance 'WebService V1 response time')" \
  '[{triggerid:"25746",tags:$a},{triggerid:"25753",tags:$b}]')
{ echo "$NEWTRIG"; echo "$UPD"; } > "$OUT/plan.json"
if [ "$APPLY" != 1 ]; then echo "== plan (APPLY!=1, nothing changed) =="; jq -c . "$OUT/plan.json"; echo "dry run done; re-run with APPLY=1"; exit 0; fi

rpc trigger.create "$NEWTRIG" | tee "$OUT/create-result.json"
rpc trigger.update "$UPD" | tee "$OUT/update-result.json"
rpc trigger.get '{"search":{"description":"WebService"},"hostids":["10610"],"output":["triggerid","description","expression"],"selectTags":["tag","value"]}' > "$OUT/after-hc-trigger.json"
rpc trigger.get '{"triggerids":["25746","25753"],"output":["triggerid","description","expression","recovery_expression"],"selectTags":["tag","value"]}' > "$OUT/after-v1-triggers.json"
echo "done: $OUT"

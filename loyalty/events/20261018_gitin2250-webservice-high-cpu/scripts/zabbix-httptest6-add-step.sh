#!/usr/bin/env bash
# GITIN-2250 — adds ONE step to web scenario 6 ("[PROD] API POS / Gestion"): GET http://webservice.clubgrido.com.ar:8080/healthcheck.ashx through the LB name, status 200 required.
# Nothing else changes (no tags, no triggers, step 1 resent unchanged because httptest.update replaces the whole step list).
# Without APPLY=1: read-only guards + BEFORE snapshot + plan, then stops. Rollback: zabbix-httptest6-add-step-rollback.sh <run dir>.
set -euo pipefail
EV=${EV:-/home/dpaniagua/Documentos/git/bots/loyalty/events/20261018_gitin2250-webservice-high-cpu}
API=${API:-http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php}
: "${ZABBIX_API_KEY:?ZABBIX_API_KEY not set}"
APPLY=${APPLY:-0}
OUT=$EV/data/httptest6-add-step-run-$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"
NEW_URL=http://webservice.clubgrido.com.ar:8080/healthcheck.ashx

rpc() {
  local r
  r=$(jq -nc --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,id:1,auth:$a}' \
      | curl -s -X POST "$API" -H 'Content-Type: application/json' -d @-)
  if [ "$(jq 'has("error")' <<<"$r")" = true ]; then echo "ERROR $1: $(jq -c .error <<<"$r")" >&2; return 1; fi
  jq -c .result <<<"$r"
}
die() { echo "GUARD FAILED: $*" >&2; exit 1; }

echo "== run dir: $OUT =="
rpc httptest.get '{"httptestids":["6"],"output":"extend","selectSteps":"extend"}' > "$OUT/before-httptest6.json"
b=$(jq -c '.[0]' "$OUT/before-httptest6.json")
[ "$(jq -r .name <<<"$b")" = "[PROD] API POS / Gestion" ] || die "httptest 6 is not '[PROD] API POS / Gestion'"
[ "$(jq -r '.steps|length' <<<"$b")" = 1 ] || die "httptest 6 does not have exactly 1 step now"
[ "$(jq -r '.steps[0].httpstepid' <<<"$b")" = 9 ] || die "step 1 is not httpstepid 9"
jq -e '.steps[0].url|test("SaleProvider.svc")' <<<"$b" >/dev/null || die "step 1 URL is not the expected one"
echo "guards passed" | tee "$OUT/guards.txt"

# step 1 is resent with its id and its current values; step 2 is new
PARAMS=$(jq -nc --argjson b "$b" --arg u "$NEW_URL" '{httptestid:"6",steps:[
  ($b.steps[0] | {httpstepid,name,no,url,timeout,status_codes,follow_redirects,retrieve_mode,required}),
  {name:"Healthcheck",no:"2",url:$u,timeout:"15s",status_codes:"200",follow_redirects:"0",retrieve_mode:"0",required:""}]}')
echo "$PARAMS" > "$OUT/plan.json"
if [ "$APPLY" != 1 ]; then echo "== plan (APPLY!=1, nothing changed) =="; jq . "$OUT/plan.json"; echo "dry run done; re-run with APPLY=1"; exit 0; fi

rpc httptest.update "$PARAMS" | tee "$OUT/update-result.json"
rpc httptest.get '{"httptestids":["6"],"output":["httptestid","name"],"selectSteps":"extend"}' > "$OUT/after-httptest6.json"
rpc item.get '{"hostids":["10610"],"webitems":true,"search":{"key_":"API POS"},"output":["itemid","name","key_","state","error"]}' > "$OUT/after-items.json"
echo "done: $OUT (rollback: zabbix-httptest6-add-step-rollback.sh $OUT)"

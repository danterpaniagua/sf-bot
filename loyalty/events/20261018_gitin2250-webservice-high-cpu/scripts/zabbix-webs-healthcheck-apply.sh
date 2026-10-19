#!/usr/bin/env bash
# GITIN-2250 — ONE Zabbix web scenario that calls healthcheck.ashx through the WEBS load balancer name (same name httptest 6 uses; with SourceIP distribution the
# proxy's checks land on one backend), plus a trigger routed to Operaciones Chat. Modelled on httptest 6 ("[PROD] API POS / Gestion": host sfcg-monitoreo, delay 1m, retries 1, agent Zabbix, step timeout 15s, status 200).
# Creates only. Rollback: zabbix-webs-healthcheck-rollback.sh <run dir>. Without APPLY=1: read-only guards + plan, then stops.
# PRECONDITION: the proxy of host sfcg-monitoreo must resolve and reach the LB name on 8080 (check with curl from that machine first).
set -euo pipefail
EV=${EV:-/home/dpaniagua/Documentos/git/bots/loyalty/events/20261018_gitin2250-webservice-high-cpu}
API=${API:-http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php}
: "${ZABBIX_API_KEY:?ZABBIX_API_KEY not set}"
APPLY=${APPLY:-0}
OUT=$EV/data/webs-healthcheck-run-$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"

MON_HOST=sfcg-monitoreo; MON_ID=10610
# label:host (the load balancer name used by httptest 6)
TARGETS=(LB:webservice.clubgrido.com.ar)
STEP=Healthcheck
FAILS=3; LAST=5   # problem when >= FAILS of the last LAST checks are not HTTP 200 (checks run every 1m)
TAGS_FOR() { jq -nc --arg f "WebService healthcheck ($1)" '[{tag:"scope",value:"availability"},{tag:"scope",value:"GIT-SML-OPE"},{tag:"service_group",value:"LOYALTY"},{tag:"action",value:"GCHAT"},{tag:"SVC_FRIENDLYNAME",value:$f}]'; }

rpc() {
  local r
  r=$(jq -nc --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,id:1,auth:$a}' \
      | curl -s -X POST "$API" -H 'Content-Type: application/json' -d @-)
  if [ "$(jq 'has("error")' <<<"$r")" = true ]; then echo "ERROR $1: $(jq -c .error <<<"$r")" >&2; return 1; fi
  jq -c .result <<<"$r"
}
die() { echo "GUARD FAILED: $*" >&2; exit 1; }
scen_name() { echo "[PROD] WebService $1 healthcheck"; }
test_params() { # label ip
  jq -nc --arg n "$(scen_name "$1")" --arg u "http://$2:8080/healthcheck.ashx" --arg s "$STEP" --arg h "$MON_ID" \
    '{name:$n,hostid:$h,delay:"1m",retries:"1",agent:"Zabbix",verify_peer:"0",verify_host:"0",steps:[{name:$s,no:"1",url:$u,timeout:"15s",status_codes:"200",follow_redirects:"0",retrieve_mode:"0",required:""}]}'
}
trig_params() { # label
  local key; key="web.test.rspcode[\"$(scen_name "$1")\",$STEP]"
  jq -nc --arg l "$1" --arg k "$key" --argjson f "$FAILS" --argjson n "$LAST" --argjson tags "$(TAGS_FOR "$1")" --arg m "$MON_HOST" \
    '{description:"WebService \($l): healthcheck.ashx HTTP code not 200 (\($f) of last \($n) checks)",
      expression:"count(/\($m)/\($k),#\($n),\"ne\",200)>=\($f)",
      recovery_mode:1, recovery_expression:"count(/\($m)/\($k),#\($n),\"ne\",200)=0",
      priority:4, tags:$tags, manual_close:0}'
}

echo "== run dir: $OUT =="
# --- guards (read only) ---
hs=$(rpc host.get "$(jq -nc --arg h "$MON_HOST" '{filter:{host:[$h]},output:["hostid","host","status"]}')")
[ "$(jq -r '.[0].hostid' <<<"$hs")" = "$MON_ID" ] || die "$MON_HOST is not hostid $MON_ID"
[ "$(jq -r '.[0].status' <<<"$hs")" = 0 ] || die "$MON_HOST not monitored"
for t in "${TARGETS[@]}"; do
  l=${t%%:*}
  n=$(rpc httptest.get "$(jq -nc --arg n "$(scen_name "$l")" '{filter:{name:[$n]},output:["httptestid"]}')" | jq length)
  [ "$n" = 0 ] || die "scenario '$(scen_name "$l")' already exists"
done
echo "guards passed" | tee "$OUT/guards.txt"
rpc httptest.get '{"httptestids":["6"],"output":"extend","selectSteps":"extend"}' > "$OUT/before-httptest6.json"

if [ "$APPLY" != 1 ]; then
  { echo "== plan (APPLY!=1, nothing created) =="
    for t in "${TARGETS[@]}"; do l=${t%%:*}; ip=${t##*:}; echo "-- $l"; test_params "$l" "$ip" | jq -c .; trig_params "$l" | jq -c '{description,expression,recovery_expression,priority}'; done; } | tee "$OUT/plan.txt"
  echo "dry run done; re-run with APPLY=1 to create"; exit 0
fi

# --- apply ---
: > "$OUT/created.tsv"
for t in "${TARGETS[@]}"; do
  l=${t%%:*}; ip=${t##*:}
  ht=$(rpc httptest.create "$(test_params "$l" "$ip")" | jq -r '.httptestids[0]')
  tr=$(rpc trigger.create "$(trig_params "$l")" | jq -r '.triggerids[0]')
  printf '%s\t%s\t%s\n' "$l" "$ht" "$tr" | tee -a "$OUT/created.tsv"
done
ids=$(awk -F'\t' '{print "\""$3"\""}' "$OUT/created.tsv" | paste -sd, -)
rpc trigger.get "{\"triggerids\":[$ids],\"output\":[\"triggerid\",\"description\",\"priority\",\"status\"],\"selectFunctions\":\"extend\",\"selectTags\":[\"tag\",\"value\"],\"selectHosts\":[\"host\"]}" > "$OUT/after-triggers.json"
hts=$(awk -F'\t' '{print "\""$2"\""}' "$OUT/created.tsv" | paste -sd, -)
rpc httptest.get "{\"httptestids\":[$hts],\"output\":\"extend\",\"selectSteps\":\"extend\"}" > "$OUT/after-httptests.json"
echo "done: $OUT (rollback: zabbix-webs-healthcheck-rollback.sh $OUT)"

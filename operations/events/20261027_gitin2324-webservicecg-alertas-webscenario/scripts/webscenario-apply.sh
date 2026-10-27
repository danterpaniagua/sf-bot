#!/usr/bin/env bash
# GITIN-2324: web scenarios + triggers for WebServiceCG (PROD, Test02, PreProd) on host sfcg-monitoreo (10610).
# Mirrors the existing scenarios (delay 1m, retries 1, step timeout 15s, status_codes 200, verify_peer/host off as in the other 16).
# Default is DRY RUN (prints payloads, only does read calls). Writes only with APPLY=1.
# Usage: API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php ZABBIX_API_KEY=... [APPLY=1] webscenario-apply.sh <output file>
set -euo pipefail
API=${API:?set API to the api_jsonrpc.php URL}
: "${ZABBIX_API_KEY:?ZABBIX_API_KEY not set}"
OUTF=${1:?usage: $0 <output file>}
HOSTID=10610
HOST=sfcg-monitoreo
APPLY=${APPLY:-0}
call(){ curl -s -X POST "$API" -H 'Content-Type: application/json' -d "$1"; }

# name|url|trigger name|priority (1=Information, 4=High)|env tag
SPECS=(
 '[PROD] WebServiceCG|https://bot-security.smartfran.com/swagger/ui/index|WebServiceCG PROD: swagger no responde 200|4|PROD'
 'WebServiceCG Test02|https://azsl-webservicecg-test02.smartfran.com:805/swagger/ui/index|WebServiceCG Test02: swagger no responde 200|1|DEV'
 'WebServiceCG PreProd|https://azsl-webservicecg-preprod.smartfran.com:8185/swagger/ui/index|WebServiceCG PreProd: swagger no responde 200|1|DEV'
)

{
echo "== ahora: $(date '+%F %T %z') APPLY=$APPLY =="
for spec in "${SPECS[@]}"; do
  IFS='|' read -r NAME URL TNAME PRIO ENVTAG <<<"$spec"
  echo "== $NAME =="
  existing=$(call '{"jsonrpc":"2.0","method":"httptest.get","id":1,"auth":"'"$ZABBIX_API_KEY"'","params":{"output":["httptestid"],"hostids":"'"$HOSTID"'","filter":{"name":"'"$NAME"'"}}}' | jq '.result|length')
  texist=$(call '{"jsonrpc":"2.0","method":"trigger.get","id":6,"auth":"'"$ZABBIX_API_KEY"'","params":{"output":["triggerid"],"hostids":"'"$HOSTID"'","filter":{"description":"'"$TNAME"'"}}}' | jq '.result|length')
  echo "existing: scenario=$existing trigger=$texist (each one that exists is not created again)"
  SC=$(jq -nc --arg n "$NAME" --arg u "$URL" --arg h "$HOSTID" --arg a "$ZABBIX_API_KEY" \
    '{jsonrpc:"2.0",method:"httptest.create",id:2,auth:$a,params:{name:$n,hostid:$h,delay:"1m",retries:"1",agent:"Zabbix",verify_peer:"0",verify_host:"0",steps:[{name:"Swagger",no:"1",url:$u,timeout:"15s",status_codes:"200",follow_redirects:"1",required:""}]}}')
  EXPR=$(printf 'min(/%s/web.test.fail["%s"],#2)<>0' "$HOST" "$NAME")
  TR=$(jq -nc --arg d "$TNAME" --arg e "$EXPR" --arg p "$PRIO" --arg t "$ENVTAG" --arg a "$ZABBIX_API_KEY" \
    '{jsonrpc:"2.0",method:"trigger.create",id:3,auth:$a,params:[{description:$d,expression:$e,priority:$p,manual_close:"1",tags:[{tag:"env",value:$t},{tag:"service_group",value:"LOYALTY"},{tag:"SVC_FRIENDLYNAME",value:$d}]}]}')
  echo "scenario: $(echo "$SC" | jq -c 'del(.auth)')"
  echo "trigger : $(echo "$TR" | jq -c 'del(.auth)')"
  if [ "$APPLY" = "1" ]; then
    [ "$existing" = "0" ] && echo "create scenario -> $(call "$SC")"
    [ "$texist" = "0" ] && echo "create trigger  -> $(call "$TR")"
    true
  fi
done
echo "== verify (read) =="
call '{"jsonrpc":"2.0","method":"httptest.get","id":4,"auth":"'"$ZABBIX_API_KEY"'","params":{"output":["httptestid","name","delay","status"],"hostids":"'"$HOSTID"'","search":{"name":"WebServiceCG"},"selectSteps":["name","url","status_codes"]}}' | jq -c '.result[]?'
call '{"jsonrpc":"2.0","method":"trigger.get","id":5,"auth":"'"$ZABBIX_API_KEY"'","params":{"output":["triggerid","description","priority","status","value"],"hostids":"'"$HOSTID"'","search":{"description":"WebServiceCG"},"selectTags":"extend","expandExpression":false}}' | jq -c '.result[]?'
} > "$OUTF" 2>&1
echo "wrote $OUTF"

#!/usr/bin/env bash
# GITIN-2324: create the three WebServiceCG triggers on host sfcg-monitoreo (10610). WRITES to Zabbix.
# Guards (abort with no change if any fails): the step's rspcode item and the scenario's fail item exist on host 10610 and the trigger name is not taken.
# Re-run safe: a trigger that already exists is skipped. Created ids go to <output file> (one JSON per line) for the rollback script.
# Usage: API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php ZABBIX_API_KEY=... triggers-create.sh <output file>
set -euo pipefail
API=${API:?set API}
: "${ZABBIX_API_KEY:?ZABBIX_API_KEY not set}"
OUTF=${1:?usage: $0 <output file>}
HOSTID=10610
HOST=sfcg-monitoreo
call(){ curl -s -X POST "$API" -H 'Content-Type: application/json' -d "$1"; }
chk(){ jq -e 'has("error")|not' >/dev/null <<<"$1" || { echo "API error: $1" >&2; exit 1; }; }

# description | rspcode item key (exact, as stored) | fail item key (exact) | scenario name for the expression | step (name or number) | env tag | severity
build_expr(){ # $1 rspcode key, $2 fail key (both exactly as stored: Zabbix matches the key text, so quoting must be the stored one), $3 failing step number or "any"
  if [ "$3" = any ]; then
    printf 'min(/%s/%s,#2)<>200 or min(/%s/%s,#2)<>0' "$HOST" "$1" "$HOST" "$2"
  else
    printf 'min(/%s/%s,#2)<>200 or min(/%s/%s,#2)=%s' "$HOST" "$1" "$HOST" "$2" "$3"
  fi
}
build_payload(){ # $1 description $2 expression $3 priority $4 env
  jq -nc --arg d "$1" --arg e "$2" --arg p "$3" --arg t "$4" --arg a "$ZABBIX_API_KEY" \
   '{jsonrpc:"2.0",method:"trigger.create",id:3,auth:$a,params:[{description:$d,expression:$e,priority:$p,opdata:"HTTP code: {ITEM.LASTVALUE1}",tags:[{tag:"env",value:$t},{tag:"service_group",value:"LOYALTY"},{tag:"SVC_FRIENDLYNAME",value:$d}]}]}'
}
SPECS=(
 'WebServiceCG PROD: swagger no responde 200|web.test.rspcode["[PROD] WebServiceCG",swagger]|web.test.fail["[PROD] WebServiceCG"]|[PROD] WebServiceCG|swagger|any|4|PROD'
 'WebServiceCG Test02: swagger no responde 200|web.test.rspcode[Loyalty Test02,WebServiceCG]|web.test.fail[Loyalty Test02]|Loyalty Test02|WebServiceCG|7|1|DEV'
 'WebServiceCG PreProd: swagger no responde 200|web.test.rspcode[Loyalty PreProd,WebServiceCG]|web.test.fail[Loyalty PreProd]|Loyalty PreProd|WebServiceCG|9|1|DEV'
)

echo "== ahora: $(date '+%F %T %z') ==" > "$OUTF"
# guards first, for all three, before any write
for spec in "${SPECS[@]}"; do
  IFS='|' read -r DESC RKEY FKEY SCEN STEP FAILNO PRIO ENVTAG <<<"$spec"
  for k in "$RKEY" "$FKEY"; do
    r=$(call '{"jsonrpc":"2.0","method":"item.get","id":1,"auth":"'"$ZABBIX_API_KEY"'","params":{"webitems":true,"hostids":"'"$HOSTID"'","output":["itemid"],"filter":{"key_":'"$(jq -nc --arg k "$k" '$k')"'}}}')
    chk "$r"
    [ "$(jq '.result|length' <<<"$r")" = 1 ] || { echo "GUARD FAILED: item not found on host $HOSTID: $k" | tee -a "$OUTF" >&2; exit 1; }
  done
done
echo "guards ok (6 items found)" >> "$OUTF"

for spec in "${SPECS[@]}"; do
  IFS='|' read -r DESC RKEY FKEY SCEN STEP FAILNO PRIO ENVTAG <<<"$spec"
  r=$(call '{"jsonrpc":"2.0","method":"trigger.get","id":2,"auth":"'"$ZABBIX_API_KEY"'","params":{"output":["triggerid"],"hostids":"'"$HOSTID"'","filter":{"description":'"$(jq -nc --arg d "$DESC" '$d')"'}}}')
  chk "$r"
  if [ "$(jq '.result|length' <<<"$r")" != 0 ]; then echo "SKIP (exists): $DESC" >> "$OUTF"; continue; fi
  resp=$(call "$(build_payload "$DESC" "$(build_expr "$RKEY" "$FKEY" "$FAILNO")" "$PRIO" "$ENVTAG")")
  chk "$resp"
  echo "$resp" | jq -c --arg d "$DESC" '{description:$d,triggerids:.result.triggerids}' >> "$OUTF"
done
echo "== after (read, raw expressions with macros expanded; none used here) ==" >> "$OUTF"
call '{"jsonrpc":"2.0","method":"trigger.get","id":4,"auth":"'"$ZABBIX_API_KEY"'","params":{"output":["triggerid","description","expression","priority","status","value","state","opdata"],"hostids":"'"$HOSTID"'","search":{"description":"WebServiceCG"},"expandExpression":true,"selectTags":"extend"}}' | jq -c '.result[]' >> "$OUTF"
echo "wrote $OUTF"

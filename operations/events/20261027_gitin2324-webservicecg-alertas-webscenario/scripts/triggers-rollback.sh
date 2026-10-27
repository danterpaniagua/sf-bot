#!/usr/bin/env bash
# GITIN-2324: delete the triggers created by triggers-create.sh, reading their ids from its output file. WRITES to Zabbix.
# Only deletes ids whose current description starts with "WebServiceCG " (guard).
# Usage: API=... ZABBIX_API_KEY=... triggers-rollback.sh <create output file> <rollback output file>
set -euo pipefail
API=${API:?set API}
: "${ZABBIX_API_KEY:?ZABBIX_API_KEY not set}"
IN=${1:?create output file}; OUTF=${2:?rollback output file}
call(){ curl -s -X POST "$API" -H 'Content-Type: application/json' -d "$1"; }
ids=$(grep '^{"description"' "$IN" | jq -r '.triggerids[]')
[ -n "$ids" ] || { echo "no triggerids in $IN" >&2; exit 1; }
for id in $ids; do
  d=$(call '{"jsonrpc":"2.0","method":"trigger.get","id":1,"auth":"'"$ZABBIX_API_KEY"'","params":{"output":["description"],"triggerids":"'"$id"'"}}' | jq -r '.result[0].description // empty')
  case "$d" in "WebServiceCG "*) ;; *) echo "GUARD FAILED: $id is '$d'" >&2; exit 1;; esac
done
{ echo "== ahora: $(date '+%F %T %z') =="; call "$(jq -nc --argjson ids "$(printf '%s\n' $ids | jq -R . | jq -sc .)" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:"trigger.delete",id:2,auth:$a,params:$ids}')"; echo; } > "$OUTF"
echo "wrote $OUTF"

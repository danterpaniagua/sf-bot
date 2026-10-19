#!/usr/bin/env bash
# GITIN-2250 — rollback of zabbix-mem-commit-apply.sh: deletes the triggers (Warning, Average, High), the items and the global macros that run created.
# Usage: zabbix-mem-commit-rollback.sh <run dir>   (APPLY=1 to delete; otherwise prints what would be deleted)
set -euo pipefail
RUN=${1:?usage: $0 <run dir>}
API=${API:-http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php}
: "${ZABBIX_API_KEY:?ZABBIX_API_KEY not set}"
APPLY=${APPLY:-0}
[ -s "$RUN/created.tsv" ] || { echo "no created.tsv in $RUN" >&2; exit 1; }
rpc() {
  local r
  r=$(jq -nc --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,id:1,auth:$a}' \
      | curl -s -X POST "$API" -H 'Content-Type: application/json' -d @-)
  if [ "$(jq 'has("error")' <<<"$r")" = true ]; then echo "ERROR $1: $(jq -c .error <<<"$r")" >&2; return 1; fi
  jq -c .result <<<"$r"
}
col() { awk -F'\t' -v c="$1" '{print $c}' "$RUN/created.tsv" | jq -R . | jq -sc .; }
iids=$(col 2)
# guards: ids must still be ours
for c in 3 4 5; do
  ids=$(col $c)
  g=$(rpc trigger.get "{\"triggerids\":$ids,\"output\":[\"description\"]}" | jq '[.[]|select(.description|startswith("Memory committed above"))]|length')
  [ "$g" = "$(jq length <<<"$ids")" ] || { echo "GUARD FAILED: column $c: $g of $(jq length <<<"$ids") match" >&2; exit 1; }
  if [ "$APPLY" = 1 ]; then echo "delete triggers col $c: $(rpc trigger.delete "$ids")"; else echo "would delete triggers col $c: $ids"; fi
done
g=$(rpc item.get "{\"itemids\":$iids,\"output\":[\"key_\"]}" | jq '[.[]|select(.key_|test("Committed Bytes In Use"))]|length')
[ "$g" = "$(jq length <<<"$iids")" ] || { echo "GUARD FAILED: items: $g of $(jq length <<<"$iids") match" >&2; exit 1; }
if [ "$APPLY" = 1 ]; then echo "delete items: $(rpc item.delete "$iids")"; else echo "would delete items: $iids"; fi
if [ -s "$RUN/created-globalmacroids.json" ]; then
  m=$(jq -c '.globalmacroids' "$RUN/created-globalmacroids.json")
  if [ "$APPLY" = 1 ]; then echo "delete macros: $(rpc usermacro.deleteglobal "$m")"; else echo "would delete macros: $m"; fi
fi

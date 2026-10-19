#!/usr/bin/env bash
# GITIN-2250 — rollback of zabbix-cpu-tiers-apply.sh: deletes only the triggers and global macros that run created (ids read from the run dir).
# Usage: zabbix-cpu-tiers-rollback.sh <run dir>   (APPLY=1 to delete; without it, prints what would be deleted)
set -euo pipefail
RUN=${1:?usage: $0 <run dir>}
API=${API:-http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php}
: "${ZABBIX_API_KEY:?ZABBIX_API_KEY not set}"
APPLY=${APPLY:-0}
[ -s "$RUN/created-triggerids.tsv" ] || { echo "no created-triggerids.tsv in $RUN" >&2; exit 1; }

rpc() {
  local r
  r=$(jq -nc --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,id:1,auth:$a}' \
      | curl -s -X POST "$API" -H 'Content-Type: application/json' -d @-)
  if [ "$(jq 'has("error")' <<<"$r")" = true ]; then echo "ERROR $1: $(jq -c .error <<<"$r")" >&2; return 1; fi
  jq -c .result <<<"$r"
}

# Warning first (it depends on Average and High), then Average, then High
for col in 2 3 4; do
  ids=$(awk -F'\t' -v c=$col '{print $c}' "$RUN/created-triggerids.tsv" | jq -R . | jq -sc .)
  # guard: every id must still be one of our CPU tier triggers
  got=$(rpc trigger.get "{\"triggerids\":$ids,\"output\":[\"description\"]}" | jq '[.[]|select(.description|startswith("CPU utilization above"))]|length')
  [ "$got" = "$(jq length <<<"$ids")" ] || { echo "GUARD FAILED: column $col: found $got of $(jq length <<<"$ids") expected CPU tier triggers" >&2; exit 1; }
  if [ "$APPLY" = 1 ]; then echo "delete column $col: $(rpc trigger.delete "$ids")"; else echo "would delete column $col: $ids"; fi
done
if [ -s "$RUN/created-globalmacroids.json" ]; then
  m=$(jq -c '.globalmacroids' "$RUN/created-globalmacroids.json")
  if [ "$APPLY" = 1 ]; then echo "delete macros: $(rpc usermacro.deleteglobal "$m")"; else echo "would delete macros: $m"; fi
fi

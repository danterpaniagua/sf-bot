#!/usr/bin/env bash
# GITIN-2250 — rollback of zabbix-webs-healthcheck-apply.sh: deletes only the triggers and web scenarios that run created (ids from the run dir).
# Usage: zabbix-webs-healthcheck-rollback.sh <run dir>   (APPLY=1 to delete; otherwise prints what would be deleted)
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
tids=$(awk -F'\t' '{print $3}' "$RUN/created.tsv" | jq -R . | jq -sc .)
hids=$(awk -F'\t' '{print $2}' "$RUN/created.tsv" | jq -R . | jq -sc .)
# guards: ids must still be ours
g=$(rpc trigger.get "{\"triggerids\":$tids,\"output\":[\"description\"]}" | jq '[.[]|select(.description|test("^WebService (WEBS-0[0-9]|LB)"))]|length')
[ "$g" = "$(jq length <<<"$tids")" ] || { echo "GUARD FAILED: $g of $(jq length <<<"$tids") triggers match" >&2; exit 1; }
g=$(rpc httptest.get "{\"httptestids\":$hids,\"output\":[\"name\"]}" | jq '[.[]|select(.name|test("^\\[PROD\\] WebService (WEBS-0[0-9]|LB) healthcheck$"))]|length')
[ "$g" = "$(jq length <<<"$hids")" ] || { echo "GUARD FAILED: $g of $(jq length <<<"$hids") scenarios match" >&2; exit 1; }
if [ "$APPLY" = 1 ]; then
  echo "delete triggers: $(rpc trigger.delete "$tids")"
  echo "delete scenarios: $(rpc httptest.delete "$hids")"
else
  echo "would delete triggers $tids and scenarios $hids"
fi

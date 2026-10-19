#!/usr/bin/env bash
# Changes global macro {$MOBILE_PCOUNT_BURST:MOBI} (id 128) from 60 to ${NEW} (default 45). Affects triggers 26909 (MOBI-01) and 26910 (MOBI-02), which fire on last() of Total requests/s >= the macro.
# Recovery of those triggers stays max over 5m < {$MOBILE_PCOUNT_SPIKE_OK:MOBI} (40), so NEW must stay above 40 (guarded).
# Without APPLY=1: read-only guards + BEFORE snapshot + plan, then stops. Rollback: zabbix-burst-macro-rollback.sh <run dir>.
set -euo pipefail
EV=${EV:-/home/dpaniagua/Documentos/git/bots/loyalty/events/20261018_mobile-spike-1900}
API=${API:-http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php}
: "${ZABBIX_API_KEY:?ZABBIX_API_KEY not set}"
APPLY=${APPLY:-0}; NEW=${NEW:-45}
OUT=$EV/data/burst-macro-run-$(date +%Y%m%d-%H%M%S)
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
rpc usermacro.get '{"globalmacro":true,"search":{"macro":"MOBILE_PCOUNT"},"output":["globalmacroid","macro","value"]}' > "$OUT/before-macros.json"
[ "$(jq -r '.[]|select(.globalmacroid=="128")|.macro' "$OUT/before-macros.json")" = '{$MOBILE_PCOUNT_BURST:MOBI}' ] || die "global macro 128 is not {\$MOBILE_PCOUNT_BURST:MOBI}"
[ "$(jq -r '.[]|select(.globalmacroid=="128")|.value' "$OUT/before-macros.json")" = 60 ] || die "macro 128 is not 60 now"
OKV=$(jq -r '.[]|select(.macro=="{$MOBILE_PCOUNT_SPIKE_OK:MOBI}")|.value' "$OUT/before-macros.json")
[[ "$NEW" =~ ^[0-9]+$ && "$OKV" =~ ^[0-9]+$ ]] || die "NEW or SPIKE_OK not numeric"
[ "$NEW" -gt "$OKV" ] || die "NEW=$NEW must be above SPIKE_OK=$OKV (recovery level)"
[ "$(rpc usermacro.get '{"hostids":["10659","10660"],"search":{"macro":"MOBILE_PCOUNT_BURST"},"output":["macro"]}' | jq length)" = 0 ] || die "a host-level BURST override exists"
echo "guards passed: 60 -> $NEW (SPIKE_OK=$OKV)" | tee "$OUT/guards.txt"
PARAMS=$(jq -nc --arg v "$NEW" '{globalmacroid:"128",value:$v}'); echo "$PARAMS" > "$OUT/plan.json"
if [ "$APPLY" != 1 ]; then echo "== plan (APPLY!=1, nothing changed) =="; cat "$OUT/plan.json"; echo "dry run done; re-run with APPLY=1"; exit 0; fi
rpc usermacro.updateglobal "$PARAMS" | tee "$OUT/update-result.json"
rpc usermacro.get '{"globalmacro":true,"globalmacroids":["128"],"output":["globalmacroid","macro","value"]}' | tee "$OUT/after-macro.json"
echo "done: $OUT (rollback: zabbix-burst-macro-rollback.sh $OUT)"

#!/usr/bin/env bash
# Event: 20261008_mobile-spike-detection-effectiveness
# C3 — MODIFICA ZABBIX: reversa de scripts-burst-apply.sh. Borra SOLO los triggers y macros globales que
# registro data/burst-apply/created-ids.json, y solo si siguen siendo los esperados (guardas).
# Uso:  bash <ruta>/scripts-burst-rollback.sh > <ruta>/data/burst-apply/rollback-log.txt 2>&1
set -euo pipefail

: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
URL="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
EV="/home/dpaniagua/Documentos/git/bots/operations/events/20261008_mobile-spike-detection-effectiveness"
OUT="$EV/data/burst-apply"
IDS="$OUT/created-ids.json"
[ -e "$IDS" ] || { echo "ABORTA: no existe $IDS (nada que revertir)"; exit 1; }

zbx() {
  jq -n --arg auth "$ZABBIX_API_KEY" --arg m "$1" --argjson p "$2" \
    '{jsonrpc:"2.0",id:1,method:$m,params:$p,auth:$auth}' \
  | curl -sS -H 'Content-Type: application/json-rpc' --data-binary @- "$URL" \
  | jq 'if .error then ("API error: " + (.error|tostring)) | halt_error(1) else .result end'
}
fail() { echo "GUARDA: $*  -> no se borro nada"; exit 1; }

TIDS=$(jq -c '.triggerids' "$IDS"); MIDS=$(jq -c '.globalmacroids' "$IDS")
[ "$(jq length <<<"$TIDS")" = 2 ] && [ "$(jq length <<<"$MIDS")" = 2 ] || fail "created-ids.json no tiene 2 triggers y 2 macros"

echo "== guardas"
cur=$(zbx trigger.get "{\"triggerids\":$TIDS,\"output\":[\"triggerid\",\"description\"],\"selectHosts\":[\"host\"]}")
echo "$cur" > "$OUT/rollback-before-triggers.json"
[ "$(jq length <<<"$cur")" = 2 ] || fail "no encuentro los 2 triggers creados"
[ "$(jq '[.[] | select(.description | startswith("IIS Spike - Burst:"))] | length' <<<"$cur")" = 2 ] || fail "algun trigger no es 'IIS Spike - Burst:'"
[ "$(jq '[.[] | select(.hosts[0].host=="SFCG-MOBI-01" or .hosts[0].host=="SFCG-MOBI-02")] | length' <<<"$cur")" = 2 ] || fail "algun trigger no es de un host MOBI"
gm=$(zbx usermacro.get "{\"globalmacroids\":$MIDS,\"globalmacro\":true,\"output\":[\"globalmacroid\",\"macro\",\"value\"]}")
echo "$gm" > "$OUT/rollback-before-macros.json"
[ "$(jq '[.[] | select(.macro=="{$MOBILE_PCOUNT_BURST:MOBI}" or .macro=="{$MOBILE_PCOUNT_BURST_TIME}")] | length' <<<"$gm")" = 2 ] || fail "alguna macro no es una de las 2 esperadas"

echo "== borrado (triggers primero, luego macros)"
zbx trigger.delete "$TIDS" > "$OUT/rollback-deleted-triggers.json"
zbx usermacro.deleteglobal "$MIDS" > "$OUT/rollback-deleted-macros.json"

echo "== verificacion"
left_t=$(zbx trigger.get "{\"triggerids\":$TIDS,\"output\":[\"triggerid\"]}" | jq length)
left_m=$(zbx usermacro.get '{"globalmacro":true,"output":["macro"],"search":{"macro":"MOBILE_PCOUNT_BURST"}}' | jq length)
echo "triggers restantes: $left_t  macros BURST restantes: $left_m"
[ "$left_t" = 0 ] && [ "$left_m" = 0 ] && mv "$IDS" "$OUT/created-ids.rolled-back-$(date +%Y%m%d%H%M%S).json" && echo "OK: revertido"

#!/usr/bin/env bash
# Event: 20261008_mobile-spike-detection-effectiveness
# C4 — Solo lectura: configuracion de la accion 7 (Google Chat Loyalty to Operaciones) y su historial de envios.
#      Responde: que manda al recuperar, si repite (escalamiento), con que condiciones enruta los triggers
#      "IIS Spike - Burst" (26909/26910) y que se envio realmente desde el 2026-10-02.
# Salidas en data/action7/. Se eliminan las claves sendto, passwd, password y token si aparecieran.
# Uso (ZABBIX_API_KEY en el entorno):
#   mkdir -p <ruta>/data/action7 && bash <ruta>/scripts-action7.sh > <ruta>/data/action7/pull-log.txt 2>&1
set -euo pipefail

: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
URL="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/operations/events/20261008_mobile-spike-detection-effectiveness/data/action7"
FROM_DAY="${FROM_DAY:-2026-10-02}"
mkdir -p "$OUT"

zbx() { # zbx <metodo> <params-json>  -> imprime .result o aborta con el error de la API
  jq -n --arg auth "$ZABBIX_API_KEY" --arg m "$1" --argjson p "$2" \
    '{jsonrpc:"2.0",id:1,method:$m,params:$p,auth:$auth}' \
  | curl -sS -H 'Content-Type: application/json-rpc' --data-binary @- "$URL" \
  | jq 'if .error then ("API error: " + (.error|tostring)) | halt_error(1) else .result end'
}
scrub() { jq 'walk(if type=="object" then del(.sendto, .passwd, .password, .token) else . end)'; }

# 1) La accion con filtro, operaciones, operaciones de recuperacion y de actualizacion
zbx action.get '{"actionids":["7"],"output":"extend","selectFilter":"extend","selectOperations":"extend","selectRecoveryOperations":"extend","selectUpdateOperations":"extend"}' | scrub > "$OUT/action-7.json"
echo "accion: $(jq -r '.[0].name' "$OUT/action-7.json") status=$(jq -r '.[0].status' "$OUT/action-7.json") esc_period=$(jq -r '.[0].esc_period' "$OUT/action-7.json")"

# 2) Los triggers nuevos con sus tags (para comparar con las condiciones del filtro)
zbx trigger.get '{"triggerids":["26909","26910","26744"],"output":["triggerid","description","priority","status","value"],"selectHosts":["host"],"selectTags":["tag","value"]}' > "$OUT/burst-triggers-tags.json"

# 3) Envios de la accion 7 desde FROM_DAY (sin mensaje ni destinatario)
T0=$(date -d "$FROM_DAY 00:00:00 -0300" +%s)
zbx alert.get "{\"actionids\":[\"7\"],\"time_from\":$T0,\"output\":[\"alertid\",\"eventid\",\"clock\",\"status\",\"retries\",\"error\",\"esc_step\",\"alerttype\",\"mediatypeid\",\"p_eventid\"],\"sortfield\":\"clock\",\"sortorder\":\"ASC\"}" > "$OUT/alerts-action7.json"
echo "envios de la accion 7 desde $FROM_DAY: $(jq length "$OUT/alerts-action7.json")"
echo "listo"

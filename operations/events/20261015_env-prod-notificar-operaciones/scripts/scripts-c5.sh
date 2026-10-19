#!/usr/bin/env bash
# Event: 20261015_env-prod-notificar-operaciones
# C5 - Zabbix 6.0.32 (sf-monitoreo.smartfran.com:8080; token en $ZABBIX_API_KEY). SOLO LECTURA.
#      Alertas generadas para ope_notify (userid 16) por la accion 12 en los ultimos $1 minutos (por defecto 60): conteo por medio y estado (1 enviada, 2 fallida, 0 en cola)
#      y el texto del error recortado y con tokens/URLs enmascarados (el error de Telegram puede incluir la URL con el token del bot). No pide ni imprime sendto.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
MIN="${1:-60}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/operations/events/20261015_env-prod-notificar-operaciones/data"
TS=$(date -u +%Y%m%dT%H%M%SZ); RUN="$OUT/c5-run-$TS"; mkdir -p "$RUN"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
FROM=$(( $(date -u +%s) - MIN*60 ))
echo "run $TS | alertas de los ultimos $MIN min | accion 12, usuario 16"
call alert.get "$(jq -nc --argjson f "$FROM" '{output:["alertid","actionid","eventid","clock","mediatypeid","status","retries","error","subject"],userids:["16"],actionids:["12"],time_from:$f,sortfield:"clock",sortorder:"DESC",limit:500}')" \
 | jq '[.[]|.error |= (gsub("https?://[^ ]+";"<url>")|gsub("[0-9]{6,}:[A-Za-z0-9_-]{20,}";"<token>")|gsub("(token|key)=[^& ]+";"\\1=<x>")|.[0:80])]' > "$RUN/alerts.json"
echo "== total y conteo por medio / estado (medio 38 Chat, 16 Telegram | estado 0 cola, 1 enviada, 2 fallida)"
jq -r 'length|"total: \(.)"' "$RUN/alerts.json"
jq -r 'group_by([.mediatypeid,.status])|.[]|"  medio \(.[0].mediatypeid) estado \(.[0].status): \(length)"' "$RUN/alerts.json"
echo "== errores distintos (recortados y enmascarados)"
jq -r '[.[]|select(.error!="")|"medio \(.mediatypeid): \(.error)"]|group_by(.)|.[]|"  \(length)x \(.[0])"' "$RUN/alerts.json"
echo "== ultimas 8 (clock UTC | evento | medio | estado | asunto)"
jq -r '.[0:8][]|"  \(.clock|tonumber|strftime("%H:%M:%S")) | \(.eventid) | \(.mediatypeid) | \(.status) | \(.subject[0:70])"' "$RUN/alerts.json"
echo "guardado en $RUN"

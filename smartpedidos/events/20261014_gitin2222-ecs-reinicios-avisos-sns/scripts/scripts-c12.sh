#!/usr/bin/env bash
# Event: 20261014_gitin2222-ecs-reinicios-avisos-sns
# C12 - SOLO LECTURA contra la API de Zabbix (sf-monitoreo.smartfran.com:8080, 6.0.32; token en $ZABBIX_API_KEY).
#       Enrutamiento a Google Chat de Operaciones para el trigger "Running tasks below desired": lee las acciones de trigger con sus condiciones y destinatarios (solo ids; no se piden correos ni webhooks)
#       para elegir los tags que coincidan con la accion 7 ("Google Chat Loyalty to Operaciones") o ver que condicion habria que agregar. Estado vivo: docs/zabbix_observability.md es del 2026-10-02.
#       Convencion de action.status sin confirmar en la documentacion: aqui se imprime el valor crudo.
#       Salidas en data/c12/.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/data/c12"
mkdir -p "$OUT"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
call action.get '{"output":["actionid","name","status","eventsource","esc_period","pause_suppressed"],"filter":{"eventsource":"0"},"selectFilter":["evaltype","formula","conditions"],"selectOperations":["operationtype","opmessage","opmessage_grp","opmessage_usr"]}' > "$OUT/actions.json"
echo "== acciones de trigger (eventsource 0): $(jq length "$OUT/actions.json")   [status crudo: 0 y 1; ver la nota de convencion en docs/zabbix_observability.md]"
jq -r '.[] | "\n#\(.actionid) \(.name) | status=\(.status) | evaltype=\(.filter.evaltype) \(.filter.formula // "") | pausa_suprimidos=\(.pause_suppressed)"' "$OUT/actions.json"
echo; echo "== condiciones (tipo 25 = nombre de tag, 26 = valor de tag [value2 = nombre del tag]; operador 0 = igual, 1 = distinto, 2 = contiene, 3 = no contiene)"
jq -r '.[] | .actionid as $a | .filter.conditions[]? | [$a, ("formulaid=" + (.formulaid // "-")), ("tipo=" + .conditiontype), ("op=" + .operator), ("valor=" + (.value // "")), ("tag=" + (.value2 // ""))] | @tsv' "$OUT/actions.json"
echo; echo "== destinatarios (solo ids)"
jq -r '.[] | .actionid as $a | .operations[]? | [$a, ("opmsg_usuarios=" + ([.opmessage_usr[]?.userid]|join(","))), ("opmsg_grupos=" + ([.opmessage_grp[]?.usrgrpid]|join(","))), ("mediatype=" + (.opmessage.mediatypeid // "-"))] | @tsv' "$OUT/actions.json"
echo listo

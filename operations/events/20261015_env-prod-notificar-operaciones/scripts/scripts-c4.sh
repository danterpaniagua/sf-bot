#!/usr/bin/env bash
# Event: 20261015_env-prod-notificar-operaciones
# C4 - Zabbix 6.0.32 (sf-monitoreo.smartfran.com:8080; token en $ZABBIX_API_KEY). Accion nueva: todo problema con la etiqueta env=PROD notifica al usuario ope_notify (userid 16)
#      por TODOS sus medios (Chat tipo 38 y Telegram tipo 16). Mismo molde que la accion 7 (mensajes por defecto del tipo de medio, operacion + recuperacion + actualizacion,
#      pause_suppressed=1, esc_period 1h). No modifica las acciones existentes. Sin piso de severidad (el pedido es "todos"): los 122 triggers con env=PROD (info 1, warning 37, average 55, high 29).
#      Requiere C3 aplicado (ope_notify fuera del grupo 14, que tiene filtros de etiquetas). Telegram no enviara hasta que el tipo de medio 16 tenga su token real (hoy placeholder, C2).
#      Modos: dry (por defecto, SOLO LECTURA) | apply (CAMBIA ESTADO) | rollback <carpeta c4-run-...> (CAMBIA ESTADO: borra la accion creada)
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
MODE="${1:-dry}"; SNAP="${2:-}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/operations/events/20261015_env-prod-notificar-operaciones/data"
NAME="Notify OPERACIONES env PROD (Chat + Telegram)"
TS=$(date -u +%Y%m%dT%H%M%SZ); RUN="$OUT/c4-run-$TS"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
if [ "$MODE" = "rollback" ]; then
  [ -f "$SNAP/after.json" ] || { echo "uso: $0 rollback <carpeta c4-run-...>"; exit 1; }
  ID=$(jq -r '.actionid' "$SNAP/after.json"); echo "borrar accion $ID:"; call action.delete "[\"$ID\"]" | jq -c .; echo "rollback hecho"; exit 0
fi
mkdir -p "$RUN"; echo "modo=$MODE | $TS | carpeta $RUN"
call user.get '{"userids":["16"],"output":["username"],"selectUsrgrps":["usrgrpid","name"]}' > "$RUN/before-user.json"
call action.get "$(jq -nc --arg n "$NAME" '{filter:{name:[$n]},output:["actionid","name"]}')" > "$RUN/before-action-exists.json"
jq -e '.[0].username=="ope_notify" and ([.[0].usrgrps[].usrgrpid]|index("14")|not)' "$RUN/before-user.json" >/dev/null || { echo "GUARDA: ope_notify sigue en el grupo 14 (o no existe): aplicar antes C3"; exit 1; }
jq -e 'length==0' "$RUN/before-action-exists.json" >/dev/null || { echo "GUARDA: ya existe una accion con ese nombre"; exit 1; }
MSG='{"operationtype":"0","opmessage":{"default_msg":"1","mediatypeid":"0"},"opmessage_usr":[{"userid":"16"}]}'
PAYLOAD=$(jq -nc --arg n "$NAME" --argjson m "$MSG" '{name:$n,eventsource:"0",status:"0",esc_period:"1h",pause_suppressed:"1",
  filter:{evaltype:"0",conditions:[{conditiontype:"26",operator:"0",value:"PROD",value2:"env"}]},
  operations:[($m+{esc_period:"0",esc_step_from:"1",esc_step_to:"1",evaltype:"0"})],
  recovery_operations:[$m],update_operations:[$m]}')
echo "$PAYLOAD" | jq . > "$RUN/payload.json"
echo "plan: accion \"$NAME\": condicion etiqueta env = PROD; operacion, recuperacion y actualizacion -> usuario 16 (ope_notify), medio 0 = todos (Chat y Telegram), mensajes por defecto"
[ "$MODE" = "apply" ] || { echo "DRY: no se creo nada. Para aplicar: $0 apply"; exit 0; }
ID=$(call action.create "$PAYLOAD" | jq -r '.actionids[0]'); echo "accion creada: $ID"; jq -n --arg a "$ID" '{actionid:$a}' > "$RUN/after.json"
call action.get "$(jq -nc --arg a "$ID" '{actionids:[$a],output:["actionid","name","status","pause_suppressed"],selectFilter:"extend",selectOperations:"extend",selectRecoveryOperations:"extend",selectUpdateOperations:"extend"}')" > "$RUN/after-action.json"
echo "== despues"; jq -c '.[]|{actionid,name,status,cond:[.filter.conditions[]|"\(.conditiontype):\(.operator):\(.value)/\(.value2)"],ops:[.operations[]|{usr:[.opmessage_usr[]?.userid],media:.opmessage.mediatypeid}],rec:[.recovery_operations[]|{usr:[.opmessage_usr[]?.userid]}],upd:[.update_operations[]|{usr:[.opmessage_usr[]?.userid]}]}' "$RUN/after-action.json"
echo "aplicado. Rollback: $0 rollback $RUN"

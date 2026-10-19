#!/usr/bin/env bash
# Event: 20261014_gitin2222-ecs-reinicios-avisos-sns
# C16 - Zabbix 6.0.32 (sf-monitoreo.smartfran.com:8080), token en $ZABBIX_API_KEY dentro del cuerpo JSON (nunca literal).
#       Correccion del usuario (2026-10-14): el enrutamiento va con scope OPE y SP, sin SML. Reemplaza el enrutamiento de C13 (que usaba scope GIT-SML-OPE + service_group SMARTPEDIDOS en la accion 7).
#       Cambios:
#         1) accion NUEVA "Google Chat SmartPedidos to Operaciones", clonada de la accion 7 leida en C15 (data/c15-run-log-20261015T014728Z.txt): mismo destinatario (usuario 9), mismo tipo de medio (38),
#            operaciones de envio, recuperacion y actualizacion con el texto por defecto del tipo de medio, esc_period 1h, pause_suppressed 1.
#            Condiciones (formula A and B and C): scope = OPE, scope = SP, action ~ GCHAT.
#         2) prototipo de trigger 26911: tags finales = scope=availability, service={#AWS.ECS.SERVICE.NAME}, scope=OPE, scope=SP, action=GCHAT
#            (triggerprototype.update reemplaza TODOS los tags; acepta como estado de partida el original de C10 o el de C13)
#       NO toca la accion 7: para devolverla a 'A and B and (C or D)' usar el rollback de C13 (scripts-c13.sh rollback data/c13-run-20261015T014357Z).
#       Modos:  payload (SOLO LECTURA, sin API) | dry (SOLO LECTURA, por defecto) | apply (CAMBIA ESTADO) | rollback <carpeta c16-run-...> (CAMBIA ESTADO: borra la accion nueva y restaura los tags)
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
MODE="${1:-dry}"; SNAP="${2:-}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/data"
TS=$(date -u +%Y%m%dT%H%M%SZ); RUN="$OUT/c16-run-$TS"
PROTO_ID=26911; ACTION_NAME='Google Chat SmartPedidos to Operaciones'
PROTO_NAME='AWS ECS Cluster Service: [{#AWS.ECS.SERVICE.NAME}]: Running tasks below desired'

# recovery_operations y update_operations NO aceptan "evaltype" (la API respondio: unexpected parameter "evaltype", intentos 01:50 y 01:51 UTC); "operations" si
OPS='{"operationtype":"0","opmessage":{"default_msg":"1","mediatypeid":"38"},"opmessage_usr":[{"userid":"9"}]}'
ACTION_PAYLOAD=$(jq -nc --arg n "$ACTION_NAME" --argjson op "$OPS" '{
  name:$n, eventsource:"0", status:"0", esc_period:"1h", pause_suppressed:"1", notify_if_canceled:"1",
  filter:{evaltype:"3", formula:"A and B and C", conditions:[
    {formulaid:"A",conditiontype:"26",operator:"0",value:"OPE",value2:"scope"},
    {formulaid:"B",conditiontype:"26",operator:"0",value:"SP",value2:"scope"},
    {formulaid:"C",conditiontype:"26",operator:"2",value:"GCHAT",value2:"action"}]},
  operations:[($op + {evaltype:"0",esc_period:"0",esc_step_from:"1",esc_step_to:"1"})],
  recovery_operations:[$op],
  update_operations:[$op]}')
TAGS_S0='[{"tag":"scope","value":"availability"},{"tag":"service","value":"{#AWS.ECS.SERVICE.NAME}"}]'
TAGS_S1='[{"tag":"scope","value":"availability"},{"tag":"service","value":"{#AWS.ECS.SERVICE.NAME}"},{"tag":"scope","value":"GIT-SML-OPE"},{"tag":"action","value":"GCHAT"},{"tag":"service_group","value":"SMARTPEDIDOS"}]'
PROTO_PAYLOAD=$(jq -nc --arg t "$PROTO_ID" --argjson o "$TAGS_S0" '{triggerid:$t, tags:($o + [{tag:"scope",value:"OPE"},{tag:"scope",value:"SP"},{tag:"action",value:"GCHAT"}])}')
if [ "$MODE" = "payload" ]; then echo "== action.create"; echo "$ACTION_PAYLOAD" | jq .; echo "== triggerprototype.update"; echo "$PROTO_PAYLOAD" | jq .; exit 0; fi

: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
get_proto() { call triggerprototype.get "$(jq -n --arg t "$PROTO_ID" '{triggerids:[$t],output:["triggerid","description","status"],selectTags:["tag","value"]}')"; }
get_new_action() { call action.get "$(jq -n --arg n "$ACTION_NAME" '{filter:{name:[$n]},output:["actionid","name","status"],selectFilter:["evaltype","formula","conditions"],selectOperations:"extend"}')"; }

if [ "$MODE" = "rollback" ]; then
  [ -f "$SNAP/before-prototype.json" ] && [ -f "$SNAP/created-ids.json" ] || { echo "uso: $0 rollback <carpeta c16-run-...> (faltan before-prototype.json / created-ids.json)"; exit 1; }
  AID=$(jq -r '.actionid' "$SNAP/created-ids.json")
  if [ -n "$AID" ] && [ "$AID" != "null" ]; then
    call action.get "$(jq -n --arg a "$AID" '{actionids:[$a],output:["name"]}')" | jq -e --arg n "$ACTION_NAME" '.[0].name==$n' >/dev/null || { echo "GUARDA: la accion $AID no se llama '$ACTION_NAME'"; exit 1; }
    call action.delete "[\"$AID\"]"; echo "accion $AID borrada"
  fi
  call triggerprototype.update "$(jq -c --arg t "$PROTO_ID" '{triggerid:$t, tags:.[0].tags}' "$SNAP/before-prototype.json")"
  echo "rollback aplicado desde $SNAP"; get_proto | jq -c '.[0].tags'; exit 0
fi

echo "version de la API: $(jq -n '{jsonrpc:"2.0",method:"apiinfo.version",params:[],id:1}' | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq -r .result) | modo=$MODE | $TS"
mkdir -p "$RUN"
get_proto > "$RUN/before-prototype.json"; get_new_action > "$RUN/before-new-action.json"
# --- guardas
jq -e --arg n "$PROTO_NAME" '.[0].description==$n' "$RUN/before-prototype.json" >/dev/null || { echo "GUARDA: el prototipo $PROTO_ID no tiene el nombre esperado"; exit 1; }
CUR=$(jq -c '.[0].tags|sort_by(.tag,.value)' "$RUN/before-prototype.json")
if [ "$CUR" = "$(echo "$TAGS_S0" | jq -c 'sort_by(.tag,.value)')" ]; then echo "tags de partida: originales de C10"; elif [ "$CUR" = "$(echo "$TAGS_S1" | jq -c 'sort_by(.tag,.value)')" ]; then echo "tags de partida: los de C13 (se reemplazan)"; else echo "GUARDA: los tags actuales no son ni los de C10 ni los de C13: $CUR"; exit 1; fi
[ "$(jq 'length' "$RUN/before-new-action.json")" = "0" ] || { echo "GUARDA: ya existe una accion llamada '$ACTION_NAME'"; exit 1; }
call user.get '{"userids":["9"],"output":["userid"]}' | jq -e 'length==1' >/dev/null || { echo "GUARDA: el usuario 9 no existe"; exit 1; }
call mediatype.get '{"mediatypeids":["38"],"output":["mediatypeid","status"]}' | jq -e 'length==1 and .[0].status=="0"' >/dev/null || { echo "GUARDA: el tipo de medio 38 no existe o esta deshabilitado"; exit 1; }
echo "guardas OK."; echo "== action.create"; echo "$ACTION_PAYLOAD" | jq -c .; echo "== triggerprototype.update"; echo "$PROTO_PAYLOAD" | jq -c .
echo "snapshot en $RUN"
if [ "$MODE" != "apply" ]; then echo "DRY: no se cambio nada. Para aplicar: $0 apply"; exit 0; fi

# --- apply: primero la accion (para que el destino exista), despues los tags del prototipo
R=$(call action.create "$ACTION_PAYLOAD"); echo "$R" > "$RUN/create-action.json"; AID=$(echo "$R" | jq -r '.actionids[0]')
jq -n --arg a "$AID" '{actionid:$a}' > "$RUN/created-ids.json"
call triggerprototype.update "$PROTO_PAYLOAD" > "$RUN/update-prototype.json"
get_new_action > "$RUN/after-new-action.json"; get_proto > "$RUN/after-prototype.json"
echo "== despues"; jq -c '.[0]|{actionid,name,status,formula:.filter.formula,condiciones:[.filter.conditions[]|"\(.formulaid): \(.value2)=\(.value)"]}' "$RUN/after-new-action.json"; jq -c '.[0].tags' "$RUN/after-prototype.json"
echo "aplicado. Los triggers descubiertos toman los tags en el proximo descubrimiento. Rollback: $0 rollback $RUN"

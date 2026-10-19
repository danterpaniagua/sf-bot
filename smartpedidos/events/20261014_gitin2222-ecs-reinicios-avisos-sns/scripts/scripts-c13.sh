#!/usr/bin/env bash
# Event: 20261014_gitin2222-ecs-reinicios-avisos-sns
# C13 - Zabbix 6.0.32 (sf-monitoreo.smartfran.com:8080), token en $ZABBIX_API_KEY dentro del cuerpo JSON (nunca literal).
#       Enrutar el trigger "Running tasks below desired" al Google Chat de Operaciones (accion 7, destinatario user 9, media type 38). Estado vivo leido en C12 (data/c12-run-log-20261015T014135Z.txt):
#       accion 7 (status 0), formula "A and B and (C or D)": A scope=GIT-SML-OPE, B action~GCHAT, C service_group=LOYALTY, D service_group=CLOUD.
#       Cambios:
#         1) accion 7: agrega la condicion E "service_group = $SERVICE_GROUP" y la formula pasa a "A and B and (C or D or E)"  (cambia una accion COMPARTIDA; solo los triggers con ese tag nuevo se ven afectados)
#         2) prototipo de trigger 26911 (C10): tags = los 2 existentes + scope=GIT-SML-OPE + action=GCHAT + service_group=$SERVICE_GROUP   (triggerprototype.update reemplaza TODOS los tags: se reenvian los 2 existentes)
#       Modos:  payload (SOLO LECTURA, sin API) | dry (SOLO LECTURA, por defecto: guardas + snapshot) | apply (CAMBIA ESTADO) | rollback <carpeta c13-run-...> (CAMBIA ESTADO, restaura desde el snapshot)
#       SERVICE_GROUP se puede cambiar en el entorno antes de correr:  SERVICE_GROUP=OTRO bash scripts-c13.sh dry   (por defecto SMARTPEDIDOS, propuesto, no confirmado por el usuario)
#       Aviso: mientras el bug de los reinicios siga vivo, Running < Desired aparece seguido (C11: 4.7 y 4.8 de 5) y el chat recibira un mensaje por cada problema nuevo.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
MODE="${1:-dry}"; SNAP="${2:-}"
SERVICE_GROUP="${SERVICE_GROUP:-SMARTPEDIDOS}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/data"
TS=$(date -u +%Y%m%dT%H%M%SZ); RUN="$OUT/c13-run-$TS"
ACTION_ID=7; PROTO_ID=26911
PROTO_NAME='AWS ECS Cluster Service: [{#AWS.ECS.SERVICE.NAME}]: Running tasks below desired'

# --- cargas esperadas (locales)
EXPECTED_CONDS='[{"formulaid":"A","conditiontype":"26","operator":"0","value":"GIT-SML-OPE","value2":"scope"},{"formulaid":"B","conditiontype":"26","operator":"2","value":"GCHAT","value2":"action"},{"formulaid":"C","conditiontype":"26","operator":"0","value":"LOYALTY","value2":"service_group"},{"formulaid":"D","conditiontype":"26","operator":"0","value":"CLOUD","value2":"service_group"}]'
NEW_COND=$(jq -nc --arg g "$SERVICE_GROUP" '{formulaid:"E",conditiontype:"26",operator:"0",value:$g,value2:"service_group"}')
ACTION_PAYLOAD=$(jq -nc --arg a "$ACTION_ID" --argjson c "$EXPECTED_CONDS" --argjson e "$NEW_COND" '{actionid:$a, filter:{evaltype:"3", formula:"A and B and (C or D or E)", conditions:($c + [$e])}}')
OLD_TAGS='[{"tag":"scope","value":"availability"},{"tag":"service","value":"{#AWS.ECS.SERVICE.NAME}"}]'
PROTO_PAYLOAD=$(jq -nc --arg t "$PROTO_ID" --argjson o "$OLD_TAGS" --arg g "$SERVICE_GROUP" '{triggerid:$t, tags:($o + [{tag:"scope",value:"GIT-SML-OPE"},{tag:"action",value:"GCHAT"},{tag:"service_group",value:$g}])}')
if [ "$MODE" = "payload" ]; then echo "== action.update"; echo "$ACTION_PAYLOAD" | jq .; echo "== triggerprototype.update"; echo "$PROTO_PAYLOAD" | jq .; exit 0; fi

: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
get_action() { call action.get "$(jq -n --arg a "$ACTION_ID" '{actionids:[$a],output:["actionid","name","status"],selectFilter:["evaltype","formula","conditions"]}')"; }
get_proto()  { call triggerprototype.get "$(jq -n --arg t "$PROTO_ID" '{triggerids:[$t],output:["triggerid","description","status"],selectTags:["tag","value"]}')"; }
norm_conds() { jq -c '[.[0].filter.conditions[] | {formulaid,conditiontype,operator,value,value2}] | sort_by(.formulaid)'; }

if [ "$MODE" = "rollback" ]; then
  [ -f "$SNAP/before-action.json" ] && [ -f "$SNAP/before-prototype.json" ] || { echo "uso: $0 rollback <carpeta c13-run-...>"; exit 1; }
  BA=$(jq -c --arg a "$ACTION_ID" '{actionid:$a, filter:{evaltype:.[0].filter.evaltype, formula:.[0].filter.formula, conditions:[.[0].filter.conditions[]|{formulaid,conditiontype,operator,value,value2}]}}' "$SNAP/before-action.json")
  BP=$(jq -c --arg t "$PROTO_ID" '{triggerid:$t, tags:.[0].tags}' "$SNAP/before-prototype.json")
  call action.update "$BA"; call triggerprototype.update "$BP"
  echo "rollback aplicado desde $SNAP"; get_action | jq -c '.[0]|{actionid,status,formula:.filter.formula}'; get_proto | jq -c '.[0].tags'; exit 0
fi

echo "version de la API: $(jq -n '{jsonrpc:"2.0",method:"apiinfo.version",params:[],id:1}' | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq -r .result) | modo=$MODE | SERVICE_GROUP=$SERVICE_GROUP | $TS"
mkdir -p "$RUN"
get_action > "$RUN/before-action.json"; get_proto > "$RUN/before-prototype.json"
# --- guardas
jq -e '.[0].status=="0" and .[0].filter.evaltype=="3" and .[0].filter.formula=="A and B and (C or D)"' "$RUN/before-action.json" >/dev/null || { echo "GUARDA: la accion $ACTION_ID no esta habilitada o su formula no es 'A and B and (C or D)'"; exit 1; }
[ "$(norm_conds < "$RUN/before-action.json")" = "$(echo "$EXPECTED_CONDS" | jq -c 'sort_by(.formulaid)')" ] || { echo "GUARDA: las condiciones de la accion $ACTION_ID no son las leidas en C12"; norm_conds < "$RUN/before-action.json"; exit 1; }
jq -e --arg n "$PROTO_NAME" '.[0].description==$n' "$RUN/before-prototype.json" >/dev/null || { echo "GUARDA: el prototipo $PROTO_ID no tiene el nombre esperado"; exit 1; }
[ "$(jq -c '.[0].tags|sort_by(.tag)' "$RUN/before-prototype.json")" = "$(echo "$OLD_TAGS" | jq -c 'sort_by(.tag)')" ] || { echo "GUARDA: los tags actuales del prototipo no son los 2 esperados"; jq -c '.[0].tags' "$RUN/before-prototype.json"; exit 1; }
echo "guardas OK. Accion $ACTION_ID '$(jq -r '.[0].name' "$RUN/before-action.json")'; prototipo $PROTO_ID"
echo "== action.update"; echo "$ACTION_PAYLOAD" | jq -c .; echo "== triggerprototype.update"; echo "$PROTO_PAYLOAD" | jq -c .
echo "snapshot en $RUN"
if [ "$MODE" != "apply" ]; then echo "DRY: no se cambio nada. Para aplicar: SERVICE_GROUP=$SERVICE_GROUP $0 apply"; exit 0; fi

# --- apply: primero la accion (para que el tag nuevo ya tenga destino), despues los tags del prototipo
call action.update "$ACTION_PAYLOAD" > "$RUN/update-action.json"
call triggerprototype.update "$PROTO_PAYLOAD" > "$RUN/update-prototype.json"
get_action > "$RUN/after-action.json"; get_proto > "$RUN/after-prototype.json"
echo "== despues"; jq -c '.[0]|{actionid,status,evaltype:.filter.evaltype,formula:.filter.formula}' "$RUN/after-action.json"; norm_conds < "$RUN/after-action.json"; jq -c '.[0].tags' "$RUN/after-prototype.json"
echo "aplicado. Los triggers descubiertos toman los tags en el proximo descubrimiento. Rollback: $0 rollback $RUN"

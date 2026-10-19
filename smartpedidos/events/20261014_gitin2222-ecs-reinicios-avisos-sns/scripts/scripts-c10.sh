#!/usr/bin/env bash
# Event: 20261014_gitin2222-ecs-reinicios-avisos-sns
# C10 - Zabbix 6.0.32 (sf-monitoreo.smartfran.com:8080), token en $ZABBIX_API_KEY dentro del cuerpo JSON (nunca literal). Crea en la plantilla "AWS ECS Serverless Cluster by HTTP" (id 10576):
#       1) la macro de plantilla {$AWS.ECS.CLUSTER.SERVICE.RUNNING.DIP} = 0.05
#       2) el prototipo de trigger "Running tasks below desired" (Warning) en la regla "Cluster Services discovery" (id 44973, macro LLD {#AWS.ECS.SERVICE.NAME})
#      Sale de la lectura C9 (data/c9-run-log-20261015T013249Z.txt) y del paso a paso outputs/zabbix-trigger-running-menor-que-desired.md.
#      Modos:  payload  (SOLO LECTURA, sin llamar a la API) imprime las dos cargas
#              dry      (SOLO LECTURA, por defecto) guardas + snapshot de lo existente + cargas
#              apply    (CAMBIA ESTADO) crea la macro y despues el prototipo; guarda los ids; lee de nuevo
#              rollback <carpeta c10-run-...> (CAMBIA ESTADO) borra el prototipo y la macro creados en esa corrida
#      Sin tags de enrutamiento: el trigger aparece en Problemas pero no notifica a nadie hasta que se agreguen (decision pendiente).
#      Afecta a los 3 hosts vinculados a la plantilla (smartfran-pedidos-production, smartfran-pedidos-dev y Zabbix server) en el proximo descubrimiento de servicios.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
MODE="${1:-dry}"; SNAP="${2:-}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/data"
TS=$(date -u +%Y%m%dT%H%M%SZ); RUN="$OUT/c10-run-$TS"
TEMPLATE_ID=10576; TEMPLATE_NAME="AWS ECS Serverless Cluster by HTTP"; RULE_ID=44973
MACRO='{$AWS.ECS.CLUSTER.SERVICE.RUNNING.DIP}'; MACRO_VALUE='0.05'
TNAME='AWS ECS Cluster Service: [{#AWS.ECS.SERVICE.NAME}]: Running tasks below desired'

# --- cargas (locales, sin API)
RUNK="last(/${TEMPLATE_NAME}/aws.ecs.services.running.task[\"{#AWS.ECS.SERVICE.NAME}\"])"
DESK="last(/${TEMPLATE_NAME}/aws.ecs.services.desired.task[\"{#AWS.ECS.SERVICE.NAME}\"])"
EXPR="${RUNK}<${DESK}-${MACRO}"; REC="${RUNK}>=${DESK}"
MACRO_PAYLOAD=$(jq -nc --arg h "$TEMPLATE_ID" --arg m "$MACRO" --arg v "$MACRO_VALUE" '{hostid:$h, macro:$m, value:$v, description:"Margen (tareas) por debajo de Desired antes de considerarlo una caida; Running llega como promedio de 10 minutos (GITIN-2222)"}')
TRIG_PAYLOAD=$(jq -nc --arg d "$TNAME" --arg e "$EXPR" --arg r "$REC" '{description:$d, expression:$e, recovery_mode:1, recovery_expression:$r, priority:2, status:0,
  opdata:"Running: {ITEM.LASTVALUE1} | Desired: {ITEM.LASTVALUE2}",
  comments:"Running Task (promedio de 10 min de RunningTaskCount) por debajo de Desired Task. Tambien aparece cuando la Lambda de la cola sube Desired y las tareas nuevas tardan en iniciar. GITIN-2222.",
  tags:[{tag:"scope",value:"availability"},{tag:"service",value:"{#AWS.ECS.SERVICE.NAME}"}]}')
if [ "$MODE" = "payload" ]; then echo "== macro (usermacro.create)"; echo "$MACRO_PAYLOAD" | jq .; echo "== prototipo de trigger (triggerprototype.create)"; echo "$TRIG_PAYLOAD" | jq .; exit 0; fi

: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
call() { # call <metodo> <params-json>
  jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
    | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }

if [ "$MODE" = "rollback" ]; then
  [ -f "$SNAP/created-ids.json" ] || { echo "uso: $0 rollback <carpeta c10-run-...> (falta created-ids.json)"; exit 1; }
  TID=$(jq -r '.triggerprototypeid' "$SNAP/created-ids.json"); MID=$(jq -r '.hostmacroid' "$SNAP/created-ids.json")
  # guarda: el prototipo y la macro a borrar son los que se crearon (mismo nombre / mismo macro)
  call triggerprototype.get "$(jq -n --arg t "$TID" '{triggerids:[$t],output:["description"]}')" | jq -e --arg d "$TNAME" '.[0].description==$d' >/dev/null || { echo "GUARDA: el prototipo $TID no tiene el nombre esperado"; exit 1; }
  call usermacro.get "$(jq -n --arg m "$MID" '{hostmacroids:[$m],output:["macro"]}')" | jq -e --arg m "$MACRO" '.[0].macro==$m' >/dev/null || { echo "GUARDA: la macro $MID no es la esperada"; exit 1; }
  call triggerprototype.delete "[\"$TID\"]"; call usermacro.delete "[\"$MID\"]"
  echo "rollback aplicado desde $SNAP (prototipo $TID y macro $MID borrados)"; exit 0
fi

echo "version de la API: $(jq -n '{jsonrpc:"2.0",method:"apiinfo.version",params:[],id:1}' | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq -r .result) | modo=$MODE | $TS"
mkdir -p "$RUN"
# --- snapshot y guardas
call template.get "$(jq -n --arg t "$TEMPLATE_ID" '{templateids:[$t],output:["templateid","name"],selectHosts:["name"]}')" > "$RUN/before-template.json"
jq -e --arg n "$TEMPLATE_NAME" '.[0].name==$n' "$RUN/before-template.json" >/dev/null || { echo "GUARDA: la plantilla $TEMPLATE_ID no es '$TEMPLATE_NAME'"; exit 1; }
echo "plantilla vinculada a: $(jq -r '[.[0].hosts[].name]|join("; ")' "$RUN/before-template.json")"
call discoveryrule.get "$(jq -n --arg r "$RULE_ID" '{itemids:[$r],output:["itemid","key_"],templateids:["'"$TEMPLATE_ID"'"]}')" > "$RUN/before-rule.json"
jq -e '.[0].key_=="aws.ecs.services.discovery"' "$RUN/before-rule.json" >/dev/null || { echo "GUARDA: la regla $RULE_ID no es aws.ecs.services.discovery de la plantilla"; exit 1; }
call itemprototype.get "$(jq -n --arg r "$RULE_ID" '{discoveryids:[$r],output:["key_"],search:{key_:"task"}}')" > "$RUN/before-itemprototypes.json"
for K in 'aws.ecs.services.running.task["{#AWS.ECS.SERVICE.NAME}"]' 'aws.ecs.services.desired.task["{#AWS.ECS.SERVICE.NAME}"]'; do
  jq -e --arg k "$K" 'map(.key_)|index($k)!=null' "$RUN/before-itemprototypes.json" >/dev/null || { echo "GUARDA: falta el prototipo de item $K"; exit 1; }
done
call triggerprototype.get "$(jq -n --arg r "$RULE_ID" '{discoveryids:[$r],output:["triggerid","description","priority","status"],expandExpression:true,selectTags:["tag","value"]}')" > "$RUN/before-triggerprototypes.json"
jq -e --arg d "$TNAME" 'map(.description)|index($d)==null' "$RUN/before-triggerprototypes.json" >/dev/null || { echo "GUARDA: ya existe un prototipo llamado '$TNAME'"; exit 1; }
echo "prototipos de trigger existentes en la regla: $(jq length "$RUN/before-triggerprototypes.json")"
call usermacro.get "$(jq -n --arg t "$TEMPLATE_ID" '{hostids:[$t],output:["hostmacroid","macro","value","type"],filter:{type:"0"}}')" > "$RUN/before-macros.json"
jq -e --arg m "$MACRO" 'map(.macro)|index($m)==null' "$RUN/before-macros.json" >/dev/null || { echo "GUARDA: la macro $MACRO ya existe en la plantilla"; exit 1; }
echo "guardas OK. Cargas:"; echo "$MACRO_PAYLOAD" | jq -c .; echo "$TRIG_PAYLOAD" | jq -c .
echo "snapshot en $RUN"
if [ "$MODE" != "apply" ]; then echo "DRY: no se cambio nada. Para aplicar: $0 apply"; exit 0; fi

# --- apply: la macro primero (una macro desconocida invalida la expresion), despues el prototipo
M=$(call usermacro.create "$MACRO_PAYLOAD"); echo "$M" > "$RUN/create-macro.json"; MID=$(echo "$M" | jq -r '.hostmacroids[0]')
T=$(call triggerprototype.create "$(echo "$TRIG_PAYLOAD" | jq -c --arg d "$TNAME" '.')") || { echo "FALLO al crear el prototipo; la macro $MID quedo creada. Rollback parcial: borrar usermacro $MID"; echo "{\"hostmacroid\":\"$MID\",\"triggerprototypeid\":\"\"}" > "$RUN/created-ids.json"; exit 1; }
echo "$T" > "$RUN/create-triggerprototype.json"; TID=$(echo "$T" | jq -r '.triggerids[0]')
jq -n --arg m "$MID" --arg t "$TID" '{hostmacroid:$m, triggerprototypeid:$t}' > "$RUN/created-ids.json"
call triggerprototype.get "$(jq -n --arg t "$TID" '{triggerids:[$t],output:["triggerid","description","priority","status","recovery_mode","opdata"],expandExpression:true,selectTags:["tag","value"]}')" > "$RUN/after-triggerprototype.json"
call usermacro.get "$(jq -n --arg m "$MID" '{hostmacroids:[$m],output:["hostmacroid","macro","value"]}')" > "$RUN/after-macro.json"
echo "== despues"; jq -c '.[0]|{description,priority,status,expression}' "$RUN/after-triggerprototype.json"; jq -c '.[0]' "$RUN/after-macro.json"
echo "aplicado. Los triggers aparecen en los hosts en el proximo descubrimiento de servicios. Rollback: $0 rollback $RUN"

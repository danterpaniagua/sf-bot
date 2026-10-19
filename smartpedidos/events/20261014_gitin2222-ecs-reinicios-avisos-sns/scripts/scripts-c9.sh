#!/usr/bin/env bash
# Event: 20261014_gitin2222-ecs-reinicios-avisos-sns
# C9 - SOLO LECTURA contra la API de Zabbix (sf-monitoreo.smartfran.com:8080, Zabbix 6.0.32; token en $ZABBIX_API_KEY dentro del cuerpo JSON, nunca literal).
#      Objetivo: crear un trigger "Running Task menor que Desired Task" para los servicios del cluster. Los items Running/Desired (float, 5 min, promedio de 10 min) se crean por descubrimiento
#      ("Cluster Services discovery", aws.ecs.services.discovery) en la plantilla "AWS ECS Serverless Cluster by HTTP"; el host smartfran-pedidos-production es un host descubierto, asi que el trigger
#      tiene que ser un PROTOTIPO de trigger en esa regla (o en una plantilla propia). Este script lee, sin cambiar nada:
#        a) el id de la plantilla y a que hosts esta vinculada (el cambio en la plantilla alcanza a todos)
#        b) las macros LLD de la regla de servicios (nombre exacto, p. ej. {#SERVICE.NAME}) y los prototipos de item/trigger existentes con su expresion, severidad y tags
#        c) las macros de plantilla que empiezan con {$AWS.ECS (solo nombre y valor si NO es secreto: type 0; los secretos/ocultos no se piden)
#      No pide macros del host. Salidas en data/c9/.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/data/c9"
mkdir -p "$OUT"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }

# a) plantillas ECS y hosts vinculados
call template.get '{"output":["templateid","host","name"],"search":{"name":"AWS ECS"},"selectHosts":["hostid","name"]}' > "$OUT/templates.json"
echo "== plantillas 'AWS ECS' y hosts vinculados"
jq -r '.[] | [.templateid, .name, ([.hosts[].name]|join("; "))] | @tsv' "$OUT/templates.json"
TID=$(jq -r '[.[]|select(.name=="AWS ECS Serverless Cluster by HTTP")][0].templateid' "$OUT/templates.json")
echo "plantilla elegida: $TID"

# b) reglas de descubrimiento, macros LLD, prototipos
call discoveryrule.get "$(jq -n --arg t "$TID" '{templateids:[$t],output:["itemid","name","key_"],selectLLDMacroPaths:["lld_macro","path"],selectFilter:["evaltype","conditions"]}')" > "$OUT/discovery-rules.json"
echo; echo "== reglas de descubrimiento de la plantilla y sus macros LLD"
jq -r '.[] | [.itemid, .name, .key_, ([.lld_macro_paths[]|"\(.lld_macro)=\(.path)"]|join(", "))] | @tsv' "$OUT/discovery-rules.json" | cut -c1-300
RID=$(jq -r '[.[]|select(.key_=="aws.ecs.services.discovery")][0].itemid' "$OUT/discovery-rules.json")
call triggerprototype.get "$(jq -n --arg r "$RID" '{discoveryids:[$r],output:["triggerid","description","priority","status","expression","recovery_expression","manual_close","opdata"],expandExpression:true,selectTags:["tag","value"],selectDependencies:["triggerid"]}')" > "$OUT/trigger-prototypes.json"
echo; echo "== prototipos de trigger de la regla de servicios (severidad | estado | nombre | expresion | tags | opdata)"
jq -r '.[] | [(.priority|tostring), (if .status=="0" then "on" else "off" end), .description, (.expression|.[0:200]), ([.tags[]|"\(.tag)=\(.value)"]|join(",")), (.opdata // "")] | @tsv' "$OUT/trigger-prototypes.json" | cut -c1-420
call itemprototype.get "$(jq -n --arg r "$RID" '{discoveryids:[$r],output:["itemid","name","key_","value_type","delay","type"],filter:{key_:[]}, search:{key_:"task"}}')" > "$OUT/item-prototypes-task.json"
echo; echo "== prototipos de item con 'task' en la clave (nombre | clave | tipo de valor | intervalo)"
jq -r '.[] | [.name, .key_, .value_type, .delay] | @tsv' "$OUT/item-prototypes-task.json" | cut -c1-260

# c) macros de plantilla (sin secretos)
call usermacro.get "$(jq -n --arg t "$TID" '{hostids:[$t],output:["macro","value","type","description"],filter:{type:"0"}}')" > "$OUT/template-macros.json"
echo; echo "== macros de la plantilla (solo texto plano; las secretas/ocultas no se piden)"
jq -r '.[] | [.macro, .value, (.description[0:80])] | @tsv' "$OUT/template-macros.json" | cut -c1-260
echo listo

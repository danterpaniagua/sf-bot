#!/usr/bin/env bash
# Event: 20261014_gitin2222-ecs-reinicios-avisos-sns
# C14 - SOLO LECTURA contra la API de Zabbix (sf-monitoreo.smartfran.com:8080, 6.0.32; token en $ZABBIX_API_KEY).
#       Pedido del usuario: dejar la alerta/monitoreo ECS "solo en smartfran-pedidos-production" y agregar las macros requeridas.
#       La plantilla "AWS ECS Serverless Cluster by HTTP" (10576) esta vinculada a 3 hosts: "Zabbix server", smartfran-pedidos-production (descubierto) y smartfran-pedidos-dev (descubierto).
#       Este script lee, por cada uno de esos hosts: plantillas vinculadas, si es descubierto (y de que host/prototipo viene), y SUS MACROS de usuario (nombre, tipo, si tiene valor).
#       Los valores de macros con nombre de credencial (KEY, SECRET, TOKEN, PASS) NO se imprimen ni se guardan; los de tipo secreto/vault la API tampoco los devuelve.
#       Tambien lista los items ECS (cantidad) y los triggers ECS por host para ver que seria afectado al desvincular.
#       Salidas en data/c14/.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/data/c14"
mkdir -p "$OUT"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
MASK='if (.macro|test("KEY|SECRET|TOKEN|PASS";"i")) then (if (.value // "")=="" then "(vacio)" else "(enmascarado)" end) elif .type=="1" then "(secreto)" elif .type=="2" then "(vault)" else (.value // "" | .[0:60]) end'

# la respuesta cruda no se escribe en disco: se enmascara en la tuberia y solo se guarda la copia sin valores de credenciales
call host.get '{"templateids":["10576"],"output":["hostid","host","name","status","flags"],"selectParentTemplates":["templateid","name"],"selectMacros":["hostmacroid","macro","type","value"],"selectHostDiscovery":["parent_hostid","parent_itemid","host"],"selectGroups":["name"]}' \
  | jq "[.[] | .macros |= map(.value = ($MASK|tostring))]" > "$OUT/hosts-masked.json"
echo "== hosts con la plantilla 10576: $(jq length "$OUT/hosts-masked.json")"
jq -r '.[] | "\n######## \(.hostid) \(.name) | \(if .status=="0" then "habilitado" else "deshabilitado" end) | \(if .flags=="4" then "DESCUBIERTO (prototipo \(.hostDiscovery.parent_itemid // "?") del host \(.hostDiscovery.parent_hostid // "?"))" else "manual" end) | grupos: \([.groups[].name]|join(", "))\n  plantillas: \([.parentTemplates[].name]|join("; "))\n  macros (\(.macros|length)):"' "$OUT/hosts-masked.json"
jq -r '.[] | .name as $h | .macros[] | [$h, .macro, ("tipo=" + .type), .value] | @tsv' "$OUT/hosts-masked.json" | cut -c1-200
echo; echo "== items y triggers ECS por host (cantidad)"
for HID in $(jq -r '.[].hostid' "$OUT/hosts-masked.json"); do
  NI=$(call item.get "$(jq -n --arg h "$HID" '{hostids:[$h],countOutput:true,search:{key_:"aws.ecs."}}')" | jq -r .)
  NT=$(call trigger.get "$(jq -n --arg h "$HID" '{hostids:[$h],countOutput:true,search:{description:"AWS ECS"}}')" | jq -r .)
  echo "host $HID: items aws.ecs.*=$NI | triggers 'AWS ECS'=$NT"
done
echo listo

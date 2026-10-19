#!/usr/bin/env bash
# Event: 20261014_gitin2222-ecs-reinicios-avisos-sns
# C7 - SOLO LECTURA contra la API de Zabbix (sf-monitoreo.smartfran.com:8080, Zabbix 6.0.32; token en $ZABBIX_API_KEY dentro del cuerpo JSON, nunca literal).
#      Contexto: el usuario mostro en el frontend un host "AWS Zabbix server" con "ECS clusters discovery: smartfran-pedidos-production" (53 items, 12 triggers, 10 graficos, 2 discovery).
#      Objetivo: ver que items y triggers ya existen para ese cluster (tareas corriendo/pendientes/detenidas, servicios, deseadas vs corriendo) antes de crear una alerta de contenedores detenidos.
#      Pide solo campos minimos: NO trae macros del host (podrian tener las credenciales de AWS), ni cabeceras/URL de los items HTTP.
#      Salidas en data/c7/ (JSON) y un resumen por pantalla.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/data/c7"
mkdir -p "$OUT"
call() { # call <metodo> <params-json>
  jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
    | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" \
    | jq 'if .error then error("API: " + (.error|tostring)) else .result end'
}
echo "version de la API: $(jq -n '{jsonrpc:"2.0",method:"apiinfo.version",params:[],id:1}' | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq -r .result)"

# 1) hosts relacionados con el cluster o con AWS
call host.get '{"output":["hostid","host","name","status","flags"],"search":{"name":"smartfran-pedidos"},"selectParentTemplates":["name"],"selectInterfaces":["ip","port","type"]}' > "$OUT/hosts-cluster.json"
call host.get '{"output":["hostid","host","name","status","flags"],"search":{"name":"AWS"},"selectParentTemplates":["name"]}' > "$OUT/hosts-aws.json"
echo "== hosts cuyo nombre contiene 'smartfran-pedidos'"
jq -r '.[] | [.hostid, .name, (if .status=="0" then "habilitado" else "deshabilitado" end), (if .flags=="4" then "descubierto" else "manual" end), ([.parentTemplates[].name]|join("; "))] | @tsv' "$OUT/hosts-cluster.json"
echo "== hosts cuyo nombre contiene 'AWS'"
jq -r '.[] | [.hostid, .name, (if .status=="0" then "habilitado" else "deshabilitado" end), (if .flags=="4" then "descubierto" else "manual" end), ([.parentTemplates[].name]|join("; "))] | @tsv' "$OUT/hosts-aws.json"

# 2) items, triggers y reglas de descubrimiento de cada host del cluster
for HID in $(jq -r '.[].hostid' "$OUT/hosts-cluster.json"); do
  call item.get "$(jq -n --arg h "$HID" '{hostids:[$h],output:["itemid","name","key_","type","status","state","delay","value_type","lastvalue","units"],sortfield:"name"}')" > "$OUT/items-$HID.json"
  call trigger.get "$(jq -n --arg h "$HID" '{hostids:[$h],output:["triggerid","description","priority","status","state","value","expression","recovery_expression"],expandExpression:true,expandDescription:true,selectTags:["tag","value"],selectDependencies:["triggerid"],sortfield:"priority"}')" > "$OUT/triggers-$HID.json"
  call discoveryrule.get "$(jq -n --arg h "$HID" '{hostids:[$h],output:["itemid","name","key_","status","delay"]}')" > "$OUT/discovery-$HID.json"
  echo; echo "######## host $HID: $(jq -r --arg h "$HID" '.[]|select(.hostid==$h)|.name' "$OUT/hosts-cluster.json")"
  echo "items: $(jq length "$OUT/items-$HID.json") | triggers: $(jq length "$OUT/triggers-$HID.json") | reglas de descubrimiento: $(jq length "$OUT/discovery-$HID.json")"
  echo "-- reglas de descubrimiento"; jq -r '.[]|[.name,.key_,.delay,(if .status=="0" then "habilitada" else "deshabilitada" end)]|@tsv' "$OUT/discovery-$HID.json"
  echo "-- items (nombre | clave | ultimo valor | estado)"
  jq -r '.[]|[.name,.key_,(.lastvalue|tostring|.[0:40]),(if .state=="1" then "NO SOPORTADO" else "ok" end)]|@tsv' "$OUT/items-$HID.json" | cut -c1-230
  echo "-- triggers (severidad | habilitado | valor | nombre | expresion)"
  jq -r '.[]|[(.priority|tostring), (if .status=="0" then "on" else "off" end), (if .value=="1" then "PROBLEMA" else "ok" end), .description, (.expression|.[0:160]), ([.tags[]|"\(.tag)=\(.value)"]|join(","))]|@tsv' "$OUT/triggers-$HID.json" | cut -c1-330
done
echo listo

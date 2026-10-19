#!/usr/bin/env bash
# Event: 20261014_gitin2222-ecs-reinicios-avisos-sns
# C29 - SOLO LECTURA contra la API de Zabbix (6.0.32; token en $ZABBIX_API_KEY).
#       Decision del usuario: opcion 1 (alerta ante cualquier caida, margen 0.05 de la plantilla). Antes de borrar o cambiar la macro hay que saber DE DONDE sale el 1000 en los hosts descubiertos
#       (10666, 10667, 10668): si esta definida en el PROTOTIPO DE HOST de la regla de descubrimiento, los tres hosts la reciben de ahi y borrarla en el host descubierto no persiste; si es una macro propia
#       del host, se puede borrar o cambiar en el host. Lee:
#         a) hosts 10666/10667/10668 y 10620 (el host "padre" visto en C7): nombre, flags, macros RUNNING.DIP con su id, y de donde se descubrio cada uno (prototipo de host)
#         b) los prototipos de host de la regla (nombre, grupos de hosts, macros RUNNING.DIP) y la regla que los contiene
#       Salidas en data/c29/.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/data/c29"
mkdir -p "$OUT"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
call host.get '{"hostids":["10666","10667","10668","10620"],"output":["hostid","host","name","flags"],"selectMacros":["hostmacroid","macro","value"],"selectHostDiscovery":"extend","selectGroups":["name"]}' > "$OUT/hosts.json"
echo "== hosts (id | nombre | flags 4=descubierto | grupos | macros RUNNING.DIP [id=valor] | prototipo de host de origen)"
jq -r '.[]|[.hostid,.name,.flags,([.groups[].name]|join(",")),([.macros[]?|select(.macro|test("RUNNING.DIP"))|"\(.hostmacroid)=\(.value)"]|join(" ")),(.hostDiscovery.parent_hostid // "-")]|@tsv' "$OUT/hosts.json"
call hostprototype.get '{"output":["hostid","host","name","status"],"selectMacros":["macro","value"],"selectGroupLinks":["groupid"],"selectGroupPrototypes":["name"],"selectDiscoveryRule":["itemid","name","hostid"],"selectParentHost":["hostid","host","name"]}' > "$OUT/hostprototypes.json"
echo; echo "== prototipos de host (id | host | regla de descubrimiento | host que la contiene | macros RUNNING.DIP | grupos [ids de enlace + nombres de prototipo])"
jq -r '.[]|[.hostid,.host,(.discoveryRule.name // "-"),(.parentHost.host // "-"),([.macros[]?|select(.macro|test("RUNNING.DIP"))|"\(.macro)=\(.value)"]|join(" ")),(([.groupLinks[].groupid]|join(","))+" / "+([.groupPrototypes[]?.name]|join(",")))]|@tsv' "$OUT/hostprototypes.json"
echo listo

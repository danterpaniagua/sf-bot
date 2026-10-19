#!/usr/bin/env bash
# Event: 20261014_gitin2222-ecs-reinicios-avisos-sns
# C23 - SOLO LECTURA contra la API de Zabbix (6.0.32; token en $ZABBIX_API_KEY).
#       C21 mostro que el trigger "Running tasks below desired" del host smartfran-pedidos-production (26915, 26916) tiene en su expresion expandida el margen "-1000",
#       por lo que no puede dispararse, y que no genero eventos despues de las 06:30 (-03:00) del 15-10. En C17 solo se creo la macro de 1000 en el host "Zabbix server" (10084).
#       Este script busca DONDE esta definida la macro {$AWS.ECS.CLUSTER.SERVICE.RUNNING.DIP}: en que hosts/plantillas/global y con que valor, y trae el trigger 26915
#       con su expresion SIN expandir y sus funciones. Tambien lista la herencia del host 10666 (plantillas vinculadas y host padre).
#       Salidas en data/c23/.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/data/c23"
mkdir -p "$OUT"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
call usermacro.get '{"output":["hostmacroid","macro","value","hostid"],"search":{"macro":"RUNNING.DIP"},"selectHosts":["hostid","name","flags"],"selectTemplates":["templateid","name"]}' > "$OUT/macros-host-template.json"
call usermacro.get '{"globalmacro":true,"output":["globalmacroid","macro","value"],"search":{"macro":"RUNNING.DIP"}}' > "$OUT/macros-global.json"
echo "== macros RUNNING.DIP en hosts y plantillas (macro | valor | donde)"
jq -r '.[]|[.macro,.value,((.hosts[0]|"host \(.name) (id \(.hostid), flags \(.flags))")? // (.templates[0]|"plantilla \(.name) (id \(.templateid))")? // "?")]|@tsv' "$OUT/macros-host-template.json"
echo "== macros globales"; jq -r '.[]|[.macro,.value]|@tsv' "$OUT/macros-global.json"
call host.get '{"hostids":["10666"],"output":["hostid","host","name","flags"],"selectParentTemplates":["templateid","name"],"selectMacros":["macro","value"],"selectDiscovery":["parent_hostid","host_prototype"],"selectGroups":["name"]}' > "$OUT/host-10666.json"
echo; echo "== host 10666: plantillas vinculadas, host padre del descubrimiento y macros propias"
jq -r '.[0]|"nombre: \(.name) | flags \(.flags)", "plantillas: \([.parentTemplates[].name]|join(" ; "))", "descubierto desde: \(.discovery|tostring)", "macros propias: \([.macros[]|select(.macro|test("RUNNING.DIP"))|"\(.macro)=\(.value)"]|join(" ; "))"' "$OUT/host-10666.json"
call trigger.get '{"triggerids":["26915","26916"],"output":["triggerid","description","expression","value","lastchange","templateid","flags"],"selectFunctions":["functionid","parameter"],"selectDiscoveryRule":["itemid","name"],"selectTags":"extend"}' > "$OUT/triggers-raw.json"
echo; echo "== triggers 26915/26916 sin expandir (id | templateid | expresion cruda | ultimo cambio UTC)"
jq -r '.[]|[.triggerid,.templateid,.expression,(.lastchange|tonumber|strftime("%FT%TZ"))]|@tsv' "$OUT/triggers-raw.json"
# eventos de los triggers entre 09:00 y 09:45 UTC del 15-10 (06:00-06:45 -03:00, cuando empezaron los 18 correos) con las etiquetas QUE TENIAN al abrirse, y las notificaciones generadas
FROM=$(date -u -d "2026-10-15 09:00:00" +%s); TO=$(date -u -d "2026-10-15 09:45:00" +%s)
call event.get "$(jq -n --argjson f "$FROM" --argjson t "$TO" '{objectids:["26915","26916"],time_from:$f,time_till:$t,source:0,object:0,output:["eventid","objectid","clock","value","name"],selectTags:"extend",sortfield:["clock"],sortorder:"ASC"}')" > "$OUT/events-0900-0945.json"
echo; echo "== eventos 09:00-09:45 UTC (hora -03:00 | trigger | PROBLEMA/OK | etiquetas del evento)"
jq -r '.[]|[((.clock|tonumber)-10800|strftime("%H:%M:%S")),.objectid,(if .value=="1" then "PROBLEMA" else "OK" end),([.tags[]|"\(.tag)=\(.value)"]|join(","))]|@tsv' "$OUT/events-0900-0945.json"
EIDS=$(jq -c '[.[].eventid]' "$OUT/events-0900-0945.json")
call alert.get "$(jq -n --argjson e "$EIDS" '{eventids:$e,output:["alertid","eventid","actionid","mediatypeid","status","retries","error","clock"],sortfield:["clock"],sortorder:"ASC"}')" > "$OUT/alerts-0900-0945.json"
echo; echo "== notificaciones generadas por esos eventos: $(jq length "$OUT/alerts-0900-0945.json") (hora -03:00 | evento | accion | tipo de medio | status 0=pendiente 1=enviada 2=fallida | error)"
jq -r '.[]|[((.clock|tonumber)-10800|strftime("%H:%M:%S")),.eventid,.actionid,.mediatypeid,.status,.error]|@tsv' "$OUT/alerts-0900-0945.json"
echo listo

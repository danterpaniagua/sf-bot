#!/usr/bin/env bash
# Event: 20261014_gitin2222-ecs-reinicios-avisos-sns
# C11 - SOLO LECTURA contra la API de Zabbix (sf-monitoreo.smartfran.com:8080, 6.0.32; token en $ZABBIX_API_KEY). Verifica lo creado por C10 (apply 2026-10-15 01:36 UTC):
#       a) el prototipo de trigger con su expresion y su expresion de recuperacion tal como quedaron guardadas (la lectura de C10 no pidio esos campos)
#       b) los triggers descubiertos a partir de el en los hosts vinculados (aparecen despues del proximo descubrimiento de servicios, hasta unos minutos)
#       c) el estado actual (valor PROBLEMA/ok) de esos triggers y los ultimos valores de Running/Desired de platform-service
#      Salidas en data/c11/.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/data/c11"
mkdir -p "$OUT"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
echo "ahora (UTC): $(date -u +%FT%TZ)"
call triggerprototype.get '{"discoveryids":["44973"],"search":{"description":"Running tasks below desired"},"output":["triggerid","description","priority","status","recovery_mode","opdata","expression","recovery_expression"],"selectTags":["tag","value"]}' > "$OUT/prototype.json"
echo "== prototipo guardado"; jq -c '.[]|{triggerid,description,priority,status,recovery_mode,opdata,expression,recovery_expression,tags}' "$OUT/prototype.json"
call trigger.get '{"search":{"description":"Running tasks below desired"},"output":["triggerid","description","priority","status","state","value","lastchange","expression","error"],"selectHosts":["name"],"selectTags":["tag","value"],"expandExpression":true,"expandDescription":true,"filter":{"flags":"4"}}' > "$OUT/discovered-triggers.json"
echo; echo "== triggers descubiertos: $(jq length "$OUT/discovered-triggers.json")"
jq -r '.[] | [([.hosts[].name]|join(";")), .description[0:90], (if .value=="1" then "PROBLEMA" else "ok" end), (if .status=="0" then "on" else "off" end), (if .state=="1" then "DESCONOCIDO" else "evaluado" end), (.error // ""), ([.tags[]|"\(.tag)=\(.value)"]|join(","))] | @tsv' "$OUT/discovered-triggers.json"
echo; echo "== valores actuales de Running / Desired en los hosts vinculados"
call item.get '{"search":{"key_":"aws.ecs.services."},"output":["name","key_","lastvalue","lastclock"],"selectHosts":["name"],"filter":{"flags":"4"}}' \
  | jq '[.[] | select(.key_|test("running.task|desired.task"))]' > "$OUT/running-desired-items.json"
jq -r '.[] | [([.hosts[].name]|join(";")), (.name|sub("AWS ECS Cluster Service: ";"")), .lastvalue, (.lastclock|tonumber|strftime("%H:%M:%SZ"))] | @tsv' "$OUT/running-desired-items.json" | cut -c1-200
echo listo

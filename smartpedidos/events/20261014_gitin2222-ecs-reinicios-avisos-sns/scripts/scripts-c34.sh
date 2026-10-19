#!/usr/bin/env bash
# Event: 20261014_gitin2222-ecs-reinicios-avisos-sns
# C34 - SOLO LECTURA contra la API de Zabbix (6.0.32; token en $ZABBIX_API_KEY).
#       C33 (apply, 2026-10-15 18:32 UTC) devolvio OK en sus 7 pasos, pero su lectura posterior no incluyo el campo "expression" y la columna de expresion salio vacia: el margen 0.05 no quedo verificado.
#       Este script lee, despues del cambio:
#         a) los triggers 26915 y 26916 (production) y 26917 y 26918 (Zabbix server): estado (0=activo), valor, estado de evaluacion, error, expresion CRUDA y EXPANDIDA (con el valor de la macro) y etiquetas
#         b) las macros RUNNING.DIP que quedan en cualquier host o plantilla (esperado: solo la de la plantilla 10576 = 0.05)
#         c) los eventos de esos triggers desde las 18:32 UTC y las notificaciones que generaron (para ver si ya aviso algo despues del cambio)
#       Salidas en data/c34/.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/data/c34"
mkdir -p "$OUT"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
echo "== $(date -u +%FT%TZ)"
call trigger.get '{"triggerids":["26915","26916","26917","26918"],"output":["triggerid","description","status","value","state","error","expression"],"expandExpression":true,"selectHosts":["host"],"selectTags":["tag","value"]}' > "$OUT/triggers-expanded.json"
call trigger.get '{"triggerids":["26915","26916","26917","26918"],"output":["triggerid","expression"]}' > "$OUT/triggers-raw.json"
echo "== triggers (id | host | status 0=activo | value | state 0=normal | error)"
jq -r '.[]|[.triggerid,.hosts[0].host,.status,.value,.state,.error]|@tsv' "$OUT/triggers-expanded.json"
echo "== expresion expandida (con el valor de la macro)"; jq -r '.[]|[.triggerid,.expression]|@tsv' "$OUT/triggers-expanded.json"
echo "== expresion cruda"; jq -r '.[]|[.triggerid,.expression]|@tsv' "$OUT/triggers-raw.json"
echo "== etiquetas (id | etiquetas)"; jq -r '.[]|[.triggerid,([.tags[]|"\(.tag)=\(.value)"]|join(","))]|@tsv' "$OUT/triggers-expanded.json"
call usermacro.get '{"output":["hostmacroid","macro","value","hostid"],"search":{"macro":"RUNNING.DIP"},"selectHosts":["host"],"selectTemplates":["name"]}' > "$OUT/macros.json"
call usermacro.get '{"globalmacro":true,"output":["macro","value"],"search":{"macro":"RUNNING.DIP"}}' > "$OUT/macros-global.json"
echo "== macros RUNNING.DIP que quedan (macro | valor | donde)"
jq -r '.[]|[.macro,.value,((.hosts[0].host // .templates[0].name) // "?")]|@tsv' "$OUT/macros.json"; echo "(globales: $(jq length "$OUT/macros-global.json"))"
FROM=$(date -u -d "2026-10-15 18:32:00" +%s)
call event.get "$(jq -n --argjson f "$FROM" '{objectids:["26915","26916","26917","26918"],time_from:$f,source:0,object:0,output:["eventid","objectid","clock","value"],sortfield:["clock"],sortorder:"ASC"}')" > "$OUT/events-since-change.json"
call alert.get "$(jq -n --argjson e "$(jq -c '[.[].eventid]' "$OUT/events-since-change.json")" '{eventids:$e,output:["eventid","actionid","status","clock"]}')" > "$OUT/alerts-since-change.json"
echo "== eventos desde las 18:32 UTC: $(jq length "$OUT/events-since-change.json") (hora -03:00 | trigger | PROBLEMA/OK | notificaciones)"
jq -r --slurpfile a "$OUT/alerts-since-change.json" '.[]|. as $e|[((.clock|tonumber)-10800|strftime("%H:%M:%S")),.objectid,(if .value=="1" then "PROBLEMA" else "OK" end),([$a[0][]|select(.eventid==$e.eventid)]|length)]|@tsv' "$OUT/events-since-change.json"
echo listo

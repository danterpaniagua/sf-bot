#!/usr/bin/env bash
# Event: 20261015_gitin2239-mobile-healthcheck-alerta-zabbix (GITIN-2239)
# C1 - SOLO LECTURA contra la API de Zabbix (sf-monitoreo.smartfran.com:8080, 6.0.32; token en $ZABBIX_API_KEY).
#      Inventario de TODOS los healthchecks monitoreados con escenarios web: pasos cuyo nombre o URL contienen "health" (sin distinguir mayusculas).
#      Para cada uno: host, escenario, paso, URL sin query, codigos requeridos, intervalo; sus items web.test.rspcode y web.test.time[...,resp]; los triggers que ya los usan
#      (expresion, prioridad, etiquetas); y el tiempo de respuesta de los ultimos 30 dias (tendencias) para calibrar el umbral de "respuesta lenta".
#      No se leen headers, usuarios ni passwords de los pasos. Salidas en data/c1/.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/loyalty/events/20261015_gitin2239-mobile-healthcheck-alerta-zabbix/data/c1"
mkdir -p "$OUT"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
call httptest.get '{"output":["httptestid","name","delay","status"],"selectSteps":["name","url","status_codes","timeout","no"],"selectHosts":["hostid","name"]}' > "$OUT/scenarios-all.json"
echo "== escenarios web en total: $(jq length "$OUT/scenarios-all.json")"
jq '[.[] | . as $s | {httptestid, scenario:.name, host:.hosts[0].name, hostid:.hosts[0].hostid, delay, status, step:(.steps[]|select((.name|test("health";"i")) or (.url|test("health";"i"))))}
    | {httptestid, scenario, host, hostid, delay, status, step:.step.name, url:(.step.url|sub("\\?.*";"")), codes:.step.status_codes, timeout:.step.timeout}]' "$OUT/scenarios-all.json" > "$OUT/healthchecks.json"
echo; echo "== pasos de healthcheck (host | escenario | paso | URL | codigos | intervalo | status 0=activo)"
jq -r '.[]|[.host,.scenario,.step,.url,.codes,.delay,.status]|@tsv' "$OUT/healthchecks.json"
call item.get '{"webitems":true,"search":{"key_":"web.test"},"output":["itemid","hostid","name","key_","delay","history","trends","status","state","lastvalue"],"selectHosts":["name"]}' > "$OUT/web-items-all.json"
# Zabbix escribe entre comillas los parametros con caracteres especiales (web.test.rspcode["[PROD] MobileApp",healthcheck]): se comparan las claves sin comillas
jq --slurpfile h "$OUT/healthchecks.json" '[ .[] | . as $i | select([ $h[0][] | ( "web.test.rspcode[\(.scenario),\(.step)]", "web.test.time[\(.scenario),\(.step),resp]" ) ] | index($i.key_|gsub("\"";""))) ]' "$OUT/web-items-all.json" > "$OUT/healthcheck-items.json"
echo; echo "== items de esos pasos (host | clave | ultimo valor | state | historia | tendencias)"
jq -r '.[]|[.hosts[0].name,.key_,.lastvalue,.state,.history,.trends]|@tsv' "$OUT/healthcheck-items.json"
IDS=$(jq -c '[.[].itemid]' "$OUT/healthcheck-items.json")
call trigger.get "$(jq -n --argjson i "$IDS" '{itemids:$i,output:["triggerid","description","expression","priority","status","value"],selectTags:"extend",selectHosts:["name"]}')" > "$OUT/healthcheck-triggers.json"
echo; echo "== triggers existentes sobre esos items (host | id | descripcion | prioridad | status 0=activo | expresion | etiquetas)"
jq -r '.[]|[.hosts[0].name,.triggerid,.description,.priority,.status,.expression,([.tags[]|"\(.tag)=\(.value)"]|join(","))]|@tsv' "$OUT/healthcheck-triggers.json"
echo "(si la lista esta vacia, ningun healthcheck tiene trigger)"
TIMEIDS=$(jq -c '[.[]|select(.key_|test("^web.test.time"))|.itemid]' "$OUT/healthcheck-items.json")
call trend.get "$(jq -n --argjson i "$TIMEIDS" --argjson t "$(( $(date +%s) - 30*86400 ))" '{itemids:$i,time_from:$t,output:["itemid","clock","num","value_min","value_avg","value_max"]}')" > "$OUT/healthcheck-trends-30d.json"
echo; echo "== tiempo de respuesta, ultimos 30 dias, por item (s): horas con dato | minimo | promedio | p95 de promedios horarios | maximo"
jq -r --slurpfile it "$OUT/healthcheck-items.json" '
  ($it[0]|map({(.itemid):(.hosts[0].name+" | "+.key_)})|add) as $names |
  group_by(.itemid)[] | . as $g | ($g|map(.value_avg|tonumber)|sort) as $a |
  [ $names[$g[0].itemid], ($g|length), ($g|map(.value_min|tonumber)|min), ($a|add/length), $a[(length*0.95|floor)], ($g|map(.value_max|tonumber)|max) ] | @tsv' "$OUT/healthcheck-trends-30d.json"
HOSTIDS=$(jq -c '[.[].hostid]|unique' "$OUT/healthchecks.json")
call host.get "$(jq -n --argjson h "$HOSTIDS" '{hostids:$h,output:["hostid","name"],selectParentTemplates:["templateid","name"]}')" > "$OUT/healthcheck-hosts.json"
ALLIDS=$(jq -c '[.[]|.hostid, (.parentTemplates[].templateid)]|unique' "$OUT/healthcheck-hosts.json")
call usermacro.get "$(jq -n --argjson i "$ALLIDS" '{hostids:$i,output:["macro","value"],search:{macro:"IIS_CODE"},selectHosts:["name"],selectTemplates:["name"]}')" > "$OUT/macro-iis-code.json"
call usermacro.get '{"globalmacro":true,"output":["macro","value"],"search":{"macro":"IIS_CODE"}}' > "$OUT/macro-iis-code-global.json"
echo; echo "== macros IIS_CODE* en los hosts de los healthchecks y sus plantillas (macro | valor | donde); son umbrales, no secretos"
jq -r '.[]|[.macro,.value,((.hosts[0].name // .templates[0].name) // "?")]|@tsv' "$OUT/macro-iis-code.json"
echo "== macros globales IIS_CODE*"; jq -r '.[]|[.macro,.value]|@tsv' "$OUT/macro-iis-code-global.json"
echo listo

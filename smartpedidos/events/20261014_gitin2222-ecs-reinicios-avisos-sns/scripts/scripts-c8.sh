#!/usr/bin/env bash
# Event: 20261014_gitin2222-ecs-reinicios-avisos-sns
# C8 - SOLO LECTURA contra la API de Zabbix (sf-monitoreo.smartfran.com:8080, Zabbix 6.0.32; token en $ZABBIX_API_KEY dentro del cuerpo JSON, nunca literal).
#      Continuacion de C7. El usuario indico que el item "Running Task" usa el preprocesado JSONPath
#        $.[?(@.Label == "ECS/ContainerInsights RunningTaskCount")].Values.first().first()
#      Es decir, el item maestro "Get metrics" del servicio devuelve series de CloudWatch Container Insights con Label y Values (varios puntos).
#      Este script lee, para platform-service en el host smartfran-pedidos-production (10666):
#        a) el item maestro "Get metrics": tipo, intervalo y el script/parametros (la API devuelve los nombres de macro, no sus valores) -> que series, que estadistico y que periodo pide
#        b) los items dependientes de ese maestro y su preprocesado (JSONPath/JavaScript)
#        c) el ultimo valor guardado del maestro (history.get tipo texto) -> que Labels llegan y cuantos puntos trae cada uno
#      Se enmascara cualquier cosa con forma de clave AWS (AKIA..., cadenas largas base64) antes de imprimir o guardar. Salidas en data/c8/.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/data/c8"
HOST=10666; SVC="platform-service-production-service"
mkdir -p "$OUT"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
mask() { sed -E 's/AKIA[0-9A-Z]{12,}/[clave-aws]/g; s/[A-Za-z0-9+\/]{40,}/[cadena-larga]/g'; }

# a) item maestro
call item.get "$(jq -n --arg h "$HOST" --arg s "$SVC" '{hostids:[$h],search:{key_:("aws.ecs.services.get_metrics[\"" + $s + "\"")},output:["itemid","name","key_","type","delay","value_type","history","trends","params","timeout","master_itemid"]}')" | mask > "$OUT/master-item.json"
MID=$(jq -r '.[0].itemid' "$OUT/master-item.json")
echo "item maestro: $(jq -r '.[0]|[.itemid,.name,.key_,("tipo="+.type),("intervalo="+.delay),("history="+.history)]|join(" | ")' "$OUT/master-item.json")"
echo "-- script/parametros del maestro (macros sin resolver; primeras 4000 caracteres)"
jq -r '.[0].params' "$OUT/master-item.json" | head -c 4000
echo

# b) dependientes del maestro y su preprocesado
call item.get "$(jq -n --arg h "$HOST" --arg m "$MID" '{hostids:[$h],filter:{master_itemid:$m},output:["itemid","name","key_","value_type","delay"],selectPreprocessing:["type","params","error_handler"]}')" | mask > "$OUT/dependent-items.json"
echo; echo "== items dependientes del maestro: $(jq length "$OUT/dependent-items.json")"
jq -r '.[] | [.name[0:70], .key_[0:60], ([.preprocessing[]|"t\(.type): \(.params)"]|join(" ; "))] | @tsv' "$OUT/dependent-items.json" | cut -c1-330

# c) ultimo valor del maestro (texto): labels y cantidad de puntos
call history.get "$(jq -n --arg m "$MID" '{itemids:[$m],history:4,sortfield:"clock",sortorder:"DESC",limit:1,output:["clock","value"]}')" > "$OUT/master-last-raw.json"
echo; echo "== ultimo valor del maestro: reloj $(jq -r '.[0].clock // "-"' "$OUT/master-last-raw.json") (UTC epoch) | $(date -u -d "@$(jq -r '.[0].clock // 0' "$OUT/master-last-raw.json")" +%FT%TZ 2>/dev/null)"
echo "forma: $(jq -r '.[0].value | fromjson? | type' "$OUT/master-last-raw.json")"
jq -r '.[0].value | fromjson? | if type=="array" then .[] | [.Label // "?", (.Values|length|tostring)+" puntos", ((.Values|map(tostring)|.[0:6])|join(",")), ((.Timestamps // [])|length|tostring)+" marcas de tiempo", (.StatusCode // "-")] | @tsv else keys end' "$OUT/master-last-raw.json" | mask | cut -c1-260
echo listo

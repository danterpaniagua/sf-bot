#!/usr/bin/env bash
# Event: 20261014_gitin2222-ecs-reinicios-avisos-sns
# C20 - SOLO LECTURA contra la API de Zabbix (sf-monitoreo.smartfran.com:8080, 6.0.32; token en $ZABBIX_API_KEY).
#       Pedido del usuario: usar el item "AWS ECS Cluster: Task Count" de Zabbix para mostrar CUANDO EMPEZO la rotacion de tareas.
#       Item de host smartfran-pedidos-production (10666), nivel cluster (suma de tareas de platform-service + concentrador-service; nominal 6 con Desired 5+1). Se espera un promedio de CloudWatch Container Insights;
#       cuando una tarea cae un rato el promedio baja por debajo del nominal.
#       Lee: la configuracion del item (clave, intervalo, dias de historia conservados) y su historia (history.get, tipo float) de los ultimos 14 dias; la historia de Zabbix 6.0 solo se consulta asi (no hay trend.get).
#       Salidas en data/c20/: task-count-history.json (puntos crudos), task-count-hourly.tsv (hora -03:00, n, min, media, max) y task-count-daily.tsv (dia -03:00, n, min, media, max, puntos por debajo de 5.95, puntos por encima de 6.05).
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/data/c20"
mkdir -p "$OUT"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
call item.get '{"hostids":["10666"],"search":{"name":"Task Count"},"output":["itemid","name","key_","type","delay","value_type","history","trends","lastvalue","lastclock","state"]}' > "$OUT/task-count-item.json"
echo "== items del host 10666 con 'Task Count' en el nombre"
jq -r '.[] | [.itemid, .name, .key_, ("intervalo="+.delay), ("history="+.history), ("tipo_valor="+.value_type), ("ultimo="+.lastvalue)] | @tsv' "$OUT/task-count-item.json"
ID=$(jq -r '[.[]|select(.name=="AWS ECS Cluster: Task Count")][0].itemid // empty' "$OUT/task-count-item.json")
[ -n "$ID" ] || { echo "GUARDA: no se encontro el item 'AWS ECS Cluster: Task Count' en el host 10666"; exit 1; }
VT=$(jq -r --arg i "$ID" '.[]|select(.itemid==$i)|.value_type' "$OUT/task-count-item.json")
FROM=$(( $(date +%s) - 14*86400 ))
call history.get "$(jq -n --arg i "$ID" --argjson t "$FROM" --argjson v "$VT" '{itemids:[$i],history:$v,time_from:$t,output:["clock","value"],sortfield:"clock",sortorder:"ASC",limit:60000}')" > "$OUT/task-count-history.json"
N=$(jq length "$OUT/task-count-history.json")
echo; echo "item $ID: $N puntos en 14 dias | primero $(jq -r 'if length>0 then (.[0].clock|tonumber|strftime("%FT%TZ")) else "-" end' "$OUT/task-count-history.json") | ultimo $(jq -r 'if length>0 then (.[-1].clock|tonumber|strftime("%FT%TZ")) else "-" end' "$OUT/task-count-history.json")"
[ "$N" -gt 0 ] || { echo "sin historia: revisar el periodo de historia del item (history=...)"; exit 0; }
# agregados por hora y por dia en hora local (-03:00)
jq -r 'map({h:((.clock|tonumber)-10800), v:(.value|tonumber)}) | group_by(.h/3600|floor) | .[] | [((.[0].h/3600|floor)*3600|strftime("%Y-%m-%d %H:00")), length, (map(.v)|min), ((map(.v)|add/length)*100|round/100), (map(.v)|max)] | @tsv' "$OUT/task-count-history.json" > "$OUT/task-count-hourly.tsv"
jq -r 'map({d:(((.clock|tonumber)-10800)|strftime("%Y-%m-%d")), v:(.value|tonumber)}) | group_by(.d) | .[] | [.[0].d, length, (map(.v)|min), ((map(.v)|add/length)*100|round/100), (map(.v)|max), (map(select(.v<5.95))|length), (map(select(.v>6.05))|length)] | @tsv' "$OUT/task-count-history.json" > "$OUT/task-count-daily.tsv"
echo "== por dia (-03:00): dia | puntos | min | media | max | puntos < 5.95 | puntos > 6.05"
cat "$OUT/task-count-daily.tsv"
echo listo

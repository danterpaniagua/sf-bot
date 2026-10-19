#!/usr/bin/env bash
# Event: 20261014_gitin2222-ecs-reinicios-avisos-sns
# C21 - SOLO LECTURA contra la API de Zabbix (sf-monitoreo.smartfran.com:8080, 6.0.32; token en $ZABBIX_API_KEY).
#       Pregunta del usuario: llegaron 18 correos "Status: STOPPED" y Zabbix no genero ninguna alerta. Este script muestra que vio Zabbix en las ultimas 24 h (por defecto)
#       en el host smartfran-pedidos-production (10666) para platform-service-production-service:
#         a) valores historicos de los items Running Task, Desired Task y Pending Task (el item guarda solo cambios + latido)
#         b) minutos con "Task Count" del cluster por debajo del nominal (5.95), agrupados en tramos continuos (hora -03:00)
#         c) estado actual de los triggers descubiertos "Running tasks below desired" y sus eventos en el periodo
#       Uso: bash scripts-c21.sh [horas hacia atras, por defecto 24]. Salidas en data/c21/.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
H="${1:-24}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/data/c21"
mkdir -p "$OUT"
FROM=$(( $(date +%s) - H*3600 ))
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
echo "== periodo: ultimas $H h desde $(date -u -d @$FROM +%FT%TZ) hasta $(date -u +%FT%TZ)"
call item.get '{"hostids":["10666"],"search":{"name":"platform-service-production-service"},"output":["itemid","name","key_","value_type","delay","history","lastvalue","lastclock","state"]}' > "$OUT/platform-items.json"
echo "== items del servicio platform (nombre | clave | tipo de valor | ultimo valor | hora del ultimo valor UTC)"
jq -r '.[]|[.name,.key_,.value_type,.lastvalue,(.lastclock|tonumber|strftime("%FT%TZ"))]|@tsv' "$OUT/platform-items.json"
for kind in "Running Task" "Desired Task" "Pending Task"; do
  ID=$(jq -r --arg k "$kind" '[.[]|select(.name|endswith($k))][0].itemid // empty' "$OUT/platform-items.json"); VT=$(jq -r --arg k "$kind" '[.[]|select(.name|endswith($k))][0].value_type // empty' "$OUT/platform-items.json")
  [ -n "$ID" ] || { echo "(no se encontro el item '$kind')"; continue; }
  call history.get "$(jq -n --arg i "$ID" --argjson t "$FROM" --argjson v "$VT" '{itemids:[$i],history:$v,time_from:$t,output:["clock","value"],sortfield:"clock",sortorder:"ASC",limit:5000}')" > "$OUT/history-$(echo $kind|tr ' ' '_').json"
  echo; echo "== $kind (item $ID): $(jq length "$OUT/history-$(echo $kind|tr ' ' '_').json") valores guardados (hora -03:00 | valor)"
  jq -r '.[]|[((.clock|tonumber)-10800|strftime("%m-%d %H:%M:%S")),.value]|@tsv' "$OUT/history-$(echo $kind|tr ' ' '_').json" | tail -40
done
call history.get "$(jq -n --argjson t "$FROM" '{itemids:["52198"],history:0,time_from:$t,output:["clock","value"],sortfield:"clock",sortorder:"ASC",limit:5000}')" > "$OUT/task-count.json"
echo; echo "== Task Count del cluster (item 52198): $(jq length "$OUT/task-count.json") puntos; tramos con valor < 5.95 (inicio -03:00 | fin | minutos | minimo)"
jq -r '[.[]|{c:(.clock|tonumber), v:(.value|tonumber)}] as $p | reduce $p[] as $x ({runs:[],cur:null};
   if $x.v < 5.95 then (if .cur==null then .cur={s:$x.c,e:$x.c,m:$x.v,n:1} else .cur.e=$x.c | .cur.n+=1 | .cur.m=([.cur.m,$x.v]|min) end)
   else (if .cur!=null then .runs+=[.cur] | .cur=null else . end) end) | (.runs + (if .cur then [.cur] else [] end))[] |
   [((.s-10800)|strftime("%m-%d %H:%M")), ((.e-10800)|strftime("%m-%d %H:%M")), .n, .m] | @tsv' "$OUT/task-count.json"
call trigger.get '{"hostids":["10666"],"search":{"description":"Running tasks below desired"},"output":["triggerid","description","expression","value","lastchange","state","error","status"],"selectTags":"extend","expandExpression":true}' > "$OUT/triggers.json"
echo; echo "== triggers 'Running tasks below desired' en el host (id | servicio | valor 0=OK 1=problema | ultimo cambio UTC | status 0=activo | expresion expandida)"
jq -r '.[]|[.triggerid,.description,.value,(.lastchange|tonumber|strftime("%FT%TZ")),.status,.expression]|@tsv' "$OUT/triggers.json"
IDS=$(jq -c '[.[].triggerid]' "$OUT/triggers.json")
call event.get "$(jq -n --argjson i "$IDS" --argjson t "$FROM" '{objectids:$i,time_from:$t,source:0,object:0,output:["eventid","objectid","clock","value","name"],sortfield:["clock"],sortorder:"ASC"}')" > "$OUT/events.json"
echo; echo "== eventos de esos triggers en el periodo: $(jq length "$OUT/events.json")"; jq -r '.[]|[((.clock|tonumber)-10800|strftime("%m-%d %H:%M:%S")),.objectid,(if .value=="1" then "PROBLEMA" else "OK" end),.name]|@tsv' "$OUT/events.json"
echo listo

#!/usr/bin/env bash
# Event: 20261014_gitin2222-ecs-reinicios-avisos-sns
# C25 - SOLO LECTURA contra la API de Zabbix (6.0.32; token en $ZABBIX_API_KEY).
#       C24 descarto el filtro de severidad: el usuario 9 recibe el medio 38 con las 6 severidades, 24 h, habilitado, y la accion 11 esta activa. Queda la accion 11 con
#       "pausar operaciones durante mantenimiento" (pause_suppressed=1): un problema suprimido por un mantenimiento no notifica. Este script lee:
#         a) para cada evento del trigger 26915/26916 de las ultimas 24 h: hora, PROBLEMA/OK, si estaba suprimido (y por que mantenimiento) y cuantas notificaciones genero
#         b) los mantenimientos existentes: nombre, periodo, tipo y los hosts/grupos que cubren
#       Salidas en data/c25/.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/data/c25"
mkdir -p "$OUT"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
FROM=$(( $(date +%s) - 24*3600 ))
call event.get "$(jq -n --argjson f "$FROM" '{objectids:["26915","26916"],time_from:$f,source:0,object:0,output:["eventid","objectid","clock","value","suppressed"],selectSuppressionData:["maintenanceid","suppress_until"],sortfield:["clock"],sortorder:"ASC"}')" > "$OUT/events.json"
EIDS=$(jq -c '[.[].eventid]' "$OUT/events.json")
call alert.get "$(jq -n --argjson e "$EIDS" '{eventids:$e,output:["eventid","actionid","status","clock"]}')" > "$OUT/alerts.json"
echo "== eventos del trigger de Running vs Desired, ultimas 24 h (hora -03:00 | trigger | PROBLEMA/OK | suprimido 0/1 | mantenimiento | notificaciones)"
jq -r --slurpfile a "$OUT/alerts.json" '.[]|. as $e|[((.clock|tonumber)-10800|strftime("%m-%d %H:%M:%S")),.objectid,(if .value=="1" then "PROBLEMA" else "OK" end),.suppressed,([.suppression_data[]?.maintenanceid]|join(",")),([$a[0][]|select(.eventid==$e.eventid)]|length)]|@tsv' "$OUT/events.json"
call maintenance.get '{"output":["maintenanceid","name","maintenance_type","active_since","active_till","tags_evaltype"],"selectTimeperiods":["timeperiod_type","start_time","period","dayofweek","every"],"selectHosts":["name"],"selectHostGroups":["name"]}' > "$OUT/maintenances.json"
echo; echo "== mantenimientos (id | nombre | tipo 0=con datos 1=sin datos | desde | hasta | hosts | grupos | periodos [tipo, inicio seg desde medianoche, duracion seg, dias])"
jq -r '.[]|[.maintenanceid,.name,.maintenance_type,(.active_since|tonumber|strftime("%F")),(.active_till|tonumber|strftime("%F")),([.hosts[].name]|join(",")),([.hostgroups[].name]|join(",")),([.timeperiods[]|"[\(.timeperiod_type),\(.start_time),\(.period),\(.dayofweek)]"]|join(" "))]|@tsv' "$OUT/maintenances.json"
echo listo

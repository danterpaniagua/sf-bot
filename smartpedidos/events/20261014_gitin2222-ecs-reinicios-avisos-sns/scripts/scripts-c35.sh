#!/usr/bin/env bash
# Event: 20261014_gitin2222-ecs-reinicios-avisos-sns
# C35 - SOLO LECTURA contra la API de Zabbix (6.0.32; token en $ZABBIX_API_KEY).
#       C27 de las 19:13 UTC muestra que NINGUN evento de problema nuevo genero notificaciones: la prueba de GITIN-2239 (26922 y 26924, 1 evento cada uno, 0 notificaciones), el ECS 26915 (10 eventos, 0) y el Graylog FATAL 26919
#       (6 eventos, solo 5 notificados: el sexto, posterior a las ~18:15 UTC, sin aviso). El total de notificaciones de 24 h no cambio desde las 18:09 UTC (14). Antes de ese momento el FATAL notificaba.
#       Este script busca por que, SOLO LEYENDO:
#         a) los eventos de problema desde las 17:40 UTC de esos triggers: suprimido (mantenimiento), etiquetas con las que se abrieron, reconocimiento y notificaciones generadas
#         b) mantenimientos activos ahora
#         c) salud interna del servidor Zabbix (host 10084): procesos escalator, alerter, alert manager, history syncer (ocupacion) y cola, con su ultimo valor y hora
#         d) estado actual de las acciones 7 y 11 y del usuario 9 (grupos, rol), para compararlo con C27 de las 18:16 UTC
#       Salidas en data/c35/.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/data/c35"
mkdir -p "$OUT"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
echo "== $(date -u +%FT%TZ)"
FROM=$(date -u -d "2026-10-15 17:40:00" +%s)
call event.get "$(jq -n --argjson f "$FROM" '{objectids:["26915","26916","26919","26920","26921","26922","26923","26924","26925","26926","26927","26928"],time_from:$f,source:0,object:0,output:["eventid","objectid","clock","value","acknowledged","suppressed"],selectTags:"extend",selectSuppressionData:["maintenanceid"],sortfield:["clock"],sortorder:"ASC"}')" > "$OUT/events.json"
call alert.get "$(jq -n --argjson e "$(jq -c '[.[].eventid]' "$OUT/events.json")" '{eventids:$e,output:["alertid","eventid","actionid","mediatypeid","userid","status","error","clock"]}')" > "$OUT/alerts.json"
echo "== eventos desde 17:40 UTC (hora UTC | trigger | PROBLEMA/OK | suprimido | mantenimiento | notificaciones | etiquetas scope/action)"
jq -r --slurpfile a "$OUT/alerts.json" '.[]|. as $e|[(.clock|tonumber|strftime("%H:%M:%S")),.objectid,(if .value=="1" then "PROBLEMA" else "OK" end),.suppressed,([.suppression_data[]?.maintenanceid]|join(",")),([$a[0][]|select(.eventid==$e.eventid)]|length),([.tags[]|select(.tag=="scope" or .tag=="action")|"\(.tag)=\(.value)"]|join(","))]|@tsv' "$OUT/events.json"
call maintenance.get '{"output":["maintenanceid","name","active_since","active_till","maintenance_type"]}' > "$OUT/maintenances.json"
NOW=$(date +%s)
echo; echo "== mantenimientos activos ahora (id | nombre | desde | hasta) [filtra por rango de fechas; el periodo diario exacto no se evalua]"
jq -r --argjson n "$NOW" '.[]|select((.active_since|tonumber)<=$n and (.active_till|tonumber)>=$n)|[.maintenanceid,.name,(.active_since|tonumber|strftime("%F")),(.active_till|tonumber|strftime("%F"))]|@tsv' "$OUT/maintenances.json"
call item.get '{"hostids":["10084"],"search":{"key_":["zabbix[process,escalator","zabbix[process,alerter","zabbix[process,alert manager","zabbix[process,history syncer","zabbix[queue"]},"searchByAny":true,"output":["itemid","name","key_","lastvalue","lastclock","state","error"]}' > "$OUT/server-items.json"
echo; echo "== salud interna del servidor (clave | ultimo valor | hora UTC del dato | estado 0=normal)"
jq -r '.[]|[.key_,.lastvalue,((.lastclock|tonumber)|if .>0 then strftime("%H:%M:%S") else "sin dato" end),.state]|@tsv' "$OUT/server-items.json" | sort
call action.get '{"actionids":["7","11"],"output":["actionid","name","status","pause_suppressed"],"selectFilter":"extend"}' > "$OUT/actions.json"
echo; echo "== acciones 7 y 11 ahora (id | status 0=activa | formula | condiciones)"; jq -r '.[]|[.actionid,.status,(.filter.formula // ""),([.filter.conditions[]?|"\(.value2)=\(.value)"]|join(" ; "))]|@tsv' "$OUT/actions.json"
call user.get '{"userids":["9"],"output":["userid","roleid"],"selectUsrgrps":["usrgrpid","name","users_status"],"selectMedias":["mediatypeid","severity","active"]}' > "$OUT/user9.json"
echo; echo "== usuario 9 ahora (rol | grupos de usuarios [habilitado 0=si] | medios tipo:severidades:active)"
jq -r '.[]|[.roleid,([.usrgrps[]|"\(.name)[\(.users_status)]"]|join(",")),([.medias[]|"\(.mediatypeid):\(.severity):\(.active)"]|join(" "))]|@tsv' "$OUT/user9.json"
echo listo

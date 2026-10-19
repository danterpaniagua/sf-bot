#!/usr/bin/env bash
# Event: 20261014_gitin2222-ecs-reinicios-avisos-sns
# C24 - SOLO LECTURA contra la API de Zabbix (6.0.32; token en $ZABBIX_API_KEY).
#       C23: el evento de las 06:20 (-03:00) del trigger 26915 (prioridad Warning) tenia las etiquetas correctas para la accion 11 y NO genero ninguna notificacion; en cambio el trigger
#       "Graylog: Platform FATAL detected" (High) del mismo dia si llego (aviso de recuperacion 12:33-12:38). Hipotesis (no verificada): el usuario destinatario de la accion 11
#       recibe solo ciertas severidades (filtro de severidad del medio) o tiene un horario activo que excluyo el evento. Este script lee, SIN destinatarios ni claves:
#         a) la accion 11: estado, filtro, operaciones (usuarios/grupos, tipo de medio), periodo de escalado, pausa en mantenimiento
#         b) para cada usuario de esas operaciones: sus medios (tipo, severidades marcadas, periodo activo, estado) -- sin el campo sendto
#         c) la prioridad (severidad) de los triggers 26915/26916 y 26919/26920
#         d) las notificaciones (alert.get) generadas por el evento del Graylog FATAL de las 12:33 (hora -03:00): accion, tipo de medio, estado
#       Salidas en data/c24/.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/data/c24"
mkdir -p "$OUT"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
call action.get '{"actionids":["7","11"],"output":["actionid","name","status","esc_period","pause_suppressed","notify_if_canceled"],"selectFilter":"extend","selectOperations":"extend","selectRecoveryOperations":"extend"}' > "$OUT/actions.json"
echo "== acciones 7 y 11 (id | nombre | status 0=activa | pausa en mantenimiento | formula)"
jq -r '.[]|[.actionid,.name,.status,.pause_suppressed,(.filter.formula // "")]|@tsv' "$OUT/actions.json"
echo "== operaciones (accion | tipo | usuarios | grupos | tipo de medio | pasos)"
jq -r '.[]|.actionid as $a|.operations[]|[$a,.operationtype,([.opmessage_usr[]?.userid]|join(",")),([.opmessage_grp[]?.usrgrpid]|join(",")),(.opmessage.mediatypeid // ""),"\(.esc_step_from)-\(.esc_step_to)"]|@tsv' "$OUT/actions.json"
UIDS=$(jq -c '[.[].operations[]?.opmessage_usr[]?.userid]|unique' "$OUT/actions.json")
GIDS=$(jq -c '[.[].operations[]?.opmessage_grp[]?.usrgrpid]|unique' "$OUT/actions.json")
call user.get "$(jq -n --argjson u "$UIDS" --argjson g "$GIDS" '{userids:$u,output:["userid","username","roleid"],selectMedias:["mediatypeid","severity","period","active"],selectUsrgrps:["usrgrpid","name"]}')" > "$OUT/users.json"
echo; echo "== usuarios destinatarios y sus medios (userid | tipo de medio | severidades [bits: 1 sin clasificar,2 info,4 warning,8 average,16 high,32 disaster; 63=todas] | periodo | active 0=habilitado)"
jq -r '.[]|.userid as $u|(.medias[]|[$u,.mediatypeid,.severity,.period,.active])|@tsv' "$OUT/users.json"
if [ "$GIDS" != "[]" ]; then call user.get "$(jq -n --argjson g "$GIDS" '{usrgrpids:$g,output:["userid","username"],selectMedias:["mediatypeid","severity","period","active"]}')" > "$OUT/group-users.json"; echo "== usuarios de los grupos destinatarios"; jq -r '.[]|.userid as $u|(.medias[]|[$u,.mediatypeid,.severity,.period,.active])|@tsv' "$OUT/group-users.json"; fi
call trigger.get '{"triggerids":["26915","26916","26919","26920"],"output":["triggerid","description","priority"]}' > "$OUT/trigger-priorities.json"
echo; echo "== prioridad de los triggers (0 sin clasificar,1 info,2 warning,3 average,4 high,5 disaster)"; jq -r '.[]|[.triggerid,.description,.priority]|@tsv' "$OUT/trigger-priorities.json"
FROM=$(date -u -d "2026-10-15 15:30:00" +%s); TO=$(date -u -d "2026-10-15 15:45:00" +%s)
call event.get "$(jq -n --argjson f "$FROM" --argjson t "$TO" '{time_from:$f,time_till:$t,source:0,object:0,output:["eventid","objectid","clock","value","name"],sortfield:["clock"],sortorder:"ASC"}')" > "$OUT/events-1530-1545.json"
EIDS=$(jq -c '[.[]|select(.name|test("Graylog: Platform FATAL"))|.eventid]' "$OUT/events-1530-1545.json")
call alert.get "$(jq -n --argjson e "$EIDS" '{eventids:$e,output:["alertid","eventid","actionid","mediatypeid","userid","status","retries","error","clock"],sortfield:["clock"],sortorder:"ASC"}')" > "$OUT/alerts-fatal.json"
echo; echo "== notificaciones del evento Graylog FATAL (12:33-12:38 -03:00 = 15:33-15:38 UTC): hora -03:00 | evento | accion | medio | usuario | status | error"
jq -r '.[]|[((.clock|tonumber)-10800|strftime("%H:%M:%S")),.eventid,.actionid,.mediatypeid,.userid,.status,.error]|@tsv' "$OUT/alerts-fatal.json"
echo listo

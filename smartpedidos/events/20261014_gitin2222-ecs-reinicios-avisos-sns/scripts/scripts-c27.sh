#!/usr/bin/env bash
# Event: 20261014_gitin2222-ecs-reinicios-avisos-sns
# C27 - SOLO LECTURA contra la API de Zabbix (sf-monitoreo.smartfran.com:8080, 6.0.32; token en $ZABBIX_API_KEY).
#       Pedido del usuario: "get live delivery config". Lee la configuracion VIVA de entrega de notificaciones, sin destinatarios, claves ni parametros de los tipos de medio:
#         1) todas las acciones de triggers: estado, filtro (condiciones), operaciones (usuarios, grupos, tipo de medio), recuperacion/actualizacion, pausa en mantenimiento
#         2) tipos de medio: id, nombre, tipo, estado (sin parametros ni scripts)
#         3) usuarios destinatarios (de las operaciones y de los grupos de usuarios destinatarios): rol, grupos de usuarios y medios (tipo, severidades, periodo, estado; SIN sendto ni nombres)
#         4) permisos de esos usuarios sobre los grupos de hosts, y lectura EFECTIVA de cada destinatario sobre los hosts relevantes (denegar gana; sin permiso = ninguno)
#         5) notificaciones de las ultimas 24 h por accion y estado, errores distintos (recortados) y, por trigger de interes, eventos de problema vs notificaciones generadas
#       Salidas en data/c27/ (JSON) y un resumen legible por stdout.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/data/c27"
mkdir -p "$OUT"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
echo "== $(date -u +%FT%TZ)"
# 1) acciones
call action.get '{"filter":{"eventsource":"0"},"output":["actionid","name","status","esc_period","pause_suppressed","notify_if_canceled"],"selectFilter":"extend","selectOperations":"extend","selectRecoveryOperations":"extend","selectUpdateOperations":"extend"}' > "$OUT/actions.json"
echo; echo "== 1) acciones de triggers (id | nombre | status 0=activa | pausa en mantenimiento | formula | condiciones [tipo:operador:valor2=valor])"
jq -r '.[]|[.actionid,.name,.status,.pause_suppressed,(.filter.formula // .filter.evaltype),([.filter.conditions[]?|"\(.conditiontype):\(.operator):\(.value2)=\(.value)"]|join(" ; "))]|@tsv' "$OUT/actions.json"
echo "-- operaciones de problema (accion | usuarios | grupos de usuarios | tipo de medio | pasos) / recuperacion / actualizacion (cantidad)"
jq -r '.[]|.actionid as $a|[$a,([.operations[]?|"u:"+([.opmessage_usr[]?.userid]|join(","))+" g:"+([.opmessage_grp[]?.usrgrpid]|join(","))+" m:"+(.opmessage.mediatypeid // "?")+" s:"+(.esc_step_from+"-"+.esc_step_to)]|join(" | ")),("recup="+([.recovery_operations[]?]|length|tostring)),("act="+([.update_operations[]?]|length|tostring))]|@tsv' "$OUT/actions.json"
# 2) tipos de medio
call mediatype.get '{"output":["mediatypeid","name","type","status","maxattempts"]}' > "$OUT/mediatypes.json"
echo; echo "== 2) tipos de medio (id | nombre | tipo 0=email 1=script 4=webhook | status 0=habilitado | intentos)"
jq -r '.[]|[.mediatypeid,.name,.type,.status,.maxattempts]|@tsv' "$OUT/mediatypes.json"
# 3) destinatarios
UIDS=$(jq -c '[.[].operations[]?.opmessage_usr[]?.userid]|unique' "$OUT/actions.json")
GIDS=$(jq -c '[.[].operations[]?.opmessage_grp[]?.usrgrpid]|unique' "$OUT/actions.json")
call user.get "$(jq -n --argjson u "$UIDS" '{userids:$u,output:["userid","roleid"],selectMedias:["mediatypeid","severity","period","active"],selectUsrgrps:["usrgrpid","name","users_status"]}')" > "$OUT/users-direct.json"
if [ "$GIDS" != "[]" ]; then call user.get "$(jq -n --argjson g "$GIDS" '{usrgrpids:$g,output:["userid","roleid"],selectMedias:["mediatypeid","severity","period","active"],selectUsrgrps:["usrgrpid","name","users_status"]}')" > "$OUT/users-groups.json"; else echo '[]' > "$OUT/users-groups.json"; fi
jq -s 'add|unique_by(.userid)' "$OUT/users-direct.json" "$OUT/users-groups.json" > "$OUT/recipients.json"
call role.get "$(jq -n --argjson r "$(jq -c '[.[].roleid]|unique' "$OUT/recipients.json")" '{roleids:$r,output:["roleid","name","type"]}')" > "$OUT/roles.json"
echo; echo "== 3) destinatarios (userid | rol | grupos de usuarios | medios [tipo:severidades:periodo:active 0=habilitado])"
jq -r --slurpfile r "$OUT/roles.json" '.[] | . as $u | [$u.userid, ($r[0]|map(select(.roleid==$u.roleid))|.[0]|"\(.name) (tipo \(.type))"), ([$u.usrgrps[]|.name]|join(",")), ([$u.medias[]|"\(.mediatypeid):\(.severity):\(.period):\(.active)"]|join(" "))] | @tsv' "$OUT/recipients.json"
# 4) permisos
UGIDS=$(jq -c '[.[].usrgrps[].usrgrpid]|unique' "$OUT/recipients.json")
call usergroup.get "$(jq -n --argjson g "$UGIDS" '{usrgrpids:$g,output:["usrgrpid","name","users_status"],selectRights:["id","permission"]}')" > "$OUT/usergroups.json"
call hostgroup.get '{"output":["groupid","name"]}' > "$OUT/hostgroups.json"
call host.get '{"hostids":["10666","10667","10668","10084","10610","10659","10660","10665","10678"],"output":["hostid","host"],"selectGroups":["groupid","name"]}' > "$OUT/hosts.json"
echo; echo "== 4) permisos de los grupos de usuarios destinatarios (grupo de usuarios | habilitado 0=si | grupo de hosts | permiso 0=denegado 2=lectura 3=lectura-escritura)"
jq -r --slurpfile h "$OUT/hostgroups.json" '.[]|.name as $n|.users_status as $s|(.rights[]?)|. as $r|[$n,$s,($h[0][]|select(.groupid==$r.id)|.name),$r.permission]|@tsv' "$OUT/usergroups.json"
echo; echo "== lectura EFECTIVA (usuario | host | permiso; 'ninguno' = no puede leer el host, por lo que no recibe notificaciones de el)"
jq -r --slurpfile ug "$OUT/usergroups.json" --slurpfile hs "$OUT/hosts.json" '.[]|. as $u|($u.usrgrps|map(.usrgrpid)) as $mine|$hs[0][]|. as $h|([.groups[].groupid]) as $gs|[$ug[0][]|select(.usrgrpid as $i|$mine|index($i))|.rights[]?|select(.id as $i|$gs|index($i))|.permission|tonumber] as $p|[$u.userid,$h.host,(if ($p|length)==0 then "ninguno" elif ($p|index(0)) != null then "0 (denegado)" else ($p|max|tostring) end)]|@tsv' "$OUT/recipients.json"
# 5) notificaciones
FROM=$(( $(date +%s) - 24*3600 ))
call alert.get "$(jq -n --argjson f "$FROM" '{time_from:$f,output:["alertid","eventid","actionid","mediatypeid","userid","status","retries","error","clock"]}')" > "$OUT/alerts-24h.json"
echo; echo "== 5) notificaciones de las ultimas 24 h: total $(jq length "$OUT/alerts-24h.json")  (accion | tipo de medio | status 0=pendiente 1=enviada 2=fallida | cantidad)"
jq -r 'group_by([.actionid,.mediatypeid,.status])[]|[.[0].actionid,.[0].mediatypeid,.[0].status,length]|@tsv' "$OUT/alerts-24h.json"
echo "-- errores distintos (cantidad | texto recortado a 120 caracteres)"; jq -r '[.[]|select(.error!="")|.error[0:120]]|group_by(.)[]|[length,.[0]]|@tsv' "$OUT/alerts-24h.json"
TRIG='["26915","26916","26919","26920","26921","26922","26923","26924","26925","26926","26927","26928"]'
call event.get "$(jq -n --argjson t "$TRIG" --argjson f "$FROM" '{objectids:$t,time_from:$f,source:0,object:0,value:"1",output:["eventid","objectid","clock"]}')" > "$OUT/problem-events-24h.json"
call alert.get "$(jq -n --argjson e "$(jq -c '[.[].eventid]' "$OUT/problem-events-24h.json")" '{eventids:$e,output:["eventid","actionid","status"]}')" > "$OUT/alerts-of-events.json"
call trigger.get "$(jq -n --argjson t "$TRIG" '{triggerids:$t,output:["triggerid","description","priority"]}')" > "$OUT/triggers.json"
echo; echo "== eventos de PROBLEMA de los triggers de interes (24 h) vs notificaciones generadas (trigger | prioridad | descripcion | eventos | con notificacion)"
jq -r --slurpfile ev "$OUT/problem-events-24h.json" --slurpfile al "$OUT/alerts-of-events.json" '.[]|. as $t|([$ev[0][]|select(.objectid==$t.triggerid)]) as $e|[$t.triggerid,$t.priority,$t.description[0:70],($e|length),([$e[]|select(.eventid as $i|$al[0]|map(.eventid)|index($i))]|length)]|@tsv' "$OUT/triggers.json"
echo listo

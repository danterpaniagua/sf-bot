#!/usr/bin/env bash
# Event: 20261014_gitin2222-ecs-reinicios-avisos-sns
# C26 - SOLO LECTURA contra la API de Zabbix (6.0.32; token en $ZABBIX_API_KEY).
#       C25: los 18 eventos del trigger 26915 (9 PROBLEMA/OK, 2026-10-14 22:50 a 2026-10-15 06:30 -03:00) NO estaban suprimidos y generaron 0 notificaciones, mientras que
#       el trigger Graylog FATAL (host "Zabbix server") si notifico por la misma accion 11 al mismo usuario (9). Hipotesis (no verificada): Zabbix solo notifica a un usuario por eventos de hosts
#       sobre los que tiene al menos permiso de lectura, y el usuario 9 (rol 4; grupos Guests y loyalty-read) no tiene permiso sobre el grupo de hosts de los hosts descubiertos de AWS.
#       Lee: el rol del usuario 9, los permisos de sus grupos de usuarios sobre grupos de hosts, y los grupos de hosts de 10666 (smartfran-pedidos-production) y 10084 (Zabbix server).
#       Salidas en data/c26/.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/data/c26"
mkdir -p "$OUT"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
call user.get '{"userids":["9"],"output":["userid","roleid"],"selectUsrgrps":["usrgrpid","name"]}' > "$OUT/user9.json"
RID=$(jq -r '.[0].roleid' "$OUT/user9.json")
call role.get "$(jq -n --arg r "$RID" '{roleids:[$r],output:["roleid","name","type"]}')" > "$OUT/role.json"
echo "== usuario 9: rol (id | nombre | tipo 1=usuario 2=admin 3=super admin)"; jq -r '.[]|[.roleid,.name,.type]|@tsv' "$OUT/role.json"
GIDS=$(jq -c '[.[0].usrgrps[].usrgrpid]' "$OUT/user9.json")
call usergroup.get "$(jq -n --argjson g "$GIDS" '{usrgrpids:$g,output:["usrgrpid","name","users_status","gui_access"],selectRights:["id","permission"]}')" > "$OUT/usergroups.json"
call host.get '{"hostids":["10666","10084"],"output":["hostid","name"],"selectGroups":["groupid","name"]}' > "$OUT/host-groups.json"
echo; echo "== grupos de hosts de los hosts relevantes (host | grupo)"
jq -r '.[]|.name as $n|.groups[]|[$n,"\(.groupid) \(.name)"]|@tsv' "$OUT/host-groups.json"
call hostgroup.get '{"output":["groupid","name"]}' > "$OUT/hostgroups-all.json"
echo; echo "== permisos de los grupos de usuarios de la persona sobre grupos de hosts (grupo de usuarios | habilitado 0=si | grupo de hosts | permiso 0=denegado 2=lectura 3=lectura-escritura)"
jq -r --slurpfile h "$OUT/hostgroups-all.json" '.[]|.name as $u|.users_status as $s|.rights[]|. as $r|[$u,$s,($h[0][]|select(.groupid==$r.id)|.name),$r.permission]|@tsv' "$OUT/usergroups.json"
echo; echo "== lectura por host (host | permiso efectivo segun los grupos de hosts y de usuarios; 0 o ninguno = sin lectura)"
jq -r --slurpfile ug "$OUT/usergroups.json" '.[]|.name as $n|[.groups[].groupid] as $gs|[$ug[0][].rights[]|select(.id as $i|$gs|index($i))|.permission|tonumber]|[$n,(if length==0 then "ninguno" elif (index(0)) then "0 (denegado)" else max end)]|@tsv' "$OUT/host-groups.json"
echo listo

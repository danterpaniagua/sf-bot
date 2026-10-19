#!/usr/bin/env bash
# Event: 20261014_gitin2222-ecs-reinicios-avisos-sns
# C38 - SOLO LECTURA contra la API de Zabbix (6.0.32; token en $ZABBIX_API_KEY).
#       C37 (auditoria): el unico cambio sobre el destinatario entre la ultima entrega correcta (18:00:09 UTC) y el primer evento sin aviso (19:04:08) es del usuario 9 (cuenta de servicio del Chat):
#       a las 18:08:49 UTC se le agrego el grupo de usuarios id 14. Este script lee la configuracion COMPLETA de los grupos de usuarios del usuario 9 (8, 14 y 15): estado, acceso al frontend,
#       permisos sobre grupos de hosts y, sobre todo, los FILTROS DE ETIQUETAS (tag filters) de cada grupo: en Zabbix 6.0 un grupo puede limitar los problemas visibles para sus miembros a ciertas etiquetas, y las
#       notificaciones solo se envian por problemas que el usuario puede ver. Sin nombres de personas ni claves. Salidas en data/c38/.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/data/c38"
mkdir -p "$OUT"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
call user.get '{"userids":["9"],"output":["userid","roleid"],"selectUsrgrps":["usrgrpid","name"]}' > "$OUT/user9.json"
echo "== usuario 9: rol y grupos (id nombre)"; jq -r '.[]|[.roleid,([.usrgrps[]|"\(.usrgrpid) \(.name)"]|join(" | "))]|@tsv' "$OUT/user9.json"
call usergroup.get '{"usrgrpids":["8","14","15"],"output":"extend","selectRights":["id","permission"],"selectTagFilters":["groupid","tag","value"],"selectUsers":["userid"]}' > "$OUT/usergroups.json"
call hostgroup.get '{"output":["groupid","name"]}' > "$OUT/hostgroups.json"
echo; echo "== grupos de usuarios (id | nombre | estado 0=habilitado | acceso al frontend 0=sistema 1=interno 2=LDAP 3=deshabilitado | modo debug | miembros)"
jq -r '.[]|[.usrgrpid,.name,.users_status,.gui_access,.debug_mode,(.users|length)]|@tsv' "$OUT/usergroups.json"
echo; echo "== permisos sobre grupos de hosts (grupo de usuarios | grupo de hosts | permiso 0=denegado 2=lectura 3=lectura-escritura)"
jq -r --slurpfile h "$OUT/hostgroups.json" '.[]|.name as $n|(.rights[]?)|. as $r|[$n,($h[0][]|select(.groupid==$r.id)|.name),$r.permission]|@tsv' "$OUT/usergroups.json"
echo; echo "== FILTROS DE ETIQUETAS (grupo de usuarios | grupo de hosts | etiqueta | valor); vacio = sin filtros"
jq -r --slurpfile h "$OUT/hostgroups.json" '.[]|.name as $n|(.tag_filters[]?)|. as $f|[$n,($h[0][]|select(.groupid==$f.groupid)|.name),$f.tag,$f.value]|@tsv' "$OUT/usergroups.json"
echo listo

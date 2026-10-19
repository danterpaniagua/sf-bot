#!/usr/bin/env bash
# Event: 20261015_env-prod-notificar-operaciones
# C3 - Zabbix 6.0.32 (sf-monitoreo.smartfran.com:8080; token en $ZABBIX_API_KEY). Grupo de usuarios para ope_notify SIN filtros de etiquetas.
#      Motivo (C2): ope_notify (userid 16) esta en los grupos 14 pedidos-read (5 filtros de etiqueta sobre el grupo de hosts 4) y 15 loyalty-read, los mismos que tenia el usuario 9
#      cuando dejaron de generarse notificaciones (hipotesis, GITIN-2222/2239). Se crea el grupo "ope-notify-read" con lectura (2) sobre los grupos de hosts 4, 30 y 37 (los mismos que dan
#      acceso hoy a los 15 hosts con env=PROD) y SIN filtros, y se mueve a ope_notify a ese unico grupo. No toca los grupos 14 ni 15 ni a otros usuarios.
#      Modos: dry (por defecto, SOLO LECTURA) | apply (CAMBIA ESTADO) | rollback <carpeta c3-run-...> (CAMBIA ESTADO: devuelve a ope_notify a 14 y 15 y borra el grupo creado)
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
MODE="${1:-dry}"; SNAP="${2:-}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/operations/events/20261015_env-prod-notificar-operaciones/data"
NAME="ope-notify-read"
TS=$(date -u +%Y%m%dT%H%M%SZ); RUN="$OUT/c3-run-$TS"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
if [ "$MODE" = "rollback" ]; then
  [ -f "$SNAP/after.json" ] || { echo "uso: $0 rollback <carpeta c3-run-...>"; exit 1; }
  NEW=$(jq -r '.newgroup' "$SNAP/after.json")
  echo "ope_notify -> grupos 14 y 15:"; call user.update '{"userid":"16","usrgrps":[{"usrgrpid":"14"},{"usrgrpid":"15"}]}' | jq -c .
  echo "borrar grupo $NEW:"; call usergroup.delete "[\"$NEW\"]" | jq -c .
  echo "rollback hecho"; exit 0
fi
mkdir -p "$RUN"; echo "modo=$MODE | $TS | carpeta $RUN"
call user.get '{"userids":["16"],"output":["userid","username"],"selectUsrgrps":["usrgrpid","name"]}' > "$RUN/before-user.json"
call usergroup.get "$(jq -nc --arg n "$NAME" '{filter:{name:[$n]},output:["usrgrpid","name"]}')" > "$RUN/before-group-exists.json"
jq -e '.[0].username=="ope_notify" and ([.[0].usrgrps[].usrgrpid]|sort)==["14","15"]' "$RUN/before-user.json" >/dev/null || { echo "GUARDA: ope_notify (16) no esta exactamente en los grupos 14 y 15"; exit 1; }
jq -e 'length==0' "$RUN/before-group-exists.json" >/dev/null || { echo "GUARDA: ya existe un grupo llamado $NAME"; exit 1; }
echo "plan: crear grupo $NAME (lectura sobre grupos de hosts 4, 30, 37; sin filtros de etiquetas) y mover a ope_notify (16) de [14,15] a [$NAME]"
[ "$MODE" = "apply" ] || { echo "DRY: no se cambio nada. Para aplicar: $0 apply"; exit 0; }
NEW=$(call usergroup.create "$(jq -nc --arg n "$NAME" '{name:$n,rights:[{id:"4",permission:2},{id:"30",permission:2},{id:"37",permission:2}]}')" | jq -r '.usrgrpids[0]')
echo "grupo creado: $NEW"; jq -n --arg g "$NEW" '{newgroup:$g}' > "$RUN/after.json"
call user.update "$(jq -nc --arg g "$NEW" '{userid:"16",usrgrps:[{usrgrpid:$g}]}')" | jq -c .
call usergroup.get "$(jq -nc --arg g "$NEW" '{usrgrpids:[$g],output:["usrgrpid","name"],selectRights:["id","permission"],selectTagFilters:["groupid","tag","value"],selectUsers:["username"]}')" > "$RUN/after-group.json"
call user.get '{"userids":["16"],"output":["username"],"selectUsrgrps":["usrgrpid","name"]}' > "$RUN/after-user.json"
echo "== despues"; jq -c '.[]|{usrgrpid,name,rights,tag_filters,users}' "$RUN/after-group.json"; jq -c '.[]|{username,grupos:[.usrgrps[].name]}' "$RUN/after-user.json"
echo "aplicado. Rollback: $0 rollback $RUN"

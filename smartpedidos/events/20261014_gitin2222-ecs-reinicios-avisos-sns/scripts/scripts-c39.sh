#!/usr/bin/env bash
# Event: 20261014_gitin2222-ecs-reinicios-avisos-sns
# C39 - Zabbix 6.0.32 (token en $ZABBIX_API_KEY). PRUEBA A/B de la hipotesis del grupo de usuarios: el usuario 9 (cuenta de servicio del Chat de Operaciones) fue agregado a las 18:08:49 UTC al grupo 14 "pedidos-read",
#      que tiene FILTROS DE ETIQUETAS sobre el grupo de hosts "Zabbix servers" (cloud=AWS, cloud=Mongo Atlas, clud=AWS, component=SmartPedidos, component=Amazon Simple Queue Service; C38). Las etiquetas de nuestras alertas
#      (scope, action, service, check...) no estan en esa lista. Las notificaciones solo se envian por problemas que el usuario puede ver. Desde la agregacion no hubo notificaciones (C35).
#      Esta prueba QUITA al usuario 9 del grupo 14 (queda en Guests y loyalty-read, como a las 18:00 cuando entregaba) para generar un evento de prueba (scripts-c7.sh on) y ver si llega la notificacion; luego se RESTAURA el grupo.
#      Mientras el usuario 9 no este en el grupo 14, NO tiene lectura sobre los hosts de AWS (smartfran-pedidos-*): la prueba solo sirve para los triggers de Zabbix server y sfcg-monitoreo (FATAL y healthchecks), no para el ECS.
#      user.update REEMPLAZA la lista de grupos: se lee la lista actual y el modo off la reenvia tal cual estaba. Efecto lateral: durante la prueba el usuario 9 deja de ver lo que ve por ese grupo.
#      Modos: dry (por defecto, SOLO LECTURA) | on (CAMBIA ESTADO: quita el grupo 14) | off <carpeta c39-run-...> (CAMBIA ESTADO: restaura los grupos originales)
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
MODE="${1:-dry}"; SNAP="${2:-}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/data"
TS=$(date -u +%Y%m%dT%H%M%SZ); RUN="$OUT/c39-run-$TS"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
show() { call user.get '{"userids":["9"],"output":["userid"],"selectUsrgrps":["usrgrpid","name"]}' | jq -r '.[0].usrgrps|map("\(.usrgrpid) \(.name)")|join(" | ")'; }
if [ "$MODE" = "off" ]; then
  [ -f "$SNAP/before-user.json" ] || { echo "uso: $0 off <carpeta c39-run-...>"; exit 1; }
  call user.update "$(jq -c '{userid:"9",usrgrps:[.[0].usrgrps[]|{usrgrpid:.usrgrpid}]}' "$SNAP/before-user.json")" >/dev/null
  echo "grupos restaurados: $(show)"; exit 0
fi
mkdir -p "$RUN"; echo "modo=$MODE | $TS | carpeta $RUN"
call user.get '{"userids":["9"],"output":["userid","roleid"],"selectUsrgrps":["usrgrpid","name"]}' > "$RUN/before-user.json"
jq -e '.[0].usrgrps|map(.usrgrpid)|sort==["14","15","8"]' "$RUN/before-user.json" >/dev/null || { echo "GUARDA: los grupos del usuario 9 no son 8, 14 y 15"; jq -c '.[0].usrgrps' "$RUN/before-user.json"; exit 1; }
echo "== grupos actuales del usuario 9: $(show)"; echo "== tras 'on': 8 Guests | 15 loyalty-read (sin 14 pedidos-read)"
if [ "$MODE" != "on" ]; then echo "DRY: no se cambio nada. Para quitar el grupo 14: $0 on"; exit 0; fi
call user.update '{"userid":"9","usrgrps":[{"usrgrpid":"8"},{"usrgrpid":"15"}]}' >/dev/null
echo "grupos ahora: $(show)"; echo "SIGUIENTE: generar un evento de prueba (scripts-c7.sh on de GITIN-2239), mirar el Chat y restaurar con: $0 off $RUN"

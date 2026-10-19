#!/usr/bin/env bash
# Event: 20261014_gitin2222-ecs-reinicios-avisos-sns
# C28 - Zabbix 6.0.32 (sf-monitoreo.smartfran.com:8080; token en $ZABBIX_API_KEY). Da LECTURA sobre el grupo de hosts "Templates/Cloud" (id 19) al grupo de usuarios "pedidos-read".
#       Motivo (C27): el usuario 9, unico destinatario de las acciones 7 y 11, pertenece ahora a "pedidos-read" (con lectura sobre PEDIDOS y Zabbix servers) pero los hosts descubiertos de AWS
#       (smartfran-pedidos-production/-common/-dev) estan solo en "Templates/Cloud": su lectura efectiva sobre esos hosts sigue siendo "ninguno" y los 9 eventos del trigger de ECS generaron 0 notificaciones.
#       usergroup.update REEMPLAZA la lista de permisos: se lee la lista actual y se le agrega {id:19, permission:2}; el rollback reenvia la lista original guardada.
#       Efecto colateral a tener presente: la lectura sobre ese grupo tambien muestra a los miembros de pedidos-read las plantillas de ese grupo y los 3 hosts descubiertos.
#       Modos: dry (por defecto, SOLO LECTURA) | apply (CAMBIA ESTADO) | rollback <carpeta c28-run-...> (CAMBIA ESTADO)
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
MODE="${1:-dry}"; SNAP="${2:-}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/data"
TS=$(date -u +%Y%m%dT%H%M%SZ); RUN="$OUT/c28-run-$TS"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
if [ "$MODE" = "rollback" ]; then
  [ -f "$SNAP/before.json" ] || { echo "uso: $0 rollback <carpeta c28-run-...>"; exit 1; }
  call usergroup.update "$(jq -c '{usrgrpid:.[0].usrgrpid,rights:.[0].rights}' "$SNAP/before.json")" >/dev/null; echo "permisos restaurados desde $SNAP"; exit 0
fi
mkdir -p "$RUN"; echo "modo=$MODE | $TS | carpeta $RUN"
call usergroup.get '{"filter":{"name":["pedidos-read"]},"output":["usrgrpid","name","users_status"],"selectRights":["id","permission"],"selectUsers":["userid"]}' > "$RUN/before.json"
jq -e 'length==1 and .[0].users_status=="0"' "$RUN/before.json" >/dev/null || { echo "GUARDA: no existe exactamente un grupo 'pedidos-read' habilitado"; exit 1; }
call hostgroup.get '{"groupids":["19"],"output":["groupid","name"]}' > "$RUN/hostgroup19.json"
jq -e '.[0].name=="Templates/Cloud"' "$RUN/hostgroup19.json" >/dev/null || { echo "GUARDA: el grupo de hosts 19 no es 'Templates/Cloud'"; exit 1; }
jq -e '[.[0].rights[]|select(.id=="19")]|length==0' "$RUN/before.json" >/dev/null || { echo "AVISO: pedidos-read ya tiene un permiso sobre el grupo 19; no se cambia nada"; jq -c '.[0].rights' "$RUN/before.json"; exit 0; }
echo "== grupo pedidos-read (id $(jq -r '.[0].usrgrpid' "$RUN/before.json")), miembros: $(jq '.[0].users|length' "$RUN/before.json"); permisos actuales: $(jq -c '[.[0].rights[]|"\(.id):\(.permission)"]' "$RUN/before.json")"
NEW=$(jq -c '.[0].rights + [{id:"19",permission:"2"}]' "$RUN/before.json"); echo "== permisos tras el cambio: $(jq -c '[.[]|"\(.id):\(.permission)"]' <<<"$NEW")"
if [ "$MODE" != "apply" ]; then echo "DRY: no se cambio nada. Para aplicar: $0 apply"; exit 0; fi
call usergroup.update "$(jq -nc --arg g "$(jq -r '.[0].usrgrpid' "$RUN/before.json")" --argjson r "$NEW" '{usrgrpid:$g,rights:$r}')" >/dev/null
call usergroup.get '{"filter":{"name":["pedidos-read"]},"output":["usrgrpid","name"],"selectRights":["id","permission"]}' > "$RUN/after.json"
jq -c '.[0].rights' "$RUN/after.json"
echo "aplicado. Rollback: $0 rollback $RUN"

#!/usr/bin/env bash
# Event: 20261014_gitin2222-ecs-reinicios-avisos-sns
# C17 - Zabbix 6.0.32 (sf-monitoreo.smartfran.com:8080), token en $ZABBIX_API_KEY dentro del cuerpo JSON (nunca literal).
#       Pedido del usuario: la alerta "Running tasks below desired" solo en smartfran-pedidos-production. Lectura C14 (data/c14-run-log-20261015T015322Z.txt):
#         10084 Zabbix server (manual) y 10668 smartfran-pedidos-dev (descubierto) tienen la misma plantilla ECS; 10666 smartfran-pedidos-production ya tiene sus 21 macros (no falta ninguna).
#       Cambio: agrega la macro de host {$AWS.ECS.CLUSTER.SERVICE.RUNNING.DIP} = 1000 en 10084 y en 10668 -> en esos hosts Running < Desired - 1000 nunca se cumple y el trigger no dispara.
#       No desvincula plantillas ni borra items. 10666 NO se toca (usa el valor 0.05 de la plantilla).
#       Incierto: si Zabbix acepta macros de host en un host DESCUBIERTO (10668); cada host se intenta por separado y un rechazo se informa sin detener el resto.
#       Modos:  payload (SOLO LECTURA, sin API) | dry (SOLO LECTURA, por defecto: guardas) | apply (CAMBIA ESTADO) | rollback <carpeta c17-run-...> (CAMBIA ESTADO: borra las macros creadas)
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
MODE="${1:-dry}"; SNAP="${2:-}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/data"
TS=$(date -u +%Y%m%dT%H%M%SZ); RUN="$OUT/c17-run-$TS"
MACRO='{$AWS.ECS.CLUSTER.SERVICE.RUNNING.DIP}'; VALUE='1000'
HOSTS='10084:Zabbix server 10668:smartfran-pedidos-dev'
payload() { jq -nc --arg h "$1" --arg m "$MACRO" --arg v "$VALUE" '{hostid:$h, macro:$m, value:$v, description:"Desactiva el trigger Running tasks below desired en este host: solo smartfran-pedidos-production alerta (GITIN-2222)"}'; }
if [ "$MODE" = "payload" ]; then for H in $HOSTS; do :; done; payload 10084; payload 10668; exit 0; fi

: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }

if [ "$MODE" = "rollback" ]; then
  [ -f "$SNAP/created-ids.json" ] || { echo "uso: $0 rollback <carpeta c17-run-...> (falta created-ids.json)"; exit 1; }
  for ROW in $(jq -r '.[] | select(.hostmacroid!=null) | "\(.hostid):\(.hostmacroid)"' "$SNAP/created-ids.json"); do
    HID=${ROW%%:*}; MID=${ROW##*:}
    call usermacro.get "$(jq -n --arg m "$MID" '{hostmacroids:[$m],output:["macro","hostid"]}')" | jq -e --arg m "$MACRO" --arg h "$HID" '.[0].macro==$m and .[0].hostid==$h' >/dev/null || { echo "GUARDA: la macro $MID no es la esperada en el host $HID"; continue; }
    call usermacro.delete "[\"$MID\"]" >/dev/null && echo "macro $MID borrada del host $HID"
  done
  echo "rollback aplicado desde $SNAP"; exit 0
fi

echo "version de la API: $(jq -n '{jsonrpc:"2.0",method:"apiinfo.version",params:[],id:1}' | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq -r .result) | modo=$MODE | $TS"
mkdir -p "$RUN"
# --- guardas: el host existe con ese nombre, tiene la plantilla ECS y no tiene ya la macro; 10666 no se toca
for ENTRY in 10084:"Zabbix server" 10668:"smartfran-pedidos-dev"; do
  HID=${ENTRY%%:*}; HN=${ENTRY#*:}
  call host.get "$(jq -n --arg h "$HID" '{hostids:[$h],output:["hostid","name","flags"],selectParentTemplates:["name"],selectMacros:["macro"]}')" > "$RUN/before-host-$HID.json"
  jq -e --arg n "$HN" '.[0].name==$n and (.[0].parentTemplates|map(.name)|index("AWS ECS Serverless Cluster by HTTP")!=null)' "$RUN/before-host-$HID.json" >/dev/null || { echo "GUARDA: el host $HID no es '$HN' o no tiene la plantilla ECS"; exit 1; }
  jq -e --arg m "$MACRO" '.[0].macros|map(.macro)|index($m)==null' "$RUN/before-host-$HID.json" >/dev/null || { echo "GUARDA: el host $HID ya tiene la macro $MACRO"; exit 1; }
  echo "host $HID '$HN': guardas OK ($(jq -r 'if .[0].flags=="4" then "descubierto" else "manual" end' "$RUN/before-host-$HID.json"))"
done
echo "== cargas"; payload 10084; payload 10668
echo "snapshot en $RUN"
if [ "$MODE" != "apply" ]; then echo "DRY: no se cambio nada. Para aplicar: $0 apply"; exit 0; fi

# --- apply: cada host por separado; un rechazo no detiene el resto
echo '[]' > "$RUN/created-ids.json"
for HID in 10084 10668; do
  if R=$(call usermacro.create "$(payload "$HID")" 2>"$RUN/err-$HID.txt"); then
    MID=$(echo "$R" | jq -r '.hostmacroids[0]'); jq --arg h "$HID" --arg m "$MID" '. + [{hostid:$h, hostmacroid:$m}]' "$RUN/created-ids.json" > "$RUN/created-ids.tmp" && mv "$RUN/created-ids.tmp" "$RUN/created-ids.json"
    echo "OK host $HID: macro $MID creada"
  else
    echo "RECHAZADO host $HID: $(cut -c1-300 "$RUN/err-$HID.txt")"
  fi
done
echo "== despues"
for HID in 10084 10668; do call usermacro.get "$(jq -n --arg h "$HID" --arg m "$MACRO" '{hostids:[$h],output:["hostmacroid","macro","value"],filter:{macro:$m}}')" | jq -c --arg h "$HID" '{host:$h, macros:.}'; done
echo "aplicado (revisar OK/RECHAZADO arriba). Rollback: $0 rollback $RUN"

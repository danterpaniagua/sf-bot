#!/usr/bin/env bash
# Event: 20261015_gitin2239-mobile-healthcheck-alerta-zabbix (GITIN-2239)
# C7 - Zabbix 6.0.32 (sf-monitoreo.smartfran.com:8080; token en $ZABBIX_API_KEY). PRUEBA CONTROLADA DE ENTREGA de las alertas de healthcheck.
#      Baja temporalmente la macro {$HC.RESP.WARN} del host sfcg-monitoreo (id 10610) de 2 s a 0.01 s: los dos triggers "slow response" (MobileApp 26922 y WebServiceV2 26924, Warning) pasan a PROBLEMA porque el tiempo
#      promedio real (~0.5 s) supera 0.01 s, y se genera la notificacion al Chat de Operaciones (accion 7). Luego se restaura el valor y llega el aviso de recuperacion.
#      Efecto visible: 2 mensajes de problema y 2 de recuperacion en el Chat de Operaciones (Warning). Avisar al equipo antes. Valida: que el trigger dispara, que la accion genera la notificacion y que llega al Chat,
#      y que el titulo de la tarjeta se resuelve con las etiquetas friendlyname/SVC_FRIENDLYNAME.
#      Modos: dry (por defecto, SOLO LECTURA) | on (CAMBIA ESTADO: baja la macro a 0.01 y espera hasta ~5 min a que dispare) | off <carpeta c7-run-...> (CAMBIA ESTADO: restaura el valor original y espera la recuperacion)
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
MODE="${1:-dry}"; SNAP="${2:-}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/loyalty/events/20261015_gitin2239-mobile-healthcheck-alerta-zabbix/data"
TS=$(date -u +%Y%m%dT%H%M%SZ); RUN="$OUT/c7-run-$TS"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
state() { call trigger.get '{"triggerids":["26922","26924"],"output":["triggerid","description","value","state","status"]}' | jq -r '.[]|[.triggerid,.description,("value="+.value),("state="+.state)]|@tsv'; }
wait_for() { # $1 = valor esperado (1 problema, 0 ok)
  for n in $(seq 1 10); do
    V=$(call trigger.get '{"triggerids":["26922","26924"],"output":["value"]}' | jq -r '[.[].value]|unique|join(",")')
    echo "  intento $n/10: valores de los 2 triggers = $V"; [ "$V" = "$1" ] && return 0; sleep 30
  done; return 1
}
if [ "$MODE" = "off" ]; then
  [ -f "$SNAP/before-macros.json" ] || { echo "uso: $0 off <carpeta c7-run-...>"; exit 1; }
  ID=$(jq -r '.[]|select(.macro=="{$HC.RESP.WARN}")|.hostmacroid' "$SNAP/before-macros.json"); OLD=$(jq -r '.[]|select(.macro=="{$HC.RESP.WARN}")|.value' "$SNAP/before-macros.json")
  call usermacro.update "$(jq -nc --arg i "$ID" --arg v "$OLD" '{hostmacroid:$i,value:$v}')" >/dev/null; echo "{\$HC.RESP.WARN} restaurada a $OLD"
  echo "esperando la recuperacion..."; wait_for 0 && echo "recuperados" || echo "AVISO: todavia no recuperaron (la recuperacion depende de la ventana de 5 min del promedio)"
  state; exit 0
fi
mkdir -p "$RUN"; echo "modo=$MODE | $TS | carpeta $RUN"
call usermacro.get '{"hostids":["10610"],"output":["hostmacroid","macro","value"],"filter":{"macro":["{$HC.RESP.WARN}","{$HC.RESP.WARN.RECOVERY}","{$HC.RESP.WINDOW}"]}}' > "$RUN/before-macros.json"
jq -e 'length==3 and ([.[]|select(.macro=="{$HC.RESP.WARN}")|.value]==["2"])' "$RUN/before-macros.json" >/dev/null || { echo "GUARDA: las macros HC.RESP.* no estan como se esperaba (RESP.WARN debe valer 2)"; jq -c . "$RUN/before-macros.json"; exit 1; }
call trigger.get '{"triggerids":["26922","26924"],"output":["triggerid","description","value","status"],"selectTags":["tag","value"]}' > "$RUN/before-triggers.json"
jq -e 'length==2 and all(.status=="0" and .value=="0")' "$RUN/before-triggers.json" >/dev/null || { echo "GUARDA: los triggers 26922/26924 no estan activos y en OK"; exit 1; }
echo "== plan: {\$HC.RESP.WARN} 2 -> 0.01 (host sfcg-monitoreo); los triggers 26922 y 26924 deberian pasar a PROBLEMA y notificar al Chat de Operaciones; despues se restaura con: $0 off $RUN"
if [ "$MODE" != "on" ]; then echo "DRY: no se cambio nada. Para ejecutar la prueba: $0 on"; exit 0; fi
ID=$(jq -r '.[]|select(.macro=="{$HC.RESP.WARN}")|.hostmacroid' "$RUN/before-macros.json")
call usermacro.update "$(jq -nc --arg i "$ID" '{hostmacroid:$i,value:"0.01"}')" >/dev/null; echo "{\$HC.RESP.WARN} = 0.01 aplicada a las $(date -u +%T) UTC"
echo "esperando que disparen..."; wait_for 1 && echo "DISPARARON" || echo "AVISO: no dispararon en 5 min"
state
call event.get '{"objectids":["26922","26924"],"source":0,"object":0,"value":"1","sortfield":["clock"],"sortorder":"DESC","limit":2,"output":["eventid","objectid","clock"]}' > "$RUN/events.json"
call alert.get "$(jq -n --argjson e "$(jq -c '[.[].eventid]' "$RUN/events.json")" '{eventids:$e,output:["eventid","actionid","mediatypeid","userid","status","error","clock"]}')" > "$RUN/alerts.json"
echo "== notificaciones generadas (evento | accion | medio | usuario | status 1=enviada 2=fallida | error)"; jq -r '.[]|[.eventid,.actionid,.mediatypeid,.userid,.status,.error]|@tsv' "$RUN/alerts.json"
echo "AHORA: revisar el Chat de Operaciones (2 avisos Warning) y restaurar con: $0 off $RUN"

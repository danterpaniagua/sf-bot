#!/usr/bin/env bash
# Event: 20261015_gitin2239-mobile-healthcheck-alerta-zabbix (GITIN-2239)
# C13 - Zabbix 6.0.32 (sf-monitoreo.smartfran.com:8080; token en $ZABBIX_API_KEY). SOLO LECTURA.
#       C12 (apply 12:11 UTC) creo los items 54613-54615 (vfs.file.exists, SFCG-WEBS-01/02/03) y las macros 7478-7480 pero NO los triggers: tras ~9 min los items seguian sin dato (lastclock 0, state 0, sin error).
#       Este script muestra el estado actual de esos items (state, valor, hora del dato, error) y, para saber si el agente de cada host esta vivo, la hora del dato mas reciente de CUALQUIER otro item de agente activo del host
#       y cuantos items de agente activo del host estan no soportados. No cambia nada.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/loyalty/events/20261015_gitin2239-mobile-healthcheck-alerta-zabbix/data"
TS=$(date -u +%Y%m%dT%H%M%SZ); RUN="$OUT/c13-run-$TS"; mkdir -p "$RUN"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
echo "run $TS ($(date -u +%FT%TZ)) | items nuevos de C12 y vida del agente de cada host"
call item.get '{"itemids":["54613","54614","54615"],"output":["itemid","hostid","key_","type","status","state","lastvalue","lastclock","error","delay"],"selectHosts":["host"]}' > "$RUN/items-c12.json"
jq -r '.[]|[.itemid,.hosts[0].host,("tipo="+.type),("status="+.status),("state="+.state),("valor="+.lastvalue),("hora_dato="+((.lastclock|tonumber)|if .>0 then strftime("%FT%TZ") else "ninguno" end)),("delay="+.delay),("error="+.error)]|@tsv' "$RUN/items-c12.json"
call item.get '{"hostids":["10661","10662","10663"],"filter":{"type":["7"],"status":["0"]},"output":["itemid","hostid","state","lastclock"],"selectHosts":["host"]}' > "$RUN/items-activos.json"
echo "== agente activo por host: dato mas reciente de cualquier item (UTC) | items no soportados (state=1) | items totales"
jq -r 'group_by(.hosts[0].host)[]|[.[0].hosts[0].host,("ultimo_dato="+(([.[]|(.lastclock|tonumber)]|max)|if .>0 then strftime("%FT%TZ") else "ninguno" end)),("no_soportados="+([.[]|select(.state=="1")]|length|tostring)),("items="+(length|tostring))]|@tsv' "$RUN/items-activos.json"
echo "guardado en $RUN"

#!/usr/bin/env bash
# Event: 20261015_gitin2229-alerta-fatal-zabbix
# C7 - SOLO LECTURA contra la API REST de Graylog de SmartPedidos. Token en $SML_GRAYLOG_API_KEY (nunca literal).
#      Pedido del usuario: la misma alerta de mensajes FATAL para concentrador-service. Antes de crearla hay que saber como se identifica ese servicio en Graylog
#      y si registra mensajes FATAL. Lee SOLO los valores de ServiceName, msg_service, msg_level y msg_category (metadatos, no el texto de los mensajes).
#      1) muestra de 500 mensajes de los ultimos 15 min con el campo msg_service: conteo por (ServiceName, msg_service)
#      2) conteo de mensajes de nivel FATAL en 7 dias por (ServiceName, msg_service, msg_category), con limit=500
#      3) conteo de mensajes de concentrador por nivel en 1 h (muestra de 500) para ver si usa el mismo esquema de campos
#      Salida: data/c7/concentrador.txt
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${SML_GRAYLOG_API_KEY:?definir SML_GRAYLOG_API_KEY en el entorno}"
BASE="http://sf-monitoreo.smartfran.com:9000/api"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261015_gitin2229-alerta-fatal-zabbix/data/c7"
mkdir -p "$OUT"; T=$(mktemp)
get() { curl -sS -G -u "$SML_GRAYLOG_API_KEY:token" -H 'Accept: application/json' "$BASE/search/universal/relative" --data-urlencode "query=$1" --data-urlencode "range=$2" --data-urlencode "limit=$3" --data-urlencode "fields=ServiceName,msg_service,msg_level,msg_category" -o "$T" -w '%{http_code}'; }
tab() { jq -r '.messages[].message | [(.ServiceName//"-"),(.msg_service//"-"),(.msg_level//"-"),(.msg_category//"-")] | @tsv' "$T"; }
{
  code=$(get '_exists_:msg_service' 900 500); echo "== 1) muestra 15 min, mensajes con msg_service: HTTP $code | total $(jq -r '.total_results' "$T") | devueltos $(jq '.messages|length' "$T")"
  echo "(conteo | ServiceName | msg_service)"; tab | cut -f1,2 | LC_ALL=C sort | uniq -c | LC_ALL=C sort -rn
  code=$(get 'msg_level:FATAL' 604800 500); echo; echo "== 2) FATAL en 7 dias: HTTP $code | total $(jq -r '.total_results' "$T") | devueltos $(jq '.messages|length' "$T")"
  echo "(conteo | ServiceName | msg_service | msg_level | msg_category)"; tab | LC_ALL=C sort | uniq -c | LC_ALL=C sort -rn
  code=$(get 'msg_service:*oncentrador*' 3600 500); echo; echo "== 3) mensajes con msg_service parecido a concentrador, 1 h: HTTP $code | total $(jq -r '.total_results' "$T") | devueltos $(jq '.messages|length' "$T")"
  echo "(conteo | ServiceName | msg_service | msg_level | msg_category)"; tab | LC_ALL=C sort | uniq -c | LC_ALL=C sort -rn
  code=$(get 'ServiceName:*oncentrador*' 3600 500); echo; echo "== 3b) mensajes con ServiceName parecido a concentrador, 1 h: HTTP $code | total $(jq -r '.total_results' "$T") | devueltos $(jq '.messages|length' "$T")"
  echo "(conteo | ServiceName | msg_service | msg_level | msg_category)"; tab | LC_ALL=C sort | uniq -c | LC_ALL=C sort -rn
} > "$OUT/concentrador.txt" 2>&1
rm -f "$T"; cat "$OUT/concentrador.txt"; echo listo

#!/usr/bin/env bash
# Event: 20261015_gitin2229-alerta-fatal-zabbix
# C4 - SOLO LECTURA contra la API REST de Graylog de SmartPedidos. Token en $SML_GRAYLOG_API_KEY (nunca literal).
#      C3 mostro que los mensajes tienen los campos ServiceName, msg_service, msg_level, msg_category y que "message:\\"[INFRA/FATAL]\\" AND \\"platforms-service\\"" devuelve 62.
#      Este script lee SOLO los valores de ServiceName, msg_service, msg_level y msg_category de los mensajes [INFRA/FATAL] (valores de metadatos, no el texto del error)
#      y prueba consultas con campos para elegir la mas precisa. Salida: data/c4/fields.txt
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${SML_GRAYLOG_API_KEY:?definir SML_GRAYLOG_API_KEY en el entorno}"
BASE="http://sf-monitoreo.smartfran.com:9000/api"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261015_gitin2229-alerta-fatal-zabbix/data/c4"
mkdir -p "$OUT"; T=$(mktemp)
get() { curl -sS -G -u "$SML_GRAYLOG_API_KEY:token" -H 'Accept: application/json' "$BASE/search/universal/relative" --data-urlencode "query=$1" --data-urlencode "range=$2" --data-urlencode "limit=${3:-1}" ${4:+--data-urlencode "fields=$4"} -o "$T" -w '%{http_code}'; }
{
  code=$(get 'message:"[INFRA/FATAL]"' 50400 500 "ServiceName,msg_service,msg_level,msg_category")
  echo "mensajes [INFRA/FATAL] (14 h): HTTP $code | total $(jq -r '.total_results' "$T") | devueltos $(jq '.messages|length' "$T")"
  echo "== combinaciones de valores (conteo | ServiceName | msg_service | msg_level | msg_category)"
  jq -r '.messages[].message | [(.ServiceName//"-"),(.msg_service//"-"),(.msg_level//"-"),(.msg_category//"-")] | @tsv' "$T" | LC_ALL=C sort | uniq -c | LC_ALL=C sort -rn
  echo; echo "== consultas candidatas (14 h): HTTP | total_results | consulta"
  while IFS= read -r q; do
    code=$(get "$q" 50400 || echo curl-fallo)
    if [ "$code" = "200" ]; then echo "$code | $(jq -r '.total_results' "$T") | $q"; else echo "$code | - | $q | $(head -c 200 "$T" | tr '\n' ' ')"; fi
  done <<'QRY'
msg_level:FATAL
msg_level:FATAL AND ServiceName:"platforms-service"
msg_level:FATAL AND msg_service:"platforms-service"
message:"[INFRA/FATAL]" AND ServiceName:"platforms-service"
message:"[INFRA/FATAL]" AND msg_service:"platforms-service"
message:"[INFRA/FATAL]" AND "platforms-service"
QRY
} > "$OUT/fields.txt" 2>&1
rm -f "$T"; cat "$OUT/fields.txt"; echo listo

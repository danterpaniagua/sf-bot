#!/usr/bin/env bash
# Event: 20261015_gitin2229-alerta-fatal-zabbix
# C6 - SOLO LECTURA contra la API de Zabbix (6.0.32; token en $ZABBIX_API_KEY).
#      El apply de C5 fallo en item.create: 'Invalid parameter "/headers/1": a character string is expected' (el formato de headers de 6.0 no es una lista {name,value}).
#      Lee de un item HTTP agent existente de "Zabbix server" (MongoDB Atlas) SOLO la forma de query_fields, headers, authtype, request_method y retrieve_mode,
#      para copiar el formato. No se leen ni se guardan username/password/url. Salida: data/c6/shape.json
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261015_gitin2229-alerta-fatal-zabbix/data/c6"
mkdir -p "$OUT"
jq -n --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:"item.get",params:{hostids:["10084"],filter:{type:"19"},output:["itemid","name","authtype","request_method","retrieve_mode","post_type","timeout","output_format"],selectPreprocessing:["type"],limit:2},auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq '.result' > "$OUT/basic.json"
ID=$(jq -r '.[0].itemid' "$OUT/basic.json")
# query_fields y headers solo se devuelven con la opcion output "extend": se piden y se guardan solo esas dos claves
jq -n --arg a "$ZABBIX_API_KEY" --arg id "$ID" '{jsonrpc:"2.0",method:"item.get",params:{itemids:[$id],output:"extend"},auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq '.result[0] | {itemid, query_fields, headers, authtype, request_method, retrieve_mode, post_type, timeout}' > "$OUT/shape.json"
echo "== ejemplo basico"; cat "$OUT/basic.json"
echo "== forma de query_fields / headers"; cat "$OUT/shape.json"
echo listo

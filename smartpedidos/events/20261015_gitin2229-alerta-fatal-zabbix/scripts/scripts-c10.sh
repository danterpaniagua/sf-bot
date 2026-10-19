#!/usr/bin/env bash
# Event: 20261015_gitin2229-alerta-fatal-zabbix
# C10 - Zabbix 6.0.32 (sf-monitoreo.smartfran.com:8080; token en $ZABBIX_API_KEY). SOLO LECTURA.
#       Verifica si los triggers ECS descubiertos 26915 y 26916 ya heredaron del prototipo 26911 las etiquetas env=PROD, friendlyname y SVC_FRIENDLYNAME.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261015_gitin2229-alerta-fatal-zabbix/data"
TS=$(date -u +%Y%m%dT%H%M%SZ)
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
call trigger.get '{"triggerids":["26915","26916"],"output":["triggerid","description","status","value"],"selectTags":["tag","value"],"selectHosts":["host"]}' > "$OUT/c10-triggers-$TS.json"
jq -e 'length==2' "$OUT/c10-triggers-$TS.json" >/dev/null || { echo "AVISO: no se encontraron los 2 triggers (el descubrimiento pudo recrearlos con otro id)"; exit 1; }
echo "== trigger | env=PROD | friendlyname | SVC_FRIENDLYNAME"
jq -r '.[]|[.triggerid,
  (([.tags[]|select(.tag=="env" and .value=="PROD")]|length)>0),
  (([.tags[]|select(.tag=="friendlyname")]|length)>0),
  (([.tags[]|select(.tag=="SVC_FRIENDLYNAME")]|length)>0)]|@tsv' "$OUT/c10-triggers-$TS.json"
echo "guardado: $OUT/c10-triggers-$TS.json"

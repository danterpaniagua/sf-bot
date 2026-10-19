#!/usr/bin/env bash
# Event: 20261015_gitin2229-alerta-fatal-zabbix
# C2 - SOLO LECTURA contra la API de Zabbix (sf-monitoreo.smartfran.com:8080, 6.0.32; token en $ZABBIX_API_KEY).
#      Para decidir en que host vivira el item HTTP agent: lista hosts (nombre, grupos, estado), items HTTP agent existentes (tipo 19) y macros cuyo nombre contenga GRAYLOG o TOKEN
#      (SOLO nombre, tipo y host; el valor nunca se guarda). Salidas en data/c2/.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261015_gitin2229-alerta-fatal-zabbix/data/c2"
mkdir -p "$OUT"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
call host.get '{"output":["hostid","name","status","flags"],"selectGroups":["name"],"selectParentTemplates":["name"]}' > "$OUT/hosts.json"
echo "== hosts (id | nombre | status 0=activo | flags 0=manual 4=descubierto | grupos)"
jq -r '.[]|[.hostid,.name,.status,.flags,([.groups[].name]|join(";"))]|@tsv' "$OUT/hosts.json"
call item.get '{"output":["itemid","hostid","name","key_","url","delay","status"],"filter":{"type":"19"},"selectHosts":["name"]}' > "$OUT/http-items.json"
echo; echo "== items HTTP agent existentes (host | nombre | intervalo | url sin query)"
jq -r '.[]|[.hosts[0].name,.name,.delay,(.url|sub("\\?.*";""))]|@tsv' "$OUT/http-items.json"
call usermacro.get '{"output":["macro","type","hostid"],"search":{"macro":"GRAYLOG"},"selectHosts":["name"]}' > "$OUT/macros-graylog.json"
call usermacro.get '{"output":["macro","type","hostid"],"search":{"macro":"TOKEN"},"selectHosts":["name"]}' > "$OUT/macros-token.json"
echo; echo "== macros con GRAYLOG o TOKEN en el nombre (macro | tipo 0=texto 1=secreto 2=vault | host); sin valores"
jq -r '.[]|[.macro,.type,(.hosts[0].name // "global")]|@tsv' "$OUT/macros-graylog.json" "$OUT/macros-token.json"
echo listo

#!/usr/bin/env bash
# Event: 20261015_gitin2239-mobile-healthcheck-alerta-zabbix (GITIN-2239)
# C10 - Zabbix 6.0.32 (sf-monitoreo.smartfran.com:8080; token en $ZABBIX_API_KEY). SOLO LECTURA.
#       Pedido del usuario (2026-10-16): agregar a Zabbix la alerta del archivo de healthcheck de los servidores "WebService - 01/02/03" (SmartLoyalty.WebService, no WebServiceV2):
#         WebService-01: C:\SmartFran\SmartLoyalty.WebService\healthcheck.ashx y healthcheckv2.ashx | WebService-02 y -03: C:\SmartFran\SmartLoyalty.WebService\healthcheck.ashx (rutas dadas por el usuario, no verificadas).
#       Nombres (documentacion: loyalty/docs/infrastructure.md lineas 23 y 141, y docs/zabbix_observability.md linea 65): SFCG-WEBS-01/02/03 = WebService en C:\SmartFran\SmartLoyalty.WebService\ (on-premise SmartFran).
#       Este script busca los hosts cuyo nombre contenga SFCG-WEBS (y no asume que existan los tres con ese nombre exacto en Zabbix) y muestra por host: id, nombre, estado, proxy, interfaces (tipo y disponibilidad), cantidad de items de agente activo (tipo 7) y los items vfs.file.exists que ya existen. No imprime IPs ni macros.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/loyalty/events/20261015_gitin2239-mobile-healthcheck-alerta-zabbix/data"
TS=$(date -u +%Y%m%dT%H%M%SZ); RUN="$OUT/c10-run-$TS"; mkdir -p "$RUN"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
echo "run $TS | hosts candidatos para la alerta del archivo de healthcheck de WebService"
call host.get '{"search":{"host":["SFCG-WEBS"],"name":["SFCG-WEBS"]},"searchByAny":true,"output":["hostid","host","name","status","flags","proxy_hostid"],"selectInterfaces":["type","main","available"],"selectGroups":["name"],"selectParentTemplates":["name"]}' > "$RUN/hosts.json"
jq -r '.[]|[.hostid,.host,("name="+.name),("status="+.status),("flags="+.flags),("proxy="+.proxy_hostid),("interfaces="+([.interfaces[]|"tipo"+.type+"/disp"+.available]|join(","))),("grupos="+([.groups[].name]|join("|"))),("plantillas="+([.parentTemplates[].name]|join("|")))]|@tsv' "$RUN/hosts.json"
IDS=$(jq -c '[.[].hostid]' "$RUN/hosts.json")
echo "== items de agente activo (tipo 7) y vfs.file.exists por host"
call item.get "$(jq -n --argjson h "$IDS" '{hostids:$h,output:["itemid","hostid","key_","type","state","lastvalue","lastclock"],selectHosts:["host"],filter:{type:["7"]}}')" > "$RUN/items-activos.json"
jq -r 'group_by(.hosts[0].host)[]|"\(.[0].hosts[0].host): items de agente activo=\(length) | vfs.file.exists=\([.[]|select(.key_|startswith("vfs.file.exists"))]|length)"' "$RUN/items-activos.json"
echo "== items vfs.file.exists existentes (clave | ultimo valor | hora del dato)"
jq -r '.[]|select(.key_|startswith("vfs.file.exists"))|[.hosts[0].host,.key_,("valor="+.lastvalue),("hora="+((.lastclock|tonumber)|if .>0 then strftime("%FT%TZ") else "ninguna" end))]|@tsv' "$RUN/items-activos.json"
echo "guardado en $RUN"

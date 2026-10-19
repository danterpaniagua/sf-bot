#!/usr/bin/env bash
# Event: 20261015_gitin2239-mobile-healthcheck-alerta-zabbix (GITIN-2239)
# C3 - SOLO LECTURA contra la API de Zabbix (6.0.32; token en $ZABBIX_API_KEY).
#      Pedido del usuario: agregar una alerta en Zabbix sobre el ARCHIVO healthcheck.ashx (que no se pierda de nuevo). Idea: un item del agente Zabbix vfs.file.exists[<ruta>] por servidor
#      y un trigger High cuando valga 0. Rutas segun los eventos de GITIN-1228 y GITIN-2058: D:\SmartLoyalty.MobileAppService\healthcheck.ashx (MOBI-01/02) y
#      D:\SmartLoyalty.WebServiceV2\healthcheck.ashx (WSV2-01/02); la ruta exacta del archivo dentro de esas carpetas NO esta verificada (se deduce de los eventos).
#      Este script lee, de los hosts "Mobile 01/02" (10659, 10660) y "WebserviceV2 01/02" (10665, 10678): nombre tecnico, estado, tipo de agente (interfaces / activo), plantillas vinculadas,
#      items vfs.file.* existentes, disponibilidad del agente y el ultimo valor/hora de un item de agente activo (para ver que el agente esta reportando). Salidas en data/c3/.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/loyalty/events/20261015_gitin2239-mobile-healthcheck-alerta-zabbix/data/c3"
mkdir -p "$OUT"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
call host.get '{"hostids":["10659","10660","10665","10678"],"output":["hostid","host","name","status","active_available","available","proxy_hostid"],"selectInterfaces":["type","ip","dns","port","main"],"selectParentTemplates":["name"],"selectGroups":["name"]}' > "$OUT/hosts.json"
echo "== hosts (id | host tecnico | nombre | status 0=activo | active_available 0=desconocido 1=disponible 2=no disponible | interfaces agente | proxy)"
jq -r '.[]|[.hostid,.host,.name,.status,.active_available,([.interfaces[]|select(.type=="1")|"\(.ip // .dns):\(.port)"]|join(",")),.proxy_hostid]|@tsv' "$OUT/hosts.json"
echo; echo "== plantillas y grupos"; jq -r '.[]|[.name,([.parentTemplates[].name]|join(";")),([.groups[].name]|join(";"))]|@tsv' "$OUT/hosts.json"
call item.get '{"hostids":["10659","10660","10665","10678"],"search":{"key_":"vfs.file"},"output":["itemid","hostid","name","key_","type","delay","status","state","lastvalue"],"selectHosts":["name"]}' > "$OUT/vfs-items.json"
echo; echo "== items vfs.file.* que ya existen (host | clave | tipo 7=agente activo 0=agente pasivo | ultimo valor)"
jq -r '.[]|[.hosts[0].name,.key_,.type,.lastvalue]|@tsv' "$OUT/vfs-items.json"
call item.get '{"hostids":["10659","10660","10665","10678"],"filter":{"type":["0","7"]},"output":["itemid","hostid","key_","type","lastclock","state"],"selectHosts":["name"],"limit":400}' > "$OUT/agent-items.json"
echo; echo "== items de agente por host: tipo mas comun y hora del dato mas reciente UTC (host | tipo 0/7 | cantidad | ultimo dato)"
jq -r 'group_by(.hosts[0].name)[]|. as $g|($g[0].hosts[0].name) as $n|($g|group_by(.type)[])|[$n,.[0].type,length,(map(.lastclock|tonumber)|max|strftime("%FT%TZ"))]|@tsv' "$OUT/agent-items.json"
echo listo

#!/usr/bin/env bash
# Event: 20261014_gitin2222-ecs-reinicios-avisos-sns
# C37 - SOLO LECTURA contra la API de Zabbix (6.0.32; token en $ZABBIX_API_KEY).
#       C36 (log del servidor Zabbix, filtro por palabras clave y por minuto) volvio vacio: sin avisos ni errores de ese tipo al nivel de log por defecto (no prueba nada mas).
#       Ultima entrega correcta: 18:00:09 UTC; primer evento sin notificacion: 19:04:08 UTC. Este script lee el REGISTRO DE AUDITORIA de Zabbix entre las 17:55 y las 19:10 UTC (todas las entidades) y muestra
#       los cambios hechos por PERSONAS (userid distinto de 0; "System" = el propio servidor se omite salvo que se pida) sobre usuarios, grupos de usuarios, acciones, tipos de medio, roles, hosts, triggers, macros y ajustes:
#       que cambio, quien (id de usuario; nombre enmascarado), cuando y los detalles recortados. Es la forma objetiva de saber que se toco en el intervalo en que dejaron de salir las notificaciones.
#       Salida en data/c37/ y resumen por stdout. Requiere auditoria habilitada.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/data/c37"
mkdir -p "$OUT"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
F=$(date -u -d "2026-10-15 17:55:00" +%s); T=$(date -u -d "2026-10-15 19:10:00" +%s)
call auditlog.get "$(jq -n --argjson f "$F" --argjson t "$T" '{output:"extend",time_from:$f,time_till:$t,sortfield:"clock",sortorder:"ASC",limit:1000}')" > "$OUT/auditlog.json"
echo "== filas de auditoria 17:55-19:10 UTC: $(jq length "$OUT/auditlog.json") | de personas (userid != 0): $(jq '[.[]|select(.userid!="0")]|length' "$OUT/auditlog.json")"
echo "== cambios de personas (hora UTC | usuario | accion 0=alta 1=cambio 2=baja 3=ingreso 4=salida 9=ejecucion | tipo de recurso | recurso | detalles 220 car.)"
jq -r '.[]|select(.userid!="0")|[(.clock|tonumber|strftime("%H:%M:%S")),("u"+.userid+" ("+((.username // "-")|.[0:2]+"***")+")"),.action,.resourcetype,((.resourceid // "-")+" "+(.resourcename // "")),((.details // "")|gsub("\n";" ")|.[0:220])]|@tsv' "$OUT/auditlog.json"
echo; echo "== resumen del sistema por tipo de recurso y accion (cantidad)"
jq -r '[.[]|select(.userid=="0")]|group_by([.resourcetype,.action])[]|[.[0].resourcetype,.[0].action,length]|@tsv' "$OUT/auditlog.json"
echo listo

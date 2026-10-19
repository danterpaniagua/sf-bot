#!/usr/bin/env bash
# Event: 20261014_gitin2222-ecs-reinicios-avisos-sns
# C18 - SOLO LECTURA contra la API de Zabbix (sf-monitoreo.smartfran.com:8080, 6.0.32; token en $ZABBIX_API_KEY).
#       El "Execute now" de la regla "Cluster Services discovery" en el host descubierto respondio "Cannot send request: wrong discovery rule type" (la regla es dependiente: su dato viene del item maestro).
#       Los tags nuevos del prototipo 26911 (C16) no llegaron a los triggers ya descubiertos (C11 de las 01:59 UTC). Este script lee, en la plantilla 10576 y en el host 10666:
#         a) la regla de servicios (44973): tipo, maestro, intervalo, periodo de conservacion de recursos perdidos y su PREPROCESADO (p. ej. "descartar sin cambios con latido")
#         b) el item maestro "Get cluster services" (tipo, intervalo) de la plantilla y de la regla descubierta en el host 10666 (sus ultimas ejecuciones)
#         c) el prototipo 26911: tags guardados
#       Salida en data/c18/.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/data/c18"
mkdir -p "$OUT"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
call discoveryrule.get '{"templateids":["10576"],"output":["itemid","name","key_","type","master_itemid","delay","lifetime","status"],"selectPreprocessing":["type","params","error_handler"]}' > "$OUT/template-rules.json"
echo "== reglas de descubrimiento de la plantilla 10576 (tipo 18 = dependiente; preprocesado: tipo 20 = descartar sin cambios con latido, 19 = descartar sin cambios)"
jq -r '.[] | [.itemid, .name, ("tipo="+.type), ("maestro="+.master_itemid), ("intervalo="+.delay), ("lifetime="+.lifetime), ([.preprocessing[]|"t\(.type): \(.params)"]|join(" ; "))] | @tsv' "$OUT/template-rules.json"
call discoveryrule.get '{"hostids":["10666"],"output":["itemid","name","key_","type","master_itemid","delay","lifetime","state","error","lastclock"],"selectPreprocessing":["type","params"]}' > "$OUT/host-rules.json"
echo; echo "== reglas descubiertas en el host 10666 (state 0 = normal; lastclock en UTC)"
jq -r '.[] | [.itemid, .name, ("state="+.state), ("lastclock="+((.lastclock|tonumber|if .>0 then strftime("%FT%TZ") else "nunca" end))), (.error // "")] | @tsv' "$OUT/host-rules.json"
call item.get '{"hostids":["10666"],"search":{"key_":"aws.ecs.get_cluster_services"},"output":["itemid","name","key_","type","delay","state","lastclock","error"]}' > "$OUT/master-item.json"
echo; echo "== item maestro 'Get cluster services' en el host 10666"
jq -r '.[] | [.itemid, .name, ("tipo="+.type), ("intervalo="+.delay), ("state="+.state), ("lastclock="+((.lastclock|tonumber|if .>0 then strftime("%FT%TZ") else "nunca" end))), (.error // "")] | @tsv' "$OUT/master-item.json"
call triggerprototype.get '{"triggerids":["26911"],"output":["triggerid"],"selectTags":["tag","value"]}' > "$OUT/prototype-tags.json"
echo; echo "== tags guardados en el prototipo 26911"; jq -c '.[0].tags' "$OUT/prototype-tags.json"
echo listo

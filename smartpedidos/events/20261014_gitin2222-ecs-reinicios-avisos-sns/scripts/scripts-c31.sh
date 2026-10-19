#!/usr/bin/env bash
# Event: 20261014_gitin2222-ecs-reinicios-avisos-sns
# C31 - SOLO LECTURA contra la API de Zabbix (6.0.32; token en $ZABBIX_API_KEY).
#       Pregunta del usuario: que usa la macro {$AWS.ECS.CLUSTER.SERVICE.RUNNING.DIP}? Busca el texto "RUNNING.DIP" en items, prototipos de item, reglas de descubrimiento, triggers y prototipos de trigger
#       de la plantilla ECS (10576) y de los hosts 10666, 10667, 10668 y 10084, mirando clave, parametros, URL, expresiones y preprocesado. Muestra tipo de objeto, id, nombre y donde aparece.
#       Salidas en data/c31/.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/data/c31"
mkdir -p "$OUT"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
SCOPE='"hostids":["10576","10666","10667","10668","10084"]'
call item.get "{$SCOPE,\"output\":\"extend\",\"selectPreprocessing\":\"extend\",\"selectHosts\":[\"host\"]}" > "$OUT/items.json"
call itemprototype.get "{$SCOPE,\"output\":\"extend\",\"selectPreprocessing\":\"extend\",\"selectHosts\":[\"host\"]}" > "$OUT/itemprototypes.json"
call discoveryrule.get "{$SCOPE,\"output\":\"extend\",\"selectPreprocessing\":\"extend\",\"selectHosts\":[\"host\"]}" > "$OUT/discoveryrules.json"
call trigger.get "{$SCOPE,\"output\":[\"triggerid\",\"description\",\"expression\",\"recovery_expression\"],\"selectHosts\":[\"host\"]}" > "$OUT/triggers.json"
call triggerprototype.get "{$SCOPE,\"output\":[\"triggerid\",\"description\",\"expression\",\"recovery_expression\"],\"selectHosts\":[\"host\"]}" > "$OUT/triggerprototypes.json"
echo "== objetos revisados: items $(jq length "$OUT/items.json"), prototipos de item $(jq length "$OUT/itemprototypes.json"), reglas $(jq length "$OUT/discoveryrules.json"), triggers $(jq length "$OUT/triggers.json"), prototipos de trigger $(jq length "$OUT/triggerprototypes.json")"
echo "== objetos que contienen 'RUNNING.DIP' (tipo | id | host | nombre/descripcion | expresion o clave)"
for k in items:item:itemid itemprototypes:item-prototype:itemid discoveryrules:discovery-rule:itemid triggers:trigger:triggerid triggerprototypes:trigger-prototype:triggerid; do
  F=${k%%:*}; R=${k#*:}; T=${R%%:*}; ID=${R#*:}
  jq -r --arg t "$T" --arg id "$ID" '.[]|select(tostring|contains("RUNNING.DIP"))|[$t,.[$id],(.hosts[0].host // "?"),(.name // .description),((.expression // .key_)[0:140])]|@tsv' "$OUT/$F.json"
done
echo listo

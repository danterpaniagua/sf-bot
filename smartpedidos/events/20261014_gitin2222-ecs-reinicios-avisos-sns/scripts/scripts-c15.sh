#!/usr/bin/env bash
# Event: 20261014_gitin2222-ecs-reinicios-avisos-sns
# C15 - SOLO LECTURA contra la API de Zabbix (sf-monitoreo.smartfran.com:8080, 6.0.32; token en $ZABBIX_API_KEY).
#       Correccion del usuario: el enrutamiento debe usar scope OPE y SP, sin SML. Para crear una accion nueva para SmartPedidos clonada de la accion 7 ("Google Chat Loyalty to Operaciones")
#       hay que leer la definicion COMPLETA de la accion 7: operaciones, operaciones de recuperacion y de actualizacion, plantillas de mensaje y periodos. Solo ids de usuario/grupo y de tipo de medio (no correos ni webhooks).
#       Salida en data/c15/action7-full.json y resumen por pantalla.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/data/c15"
mkdir -p "$OUT"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
call action.get '{"actionids":["7"],"output":"extend","selectFilter":"extend","selectOperations":"extend","selectRecoveryOperations":"extend","selectUpdateOperations":"extend"}' > "$OUT/action7-full.json"
echo "== accion 7: campos de primer nivel"
jq -r '.[0] | to_entries[] | select(.value|type=="string") | "\(.key)=\(.value|.[0:200]|gsub("\n";"\\n"))"' "$OUT/action7-full.json"
echo; echo "== filtro"; jq -c '.[0].filter' "$OUT/action7-full.json"
for K in operations recovery_operations update_operations; do echo; echo "== $K"; jq -c --arg k "$K" '.[0][$k][]?' "$OUT/action7-full.json"; done
echo; echo "== accion 7 vigente (tras el rollback de C13 deberia ser 'A and B and (C or D)' con 4 condiciones)"
jq -r '.[0] | "status=\(.status) evaltype=\(.filter.evaltype) formula=\(.filter.formula) condiciones=\(.filter.conditions|length)"' "$OUT/action7-full.json"
echo listo

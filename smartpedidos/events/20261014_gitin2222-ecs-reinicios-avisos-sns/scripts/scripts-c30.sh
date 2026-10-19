#!/usr/bin/env bash
# Event: 20261014_gitin2222-ecs-reinicios-avisos-sns
# C30 - Zabbix 6.0.32 (sf-monitoreo.smartfran.com:8080; token en $ZABBIX_API_KEY). Opcion 1 elegida por el usuario: la alerta de ECS vuelve a usar el margen 0.05 de la plantilla.
#       C29: el prototipo de host 10620 NO tiene la macro {$AWS.ECS.CLUSTER.SERVICE.RUNNING.DIP}; los hosts descubiertos tienen cada uno la suya con valor 1000 (production id 7451, common 7455, dev 7459).
#       Este script borra SOLO la macro 7451 del host smartfran-pedidos-production (10666), de modo que herede el 0.05 de la plantilla 10576. Common (7455), dev (7459) y la macro de "Zabbix server" (que silencia
#       la copia duplicada) NO se tocan.
#       Hipotesis no verificada: que la API permita borrar una macro de un host descubierto (flags 4) y que la proxima pasada de descubrimiento no la recree (si el prototipo no la define, no deberia). El script lo comprueba
#       leyendo la expresion expandida del trigger 26915 despues del cambio.
#       Efecto esperado: el trigger "Running tasks below desired" reaccionara a cualquier caida (unas decenas por dia en Platform segun CloudWatch) y notificara al Chat de Operaciones.
#       Modos: dry (por defecto, SOLO LECTURA) | apply (CAMBIA ESTADO) | rollback <carpeta c30-run-...> (CAMBIA ESTADO: recrea la macro con valor 1000)
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
MODE="${1:-dry}"; SNAP="${2:-}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/data"
TS=$(date -u +%Y%m%dT%H%M%SZ); RUN="$OUT/c30-run-$TS"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
if [ "$MODE" = "rollback" ]; then
  [ -f "$SNAP/before-macro.json" ] || { echo "uso: $0 rollback <carpeta c30-run-...>"; exit 1; }
  call usermacro.create "$(jq -c '{hostid:.[0].hostid,macro:.[0].macro,value:.[0].value}' "$SNAP/before-macro.json")" >/dev/null; echo "macro recreada con su valor anterior (1000)"; exit 0
fi
mkdir -p "$RUN"; echo "modo=$MODE | $TS | carpeta $RUN"
call usermacro.get '{"hostmacroids":["7451"],"output":["hostmacroid","macro","value","hostid"],"selectHosts":["host"]}' > "$RUN/before-macro.json"
jq -e 'length==1 and .[0].hostid=="10666" and .[0].macro=="{$AWS.ECS.CLUSTER.SERVICE.RUNNING.DIP}" and .[0].value=="1000" and .[0].hosts[0].host=="smartfran-pedidos-production"' "$RUN/before-macro.json" >/dev/null || { echo "GUARDA: la macro 7451 no es la esperada"; jq -c . "$RUN/before-macro.json"; exit 1; }
call usermacro.get '{"hostids":["10576"],"output":["hostmacroid","macro","value"],"filter":{"macro":"{$AWS.ECS.CLUSTER.SERVICE.RUNNING.DIP}"}}' > "$RUN/template-macro.json"
jq -e 'length==1 and .[0].value=="0.05"' "$RUN/template-macro.json" >/dev/null || { echo "GUARDA: la macro de la plantilla 10576 no vale 0.05"; jq -c . "$RUN/template-macro.json"; exit 1; }
echo "== se borraria la macro 7451 (smartfran-pedidos-production = 1000); la plantilla 10576 tiene 0.05"
if [ "$MODE" != "apply" ]; then echo "DRY: no se cambio nada. Para aplicar: $0 apply"; exit 0; fi
call usermacro.delete '["7451"]' > "$RUN/delete-response.json"; echo "macro 7451 borrada"
call trigger.get '{"triggerids":["26915","26916"],"output":["triggerid","description","value","state"],"expandExpression":true}' > "$RUN/after-triggers.json"
jq -r '.[]|[.triggerid,.value,.state,.expression]|@tsv' "$RUN/after-triggers.json"
echo "aplicado. Rollback: $0 rollback $RUN"

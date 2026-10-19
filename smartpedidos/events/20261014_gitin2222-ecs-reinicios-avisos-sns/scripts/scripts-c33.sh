#!/usr/bin/env bash
# Event: 20261014_gitin2222-ecs-reinicios-avisos-sns
# C33 - Zabbix 6.0.32 (sf-monitoreo.smartfran.com:8080; token en $ZABBIX_API_KEY). Deja funcionando la alerta "Running tasks below desired" en el host que tiene los items (smartfran-pedidos-production).
#       Causa (C32, registro de auditoria): la macro {$AWS.ECS.CLUSTER.SERVICE.RUNNING.DIP}=1000 que C17 puso en "Zabbix server" (id 7447) fue copiada por el descubrimiento a los hosts descubiertos
#       (7451 production, 7455 common, 7459 dev) y anula el trigger de production. Decision del usuario: que el trigger funcione en el host que aloja los items.
#       Cambios (en este orden):
#         1) borra la macro 7447 de "Zabbix server" (la fuente) y las tres copias 7451, 7455, 7459 (cada borrado se intenta por separado y un rechazo se informa)
#         2) deshabilita la copia duplicada de "Zabbix server": el prototipo 26912 y los triggers descubiertos 26917 y 26918 (para que cada caida no avise dos veces); NO se desvincula ninguna plantilla
#       Resultado esperado: los triggers 26915 y 26916 de smartfran-pedidos-production se evaluan con el margen 0.05 de la plantilla (se verifica con la expresion expandida) y avisan al Chat de Operaciones en cada caida.
#       Inciertos (no verificados): que la API permita borrar macros de hosts descubiertos y cambiar el estado de triggers descubiertos/prototipos heredados; si algo es rechazado se informa y se sigue.
#       Modos: dry (por defecto, SOLO LECTURA) | apply (CAMBIA ESTADO) | rollback <carpeta c33-run-...> (CAMBIA ESTADO: recrea la macro 7447 en Zabbix server y rehabilita 26912, 26917, 26918; las copias las recrea el descubrimiento)
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
MODE="${1:-dry}"; SNAP="${2:-}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/data"
TS=$(date -u +%Y%m%dT%H%M%SZ); RUN="$OUT/c33-run-$TS"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
try() { if "$@" >/dev/null 2>"$RUN/err.tmp"; then echo "  OK"; else echo "  RECHAZADO: $(head -c 300 "$RUN/err.tmp")"; fi; }
if [ "$MODE" = "rollback" ]; then
  [ -f "$SNAP/before-macros.json" ] || { echo "uso: $0 rollback <carpeta c33-run-...>"; exit 1; }
  RUN="$SNAP"
  echo "recrear macro 7447 en Zabbix server:"; try call usermacro.create "$(jq -c '[.[]|select(.hostmacroid=="7447")][0]|{hostid:.hostid,macro:.macro,value:.value,description:.description}' "$SNAP/before-macros.json")"
  for T in 26917 26918; do echo "rehabilitar trigger $T:"; try call trigger.update "{\"triggerid\":\"$T\",\"status\":0}"; done
  echo "rehabilitar prototipo 26912:"; try call triggerprototype.update '{"triggerid":"26912","status":0}'
  echo "rollback hecho (las copias de production/common/dev las recrea el descubrimiento en su proxima pasada)"; exit 0
fi
mkdir -p "$RUN"; echo "modo=$MODE | $TS | carpeta $RUN"
call usermacro.get '{"hostmacroids":["7447","7451","7455","7459"],"output":["hostmacroid","macro","value","description","hostid"],"selectHosts":["host"]}' > "$RUN/before-macros.json"
jq -e 'length==4 and all(.macro=="{$AWS.ECS.CLUSTER.SERVICE.RUNNING.DIP}" and .value=="1000")' "$RUN/before-macros.json" >/dev/null || { echo "GUARDA: las 4 macros no son las esperadas"; jq -c '[.[]|{hostmacroid,macro,value,host:.hosts[0].host}]' "$RUN/before-macros.json"; exit 1; }
jq -e '([.[]|select(.hostmacroid=="7447")][0].hosts[0].host)=="Zabbix server"' "$RUN/before-macros.json" >/dev/null || { echo "GUARDA: la macro 7447 no esta en Zabbix server"; exit 1; }
call usermacro.get '{"hostids":["10576"],"output":["hostmacroid","value"],"filter":{"macro":"{$AWS.ECS.CLUSTER.SERVICE.RUNNING.DIP}"}}' > "$RUN/template-macro.json"
jq -e 'length==1 and .[0].value=="0.05"' "$RUN/template-macro.json" >/dev/null || { echo "GUARDA: la macro de la plantilla no vale 0.05"; exit 1; }
call triggerprototype.get '{"triggerids":["26912"],"output":["triggerid","description","status"],"selectHosts":["host"]}' > "$RUN/before-prototype.json"
call trigger.get '{"triggerids":["26915","26916","26917","26918"],"output":["triggerid","description","status","value"],"selectHosts":["host"]}' > "$RUN/before-triggers.json"
jq -e '(.[0].hosts[0].host)=="Zabbix server"' "$RUN/before-prototype.json" >/dev/null || { echo "GUARDA: el prototipo 26912 no esta en Zabbix server"; exit 1; }
jq -e '([.[]|select(.triggerid=="26917" or .triggerid=="26918")|.hosts[0].host]|all(.=="Zabbix server")) and ([.[]|select(.triggerid=="26915" or .triggerid=="26916")|.hosts[0].host]|all(.=="smartfran-pedidos-production"))' "$RUN/before-triggers.json" >/dev/null || { echo "GUARDA: los triggers no estan en los hosts esperados"; exit 1; }
echo "== se haria: borrar macros 7447 (Zabbix server), 7451 (production), 7455 (common), 7459 (dev); deshabilitar prototipo 26912 y triggers 26917, 26918 (copias en Zabbix server). Production (26915, 26916) queda con la plantilla: 0.05"
if [ "$MODE" != "apply" ]; then echo "DRY: no se cambio nada. Para aplicar: $0 apply"; exit 0; fi
for M in 7447 7451 7455 7459; do echo "borrar macro $M:"; try call usermacro.delete "[\"$M\"]"; done
echo "deshabilitar prototipo 26912:"; try call triggerprototype.update '{"triggerid":"26912","status":1}'
for T in 26917 26918; do echo "deshabilitar trigger $T:"; try call trigger.update "{\"triggerid\":\"$T\",\"status\":1}"; done
call trigger.get '{"triggerids":["26915","26916","26917","26918"],"output":["triggerid","description","status","value","state"],"expandExpression":true,"selectHosts":["host"]}' > "$RUN/after-triggers.json"
echo "== despues (id | host | status 0=activo | value | expresion expandida)"
jq -r '.[]|[.triggerid,.hosts[0].host,.status,.value,.expression]|@tsv' "$RUN/after-triggers.json"
echo "aplicado. Rollback: $0 rollback $RUN"

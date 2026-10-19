#!/usr/bin/env bash
# Event: 20261015_gitin2229-alerta-fatal-zabbix
# C8 - Zabbix 6.0.32 (sf-monitoreo.smartfran.com:8080; token en $ZABBIX_API_KEY). Agrega a los triggers de alerta las etiquetas de tarjeta del Chat que faltan:
#      el aviso de recuperacion de "Graylog: Platform FATAL detected" (2026-10-15 12:33-12:38 -03:00) llego con el titulo sin resolver: "El servicio {EVENT.TAGS.friendlyname} se ha normalizado".
#      La plantilla del Chat usa SVC_FRIENDLYNAME para el titulo del problema y friendlyname (minuscula) para el de la recuperacion (convencion de GITIN-2156); estos triggers no las tenian.
#      Objetos: triggers 26919 y 26920 (GITIN-2229, host Zabbix server) -> friendlyname = "Graylog FATAL Platform"
#               prototipo de trigger 26911 (GITIN-2222, plantilla ECS) -> friendlyname = "ECS tasks {#AWS.ECS.SERVICE.NAME}" (los triggers ya descubiertos lo reciben en la proxima pasada de descubrimiento, hasta ~3 h)
#      trigger.update / triggerprototype.update REEMPLAZAN la lista de etiquetas: se lee la lista actual y se le agregan las dos etiquetas (si faltan); el rollback reenvia la lista original guardada.
#      Modos: dry (por defecto, SOLO LECTURA) | apply (CAMBIA ESTADO) | rollback <carpeta c8-run-...> (CAMBIA ESTADO)
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
MODE="${1:-dry}"; SNAP="${2:-}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261015_gitin2229-alerta-fatal-zabbix/data"
TS=$(date -u +%Y%m%dT%H%M%SZ); RUN="$OUT/c8-run-$TS"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
if [ "$MODE" = "rollback" ]; then
  [ -f "$SNAP/before.json" ] || { echo "uso: $0 rollback <carpeta c8-run-...> (falta before.json)"; exit 1; }
  jq -c '.triggers[]' "$SNAP/before.json" | while read -r o; do call trigger.update "$(jq -nc --argjson o "$o" '{triggerid:$o.triggerid,tags:$o.tags}')" >/dev/null; echo "trigger $(jq -r .triggerid <<<"$o") restaurado"; done
  jq -c '.prototypes[]' "$SNAP/before.json" | while read -r o; do call triggerprototype.update "$(jq -nc --argjson o "$o" '{triggerid:$o.triggerid,tags:$o.tags}')" >/dev/null; echo "prototipo $(jq -r .triggerid <<<"$o") restaurado"; done
  echo "rollback aplicado desde $SNAP"; exit 0
fi
mkdir -p "$RUN"; echo "modo=$MODE | $TS | carpeta $RUN"
TR=$(call trigger.get '{"triggerids":["26919","26920"],"output":["triggerid","description"],"selectTags":["tag","value"],"selectHosts":["name"]}')
PR=$(call triggerprototype.get '{"triggerids":["26911"],"output":["triggerid","description"],"selectTags":["tag","value"]}')
jq -n --argjson t "$TR" --argjson p "$PR" '{triggers:$t,prototypes:$p}' > "$RUN/before.json"
jq -e '(.triggers|length)==2 and (.prototypes|length)==1 and (.triggers|all(.description|startswith("Graylog: Platform FATAL"))) and (.prototypes[0].description|contains("Running tasks below desired"))' "$RUN/before.json" >/dev/null || { echo "GUARDA: los objetos no son los esperados"; jq -c '[.triggers[],.prototypes[]|{triggerid,description}]' "$RUN/before.json"; exit 1; }
ADD() { jq -nc --argjson o "$1" --arg v "$2" '$o.tags as $t | (["SVC_FRIENDLYNAME","friendlyname"]|map(select(. as $n | ($t|map(.tag)|index($n))|not))) as $miss | $t + ($miss|map({tag:.,value:$v}))'; }
echo "== etiquetas actuales y resultado previsto"
jq -c '.triggers[]' "$RUN/before.json" | while read -r o; do echo "trigger $(jq -r .triggerid <<<"$o"): ahora $(jq -c '[.tags[]|"\(.tag)=\(.value)"]' <<<"$o") -> $(ADD "$o" 'Graylog FATAL Platform' | jq -c '[.[]|"\(.tag)=\(.value)"]')"; done
jq -c '.prototypes[]' "$RUN/before.json" | while read -r o; do echo "prototipo $(jq -r .triggerid <<<"$o"): ahora $(jq -c '[.tags[]|"\(.tag)=\(.value)"]' <<<"$o") -> $(ADD "$o" 'ECS tasks {#AWS.ECS.SERVICE.NAME}' | jq -c '[.[]|"\(.tag)=\(.value)"]')"; done
if [ "$MODE" != "apply" ]; then echo "DRY: no se cambio nada. Para aplicar: $0 apply"; exit 0; fi
jq -c '.triggers[]' "$RUN/before.json" | while read -r o; do call trigger.update "$(jq -nc --argjson o "$o" --argjson t "$(ADD "$o" 'Graylog FATAL Platform')" '{triggerid:$o.triggerid,tags:$t}')" >/dev/null; echo "trigger $(jq -r .triggerid <<<"$o") actualizado"; done
jq -c '.prototypes[]' "$RUN/before.json" | while read -r o; do call triggerprototype.update "$(jq -nc --argjson o "$o" --argjson t "$(ADD "$o" 'ECS tasks {#AWS.ECS.SERVICE.NAME}')" '{triggerid:$o.triggerid,tags:$t}')" >/dev/null; echo "prototipo $(jq -r .triggerid <<<"$o") actualizado"; done
TR2=$(call trigger.get '{"triggerids":["26919","26920"],"output":["triggerid"],"selectTags":["tag","value"]}'); PR2=$(call triggerprototype.get '{"triggerids":["26911"],"output":["triggerid"],"selectTags":["tag","value"]}')
jq -n --argjson t "$TR2" --argjson p "$PR2" '{triggers:$t,prototypes:$p}' > "$RUN/after.json"; jq -c '.triggers[],.prototypes[]|{triggerid,tags:[.tags[]|"\(.tag)=\(.value)"]}' "$RUN/after.json"
echo "aplicado. Rollback: $0 rollback $RUN"

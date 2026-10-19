#!/usr/bin/env bash
# Event: 20261015_gitin2229-alerta-fatal-zabbix
# C9 - Zabbix 6.0.32 (sf-monitoreo.smartfran.com:8080; token en $ZABBIX_API_KEY). Pedido del usuario: los triggers nuevos de ECS y de Graylog necesitan la etiqueta env:PROD para aparecer en el dashboard.
#      Convencion existente: etiqueta "env" con valor "PROD" (193 triggers del Zabbix ya la tienen, segun el inventario de etiquetas de GITIN-1961).
#      Objetos: triggers 26919 y 26920 (Graylog FATAL, GITIN-2229, host Zabbix server); prototipo de trigger 26911 (ECS, GITIN-2222, plantilla 10576), del que los triggers descubiertos 26915 y 26916
#      (host smartfran-pedidos-production) heredan las etiquetas en la proxima pasada de descubrimiento; ademas se INTENTA agregarla directamente a 26915 y 26916 (un host descubierto puede rechazarlo: se informa y se sigue).
#      Los triggers de healthcheck de GITIN-2239 (26921-26928) NO se incluyen: no fueron pedidos. trigger.update REEMPLAZA la lista de etiquetas: se lee la actual y solo se AGREGA env=PROD si falta.
#      Modos: dry (por defecto, SOLO LECTURA) | apply (CAMBIA ESTADO) | rollback <carpeta c9-run-...> (CAMBIA ESTADO: reenvia las listas originales)
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
MODE="${1:-dry}"; SNAP="${2:-}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261015_gitin2229-alerta-fatal-zabbix/data"
TS=$(date -u +%Y%m%dT%H%M%SZ); RUN="$OUT/c9-run-$TS"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
try() { if "$@" >/dev/null 2>"$RUN/err.tmp"; then echo "  OK"; else echo "  RECHAZADO: $(head -c 250 "$RUN/err.tmp")"; fi; }
if [ "$MODE" = "rollback" ]; then
  [ -f "$SNAP/before.json" ] || { echo "uso: $0 rollback <carpeta c9-run-...>"; exit 1; }; RUN="$SNAP"
  jq -c '.triggers[]' "$SNAP/before.json" | while read -r o; do echo "trigger $(jq -r .triggerid <<<"$o"):"; try call trigger.update "$(jq -nc --argjson o "$o" '{triggerid:$o.triggerid,tags:$o.tags}')"; done
  jq -c '.prototypes[]' "$SNAP/before.json" | while read -r o; do echo "prototipo $(jq -r .triggerid <<<"$o"):"; try call triggerprototype.update "$(jq -nc --argjson o "$o" '{triggerid:$o.triggerid,tags:$o.tags}')"; done
  echo "rollback hecho"; exit 0
fi
mkdir -p "$RUN"; echo "modo=$MODE | $TS | carpeta $RUN"
TR=$(call trigger.get '{"triggerids":["26919","26920","26915","26916"],"output":["triggerid","description"],"selectTags":["tag","value"],"selectHosts":["host"]}')
PR=$(call triggerprototype.get '{"triggerids":["26911"],"output":["triggerid","description"],"selectTags":["tag","value"]}')
jq -n --argjson t "$TR" --argjson p "$PR" '{triggers:$t,prototypes:$p}' > "$RUN/before.json"
jq -e '(.triggers|length)==4 and (.prototypes|length)==1' "$RUN/before.json" >/dev/null || { echo "GUARDA: no se encontraron los 4 triggers y el prototipo esperados"; exit 1; }
ADD() { jq -nc --argjson o "$1" 'if ($o.tags|map(select(.tag=="env" and .value=="PROD"))|length)>0 then $o.tags else $o.tags+[{tag:"env",value:"PROD"}] end'; }
echo "== resultado previsto (objeto | host | etiqueta env=PROD ya presente? | etiquetas tras el cambio)"
jq -c '.triggers[],.prototypes[]' "$RUN/before.json" | while read -r o; do echo "$(jq -r '.triggerid + " | " + ((.hosts[0].host)//"prototipo")' <<<"$o") | $(jq -r '[.tags[]|select(.tag=="env")]|length' <<<"$o") | $(ADD "$o" | jq -c '[.[]|"\(.tag)=\(.value)"]')"; done
if [ "$MODE" != "apply" ]; then echo "DRY: no se cambio nada. Para aplicar: $0 apply"; exit 0; fi
jq -c '.triggers[]' "$RUN/before.json" | while read -r o; do echo "trigger $(jq -r .triggerid <<<"$o"):"; try call trigger.update "$(jq -nc --argjson o "$o" --argjson t "$(ADD "$o")" '{triggerid:$o.triggerid,tags:$t}')"; done
jq -c '.prototypes[]' "$RUN/before.json" | while read -r o; do echo "prototipo $(jq -r .triggerid <<<"$o"):"; try call triggerprototype.update "$(jq -nc --argjson o "$o" --argjson t "$(ADD "$o")" '{triggerid:$o.triggerid,tags:$t}')"; done
call trigger.get '{"triggerids":["26919","26920","26915","26916"],"output":["triggerid"],"selectTags":["tag","value"],"selectHosts":["host"]}' > "$RUN/after-triggers.json"
call triggerprototype.get '{"triggerids":["26911"],"output":["triggerid"],"selectTags":["tag","value"]}' > "$RUN/after-prototype.json"
echo "== despues (objeto | tiene env=PROD)"; jq -r '.[]|[.triggerid,(([.tags[]|select(.tag=="env" and .value=="PROD")]|length)>0)]|@tsv' "$RUN/after-triggers.json" "$RUN/after-prototype.json"
echo "aplicado. Rollback: $0 rollback $RUN"

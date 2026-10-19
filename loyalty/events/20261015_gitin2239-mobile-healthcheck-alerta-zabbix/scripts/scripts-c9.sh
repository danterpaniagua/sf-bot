#!/usr/bin/env bash
# Event: 20261015_gitin2239-mobile-healthcheck-alerta-zabbix
# C9 - Zabbix 6.0.32 (sf-monitoreo.smartfran.com:8080; token en $ZABBIX_API_KEY). Pedido del usuario: agregar la etiqueta env=PROD a los triggers de healthcheck (26921-26928, GITIN-2239)
#      para que la accion 12 (env=PROD -> usuario ope_notify, Chat + Telegram) y el dashboard los tomen. Mismo patron que C9 de GITIN-2229.
#      trigger.update REEMPLAZA la lista de etiquetas: se lee la actual y solo se AGREGA env=PROD si falta. No se tocan expresiones ni otras etiquetas.
#      Efecto esperado: estos triggers pasan a notificar tambien por la accion 12 (ademas de las acciones 7/8/etc. que ya coincidan por sus etiquetas).
#      Modos: dry (por defecto, SOLO LECTURA) | apply (CAMBIA ESTADO) | rollback <carpeta c9-run-...> (CAMBIA ESTADO: reenvia las listas originales)
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
MODE="${1:-dry}"; SNAP="${2:-}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/loyalty/events/20261015_gitin2239-mobile-healthcheck-alerta-zabbix/data"
IDS='["26921","26922","26923","26924","26925","26926","26927","26928"]'
TS=$(date -u +%Y%m%dT%H%M%SZ); RUN="$OUT/c9-run-$TS"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
try() { if "$@" >/dev/null 2>"$RUN/err.tmp"; then echo "  OK"; else echo "  RECHAZADO: $(head -c 250 "$RUN/err.tmp")"; fi; }
if [ "$MODE" = "rollback" ]; then
  [ -f "$SNAP/before.json" ] || { echo "uso: $0 rollback <carpeta c9-run-...>"; exit 1; }; RUN="$SNAP"
  jq -c '.[]' "$SNAP/before.json" | while read -r o; do echo "trigger $(jq -r .triggerid <<<"$o"):"; try call trigger.update "$(jq -nc --argjson o "$o" '{triggerid:$o.triggerid,tags:$o.tags}')"; done
  echo "rollback hecho"; exit 0
fi
mkdir -p "$RUN"; echo "modo=$MODE | $TS | carpeta $RUN"
call trigger.get "$(jq -nc --argjson i "$IDS" '{triggerids:$i,output:["triggerid","description","status"],selectTags:["tag","value"],selectHosts:["host"]}')" > "$RUN/before.json"
jq -e 'length==8 and all(.[]; .description|test("ealthcheck"))' "$RUN/before.json" >/dev/null || { echo "GUARDA: no se encontraron 8 triggers con 'healthcheck' en el nombre"; exit 1; }
ADD() { jq -nc --argjson o "$1" 'if ($o.tags|map(select(.tag=="env" and .value=="PROD"))|length)>0 then $o.tags else $o.tags+[{tag:"env",value:"PROD"}] end'; }
echo "== resultado previsto (id | host | descripcion | env ya presente (cantidad) | etiquetas tras el cambio)"
jq -c '.[]' "$RUN/before.json" | while read -r o; do echo "$(jq -r '.triggerid + " | " + .hosts[0].host + " | " + .description' <<<"$o") | $(jq -r '[.tags[]|select(.tag=="env")]|length' <<<"$o") | $(ADD "$o" | jq -c '[.[]|"\(.tag)=\(.value)"]')"; done
if [ "$MODE" != "apply" ]; then echo "DRY: no se cambio nada. Para aplicar: $0 apply"; exit 0; fi
jq -c '.[]' "$RUN/before.json" | while read -r o; do echo "trigger $(jq -r .triggerid <<<"$o"):"; try call trigger.update "$(jq -nc --argjson o "$o" --argjson t "$(ADD "$o")" '{triggerid:$o.triggerid,tags:$t}')"; done
call trigger.get "$(jq -nc --argjson i "$IDS" '{triggerids:$i,output:["triggerid"],selectTags:["tag","value"]}')" > "$RUN/after.json"
echo "== despues (id | tiene env=PROD)"; jq -r '.[]|[.triggerid,(([.tags[]|select(.tag=="env" and .value=="PROD")]|length)>0)]|@tsv' "$RUN/after.json"
echo "aplicado. Rollback: $0 rollback $RUN"

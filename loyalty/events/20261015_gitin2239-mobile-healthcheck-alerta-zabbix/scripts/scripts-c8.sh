#!/usr/bin/env bash
# Event: 20261015_gitin2239-mobile-healthcheck-alerta-zabbix (GITIN-2239)
# C8 - Zabbix 6.0.32 (token en $ZABBIX_API_KEY). DESHABILITA (no borra) los dos triggers antiguos de WebServiceV2 en el host sfcg-monitoreo, reemplazados por los nuevos de GITIN-2239:
#      26860 "WebServiceV2 Response Time > 100ms" (Average): el item mide segundos y el umbral es 100, por lo que no puede dispararse (sin verificar la funcion exacta); sin etiquetas, no notifica.
#      26861 "WebServiceV2. HTTP Code not 200" (High): dispara solo con codigo > {$IIS_CODE_THRESS_NOK}=220 en una ventana de 20 min y no detecta timeouts; sin etiquetas, no notifica.
#      Deshabilitar conserva el historial y permite volver atras. Modos: dry (por defecto, SOLO LECTURA) | apply (CAMBIA ESTADO) | rollback (CAMBIA ESTADO: los vuelve a habilitar)
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
MODE="${1:-dry}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/loyalty/events/20261015_gitin2239-mobile-healthcheck-alerta-zabbix/data"; TS=$(date -u +%Y%m%dT%H%M%SZ); RUN="$OUT/c8-run-$TS"; mkdir -p "$RUN"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
call trigger.get '{"triggerids":["26860","26861"],"output":["triggerid","description","status","value","priority"],"selectHosts":["host"],"selectTags":["tag","value"]}' > "$RUN/before.json"
echo "modo=$MODE | $TS"; jq -r '.[]|[.triggerid,.hosts[0].host,.description,("status="+.status),("value="+.value),("etiquetas="+(.tags|length|tostring))]|@tsv' "$RUN/before.json"
jq -e 'length==2 and all(.hosts[0].host=="sfcg-monitoreo")' "$RUN/before.json" >/dev/null || { echo "GUARDA: los triggers no son los esperados"; exit 1; }
if [ "$MODE" = "rollback" ]; then for t in 26860 26861; do call trigger.update "{\"triggerid\":\"$t\",\"status\":0}" >/dev/null; echo "trigger $t habilitado"; done; exit 0; fi
if [ "$MODE" != "apply" ]; then echo "DRY: no se cambio nada. Para aplicar: $0 apply"; exit 0; fi
for t in 26860 26861; do call trigger.update "{\"triggerid\":\"$t\",\"status\":1}" >/dev/null; echo "trigger $t deshabilitado"; done
call trigger.get '{"triggerids":["26860","26861"],"output":["triggerid","status"]}' > "$RUN/after.json"; jq -c '.[]' "$RUN/after.json"
echo "aplicado. Rollback: $0 rollback"

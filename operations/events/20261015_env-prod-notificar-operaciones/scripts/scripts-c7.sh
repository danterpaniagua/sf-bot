#!/usr/bin/env bash
# Event: 20261015_env-prod-notificar-operaciones
# C7 - Zabbix 6.0.32 (sf-monitoreo.smartfran.com:8080; token en $ZABBIX_API_KEY). SOLO LECTURA.
#      Revisa el parametro Token del tipo de medio Telegram (16) SIN imprimirlo: largo y si tiene forma de token de bot (<numeros>:<letras/numeros/_/->). Ademas, largo y forma de "To".
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
echo "run $(date -u +%Y%m%dT%H%M%SZ)"
jq -n --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:"mediatype.get",params:{mediatypeids:["16"],output:["name","status","parameters"]},auth:$a,id:1}' \
 | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" \
 | jq -r '.result[0]|"tipo: \(.name) | status=\(.status) (0=habilitado)",
   (.parameters[]|select(.name=="Token")|"Token: largo \(.value|length) | forma de token de bot valida: \(.value|test("^[0-9]+:[A-Za-z0-9_-]+$")) | espacios o saltos de linea: \(.value|test("\\s"))"),
   (.parameters[]|select(.name=="Token")|.value as $v|"estructura (sin valores): empieza con 'bot': \($v|test("^bot";"i")) | comillas: \($v|test("[\"'"'"']")) | angulos <>: \($v|test("[<>]")) | dos puntos: \($v|[match(":";"g")]|length) | largo antes de ':': \($v|split(":")[0]|length) | largo despues del primer ':': \($v|split(":")[1:]|join(":")|length) | caracteres fuera de [A-Za-z0-9_:-]: \($v|[match("[^A-Za-z0-9_:-]";"g")]|length)"),
   (.parameters[]|select(.name=="To")|"To: usa {ALERT.SENDTO}: \(.value|test("ALERT.SENDTO"))")'
echo "== medio Telegram de ope_notify (estructura del chat id, sin el valor completo)"
jq -n --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:"user.get",params:{userids:["16"],output:["username"],selectMedias:["mediatypeid","sendto"]},auth:$a,id:1}' \
 | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" \
 | jq -r '.result[0].medias[]|select(.mediatypeid=="16")|.sendto|tostring|"signo \(if startswith("-") then "-" else "+" end) | largo \(length) | empieza con -100 (supergrupo): \(startswith("-100")) | termina en \(.[-4:])"'

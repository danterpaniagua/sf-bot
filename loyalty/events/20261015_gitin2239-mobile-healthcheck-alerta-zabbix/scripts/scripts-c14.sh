#!/usr/bin/env bash
# Event: 20261015_gitin2239-mobile-healthcheck-alerta-zabbix (GITIN-2239)
# C14 - Zabbix 6.0.32 (sf-monitoreo.smartfran.com:8080; token en $ZABBIX_API_KEY). SOLO LECTURA.
#       Pedido del usuario (2026-10-16): "get what is in each web scenario of zabbix proxy". El host del proxy es sfcg-monitoreo (10610; en las tarjetas aparece como "Zabbix Proxy").
#       Lista los escenarios web (httptest) de ese host y, por informacion, cuantos escenarios tiene el resto de los hosts. Por escenario: nombre, estado, intervalo, reintentos y, por paso:
#       numero, nombre, URL SIN la cadena de consulta (puede llevar tokens), codigos de estado requeridos, texto requerido (solo si existe: si/no), tiempo de espera, seguir redirecciones,
#       y SOLO la CANTIDAD de variables, cabeceras y campos de consulta del escenario/paso y si el paso tiene cuerpo POST (si/no). NO se imprime ni se guarda ningun valor de variables, cabeceras ni cuerpo POST
#       (un paso de login suele llevar credenciales): la respuesta de la API se procesa en memoria y solo se guarda la salida filtrada.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
HOSTID=10610
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
echo "run $(date -u +%Y%m%dT%H%M%SZ) | escenarios web del host $HOSTID (sfcg-monitoreo, 'Zabbix Proxy')"
call httptest.get "$(jq -nc --arg h "$HOSTID" '{hostids:[$h],output:["httptestid","name","status","delay","retries","variables","headers","agent"],selectSteps:["no","name","url","status_codes","required","timeout","follow_redirects","posts","variables","headers","query_fields"],selectHosts:["host"]}')" \
 | jq -r '
   def cnt(x): (x // [] | if type=="array" then length else 0 end);
   sort_by(.name)[] as $t
   | "== \($t.name) | estado=\(if $t.status=="0" then "activo" else "deshabilitado" end) | intervalo=\($t.delay) | reintentos=\($t.retries) | variables del escenario=\(cnt($t.variables)) | cabeceras del escenario=\(cnt($t.headers))",
     ($t.steps|sort_by(.no|tonumber)[]
      | "   paso \(.no): \(.name) | \(.url|split("?")[0]) | consulta=\(if (.url|contains("?")) then "si (no se muestra)" else "no" end) | codigos=\(.status_codes) | texto requerido=\(if .required=="" then "no" else "si" end) | timeout=\(.timeout) | redirecciones=\(if .follow_redirects=="1" then "si" else "no" end) | cuerpo POST=\(if (.posts|tostring)=="" or (.posts|tostring)=="[]" then "no" else "si (no se muestra)" end) | variables=\(cnt(.variables)) | cabeceras=\(cnt(.headers)) | campos de consulta=\(cnt(.query_fields))")'
echo "== cantidad de escenarios por host (todos los hosts)"
call httptest.get '{"output":["httptestid"],"selectHosts":["host"]}' | jq -r 'group_by(.hosts[0].host)[]|"\(.[0].hosts[0].host): \(length)"'

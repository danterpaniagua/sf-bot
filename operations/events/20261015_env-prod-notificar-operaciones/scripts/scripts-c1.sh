#!/usr/bin/env bash
# Event: 20261015_env-prod-notificar-operaciones
# C1 - Zabbix 6.0.32 (sf-monitoreo.smartfran.com:8080; token en $ZABBIX_API_KEY). SOLO LECTURA.
#      Pedido: todo problema con la etiqueta env=PROD debe notificar al espacio de Chat OPERACIONES.
#      Lee (1) las acciones de triggers (condiciones y operaciones), (2) los medios del usuario 9, comparando SIN imprimir ni guardar el valor si el espacio/key/token
#      del webhook dado en $OPERACIONES_CHAT_URL coinciden con el medio ya configurado (solo imprime true/false), (3) cuantos triggers monitoreados tienen env=PROD,
#      por severidad, por host y cuantos ya tienen las etiquetas que usan las acciones 7/11 y la tarjeta (SVC_FRIENDLYNAME).
#      Ambas URL se exportan en la terminal del usuario; este script NO lo escribe en ningun archivo.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
# OPERACIONES_CHAT_URL y BOTTEST_CHAT_URL son opcionales: sin ellas se omite la comparacion de webhooks.
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/operations/events/20261015_env-prod-notificar-operaciones/data"
TS=$(date -u +%Y%m%dT%H%M%SZ); RUN="$OUT/c1-run-$TS"; mkdir -p "$RUN"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
echo "run $TS | carpeta $RUN"
echo "== 1. acciones de triggers (id | nombre | status 0=habilitada | condiciones | operaciones: tipo/usuarios/grupos/medio)"
call action.get '{"output":["actionid","name","status","pause_suppressed","esc_period"],"filter":{"eventsource":"0"},"selectFilter":"extend","selectOperations":"extend","selectRecoveryOperations":"extend","selectUpdateOperations":"extend"}' > "$RUN/actions.json"
jq -r '.[]|[.actionid,.name,("status="+.status),
  ("cond: "+([.filter.conditions[]?|"\(.conditiontype):\(.operator):\(.value)\(if .value2 != "" then "/"+.value2 else "" end)"]|join(" ; "))),
  ("ops: "+([.operations[]?|"t\(.operationtype) usr=\([.opmessage_usr[]?.userid]|join(",")) grp=\([.opmessage_grp[]?.usrgrpid]|join(",")) media=\(.opmessage.mediatypeid // "-")"]|join(" | ")))]|@tsv' "$RUN/actions.json"
echo "== 2. medios del usuario 9 (sin sendto) y comparacion con \$OPERACIONES_CHAT_URL (solo true/false)"
U=$(call user.get '{"userids":["9"],"output":["userid","username"],"selectMedias":["mediatypeid","sendto","active","severity","period"],"selectUsrgrps":["usrgrpid","name"]}')
jq '[.[]|{userid,username,usrgrps,medias:[.medias[]|del(.sendto)]}]' <<<"$U" > "$RUN/user9-medias-sin-sendto.json"
jq -r '.[]|.medias[]|"media \(.mediatypeid) | active=\(.active) (0=activo) | severity-mask=\(.severity) | periodo=\(.period)"' "$RUN/user9-medias-sin-sendto.json"
for VAR in OPERACIONES_CHAT_URL BOTTEST_CHAT_URL; do
  URLV="${!VAR:-}"; [ -n "$URLV" ] || { echo "$VAR no definida: se omite"; continue; }
  echo "-- comparacion con $VAR"
  jq -r --arg url "$URLV" '
    def sp: capture("spaces/(?<s>[^/?]+)").s? // "";
    def kv($k): capture("[?&]\($k)=(?<v>[^&]+)").v? // "";
    [.[]|.medias[]] as $m | ($url|sp) as $us | ($url|kv("key")) as $uk | ($url|kv("token")) as $ut |
    ($m|map(select(.mediatypeid=="38")|.sendto|tostring)) as $s38 |
    "  URL dada: espacio presente=\($us!=""), key presente=\($uk!=""), token presente=\($ut!="")",
    "  medios tipo 38 del usuario 9: \($s38|length)",
    "  mismo espacio que algun medio 38 del usuario 9: \($s38|map(sp==$us)|any)",
    "  misma key: \($s38|map(kv("key")==$uk)|any) | mismo token: \($s38|map(kv("token")==$ut)|any)"' <<<"$U"
done
echo "== 3. triggers monitoreados con env=PROD"
call trigger.get '{"monitored":true,"output":["triggerid","description","priority","status"],"tags":[{"tag":"env","value":"PROD","operator":"1"}],"evaltype":"0","selectTags":["tag","value"],"selectHosts":["host"]}' > "$RUN/triggers-env-prod.json"
jq -r 'length|"total con env=PROD: \(.)"' "$RUN/triggers-env-prod.json"
echo "por severidad (0 sin clasificar, 1 info, 2 warning, 3 average, 4 high, 5 disaster):"
jq -r 'group_by(.priority)|.[]|"  \(.[0].priority): \(length)"' "$RUN/triggers-env-prod.json"
echo "con SVC_FRIENDLYNAME: $(jq '[.[]|select(any(.tags[];.tag=="SVC_FRIENDLYNAME"))]|length' "$RUN/triggers-env-prod.json") | con action ~ GCHAT: $(jq '[.[]|select(any(.tags[];.tag=="action" and (.value|test("GCHAT"))))]|length' "$RUN/triggers-env-prod.json")"
echo "por host:"
jq -r '[.[]|.hosts[0].host]|group_by(.)|map({h:.[0],n:length})|sort_by(-.n)|.[]|"  \(.n)\t\(.h)"' "$RUN/triggers-env-prod.json"
echo "guardado en $RUN (sin ningun valor de sendto)"

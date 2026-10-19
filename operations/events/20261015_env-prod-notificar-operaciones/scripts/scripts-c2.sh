#!/usr/bin/env bash
# Event: 20261015_env-prod-notificar-operaciones
# C2 - Zabbix 6.0.32 (sf-monitoreo.smartfran.com:8080; token en $ZABBIX_API_KEY). SOLO LECTURA.
#      Revisa el usuario nuevo "ope_notify": rol, grupos, medios (sin sendto), si su webhook coincide con $OPERACIONES_CHAT_URL (solo true/false),
#      derechos y filtros de etiquetas de sus grupos, y si puede ver (permiso de lectura) los hosts de los triggers con env=PROD.
#      Sin acceso de lectura a un host, el usuario NO recibe sus problemas aunque la accion lo incluya.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/operations/events/20261015_env-prod-notificar-operaciones/data"
TS=$(date -u +%Y%m%dT%H%M%SZ); RUN="$OUT/c2-run-$TS"; mkdir -p "$RUN"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
echo "run $TS | carpeta $RUN"
U=$(call user.get '{"filter":{"username":"ope_notify"},"output":["userid","username","roleid","autologin","lang"],"selectMedias":["mediatypeid","sendto","active","severity","period"],"selectUsrgrps":["usrgrpid","name","users_status","gui_access"],"selectRole":["roleid","name","type"]}')
jq -e 'length==1' <<<"$U" >/dev/null || { echo "AVISO: usuario ope_notify no encontrado (o hay mas de uno)"; exit 1; }
jq '[.[]|{userid,username,roleid,role,usrgrps,medias:[.medias[]|del(.sendto)]}]' <<<"$U" > "$RUN/user-sin-sendto.json"
UID_=$(jq -r '.[0].userid' <<<"$U")
echo "== 1. usuario: id | rol | grupos | medios (mediatype, active 0=activo, mascara de severidad 63=todas, periodo)"
jq -r '.[0]|"id \(.userid) | rol \(.role.name) (type \(.role.type)) | grupos: \([.usrgrps[]|"\(.usrgrpid) \(.name) (users_status=\(.users_status))"]|join("; "))",
  (.medias[]|"medio \(.mediatypeid) | active=\(.active) | severity=\(.severity) | periodo=\(.period)")' "$RUN/user-sin-sendto.json"
if [ -n "${OPERACIONES_CHAT_URL:-}" ]; then
  echo "== 2. webhook de ope_notify vs OPERACIONES_CHAT_URL (solo true/false)"
  jq -r --arg url "$OPERACIONES_CHAT_URL" '
    def sp: capture("spaces/(?<s>[^/?]+)").s? // "";
    def kv($k): capture("[?&]\($k)=(?<v>[^&]+)").v? // "";
    [.[0].medias[]|select(.mediatypeid=="38")|.sendto|tostring] as $s |
    "medios tipo 38: \($s|length) | mismo espacio: \($s|map(sp==($url|sp))|any) | misma key: \($s|map(kv("key")==($url|kv("key")))|any) | mismo token: \($s|map(kv("token")==($url|kv("token")))|any)"' <<<"$U"
else echo "== 2. OPERACIONES_CHAT_URL no definida: se omite la comparacion"; fi
echo "== 2b. Telegram (media type 16) y Chat (38): estado del tipo de medio y medio del usuario (sin valores secretos)"
call mediatype.get '{"mediatypeids":["16","38"],"output":["mediatypeid","name","type","status","parameters"]}' > "$RUN/mediatypes-raw.json"
jq '[.[]|del(.parameters)+{parametros:[(.parameters//[])[]?|{name,vacio:((.value//"")==""),placeholder:((.value//"")|test("PLACE|YOUR|TOKEN";"i"))}]}]' "$RUN/mediatypes-raw.json" > "$RUN/mediatypes.json"; rm -f "$RUN/mediatypes-raw.json"
jq -r '.[]|"tipo \(.mediatypeid) \(.name) | status=\(.status) (0=habilitado) | parametros (solo nombre; vacio/placeholder = valor sin configurar): \([.parametros[]?|"\(.name) vacio=\(.vacio) placeholder=\(.placeholder)"]|join("; "))"' "$RUN/mediatypes.json"
jq -r '.[0].medias[]|select(.mediatypeid=="16")|"medio Telegram de ope_notify: sendto con \(.sendto|tostring|length) caracteres, vacio=\((.sendto|tostring)==""), numerico=\((.sendto|tostring)|test("^-?[0-9]+$")) | active=\(.active) | severity=\(.severity)"' <<<"$U"
echo "== 3. derechos y filtros de etiquetas de sus grupos"
call usergroup.get "$(jq -nc --arg u "$UID_" '{userids:[$u],output:["usrgrpid","name"],selectRights:["id","permission"],selectTagFilters:["groupid","tag","value"]}')" > "$RUN/usergroups.json"
jq -r '.[]|"grupo \(.usrgrpid) \(.name): derechos=\(.rights|length) | filtros de etiqueta=\(.tag_filters|length)"' "$RUN/usergroups.json"
echo "-- filtros de etiqueta (si hay, limitan los problemas visibles y notificados): grupo de hosts | tag | value"
jq -r '.[]|.tag_filters[]?|"  \(.groupid) | \(.tag) | \(.value)"' "$RUN/usergroups.json"
echo "== 4. acceso a los hosts de los triggers con env=PROD"
call trigger.get '{"monitored":true,"output":["triggerid"],"tags":[{"tag":"env","value":"PROD","operator":"1"}],"evaltype":"0","selectHosts":["hostid","host"]}' > "$RUN/triggers-env-prod.json"
HIDS=$(jq -c '[.[].hosts[].hostid]|unique' "$RUN/triggers-env-prod.json")
call host.get "$(jq -nc --argjson h "$HIDS" '{hostids:$h,output:["hostid","host"],selectGroups:["groupid"]}')" > "$RUN/hosts.json"
jq -n --slurpfile h "$RUN/hosts.json" --slurpfile g "$RUN/usergroups.json" '
  ([$g[0][]|.rights[]]|group_by(.id)|map({key:.[0].id, value:(map(.permission|tonumber)|if any(.==0) then 0 else max end)})|from_entries) as $perm |
  [$h[0][]|{host, p:([.groups[].groupid|$perm[.]//null]|map(select(.!=null))|if length==0 then null elif any(.==0) then 0 else max end)}] as $r |
  "hosts con env=PROD: \($r|length) | con lectura (>=2): \($r|map(select(.p!=null and .p>=2))|length) | sin acceso o denegado: \($r|map(select(.p==null or .p<2))|length)",
  ($r|map(select(.p==null or .p<2))|.[]|"  sin acceso: \(.host) (permiso \(.p))")' -r
echo "guardado en $RUN (sin sendto)"

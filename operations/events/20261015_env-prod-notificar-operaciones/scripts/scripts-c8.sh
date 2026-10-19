#!/usr/bin/env bash
# Event: 20261015_env-prod-notificar-operaciones
# C8 - Zabbix 6.0.32 (sf-monitoreo.smartfran.com:8080; token en $ZABBIX_API_KEY). Las alertas de la accion 12 figuran "enviadas" en Zabbix pero el usuario dice que ninguna llega al Chat.
#      Modos:
#        compare      (SOLO LECTURA) compara el medio de Chat (tipo 38) del usuario 9 (operaciones_msg) y del 16 (ope_notify): forma de la ruta del webhook, largo de la clave y del token,
#                     ultimos 4 caracteres del espacio, y si son IGUALES entre los dos usuarios (true/false). No imprime sendto ni ningun secreto.
#        send <userid> (CAMBIA ESTADO: publica UN mensaje de prueba, "ignorar", en el espacio del webhook de ese usuario, 9 o 16) imprime solo el codigo HTTP y el texto de error recortado.
#                     El webhook se lee en memoria desde Zabbix y se pasa a curl por stdin (-K -), no queda en la lista de procesos.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
MODE="${1:-}"; UID_T="${2:-}"
case "$MODE" in compare|send) ;; *) echo "uso: $0 compare | send 9|16"; exit 1;; esac
[ "$MODE" = "compare" ] || case "$UID_T" in 9|16) ;; *) echo "uso: $0 send 9|16"; exit 1;; esac
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
TS=$(date -u +%Y%m%dT%H%M%SZ)
get() { jq -n --arg a "$ZABBIX_API_KEY" --argjson ids "$1" '{jsonrpc:"2.0",method:"user.get",params:{userids:$ids,output:["userid","username"],selectMedias:["mediatypeid","sendto","active"]},auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
if [ "$MODE" = "compare" ]; then
  echo "run $TS | comparacion de los medios de Chat (tipo 38) de los usuarios 9 y 16 | solo true/false, largos y ultimos 4 del espacio"
  get '["9","16"]' | jq -r '
    def info($u): ([$u.medias[]|select(.mediatypeid=="38")] ) as $m
      | if ($m|length)==0 then "usuario \($u.userid): SIN medio de Chat"
        else ($m[0].sendto|tostring) as $s
          | (try ($s|capture("spaces/(?<sp>[^/?]+)")|.sp) catch "") as $sp
          | (try ($s|capture("key=(?<k>[^&]+)")|.k) catch "") as $k
          | (try ($s|capture("token=(?<t>[^&]+)")|.t) catch "") as $t
          | "usuario \($u.userid) (\($u.username)): medios de Chat=\($m|length) | active=\($m[0].active) | largo sendto=\($s|length) | empieza con http=\($s|startswith("http")) | empieza con /v1/spaces/=\($s|startswith("/v1/spaces/")) | espacio: largo \($sp|length), termina en \($sp[-4:]) | clave: largo \($k|length) | token: largo \($t|length)"
        end;
    (.[]|info(.)),
    ( [ .[] | {u:.userid, s:([.medias[]|select(.mediatypeid=="38")|.sendto|tostring][0] // "")} ] ) as $x
    | ($x|map(select(.u=="9"))[0].s) as $a | ($x|map(select(.u=="16"))[0].s) as $b
    | "sendto completo IGUAL entre usuario 9 y 16: \(($a|length)>0 and $a==$b)",
      "espacio IGUAL entre usuario 9 y 16: \((try ($a|capture("spaces/(?<sp>[^/?]+)")|.sp) catch "x1") == (try ($b|capture("spaces/(?<sp>[^/?]+)")|.sp) catch "x2"))"'
  exit 0
fi
R=$(get "[\"$UID_T\"]" | jq -r '.[0].medias[]|select(.mediatypeid=="38")|.sendto|tostring' | head -1)
[ -n "$R" ] || { echo "el usuario $UID_T no tiene medio de Chat"; exit 1; }
case "$R" in http*) URL="$R";; *) URL="https://chat.googleapis.com$R";; esac
BODY=$(jq -nc --arg t "Prueba de webhook (Zabbix usuario $UID_T) $(date -u +%H:%M:%S) UTC - ignorar" '{text:$t}')
TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT
CODE=$(printf 'url = "%s"\n' "$URL" | curl -sS -K - -o "$TMP" -w '%{http_code}' -H 'Content-Type: application/json; charset=UTF-8' -d "$BODY" || true)
echo "run $TS | send usuario $UID_T | codigo HTTP: $CODE"
echo "respuesta (recortada, sin URLs): $(head -c 300 "$TMP" | tr '\n' ' ' | sed -E 's#https?://[^ ]+#<url>#g; s/(key|token)=[^& "]+/\1=<x>/g')"

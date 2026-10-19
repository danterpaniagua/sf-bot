#!/usr/bin/env bash
# Event: 20261015_env-prod-notificar-operaciones
# C6 - Prueba del token del bot de Telegram, FUERA de Zabbix (llama directo a api.telegram.org). El token se pide por teclado (sin eco) y NO se guarda ni se imprime.
#      Modos: me   (SOLO LECTURA: getMe; valida que el token sea valido y muestra el nombre del bot)
#             send (ENVIA UN MENSAJE REAL de prueba al chat de Telegram de ope_notify; el chat id se lee del medio del usuario 16 en Zabbix, en memoria, sin imprimirlo; requiere ZABBIX_API_KEY)
#             updates (SOLO LECTURA: getUpdates; lista los chats que el bot vio en las ultimas ~24 h con tipo, titulo, signo y ultimos 4 digitos del id, para encontrar el chat correcto)
#      Salida: solo ok / codigo de error / descripcion de Telegram (nunca el token ni el chat id).
set -euo pipefail
trap 'echo "FALLO en linea $LINENO" >&2' ERR
MODE="${1:-me}"
case "$MODE" in me|send|updates) ;; *) echo "uso: $0 me|send|updates"; exit 1;; esac
printf 'Token del bot de Telegram (no se muestra): ' >/dev/tty; IFS= read -rs TOKEN </dev/tty; printf '\n' >/dev/tty
TOKEN=$(printf '%s' "$TOKEN" | tr -d '[:space:]"'"'"'')   # quita espacios, CR/LF y comillas pegadas por error
[ -n "$TOKEN" ] || { echo "token vacio"; exit 1; }
[[ "$TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]] || { echo "FORMATO INVALIDO: el token debe ser <numeros>:<letras/numeros/_/-> (sin prefijo 'bot', sin espacios). Largo recibido: ${#TOKEN} caracteres"; exit 1; }
tg() { # $1 = metodo, $2... = campos de formulario para curl; la URL (con el token) va por stdin, no en la linea de comandos
  local m="$1"; shift
  printf 'url = "https://api.telegram.org/bot%s/%s"\n' "$TOKEN" "$m" | curl -sS --max-time 20 -K - "$@"
}
echo "modo=$MODE | $(date -u +%Y%m%dT%H%M%SZ)"
if [ "$MODE" = "me" ]; then
  R=$(tg getMe)
  jq -r 'if .ok then "OK: token valido | bot: \(.result.username) | es bot: \(.result.is_bot)" else "ERROR \(.error_code): \(.description)" end' <<<"$R"
  exit 0
fi
if [ "$MODE" = "updates" ]; then
  R=$(tg getUpdates)
  jq -r 'if .ok|not then "ERROR \(.error_code): \(.description)" else
    ([.result[]|(.message // .channel_post // .my_chat_member // .edited_message // empty)|.chat]|unique_by(.id)) as $c |
    "chats vistos por el bot: \($c|length)",
    ($c[]|"  tipo \(.type) | titulo/usuario: \(.title // .username // .first_name // "-") | signo \(if .id<0 then "-" else "+" end) | largo del id \(.id|tostring|length) | termina en \(.id|tostring|.[-4:])") end' <<<"$R"
  exit 0
fi
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
CHAT=$(jq -n --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:"user.get",params:{userids:["16"],output:["username"],selectMedias:["mediatypeid","sendto"]},auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq -r '.result[0].medias[]|select(.mediatypeid=="16")|.sendto|tostring' | head -1)
[[ "$CHAT" =~ ^-?[0-9]+$ ]] || { echo "no se obtuvo un chat id numerico del medio Telegram de ope_notify"; exit 1; }
R=$(tg sendMessage --data-urlencode "chat_id=$CHAT" --data-urlencode "text=Prueba de token (Zabbix ope_notify) $(date -u +%H:%M:%S) UTC - ignorar")
jq -r 'if .ok then "OK: mensaje enviado al chat de ope_notify" else "ERROR \(.error_code): \(.description)" end' <<<"$R"

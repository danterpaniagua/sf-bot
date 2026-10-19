#!/usr/bin/env bash
# Event: 20261013_gitin2218-graylog-visibilidad
# C10 — Solo lectura. ¿Por que Sales casi no tiene ElapsedMilliseconds (1 de 6.547 lineas con StatusCode en C9)?
#       Baja 5 mensajes de Sales con StatusCode y SIN ElapsedMilliseconds (y hasta 3 que si lo tengan) de la ultima hora y muestra, SIN valores salvo el elapsed:
#       los nombres de las propiedades del campo Properties (JSON stringificado por Logstash) y el valor y el tipo JSON de ElapsedMilliseconds/Elapsed* dentro de el.
#       La respuesta cruda (puede traer datos de usuario) se guarda en un archivo temporal fuera del repo y se borra al terminar; en data/ queda solo el resumen.
#       Salida data/c10-summary.txt. Token en $GRAYLOG_API_KEY (nunca literal).
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${GRAYLOG_API_KEY:?definir GRAYLOG_API_KEY en el entorno}"
BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
OUT="/home/dpaniagua/Documentos/git/bots/cloud/events/20261013_gitin2218-graylog-visibilidad/data"
TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT
GET() { curl -sS -f -u "$GRAYLOG_API_KEY:token" -H 'Accept: application/json' "$@"; }
POST() { curl -sS -f -u "$GRAYLOG_API_KEY:token" -H 'Content-Type: application/json' -H 'Accept: application/json' -H 'X-Requested-By: cli' "$@"; }
iso() { date -u -d "$1" +"%Y-%m-%dT%H:%M:%S.000Z"; }
NOW=$(iso now); H1=$(iso "1 hour ago")
BODY=$(jq -nc --arg f "$H1" --arg t "$NOW" '
  def q($id; $qs; $n): {id:$id, query:{type:"elasticsearch", query_string:$qs}, timerange:{type:"absolute", from:$f, to:$t},
                        search_types:[{id:"m", type:"messages", limit:$n, offset:0}]};
  {queries:[ q("without"; "Service:Sales AND _exists_:StatusCode AND NOT _exists_:ElapsedMilliseconds AND NOT category:AppServiceHTTPLogs"; 5),
             q("with";    "Service:Sales AND _exists_:ElapsedMilliseconds AND NOT category:AppServiceHTTPLogs"; 3) ]}')
SID=$(POST -d "$BODY" "$BASE/views/search" | jq -r '.id'); JID=$(POST -d '{}' "$BASE/views/search/$SID/execute" | jq -r '.id')
for i in $(seq 1 60); do GET "$BASE/views/search/status/$JID" > "$TMP"; [ "$(jq -r '.execution.done // false' "$TMP")" = true ] && break; sleep 3; done
{
echo "ventana UTC $H1..$NOW"
for K in without with; do
  echo "== $K ElapsedMilliseconds: $(jq -r --arg k $K '.results[$k].search_types.m.total_results' "$TMP") mensajes en total; se muestran hasta $(jq -r --arg k $K '.results[$k].search_types.m.messages | length' "$TMP")"
  jq -r --arg k $K '.results[$k].search_types.m.messages[] | .message as $m |
    "campos de nivel superior: " + ($m | keys | map(select(test("^(Elapsed|StatusCode|Path|Method|Properties|full_message|message|Service|SourceContext|AppLevel|category)"))) | join(",")),
    "  ElapsedMilliseconds top-level: " + ($m.ElapsedMilliseconds | tostring) + " (" + ($m.ElapsedMilliseconds | type) + ")",
    "  StatusCode: " + ($m.StatusCode | tostring) + " (" + ($m.StatusCode | type) + ")",
    "  Properties: " + (($m.Properties | type)) + (if ($m.Properties | type) == "string" then
        " | claves: " + (try ($m.Properties | fromjson | keys | join(",")) catch "no es JSON") +
        " | Elapsed*: " + (try ($m.Properties | fromjson | to_entries | map(select(.key | test("Elapsed"; "i")) | "\(.key)=\(.value|tostring) (\(.value|type))") | join(";")) catch "-")
      else "" end)' "$TMP"
done
} | tee "$OUT/c10-summary.txt"
echo listo

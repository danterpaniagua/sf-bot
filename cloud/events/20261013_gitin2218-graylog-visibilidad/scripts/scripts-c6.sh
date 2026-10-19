#!/usr/bin/env bash
# Event: 20261013_gitin2218-graylog-visibilidad
# C6 — Solo lectura. Comprueba la sintaxis de las consultas de los widgets de StatusCode y de Endpoints, para Service:Sales,
#      ultima hora. Imprime por variante: estado, errores y total de mensajes (messages.total_results).
#      a base (la actual) | b _exists_ separados con StatusCode | c _exists_:("Method" AND "StatusCode") | d igual sin comillas
#      e separados con Path | f _exists_:("Method" AND "Path") | g _exists_:("Method" AND "EndPoint") (campo que no existe: debe dar 0)
#      Salidas data/c6-result.json. Token en $GRAYLOG_API_KEY (nunca literal).
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${GRAYLOG_API_KEY:?definir GRAYLOG_API_KEY en el entorno}"
BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
OUT="/home/dpaniagua/Documentos/git/bots/cloud/events/20261013_gitin2218-graylog-visibilidad/data"
GET() { curl -sS -f -u "$GRAYLOG_API_KEY:token" -H 'Accept: application/json' "$@"; }
POST() { curl -sS -f -u "$GRAYLOG_API_KEY:token" -H 'Content-Type: application/json' -H 'Accept: application/json' -H 'X-Requested-By: cli' "$@"; }
iso() { date -u -d "$1" +"%Y-%m-%dT%H:%M:%S.000Z"; }
NOW=$(iso now); H1=$(iso "1 hour ago")
TAIL='NOT Method: ("OPTIONS") AND Service:Sales'
declare -A Q=(
  [a]="_exists_:Method AND $TAIL"
  [b]="_exists_:Method AND _exists_:StatusCode AND $TAIL"
  [c]="_exists_:(\"Method\" AND \"StatusCode\") AND $TAIL"
  [d]="_exists_:(Method AND StatusCode) AND $TAIL"
  [e]="_exists_:Method AND _exists_:Path AND $TAIL"
  [f]="_exists_:(\"Method\" AND \"Path\") AND $TAIL"
  [g]="_exists_:(\"Method\" AND \"EndPoint\") AND $TAIL"
)
BODY=$(jq -nc --arg f "$H1" --arg t "$NOW" --argjson qs "$(for k in "${!Q[@]}"; do jq -nc --arg k "$k" --arg v "${Q[$k]}" '{($k):$v}'; done | jq -sc 'add')" '
  {queries: [$qs | to_entries[] | {id:.key, query:{type:"elasticsearch", query_string:.value}, timerange:{type:"absolute", from:$f, to:$t},
     search_types:[{id:"m", type:"messages", limit:1, offset:0}]}]}')
echo "$BODY" > "$OUT/c6-request.json"
SID=$(POST -d "$BODY" "$BASE/views/search" | jq -r '.id'); JID=$(POST -d '{}' "$BASE/views/search/$SID/execute" | jq -r '.id')
for i in $(seq 1 40); do GET "$BASE/views/search/status/$JID" > "$OUT/c6-result.json"; [ "$(jq -r '.execution.done // false' "$OUT/c6-result.json")" = true ] && break; sleep 3; done
echo "ventana UTC $H1..$NOW"
for k in a b c d e f g; do
  echo "$k | state=$(jq -r --arg k $k '.results[$k].state' "$OUT/c6-result.json") | total=$(jq -r --arg k $k '.results[$k].search_types.m.total_results // "-"' "$OUT/c6-result.json") | errores=$(jq -rc --arg k $k '.results[$k].errors // [] | map(.description) | join(";")' "$OUT/c6-result.json") | $(jq -r --arg k $k '.queries[]|select(.id==$k)|.query.query_string' "$OUT/c6-request.json")"
done
echo listo

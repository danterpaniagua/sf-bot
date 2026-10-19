#!/usr/bin/env bash
# Event: 20261013_gitin2218-graylog-visibilidad
# C7 — Solo lectura. Baja la definicion actual del dashboard Operations y el search guardado detras (search_id), para ver
#      como se corresponden widgets y search_types antes de escribir el script que agrega widgets. Es tambien el respaldo previo.
#      Salidas data/c7-view.json y data/c7-search.json. Token en $GRAYLOG_API_KEY (nunca literal).
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${GRAYLOG_API_KEY:?definir GRAYLOG_API_KEY en el entorno}"
BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
OUT="/home/dpaniagua/Documentos/git/bots/cloud/events/20261013_gitin2218-graylog-visibilidad/data"
VID="6ace703e41759be0a237ff89"
GET() { curl -sS -f -u "$GRAYLOG_API_KEY:token" -H 'Accept: application/json' "$@"; }
GET "$BASE/views/$VID" > "$OUT/c7-view.json"
SEARCH_ID=$(jq -r '.search_id' "$OUT/c7-view.json")
GET "$BASE/views/search/$SEARCH_ID" > "$OUT/c7-search.json"
echo "vista $(jq -r '.id' "$OUT/c7-view.json") | search $SEARCH_ID | widgets $(jq '[.state[].widgets[]] | length' "$OUT/c7-view.json") | queries del search $(jq '.queries | length' "$OUT/c7-search.json")"
echo "query ids del search: $(jq -rc '[.queries[].id]' "$OUT/c7-search.json") | claves de state: $(jq -rc '.state | keys' "$OUT/c7-view.json")"
echo "search types por query: $(jq -rc '[.queries[] | {id, n: (.search_types|length)}]' "$OUT/c7-search.json")"
echo "== un search_type de ejemplo (widget Sales Method) y su widget_mapping"
W="b6d7501a-e5ab-4de7-af94-61a6b58e9199"
ST=$(jq -r --arg w "$W" '.state[].widget_mapping[$w][0]' "$OUT/c7-view.json")
jq -c --arg st "$ST" '.queries[].search_types[] | select(.id==$st)' "$OUT/c7-search.json"
echo "== claves de nivel superior de la vista y del search"
jq -c 'keys' "$OUT/c7-view.json"; jq -c 'keys' "$OUT/c7-search.json"
echo listo

#!/usr/bin/env bash
# Event: 20261013_gitin2218-graylog-visibilidad
# C4 — Solo lectura contra el Graylog de SmartCloud. Lista los dashboards y baja la definicion completa de los que tienen
#      "HTTP" u "Operations" en el titulo (no se sabe si "Operations" es el dashboard y "HTTP Dashboard" una pestana, o al reves).
#      Imprime por dashboard y pestana: widgets (id, tipo, titulo, consulta, visualizacion, filas, columnas, series).
#      Salidas data/c4-*.json y resumen por stdout. Token en $GRAYLOG_API_KEY (nunca literal).
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${GRAYLOG_API_KEY:?definir GRAYLOG_API_KEY en el entorno}"
BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
OUT="/home/dpaniagua/Documentos/git/bots/cloud/events/20261013_gitin2218-graylog-visibilidad/data"
GET() { curl -sS -f -u "$GRAYLOG_API_KEY:token" -H 'Accept: application/json' "$@"; }
GET "$BASE/dashboards?per_page=200&page=1" > "$OUT/c4-dashboards-list.json"
echo "dashboards: $(jq '(.views // .elements // []) | length' "$OUT/c4-dashboards-list.json")"
jq -r '(.views // .elements // [])[] | "\(.id)\t\(.title)\t\(.owner // "")"' "$OUT/c4-dashboards-list.json" | tee "$OUT/c4-dashboards-titles.txt"
echo "== definicion de los que coinciden"
jq -r '(.views // .elements // [])[] | select(.title | test("http|operations"; "i")) | .id' "$OUT/c4-dashboards-list.json" | while read -r ID; do
  GET "$BASE/views/$ID" > "$OUT/c4-view-$ID.json"
  echo "---- dashboard: $(jq -r '.title' "$OUT/c4-view-$ID.json") ($ID)"
  jq -r '.state | to_entries[] | .key as $k | (.value.titles.tab.title // "") as $t | .value.widgets[] |
    [$k, $t, .id, .type, (.config.title // ""), (.query.query_string // ""), (.config.visualization // ""),
     ([.config.row_pivots[]? | .fields | join("+")] | join(",")), ([.config.column_pivots[]? | .fields | join("+")] | join(",")),
     ([.config.series[]? | .function] | join(","))] | @tsv' "$OUT/c4-view-$ID.json"
done
echo listo

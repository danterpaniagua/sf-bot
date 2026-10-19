#!/usr/bin/env bash
# Event: 20261013_gitin2218-graylog-visibilidad
# C8 — Solo lectura. Verificacion posterior a la aplicacion de los widgets: baja el dashboard Operations, ejecuta su search guardado
#      y, por widget, imprime titulo, tipo de visualizacion, rango, stream, y el resultado de su search_type (filas, error).
#      Salidas data/c8-view.json y data/c8-result.json. Token en $GRAYLOG_API_KEY (nunca literal).
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${GRAYLOG_API_KEY:?definir GRAYLOG_API_KEY en el entorno}"
BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
OUT="/home/dpaniagua/Documentos/git/bots/cloud/events/20261013_gitin2218-graylog-visibilidad/data"
GET() { curl -sS -f -u "$GRAYLOG_API_KEY:token" -H 'Accept: application/json' "$@"; }
POST() { curl -sS -f -u "$GRAYLOG_API_KEY:token" -H 'Content-Type: application/json' -H 'Accept: application/json' -H 'X-Requested-By: cli' "$@"; }
GET "$BASE/views/6ace703e41759be0a237ff89" > "$OUT/c8-view.json"
SID=$(jq -r '.search_id' "$OUT/c8-view.json")
echo "vista: $(jq -r '.title' "$OUT/c8-view.json") | search_id $SID | widgets $(jq '[.state[].widgets[]] | length' "$OUT/c8-view.json")"
JID=$(POST -d '{}' "$BASE/views/search/$SID/execute" | jq -r '.id')
for i in $(seq 1 60); do GET "$BASE/views/search/status/$JID" > "$OUT/c8-result.json"; [ "$(jq -r '.execution.done // false' "$OUT/c8-result.json")" = true ] && break; sleep 3; done
echo "ejecucion: done=$(jq -r '.execution.done' "$OUT/c8-result.json") | errores de la ejecucion: $(jq -rc '[.results[].errors // [] | .[]?.description] | length' "$OUT/c8-result.json")"
jq -r --slurpfile r "$OUT/c8-result.json" '
  .state | to_entries[] | .key as $q | .value as $s | $s.widgets[] | . as $w |
  ($s.widget_mapping[$w.id][0]) as $st |
  ($r[0].results[$q].search_types[$st]) as $res |
  [($s.titles.widget[$w.id]), .config.visualization, (.timerange|tojson), (.streams[0][0:8]),
   ($res.type // "SIN RESULTADO"), (($res.rows // []) | length), ($res.total // "-"),
   (($r[0].results[$q].errors // []) | map(select(.search_type_id==$st) | .description) | join(";"))] | @tsv' "$OUT/c8-view.json" | sort | column -t -s$'\t'
echo listo

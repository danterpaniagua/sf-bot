#!/usr/bin/env bash
# Event: 20261009_gitin2209-graylog-poco-espacio-disco
# Retention - Solo lectura (GET) en el Graylog de SmartCloud. Para el email sobre la politica de retencion:
#   por cada index set: la vida de los indices segun Data Tiering (index_lifetime_min..max, p. ej. P30D..P40D; los campos rotation_strategy /
#   retention_strategy son los heredados y no mandan cuando data_tiering existe) y las estadisticas, que vienen en el objeto "stats" del nivel
#   superior indexado por id de index set (indices, documentos, tamano en bytes), con el porcentaje de cada set sobre el total.
#   Salidas: data/retention-index-sets.json (respuesta completa) y data/retention-summary.tsv. Token en $GRAYLOG_API_KEY (nunca literal).
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${GRAYLOG_API_KEY:?definir GRAYLOG_API_KEY en el entorno}"
BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
OUT="/home/dpaniagua/Documentos/git/bots/cloud/events/20261009_gitin2209-graylog-poco-espacio-disco/data"
curl -sS -f -u "$GRAYLOG_API_KEY:token" -H 'Accept: application/json' "$BASE/system/indices/index_sets?stats=true" > "$OUT/retention-index-sets.json"
echo "index sets: $(jq '.index_sets | length' "$OUT/retention-index-sets.json")"
{
  printf 'titulo\tprefijo\tvida_min..max_(data_tiering)\ttipo_tiering\tindices\tdocumentos\tGB_actuales\tporcentaje_del_total\n'
  jq -r '.stats as $st | ([.index_sets[] | ($st[.id].size // 0)] | add) as $tot
    | .index_sets | map({t: .title, p: .index_prefix, d: (.data_tiering.index_lifetime_min + ".." + .data_tiering.index_lifetime_max), k: .data_tiering.type, i: ($st[.id].indices // 0), n: ($st[.id].documents // 0), b: ($st[.id].size // 0)})
    | sort_by(-.b) | .[] | [.t, .p, .d, .k, .i, .n, (.b / 1073741824 * 100 | round / 100), (if $tot > 0 then (.b / $tot * 1000 | round / 10 | tostring) + " %" else "-" end)] | @tsv' "$OUT/retention-index-sets.json"
} > "$OUT/retention-summary.tsv"
column -t -s $'\t' "$OUT/retention-summary.tsv"
echo listo

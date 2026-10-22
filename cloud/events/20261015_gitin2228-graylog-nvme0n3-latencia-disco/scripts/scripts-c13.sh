#!/usr/bin/env bash
# C13 (solo lectura) - mapa stream -> index set, retencion y tamano de cada index set en SmartCloud Graylog.
# Dos tablas TSV: (1) index sets con retencion (data_tiering), shards, indices, documentos y GB; (2) streams con su index set,
# si quitan los mensajes del Default Stream y cuantas reglas tienen. No lee mensajes.
# Se ejecuta desde la estacion local. Requiere GRAYLOG_API_KEY y jq. Salida a stdout.
# Uso: bash scripts-c13.sh > data/c13-graylog-indexsets-streams.txt
set -u
BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
[ -n "${GRAYLOG_API_KEY:-}" ] || { echo "ABORTA: GRAYLOG_API_KEY no definida" >&2; exit 1; }
get() { curl -s --max-time 120 -u "$GRAYLOG_API_KEY:token" -H 'Accept: application/json' "$BASE/$1"; }
SETS=$(get 'system/indices/index_sets?stats=true&skip=0&limit=0')
STREAMS=$(get 'streams')
echo "# $(date -u +%FT%TZ) | host consultado: sfcloud-monitoreo (Graylog SmartCloud)"
echo "== index sets"
echo "$SETS" | jq -r '
  if .index_sets == null then "ERR: respuesta sin index_sets" else
  (.stats // {}) as $st
  | "id\ttitulo\ttiering\tvida_min\tvida_max\tshards\treplicas\tindices\tdocumentos\tGB\tdefault",
    ( .index_sets | sort_by(.title)[] | . as $s | ($st[$s.id] // {}) as $x
      | [ $s.id, $s.title,
          ($s.data_tiering.type // "?"),
          ($s.data_tiering.index_lifetime_min // "?"), ($s.data_tiering.index_lifetime_max // "?"),
          ($s.shards // "?"), ($s.replicas // "?"),
          ($x.indices // "?"), ($x.documents // "?"),
          (if $x.size == null then "?" else (($x.size / 1073741824 * 10 | round) / 10) end),
          ($s.default // false) ] | @tsv ) end' 2>&1
echo "== streams"
echo "$STREAMS" | jq -r --argjson sets "$(echo "$SETS" | jq '[.index_sets[]? | {key: .id, value: .title}] | from_entries' 2>/dev/null || echo '{}')" '
  if .streams == null then "ERR: respuesta sin streams" else
  "id\ttitulo\tindex_set_id\tindex_set_titulo\tquita_del_default\treglas\tactivo",
  ( .streams | sort_by(.title)[]
    | [ .id, .title, (.index_set_id // "?"), ($sets[.index_set_id] // "?"),
        (.remove_matches_from_default_stream // false), ((.rules // []) | length), (.disabled | not) ] | @tsv ) end' 2>&1

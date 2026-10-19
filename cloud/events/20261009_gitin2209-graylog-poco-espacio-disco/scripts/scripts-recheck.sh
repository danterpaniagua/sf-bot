#!/usr/bin/env bash
# Event: 20261009_gitin2209-graylog-poco-espacio-disco
# C6 — Solo lectura. Recheck de 2026-10-13: (a) disco e index sets (mismo pull que C1, nombres nuevos), (b) por cada uno
#      de los index sets mas grandes (business_, orders_, sales_, scheduledjobs_): mensajes por hora de las ultimas 48 h,
#      y los Path y SourceContext mas frecuentes en las ultimas 24 h contra las 24 h anteriores.
#      Salidas en data/recheck-20261013/. Token en $GRAYLOG_API_KEY (nunca literal). Hora local UTC-3.
# Uso:  mkdir -p <ruta>/data/recheck-20261013 && bash <ruta>/scripts-recheck.sh > <ruta>/data/recheck-20261013/pull-log.txt 2>&1
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR

: "${GRAYLOG_API_KEY:?definir GRAYLOG_API_KEY en el entorno}"
OUT="/home/dpaniagua/Documentos/git/bots/cloud/events/20261009_gitin2209-graylog-poco-espacio-disco/data/recheck-20261013"
BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
VM() { ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com "$1"; }
OS="http://127.0.0.1:9200"
GET() { curl -sS -f -u "$GRAYLOG_API_KEY:token" -H 'Accept: application/json' "$@"; }
POST() { curl -sS -f -u "$GRAYLOG_API_KEY:token" -H 'Content-Type: application/json' -H 'Accept: application/json' -H 'X-Requested-By: cli' "$@"; }
iso() { date -u -d "$1" +"%Y-%m-%dT%H:%M:%S.000Z"; }
mkdir -p "$OUT"

echo "== (a) disco e indices"
VM "date -u +'%F %T UTC'; df -h /var/lib/opensearch; df -B1G --output=source,size,used,avail,pcent /var/lib/opensearch" > "$OUT/df.txt"
VM "curl -s '$OS/_cat/indices?h=index,health,status,pri,rep,docs.count,store.size,creation.date.string&bytes=gb&s=creation.date.string'" > "$OUT/cat-indices.txt"
GET "$BASE/system/indices/index_sets?stats=true&skip=0&limit=0" > "$OUT/index-sets.json"
GET "$BASE/streams" > "$OUT/streams.json"

echo "== (b) streams de los index sets grandes"
NOW=$(iso now); H24=$(iso "24 hours ago"); H48=$(iso "48 hours ago")
echo "ventanas UTC: ultimas 24 h $H24..$NOW | 24 h previas $H48..$H24"
QUERIES='[]'
for PFX in business_ orders_ sales_ scheduledjobs_; do
  ISID=$(jq -r --arg p "$PFX" '[.index_sets[] | select(.index_prefix==$p)] | if length==1 then .[0].id else empty end' "$OUT/index-sets.json")
  [ -n "$ISID" ] || { echo "GUARDA: no hay exactamente un index set con prefijo $PFX"; exit 1; }
  SID=$(jq -r --arg is "$ISID" '[.streams[] | select(.index_set_id==$is)] | if length==1 then .[0].id else empty end' "$OUT/streams.json")
  [ -n "$SID" ] || { echo "GUARDA: no hay exactamente un stream para el index set $PFX ($ISID); ver streams.json"; exit 1; }
  echo "$PFX -> index set $ISID, stream $SID ($(jq -r --arg id "$SID" '.streams[] | select(.id==$id) | .title' "$OUT/streams.json"))"
  QUERIES=$(jq -c --arg p "$PFX" --arg sid "$SID" --arg h48 "$H48" --arg h24 "$H24" --arg now "$NOW" '
    def q($id; $from; $to; $types): {id:$id, query:{type:"elasticsearch", query_string:"*"}, filter:{type:"stream", id:$sid},
                                     timerange:{type:"absolute", from:$from, to:$to}, search_types:$types};
    def cnt: [{type:"count", id:"count()"}];
    def top($id; $field; $limit): {id:$id, type:"pivot", row_groups:[{type:"values", field:$field, limit:$limit}], series:cnt, rollup:true};
    def tops: [top("path"; "Path"; 15), top("ctx"; "SourceContext"; 10), top("lvl"; "AppLevel"; 6)];
    . + [ q($p+"hourly"; $h48; $now; [{id:"hourly", type:"pivot", row_groups:[{type:"time", field:"timestamp", interval:{type:"timeunit", timeunit:"1h"}}], series:cnt, rollup:true}]),
          q($p+"now";   $h24; $now; tops),
          q($p+"prev";  $h48; $h24; tops) ]' <<< "$QUERIES")
done
BODY=$(jq -nc --argjson q "$QUERIES" '{queries:$q}')
echo "$BODY" > "$OUT/search-request.json"
SEARCH_ID=$(POST -d "$BODY" "$BASE/views/search" | jq -r '.id')
JOB_ID=$(POST -d '{}' "$BASE/views/search/$SEARCH_ID/execute" | jq -r '.id')
echo "busqueda $SEARCH_ID, trabajo $JOB_ID"
for i in $(seq 1 60); do
  GET "$BASE/views/search/status/$JOB_ID" > "$OUT/job-status.json"
  [ "$(jq -r '.execution.done // false' "$OUT/job-status.json")" = true ] && break
  sleep 3
done
[ "$(jq -r '.execution.done // false' "$OUT/job-status.json")" = true ] || { echo "el trabajo no termino en 3 minutos; reintentar mas tarde"; exit 1; }
echo "terminado tras $i consulta(s). Errores por consulta:"
jq -r '.results | to_entries[] | "  \(.key): errors=\(.value.errors // [] | length) state=\(.value.state)"' "$OUT/job-status.json"
echo "listo"

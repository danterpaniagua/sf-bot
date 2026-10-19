#!/usr/bin/env bash
# Event: 20261009_gitin2209-graylog-poco-espacio-disco
# C3 — Solo lectura contra el Graylog de SmartCloud (https://sfcloud-monitoreo.smartfran.com/graylog/api, Views Search API
#      de Graylog 7.1.3; las rutas universal/* ya no existen). Objetivo: ver QUE cambio en el stream de Business desde
#      2026-10-07, donde el index set SFC-Business-prod paso de ~2 GB/dia a 17-38 GB/dia.
#      Una sola busqueda con 3 consultas, todas acotadas al stream de Business (el stream cuyo index set es business_):
#        q_all    ultimos 14 dias : mensajes por dia, y por dia y AppLevel
#        q_before 2026-10-01 00:00 a 2026-10-07 00:00 local (6 dias)      : top SourceContext, Category, AppLevel, Path
#        q_after  2026-10-08 00:00 local hasta ahora (menos de 2 dias)    : lo mismo
#      Salidas en data/business/. Token en $GRAYLOG_API_KEY (nunca literal). Hora local UTC-3.
# Uso:  mkdir -p <ruta>/data/business && bash <ruta>/scripts-business.sh > <ruta>/data/business/pull-log.txt 2>&1
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR

: "${GRAYLOG_API_KEY:?definir GRAYLOG_API_KEY en el entorno}"
BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
OUT="/home/dpaniagua/Documentos/git/bots/cloud/events/20261009_gitin2209-graylog-poco-espacio-disco/data/business"
BUSINESS_INDEX_SET="${BUSINESS_INDEX_SET:-6a471f324b3c88a95fa99916}"   # SFC-Business-prod (index_prefix business_), de data/index-sets.json
mkdir -p "$OUT"
iso() { date -u -d "$1" +"%Y-%m-%dT%H:%M:%S.000Z"; }
GET() { curl -sS -f -u "$GRAYLOG_API_KEY:token" -H 'Accept: application/json' "$@"; }
POST() { curl -sS -f -u "$GRAYLOG_API_KEY:token" -H 'Content-Type: application/json' -H 'Accept: application/json' -H 'X-Requested-By: cli' "$@"; }

# 1) Stream de Business (cuyo index set es el de business_)
GET "$BASE/streams" > "$OUT/streams.json"
SID=$(jq -r --arg is "$BUSINESS_INDEX_SET" '[.streams[] | select(.index_set_id==$is)] | if length==1 then .[0].id else empty end' "$OUT/streams.json")
[ -n "$SID" ] || { echo "GUARDA: no hay exactamente un stream con el index set $BUSINESS_INDEX_SET (ver data/business/streams.json)"; exit 1; }
echo "stream de Business: $(jq -r --arg id "$SID" '.streams[] | select(.id==$id) | .title' "$OUT/streams.json") ($SID)"

NOW=$(iso now); D14=$(iso "14 days ago 00:00 -0300")
B0=$(iso "2026-10-01 00:00 -0300"); B1=$(iso "2026-10-07 00:00 -0300"); A0=$(iso "2026-10-08 00:00 -0300")
echo "ventanas UTC: q_all $D14..$NOW | q_before $B0..$B1 | q_after $A0..$NOW"

# 2) Busqueda con 3 consultas
BODY=$(jq -nc --arg sid "$SID" --arg d14 "$D14" --arg now "$NOW" --arg b0 "$B0" --arg b1 "$B1" --arg a0 "$A0" '
  def q($id; $from; $to; $types): {id:$id, query:{type:"elasticsearch", query_string:"*"}, filter:{type:"stream", id:$sid},
                                   timerange:{type:"absolute", from:$from, to:$to}, search_types:$types};
  def cnt: [{type:"count", id:"count()"}];
  def top($id; $field; $limit): {id:$id, type:"pivot", row_groups:[{type:"values", field:$field, limit:$limit}], series:cnt, rollup:true};
  def tops: [top("ctx"; "SourceContext"; 15), top("cat"; "Category"; 10), top("lvl"; "AppLevel"; 6), top("path"; "Path"; 12)];
  {queries:[
    q("q_all"; $d14; $now; [
      {id:"daily", type:"pivot", row_groups:[{type:"time", field:"timestamp", interval:{type:"timeunit", timeunit:"1d"}}], series:cnt, rollup:true},
      {id:"daily_level", type:"pivot", row_groups:[{type:"time", field:"timestamp", interval:{type:"timeunit", timeunit:"1d"}}, {type:"values", field:"AppLevel", limit:6}], series:cnt, rollup:false}]),
    q("q_before"; $b0; $b1; tops),
    q("q_after"; $a0; $now; tops)]}')
echo "$BODY" > "$OUT/search-request.json"
SEARCH_ID=$(POST -d "$BODY" "$BASE/views/search" | jq -r '.id')
JOB_ID=$(POST -d '{}' "$BASE/views/search/$SEARCH_ID/execute" | jq -r '.id')
echo "busqueda $SEARCH_ID, trabajo $JOB_ID"
for i in $(seq 1 40); do
  GET "$BASE/views/search/status/$JOB_ID" > "$OUT/job-status.json"
  [ "$(jq -r '.execution.done // false' "$OUT/job-status.json")" = true ] && break
  sleep 3
done
[ "$(jq -r '.execution.done // false' "$OUT/job-status.json")" = true ] || { echo "el trabajo no termino en 2 minutos; reintentar mas tarde"; exit 1; }
echo "terminado tras $i consulta(s). Errores por consulta:"
jq -r '.results | to_entries[] | "  \(.key): errors=\(.value.errors // [] | length) state=\(.value.state)"' "$OUT/job-status.json"
echo "listo"

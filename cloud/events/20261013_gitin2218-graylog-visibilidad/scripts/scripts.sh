#!/usr/bin/env bash
# Event: 20261013_gitin2218-graylog-visibilidad
# C1 — Solo lectura contra el Graylog de SmartCloud. Valores de Service que tienen Method en las ultimas 24 h, con el conteo
#      por Method, para definir un grafico de lineas por servicio. Una sola busqueda sin filtro de stream.
#      Consulta: _exists_:Method AND NOT Method:(PUT OR OPTIONS OR PATCH) AND NOT category:AppServiceHTTPLogs (solo logs de aplicacion). Token en $GRAYLOG_API_KEY (nunca literal).
# Uso:  bash <ruta>/scripts.sh > <ruta>/data/pull-log.txt 2>&1
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${GRAYLOG_API_KEY:?definir GRAYLOG_API_KEY en el entorno}"
BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
OUT="/home/dpaniagua/Documentos/git/bots/cloud/events/20261013_gitin2218-graylog-visibilidad/data"
GET() { curl -sS -f -u "$GRAYLOG_API_KEY:token" -H 'Accept: application/json' "$@"; }
POST() { curl -sS -f -u "$GRAYLOG_API_KEY:token" -H 'Content-Type: application/json' -H 'Accept: application/json' -H 'X-Requested-By: cli' "$@"; }
iso() { date -u -d "$1" +"%Y-%m-%dT%H:%M:%S.000Z"; }
NOW=$(iso now); H24=$(iso "24 hours ago")
BODY=$(jq -nc --arg f "$H24" --arg t "$NOW" '
  def cnt: [{type:"count", id:"count()"}];
  {queries:[{id:"q", query:{type:"elasticsearch", query_string:"_exists_:Method AND NOT Method:(PUT OR OPTIONS OR PATCH) AND NOT category:AppServiceHTTPLogs"},
    timerange:{type:"absolute", from:$f, to:$t},
    search_types:[
      {id:"svc_method", type:"pivot", row_groups:[{type:"values", field:"Service", limit:30}, {type:"values", field:"Method", limit:10}], series:cnt, rollup:false},
      {id:"cat", type:"pivot", row_groups:[{type:"values", field:"category", limit:10}], series:cnt, rollup:true},
      {id:"svc_total", type:"pivot", row_groups:[{type:"values", field:"Service", limit:30}], series:cnt, rollup:true}]}]}')
echo "$BODY" > "$OUT/search-request.json"
SEARCH_ID=$(POST -d "$BODY" "$BASE/views/search" | jq -r '.id')
JOB_ID=$(POST -d '{}' "$BASE/views/search/$SEARCH_ID/execute" | jq -r '.id')
for i in $(seq 1 40); do
  GET "$BASE/views/search/status/$JOB_ID" > "$OUT/job-status.json"
  [ "$(jq -r '.execution.done // false' "$OUT/job-status.json")" = true ] && break
  sleep 3
done
[ "$(jq -r '.execution.done // false' "$OUT/job-status.json")" = true ] || { echo "el trabajo no termino; reintentar"; exit 1; }
echo "ventana UTC $H24..$NOW"
jq -r '.results.q.search_types.svc_total.rows[] | "\(.key[0])\t\(.values[0].value)"' "$OUT/job-status.json" | sort -t$'\t' -k2 -nr
echo "-- por category (las que quedan tras el filtro)"
jq -r '.results.q.search_types.cat.rows[] | "\(.key[0])\t\(.values[0].value)"' "$OUT/job-status.json"
echo listo

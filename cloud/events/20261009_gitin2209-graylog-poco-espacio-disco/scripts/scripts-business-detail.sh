#!/usr/bin/env bash
# Event: 20261009_gitin2209-graylog-poco-espacio-disco
# C4 — Solo lectura contra el Graylog de SmartCloud (Views Search API). Sobre el stream de Business:
#      (a) errores (AppLevel:Error) por hora desde 2026-10-07 00:00 local, para ubicar el inicio exacto;
#      (b) 30 mensajes de error recientes con message, SourceContext, Path, StatusCode y ErrorCode, para ver el texto y el codigo HTTP.
#      Los mensajes pueden contener datos sensibles: data/business/detail-* esta en .gitignore y solo se reportan patrones normalizados.
# Salidas en data/business/. Token en $GRAYLOG_API_KEY (nunca literal). Hora local UTC-3.
# Uso:  bash <ruta>/scripts-business-detail.sh > <ruta>/data/business/pull-log-detail.txt 2>&1
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${GRAYLOG_API_KEY:?definir GRAYLOG_API_KEY en el entorno}"
BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
OUT="/home/dpaniagua/Documentos/git/bots/cloud/events/20261009_gitin2209-graylog-poco-espacio-disco/data/business"
SID="${SID:-6a452a0d18ebc987b1ca003a}"   # stream PROD-Business-AppServicePlan (data/business/streams.json)
mkdir -p "$OUT"
printf "detail-*\n" > "$OUT/.gitignore"
iso() { date -u -d "$1" +"%Y-%m-%dT%H:%M:%S.000Z"; }
GET() { curl -sS -f -u "$GRAYLOG_API_KEY:token" -H 'Accept: application/json' "$@"; }
POST() { curl -sS -f -u "$GRAYLOG_API_KEY:token" -H 'Content-Type: application/json' -H 'Accept: application/json' -H 'X-Requested-By: cli' "$@"; }
NOW=$(iso now); T0=$(iso "2026-10-07 00:00 -0300")
BODY=$(jq -nc --arg sid "$SID" --arg t0 "$T0" --arg now "$NOW" '{queries:[
  {id:"q_hourly", query:{type:"elasticsearch", query_string:"AppLevel:Error"}, filter:{type:"stream", id:$sid}, timerange:{type:"absolute", from:$t0, to:$now},
   search_types:[{id:"hourly", type:"pivot", row_groups:[{type:"time", field:"timestamp", interval:{type:"timeunit", timeunit:"1h"}}], series:[{type:"count", id:"count()"}], rollup:true}]},
  {id:"q_msgs", query:{type:"elasticsearch", query_string:"AppLevel:Error"}, filter:{type:"stream", id:$sid}, timerange:{type:"relative", range:600},
   search_types:[{id:"msgs", type:"messages", limit:30, offset:0, sort:[{field:"timestamp", order:"DESC"}], fields:["timestamp","SourceContext","Path","StatusCode","ErrorCode","message"]}]}]}')
SEARCH_ID=$(POST -d "$BODY" "$BASE/views/search" | jq -r '.id')
JOB_ID=$(POST -d '{}' "$BASE/views/search/$SEARCH_ID/execute" | jq -r '.id')
for i in $(seq 1 40); do
  GET "$BASE/views/search/status/$JOB_ID" > "$OUT/detail-job-status.json"
  [ "$(jq -r '.execution.done // false' "$OUT/detail-job-status.json")" = true ] && break
  sleep 3
done
[ "$(jq -r '.execution.done // false' "$OUT/detail-job-status.json")" = true ] || { echo "el trabajo no termino en 2 minutos"; exit 1; }
jq -r '.results | to_entries[] | "  \(.key): errors=\(.value.errors // [] | length) state=\(.value.state)"' "$OUT/detail-job-status.json"
echo "listo"

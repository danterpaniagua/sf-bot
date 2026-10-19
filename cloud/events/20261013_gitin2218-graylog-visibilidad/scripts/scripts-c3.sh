#!/usr/bin/env bash
# Event: 20261013_gitin2218-graylog-visibilidad
# C3 — Solo lectura. Business.API, logs de aplicacion, Method GET: mensajes por dia desde 2026-10-05 00:00 local, y por dia y Path (top 15).
#      Para ver desde que dia crecen los GET y que Path los explica. Sin pivot por category (C1 fallo con mas pivots; C2 con uno solo anduvo).
#      Salidas data/c3-*.json y resumen por stdout. Token en $GRAYLOG_API_KEY (nunca literal). Hora local UTC-3.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${GRAYLOG_API_KEY:?definir GRAYLOG_API_KEY en el entorno}"
BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
OUT="/home/dpaniagua/Documentos/git/bots/cloud/events/20261013_gitin2218-graylog-visibilidad/data"
GET() { curl -sS -f -u "$GRAYLOG_API_KEY:token" -H 'Accept: application/json' "$@"; }
POST() { curl -sS -f -u "$GRAYLOG_API_KEY:token" -H 'Content-Type: application/json' -H 'Accept: application/json' -H 'X-Requested-By: cli' "$@"; }
iso() { date -u -d "$1" +"%Y-%m-%dT%H:%M:%S.000Z"; }
F=$(iso "2026-10-05 00:00 -0300"); T=$(iso now)
Q='_exists_:Method AND Method:GET AND NOT category:AppServiceHTTPLogs AND Service:"SmartFran.Cloud.Business.API"'
BODY=$(jq -nc --arg q "$Q" --arg f "$F" --arg t "$T" '
  def day: {type:"time", field:"timestamp", interval:{type:"timeunit", timeunit:"1d"}};
  def cnt: [{type:"count", id:"count()"}];
  {queries:[{id:"q", query:{type:"elasticsearch", query_string:$q}, timerange:{type:"absolute", from:$f, to:$t},
    search_types:[
      {id:"daily", type:"pivot", row_groups:[day], series:cnt, rollup:true},
      {id:"daily_path", type:"pivot", row_groups:[day, {type:"values", field:"Path", limit:15}], series:cnt, rollup:false}]}]}')
echo "$BODY" > "$OUT/c3-request.json"
SID=$(POST -d "$BODY" "$BASE/views/search" | jq -r '.id'); JID=$(POST -d '{}' "$BASE/views/search/$SID/execute" | jq -r '.id')
for i in $(seq 1 40); do GET "$BASE/views/search/status/$JID" > "$OUT/c3-result.json"; [ "$(jq -r '.execution.done // false' "$OUT/c3-result.json")" = true ] && break; sleep 3; done
echo "ventana UTC $F..$T | state=$(jq -r '.results.q.state' "$OUT/c3-result.json") | errores=$(jq -rc '.results.q.errors // [] | map(.description) | join(";")' "$OUT/c3-result.json")"
jq -r '.results.q.search_types.daily.rows[] | select(.source=="leaf") | "\(.key[0])\t\(.values[0].value)"' "$OUT/c3-result.json"
echo listo

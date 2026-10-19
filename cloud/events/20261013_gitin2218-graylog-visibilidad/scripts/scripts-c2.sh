#!/usr/bin/env bash
# Event: 20261013_gitin2218-graylog-visibilidad
# C2 — Solo lectura. C1 fallo (query FAILED, "description: null"). Prueba variantes por separado para ubicar cual rompe:
#      v1 query "*" + pivot Service | v2 query con _exists_:Method | v3 v2 + NOT Method:(...) | v4 v3 + NOT category:AppServiceHTTPLogs
#      cada una con el pivot por Service solo. Ventana: ultima hora. Salidas data/c2-v*.json y resumen por stdout.
set -uo pipefail
: "${GRAYLOG_API_KEY:?definir GRAYLOG_API_KEY en el entorno}"
BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
OUT="/home/dpaniagua/Documentos/git/bots/cloud/events/20261013_gitin2218-graylog-visibilidad/data"
GET() { curl -sS -f -u "$GRAYLOG_API_KEY:token" -H 'Accept: application/json' "$@"; }
POST() { curl -sS -f -u "$GRAYLOG_API_KEY:token" -H 'Content-Type: application/json' -H 'Accept: application/json' -H 'X-Requested-By: cli' "$@"; }
iso() { date -u -d "$1" +"%Y-%m-%dT%H:%M:%S.000Z"; }
NOW=$(iso now); H1=$(iso "1 hour ago")
run() { # $1 nombre, $2 query
  local BODY SID JID
  BODY=$(jq -nc --arg q "$2" --arg f "$H1" --arg t "$NOW" '{queries:[{id:"q", query:{type:"elasticsearch", query_string:$q}, timerange:{type:"absolute", from:$f, to:$t},
    search_types:[{id:"svc", type:"pivot", row_groups:[{type:"values", field:"Service", limit:30}], series:[{type:"count", id:"count()"}], rollup:true}]}]}')
  SID=$(POST -d "$BODY" "$BASE/views/search" | jq -r '.id'); JID=$(POST -d '{}' "$BASE/views/search/$SID/execute" | jq -r '.id')
  for i in $(seq 1 40); do GET "$BASE/views/search/status/$JID" > "$OUT/c2-$1.json"; [ "$(jq -r '.execution.done // false' "$OUT/c2-$1.json")" = true ] && break; sleep 3; done
  echo "$1 | $2 | state=$(jq -r '.results.q.state' "$OUT/c2-$1.json") | servicios=$(jq -r '.results.q.search_types.svc.rows // [] | length' "$OUT/c2-$1.json") | error=$(jq -rc '.results.q.errors // [] | map(.description) | join(";")' "$OUT/c2-$1.json")"
}
run v1 '*'
run v2 '_exists_:Method'
run v3 '_exists_:Method AND NOT Method:(PUT OR OPTIONS OR PATCH)'
run v4 '_exists_:Method AND NOT Method:(PUT OR OPTIONS OR PATCH) AND NOT category:AppServiceHTTPLogs'
echo listo

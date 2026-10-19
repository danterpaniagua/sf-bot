#!/usr/bin/env bash
# Event: 20261013_gitin2221-normalizar-http-paths
# C4 — Solo lectura contra el Graylog de SmartCloud (Views Search API). Verifica NormalizedPath desde el reinicio de Logstash (19:31 UTC):
#      a) mensajes con Path vs. con NormalizedPath en la misma ventana (deben coincidir si el filtro corre sobre todo lo que trae Path),
#      b) por Service: mensajes con NormalizedPath y los 10 valores mas frecuentes (3 niveles: Service, NormalizedPath),
#      c) los Path que quedaron en "unmatched" (top 25) y cuantos son.
#      Ventana: 2026-10-13 19:33:00Z hasta ahora. Salidas data/c4-*.json. Token en $GRAYLOG_API_KEY (nunca literal).
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${GRAYLOG_API_KEY:?definir GRAYLOG_API_KEY en el entorno}"
BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
OUT="/home/dpaniagua/Documentos/git/bots/operations/events/20261013_gitin2221-normalizar-http-paths/data"
GET() { curl -sS -f -u "$GRAYLOG_API_KEY:token" -H 'Accept: application/json' "$@"; }
POST() { curl -sS -f -u "$GRAYLOG_API_KEY:token" -H 'Content-Type: application/json' -H 'Accept: application/json' -H 'X-Requested-By: cli' "$@"; }
F="2026-10-13T19:33:00.000Z"; T=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
BODY=$(jq -nc --arg f "$F" --arg t "$T" '
  def cnt: [{type:"count", id:"count()"}];
  def q($id; $qs; $types): {id:$id, query:{type:"elasticsearch", query_string:$qs}, timerange:{type:"absolute", from:$f, to:$t}, search_types:$types};
  def msgs: [{id:"m", type:"messages", limit:1, offset:0}];
  {queries:[
    q("with_path";  "_exists_:Path";            msgs),
    q("with_norm";  "_exists_:NormalizedPath";  msgs),
    q("per_service"; "_exists_:NormalizedPath"; [
      {id:"svc", type:"pivot", row_groups:[{type:"values", field:"Service", limit:20}], series:cnt, rollup:true},
      {id:"svc_norm", type:"pivot", row_groups:[{type:"values", field:"Service", limit:20}, {type:"values", field:"NormalizedPath", limit:10}], series:cnt, rollup:false}]),
    q("unmatched";  "NormalizedPath:unmatched"; [
      {id:"u_total", type:"pivot", row_groups:[], series:cnt, rollup:true},
      {id:"u_paths", type:"pivot", row_groups:[{type:"values", field:"Path", limit:25}], series:cnt, rollup:true}])
  ]}')
echo "$BODY" > "$OUT/c4-request.json"
SID=$(POST -d "$BODY" "$BASE/views/search" | jq -r '.id'); JID=$(POST -d '{}' "$BASE/views/search/$SID/execute" | jq -r '.id')
for i in $(seq 1 60); do GET "$BASE/views/search/status/$JID" > "$OUT/c4-result.json"; [ "$(jq -r '.execution.done // false' "$OUT/c4-result.json")" = true ] && break; sleep 3; done
echo "ventana UTC $F..$T"
jq -r '.results | to_entries[] | "\(.key) state=\(.value.state) errores=\(.value.errors // [] | length)"' "$OUT/c4-result.json"
echo "== a) con Path: $(jq -r '.results.with_path.search_types.m.total_results' "$OUT/c4-result.json") | con NormalizedPath: $(jq -r '.results.with_norm.search_types.m.total_results' "$OUT/c4-result.json")"
echo "== b) por Service (mensajes con NormalizedPath)"
jq -r '.results.per_service.search_types.svc.rows[] | select(.source=="leaf") | "\(.key[0])\t\(.values[0].value)"' "$OUT/c4-result.json" | LC_ALL=C sort -t$'\t' -k2 -nr
echo "== b2) top NormalizedPath por Service"
jq -r '.results.per_service.search_types.svc_norm.rows[] | select(.source=="leaf") | "\(.key[0])\t\(.key[1])\t\(.values[0].value)"' "$OUT/c4-result.json" | LC_ALL=C sort -t$'\t' -k1,1 -k3,3nr
echo "== c) unmatched: total $(jq -r '.results.unmatched.search_types.u_total.rows[0].values[0].value // 0' "$OUT/c4-result.json"); top Path"
jq -r '.results.unmatched.search_types.u_paths.rows[] | select(.source=="leaf") | "\(.values[0].value)\t\(.key[0])"' "$OUT/c4-result.json" | LC_ALL=C sort -nr | head -25
echo listo

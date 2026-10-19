#!/usr/bin/env bash
# Event: 20261013_gitin2218-graylog-visibilidad
# C9 — Solo lectura. ¿Donde falta ElapsedMilliseconds y de que tipo esta guardado?
#      a) Tipo del campo en cada indice de OpenSearch (mapping), por SSH no interactivo a la VM de Graylog: resumen por tipo e indices con un tipo distinto.
#      b) Graylog, ultima hora, por Service: lineas con Method, con StatusCode, con ElapsedMilliseconds, y promedio de ElapsedMilliseconds
#         (si el campo no fuera numerico en algun indice, el promedio daria error o saldria vacio).
#      Salidas data/c9-*.json y resumen por stdout. Token en $GRAYLOG_API_KEY (nunca literal).
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${GRAYLOG_API_KEY:?definir GRAYLOG_API_KEY en el entorno}"
BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
OUT="/home/dpaniagua/Documentos/git/bots/cloud/events/20261013_gitin2218-graylog-visibilidad/data"
VM() { ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com "$1"; }
GET() { curl -sS -f -u "$GRAYLOG_API_KEY:token" -H 'Accept: application/json' "$@"; }
POST() { curl -sS -f -u "$GRAYLOG_API_KEY:token" -H 'Content-Type: application/json' -H 'Accept: application/json' -H 'X-Requested-By: cli' "$@"; }
iso() { date -u -d "$1" +"%Y-%m-%dT%H:%M:%S.000Z"; }

echo "== a) tipo de ElapsedMilliseconds y de StatusCode por indice"
VM "curl -s 'http://127.0.0.1:9200/_mapping/field/ElapsedMilliseconds,StatusCode'" > "$OUT/c9-mapping.json"
for F in ElapsedMilliseconds StatusCode; do
  echo "-- $F: indices por tipo"
  jq -r --arg f "$F" 'to_entries[] | "\(.value.mappings[$f].mapping[$f].type // "SIN CAMPO")"' "$OUT/c9-mapping.json" | sort | uniq -c
  echo "-- $F: indices con tipo distinto de float/long/double/integer (primeros 15)"
  jq -r --arg f "$F" 'to_entries[] | select((.value.mappings[$f].mapping[$f].type // "SIN CAMPO") | IN("float","double","long","integer","half_float","scaled_float") | not) | "\(.key)\t\(.value.mappings[$f].mapping[$f].type // "SIN CAMPO")"' "$OUT/c9-mapping.json" | head -15
done

echo "== b) Graylog, ultima hora, por Service"
NOW=$(iso now); H1=$(iso "1 hour ago")
BODY=$(jq -nc --arg f "$H1" --arg t "$NOW" '
  def q($id; $qs): {id:$id, query:{type:"elasticsearch", query_string:$qs}, timerange:{type:"absolute", from:$f, to:$t},
    search_types:[{id:"svc", type:"pivot", row_groups:[{type:"values", field:"Service", limit:20}], series:[{type:"count", id:"count()"}, {type:"avg", id:"avg(ElapsedMilliseconds)", field:"ElapsedMilliseconds"}], rollup:true}]};
  {queries:[ q("method";  "_exists_:Method AND NOT category:AppServiceHTTPLogs"),
             q("status";  "_exists_:StatusCode AND NOT category:AppServiceHTTPLogs"),
             q("elapsed"; "_exists_:ElapsedMilliseconds AND NOT category:AppServiceHTTPLogs") ]}')
echo "$BODY" > "$OUT/c9-request.json"
SID=$(POST -d "$BODY" "$BASE/views/search" | jq -r '.id'); JID=$(POST -d '{}' "$BASE/views/search/$SID/execute" | jq -r '.id')
for i in $(seq 1 60); do GET "$BASE/views/search/status/$JID" > "$OUT/c9-result.json"; [ "$(jq -r '.execution.done // false' "$OUT/c9-result.json")" = true ] && break; sleep 3; done
echo "ventana UTC $H1..$NOW"
jq -r '.results | to_entries[] | "\(.key) state=\(.value.state) errores=\(.value.errors // [] | map(.description) | join(";"))"' "$OUT/c9-result.json"
printf '%-34s %10s %12s %12s %14s\n' Service con_Method con_StatusCode con_Elapsed avg_Elapsed_ms
jq -r '.results as $r | [$r.method.search_types.svc.rows[] | select(.source=="leaf") | .key[0]] | unique[] as $s |
  [$s,
   ([$r.method.search_types.svc.rows[] | select(.source=="leaf" and .key[0]==$s) | .values[] | select(.key[0]=="count()") | .value] | first // 0),
   ([$r.status.search_types.svc.rows[] | select(.source=="leaf" and .key[0]==$s) | .values[] | select(.key[0]=="count()") | .value] | first // 0),
   ([$r.elapsed.search_types.svc.rows[] | select(.source=="leaf" and .key[0]==$s) | .values[] | select(.key[0]=="count()") | .value] | first // 0),
   ([$r.elapsed.search_types.svc.rows[] | select(.source=="leaf" and .key[0]==$s) | .values[] | select(.key[0]=="avg(ElapsedMilliseconds)") | .value] | first // "-")] | @tsv' "$OUT/c9-result.json" \
  | awk -F'\t' '{printf "%-34s %10s %12s %12s %14s\n", $1,$2,$3,$4,$5}'
echo listo

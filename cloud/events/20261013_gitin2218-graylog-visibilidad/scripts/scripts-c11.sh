#!/usr/bin/env bash
# Event: 20261013_gitin2218-graylog-visibilidad
# C11 — Solo lectura. Verifica ElapsedMillisecondsOpe despues del reinicio de Logstash de las ~20:03 UTC (deploy.sh fix, GITIN-2221):
#       a) Graylog, desde 20:05:00Z hasta ahora, por Service: lineas con StatusCode, con ElapsedMilliseconds, con ElapsedMillisecondsOpe,
#          y promedio / maximo de ElapsedMillisecondsOpe (Sales deberia pasar de ~0 a casi todas las lineas con StatusCode),
#       b) tipo del campo ElapsedMillisecondsOpe en los indices de OpenSearch (por SSH no interactivo a la VM de Graylog).
#       Salidas data/c11-*.json y resumen por stdout. Token en $GRAYLOG_API_KEY (nunca literal).
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${GRAYLOG_API_KEY:?definir GRAYLOG_API_KEY en el entorno}"
BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
OUT="/home/dpaniagua/Documentos/git/bots/cloud/events/20261013_gitin2218-graylog-visibilidad/data"
GET() { curl -sS -f -u "$GRAYLOG_API_KEY:token" -H 'Accept: application/json' "$@"; }
POST() { curl -sS -f -u "$GRAYLOG_API_KEY:token" -H 'Content-Type: application/json' -H 'Accept: application/json' -H 'X-Requested-By: cli' "$@"; }
F="2026-10-13T20:05:00.000Z"; T=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
BODY=$(jq -nc --arg f "$F" --arg t "$T" '
  def q($id; $qs): {id:$id, query:{type:"elasticsearch", query_string:$qs}, timerange:{type:"absolute", from:$f, to:$t},
    search_types:[{id:"svc", type:"pivot", row_groups:[{type:"values", field:"Service", limit:20}],
      series:[{type:"count", id:"count()"}, {type:"avg", id:"avg(ElapsedMillisecondsOpe)", field:"ElapsedMillisecondsOpe"}, {type:"max", id:"max(ElapsedMillisecondsOpe)", field:"ElapsedMillisecondsOpe"}], rollup:true}]};
  {queries:[ q("status"; "_exists_:StatusCode AND NOT category:AppServiceHTTPLogs"),
             q("elapsed"; "_exists_:ElapsedMilliseconds AND NOT category:AppServiceHTTPLogs"),
             q("ope";     "_exists_:ElapsedMillisecondsOpe AND NOT category:AppServiceHTTPLogs") ]}')
echo "$BODY" > "$OUT/c11-request.json"
SID=$(POST -d "$BODY" "$BASE/views/search" | jq -r '.id'); JID=$(POST -d '{}' "$BASE/views/search/$SID/execute" | jq -r '.id')
for i in $(seq 1 60); do GET "$BASE/views/search/status/$JID" > "$OUT/c11-result.json"; [ "$(jq -r '.execution.done // false' "$OUT/c11-result.json")" = true ] && break; sleep 3; done
echo "ventana UTC $F..$T"
jq -r '.results | to_entries[] | "\(.key) state=\(.value.state) errores=\(.value.errors // [] | map(.description) | join(";"))"' "$OUT/c11-result.json"
printf '%-34s %14s %16s %12s %12s %12s\n' Service con_StatusCode con_ElapsedMs con_Ope avg_Ope max_Ope
jq -r '.results as $r | [$r.status.search_types.svc.rows[] | select(.source=="leaf") | .key[0]] | unique[] as $s |
  def v($q; $k): ([$r[$q].search_types.svc.rows[] | select(.source=="leaf" and .key[0]==$s) | .values[] | select(.key[0]==$k) | .value] | first // "-");
  [$s, v("status";"count()"), v("elapsed";"count()"), v("ope";"count()"), v("ope";"avg(ElapsedMillisecondsOpe)"), v("ope";"max(ElapsedMillisecondsOpe)")] | @tsv' "$OUT/c11-result.json" \
  | awk -F'\t' '{printf "%-34s %14s %16s %12s %12s %12s\n", $1,$2,$3,$4,$5,$6}'
echo "== b) tipo de ElapsedMillisecondsOpe por indice (OpenSearch)"
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com "curl -s 'http://127.0.0.1:9200/_mapping/field/ElapsedMillisecondsOpe'" > "$OUT/c11-mapping.json"
jq -r 'to_entries[] | "\(.value.mappings.ElapsedMillisecondsOpe.mapping.ElapsedMillisecondsOpe.type // "SIN CAMPO")"' "$OUT/c11-mapping.json" | sort | uniq -c
jq -r 'to_entries[] | select(.value.mappings.ElapsedMillisecondsOpe) | "\(.key)\t\(.value.mappings.ElapsedMillisecondsOpe.mapping.ElapsedMillisecondsOpe.type)"' "$OUT/c11-mapping.json"
echo listo

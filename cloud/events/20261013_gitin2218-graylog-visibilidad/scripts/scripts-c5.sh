#!/usr/bin/env bash
# Event: 20261013_gitin2218-graylog-visibilidad
# C5 — Solo lectura. Revision de los widgets existentes del dashboard Operations, pestana HTTP:
#      (1) vuelve a bajar la definicion y la compara con la de C4 (por si cambio),
#      (2) agrega 4 servicios sin widget (Platform.API, Client.Web, pos-wasm y Security.API, este ultimo nombre supuesto),
#      (3) ejecuta la consulta exacta de cada widget sobre la ultima hora y cuenta por Method, por StatusCode (top 12) y por Path (top 5),
#          y cuantos mensajes tienen StatusCode y Path (_exists_), para saber si los graficos de respuestas y de endpoints son viables.
#      Salidas data/c5-*.json y resumen por stdout. Token en $GRAYLOG_API_KEY (nunca literal).
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${GRAYLOG_API_KEY:?definir GRAYLOG_API_KEY en el entorno}"
BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
OUT="/home/dpaniagua/Documentos/git/bots/cloud/events/20261013_gitin2218-graylog-visibilidad/data"
VID="6ace703e41759be0a237ff89"
GET() { curl -sS -f -u "$GRAYLOG_API_KEY:token" -H 'Accept: application/json' "$@"; }
POST() { curl -sS -f -u "$GRAYLOG_API_KEY:token" -H 'Content-Type: application/json' -H 'Accept: application/json' -H 'X-Requested-By: cli' "$@"; }
iso() { date -u -d "$1" +"%Y-%m-%dT%H:%M:%S.000Z"; }
GET "$BASE/views/$VID" > "$OUT/c5-view.json"
W() { jq -S '[.state[].widgets[] | {id, type, query, config}]' "$1"; }
if [ "$(W "$OUT/c4-view-$VID.json" | md5sum | cut -d' ' -f1)" = "$(W "$OUT/c5-view.json" | md5sum | cut -d' ' -f1)" ]; then echo "definicion: igual que C4"; else echo "definicion: CAMBIO respecto de C4 (comparar c4-view-$VID.json y c5-view.json)"; fi
echo "widgets: $(jq '[.state[].widgets[]] | length' "$OUT/c5-view.json")"
jq -r '.state[].widgets[] | [.id, (.timerange | tostring), .query.query_string] | @tsv' "$OUT/c5-view.json" > "$OUT/c5-widgets.tsv"
# servicios que hoy no tienen widget (C2): se consultan igual, con el mismo patron de consulta que los existentes.
# SmartFran.Cloud.Security.API es una suposicion de nombre (Security no aparecio en C2): si da 0, no existe con ese nombre.
for SVC in SmartFran.Cloud.Platform.API SmartFran.Cloud.Client.Web smartfran-pos-wasm SmartFran.Cloud.Security.API; do
  printf 'nuevo-%s\t-\t_exists_:Method AND NOT Method: ("OPTIONS") AND Service:"%s"\n' "$SVC" "$SVC" >> "$OUT/c5-widgets.tsv"
done
cat "$OUT/c5-widgets.tsv"
NOW=$(iso now); H1=$(iso "1 hour ago")
BODY=$(jq -nc --arg f "$H1" --arg t "$NOW" --rawfile w "$OUT/c5-widgets.tsv" '
  def cnt: [{type:"count", id:"count()"}];
  def top($id; $field; $n): {id:$id, type:"pivot", row_groups:[{type:"values", field:$field, limit:$n}], series:cnt, rollup:true};
  def qq($id; $qs): {id:$id, query:{type:"elasticsearch", query_string:$qs}, timerange:{type:"absolute", from:$f, to:$t},
                     search_types:[top("method";"Method";10), top("status";"StatusCode";12), top("path";"Path";5)]};
  {queries: ([$w | split("\n")[] | select(length>0) | split("\t")] | map(
      qq(.[0]; .[2]), qq(.[0]+"_st"; .[2]+" AND _exists_:StatusCode"), qq(.[0]+"_pa"; .[2]+" AND _exists_:Path")) )}')
echo "$BODY" > "$OUT/c5-request.json"
SID=$(POST -d "$BODY" "$BASE/views/search" | jq -r '.id'); JID=$(POST -d '{}' "$BASE/views/search/$SID/execute" | jq -r '.id')
for i in $(seq 1 60); do GET "$BASE/views/search/status/$JID" > "$OUT/c5-result.json"; [ "$(jq -r '.execution.done // false' "$OUT/c5-result.json")" = true ] && break; sleep 3; done
echo "ventana UTC $H1..$NOW"
jq -r '.results | to_entries[] | "\(.key)\tstate=\(.value.state)\terrores=\(.value.errors // [] | length)"' "$OUT/c5-result.json"
echo "== por widget: total / con StatusCode / con Path; verbos; estados; rutas"
for ID in $(cut -f1 "$OUT/c5-widgets.tsv"); do
  S=$(jq -r --arg k "$ID" '.results[$k].search_types.method.total // 0' "$OUT/c5-result.json")
  echo "-- $ID | service: $(grep "^$ID" "$OUT/c5-widgets.tsv" | cut -f3 | sed 's/.*Service://')"
  echo "   total=$S | con StatusCode=$(jq -r --arg k "${ID}_st" '.results[$k].search_types.method.total // 0' "$OUT/c5-result.json") | con Path=$(jq -r --arg k "${ID}_pa" '.results[$k].search_types.method.total // 0' "$OUT/c5-result.json")"
  echo "   verbos:  $(jq -r --arg k "$ID" '[.results[$k].search_types.method.rows[] | select(.source=="leaf") | "\(.key[0])=\(.values[0].value)"] | join(" ")' "$OUT/c5-result.json")"
  echo "   estados: $(jq -r --arg k "${ID}_st" '[.results[$k].search_types.status.rows[] | select(.source=="leaf") | "\(.key[0])=\(.values[0].value)"] | join(" ")' "$OUT/c5-result.json")"
  echo "   rutas:   $(jq -r --arg k "${ID}_pa" '[.results[$k].search_types.path.rows[] | select(.source=="leaf") | "\(.key[0])=\(.values[0].value)"] | join(" | ")' "$OUT/c5-result.json")"
done
echo listo

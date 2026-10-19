#!/usr/bin/env bash
# Event: 20261015_logs-contract-ope-sp-sml
# C1 - SOLO LECTURA contra la API REST de Graylog de SmartPedidos/SmartLoyalty (sf-monitoreo.smartfran.com:9000). Token en $SML_GRAYLOG_API_KEY (nunca literal).
#      Objetivo: ver COMO llegan a Graylog los logs de SmartLoyalty (nombres de campos, nivel, servicio, version) para el anexo de Operaciones del contrato de logs.
#      Que hace:
#        1) lista los streams (id y titulo) y los inputs globales no se tocan
#        2) muestra de hasta 500 mensajes de la ultima hora que NO son de SmartPedidos (NOT _exists_:msg_service): conteo por source y frecuencia de cada NOMBRE de campo
#        3) para las 6 fuentes con mas mensajes: muestra de hasta 200 mensajes (source:"<nombre>"), frecuencia de nombres de campo y, SOLO para campos cuyo nombre sugiere metadatos
#           (nivel, severidad, facilidad, categoria, tipo, modulo, canal, aplicacion, servicio, version, entorno, host, stream), los valores con sus conteos
#      Privacidad: no se guarda ni se imprime texto de mensajes ni valores de otros campos (solo nombres, porcentajes y cantidad de valores distintos). Las respuestas crudas viven en un
#      archivo temporal que se borra al terminar. Salida: data/c1/sml-sample.txt
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${SML_GRAYLOG_API_KEY:?definir SML_GRAYLOG_API_KEY en el entorno}"
BASE="http://sf-monitoreo.smartfran.com:9000/api"
OUT="/home/dpaniagua/Documentos/git/bots/operations/events/20261015_logs-contract-ope-sp-sml/data/c1"
mkdir -p "$OUT"; T=$(mktemp); trap 'rm -f "$T"' EXIT
META='level|severity|facility|categor|type|module|channel|application|app_|service|version|env|host|stream|logger|source'
get() { curl -sS -G -u "$SML_GRAYLOG_API_KEY:token" -H 'Accept: application/json' "$BASE/search/universal/relative" --data-urlencode "query=$1" --data-urlencode "range=3600" --data-urlencode "limit=$2" -o "$T" -w '%{http_code}'; }
fields_report() { # estadisticas sobre $T: nombres de campo (porcentaje de mensajes) y valores de campos de metadatos
  jq -r --arg meta "$META" '
    [.messages[].message] as $m | ($m|length) as $n |
    if $n==0 then "  (sin mensajes)" else
    ( "  mensajes en la muestra: \($n)",
      "  campos (nombre | % de mensajes | valores distintos):",
      ( [ $m[] | to_entries[] | .key ] | group_by(.) | map({k:.[0], c:length}) | sort_by(-.c)[] as $f
        | "    \($f.k) | \(($f.c*100/$n)|floor)% | \([ $m[] | .[$f.k] | select(.!=null) | tostring ] | unique | length)" ),
      "  valores de campos de metadatos (campo = valor : conteo; solo si hay 12 valores distintos o menos):",
      ( [ $m[] | to_entries[] | select(.key|test($meta;"i")) | select(.key|test("^(message|full_message)$")|not) ] | group_by(.key)[]
        | (.[0].key) as $k | ([ .[] | .value | tostring ] | group_by(.) | map({v:.[0], c:length})) as $vals
        | select(($vals|length) <= 12) | $vals[] | "    \($k) = \(.v|.[0:60]) : \(.c)" ) )
    end' "$T"
}
{
  echo "== $(date -u +%FT%TZ) | Graylog de SmartPedidos/SmartLoyalty | ultima hora"
  curl -sS -u "$SML_GRAYLOG_API_KEY:token" -H 'Accept: application/json' "$BASE/streams" -o "$T"
  echo "== 1) streams (titulo | habilitado)"; jq -r '.streams[] | [.title, (.disabled|not|tostring)] | @tsv' "$T" | LC_ALL=C sort
  code=$(get 'NOT _exists_:msg_service' 500)
  echo; echo "== 2) mensajes que no son de SmartPedidos (NOT _exists_:msg_service): HTTP $code | total en la hora $(jq -r '.total_results' "$T") | devueltos $(jq '.messages|length' "$T")"
  echo "  fuentes (conteo | source):"; jq -r '.messages[].message.source // "-"' "$T" | LC_ALL=C sort | uniq -c | LC_ALL=C sort -rn | head -20 | sed 's/^/    /'
  fields_report
  SRCS=$(get 'NOT _exists_:msg_service' 500 >/dev/null; jq -r '.messages[].message.source // empty' "$T" | LC_ALL=C sort | uniq -c | LC_ALL=C sort -rn | head -6 | awk '{print $2}')
  for s in $SRCS; do
    code=$(get "source:\"$s\"" 200)
    echo; echo "== 3) source=$s: HTTP $code | total en la hora $(jq -r '.total_results' "$T") | devueltos $(jq '.messages|length' "$T")"
    fields_report
  done
} > "$OUT/sml-sample.txt" 2>&1
cat "$OUT/sml-sample.txt"; echo listo

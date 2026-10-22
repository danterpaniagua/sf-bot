#!/usr/bin/env bash
# C21 (solo lectura) - patrones mas frecuentes de los mensajes Warning/Error/Fatal en los streams Platform, Person y Pos, ultimas 24 h.
# Toma una muestra repartida en 4 tramos de 6 h (hasta 250 mensajes por tramo, 1000 por stream), no el total: el total del stream se imprime aparte.
# Cada mensaje se normaliza antes de agrupar: espacios y saltos de linea colapsados, emails -> <EMAIL>, GUID -> <GUID>, todo numero -> N, corte a 160 caracteres.
# Aun asi puede quedar texto libre (nombres): revisar el archivo antes de pegarlo o compartirlo.
# Se ejecuta desde la estacion local. Requiere GRAYLOG_API_KEY, jq y GNU date. Salida TSV a stdout.
# Uso: bash top-patterns-warning.sh > data/c21-top-patterns.tsv
set -u
BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
QUERY='AppLevel:"Warning" OR AppLevel:"Error" OR AppLevel:"Fatal"'
PER=250
[ -n "${GRAYLOG_API_KEY:-}" ] || { echo "ABORTA: GRAYLOG_API_KEY no definida" >&2; exit 1; }
FMT='+%Y-%m-%dT%H:%M:%S.000Z'
NOW=$(date -u +%s)

api() { curl -s --max-time 180 -u "$GRAYLOG_API_KEY:token" -H 'Accept: application/json' "$@"; }

echo "# $(date -u +%FT%TZ) | 24 h | consulta: $QUERY | host consultado: sfcloud-monitoreo (Graylog SmartCloud) | muestra: 4 tramos x $PER por stream"
printf 'stream\ttotal_24h\tmuestra\tveces_en_muestra\tpct_muestra\tpatron\n'
for S in Platform Person Pos; do
  ID=$(api "$BASE/streams" | jq -r --arg t "PROD-$S-AppServicePlan" '.streams[]? | select(.title == $t) | .id')
  [ -n "$ID" ] || { printf '%s\tERR\tstream no encontrado\n' "$S"; continue; }
  TOTAL=$(api --data-urlencode "query=$QUERY" --data-urlencode "filter=streams:$ID" --data-urlencode 'range=86400' --data-urlencode 'limit=1' \
          -G "$BASE/search/universal/relative" | jq -r '.total_results // "ERR"')
  TMP=$(mktemp)
  for I in 0 1 2 3; do
    FROM=$(date -u -d "@$((NOW - 86400 + I * 21600))" "$FMT")
    TO=$(date -u -d "@$((NOW - 86400 + (I + 1) * 21600))" "$FMT")
    api --data-urlencode "query=$QUERY" --data-urlencode "filter=streams:$ID" --data-urlencode "from=$FROM" --data-urlencode "to=$TO" \
        --data-urlencode "limit=$PER" --data-urlencode 'fields=message' -G "$BASE/search/universal/absolute" \
      | jq -r '.messages[]?.message.message // empty | gsub("\\s+"; " ")' >> "$TMP"
  done
  N=$(wc -l < "$TMP")
  if [ "$N" -eq 0 ]; then printf '%s\t%s\t0\t\t\tsin mensajes en la muestra (o la consulta fallo)\n' "$S" "$TOTAL"; rm -f "$TMP"; continue; fi
  sed -E 's/[[:alnum:]._%+-]+@[[:alnum:].-]+/<EMAIL>/g; s/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/<GUID>/g; s/[0-9]+/N/g' "$TMP" \
    | cut -c1-160 | LC_ALL=C sort | LC_ALL=C uniq -c | LC_ALL=C sort -rn | head -15 \
    | while read -r CNT PAT; do
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$S" "$TOTAL" "$N" "$CNT" "$(LC_ALL=C awk -v c="$CNT" -v n="$N" 'BEGIN{printf "%.1f", 100*c/n}')" "$PAT"
      done
  rm -f "$TMP"
done

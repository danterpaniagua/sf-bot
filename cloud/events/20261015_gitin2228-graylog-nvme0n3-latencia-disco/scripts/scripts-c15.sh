#!/usr/bin/env bash
# C15 (solo lectura) - mensajes por nivel (AppLevel) en los streams de aplicacion PROD-*-AppServicePlan, ultimas 24 h.
# Filtra por stream (no por el campo `name`) y excluye los streams AppServiceHTTPLogs y las Function Apps.
# Se ejecuta desde la estacion local. Requiere GRAYLOG_API_KEY y jq. Salida TSV a stdout.
# Uso: bash scripts-c15.sh > data/c15-graylog-app-streams-levels.tsv
set -u
BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
RANGE=86400
[ -n "${GRAYLOG_API_KEY:-}" ] || { echo "ABORTA: GRAYLOG_API_KEY no definida" >&2; exit 1; }

count() {  # $1 = consulta, $2 = id de stream
  local out
  out=$(curl -s --max-time 180 -u "$GRAYLOG_API_KEY:token" -H 'Accept: application/json' \
        --data-urlencode "query=$1" --data-urlencode "filter=streams:$2" --data-urlencode "range=$RANGE" --data-urlencode 'limit=1' \
        -G "$BASE/search/universal/relative") || { echo ERR; return; }
  echo "$out" | jq -r 'if .total_results == null then "ERR" else .total_results end' 2>/dev/null || echo ERR
}

STREAMS=$(curl -s --max-time 60 -u "$GRAYLOG_API_KEY:token" -H 'Accept: application/json' "$BASE/streams" \
          | jq -r '.streams[]? | select(.title | test("^PROD-.*-AppServicePlan$")) | [.id, .title] | @tsv')
[ -n "$STREAMS" ] || { echo "ABORTA: no se obtuvieron streams PROD-*-AppServicePlan" >&2; exit 1; }

echo "# $(date -u +%FT%TZ) | rango ${RANGE}s | filtro por stream | host consultado: sfcloud-monitoreo (Graylog SmartCloud)"
printf 'stream\ttotal\tInformation\tWarning\tError\tFatal\tUnknown\totros_valores\n'
while IFS=$'\t' read -r ID TITLE; do
  echo "$(date -u +%T) consultando $TITLE" >&2
  T=$(count "*" "$ID")
  I=$(count 'AppLevel:"Information"' "$ID")
  W=$(count 'AppLevel:"Warning"' "$ID")
  E=$(count 'AppLevel:"Error"' "$ID")
  X=$(count 'AppLevel:"Fatal"' "$ID")
  U=$(count 'AppLevel:"Unknown"' "$ID")
  if [[ "$T$I$W$E$X$U" =~ ERR ]]; then printf '%s\tERR\t(una consulta fallo)\n' "$TITLE"; continue; fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$TITLE" "$T" "$I" "$W" "$E" "$X" "$U" "$((T-I-W-E-X-U))"
done <<< "$STREAMS"

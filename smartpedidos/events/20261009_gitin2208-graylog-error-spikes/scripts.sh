#!/usr/bin/env bash
# Event: 20261009_gitin2208-graylog-error-spikes
# C1 — (descartado) histogram/terms de la API universal: 404 en Graylog 5.2.12 de sf-monitoreo.smartfran.com:9000
#      (ver data/pull-log.txt). Reemplazado por C2.
# C2 — Solo lectura contra sf-monitoreo.smartfran.com:9000 usando solo search/universal/absolute (el mismo
#      endpoint que respondio en GITIN-2194): conteo de "ERROR" por franja (por hora desde ayer 00:00; cada
#      5 min desde hoy 08:00) y dos muestras de mensajes (08:00-inicio y desde el inicio) para agrupar por
#      fuente y texto en local. Salidas en data/. Hora local UTC-3. Token en $SML_GRAYLOG_API_KEY (nunca literal).
# Uso:  bash <ruta>/scripts.sh > <ruta>/data/pull-log-3.txt 2>&1      (DAY=YYYY-MM-DD, SINCE=HH:MM, QUERY='...', SAMPLE=2000)
# C3 — scripts-restarts.sh: solo lectura; senales de reinicio de concentrador-service en las ventanas de los picos y en una ventana de control; salidas en data/restarts/
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR

: "${SML_GRAYLOG_API_KEY:?definir SML_GRAYLOG_API_KEY en el entorno}"
BASE="http://sf-monitoreo.smartfran.com:9000/api"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261009_gitin2208-graylog-error-spikes/data"
DAY="${DAY:-2026-10-09}"; SINCE="${SINCE:-09:00}"; QUERY="${QUERY:-ERROR}"; SAMPLE="${SAMPLE:-2000}"
TAG="${TAG:-}"; COUNTS_ONLY="${COUNTS_ONLY:-0}"   # COUNTS_ONLY=1: solo series de 5 min (hoy y ayer 07:00-12:00); TAG sufija los archivos
mkdir -p "$OUT"

fmt() { date -u -d "@$1" +"%Y-%m-%dT%H:%M:%S.000Z"; }   # ISO con Z: el formato sin zona lo interpreta Graylog en UTC-3 (visto en la corrida 2)
Y0=$(date -d "$(date -d "$DAY -1 day" +%F) 00:00:00 -0300" +%s)   # ayer 00:00 local
T8=$(date -d "$DAY 08:00:00 -0300" +%s)                           # hoy 08:00 local
TS=$(date -d "$DAY $SINCE:00 -0300" +%s)                          # inicio del pico
NOW=$(date +%s)
echo "ayer 00:00 local=$(fmt $Y0) UTC | 08:00 local=$(fmt $T8) UTC | inicio=$(fmt $TS) UTC | ahora=$(fmt $NOW) UTC | query=$QUERY"

gl() { curl -sS -f -G -u "$SML_GRAYLOG_API_KEY:token" -H 'Accept: application/json' "$BASE/$1" "${@:2}"; }

search() { # search <desde-epoch> <hasta-epoch> <limite> <campos>  -> JSON de la busqueda
  gl search/universal/absolute --data-urlencode "query=$QUERY" --data-urlencode "from=$(fmt "$1")" \
     --data-urlencode "to=$(fmt "$2")" --data-urlencode "limit=$3" --data-urlencode "fields=$4" --data-urlencode "sort=timestamp:desc"
}

# 0) Prueba de acceso y de formato de fecha: debe devolver total_results numerico
probe=$(search $((NOW - 1800)) "$NOW" 1 timestamp,source,message)
echo "prueba: ERROR en los ultimos 30 min = $(jq -r '.total_results' <<<"$probe") | mensaje mas nuevo (UTC): $(jq -r '.messages[0].message.timestamp // "ninguno"' <<<"$probe") | ahora (UTC): $(fmt $NOW)"

# 1) Conteos por franja (TSV: inicio UTC, inicio local UTC-3, conteo)
count_series() { # count_series <desde> <hasta> <paso-seg> <archivo>
  : > "$4"
  local t="$1"
  while [ "$t" -lt "$2" ]; do
    local e=$((t + $3)); [ "$e" -gt "$2" ] && e="$2"
    local n; n=$(search "$t" "$e" 1 timestamp | jq -r '.total_results')
    printf '%s\t%s\t%s\n' "$(fmt "$t")" "$(date -d "@$t" +'%m-%d %H:%M')" "$n" >> "$4"
    t=$e
  done
}
if [ "$COUNTS_ONLY" = "1" ]; then
  YDAY7=$(date -d "$(date -d "$DAY -1 day" +%F) 07:00:00 -0300" +%s); YDAY12=$(date -d "$(date -d "$DAY -1 day" +%F) 12:00:00 -0300" +%s)
  count_series "$T8" "$NOW" 300 "$OUT/counts-5min-today${TAG:+-$TAG}.tsv"
  count_series "$YDAY7" "$YDAY12" 300 "$OUT/counts-5min-yesterday-0700-1200${TAG:+-$TAG}.tsv"
  echo "serie ${TAG:-ERROR}: hoy=$(wc -l < "$OUT/counts-5min-today${TAG:+-$TAG}.tsv") ayer=$(wc -l < "$OUT/counts-5min-yesterday-0700-1200${TAG:+-$TAG}.tsv") franjas"
  echo "listo"; exit 0
fi
count_series "$Y0" "$NOW" 3600 "$OUT/counts-hour.tsv"
count_series "$T8" "$NOW" 300 "$OUT/counts-5min.tsv"
echo "franjas: hora=$(wc -l < "$OUT/counts-hour.tsv") 5min=$(wc -l < "$OUT/counts-5min.tsv")"

# 2) Muestras de mensajes (solo timestamp, source y message), una por tramo para no sesgar hacia lo mas nuevo:
#    08:00-inicio, inicio-+1h y +1h-ahora
search "$T8" "$TS" "$SAMPLE" "timestamp,source,message" > "$OUT/sample-1-before.json"
search "$TS" $((TS + 3600)) "$SAMPLE" "timestamp,source,message" > "$OUT/sample-2-firsthour.json"
search $((TS + 3600)) "$NOW" "$SAMPLE" "timestamp,source,message" > "$OUT/sample-3-rest.json"
for f in sample-1-before sample-2-firsthour sample-3-rest; do
  echo "$f: total=$(jq '.total_results' "$OUT/$f.json") traidos=$(jq '.messages|length' "$OUT/$f.json")"
done
echo "listo"

#!/usr/bin/env bash
# GITIN-2251 (v2 of graylog-iis-1711-1716gmt.sh): IIS requests of one WEBS host, counted by the time the request happened
# (IIS fields date + time, GMT) and not by the time Graylog received the line. Graylog is queried by receive time over a wider
# range (17:08-17:20 GMT of 2026-10-18, one request per minute) so lines delivered late are not lost; the window that is analysed
# is 17:11:00-17:15:59 of the IIS time. Also reports the ingestion lag (EventReceivedTime minus IIS time).
# Read-only: GET /api/search/universal/absolute. Usage: graylog-iis-1711-1716gmt-v2.sh [HOST] (default SFCG-WEBS-02).
# Needs $SML_GRAYLOG_API_KEY. The client IP (c-ip) is not requested; raw files (detail-*) may still hold URL stems with
# identifiers: keep them out of version control and out of tickets.
set -u
export LC_ALL=C
H="${1:-SFCG-WEBS-02}"
TAG=$(printf '%s' "${H#SFCG-}" | tr 'A-Z' 'a-z')
DIR=/home/dpaniagua/Documentos/git/bots/loyalty/events/20261018_gitin2251-webs-db-misma-ventana/data
BASE="http://sf-monitoreo.smartfran.com:9000/api/search/universal/absolute"
FIELDS="timestamp,s-computername,cs-method,cs-uri-stem,sc-status,time-taken,date,time,EventReceivedTime"
OUT="$DIR/graylog-${TAG}-iis-hora-real-resumen.txt"
TMP=$(mktemp)

for m in 08 09 10 11 12 13 14 15 16 17 18 19; do
  n=$(printf '%02d' $((10#$m + 1)))
  f="$DIR/detail-graylog-${TAG}-v2-17${m}.json"
  curl -s -G -u "$SML_GRAYLOG_API_KEY:token" -H "Accept: application/json" "$BASE" \
    --data-urlencode "query=\"$H\"" \
    --data-urlencode "from=2026-10-18T17:${m}:00.000Z" \
    --data-urlencode "to=2026-10-18T17:${n}:00.000Z" \
    --data-urlencode "limit=3000" \
    --data-urlencode "fields=$FIELDS" > "$f"
  echo "recibido 17:${m} GMT total_results=$(jq -r '.total_results // "ERROR"' "$f") returned=$(jq -r '.messages | length' "$f" 2>/dev/null)" >> "$TMP"
done

jq -s --arg h "$H" '
  def epoch(d; t): ("\(d) \(t)" | strptime("%Y-%m-%d %H:%M:%S") | mktime);
  [.[].messages[]?.message | select((.["s-computername"] // "") | startswith($h))] as $all
  | ($all | map(select(.date == "2026-10-18" and .time >= "17:11:00" and .time < "17:16:00"))) as $m
  | ($m | map(select(.["cs-uri-stem"] == "/Service/SaleProvider.svc" and .["cs-method"] == "POST"))) as $sp
  | ($m | map(epoch(.date; .time) as $t | ((.EventReceivedTime | strptime("%Y-%m-%d %H:%M:%S") | mktime) - $t)) | sort) as $lag
  | {
      host: $h,
      mensajes_hora_iis_1711_1716: ($m | length),
      saleprovider_post: ($sp | length),
      saleprovider_500: ($sp | map(select(.["sc-status"] == 500)) | length),
      saleprovider_por_minuto_iis: ($sp | group_by(.time[0:5]) | map({minuto: .[0].time[0:5], n: length,
        s500: (map(select(.["sc-status"] == 500)) | length),
        mayor_10s: (map(select((.["time-taken"] // 0 | tonumber) > 10000)) | length),
        max_ms: (map(.["time-taken"] // 0 | tonumber) | max)})),
      healthcheck_por_status: ($m | map(select(.["cs-uri-stem"] == "/healthcheck.ashx")) | group_by(.["sc-status"])
        | map({status: .[0]["sc-status"], n: length})),
      healthcheck_400_horas_iis: ($m | map(select(.["cs-uri-stem"] == "/healthcheck.ashx" and .["sc-status"] == 400) | .time) | sort),
      retraso_ingesta_segundos: (if ($lag | length) == 0 then null else
        {min: $lag[0], mediana: $lag[($lag | length / 2 | floor)], p95: $lag[($lag | length * 0.95 | floor)], max: $lag[-1]} end),
      retraso_max_por_minuto_iis: ($m | group_by(.time[0:5]) | map({minuto: .[0].time[0:5],
        max_s: (map((.EventReceivedTime | strptime("%Y-%m-%d %H:%M:%S") | mktime) - epoch(.date; .time)) | max)}))
    }' "$DIR"/detail-graylog-${TAG}-v2-17*.json > "$OUT.json"

{ cat "$TMP"; cat "$OUT.json"; } > "$OUT"
rm -f "$TMP" "$OUT.json"
cat "$OUT"

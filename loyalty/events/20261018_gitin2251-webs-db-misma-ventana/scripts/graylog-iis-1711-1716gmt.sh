#!/usr/bin/env bash
# GITIN-2251: IIS requests of one WEBS host in Graylog between 17:11 and 17:16 GMT of 2026-10-18 (V1, the 5 minutes in which
# session 117 used 97.5 s of CPU on the database). Read-only: GET /api/search/universal/absolute, one request per minute.
# Usage: graylog-iis-1711-1716gmt.sh [HOST]   (default SFCG-WEBS-02; also SFCG-WEBS-01, SFCG-WEBS-03 to compare)
# Needs $SML_GRAYLOG_API_KEY (access token). The client IP (c-ip) is not requested. The raw files (detail-*) can still hold
# URL stems with identifiers: keep them out of version control and out of tickets.
set -u
export LC_ALL=C
H="${1:-SFCG-WEBS-02}"
TAG=$(printf '%s' "${H#SFCG-}" | tr 'A-Z' 'a-z')
DIR=/home/dpaniagua/Documentos/git/bots/loyalty/events/20261018_gitin2251-webs-db-misma-ventana/data
BASE="http://sf-monitoreo.smartfran.com:9000/api/search/universal/absolute"
FIELDS="timestamp,s-computername,cs-method,cs-uri-stem,sc-status,sc-substatus,time-taken"
OUT="$DIR/graylog-${TAG}-1711-1716gmt-resumen.txt"
TMP=$(mktemp)

for m in 11 12 13 14 15; do
  n=$((m + 1))
  f="$DIR/detail-graylog-${TAG}-iis-17${m}.json"
  curl -s -G -u "$SML_GRAYLOG_API_KEY:token" -H "Accept: application/json" "$BASE" \
    --data-urlencode "query=\"$H\"" \
    --data-urlencode "from=2026-10-18T17:${m}:00.000Z" \
    --data-urlencode "to=2026-10-18T17:${n}:00.000Z" \
    --data-urlencode "limit=3000" \
    --data-urlencode "fields=$FIELDS" > "$f"
  echo "17:${m} GMT total_results=$(jq -r '.total_results // "ERROR"' "$f") returned=$(jq -r '.messages | length' "$f" 2>/dev/null)" >> "$TMP"
done

jq -s --arg h "$H" '
  [.[].messages[]?.message | select((.["s-computername"] // "") | startswith($h))] as $m
  | ($m | map(select(.["cs-uri-stem"] == "/Service/SaleProvider.svc" and .["cs-method"] == "POST"))) as $sp
  | {
      host: $h,
      mensajes: ($m | length),
      por_metodo: ($m | group_by(.["cs-method"] // "-") | map({metodo: (.[0]["cs-method"] // "-"), n: length})),
      por_status: ($m | group_by(.["sc-status"] // "-") | map({status: (.[0]["sc-status"] // "-"), n: length})),
      por_uri_top25: ($m | group_by((.["cs-method"] // "-") + " " + (.["cs-uri-stem"] // "-"))
        | map({req: ((.[0]["cs-method"] // "-") + " " + (.[0]["cs-uri-stem"] // "-")), n: length,
               tiempo_max_ms: (map(.["time-taken"] // 0 | tonumber) | max),
               tiempo_suma_ms: (map(.["time-taken"] // 0 | tonumber) | add)})
        | sort_by(-.n) | .[0:25]),
      saleprovider_por_minuto: ($sp | group_by(.timestamp[0:16]) | map({minuto: .[0].timestamp[0:16], n: length,
        s500: (map(select(.["sc-status"] == 500)) | length),
        mayor_10s: (map(select((.["time-taken"] // 0 | tonumber) > 10000)) | length),
        max_ms: (map(.["time-taken"] // 0 | tonumber) | max)})),
      saleprovider_500_por_substatus: ($sp | map(select(.["sc-status"] == 500)) | group_by(.["sc-substatus"] // "-")
        | map({substatus: (.[0]["sc-substatus"] // "-"), n: length})),
      healthcheck_por_status: ($m | map(select(.["cs-uri-stem"] == "/healthcheck.ashx")) | group_by(.["sc-status"])
        | map({status: .[0]["sc-status"], n: length}))
    }' "$DIR"/detail-graylog-${TAG}-iis-17*.json > "$OUT.json"

{ cat "$TMP"; cat "$OUT.json"; } > "$OUT"
rm -f "$TMP" "$OUT.json"
cat "$OUT"

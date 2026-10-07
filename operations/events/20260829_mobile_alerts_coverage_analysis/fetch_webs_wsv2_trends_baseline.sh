#!/bin/bash
# GITIN-1965 — fallback for WebServiceV1/V2 baseline weekends (now-1w/2w/3w).
# Raw History for these 10 items was only 7d retention until just now (fixed
# to 180d, but that's not retroactive) — data older than ~7 days is genuinely
# gone from History. Trends (hourly value_min/avg/max/count) are kept 365d,
# so this pulls those instead for the baseline weekends only. "now" already
# has full per-minute History from fetch_get_post_weeks.sh — not re-pulled here.
#
# Read-only Zabbix API calls (trends.get) — no state changes.

set -euo pipefail

API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUTDIR="$(dirname "$0")/data"
mkdir -p "$OUTDIR"

WEEKS_BACK="${1:-3}"

# hostlabel:metric:itemid
ITEMS=(
  "webs01:get:51060"
  "webs01:post:51068"
  "webs02:get:51158"
  "webs02:post:51166"
  "webs03:get:51256"
  "webs03:post:51264"
  "wsv201:get:51820"
  "wsv201:post:51828"
  "wsv202:get:54402"
  "wsv202:post:54410"
)

zbx_call() {
  curl -s -X POST "$API" -H 'Content-Type: application/json-rpc' -d "$1"
}

DOW=$(TZ=America/Argentina/Cordoba date +%u)
DAYS_SINCE_SAT=$(( (DOW - 6 + 7) % 7 ))
CURRENT_SAT=$(TZ=America/Argentina/Cordoba date -d "-${DAYS_SINCE_SAT} days" +%Y-%m-%d)

for offset in $(seq 1 "$WEEKS_BACK"); do
  sat=$(date -d "$CURRENT_SAT -$((offset * 7)) days" +%Y-%m-%d)
  sun=$(date -d "$sat +1 day" +%Y-%m-%d)
  label="now-${offset}w"

  time_from=$(date -d "$sat 00:00:00 -03:00" +%s)
  time_till=$(date -d "$sun 23:59:59 -03:00" +%s)

  echo "== $label (trends): $sat/$sun =="
  for item in "${ITEMS[@]}"; do
    IFS=':' read -r hostlabel metric itemid <<< "$item"
    outfile="$OUTDIR/${label}_${hostlabel}_${metric}_trends.json"
    zbx_call '{
      "jsonrpc": "2.0",
      "method": "trends.get",
      "params": {
        "output": "extend",
        "itemids": ["'"$itemid"'"],
        "time_from": '"$time_from"',
        "time_till": '"$time_till"',
        "sortfield": "clock",
        "sortorder": "ASC"
      },
      "auth": "'"$ZABBIX_API_KEY"'",
      "id": 13
    }' | python3 -m json.tool > "$outfile"
    echo "Saved -> $outfile"
  done
done

echo
echo "Done. Run analyze_webs_wsv2_trends.py to summarize (history for 'now' + trends for baseline)."

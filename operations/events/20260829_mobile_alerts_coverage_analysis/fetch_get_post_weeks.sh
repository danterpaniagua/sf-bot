#!/bin/bash
# GITIN-1965 — dynamic weekend GET/POST puller for MobileAppService, WebService
# (V1: SFCG-WEBS-01/02/03) and WebServiceV2 (SFCG-WSV2-01/02) — cross-service
# peak-season traffic comparison. Fully relative to "now" — no hardcoded
# weekend dates. Computes the most recent Saturday (local
# America/Argentina/Cordoba, fixed UTC-3) and pulls it plus N prior weekends,
# all "as of whenever this is run".
#
# Usage: ./fetch_get_post_weeks.sh [weeks_back]   (default weeks_back=3)
# Files: data/now_<host>_<metric>.json, data/now-1w_..., data/now-2w_..., ...
# Safe to re-run any time — overwrites in place. Re-running mid-weekend
# refreshes "now" with a partial read; re-run again once the weekend closes.
#
# Read-only Zabbix API calls (history.get) — no state changes.
# Requires: $ZABBIX_API_KEY set in the environment, python3.

set -euo pipefail

API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUTDIR="$(dirname "$0")/data"
mkdir -p "$OUTDIR"

WEEKS_BACK="${1:-3}"

# hostlabel:metric:itemid:value_type — "_Total" key-instance family throughout
# (matches GITIN-1918's convention), not the newer per-app {$IIS.APP.NAME}-scoped
# duplicates (visibility-only, no trigger references them per GITIN-1966).
ITEMS=(
  "mobi01:get:52784:0"
  "mobi01:post:52792:0"
  "mobi02:get:52742:0"
  "mobi02:post:52750:0"
  "webs01:get:51060:0"
  "webs01:post:51068:0"
  "webs02:get:51158:0"
  "webs02:post:51166:0"
  "webs03:get:51256:0"
  "webs03:post:51264:0"
  "wsv201:get:51820:0"
  "wsv201:post:51828:0"
  "wsv202:get:54402:0"
  "wsv202:post:54410:0"
)

zbx_call() {
  curl -s -X POST "$API" -H 'Content-Type: application/json-rpc' -d "$1"
}

# Most recent Saturday <= today, local time. %u: 1=Mon .. 7=Sun, Saturday=6.
DOW=$(TZ=America/Argentina/Cordoba date +%u)
DAYS_SINCE_SAT=$(( (DOW - 6 + 7) % 7 ))
CURRENT_SAT=$(TZ=America/Argentina/Cordoba date -d "-${DAYS_SINCE_SAT} days" +%Y-%m-%d)

for offset in $(seq 0 "$WEEKS_BACK"); do
  sat=$(date -d "$CURRENT_SAT -$((offset * 7)) days" +%Y-%m-%d)
  sun=$(date -d "$sat +1 day" +%Y-%m-%d)
  label="now"
  [ "$offset" -gt 0 ] && label="now-${offset}w"

  # Always request the full Sat 00:00 - Sun 23:59:59 window. If "now" is
  # mid-weekend, Zabbix simply returns whatever exists up to the current
  # moment — no need to cap time_till ourselves.
  time_from=$(date -d "$sat 00:00:00 -03:00" +%s)
  time_till=$(date -d "$sun 23:59:59 -03:00" +%s)

  echo "== $label: $sat/$sun  ($(date -d @"$time_from") -> $(date -d @"$time_till")) =="
  for item in "${ITEMS[@]}"; do
    IFS=':' read -r hostlabel metric itemid value_type <<< "$item"
    outfile="$OUTDIR/${label}_${hostlabel}_${metric}.json"
    zbx_call '{
      "jsonrpc": "2.0",
      "method": "history.get",
      "params": {
        "output": "extend",
        "history": '"$value_type"',
        "itemids": ["'"$itemid"'"],
        "time_from": '"$time_from"',
        "time_till": '"$time_till"',
        "sortfield": "clock",
        "sortorder": "ASC"
      },
      "auth": "'"$ZABBIX_API_KEY"'",
      "id": 5
    }' | python3 -m json.tool > "$outfile"
    echo "Saved -> $outfile"
  done
done

echo
echo "Done. Run analyze_weekend_get_post.py to summarize — it auto-discovers all data/*_mobi01_get.json."

#!/usr/bin/env bash
# Read-only (trend.get / item.get): 30 days of hourly trends for Total Method Requests/Sec on MOBI-02 (item 52755) and MOBI-01 (item 52797), to size spike thresholds.
# Prints per-day max-of-hourly-max and median-of-hourly-avg, plus how many hours exceeded 15/20/25/30/45 req/s (hourly max). Times in UTC.
set -euo pipefail
API=${API:-http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php}
: "${ZABBIX_API_KEY:?ZABBIX_API_KEY not set}"
FROM=$(date -u -d '30 days ago' +%s)
rpc() {
  local r
  r=$(jq -nc --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,id:1,auth:$a}' \
      | curl -s -X POST "$API" -H 'Content-Type: application/json' -d @-)
  if [ "$(jq 'has("error")' <<<"$r")" = true ]; then echo "ERROR $1: $(jq -c .error <<<"$r")" >&2; return 1; fi
  jq -c .result <<<"$r"
}
echo "== now: $(date '+%F %T %z') =="
for i in 52755 52797; do
  rpc item.get "$(jq -nc --arg i "$i" '{itemids:[$i],output:["itemid","name","key_"],selectHosts:["host"]}')" | jq -c '.[]|{itemid,host:.hosts[0].host,key_}'
  T=$(rpc trend.get "$(jq -nc --arg i "$i" --argjson f "$FROM" '{itemids:[$i],time_from:$f,output:["clock","num","value_min","value_avg","value_max"]}')")
  echo "hourly points: $(jq length <<<"$T")"
  echo "-- per day (UTC): date  max-hourly-max  max-hourly-avg  median-hourly-avg"
  jq -r 'group_by(.clock|tonumber|strftime("%F"))[]|{d:(.[0].clock|tonumber|strftime("%F")),mx:(map(.value_max|tonumber)|max),ma:(map(.value_avg|tonumber)|max),med:(map(.value_avg|tonumber)|sort|.[(length/2|floor)])}|"\(.d) \(.mx*10|round/10) \(.ma*10|round/10) \(.med*10|round/10)"' <<<"$T"
  echo "-- hours with hourly max above N req/s"
  for n in 15 20 25 30 45 60; do echo "  >$n: $(jq --argjson n "$n" '[.[]|select((.value_max|tonumber)>$n)]|length' <<<"$T")"; done
done

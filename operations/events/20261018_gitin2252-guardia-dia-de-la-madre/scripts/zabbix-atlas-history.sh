#!/usr/bin/env bash
# GITIN-2252 — read-only (history.get): Atlas shard CPU, RAM and network (items collected by Zabbix every 10 minutes) from Friday 2026-10-16 00:00 UTC-3 until now.
# Per shard and metric: per-day maximum / mean / time of the maximum (UTC-3), and the maximum inside the windows that matter (Fri 13:47-23:59; Sun 14:03-15:28, 16:34-17:10, 17:10-18:20, 19:02-19:18).
# Item ids from data/zabbix-atlas-discovery-2205.txt. The "AVG Reads Latency" items (53367-53369) are NOT used: their values equal the RAM values.
set -euo pipefail
API=${API:-http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php}
: "${ZABBIX_API_KEY:?ZABBIX_API_KEY not set}"
FROM=$(date -u -d '2026-10-16 03:00:00' +%s); TILL=$(date -u +%s)
ITEMS="50548:00:CPU(%):0 50549:01:CPU(%):0 50550:02:CPU(%):0 50551:00:RAM(MB):3 50552:01:RAM(MB):3 50553:02:RAM(MB):3 50554:00:NetIn(B):3 50555:01:NetIn(B):3 50556:02:NetIn(B):3 50557:00:NetOut(B):3 50558:01:NetOut(B):3 50559:02:NetOut(B):3"
echo "== now: $(date '+%F %T %z'); window UTC $FROM-$TILL; update interval of the items 10 min =="
for it in $ITEMS; do
  IFS=: read -r id shard name vt <<<"$it"
  r=$(jq -nc --arg i "$id" --argjson vt "$vt" --argjson f "$FROM" --argjson t "$TILL" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:"history.get",id:1,auth:$a,params:{itemids:[$i],history:$vt,time_from:$f,time_till:$t,output:["clock","value"],sortfield:"clock",limit:5000}}' | curl -s -X POST "$API" -H 'Content-Type: application/json' -d @-)
  [ "$(jq 'has("error")' <<<"$r")" = true ] && { echo "ERROR item $id: $(jq -c .error <<<"$r")" >&2; continue; }
  echo "== shard-$shard $name item $id: $(jq '.result|length' <<<"$r") points =="
  jq -r '
    def hm(c): (c-10800)|strftime("%H:%M");
    def day(c): (c-10800)|strftime("%m-%d");
    def inw(c;a;b): ((c-10800)|strftime("%H:%M")) as $h | $h>=a and $h<b;
    .result|map({c:(.clock|tonumber),v:(.value|tonumber)}) as $p |
    ($p|group_by(day(.c))[]|"  day \(day(.[0].c)): max \(map(.v)|max*100|round/100) at \(max_by(.v)|hm(.c)), mean \(((map(.v)|add)/length)*100|round/100) (\(length) pts)"),
    (["Fri 13:47-23:59","10-16","13:47","23:59"],["W1 Sun 14:03-15:28","10-18","14:03","15:28"],["W2 Sun 16:34-17:10","10-18","16:34","17:10"],["W3 Sun 17:10-18:20","10-18","17:10","18:20"],["W4 Sun 19:02-19:18","10-18","19:02","19:18"]) as $w |
    ($p|map(select(day(.c)==$w[1] and inw(.c;$w[2];$w[3])))) as $q |
    "  \($w[0]): " + (if ($q|length)==0 then "no points" else "max \($q|map(.v)|max*100|round/100) at \($q|max_by(.v)|hm(.c)) (\($q|length) pts)" end)' <<<"$r"
done

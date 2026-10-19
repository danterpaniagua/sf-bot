#!/usr/bin/env bash
# GITIN-2250 — read-only pull for validating the balancer probe (healthcheck.ashx) against CPU, 2026-10-18 from 10:00 UTC-3 until now.
#  - Azure Monitor DipAvailability per backend IP, 1-minute average (probe every 15 s, so values move in steps of 25 %)  -> data/webs-dip-1min-<HHMM>.json
#  - Zabbix CPU util (1-minute items) of WEBS-01/02/03 (51092 / 51190 / 51288)                                          -> data/webs-cpu-1min-<HHMM>.jsonl
# Backend IPs: .101 = WEBS-01, .102 = WEBS-02, .103 = WEBS-03. Analysis afterwards with webs-healthcheck-validate.py (local, reads these files).
set -uo pipefail
EV=/home/dpaniagua/Documentos/git/bots/loyalty/events/20261018_gitin2250-webservice-high-cpu
SUB=0190fa7d-4ccf-4e3d-beb1-323b5780bfc8
API=${API:-http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php}
: "${ZABBIX_API_KEY:?ZABBIX_API_KEY not set}"
T=$(date +%H%M); START_ISO=2026-10-18T13:00:00Z; START=$(date -u -d "$START_ISO" +%s); NOW=$(date +%s)
LBID=$(az network lb show --subscription $SUB -g DefaultGroup01 -n SFCG-WEBS-LB --query id -o tsv)
az monitor metrics list --subscription $SUB --resource "$LBID" --metric DipAvailability --dimension BackendIPAddress --interval PT1M --aggregation Average \
  --start-time "$START_ISO" --end-time "$(date -u +%FT%TZ)" -o json > "$EV/data/webs-dip-1min-$T.json" 2> "$EV/data/webs-dip-1min-$T.err"
: > "$EV/data/webs-cpu-1min-$T.jsonl"
for id in 51092 51190 51288; do
  curl -s -X POST "$API" -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","method":"history.get","id":1,"auth":"'"$ZABBIX_API_KEY"'","params":{"itemids":["'$id'"],"history":0,"time_from":'$START',"time_till":'$NOW',"output":["itemid","clock","value"],"sortfield":"clock","limit":5000}}' \
  | jq -c '.result[]?' >> "$EV/data/webs-cpu-1min-$T.jsonl"
done
echo "dip: $(wc -c < "$EV/data/webs-dip-1min-$T.json") bytes (errors: $(wc -c < "$EV/data/webs-dip-1min-$T.err") bytes); cpu points: $(wc -l < "$EV/data/webs-cpu-1min-$T.jsonl"); suffix $T"

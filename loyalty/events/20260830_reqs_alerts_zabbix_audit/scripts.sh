EVENTDIR="loyalty/events/20260830_reqs_alerts_zabbix_audit"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"

# ALL global macros — no filter, to catch every family (PERF_COUNT_TRIG_*,
# IIS_REQUESTS_WSV1_POST, DROP.*, MOBILE_PCOUNT_SPIKE_*, etc.)
curl -s "$API" -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0",
    "method": "usermacro.get",
    "params": {
      "output": "extend",
      "globalmacro": true
    },
    "auth": "'"$ZABBIX_API_KEY"'",
    "id": 2
  }' | jq . > "$EVENTDIR/all-global-macros.json"

# GITIN-1961 — creates the missing WEBSCG01 macro context + 3-tier IIS
# "Method Total requests per second" trigger on SFCG-WSCG-01's item 53770.
# WRITES real Zabbix config (global macros + host triggers). Run once.

EVENTDIR="loyalty/events/20260828_wscg01_zabbix_graylog_onboarding"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"

# 1) Global macros (WEBSCG01 context)
curl -s "$API" -H 'Content-Type: application/json' \
  -d "$(jq --arg auth "$ZABBIX_API_KEY" '. + {auth: $auth}' "$EVENTDIR/fix-macros.json")" \
  | jq . | tee "$EVENTDIR/result-macros.json"

# 2) Warning-tier trigger — capture its triggerid for the Average tier's dependency
curl -s "$API" -H 'Content-Type: application/json' \
  -d "$(jq --arg auth "$ZABBIX_API_KEY" '. + {auth: $auth}' "$EVENTDIR/fix-trigger-warning.json")" \
  | jq . | tee "$EVENTDIR/result-trigger-warning.json"

WARNING_ID=$(jq -r '.result.triggerids[0]' "$EVENTDIR/result-trigger-warning.json")
echo "Warning triggerid: $WARNING_ID"

# 3) Average-tier trigger (depends on Warning) — capture its triggerid for High
sed "s/__WARNING_ID__/$WARNING_ID/" "$EVENTDIR/fix-trigger-average.json" > "$EVENTDIR/fix-trigger-average.resolved.json"
curl -s "$API" -H 'Content-Type: application/json' \
  -d "$(jq --arg auth "$ZABBIX_API_KEY" '. + {auth: $auth}' "$EVENTDIR/fix-trigger-average.resolved.json")" \
  | jq . | tee "$EVENTDIR/result-trigger-average.json"

AVERAGE_ID=$(jq -r '.result.triggerids[0]' "$EVENTDIR/result-trigger-average.json")
echo "Average triggerid: $AVERAGE_ID"

# 4) High-tier trigger (depends on Average)
sed "s/__AVERAGE_ID__/$AVERAGE_ID/" "$EVENTDIR/fix-trigger-high.json" > "$EVENTDIR/fix-trigger-high.resolved.json"
curl -s "$API" -H 'Content-Type: application/json' \
  -d "$(jq --arg auth "$ZABBIX_API_KEY" '. + {auth: $auth}' "$EVENTDIR/fix-trigger-high.resolved.json")" \
  | jq . | tee "$EVENTDIR/result-trigger-high.json"

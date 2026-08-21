#!/usr/bin/env bash
# Event: 20260819_gitin1883-config-drift
# Root-cause why GITIN-1883's later 2 patches (Service/Environment promotion,
# Sales naming-unification) aren't on the live VM despite being documented as
# deployed and verified. Read-only checks — no state change, no banner needed.

BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"

# === C1 — current source of the 3 Graylog Pipeline Rules GITIN-1883 claims it updated ===
# Expect bare "Service"/"Environment" if the rule update persisted, or
# "Properties_Service"/"Properties_Environment" if it reverted too.
for rule_id in 6a7f29664814bcaed30c7de7 6a7f24784814bcaed30c6d52 6a7f2cb84814bcaed30c8de3; do
  echo "=== rule ${rule_id} ==="
  curl -s -u "${GRAYLOG_API_KEY}:token" -H "Accept: application/json" \
    "${BASE}/system/pipelines/rule/${rule_id}" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print('title:', d.get('title'))
print('source:')
print(d.get('source'))
"
done

# === C2 — current live Sales traffic: bare fields or Properties_* prefix? ===
RESP1=$(curl -s -u "${GRAYLOG_API_KEY}:token" \
  -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
  -d '{
    "queries": [{
      "id": "q1",
      "query": {"type": "elasticsearch", "query_string": "name:\"SMARTFRAN-CLOUD-SALES-PRO\""},
      "timerange": {"type": "relative", "range": 3600},
      "search_types": [{"id": "msg1", "type": "messages", "limit": 1}]
    }]
  }' \
  "${BASE}/views/search")
SEARCH_ID=$(echo "$RESP1" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])" 2>/dev/null)
if [ -z "$SEARCH_ID" ]; then echo "C2 FAILED at search creation: $RESP1"; else
  RESP2=$(curl -s -u "${GRAYLOG_API_KEY}:token" \
    -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
    -d '{}' "${BASE}/views/search/${SEARCH_ID}/execute")
  JOB_ID=$(echo "$RESP2" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])" 2>/dev/null)
  for i in $(seq 1 15); do
    curl -s -u "${GRAYLOG_API_KEY}:token" -H "Accept: application/json" \
      "${BASE}/views/search/status/${JOB_ID}" -o c2-sales-sample.json
    if python3 -c "import json,sys; sys.exit(0 if json.load(open('c2-sales-sample.json'))['execution']['done'] else 1)" 2>/dev/null; then break; fi
    sleep 1
  done
  python3 -c "
import json
d = json.load(open('c2-sales-sample.json'))
msgs = d['results']['q1']['search_types']['msg1']['messages']
if not msgs:
    print('C2: 0 messages in last hour for Sales-PRO')
else:
    keys = sorted(msgs[0]['message'].keys())
    print('C2 top-level keys:', keys)
    print('has bare Service:', 'Service' in keys, '| has Properties_Service:', 'Properties_Service' in keys)
    print('has bare Environment:', 'Environment' in keys, '| has Properties_Environment:', 'Properties_Environment' in keys)
"
fi

# === C3 — VM file mtime + check for patch backup/reject files ===
# ⚠️ Read-only (ls/stat/cat), but included here since it's SSH — presented as
# a copy-paste block per project convention regardless.
ssh -i ~/.ssh/sfcloud_monitoreo -p 5689 gadmin@sfcloud-monitoreo.smartfran.com \
  'stat /etc/logstash/conf.d/azure-eventhub-to-graylog.conf; echo "---"; ls -la /etc/logstash/conf.d/ | grep -i "azure-eventhub\|\.orig\|\.bak\|\.rej"'

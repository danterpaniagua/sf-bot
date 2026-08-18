#!/usr/bin/env bash
# Event: 20260818_properties-flat-other-services (GITIN-1883)
# Fetch one real AppServiceConsoleLogs message per app (PROD) via Graylog's
# Views Search API (3-step: create -> execute -> poll status), same pattern
# as bots/cloud/events/20260812_prod-full-onboarding/scripts.sh C10.
# Read-only — no state change, no banner needed.

# === INVESTIGATION ===
# C1 — one AppServiceConsoleLogs message per app, saved to console-logs-samples/
BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
mkdir -p console-logs-samples

for app in Sales Business Pos Platform Person Admin Catalog Orders; do
  echo "=== ${app} ==="
  SEARCH_ID=$(curl -s -u "${GRAYLOG_API_KEY}:token" \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    -H "X-Requested-By: cli" \
    -d "{
      \"queries\": [{
        \"id\": \"q1\",
        \"query\": {\"type\": \"elasticsearch\", \"query_string\": \"category:\\\"AppServiceConsoleLogs\\\" AND name:\\\"SMARTFRAN-CLOUD-${app^^}-PRO\\\"\"},
        \"timerange\": {\"type\": \"relative\", \"range\": 604800},
        \"search_types\": [{
          \"id\": \"msg1\", \"type\": \"messages\", \"limit\": 1
        }]
      }]
    }" \
    "${BASE}/views/search" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")

  JOB_ID=$(curl -s -u "${GRAYLOG_API_KEY}:token" \
    -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
    -d '{}' "${BASE}/views/search/${SEARCH_ID}/execute" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")

  curl -s -u "${GRAYLOG_API_KEY}:token" -H "Accept: application/json" \
    "${BASE}/views/search/status/${JOB_ID}" \
    -o "console-logs-samples/${app,,}.json"

  python3 -m json.tool "console-logs-samples/${app,,}.json" > /dev/null \
    && echo "saved console-logs-samples/${app,,}.json" \
    || echo "WARNING: ${app} response is not valid JSON — check manually"
done

# === REMEDIATION (not yet run — do C2 before C3, see ops.md Acciones propuestas #1) ===
# C2 — diff done 2026-08-18: only the credential lines (Event Hub SAS / storage
# key, live-only, correctly placeholder'd in the repo copy) and our new
# GITIN-1883 block differ. No other drift like GITIN-1835 found. Because of
# the credential difference, do NOT scp/overwrite the whole file (C3 below
# uses a scoped patch instead, which never touches the credential lines).

# ⚠️ C3 — apply only the new block to the live file via patch, validate, restart
scp -i ~/.ssh/sfcloud_monitoreo -P 5689 \
  ~/Documentos/git/bots/cloud/events/20260818_properties-flat-other-services/gitin-1883.patch \
  gadmin@sfcloud-monitoreo.smartfran.com:/tmp/gitin-1883.patch
ssh -i ~/.ssh/sfcloud_monitoreo -p 5689 gadmin@sfcloud-monitoreo.smartfran.com 'cd /etc/logstash/conf.d && sudo patch --dry-run -p1 < /tmp/gitin-1883.patch'
# Only proceed if the dry-run prints "patching file azure-eventhub-to-graylog.conf" with no "FAILED" hunks.
ssh -i ~/.ssh/sfcloud_monitoreo -p 5689 gadmin@sfcloud-monitoreo.smartfran.com 'cd /etc/logstash/conf.d && sudo patch -p1 < /tmp/gitin-1883.patch && sudo -u logstash /usr/share/logstash/bin/logstash -t --path.settings /etc/logstash'
# Only proceed to restart if the line above prints "Configuration OK".
# ⚠️ C4 — restart Logstash to pick up the new pipeline
ssh -i ~/.ssh/sfcloud_monitoreo -p 5689 gadmin@sfcloud-monitoreo.smartfran.com 'sudo systemctl restart logstash && sudo systemctl status logstash --no-pager'

# === VERIFICATION (after C4, wait a few minutes for traffic) ===
# C5 — confirm TraceKey/TenantId are populated on live traffic, per affected app
BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
for field in TraceKey TenantId; do
  echo "=== _exists_:${field} ==="
  SEARCH_ID=$(curl -s -u "${GRAYLOG_API_KEY}:token" \
    -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
    -d "{
      \"queries\": [{
        \"id\": \"q1\",
        \"query\": {\"type\": \"elasticsearch\", \"query_string\": \"_exists_:${field}\"},
        \"timerange\": {\"type\": \"relative\", \"range\": 1800},
        \"search_types\": [{
          \"id\": \"agg1\", \"type\": \"pivot\",
          \"row_groups\": [{\"type\": \"values\", \"field\": \"name\", \"limit\": 20}],
          \"series\": [{\"type\": \"count\", \"id\": \"count()\"}],
          \"rollup\": true
        }]
      }]
    }" \
    "${BASE}/views/search" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
  JOB_ID=$(curl -s -u "${GRAYLOG_API_KEY}:token" \
    -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
    -d '{}' "${BASE}/views/search/${SEARCH_ID}/execute" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
  curl -s -u "${GRAYLOG_API_KEY}:token" -H "Accept: application/json" \
    "${BASE}/views/search/status/${JOB_ID}" -o "verify-${field}.json"
done

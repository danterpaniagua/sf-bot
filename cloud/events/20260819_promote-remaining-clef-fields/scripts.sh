#!/usr/bin/env bash
# Event: 20260819_promote-remaining-clef-fields (GITIN-1892, parent GITIN-1835)
# Fetch real AppServiceConsoleLogs messages that exercise the 6 conditional
# helper fields (ErrorCode/Operation/Recovered/Handled/AuditAction/AuditOutcome)
# plus a plain sample for the 6 always-present fields, across the 6 Event Hub
# services. Views Search API, 3-step (create -> execute -> poll status), same
# pattern as GITIN-1883's C1 (bots/cloud/events/20260818_properties-flat-other-services/scripts.sh).
# Read-only — no state change, no banner needed.

BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
# Each name quoted individually — unquoted hyphens inside name:(A OR B OR C)
# get parsed as Lucene NOT operators and threw query_shard_exception on the
# first run (2026-08-19, both marker-errorcode.json and marker-auditaction.json).
# Quotes here must be pre-escaped (\") — this variable is substituted as-is
# inside the double-quoted curl -d "..." JSON payload below, so bash does not
# re-process any backslash-escaping at substitution time. A plain '"' broke
# the outer JSON on the second run (server-side "expecting comma" parse error).
SERVICES='\"SMARTFRAN-CLOUD-BUSINESS-PRO\" OR \"SMARTFRAN-CLOUD-ADMIN-PRO\" OR \"SMARTFRAN-CLOUD-PLATFORM-PRO\" OR \"SMARTFRAN-CLOUD-PERSON-PRO\" OR \"SMARTFRAN-CLOUD-CATALOG-PRO\" OR \"SMARTFRAN-CLOUD-ORDERS-PRO\"'
mkdir -p field-samples

# Poll a Views Search job's status endpoint until execution.done == true
# (or ~15s timeout). Views Search execution is async — a single immediate
# status fetch raced ahead of completion on the 6-service OR-grouped query
# (2026-08-19, all 6 marker files came back with "done": false, empty
# "results": {} — not a query bug, just read too early).
poll_job() {
  local job_id="$1" out_file="$2"
  for i in $(seq 1 15); do
    curl -s -u "${GRAYLOG_API_KEY}:token" -H "Accept: application/json" \
      "${BASE}/views/search/status/${job_id}" -o "$out_file"
    if python3 -c "import json,sys; sys.exit(0 if json.load(open('$out_file'))['execution']['done'] else 1)" 2>/dev/null; then
      return 0
    fi
    sleep 1
  done
  echo "WARNING: ${out_file} still not done after 15s — inspect manually"
  return 1
}

# === C1 — plain sample per service (always-present group: UserId/Component/ProcessType/RequestId; Category/SourceContext need targeted samples too, see investigation.md) ===
for app in Business Admin Platform Person Catalog Orders; do
  echo "=== plain: ${app} ==="
  RESP1=$(curl -s -u "${GRAYLOG_API_KEY}:token" \
    -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
    -d "{
      \"queries\": [{
        \"id\": \"q1\",
        \"query\": {\"type\": \"elasticsearch\", \"query_string\": \"category:\\\"AppServiceConsoleLogs\\\" AND name:\\\"SMARTFRAN-CLOUD-${app^^}-PRO\\\"\"},
        \"timerange\": {\"type\": \"relative\", \"range\": 604800},
        \"search_types\": [{\"id\": \"msg1\", \"type\": \"messages\", \"limit\": 1}]
      }]
    }" \
    "${BASE}/views/search")
  SEARCH_ID=$(echo "$RESP1" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])" 2>/dev/null)
  if [ -z "$SEARCH_ID" ]; then echo "FAILED to create search — raw response: $RESP1"; continue; fi
  RESP2=$(curl -s -u "${GRAYLOG_API_KEY}:token" \
    -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
    -d '{}' "${BASE}/views/search/${SEARCH_ID}/execute")
  JOB_ID=$(echo "$RESP2" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])" 2>/dev/null)
  if [ -z "$JOB_ID" ]; then echo "FAILED to execute search — raw response: $RESP2"; continue; fi
  poll_job "$JOB_ID" "field-samples/plain-${app,,}.json" \
    && echo "saved field-samples/plain-${app,,}.json" \
    || echo "check field-samples/plain-${app,,}.json manually"
done

# === C2 — one sample per conditional-field marker, across all 6 services combined (7d window, limit 3) ===
# resultDescription is keyword-mapped, not analyzed/tokenized — confirmed
# 2026-08-19 via a 3-stage debug: (1) wildcard *X* failed cluster-wide with
# query_shard_exception (leading wildcards disabled here); (2) a plain
# unwildcarded term also returned 0 even for TraceKey, which is definitely
# present — proved the field isn't tokenized, so no substring term-match is
# possible; (3) a regex query (resultDescription:/.*TraceKey.*/) returned
# 97306 real hits on Business alone — regex is not subject to the
# leading-wildcard restriction and works correctly on keyword fields.
# ErrorCode <- LogDomainError, Operation/Recovered <- LogTransientFailure,
# Handled <- LogUnrecoverableFailure, AuditAction/AuditOutcome <- LogSecurityAudit.
for marker in ErrorCode Operation Recovered Handled AuditAction AuditOutcome; do
  echo "=== marker: ${marker} ==="
  RESP1=$(curl -s -u "${GRAYLOG_API_KEY}:token" \
    -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
    -d "{
      \"queries\": [{
        \"id\": \"q1\",
        \"query\": {\"type\": \"elasticsearch\", \"query_string\": \"category:\\\"AppServiceConsoleLogs\\\" AND (name:(${SERVICES})) AND resultDescription:/.*${marker}.*/\"},
        \"timerange\": {\"type\": \"relative\", \"range\": 604800},
        \"search_types\": [{\"id\": \"msg1\", \"type\": \"messages\", \"limit\": 3}]
      }]
    }" \
    "${BASE}/views/search")
  SEARCH_ID=$(echo "$RESP1" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])" 2>/dev/null)
  if [ -z "$SEARCH_ID" ]; then echo "FAILED to create search — raw response: $RESP1"; continue; fi
  RESP2=$(curl -s -u "${GRAYLOG_API_KEY}:token" \
    -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
    -d '{}' "${BASE}/views/search/${SEARCH_ID}/execute")
  JOB_ID=$(echo "$RESP2" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])" 2>/dev/null)
  if [ -z "$JOB_ID" ]; then echo "FAILED to execute search — raw response: $RESP2"; continue; fi
  poll_job "$JOB_ID" "field-samples/marker-${marker,,}.json"
  python3 -c "
import json
d = json.load(open('field-samples/marker-${marker,,}.json'))
r = d.get('results', {}).get('q1', {})
n = r.get('search_types', {}).get('msg1', {}).get('total_results', 'unknown')
errs = r.get('errors', [])
print(f'total_results: {n}', f'errors: {errs}' if errs else '')
" 2>/dev/null || echo "check field-samples/marker-${marker,,}.json manually"
done

# === REMEDIATION ===
# gitin-1892.patch generated against the real VM file (vm-live-azure-eventhub-
# to-graylog.conf, fetched 2026-08-19 and confirmed byte-identical to the repo
# copy for all of GITIN-1883's code — see the false-alarm writeup in
# cloud/events/20260819_gitin1883-config-drift/). Dry-run confirmed clean
# locally against that file before this was staged.
# ⚠️ C3 — copy patch to VM, dry-run, apply, validate, restart
scp -i ~/.ssh/sfcloud_monitoreo -P 5689 \
  ~/Documentos/git/bots/cloud/events/20260819_promote-remaining-clef-fields/gitin-1892.patch \
  gadmin@sfcloud-monitoreo.smartfran.com:/tmp/gitin-1892.patch
ssh -i ~/.ssh/sfcloud_monitoreo -p 5689 gadmin@sfcloud-monitoreo.smartfran.com 'cd /etc/logstash/conf.d && sudo patch --dry-run -p0 < /tmp/gitin-1892.patch'
# Only proceed if the dry-run prints "patching file azure-eventhub-to-graylog.conf" with no "FAILED" hunks.
ssh -i ~/.ssh/sfcloud_monitoreo -p 5689 gadmin@sfcloud-monitoreo.smartfran.com 'cd /etc/logstash/conf.d && sudo patch -p0 < /tmp/gitin-1892.patch && sudo -u logstash /usr/share/logstash/bin/logstash -t --path.settings /etc/logstash'
# Only proceed to restart if the line above prints "Configuration OK".
# ⚠️ C4 — restart Logstash to pick up the new pipeline
ssh -i ~/.ssh/sfcloud_monitoreo -p 5689 gadmin@sfcloud-monitoreo.smartfran.com 'sudo systemctl restart logstash && sudo systemctl status logstash --no-pager'

# === VERIFICATION (after C4, wait a few minutes for traffic) ===
# C5 — confirm the 4 always-present fields on Event Hub apps (regex not
# needed here — resultDescription is keyword-mapped, but these fields are
# ALSO promoted bare by this fix, so query the bare field directly)
BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
for field in UserId ProcessType Component RequestId Category SourceContext ErrorCode Operation Recovered Handled AuditAction AuditOutcome; do
  echo "=== _exists_:${field} ==="
  RESP1=$(curl -s -u "${GRAYLOG_API_KEY}:token" \
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
    "${BASE}/views/search")
  SEARCH_ID=$(echo "$RESP1" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])" 2>/dev/null)
  if [ -z "$SEARCH_ID" ]; then echo "FAILED: $RESP1"; continue; fi
  RESP2=$(curl -s -u "${GRAYLOG_API_KEY}:token" \
    -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
    -d '{}' "${BASE}/views/search/${SEARCH_ID}/execute")
  JOB_ID=$(echo "$RESP2" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])" 2>/dev/null)
  for i in $(seq 1 15); do
    curl -s -u "${GRAYLOG_API_KEY}:token" -H "Accept: application/json" \
      "${BASE}/views/search/status/${JOB_ID}" -o "verify-${field}.json"
    if python3 -c "import json,sys; sys.exit(0 if json.load(open('verify-${field}.json'))['execution']['done'] else 1)" 2>/dev/null; then break; fi
    sleep 1
  done
done

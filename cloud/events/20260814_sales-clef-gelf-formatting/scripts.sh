#!/usr/bin/env bash
# Event: 20260814_sales-clef-gelf-formatting (GITIN-1835)
# BASE=https://sfcloud-monitoreo.smartfran.com/graylog/api, auth -u "$GRAYLOG_API_KEY:token"
# The fix itself (5 rules + 1 rule + pipeline, Stage 0 + Stage 1) was applied
# manually via the Graylog UI, not scripted — source lives in
# cloud-graylog/docs/sales-direct-gelf-clef-format.rule (separate repo).
# Commands below are read-only diagnostics, except C4 (marked).

# === INVESTIGATION ===

# C1 — Confirm PROD-Sales-AppServicePlan's stream routing rule (keys on field "name", exact match)
curl -s -u "${GRAYLOG_API_KEY}:token" -H "Accept: application/json" \
  "https://sfcloud-monitoreo.smartfran.com/graylog/api/streams/6a47c5c94b3c88a95fad7a7a/rules" | jq .
# OUTPUT: {"field": "name", "type": 1 (exact match), "value": "SMARTFRAN-CLOUD-SALES-PRO", "inverted": false}

# C2 — Look up a specific message by _id via the 3-step async Views Search API
#      (Graylog 7.1.3 has no legacy /api/search/universal/relative endpoint — returns bare `null`)
BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"

curl -s -u "${GRAYLOG_API_KEY}:token" \
  -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
  -d '{
    "queries": [{
      "id": "q1",
      "query": {"type": "elasticsearch", "query_string": "_id:d0465850-978d-11f1-8f28-7c1e52beabec"},
      "timerange": {"type": "relative", "range": 604800},
      "search_types": [{
        "id": "msgs1", "type": "messages", "limit": 1
      }]
    }]
  }' \
  "${BASE}/views/search"
# OUTPUT: {"id": "6a7f280b4814bcaed30c7ac7", ...} — search created

curl -s -u "${GRAYLOG_API_KEY}:token" \
  -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
  -d '{}' "${BASE}/views/search/6a7f280b4814bcaed30c7ac7/execute"
# OUTPUT: {"id": "6a7f28234814bcaed30c7b21", "execution": {"done": false}, ...} — job created, async

curl -s -u "${GRAYLOG_API_KEY}:token" -H "Accept: application/json" \
  "${BASE}/views/search/status/6a7f28234814bcaed30c7b21"
# OUTPUT: full message confirmed — same content as pasted directly from the UI earlier in the session

# === DEBUGGING (rule update UI bug) ===

# C3 — Fetch a rule's raw stored source via API, to rule out a hidden-character
#      issue when the UI's own displayed source looked correct
curl -s -u "${GRAYLOG_API_KEY}:token" -H "Accept: application/json" \
  "${BASE}/system/pipelines/rule" | \
  jq -r '.[] | select(.title == "GITIN-1835: CLEF full_message with exception") | .id'
# OUTPUT: 6a7f24584814bcaed30c6cb9

# ⚠️ C4 — Update the same rule via direct API PUT, bypassing the UI's update flow
#         (which returned an opaque "Bad Request" with no detail, for content
#         later confirmed valid). Needed because the UI's rule-CREATE flow
#         surfaces detailed parser errors, but its rule-UPDATE flow doesn't.
RULE_SOURCE=$'rule "GITIN-1835: CLEF full_message with exception"\nwhen\n  has_field("MessageTemplate") AND has_field("Exception")\nthen\n  let template = to_string($message.MessageTemplate);\n  let exception = to_string($message.Exception);\n  set_field("full_message", concat(concat(template, "\\n\\n"), exception));\nend'

curl -s -u "${GRAYLOG_API_KEY}:token" -H "Content-Type: application/json" -H "X-Requested-By: cli" \
  -X PUT "${BASE}/system/pipelines/rule/6a7f24584814bcaed30c6cb9" \
  -d "$(jq -n --arg id "6a7f24584814bcaed30c6cb9" --arg src "$RULE_SOURCE" '{id: $id, title: "GITIN-1835: CLEF full_message with exception", source: $src}')"
# OUTPUT: 200, "errors": null — succeeded cleanly via API; confirms the earlier UI "Bad Request" was a UI-only glitch, not a real syntax problem

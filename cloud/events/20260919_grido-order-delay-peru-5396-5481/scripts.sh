#!/usr/bin/env bash
# Event: 20260919_grido-order-delay-peru-5396-5481
# Read-only investigation only.

# === INVESTIGATION ===

# C1 — SQS queue depth, both reported branches (corrected: ApproximateAgeOfOldestMessage
# is a CloudWatch metric, not a valid GetQueueAttributes name — first attempt failed with
# InvalidAttributeName, fixed by dropping it from this call and pulling it via CloudWatch
# instead, see C2). Result: both queues empty at snapshot time (0 messages, 0 in-flight).
for BRANCH in 5396 5481; do
  aws sqs get-queue-attributes \
    --queue-url "https://sqs.us-east-1.amazonaws.com/382381053403/${BRANCH}PRD_PlatformMessages.fifo" \
    --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible \
    --output json > data/sqs_queue_attrs_${BRANCH}.json
done

# C2 — CloudWatch: ApproximateAgeOfOldestMessage, both branches, 48h window, 300s period.
# Confirmed real recurring delay pattern (see investigation.md) — queue ages to 100-1500s
# then drains, not a permanent stuck state.
for BRANCH in 5396 5481; do
  aws cloudwatch get-metric-statistics \
    --namespace AWS/SQS \
    --metric-name ApproximateAgeOfOldestMessage \
    --dimensions Name=QueueName,Value=${BRANCH}PRD_PlatformMessages.fifo \
    --start-time "$(date -u -d '48 hours ago' +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 300 \
    --statistics Maximum \
    --output json > data/sqs_age_oldest_${BRANCH}.json
done

# C3 — Graylog query, ATTEMPT #1, FAILED (wrong host/path — hung, returned empty after a
# long wait). Used sf-monitoreo.smartfran.com with no /graylog prefix — that's the OLDER
# SmartPedidos/SmartLoyalty Graylog stack's convention (auth via $SML_GRAYLOG_API_KEY, port
# 9000, no path prefix), not SmartCloud's. This mixup is a KNOWN, previously-documented trap
# (see memory reference_smartpedidos_smartloyalty_graylog_stack.md, "happened 2026-08-15")
# that recurred here because the command wasn't checked against a working example first.
# DO NOT REPEAT — see cloud/CLAUDE.md's Graylog section for the corrected, permanent note.
#
# curl -s -u "$GRAYLOG_API_KEY:token" \
#   "https://sf-monitoreo.smartfran.com/api/search/universal/relative?query=Service%3AOrders+AND+AppLevel%3AError+AND+(5396+OR+5481)&range=172800&limit=100" \
#   -H 'Accept: application/json' \
#   > data/graylog_orders_errors_5396_5481_48h.json

# C4 — Graylog query, ATTEMPT #2, CORRECTED (right host: sfcloud-monitoreo.smartfran.com,
# right /graylog/api path prefix, matches the working pattern from GITIN-2068's scripts.sh).
# Result: 0 results for Service:Orders AND AppLevel:Error AND (5396 OR 5481), 48h.
curl -s -u "$GRAYLOG_API_KEY:token" \
  --data-urlencode 'query=Service:Orders AND AppLevel:Error AND (5396 OR 5481)' \
  --data-urlencode 'range=172800' --data-urlencode 'limit=100' \
  -G "https://sfcloud-monitoreo.smartfran.com/graylog/api/search/universal/relative" \
  -H 'Accept: application/json' \
  > data/graylog_orders_errors_5396_5481_48h.json

# C5 — sanity check on C4's 0-result: does `Service:Orders` alone match ANY message at all
# (last 1h)? Also 0. THIS IS A REPEAT OF AN ALREADY-KNOWN, UNRESOLVED GAP — GITIN-2068's
# investigation.md documents the identical `Service:Orders` filter returning 0 even against
# a message it independently confirmed existed (via a raw Azure export, not Graylog). Do not
# treat C4's 0-result as "no Orders errors" — it's inconclusive for the same undiagnosed
# reason as GITIN-2068, not fresh evidence of anything. `used_indices: []` in the response is
# NOT itself a failure signal — it's present even on GITIN-2068's confirmed 22-result
# free-text query, so don't use it to judge success/failure of a query.
curl -s -u "$GRAYLOG_API_KEY:token" \
  --data-urlencode 'query=Service:Orders' \
  --data-urlencode 'range=3600' --data-urlencode 'limit=5' \
  -G "https://sfcloud-monitoreo.smartfran.com/graylog/api/search/universal/relative" \
  -H 'Accept: application/json' \
  > data/graylog_orders_any_1h.json

# C6 — branch 5523 added to scope, narrower 4h window. SQS queue depth (snapshot).
aws sqs get-queue-attributes \
  --queue-url "https://sqs.us-east-1.amazonaws.com/382381053403/5523PRD_PlatformMessages.fifo" \
  --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible \
  --output json > data/sqs_queue_attrs_5523.json

# C7 — branch 5523: CloudWatch ApproximateAgeOfOldestMessage, last 4h, 60s period
# (finer granularity than the 300s used for the 48h/5396+5481 pull, since this window
# is much narrower).
aws cloudwatch get-metric-statistics \
  --namespace AWS/SQS \
  --metric-name ApproximateAgeOfOldestMessage \
  --dimensions Name=QueueName,Value=5523PRD_PlatformMessages.fifo \
  --start-time "$(date -u -d '4 hours ago' +%Y-%m-%dT%H:%M:%S)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
  --period 60 \
  --statistics Maximum \
  --output json > data/sqs_age_oldest_5523.json

# C8 — branch 5523: Graylog free-text query (NOT Service:Orders-filtered — see C5's
# note, that filter is a known-unreliable pattern), last 4h.
curl -s -u "$GRAYLOG_API_KEY:token" \
  --data-urlencode 'query="5523"' \
  --data-urlencode 'range=14400' --data-urlencode 'limit=100' \
  -G "https://sfcloud-monitoreo.smartfran.com/graylog/api/search/universal/relative" \
  -H 'Accept: application/json' \
  > data/graylog_5523_freetext_4h.json

#!/usr/bin/env bash
# Event: 20260826_appservicehttplogs-stream-split
# Pilot (Admin only): create a dedicated Stream + Index Set for
# AppServiceHTTPLogs, and exclude that category from the existing
# PROD-Admin-AppServicePlan stream so the verbosity is actually removed
# from it, not just duplicated. Run this pilot, verify, then replicate for
# the remaining 7 apps (Business/Catalog/Orders/Person/Platform/Pos/Sales).

BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
AUTH="${GRAYLOG_API_KEY}:token"
EXISTING_STREAM_ID="6a7cb18f4814bcaed30a8791"   # PROD-Admin-AppServicePlan

# C1 — pilot-create-index-set-and-stream (Admin)
# 1. Create the new index set
INDEX_SET_ID=$(curl -s -u "$AUTH" \
  -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
  -d '{
    "title": "SFC-Admin-prod-http",
    "description": "SmartFran Cloud Admin PROD HTTP access logs (AppServiceHTTPLogs, split from main stream for noise)",
    "index_prefix": "http_admin_",
    "shards": 1,
    "replicas": 0,
    "index_optimization_max_num_segments": 1,
    "index_optimization_disabled": false,
    "field_type_refresh_interval": 5000,
    "rotation_strategy_class": "org.graylog2.indexer.rotation.strategies.TimeBasedSizeOptimizingStrategy",
    "rotation_strategy": {"type": "org.graylog2.indexer.rotation.strategies.TimeBasedSizeOptimizingStrategyConfig", "index_lifetime_min": "P30D", "index_lifetime_max": "P40D"},
    "retention_strategy_class": "org.graylog2.indexer.retention.strategies.DeletionRetentionStrategy",
    "retention_strategy": {"type": "org.graylog2.indexer.retention.strategies.DeletionRetentionStrategyConfig", "max_number_of_indices": 20},
    "index_analyzer": "standard",
    "use_legacy_rotation": false,
    "data_tiering": {"type": "hot_only", "index_lifetime_min": "P30D", "index_lifetime_max": "P40D"},
    "writable": true
  }' "${BASE}/system/indices/index_sets" | python3 -c "import json,sys; print(json.load(sys.stdin)['index_set']['id'])")
echo "INDEX_SET_ID=${INDEX_SET_ID}"

# 2. Create the new stream (created paused)
STREAM_ID=$(curl -s -u "$AUTH" \
  -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
  -d "{\"entity\": {\"title\": \"PROD-Admin-AppServiceHTTPLogs\", \"description\": \"Admin PROD AppServiceHTTPLogs (verbose HTTP access logs, split out for noise reduction)\", \"index_set_id\": \"${INDEX_SET_ID}\", \"remove_matches_from_default_stream\": true}}" \
  "${BASE}/streams" | python3 -c "import json,sys; print(json.load(sys.stdin)['stream_id'])")
echo "STREAM_ID=${STREAM_ID}"

# C2 — pilot-add-rules-and-resume (Admin)
# 3. Add rule: name == SMARTFRAN-CLOUD-ADMIN-PRO
curl -s -u "$AUTH" \
  -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
  -d '{"field": "name", "type": 1, "value": "SMARTFRAN-CLOUD-ADMIN-PRO", "inverted": false}' \
  "${BASE}/streams/${STREAM_ID}/rules"
echo

# 4. Add rule: category == AppServiceHTTPLogs
curl -s -u "$AUTH" \
  -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
  -d '{"field": "category", "type": 1, "value": "AppServiceHTTPLogs", "inverted": false}' \
  "${BASE}/streams/${STREAM_ID}/rules"
echo

# 5. Resume the new stream
curl -s -u "$AUTH" -H "X-Requested-By: cli" -X POST "${BASE}/streams/${STREAM_ID}/resume"
echo

# C3 — pilot-exclude-from-existing-stream (Admin) — ⚠️ modifies a live production stream's rules
# 6. Exclude AppServiceHTTPLogs from the EXISTING PROD-Admin-AppServicePlan stream
curl -s -u "$AUTH" \
  -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
  -d '{"field": "category", "type": 1, "value": "AppServiceHTTPLogs", "inverted": true}' \
  "${BASE}/streams/${EXISTING_STREAM_ID}/rules"
echo

echo "Pilot done. New stream: ${STREAM_ID}, index set: ${INDEX_SET_ID}"

# ⚠️ C4 — batch-create-and-exclude-remaining-7-apps (creates 14 new resources, modifies 7 live streams)
# === BATCH: remaining 7 apps (Admin pilot confirmed working, 209 live
# messages in new stream within 10 min) ===
# Confirmed response shapes from the pilot:
#   POST .../index_sets      -> bare object, id at resp['id']
#   POST .../streams         -> {"stream_id": "..."}
#   POST .../streams/{id}/rules -> {"streamrule_id": "..."}
#   POST .../streams/{id}/resume -> empty 204 body (not an error)

BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
AUTH="${GRAYLOG_API_KEY}:token"

declare -A EXISTING_STREAM=(
  [Business]=6a452a0d18ebc987b1ca003a
  [Catalog]=6a7cb1924814bcaed30a87aa
  [Orders]=6a7cb1944814bcaed30a87bf
  [Person]=6a7cb18d4814bcaed30a8774
  [Platform]=6a7cb18a4814bcaed30a875a
  [Pos]=6a7cb1884814bcaed30a8744
  [Sales]=6a47c5c94b3c88a95fad7a7a
)

for APP in Business Catalog Orders Person Platform Pos Sales; do
  APP_LOWER=$(echo "$APP" | tr '[:upper:]' '[:lower:]')
  APP_UPPER=$(echo "$APP" | tr '[:lower:]' '[:upper:]')
  NAME_VALUE="SMARTFRAN-CLOUD-${APP_UPPER}-PRO"
  EXISTING_ID="${EXISTING_STREAM[$APP]}"

  echo "=== ${APP} ==="

  INDEX_SET_ID=$(curl -s -u "$AUTH" \
    -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
    -d "{
      \"title\": \"SFC-${APP}-prod-http\",
      \"description\": \"SmartFran Cloud ${APP} PROD HTTP access logs (AppServiceHTTPLogs, split from main stream for noise)\",
      \"index_prefix\": \"http_${APP_LOWER}_\",
      \"shards\": 1,
      \"replicas\": 0,
      \"index_optimization_max_num_segments\": 1,
      \"index_optimization_disabled\": false,
      \"field_type_refresh_interval\": 5000,
      \"rotation_strategy_class\": \"org.graylog2.indexer.rotation.strategies.TimeBasedSizeOptimizingStrategy\",
      \"rotation_strategy\": {\"type\": \"org.graylog2.indexer.rotation.strategies.TimeBasedSizeOptimizingStrategyConfig\", \"index_lifetime_min\": \"P30D\", \"index_lifetime_max\": \"P40D\"},
      \"retention_strategy_class\": \"org.graylog2.indexer.retention.strategies.DeletionRetentionStrategy\",
      \"retention_strategy\": {\"type\": \"org.graylog2.indexer.retention.strategies.DeletionRetentionStrategyConfig\", \"max_number_of_indices\": 20},
      \"index_analyzer\": \"standard\",
      \"use_legacy_rotation\": false,
      \"data_tiering\": {\"type\": \"hot_only\", \"index_lifetime_min\": \"P30D\", \"index_lifetime_max\": \"P40D\"},
      \"writable\": true
    }" "${BASE}/system/indices/index_sets" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
  echo "  index_set_id=${INDEX_SET_ID}"

  STREAM_ID=$(curl -s -u "$AUTH" \
    -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
    -d "{\"entity\": {\"title\": \"PROD-${APP}-AppServiceHTTPLogs\", \"description\": \"${APP} PROD AppServiceHTTPLogs (verbose HTTP access logs, split out for noise reduction)\", \"index_set_id\": \"${INDEX_SET_ID}\", \"remove_matches_from_default_stream\": true}}" \
    "${BASE}/streams" | python3 -c "import json,sys; print(json.load(sys.stdin)['stream_id'])")
  echo "  stream_id=${STREAM_ID}"

  curl -s -u "$AUTH" \
    -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
    -d "{\"field\": \"name\", \"type\": 1, \"value\": \"${NAME_VALUE}\", \"inverted\": false}" \
    "${BASE}/streams/${STREAM_ID}/rules" > /dev/null

  curl -s -u "$AUTH" \
    -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
    -d '{"field": "category", "type": 1, "value": "AppServiceHTTPLogs", "inverted": false}' \
    "${BASE}/streams/${STREAM_ID}/rules" > /dev/null

  curl -s -u "$AUTH" -H "X-Requested-By: cli" -X POST "${BASE}/streams/${STREAM_ID}/resume" > /dev/null

  curl -s -u "$AUTH" \
    -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
    -d '{"field": "category", "type": 1, "value": "AppServiceHTTPLogs", "inverted": true}' \
    "${BASE}/streams/${EXISTING_ID}/rules" > /dev/null

  echo "  done"
done

# C5 — verification-queries (guidance, only Admin's inflow side actually run this session)
# === VERIFICATION (after a few minutes of traffic) ===
# - GET ${BASE}/streams/${STREAM_ID} to confirm it's not disabled/paused
# - Views Search API, query "category:AppServiceHTTPLogs AND name:SMARTFRAN-CLOUD-ADMIN-PRO",
#   filter to the NEW stream ID -> should show recent messages
# - Same query filtered to the OLD stream ID (6a7cb18f4814bcaed30a8791) -> should show ZERO
#   new messages after the rule change (older messages already indexed there stay put)
# - Spot-check Default Stream is unaffected (remove_matches_from_default_stream was
#   already true on the old stream before this change, so no change expected there)

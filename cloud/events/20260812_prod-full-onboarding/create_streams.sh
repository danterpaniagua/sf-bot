#!/usr/bin/env bash
# GITIN-1834 — create dedicated index set + stream + exact-match rule for the
# 6 remaining PROD apps, mirroring the validated Sales/Business pattern.
# Flag remove_matches_from_default_stream is left OFF here deliberately —
# verify the rule matches only the intended app against real traffic first,
# then enable it as a separate step. Requires $GRAYLOG_API_KEY in the env.
set -euo pipefail

BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
AUTH="${GRAYLOG_API_KEY}:token"

APPS=(Pos Platform Person Admin Catalog Orders)
PREFIXES=(pos_ platform_ person_ admin_ catalog_ orders_)

for i in "${!APPS[@]}"; do
  app="${APPS[$i]}"
  prefix="${PREFIXES[$i]}"
  name_value="SMARTFRAN-CLOUD-$(echo "$app" | tr '[:lower:]' '[:upper:]')-PRO"

  echo "=== ${app} ==="

  index_set_payload=$(printf '{
    "title": "SFC-%s-prod",
    "description": "SmartFran Cloud %s PROD",
    "index_prefix": "%s",
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
  }' "$app" "$app" "$prefix")

  index_set_response=$(curl -s -u "${AUTH}" \
    -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
    -d "${index_set_payload}" "${BASE}/system/indices/index_sets")
  index_set_id=$(echo "${index_set_response}" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
  echo "index_set_id: ${index_set_id}"

  stream_payload=$(printf '{
    "entity": {
      "title": "PROD-%s-AppServicePlan",
      "description": "%s PROD app service logs",
      "index_set_id": "%s",
      "remove_matches_from_default_stream": false
    }
  }' "$app" "$app" "$index_set_id")

  stream_response=$(curl -s -u "${AUTH}" \
    -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
    -d "${stream_payload}" "${BASE}/streams")
  stream_id=$(echo "${stream_response}" | python3 -c "import json,sys; print(json.load(sys.stdin)['stream_id'])")
  echo "stream_id: ${stream_id}"

  rule_payload=$(printf '{"field": "name", "type": 1, "value": "%s", "inverted": false}' "$name_value")

  rule_status=$(curl -s -o /dev/null -w "%{http_code}" -u "${AUTH}" \
    -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
    -d "${rule_payload}" "${BASE}/streams/${stream_id}/rules")
  echo "rule status: ${rule_status}"

  resume_status=$(curl -s -o /dev/null -w "%{http_code}" -u "${AUTH}" \
    -H "Content-Type: application/json" -H "X-Requested-By: cli" \
    -X POST "${BASE}/streams/${stream_id}/resume")
  echo "resume status: ${resume_status}"

  echo "---"
done

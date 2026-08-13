#!/usr/bin/env bash
# Event: 20260812_graylog_messages_not_arriving
# Run on sf-monitoreo.smartfran.com (Graylog/OpenSearch/MongoDB Docker host)
# Commands are grouped by phase: Investigation / Audit / Remediation
# ⚠️ ACTION commands are clearly marked

# === INVESTIGATION ===

# C1 — Check root filesystem disk usage (ruled out disk pressure on this mount)
df -h

# C2 — Confirm this host runs the Graylog/OpenSearch/MongoDB Docker stack
docker ps

# C3 — Check OpenSearch container restart state
docker inspect opensearch --format '{{.State.OOMKilled}} {{.State.StartedAt}}'

# C4 — Look for crash/restart signatures in OpenSearch logs
docker logs opensearch 2>&1 | grep -E "Cluster is not recovered yet|recovered \[[0-9]+\] indices into cluster_state"
docker logs opensearch --since 2026-08-12T01:00:00 --until 2026-08-12T01:25:00
docker logs opensearch 2>&1 | grep -n -B5 -iE "OutOfMemoryError|fatal|uncaught exception|exception in thread|bootstrap check|SIGTERM|SIGKILL" | tail -100

# === AUDIT ===

# C5 — Count mapping fields on the two indices flagged by the indexer-failures list
curl -s "http://localhost:9200/graylog_299/_mapping" | jq '.graylog_299.mappings.properties | length'
curl -s "http://localhost:9200/sp_platform__50/_mapping" | jq '.sp_platform__50.mappings.properties | length'

# C6 — Full index listing: sizes, doc counts, health per index
curl -s "http://localhost:9200/_cat/indices?v"

# C7 — Overall cluster health
curl -s "http://localhost:9200/_cluster/health?pretty"

# C8 — Allocation explanation for a specific shard (sanity check against persistent corruption)
curl -s "http://localhost:9200/_cluster/allocation/explain?pretty" -H 'Content-Type: application/json' -d '{
  "index": "aws_wafv2__189",
  "shard": 0,
  "primary": true
}'

# C9 — Indexer failures breakdown by error message (via Graylog REST API — substitute real admin credentials)
curl -s -u admin:'YOUR_PASSWORD' "http://localhost:9000/api/system/indexer/failures?limit=250" \
  | jq -r '.failures[].message' | sort | uniq -c | sort -rn

# === REMEDIATION ===

# ⚠️ C12 — Raise the mapping field-count limit on the affected indices (NOT YET APPLIED — pending confirmation)
curl -X PUT "http://localhost:9200/graylog_299,sp_platform__50/_settings" \
  -H 'Content-Type: application/json' \
  -d '{"index.mapping.total_fields.limit": 2000}'

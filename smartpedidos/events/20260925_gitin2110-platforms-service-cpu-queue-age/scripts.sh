#!/usr/bin/env bash
# Event: 20260925_gitin2110-platforms-service-cpu-queue-age (GITIN-2110)
# Read-only investigation, except C11/C12 which are the actual ECS task-definition
# mitigation/rollback deploys (run by the user, not by Claude).

# === CloudWatch / SQS ===

# C1 - ApproximateAgeOfOldestMessage, PRD_BranchMessages.fifo, last 6h (initial check)
aws cloudwatch get-metric-statistics \
  --namespace AWS/SQS --metric-name ApproximateAgeOfOldestMessage \
  --dimensions Name=QueueName,Value=PRD_BranchMessages.fifo \
  --start-time "$(date -u -d '6 hours ago' +%Y-%m-%dT%H:%M:%S)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
  --period 60 --statistics Maximum --region us-east-1 \
  --output json > data/branchmessages_age_oldest_6h.json

# C2 - ApproximateAgeOfOldestMessage, PRD_BranchMessages.fifo, full weekend
#      (:267's in-service window, 2026-09-26T00:30Z - 2026-09-28T11:20Z)
aws cloudwatch get-metric-statistics \
  --namespace AWS/SQS --metric-name ApproximateAgeOfOldestMessage \
  --dimensions Name=QueueName,Value=PRD_BranchMessages.fifo \
  --start-time 2026-09-26T00:30:00 --end-time 2026-09-28T11:20:00 \
  --period 300 --statistics Maximum --region us-east-1 \
  --output json > data/branchmessages_age_oldest_weekend.json

# C3 - platforms-service CPUUtilization, same weekend window
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS --metric-name CPUUtilization \
  --dimensions Name=ClusterName,Value=smartfran-pedidos-production Name=ServiceName,Value=platform-service-production-service \
  --start-time 2026-09-26T00:30:00 --end-time 2026-09-28T11:20:00 \
  --period 300 --statistics Average Maximum --region us-east-1 \
  --output json > data/platforms_cpu_weekend.json

# === ECS task definitions ===

# C4 - taskdef :266 (pre-mitigation baseline) and :267 (reactive CPU bump)
for REV in 266 267; do
  aws ecs describe-task-definition --task-definition platform-service-production-task:${REV} \
    --region us-east-1 \
    --query 'taskDefinition.{registeredAt:registeredAt,cpu:cpu,memory:memory,containers:containerDefinitions[].{image:image,env:environment}}' \
    --output json > data/taskdef_${REV}.json
done

# C5 - confirm :267 fully rolled out on the service
aws ecs describe-services --cluster smartfran-pedidos-production \
  --services platform-service-production-service --region us-east-1 \
  --query 'services[0].{taskDefinition:taskDefinition,desired:desiredCount,running:runningCount,pending:pendingCount,deployments:deployments[*].{status:status,taskDef:taskDefinition,desired:desiredCount,running:runningCount,rolloutState:rolloutState}}' \
  --output json > data/service_current_taskdef.json

# C6 - taskdef :268 (2026-09-28, cpu back to 512, memory cut to 1024)
aws ecs describe-task-definition --task-definition platform-service-production-task:268 \
  --region us-east-1 \
  --query 'taskDefinition.{registeredAt:registeredAt,cpu:cpu,memory:memory,containers:containerDefinitions[].{image:image,env:environment}}' \
  --output json > data/taskdef_268.json

# C7 - confirm :268 rollout status vs :267
aws ecs describe-services --cluster smartfran-pedidos-production \
  --services platform-service-production-service --region us-east-1 \
  --query 'services[0].{taskDefinition:taskDefinition,desired:desiredCount,running:runningCount,pending:pendingCount,deployments:deployments[*].{status:status,taskDef:taskDefinition,desired:desiredCount,running:runningCount,rolloutState:rolloutState}}' \
  --output json > data/service_current_taskdef_268.json

# === Graylog (sf-monitoreo.smartfran.com, older SmartPedidos/SmartLoyalty stack) ===
# Boolean/parenthesized queries hit this stack's "Missing search type result!" bug even on
# short ranges - fell back to plain single-term queries throughout.

# C8 - error-signal terms, both 2026-09-25 incident windows: 0 results, both terms, both windows
for WIN in "2026-09-25T19:00:00.000Z 2026-09-25T19:20:00.000Z cluster1" "2026-09-25T23:45:00.000Z 2026-09-26T00:15:00.000Z cluster2"; do
  set -- $WIN
  for TERM in sqs_consumer batch_processing; do
    curl -s -u "$SML_GRAYLOG_API_KEY:token" \
      --data-urlencode "query=$TERM" --data-urlencode "from=$1" --data-urlencode "to=$2" --data-urlencode 'limit=200' \
      -G "http://sf-monitoreo.smartfran.com:9000/api/search/universal/absolute" -H 'Accept: application/json' \
      >| "data/graylog_${3}_${TERM//_/}.json"
  done
done

# C9 - sanity check: confirms the search mechanism itself returns real data in that window
#      (29,318 total_results) - the 0-result queries above are a real finding, not a search gap
curl -s -u "$SML_GRAYLOG_API_KEY:token" \
  --data-urlencode 'query=platforms-service' \
  --data-urlencode 'from=2026-09-25T19:00:00.000Z' --data-urlencode 'to=2026-09-25T19:20:00.000Z' \
  --data-urlencode 'limit=5' \
  -G "http://sf-monitoreo.smartfran.com:9000/api/search/universal/absolute" -H 'Accept: application/json' \
  >| data/graylog_sanity_check.json

# === MongoDB (PedidosSmartfran / smartfran) ===

# C10 - news volume per hour (UTC buckets), full weekend window - mongo_news_volume_weekend.js
mongosh "<conn>" mongo_news_volume_weekend.js >| data/mongo_news_volume_weekend.txt

# C11 - candidate news docs updated right at/after the Sun 21:05 ART spike - mongo_trace_sunday_2105.js
mongosh "<conn>" mongo_trace_sunday_2105.js >| data/mongo_trace_sunday_2105.txt

# C12 - full traces[] for 15 sample orders from the 00:06:23-00:06:34 UTC burst - mongo_traces_sunday_burst.js
mongosh "<conn>" mongo_traces_sunday_burst.js >| data/mongo_traces_sunday_burst.txt

# C13 - newsTypes lookup (typeId -> cod/name mapping, config-driven not hardcoded)
mongosh "<conn>" --eval "db.newsTypes.find({}, {typeId:1, cod:1, name:1, _id:0}).forEach(printjson)" \
  >| data/newstypes_lookup.txt

# C16 - NumberOfMessagesReceived, PRD_BranchMessages.fifo, last 30 days (hourly, Sum)
aws cloudwatch get-metric-statistics \
  --namespace AWS/SQS --metric-name NumberOfMessagesReceived \
  --dimensions Name=QueueName,Value=PRD_BranchMessages.fifo \
  --start-time 2026-08-29T00:00:00 --end-time 2026-09-28T12:00:00 \
  --period 3600 --statistics Sum --region us-east-1 \
  --output json > data/branchmessages_received_30d.json

# === Mitigation deploys (run by the user; not read-only) ===

# C14 - :267 deployed (2026-09-25 21:33 ART): cpu 512 -> 1024, memory unchanged at 2048, no code change
# C15 - :268 deployed (2026-09-28 08:18 ART): cpu back to 512, memory cut to 1024 (below the 2048
#       pre-existing baseline) - reason not confirmed with the team

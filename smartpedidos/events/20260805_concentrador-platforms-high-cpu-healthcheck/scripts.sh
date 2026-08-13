#!/bin/bash
# Diagnostic commands for 20260805_concentrador-platforms-high-cpu-healthcheck
# Read-only. Region us-east-1, profile smartfran, account 382381053403.

export CLUSTER=smartfran-pedidos-production
export SVC_CONC=concentrador-service-production-service
export SVC_PLAT=platform-service-production-service
export REGION=us-east-1
export PROFILE=smartfran

# C1 — current desired/running/pending count + last deployment events for both services
aws ecs describe-services \
  --cluster $CLUSTER \
  --services $SVC_CONC $SVC_PLAT \
  --region $REGION --profile $PROFILE \
  --query 'services[].{name:serviceName,desired:desiredCount,running:runningCount,pending:pendingCount,events:events[0:8]}'

# C2 — recently stopped tasks + stoppedReason, per service (confirms health-check vs OOM vs other)
for SVC in $SVC_CONC $SVC_PLAT; do
  echo "=== $SVC ==="
  TASK_ARNS=$(aws ecs list-tasks --cluster $CLUSTER --service-name $SVC --desired-status STOPPED \
    --region $REGION --profile $PROFILE --query 'taskArns' --output text)
  if [ -n "$TASK_ARNS" ]; then
    aws ecs describe-tasks --cluster $CLUSTER --tasks $TASK_ARNS \
      --region $REGION --profile $PROFILE \
      --query 'tasks[].{stoppedAt:stoppedAt,stoppedReason:stoppedReason,lastStatus:lastStatus,containers:containers[].{name:name,reason:reason,exitCode:exitCode}}'
  fi
done

# C3 — CPUUtilization (avg + max, 5-min buckets) last 2 hours, both services
for SVC in $SVC_CONC $SVC_PLAT; do
  echo "=== $SVC ==="
  aws cloudwatch get-metric-statistics \
    --namespace AWS/ECS \
    --metric-name CPUUtilization \
    --dimensions Name=ClusterName,Value=$CLUSTER Name=ServiceName,Value=$SVC \
    --start-time "$(date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 300 \
    --statistics Average Maximum \
    --region $REGION --profile $PROFILE \
    --query 'sort_by(Datapoints,&Timestamp)'
done

# C4 — find the target group(s) attached to each service, then pull their health-check config
aws ecs describe-services \
  --cluster $CLUSTER --services $SVC_CONC $SVC_PLAT \
  --region $REGION --profile $PROFILE \
  --query 'services[].{name:serviceName,targetGroupArn:loadBalancers[0].targetGroupArn}'

# Then, for each targetGroupArn returned above:
# aws elbv2 describe-target-groups --target-group-arns <arn> --region $REGION --profile $PROFILE \
#   --query 'TargetGroups[].{Path:HealthCheckPath,Timeout:HealthCheckTimeoutSeconds,Interval:HealthCheckIntervalSeconds,Unhealthy:UnhealthyThresholdCount}'
# aws elbv2 describe-target-health --target-group-arn <arn> --region $REGION --profile $PROFILE

# C5 — URGENT (incident is live): diff the two task-definition revisions on each service.
# Confirms whether the new revision (318 / 253) is the trigger, or a restart response to it.
# registeredAt tells you the ORDER of events vs. the CPU spike timestamps from C3.
echo "=== concentrador :317 vs :318 ==="
aws ecs describe-task-definition --task-definition concentrador-service-production-task:317 \
  --region $REGION --profile $PROFILE \
  --query 'taskDefinition.{registeredAt:registeredAt,cpu:cpu,memory:memory,containers:containerDefinitions[].{image:image,env:environment}}' > /tmp/conc_317.json
aws ecs describe-task-definition --task-definition concentrador-service-production-task:318 \
  --region $REGION --profile $PROFILE \
  --query 'taskDefinition.{registeredAt:registeredAt,cpu:cpu,memory:memory,containers:containerDefinitions[].{image:image,env:environment}}' > /tmp/conc_318.json
diff /tmp/conc_317.json /tmp/conc_318.json

echo "=== platform :252 vs :253 ==="
aws ecs describe-task-definition --task-definition platform-service-production-task:252 \
  --region $REGION --profile $PROFILE \
  --query 'taskDefinition.{registeredAt:registeredAt,cpu:cpu,memory:memory,containers:containerDefinitions[].{image:image,env:environment}}' > /tmp/plat_252.json
aws ecs describe-task-definition --task-definition platform-service-production-task:253 \
  --region $REGION --profile $PROFILE \
  --query 'taskDefinition.{registeredAt:registeredAt,cpu:cpu,memory:memory,containers:containerDefinitions[].{image:image,env:environment}}' > /tmp/plat_253.json
diff /tmp/plat_252.json /tmp/plat_253.json

# C6 — which revision is actually running right now on each service
aws ecs describe-services --cluster $CLUSTER --services $SVC_CONC $SVC_PLAT \
  --region $REGION --profile $PROFILE \
  --query 'services[].{name:serviceName,taskDefinition:taskDefinition,deployments:deployments[].{taskDef:taskDefinition,status:status,desired:desiredCount,running:runningCount,rolloutState:rolloutState}}'

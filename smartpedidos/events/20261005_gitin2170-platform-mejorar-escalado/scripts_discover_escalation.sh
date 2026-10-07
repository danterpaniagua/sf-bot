#!/usr/bin/env bash
# GITIN-2170: locate the Lambda that scales platform-service from ApproximateAgeOfOldestMessage, and the scaling setup around it.
# Usage: bash scripts_discover_escalation.sh <aws-cli-profile>
# Read-only AWS calls (lambda list, events list, cloudwatch describe-alarms, application-autoscaling describe-*). Writes JSON under data/.
# Scans us-east-1 and us-east-2 (ECS/ECR for platform-service is in us-east-2 per GITIN-2162; production queues are in us-east-1 per the env config).
set -eu
E=/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261005_gitin2170-platform-mejorar-escalado/data
P="${1:?usage: $0 <aws-cli-profile>}"
mkdir -p "$E"

for R in us-east-1 us-east-2; do
  A="aws --profile $P --region $R --output json"

  # Lambdas (name, runtime, last modified, description, env var NAMES only — values not stored)
  $A lambda list-functions --query 'Functions[].{Name:FunctionName,Runtime:Runtime,LastModified:LastModified,Description:Description,Role:Role,EnvVarNames:keys(Environment.Variables||`{}`)}' > "$E/lambda_functions_$R.json" 2> "$E/lambda_functions_${R}_stderr.txt" || true

  # EventBridge rules and their targets (schedule/trigger of any Lambda)
  $A events list-rules > "$E/events_rules_$R.json" 2> "$E/events_rules_${R}_stderr.txt" || true
  : > "$E/events_targets_$R.jsonl"
  for RULE in $(jq -r '.Rules[]?.Name' "$E/events_rules_$R.json" 2>/dev/null); do
    $A events list-targets-by-rule --rule "$RULE" 2>/dev/null | jq -c --arg r "$RULE" '{Rule:$r, Targets:[.Targets[]|{Id,Arn}]}' >> "$E/events_targets_$R.jsonl" || true
  done

  # CloudWatch alarms (metric + composite) incl. their actions
  $A cloudwatch describe-alarms --alarm-types MetricAlarm CompositeAlarm > "$E/cw_alarms_$R.json" 2> "$E/cw_alarms_${R}_stderr.txt" || true

  # ECS Application Auto Scaling: targets, policies, scheduled actions
  $A application-autoscaling describe-scalable-targets --service-namespace ecs > "$E/appas_targets_$R.json" 2> "$E/appas_targets_${R}_stderr.txt" || true
  $A application-autoscaling describe-scaling-policies --service-namespace ecs > "$E/appas_policies_$R.json" 2> "$E/appas_policies_${R}_stderr.txt" || true
  $A application-autoscaling describe-scheduled-actions --service-namespace ecs > "$E/appas_scheduled_$R.json" 2> "$E/appas_scheduled_${R}_stderr.txt" || true
done

# Summary of likely candidates (name/ARN matches; not proof)
{
  for R in us-east-1 us-east-2; do
    echo "== $R lambdas matching scal|escal|queue|age|sqs|ecs|autoscal"
    jq -r '.[]?|select(.Name|test("scal|escal|queue|age|sqs|ecs|autoscal";"i"))|[.Name,.Runtime,.LastModified]|@tsv' "$E/lambda_functions_$R.json" 2>/dev/null
    echo "== $R EventBridge rules targeting a Lambda"
    jq -r 'select(any(.Targets[]?;.Arn|test(":function:")))|[.Rule,(.Targets|map(.Arn)|join(","))]|@tsv' "$E/events_targets_$R.jsonl" 2>/dev/null
    echo "== $R alarms on ApproximateAgeOfOldestMessage or with Lambda/SNS actions"
    jq -r '(.MetricAlarms[]?|select(.MetricName=="ApproximateAgeOfOldestMessage" or ((.AlarmActions|join(","))|test("lambda|sns";"i")))|[.AlarmName,(.MetricName//"-"),(.Threshold|tostring),(.AlarmActions|join(","))]|@tsv)' "$E/cw_alarms_$R.json" 2>/dev/null
    echo "== $R ECS scalable targets (resource, min, max)"
    jq -r '.ScalableTargets[]?|[.ResourceId,(.MinCapacity|tostring),(.MaxCapacity|tostring)]|@tsv' "$E/appas_targets_$R.json" 2>/dev/null
    echo "== $R ECS scaling policies (resource, policy, type)"
    jq -r '.ScalingPolicies[]?|[.ResourceId,.PolicyName,.PolicyType]|@tsv' "$E/appas_policies_$R.json" 2>/dev/null
    echo "== $R ECS scheduled actions"
    jq -r '.ScheduledActions[]?|[.ResourceId,.ScheduledActionName,.Schedule]|@tsv' "$E/appas_scheduled_$R.json" 2>/dev/null
  done
} > "$E/discovery_summary.txt"
echo "done: $E/discovery_summary.txt"

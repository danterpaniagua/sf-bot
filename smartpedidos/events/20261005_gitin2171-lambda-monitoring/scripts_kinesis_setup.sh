#!/usr/bin/env bash
# GITIN-2171: generic Kinesis -> Graylog path for the logs of ALL SmartPedidos Lambdas, replicating the pattern already used for
# platform-service / concentrador-service / WAF logs (see data/subfilter_full_*, data/role_*, data/kinesis_summary_*):
#   CloudWatch Logs subscription filter(s) -> ONE Kinesis stream (provisioned, 1 shard, 24 h) -> ONE Graylog AWS input
#   (KINESIS_CLOUDWATCH_RAW, created separately in Graylog) -> stream SP_Lambdas.
# Generic names (user, 2026-10-05): stream sp-lambda-logs, role graylog-cloudwatch-role-sp-lambda-logs, filter name sp-lambda-logs.
# No Lambda function is modified: only log-group subscription filters are added.
# Usage: bash scripts_kinesis_setup.sh <aws-cli-profile> <phase> [log-group]
#   create                  : ⚠️ STATE-CHANGING (production AWS account): creates the stream and the IAM role + inline policy (once).
#   subscribe <log-group>   : ⚠️ STATE-CHANGING: adds the subscription filter on that log group (a log group allows at most 2 filters).
#   unsubscribe <log-group> : ⚠️ STATE-CHANGING: removes that filter.
#   verify [log-group]      : read-only: stream, role, policy, filters on the log group (default: the escalation Lambda), IncomingRecords.
#   rollback                : ⚠️ STATE-CHANGING: deletes role policy, role and stream (run `unsubscribe` for every log group first).
# The Graylog side (AWS input for this stream, routing to SP_Lambdas) is a separate step in the Graylog UI/API.
set -eu
E=/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261005_gitin2171-lambda-monitoring/data
P="${1:?usage: $0 <aws-cli-profile> <create|subscribe|unsubscribe|verify|rollback> [log-group]}"
PHASE="${2:?phase required}"
LG="${3:-/aws/lambda/IntegrationLambdaEcsTaskProd}"
R=us-east-1
ACCT=382381053403
STREAM=sp-lambda-logs
ROLE=graylog-cloudwatch-role-sp-lambda-logs
POLICY=graylog-cloudwatch-role-policy-sp-lambda-logs
FILTER=sp-lambda-logs
STREAM_ARN="arn:aws:kinesis:$R:$ACCT:stream/$STREAM"
ROLE_ARN="arn:aws:iam::$ACCT:role/$ROLE"
A="aws --profile $P --region $R --output json"
TS=$(date +%Y%m%d_%H%M%S)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$E"

case "$PHASE" in
  create)
    # ⚠️ 1) Kinesis stream, same sizing as the existing three (provisioned, 1 shard; 24 h retention is the default)
    $A kinesis create-stream --stream-name "$STREAM" --shard-count 1 --stream-mode-details StreamMode=PROVISIONED
    aws --profile "$P" --region "$R" kinesis wait stream-exists --stream-name "$STREAM"
    # ⚠️ 2) Role assumed by CloudWatch Logs (same trust as the existing graylog-cloudwatch-role-*), allowed to PutRecord on this stream only
    cat > "$TMP/trust.json" <<'JSON'
{"Version":"2008-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"logs.us-east-1.amazonaws.com"},"Action":"sts:AssumeRole"}]}
JSON
    cat > "$TMP/policy.json" <<JSON
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"kinesis:PutRecord","Resource":"$STREAM_ARN"}]}
JSON
    $A iam create-role --role-name "$ROLE" --assume-role-policy-document "file://$TMP/trust.json" --query 'Role.{RoleName:RoleName,Arn:Arn}'
    $A iam put-role-policy --role-name "$ROLE" --policy-name "$POLICY" --policy-document "file://$TMP/policy.json"
    echo "created: stream $STREAM and role $ROLE (no log group subscribed yet)"
    ;;
  subscribe)
    sleep 5   # a just-created role may need a few seconds to propagate
    # ⚠️ Subscription filter (same pattern/distribution as the existing filters)
    $A logs put-subscription-filter --log-group-name "$LG" --filter-name "$FILTER" --filter-pattern "" \
        --destination-arn "$STREAM_ARN" --role-arn "$ROLE_ARN" --distribution ByLogStream
    echo "subscribed: $LG -> $STREAM"
    ;;
  unsubscribe)
    $A logs delete-subscription-filter --log-group-name "$LG" --filter-name "$FILTER"
    echo "unsubscribed: $LG"
    ;;
  verify)
    { echo "== stream";  $A kinesis describe-stream-summary --stream-name "$STREAM" --query 'StreamDescriptionSummary.{Name:StreamName,Status:StreamStatus,Mode:StreamModeDetails.StreamMode,OpenShards:OpenShardCount,RetentionHours:RetentionPeriodHours,Encryption:EncryptionType}'
      echo "== role";    $A iam get-role --role-name "$ROLE" --query 'Role.{Name:RoleName,Trust:AssumeRolePolicyDocument}'
      echo "== policy";  $A iam get-role-policy --role-name "$ROLE" --policy-name "$POLICY" --query 'PolicyDocument'
      echo "== filters on $LG"; $A logs describe-subscription-filters --log-group-name "$LG" --query 'subscriptionFilters[].{filterName:filterName,destinationArn:destinationArn,roleArn:roleArn,distribution:distribution,filterPattern:filterPattern}'
      echo "== IncomingRecords, last 6 h (sum per hour)"
      $A cloudwatch get-metric-statistics --namespace AWS/Kinesis --metric-name IncomingRecords --dimensions Name=StreamName,Value="$STREAM" \
        --start-time "$(date -u -d '6 hours ago' +%Y-%m-%dT%H:%M:%SZ)" --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --period 3600 --statistics Sum --query 'sort_by(Datapoints,&Timestamp)[].[Timestamp,Sum]'
    } > "$E/kinesis_setup_verify_$TS.txt" 2>&1
    cat "$E/kinesis_setup_verify_$TS.txt"
    ;;
  rollback)
    # ⚠️ removes what `create` made (does not touch any Lambda or the existing three streams); unsubscribe every log group first
    $A iam delete-role-policy --role-name "$ROLE" --policy-name "$POLICY" || true
    $A iam delete-role --role-name "$ROLE" || true
    $A kinesis delete-stream --stream-name "$STREAM" || true
    echo "rolled back: role policy, role, stream (check with the verify phase)"
    ;;
  *) echo "unknown phase: $PHASE"; exit 2 ;;
esac

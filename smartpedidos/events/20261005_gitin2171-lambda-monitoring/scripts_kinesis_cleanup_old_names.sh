#!/usr/bin/env bash
# GITIN-2171: the first version of scripts_kinesis_setup.sh (`create` phase) was run by the user with the per-Lambda names below
# before the names were changed to the generic sp-lambda-logs set. This script inspects and, if wanted, removes ONLY those objects.
# Old names: stream IntegrationLambdaEcsTaskProd, role graylog-cloudwatch-role-IntegrationLambdaEcsTaskProd (+ inline policy
# graylog-cloudwatch-role-policy-IntegrationLambdaEcsTaskProd), subscription filter `filter-name` on /aws/lambda/IntegrationLambdaEcsTaskProd.
# Usage: bash scripts_kinesis_cleanup_old_names.sh <aws-cli-profile> <check|cleanup>
#   check   : read-only. Shows which of those objects exist and where the log group's filter points. Writes data/.
#   cleanup : ⚠️ STATE-CHANGING (production AWS account). Deletes the filter (only if it points at the old stream), the role policy,
#             the role and the old stream. Does not touch the Lambda, the generic sp-lambda-logs objects or the existing three streams.
set -eu
E=/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261005_gitin2171-lambda-monitoring/data
P="${1:?usage: $0 <aws-cli-profile> <check|cleanup>}"
PHASE="${2:?phase required}"
R=us-east-1
ACCT=382381053403
LG=/aws/lambda/IntegrationLambdaEcsTaskProd
STREAM=IntegrationLambdaEcsTaskProd
ROLE=graylog-cloudwatch-role-IntegrationLambdaEcsTaskProd
POLICY=graylog-cloudwatch-role-policy-IntegrationLambdaEcsTaskProd
OLD_ARN="arn:aws:kinesis:$R:$ACCT:stream/$STREAM"
A="aws --profile $P --region $R --output json"
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "$E"

case "$PHASE" in
  check)
    { echo "== old stream";  $A kinesis describe-stream-summary --stream-name "$STREAM" --query 'StreamDescriptionSummary.{Name:StreamName,Status:StreamStatus,Mode:StreamModeDetails.StreamMode,OpenShards:OpenShardCount,RetentionHours:RetentionPeriodHours}' 2>&1 || true
      echo "== old role";    $A iam get-role --role-name "$ROLE" --query 'Role.{Name:RoleName,Created:CreateDate,Trust:AssumeRolePolicyDocument}' 2>&1 || true
      echo "== old role policy"; $A iam get-role-policy --role-name "$ROLE" --policy-name "$POLICY" --query 'PolicyDocument' 2>&1 || true
      echo "== subscription filters on $LG"; $A logs describe-subscription-filters --log-group-name "$LG" --query 'subscriptionFilters[].{filterName:filterName,destinationArn:destinationArn,roleArn:roleArn,distribution:distribution,filterPattern:filterPattern}' 2>&1 || true
      echo "== generic sp-lambda-logs objects (should not exist yet)"
      $A kinesis describe-stream-summary --stream-name sp-lambda-logs --query 'StreamDescriptionSummary.StreamName' 2>&1 | head -2 || true
      $A iam get-role --role-name graylog-cloudwatch-role-sp-lambda-logs --query 'Role.RoleName' 2>&1 | head -2 || true
    } > "$E/kinesis_old_names_check_$TS.txt" 2>&1
    cat "$E/kinesis_old_names_check_$TS.txt"
    ;;
  cleanup)
    # ⚠️ delete the filter only if it really points at the old stream
    DEST=$($A logs describe-subscription-filters --log-group-name "$LG" --query 'subscriptionFilters[?filterName==`filter-name`].destinationArn | [0]' --output text 2>/dev/null || true)
    if [ "$DEST" = "$OLD_ARN" ]; then
      $A logs delete-subscription-filter --log-group-name "$LG" --filter-name filter-name
      echo "deleted subscription filter filter-name on $LG"
    else
      echo "no filter 'filter-name' pointing at $STREAM on $LG (found: ${DEST:-none}) — not touching filters"
    fi
    $A iam delete-role-policy --role-name "$ROLE" --policy-name "$POLICY" || true
    $A iam delete-role --role-name "$ROLE" || true
    $A kinesis delete-stream --stream-name "$STREAM" || true
    echo "cleanup done: re-run check to confirm"
    ;;
  *) echo "unknown phase: $PHASE"; exit 2 ;;
esac

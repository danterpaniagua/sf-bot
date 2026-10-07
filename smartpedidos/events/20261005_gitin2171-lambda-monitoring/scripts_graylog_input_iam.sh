#!/usr/bin/env bash
# GITIN-2171: a dedicated least-privilege IAM user for the NEW Graylog AWS input `sp-lambda-logs` (the existing three inputs use the
# static key of a personal administrator user — see investigation.md; this script does not touch them).
# Permissions are limited to the new Kinesis stream and the DynamoDB lease table the input creates, plus CloudWatch PutMetricData
# (which does not support resource-level restrictions). Action list = what the Kinesis consumer used by the Graylog AWS plugin needs
# (stream read + lease table + metrics); it is NOT verified against the plugin: if the input fails to start, its error names the
# missing action and the policy should be extended by exactly that action.
# Usage: bash scripts_graylog_input_iam.sh <aws-cli-profile> <create|verify|rollback>
#   create   : ⚠️ STATE-CHANGING (production AWS account): creates the user, its inline policy and ONE access key.
#              The access key's SECRET is printed ONCE to the terminal: do NOT redirect it into a file, do NOT paste it in a chat or
#              ticket; type/paste it only into the Graylog input form. If lost, delete the key and create a new one.
#   verify   : read-only (writes data/, key IDs masked).
#   rollback : ⚠️ STATE-CHANGING: deletes the user's access keys, inline policy and the user.
set -eu
E=/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261005_gitin2171-lambda-monitoring/data
P="${1:?usage: $0 <aws-cli-profile> <create|verify|rollback>}"
PHASE="${2:?phase required}"
R=us-east-1
ACCT=382381053403
U=graylog-aws-input-sp-lambda-logs
POLICY=graylog-aws-input-sp-lambda-logs-policy
STREAM_ARN="arn:aws:kinesis:$R:$ACCT:stream/sp-lambda-logs"
TABLE_ARN="arn:aws:dynamodb:$R:$ACCT:table/graylog-aws-plugin-sp-lambda-logs"
A="aws --profile $P --region $R --output json"
TS=$(date +%Y%m%d_%H%M%S)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$E"
mask() { sed -E 's/(AKIA|ASIA)[A-Z0-9]{12}([A-Z0-9]{4})/\1************\2/g'; }

case "$PHASE" in
  create)
    cat > "$TMP/policy.json" <<JSON
{"Version":"2012-10-17","Statement":[
 {"Sid":"ReadTheStream","Effect":"Allow","Action":["kinesis:GetRecords","kinesis:GetShardIterator","kinesis:DescribeStream","kinesis:DescribeStreamSummary","kinesis:ListShards"],"Resource":"$STREAM_ARN"},
 {"Sid":"LeaseTable","Effect":"Allow","Action":["dynamodb:CreateTable","dynamodb:DescribeTable","dynamodb:GetItem","dynamodb:PutItem","dynamodb:UpdateItem","dynamodb:DeleteItem","dynamodb:Scan"],"Resource":"$TABLE_ARN"},
 {"Sid":"ConsumerMetrics","Effect":"Allow","Action":"cloudwatch:PutMetricData","Resource":"*"}
]}
JSON
    # ⚠️ 1) user  2) inline policy
    $A iam create-user --user-name "$U" --query 'User.{UserName:UserName,Arn:Arn}'
    $A iam put-user-policy --user-name "$U" --policy-name "$POLICY" --policy-document "file://$TMP/policy.json"
    # ⚠️ 3) access key — SECRET printed once, to the terminal only (never redirected by this script)
    echo "---- access key for the Graylog input form (shown once; do not copy it anywhere else) ----"
    aws --profile "$P" --region "$R" iam create-access-key --user-name "$U" --query 'AccessKey.{AccessKeyId:AccessKeyId,SecretAccessKey:SecretAccessKey}' --output table
    ;;
  verify)
    { echo "== user";   $A iam get-user --user-name "$U" --query 'User.{UserName:UserName,Arn:Arn,Created:CreateDate}'
      echo "== keys";   $A iam list-access-keys --user-name "$U" --query 'AccessKeyMetadata[].{Id:AccessKeyId,Status:Status,Created:CreateDate}' | mask
      echo "== policy"; $A iam get-user-policy --user-name "$U" --policy-name "$POLICY" --query 'PolicyDocument'
      echo "== attached/groups"; $A iam list-attached-user-policies --user-name "$U" --query 'AttachedPolicies[].PolicyArn'; $A iam list-groups-for-user --user-name "$U" --query 'Groups[].GroupName'
    } > "$E/graylog_input_iam_verify_$TS.txt" 2>&1
    cat "$E/graylog_input_iam_verify_$TS.txt"
    ;;
  rollback)
    for K in $($A iam list-access-keys --user-name "$U" --query 'AccessKeyMetadata[].AccessKeyId' --output text); do
      $A iam delete-access-key --user-name "$U" --access-key-id "$K"
    done
    $A iam delete-user-policy --user-name "$U" --policy-name "$POLICY" || true
    $A iam delete-user --user-name "$U" || true
    echo "rolled back: access keys, inline policy, user (check with verify)"
    ;;
  *) echo "unknown phase: $PHASE"; exit 2 ;;
esac

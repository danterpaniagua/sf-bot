#!/usr/bin/env bash
# GITIN-2171: read the EXISTING Kinesis -> Graylog pattern (used for platform-service / concentrador-service / WAF logs) in enough
# detail to replicate it for /aws/lambda/IntegrationLambdaEcsTaskProd without modifying the Lambda.
# Usage: SML_GRAYLOG_API_KEY="$SML_GRAYLOG_API_KEY" bash scripts_kinesis_pattern_recon.sh <aws-cli-profile>
# Read-only: logs describe-subscription-filters, iam get-role/list/get policy, kinesis describe-stream-summary, dynamodb list-tables,
# and Graylog GET /api/system/inputs (attributes copied through an allowlist that EXCLUDES any key/secret/password/token attribute).
set -eu
E=/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261005_gitin2171-lambda-monitoring/data
P="${1:?usage: $0 <aws-cli-profile>}"
: "${SML_GRAYLOG_API_KEY:?SML_GRAYLOG_API_KEY not set (pass it as shown in the usage line)}"
R=us-east-1
A="aws --profile $P --region $R --output json"
mkdir -p "$E"

# 1) Subscription filters in full (includes roleArn and distribution), the three log groups that already ship to Graylog
for LG in /ecs/platform-service-production-task /ecs/concentrador-service-production-task aws-waf-logs-sp-wafv2; do
  N=$(echo "$LG" | tr '/' '_')
  $A logs describe-subscription-filters --log-group-name "$LG" > "$E/subfilter_full${N}.json" 2>&1 || true
done
cat "$E"/subfilter_full_* "$E"/subfilter_full*.json 2>/dev/null | jq -r '.subscriptionFilters[]?.roleArn' | sort -u > "$E/subfilter_role_arns.txt" || true

# 2) What those roles trust and may do
for ARN in $(cat "$E/subfilter_role_arns.txt" 2>/dev/null); do
  RN="${ARN##*/}"
  $A iam get-role --role-name "$RN" --query 'Role.{Name:RoleName,Trust:AssumeRolePolicyDocument,Created:CreateDate}' > "$E/role_${RN}.json" 2>&1 || true
  $A iam list-attached-role-policies --role-name "$RN" > "$E/role_${RN}_attached.json" 2>&1 || true
  for PN in $($A iam list-role-policies --role-name "$RN" --query 'PolicyNames[]' --output text 2>/dev/null); do
    $A iam get-role-policy --role-name "$RN" --policy-name "$PN" > "$E/role_${RN}_inline_${PN}.json" 2>&1 || true
  done
  for PA in $(jq -r '.AttachedPolicies[]?.PolicyArn' "$E/role_${RN}_attached.json" 2>/dev/null); do
    V=$($A iam get-policy --policy-arn "$PA" --query 'Policy.DefaultVersionId' --output text 2>/dev/null || true)
    [ -n "$V" ] && $A iam get-policy-version --policy-arn "$PA" --version-id "$V" > "$E/role_${RN}_policy_$(basename "$PA").json" 2>&1 || true
  done
done

# 3) The three Kinesis streams: shards, retention, mode (cost/size reference)
for S in platform-service-production-task concentrador-service-production-task aws-waf-logs-sp-wafv2; do
  $A kinesis describe-stream-summary --stream-name "$S" --query 'StreamDescriptionSummary.{Name:StreamName,Status:StreamStatus,Mode:StreamModeDetails.StreamMode,OpenShards:OpenShardCount,RetentionHours:RetentionPeriodHours,Encryption:EncryptionType}' > "$E/kinesis_summary_${S}.json" 2>&1 || true
done

# 4) DynamoDB tables (the Graylog AWS Kinesis input uses a KCL lease table per application)
$A dynamodb list-tables > "$E/dynamodb_tables_$R.json" 2>&1 || true

# 5) Graylog AWS inputs: attributes through an allowlist that excludes credentials
curl -sS -m 30 -u "$SML_GRAYLOG_API_KEY:token" -H 'Accept: application/json' http://sf-monitoreo.smartfran.com:9000/api/system/inputs \
  | jq '[.inputs[]|select(.type|test("AWS"))|{title,type,global,created_at,attributes:(.attributes|with_entries(select(.key|test("key|secret|password|token";"i")|not)))}]' > "$E/graylog_aws_inputs_attributes.json" 2>&1 || true

echo "done: subfilter_full_*, role_*, kinesis_summary_*, dynamodb_tables_$R.json, graylog_aws_inputs_attributes.json in $E"

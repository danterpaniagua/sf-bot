#!/usr/bin/env bash
# GITIN-2170: read the production escalation chain found by scripts_discover_escalation.sh:
#   alarm sendMailOldestMessage (PRD_BranchMessages.fifo, ApproximateAgeOfOldestMessage > 25, us-east-1)
#   -> SNS Pedidos_Production -> (suspected) Lambda IntegrationLambdaEcsTaskProd (us-east-1, python3.12) -> ECS service.
# Usage: bash scripts_read_escalation_lambda.sh <aws-cli-profile>
# Read-only AWS calls (lambda get-function/get-policy, sns get/list, iam get/list, logs filter-log-events, cloudwatch get-metric-statistics).
# Writes under data/. Masking: AWS key IDs, secret-looking assignments in the Lambda code, and e-mail local parts in SNS endpoints.
# The Lambda's code zip is downloaded to a temp dir (signed URL never stored) and only the masked text of its files is kept in data/.
set -eu
E=/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261005_gitin2170-platform-mejorar-escalado/data
P="${1:?usage: $0 <aws-cli-profile>}"
R=us-east-1
FN=IntegrationLambdaEcsTaskProd
TOPIC=arn:aws:sns:us-east-1:382381053403:Pedidos_Production
A="aws --profile $P --region $R --output json"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$E"
mask() { sed -E -e 's/(AKIA|ASIA)[A-Z0-9]{12}([A-Z0-9]{4})/\1************\2/g' \
                -e "s/((secret|password|passwd|token|api_?key)[A-Za-z_]*[[:space:]]*[=:][[:space:]]*)['\"][^'\"]{6,}['\"]/\1'<redacted>'/Ig" \
                -e 's/[A-Za-z0-9._%+-]+@([A-Za-z0-9.-]+\.[A-Za-z]{2,})/***@\1/g' \
                -e 's/\+[0-9]{8,}([0-9]{4})/+*********\1/g'; }

# 1) Lambda configuration (no code URL stored) and invoke permissions
$A lambda get-function-configuration --function-name "$FN" | mask > "$E/lambda_${FN}_config.json" || true
$A lambda get-policy --function-name "$FN" --query Policy --output text 2>&1 | mask > "$E/lambda_${FN}_policy.json" || true
$A lambda list-event-source-mappings --function-name "$FN" | mask > "$E/lambda_${FN}_event_source_mappings.json" || true

# 2) Lambda code (masked text of every file in the zip)
URL=$($A lambda get-function --function-name "$FN" --query 'Code.Location' --output text 2>/dev/null || true)
if [ -n "$URL" ] && [ "$URL" != None ]; then
  curl -fsS "$URL" -o "$TMP/code.zip" 2> "$E/lambda_${FN}_code_download_stderr.txt" || true
  if [ -s "$TMP/code.zip" ]; then
    unzip -qo "$TMP/code.zip" -d "$TMP/code" || true
    { for f in $(cd "$TMP/code" && find . -type f \( -name '*.py' -o -name '*.json' -o -name '*.txt' \) | sort); do echo "######## $f"; mask < "$TMP/code/$f"; done; } > "$E/lambda_${FN}_code_masked.txt"
  fi
fi

# 3) SNS topic and subscriptions (endpoints masked)
$A sns get-topic-attributes --topic-arn "$TOPIC" --query 'Attributes.{TopicArn:TopicArn,SubscriptionsConfirmed:SubscriptionsConfirmed,SubscriptionsPending:SubscriptionsPending}' > "$E/sns_Pedidos_Production_attrs.json" || true
$A sns list-subscriptions-by-topic --topic-arn "$TOPIC" --query 'Subscriptions[].{Protocol:Protocol,Endpoint:Endpoint,SubscriptionArn:SubscriptionArn}' | mask > "$E/sns_Pedidos_Production_subscriptions.json" || true

# 4) What the Lambda's role can do
ROLE=$(jq -r '.Role // empty' "$E/lambda_${FN}_config.json" 2>/dev/null | sed 's#.*/##')
if [ -n "$ROLE" ]; then
  $A iam list-attached-role-policies --role-name "$ROLE" > "$E/lambda_role_attached.json" || true
  $A iam list-role-policies --role-name "$ROLE" > "$E/lambda_role_inline_names.json" || true
  for PN in $(jq -r '.PolicyNames[]?' "$E/lambda_role_inline_names.json" 2>/dev/null); do
    $A iam get-role-policy --role-name "$ROLE" --policy-name "$PN" > "$E/lambda_role_inline_${PN}.json" || true
  done
  for PA in $(jq -r '.AttachedPolicies[]?.PolicyArn' "$E/lambda_role_attached.json" 2>/dev/null); do
    V=$($A iam get-policy --policy-arn "$PA" --query 'Policy.DefaultVersionId' --output text 2>/dev/null || true)
    [ -n "$V" ] && $A iam get-policy-version --policy-arn "$PA" --version-id "$V" > "$E/lambda_role_policy_$(basename "$PA").json" || true
  done
fi

# 5) Did it run? Invocations/Errors per hour over the last 8 days + log lines since Fri 2026-10-02 00:00 ART
for M in Invocations Errors; do
  $A cloudwatch get-metric-statistics --namespace AWS/Lambda --metric-name "$M" --dimensions Name=FunctionName,Value="$FN" \
    --start-time "$(date -u -d '8 days ago' +%Y-%m-%dT%H:%M:%SZ)" --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --period 3600 --statistics Sum \
    --query 'sort_by(Datapoints,&Timestamp)[?Sum>`0`].[Timestamp,Sum]' > "$E/lambda_${FN}_${M}_hourly_8d.json" || true
done
START_MS=$(( $(date -d '2026-10-02 00:00 -0300' +%s) * 1000 ))
$A logs filter-log-events --log-group-name "/aws/lambda/$FN" --start-time "$START_MS" --limit 500 --query 'events[].[timestamp,message]' | mask > "$E/lambda_${FN}_logs_since_oct2.json" 2> "$E/lambda_${FN}_logs_stderr.txt" || true

# 6) State history of the age alarm over the weekend (when it went ALARM/OK)
$A cloudwatch describe-alarm-history --alarm-name sendMailOldestMessage --history-item-type StateUpdate \
  --start-date "$(date -u -d '2026-10-02 03:00' +%Y-%m-%dT%H:%M:%SZ)" --query 'AlarmHistoryItems[].[Timestamp,HistorySummary]' > "$E/alarm_sendMailOldestMessage_history_oct2_on.json" || true

echo "done: files under $E (lambda_${FN}_*, sns_Pedidos_Production_*, lambda_role_*, alarm_sendMailOldestMessage_history_oct2_on.json)"

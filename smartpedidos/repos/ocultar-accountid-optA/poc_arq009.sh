#!/usr/bin/env bash
# ARQ-009 PoC — REST API + native SQS integration, parametrized /{branchId} resource
# Ref: smartpedidos/events/20260720_ocultar-account-id-sqs-urls
# Account 382381053403, region us-west-2 (isolated from prod us-east-1 / staging us-east-2,
# and from the real _PER_ queues at branchId 1000-1004 also in us-west-2 — do not touch those).
set -euo pipefail

# --- Config ---
REGION="us-west-2"
ACCOUNT_ID="382381053403"
QUEUE_A="poc-arq009-branchA.fifo"
QUEUE_B="poc-arq009-branchB.fifo"
API_NAME="poc-arq009-hide-account-id"
ROLE_NAME="poc-arq009-apigw-sqs-role"
STAGE_NAME="poc"
WORKDIR=$(mktemp -d)

# --- 1. Two disposable FIFO test queues ---
aws sqs create-queue --queue-name "$QUEUE_A" \
  --attributes FifoQueue=true,ContentBasedDeduplication=true \
  --region "$REGION"

aws sqs create-queue --queue-name "$QUEUE_B" \
  --attributes FifoQueue=true,ContentBasedDeduplication=true \
  --region "$REGION"

QUEUE_A_URL="https://sqs.$REGION.amazonaws.com/$ACCOUNT_ID/$QUEUE_A"
QUEUE_B_URL="https://sqs.$REGION.amazonaws.com/$ACCOUNT_ID/$QUEUE_B"
QUEUE_A_ARN="arn:aws:sqs:$REGION:$ACCOUNT_ID:$QUEUE_A"
QUEUE_B_ARN="arn:aws:sqs:$REGION:$ACCOUNT_ID:$QUEUE_B"

# --- 2. Scoped IAM role for API Gateway: SendMessage only, only these 2 queues ---
cat > "$WORKDIR/trust-policy.json" <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "apigateway.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
EOF

aws iam create-role --role-name "$ROLE_NAME" \
  --assume-role-policy-document "file://$WORKDIR/trust-policy.json"

cat > "$WORKDIR/sqs-policy.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "sqs:SendMessage",
    "Resource": ["$QUEUE_A_ARN", "$QUEUE_B_ARN"]
  }]
}
EOF

aws iam put-role-policy --role-name "$ROLE_NAME" \
  --policy-name "poc-arq009-sqs-sendmessage" \
  --policy-document "file://$WORKDIR/sqs-policy.json"

ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)
sleep 10   # IAM role propagation before API Gateway can assume it

# --- 3. REST API + parametrized resource /{branchId} ---
API_ID=$(aws apigateway create-rest-api --name "$API_NAME" --region "$REGION" \
  --query 'id' --output text)

ROOT_ID=$(aws apigateway get-resources --rest-api-id "$API_ID" --region "$REGION" \
  --query 'items[?path==`/`].id' --output text)

RESOURCE_ID=$(aws apigateway create-resource --rest-api-id "$API_ID" \
  --parent-id "$ROOT_ID" --path-part "{branchId}" --region "$REGION" \
  --query 'id' --output text)

aws apigateway put-method --rest-api-id "$API_ID" --resource-id "$RESOURCE_ID" \
  --http-method POST --authorization-type NONE \
  --request-parameters "method.request.path.branchId=true" \
  --region "$REGION"

# --- 4. Native AWS integration: QueueUrl built server-side from {branchId} via VTL ---
cat > "$WORKDIR/request-template.vtl" <<EOF
Action=SendMessage&Version=2012-11-05&QueueUrl=\$util.urlEncode("https://sqs.$REGION.amazonaws.com/$ACCOUNT_ID/poc-arq009-\$input.params('branchId').fifo")&MessageBody=\$util.urlEncode(\$input.body)&MessageGroupId=\$util.urlEncode(\$input.params('branchId'))
EOF

python3 - "$WORKDIR/request-template.vtl" "$WORKDIR/request-templates.json" <<'PYEOF'
import json, sys
tpl = open(sys.argv[1]).read().rstrip("\n")
json.dump({"application/json": tpl}, open(sys.argv[2], "w"))
PYEOF

cat > "$WORKDIR/request-parameters.json" <<'EOF'
{
  "integration.request.header.Content-Type": "'application/x-www-form-urlencoded'"
}
EOF

aws apigateway put-integration --rest-api-id "$API_ID" --resource-id "$RESOURCE_ID" \
  --http-method POST --type AWS --integration-http-method POST \
  --uri "arn:aws:apigateway:$REGION:sqs:action/SendMessage" \
  --credentials "$ROLE_ARN" \
  --request-parameters "file://$WORKDIR/request-parameters.json" \
  --request-templates "file://$WORKDIR/request-templates.json" \
  --region "$REGION"

aws apigateway put-method-response --rest-api-id "$API_ID" --resource-id "$RESOURCE_ID" \
  --http-method POST --status-code 200 --region "$REGION"

aws apigateway put-integration-response --rest-api-id "$API_ID" --resource-id "$RESOURCE_ID" \
  --http-method POST --status-code 200 --region "$REGION"

# --- 5. Deploy ---
aws apigateway create-deployment --rest-api-id "$API_ID" --stage-name "$STAGE_NAME" \
  --region "$REGION"

INVOKE_URL="https://$API_ID.execute-api.$REGION.amazonaws.com/$STAGE_NAME"
echo "API_ID=$API_ID"
echo "ROLE_ARN=$ROLE_ARN"
echo "INVOKE_URL=$INVOKE_URL"

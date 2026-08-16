#!/usr/bin/env bash
# ARQ-009 PoC validation — proves /{branchId} dynamically resolves to two different queues.
# Requires INVOKE_URL, QUEUE_A_URL, QUEUE_B_URL, REGION exported from poc_arq009.sh output.
set -euo pipefail

: "${INVOKE_URL:?set from poc_arq009.sh output}"
: "${QUEUE_A_URL:?set from poc_arq009.sh output}"
: "${QUEUE_B_URL:?set from poc_arq009.sh output}"
: "${REGION:?e.g. us-west-2}"

curl -s -o /dev/null -w 'branchA -> %{http_code}\n' -X POST "$INVOKE_URL/branchA" -d '{"test":"poc-arq009 branchA message"}'
curl -s -o /dev/null -w 'branchB -> %{http_code}\n' -X POST "$INVOKE_URL/branchB" -d '{"test":"poc-arq009 branchB message"}'

aws sqs receive-message --queue-url "$QUEUE_A_URL" --region "$REGION"
aws sqs receive-message --queue-url "$QUEUE_B_URL" --region "$REGION"

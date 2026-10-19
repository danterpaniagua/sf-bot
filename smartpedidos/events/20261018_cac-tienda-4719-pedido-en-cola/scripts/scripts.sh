#!/usr/bin/env bash
# Read-only AWS calls (get-queue-attributes, get-metric-statistics) for the store 4719 report. Outputs go to data/.
# Region us-east-1 (production queues), account 382381053403. Window 19:30-20:30 UTC-3 = 22:30-23:30 UTC on 2026-10-18.
set -uo pipefail
D=/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261018_cac-tienda-4719-pedido-en-cola/data
R=us-east-1; ACC=382381053403; T=$(date +%H%M)
for Q in 4719PRD_PlatformMessages.fifo PRD_BranchMessages.fifo MainDeadLetter.fifo DeadLetter.fifo; do
  {
    echo "== $(date '+%F %T %z') queue $Q =="
    aws sqs get-queue-attributes --region $R --queue-url "https://sqs.$R.amazonaws.com/$ACC/$Q" --attribute-names All --output json 2>&1
  } > "$D/sqs-attributes-$Q-$T.txt"
done
for M in "NumberOfMessagesSent Sum" "NumberOfMessagesReceived Sum" "NumberOfMessagesDeleted Sum" "ApproximateAgeOfOldestMessage Maximum" "ApproximateNumberOfMessagesVisible Maximum" "ApproximateNumberOfMessagesNotVisible Maximum"; do
  set -- $M
  {
    echo "== $(date '+%F %T %z') 4719PRD_PlatformMessages.fifo $1 $2 (1-minute, UTC) =="
    aws cloudwatch get-metric-statistics --region $R --namespace AWS/SQS --metric-name "$1" --dimensions Name=QueueName,Value=4719PRD_PlatformMessages.fifo \
      --start-time 2026-10-18T22:30:00Z --end-time 2026-10-18T23:30:00Z --period 60 --statistics "$2" --output json 2>&1
  } > "$D/cw-4719-$1-$T.txt"
done
echo "done; files in $D with suffix $T"

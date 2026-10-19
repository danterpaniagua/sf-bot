#!/usr/bin/env bash
# GITIN-2252 — read-only (CloudWatch get-metric-statistics): production queue PRD_BranchMessages.fifo and the dead-letter queues, 2026-10-18 from 10:00 UTC-3 until now, 1-minute data.
# Region us-east-1, account 382381053403. Outputs go to data/ with the run time as suffix. Used to check the user-stated link between the WebService/Mobile spikes and the queue, and that the dead-letter queues did not grow.
set -uo pipefail
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261018_gitin2252-guardia-dia-de-la-madre/data
R=us-east-1; T=$(date +%H%M); START=2026-10-18T13:00:00Z; END=$(date -u +%FT%TZ)
cw() { # queue metric stat [stat...]
  local q=$1 m=$2; shift 2
  aws cloudwatch get-metric-statistics --region $R --namespace AWS/SQS --metric-name "$m" --dimensions Name=QueueName,Value="$q" \
    --start-time "$START" --end-time "$END" --period 60 --statistics "$@" --output json 2>&1
}
# Maximum for every metric (peak per minute); count metrics also get Sum, because Maximum alone is not the volume of messages in the minute
for M in NumberOfMessagesSent NumberOfMessagesReceived NumberOfMessagesDeleted; do
  { echo "== $(date '+%F %T %z') PRD_BranchMessages.fifo $M Sum Maximum (1 min, UTC) =="; cw PRD_BranchMessages.fifo "$M" Sum Maximum; } > "$D/sqs-PRD_BranchMessages-$M-$T.txt"
done
for M in ApproximateAgeOfOldestMessage ApproximateNumberOfMessagesVisible; do
  { echo "== $(date '+%F %T %z') PRD_BranchMessages.fifo $M Maximum (1 min, UTC) =="; cw PRD_BranchMessages.fifo "$M" Maximum; } > "$D/sqs-PRD_BranchMessages-$M-$T.txt"
done
for Q in MainDeadLetter.fifo DeadLetter.fifo; do
  { echo "== $(date '+%F %T %z') $Q NumberOfMessagesSent Sum Maximum (1 min, UTC) =="; cw "$Q" NumberOfMessagesSent Sum Maximum; } > "$D/sqs-$Q-NumberOfMessagesSent-$T.txt"
  { echo "== $(date '+%F %T %z') $Q ApproximateNumberOfMessagesVisible Maximum (1 min, UTC) =="; cw "$Q" ApproximateNumberOfMessagesVisible Maximum; } > "$D/sqs-$Q-ApproximateNumberOfMessagesVisible-$T.txt"
done
echo "done; files in $D with suffix $T"

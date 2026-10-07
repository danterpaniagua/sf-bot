#!/bin/bash
# GITIN-1965 — peak-season cross-check: SQS ApproximateAgeOfOldestMessage for
# PRD_BranchMessages.fifo, same weekend windows as the other fetch scripts.
# Cleaner signal than concentrador-service CPU (which is confounded by the
# unrelated fan-out bug from GITIN-1964) — backlog age reflects whether the
# consumer is keeping up with real message volume.
#
# Usage: ./fetch_sqs_age_weeks.sh [weeks_back]   (default weeks_back=3)
# Files: data/now_sqs_branchmessages_age.json, data/now-1w_..., ...
#
# Read-only CloudWatch calls — no state changes.

set -euo pipefail

OUTDIR="$(dirname "$0")/data"
mkdir -p "$OUTDIR"

WEEKS_BACK="${1:-3}"
REGION="us-east-1"
PROFILE="dpaniagua.smartfran"
QUEUE_NAME="PRD_BranchMessages.fifo"

DOW=$(TZ=America/Argentina/Cordoba date +%u)
DAYS_SINCE_SAT=$(( (DOW - 6 + 7) % 7 ))
CURRENT_SAT=$(TZ=America/Argentina/Cordoba date -d "-${DAYS_SINCE_SAT} days" +%Y-%m-%d)

for offset in $(seq 0 "$WEEKS_BACK"); do
  sat=$(date -d "$CURRENT_SAT -$((offset * 7)) days" +%Y-%m-%d)
  sun=$(date -d "$sat +1 day" +%Y-%m-%d)
  label="now"
  [ "$offset" -gt 0 ] && label="now-${offset}w"

  time_from=$(date -u -d "$sat 00:00:00 -03:00" +%Y-%m-%dT%H:%M:%SZ)
  time_till=$(date -u -d "$sun 23:59:59 -03:00" +%Y-%m-%dT%H:%M:%SZ)

  outfile="$OUTDIR/${label}_sqs_branchmessages_age.json"
  echo "== $label: $sat/$sun local ($time_from -> $time_till UTC) =="
  aws cloudwatch get-metric-statistics --namespace AWS/SQS --metric-name ApproximateAgeOfOldestMessage \
    --dimensions Name=QueueName,Value="$QUEUE_NAME" \
    --start-time "$time_from" --end-time "$time_till" --period 300 --statistics Average Maximum \
    --region "$REGION" --profile "$PROFILE" > "$outfile"
  echo "Saved -> $outfile"
done

echo
echo "Done."

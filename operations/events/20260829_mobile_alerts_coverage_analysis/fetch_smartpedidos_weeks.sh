#!/bin/bash
# GITIN-1965 — peak-season cross-check: SmartPedidos CPUUtilization (CloudWatch),
# same weekend windows as fetch_get_post_weeks.sh (now, now-1w, now-2w, now-3w).
# Fully relative to "now" — no hardcoded dates. Mirrors GITIN-1964's CloudWatch
# query pattern (cluster smartfran-pedidos-production, us-east-1).
#
# Usage: ./fetch_smartpedidos_weeks.sh [weeks_back]   (default weeks_back=3)
# Files: data/now_concentrador_cpu.json, data/now-1w_concentrador_cpu.json, ...
#        data/now_platform_cpu.json, ...
#
# Read-only CloudWatch calls — no state changes.

set -euo pipefail

OUTDIR="$(dirname "$0")/data"
mkdir -p "$OUTDIR"

WEEKS_BACK="${1:-3}"
REGION="us-east-1"
PROFILE="dpaniagua.smartfran"
CLUSTER="smartfran-pedidos-production"

SERVICES=(
  "concentrador:concentrador-service-production-service"
  "platform:platform-service-production-service"
)

# Most recent Saturday <= today, local (America/Argentina/Cordoba, fixed UTC-3).
DOW=$(TZ=America/Argentina/Cordoba date +%u)
DAYS_SINCE_SAT=$(( (DOW - 6 + 7) % 7 ))
CURRENT_SAT=$(TZ=America/Argentina/Cordoba date -d "-${DAYS_SINCE_SAT} days" +%Y-%m-%d)

for offset in $(seq 0 "$WEEKS_BACK"); do
  sat=$(date -d "$CURRENT_SAT -$((offset * 7)) days" +%Y-%m-%d)
  sun=$(date -d "$sat +1 day" +%Y-%m-%d)
  label="now"
  [ "$offset" -gt 0 ] && label="now-${offset}w"

  # Convert local (-03:00) window to UTC 'Z' timestamps for CloudWatch.
  time_from=$(date -u -d "$sat 00:00:00 -03:00" +%Y-%m-%dT%H:%M:%SZ)
  time_till=$(date -u -d "$sun 23:59:59 -03:00" +%Y-%m-%dT%H:%M:%SZ)

  echo "== $label: $sat/$sun local ($time_from -> $time_till UTC) =="
  for svc in "${SERVICES[@]}"; do
    IFS=':' read -r svclabel svcname <<< "$svc"
    outfile="$OUTDIR/${label}_${svclabel}_cpu.json"
    aws cloudwatch get-metric-statistics --namespace AWS/ECS --metric-name CPUUtilization \
      --dimensions Name=ClusterName,Value="$CLUSTER" Name=ServiceName,Value="$svcname" \
      --start-time "$time_from" --end-time "$time_till" --period 300 --statistics Average Maximum \
      --region "$REGION" --profile "$PROFILE" > "$outfile"
    echo "Saved -> $outfile"
  done
done

echo
echo "Done."

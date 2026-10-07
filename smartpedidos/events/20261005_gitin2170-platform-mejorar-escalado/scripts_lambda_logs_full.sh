#!/usr/bin/env bash
# GITIN-2170: complete invocation log of IntegrationLambdaEcsTaskProd since Fri 2026-10-02 00:00 ART (the first extract in
# scripts_read_escalation_lambda.sh returned only 2 invocations). Paginates explicitly and keeps the lines that show what each
# invocation saw/did, plus any timeout/error line.
# Usage: bash scripts_lambda_logs_full.sh <aws-cli-profile>
# Read-only (logs:FilterLogEvents). Output under data/ (e-mail/phone/AWS-key masking as in the other script).
set -eu
E=/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261005_gitin2170-platform-mejorar-escalado/data
P="${1:?usage: $0 <aws-cli-profile>}"
R=us-east-1
LG=/aws/lambda/IntegrationLambdaEcsTaskProd
START_MS=$(( $(date -d '2026-10-02 00:00 -0300' +%s) * 1000 ))
mkdir -p "$E"
mask() { sed -E -e 's/(AKIA|ASIA)[A-Z0-9]{12}([A-Z0-9]{4})/\1************\2/g' -e 's/[A-Za-z0-9._%+-]+@([A-Za-z0-9.-]+\.[A-Za-z]{2,})/***@\1/g' -e 's/\+[0-9]{8,}([0-9]{4})/+*********\1/g'; }

OUT="$E/lambda_IntegrationLambdaEcsTaskProd_logs_full_since_oct2.tsv"
: > "$OUT"
TOKEN=""
while :; do
  if [ -z "$TOKEN" ]; then
    RESP=$(aws --profile "$P" --region "$R" --output json logs filter-log-events --log-group-name "$LG" --start-time "$START_MS")
  else
    RESP=$(aws --profile "$P" --region "$R" --output json logs filter-log-events --log-group-name "$LG" --start-time "$START_MS" --next-token "$TOKEN")
  fi
  echo "$RESP" | jq -r '.events[]|[(.timestamp/1000|todate),(.message|rtrimstr("\n")|gsub("\t";" "))]|@tsv' | mask >> "$OUT"
  TOKEN=$(echo "$RESP" | jq -r '.nextToken // empty')
  [ -n "$TOKEN" ] || break
done

# One line per invocation: start, running/desired/pending seen, REPORT duration, and any timeout/error line
grep -E 'START RequestId|Tareas Actuales|Tareas Deseadas antes|Tareas Pendientes|Task timed out|Traceback|Error|REPORT RequestId' "$OUT" \
  | cut -c1-200 > "$E/lambda_IntegrationLambdaEcsTaskProd_logs_summary_since_oct2.txt"
echo "done: $(wc -l < "$OUT") log lines; summary in $E/lambda_IntegrationLambdaEcsTaskProd_logs_summary_since_oct2.txt"

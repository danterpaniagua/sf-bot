#!/usr/bin/env bash
# Event: 20261013_sqs-spikes-20261011
# C1 — Solo lectura contra CloudWatch (AWS/SQS, us-east-1, cuenta 382381053403). Series por cola de tres metricas en
#      periodos de 5 min: NumberOfMessagesSent, ApproximateNumberOfMessagesVisible, ApproximateAgeOfOldestMessage.
#      Resume las 15 colas con mayor pico y el total por periodo. Ventana del evento: 2026-10-11 22:00 hora local (UTC-3) +-3 h.
# Uso:  FROM / TO en UTC (ISO). Evento:    bash scripts.sh evento   2026-10-11T22:00:00Z 2026-10-12T04:00:00Z
#       Linea base (domingo anterior):     bash scripts.sh base     2026-10-04T22:00:00Z 2026-10-05T04:00:00Z
# Salidas en data/c1-<etiqueta>-*.json y data/c1-<etiqueta>-top.txt (rutas nuevas por corrida; noclobber).
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR

LABEL="${1:?etiqueta (evento|base)}"; FROM="${2:?inicio UTC}"; TO="${3:?fin UTC}"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261013_sqs-spikes-20261011/data"
REGION=us-east-1

pull() {  # $1 metrica  $2 estadistica
  local m="$1" s="$2" f="$OUT/c1-$LABEL-$1.json"
  aws cloudwatch get-metric-data --region "$REGION" --start-time "$FROM" --end-time "$TO" \
    --metric-data-queries "[{\"Id\":\"q\",\"Expression\":\"SEARCH('{AWS/SQS,QueueName} MetricName=\\\"$m\\\"', '$s', 300)\",\"ReturnData\":true}]" \
    --output json > "$f"
  echo "$m: $(jq '.MetricDataResults | length' "$f") series, mensajes=$(jq '[.Messages[]?] | length' "$f")"
}
pull NumberOfMessagesSent Sum
pull ApproximateNumberOfMessagesVisible Maximum
pull ApproximateAgeOfOldestMessage Maximum

# Top 15 colas por maximo de cada metrica
for m in NumberOfMessagesSent ApproximateNumberOfMessagesVisible ApproximateAgeOfOldestMessage; do
  echo "== $m (top 15 por maximo en la ventana; hora UTC del pico)"
  jq -r '.MetricDataResults[] | select((.Values|length)>0)
         | [(.Values|max), .Label, (.Timestamps[(.Values|index(max))])] | @tsv' "$OUT/c1-$LABEL-$m.json" \
    | sort -rn | head -15
done > "$OUT/c1-$LABEL-top.txt"
echo "listo: $OUT/c1-$LABEL-top.txt"

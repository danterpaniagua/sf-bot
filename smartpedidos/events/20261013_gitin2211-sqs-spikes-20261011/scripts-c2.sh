#!/usr/bin/env bash
# Event: 20261013_sqs-spikes-20261011
# C2 — Solo lectura contra CloudWatch (AWS/SQS, us-east-1). C1 uso SEARCH y CloudWatch corto la respuesta en 500 series
#      (MaxMetricsExceeded), asi que la linea base no trajo PRD_BranchMessages.fifo. Aqui se piden por nombre las colas
#      que no son por sucursal, 10 dias a 5 min, para comparar la misma franja de cada dia:
#        PRD_BranchMessages.fifo : NumberOfMessagesSent (Sum)
#        MainDeadLetter.fifo y DeadLetter.fifo : ApproximateNumberOfMessagesVisible (Max) y NumberOfMessagesSent (Sum)
#      Resumen: por dia, maximo y hora local del maximo; y valores de 21:00 a 23:00 locales.
# Uso:  bash scripts-c2.sh <etiqueta>   (etiqueta nueva por corrida; noclobber)
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
LABEL="${1:?etiqueta}"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261013_sqs-spikes-20261011/data"
FROM="2026-10-03T03:00:00Z"; TO="2026-10-13T03:00:00Z"   # 10 dias locales completos: 2026-10-03 00:00 a 2026-10-13 00:00
F="$OUT/c2-$LABEL.json"
q() { echo "{\"Id\":\"$1\",\"Label\":\"$2\",\"ReturnData\":true,\"MetricStat\":{\"Period\":300,\"Stat\":\"$3\",\"Metric\":{\"Namespace\":\"AWS/SQS\",\"MetricName\":\"$4\",\"Dimensions\":[{\"Name\":\"QueueName\",\"Value\":\"$5\"}]}}}"; }
Q="[$(q a bm_sent Sum NumberOfMessagesSent PRD_BranchMessages.fifo),
$(q b mdl_vis Maximum ApproximateNumberOfMessagesVisible MainDeadLetter.fifo),
$(q c mdl_sent Sum NumberOfMessagesSent MainDeadLetter.fifo),
$(q d dl_vis Maximum ApproximateNumberOfMessagesVisible DeadLetter.fifo),
$(q e dl_sent Sum NumberOfMessagesSent DeadLetter.fifo)]"
aws cloudwatch get-metric-data --region us-east-1 --start-time "$FROM" --end-time "$TO" --metric-data-queries "$Q" --output json > "$F"
echo "mensajes de CloudWatch: $(jq -c '.Messages' "$F")"
for id in bm_sent mdl_vis mdl_sent dl_vis dl_sent; do
  echo "== $id: puntos=$(jq --arg l "$id" '[.MetricDataResults[]|select(.Label==$l)|.Values|length]|add' "$F")"
  # maximo por dia local y hora del maximo
  jq -r --arg l "$id" '.MetricDataResults[]|select(.Label==$l)|[.Timestamps,.Values]|transpose[]|"\(.[0][0:10]) \(.[0][11:16]) \(.[1])"' "$F" \
    | sort | awk '{d=$1; if($3+0>m[d]+0){m[d]=$3;t[d]=$2}} END{for(d in m) print d, "max="m[d], "a las "t[d]}' | sort
done

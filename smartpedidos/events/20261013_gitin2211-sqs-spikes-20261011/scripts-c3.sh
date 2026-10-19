#!/usr/bin/env bash
# Event: 20261013_sqs-spikes-20261011
# C3 — Solo lectura contra CloudWatch (AWS/SQS, us-east-1), cola PRD_BranchMessages.fifo, pedida por nombre (sin SEARCH).
#      El pico lo ve el usuario en Grafana el 2026-10-11 a las 22:03 (UTC-3). Grafana lee las metricas SQS del exporter de
#      CloudWatch (ApproximateAgeOfOldestMessage, ...Visible, NumberOfMessagesSent/Received/Deleted).
#      A) fino : 21:30 a 22:30 locales, periodo 60 s : edad, visibles, en vuelo, enviados, recibidos, borrados
#      B) 10 dias, periodo 300 s : edad maxima -> episodios con edad > 60 s
# Uso:  bash scripts-c3.sh <etiqueta>   (etiqueta nueva por corrida; noclobber)
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
LABEL="${1:?etiqueta}"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261013_sqs-spikes-20261011/data"
Qn=PRD_BranchMessages.fifo
q() { echo "{\"Id\":\"$1\",\"Label\":\"$1\",\"ReturnData\":true,\"MetricStat\":{\"Period\":$2,\"Stat\":\"$3\",\"Metric\":{\"Namespace\":\"AWS/SQS\",\"MetricName\":\"$4\",\"Dimensions\":[{\"Name\":\"QueueName\",\"Value\":\"$Qn\"}]}}}"; }

FA="$OUT/c3-$LABEL-fino.json"
aws cloudwatch get-metric-data --region us-east-1 --start-time 2026-10-12T00:30:00Z --end-time 2026-10-12T01:30:00Z --metric-data-queries \
"[$(q age 60 Maximum ApproximateAgeOfOldestMessage),$(q visible 60 Maximum ApproximateNumberOfMessagesVisible),$(q inflight 60 Maximum ApproximateNumberOfMessagesNotVisible),$(q sent 60 Sum NumberOfMessagesSent),$(q received 60 Sum NumberOfMessagesReceived),$(q deleted 60 Sum NumberOfMessagesDeleted)]" \
--output json > "$FA"
echo "A) mensajes de CloudWatch: $(jq -c '.Messages' "$FA")"
echo "A) hora_local edad visibles en_vuelo enviados recibidos borrados  (minutos con edad>0 o visibles>0 o borrados=0, 21:30-22:30)"
jq -r '[.MetricDataResults[]|{(.Id):([.Timestamps,.Values]|transpose|map({(.[0]):.[1]})|add)}]|add as $m
  | ($m.sent|keys)[] as $t | [$t[11:16], ($m.age[$t]//"-"), ($m.visible[$t]//"-"), ($m.inflight[$t]//"-"), ($m.sent[$t]//0), ($m.received[$t]//0), ($m.deleted[$t]//0)] | @tsv' "$FA" | sort \
  | awk -F'\t' '$2!="-" && ($2+0>0 || $3+0>0 || $7+0==0)'

FB="$OUT/c3-$LABEL-10d.json"
aws cloudwatch get-metric-data --region us-east-1 --start-time 2026-10-03T03:00:00Z --end-time 2026-10-13T03:00:00Z --metric-data-queries \
"[$(q age 300 Maximum ApproximateAgeOfOldestMessage)]" --output json > "$FB"
echo "B) buckets de 5 min con edad > 60 s en 10 dias (fecha hora_local edad_s):"
jq -r '.MetricDataResults[0]|[.Timestamps,.Values]|transpose[]|select(.[1]>60)|"\(.[0][0:10]) \(.[0][11:16]) \(.[1])"' "$FB" | sort

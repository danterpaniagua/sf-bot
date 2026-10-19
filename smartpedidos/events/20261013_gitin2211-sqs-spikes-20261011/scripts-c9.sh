#!/usr/bin/env bash
# Event: 20261013_sqs-spikes-20261011
# C9 — Solo lectura (us-east-1). El usuario indica que el disparador usa ApproximateAgeOfOldestMessage con estadistica Maximum
#      sobre PRD_BranchMessages.fifo; C5 leyo la alarma sendMailOldestMessage con Statistic=Average, Period=300, Threshold=25.
#      Aqui: configuracion completa de la alarma (incluye OKActions), cambios de configuracion de los ultimos 30 dias, y toda
#      alarma de la region que mencione PRD_BranchMessages.fifo, ApproximateAgeOfOldestMessage o el topic Pedidos_Production
#      (incluye alarmas compuestas y de metric math).
# Uso:  bash scripts-c9.sh <etiqueta>   (etiqueta nueva por corrida; noclobber)
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
LABEL="${1:?etiqueta}"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261013_sqs-spikes-20261011/data"
R=us-east-1
aws cloudwatch describe-alarms --region $R --alarm-names sendMailOldestMessage --output json > "$OUT/c9-$LABEL-alarm-sendMailOldestMessage.json"
echo "== sendMailOldestMessage (config actual)"
jq -c '.MetricAlarms[0]|{Namespace,MetricName,Statistic,ExtendedStatistic,Period,EvaluationPeriods,DatapointsToAlarm,Threshold,ComparisonOperator,TreatMissingData,ActionsEnabled,StateValue,AlarmConfigurationUpdatedTimestamp,Dimensions,AlarmActions:(.AlarmActions|map(split(":")|last)),OKActions:(.OKActions|map(split(":")|last)),InsufficientDataActions:(.InsufficientDataActions|map(split(":")|last))}' "$OUT/c9-$LABEL-alarm-sendMailOldestMessage.json"
aws cloudwatch describe-alarm-history --region $R --alarm-name sendMailOldestMessage --history-item-type ConfigurationUpdate \
  --start-date "$(date -u -d '30 days ago' +%FT%TZ)" --end-date "$(date -u +%FT%TZ)" --output json > "$OUT/c9-$LABEL-config-history.json"
echo "== cambios de configuracion (30 dias): $(jq '.AlarmHistoryItems|length' "$OUT/c9-$LABEL-config-history.json")"
jq -r '.AlarmHistoryItems|sort_by(.Timestamp)[]|"  \(.Timestamp) \(.HistorySummary)"' "$OUT/c9-$LABEL-config-history.json"
aws cloudwatch describe-alarms --region $R --alarm-types MetricAlarm CompositeAlarm --output json > "$OUT/c9-$LABEL-all-alarms.json"
echo "== alarmas de la region que mencionan la cola, la metrica de edad o el topic Pedidos_Production"
jq -r '(.MetricAlarms[]?, .CompositeAlarms[]?) | select(tostring | test("PRD_BranchMessages|ApproximateAgeOfOldestMessage|Pedidos_Production"))
       | "  \(.AlarmName) | \(.MetricName // "composite/metric-math") | \(.Statistic // "-") | periodo \(.Period // "-") | umbral \(.Threshold // "-") | \(.StateValue)"' "$OUT/c9-$LABEL-all-alarms.json"

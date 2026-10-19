#!/usr/bin/env bash
# Event: 20261013_sqs-spikes-20261011
# C5 — Solo lectura. Que hizo la Lambda IntegrationLambdaEcsTaskProd (segun el usuario, escala Fargate cuando la edad del
#      mensaje mas viejo llega a 300 s) alrededor de las 22:03 locales (UTC-3) del 2026-10-11.
#      1) Region de la Lambda (us-east-1 o us-east-2) y su configuracion SIN valores de variables de entorno (solo nombres)
#      2) Lo que la dispara: reglas de EventBridge con la Lambda como destino, y alarmas de CloudWatch sobre AWS/SQS
#      3) Invocaciones, errores y duracion: 21:30-22:30 a 60 s, y 10 dias a 300 s (buckets con invocaciones)
#      4) Logs de la Lambda 21:50-22:30 (archivo detail-*, fuera del control de versiones)
#      5) Servicio ECS platform-service-production-service: eventos y actividad de Application Auto Scaling de esa franja
# Uso:  bash scripts-c5.sh <etiqueta>   (etiqueta nueva por corrida; noclobber)
set -uo pipefail
LABEL="${1:?etiqueta}"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261013_sqs-spikes-20261011/data"
FN=IntegrationLambdaEcsTaskProd
SVC=platform-service-production-service
S_MS=$(( $(date -d "2026-10-11 21:50 -0300" +%s) * 1000 )); E_MS=$(( $(date -d "2026-10-11 22:30 -0300" +%s) * 1000 ))
S_ISO=$(date -u -d "2026-10-11 21:30 -0300" +%FT%TZ); E_ISO=$(date -u -d "2026-10-11 22:30 -0300" +%FT%TZ)
D_S=2026-10-03T03:00:00Z; D_E=2026-10-13T03:00:00Z

echo "== 1) region y configuracion"
REGION=""
for r in us-east-1 us-east-2; do
  if aws lambda get-function-configuration --region "$r" --function-name "$FN" 2> "$OUT/c5-$LABEL-lambda-config-$r.err" \
      | jq '.Environment.Variables |= (if . then keys else . end)' > "$OUT/c5-$LABEL-lambda-config-$r.json" && [ -s "$OUT/c5-$LABEL-lambda-config-$r.json" ]; then
    REGION="$r"; break
  fi
done
[ -n "$REGION" ] || { echo "la Lambda no se encontro en us-east-1 ni us-east-2 (ver data/c5-$LABEL-lambda-config-*.err)"; exit 1; }
echo "region: $REGION"
jq -r '"runtime=\(.Runtime) timeout=\(.Timeout)s memoria=\(.MemorySize)MB ultima_modificacion=\(.LastModified) env_var_nombres=\(.Environment.Variables // [] | join(","))"' "$OUT/c5-$LABEL-lambda-config-$REGION.json"
ARN=$(jq -r '.FunctionArn' "$OUT/c5-$LABEL-lambda-config-$REGION.json")

echo "== 2) disparadores"
aws events list-rule-names-by-target --region "$REGION" --target-arn "$ARN" --output json > "$OUT/c5-$LABEL-eventbridge-rules.json" 2>&1 || true
echo "reglas de EventBridge con la Lambda como destino: $(jq -c '.RuleNames // .' "$OUT/c5-$LABEL-eventbridge-rules.json" 2>/dev/null)"
for r in us-east-1 us-east-2; do
  aws cloudwatch describe-alarms --region "$r" --output json 2>/dev/null \
    | jq '[.MetricAlarms[] | select(.Namespace=="AWS/SQS" or ((.Metrics // []) | map(.MetricStat.Metric.Namespace // "") | any(.=="AWS/SQS"))) | {AlarmName, MetricName, Statistic, ExtendedStatistic, Period, EvaluationPeriods, DatapointsToAlarm, Threshold, ComparisonOperator, StateValue, StateUpdatedTimestamp, AlarmActions, Dimensions}]' \
    > "$OUT/c5-$LABEL-alarms-sqs-$r.json" || true
  echo "alarmas sobre AWS/SQS en $r: $(jq 'length' "$OUT/c5-$LABEL-alarms-sqs-$r.json")"
done

echo "== 3) invocaciones"
DIM="Name=FunctionName,Value=$FN"
for m in Invocations Errors; do
  aws cloudwatch get-metric-statistics --region "$REGION" --namespace AWS/Lambda --metric-name $m --dimensions "$DIM" \
    --start-time "$S_ISO" --end-time "$E_ISO" --period 60 --statistics Sum --output json > "$OUT/c5-$LABEL-$m-fino.json"
  echo "$m 21:30-22:30 (minuto local, suma):"
  jq -r '.Datapoints|sort_by(.Timestamp)[]|select(.Sum>0)|"  \(.Timestamp) \(.Sum)"' "$OUT/c5-$LABEL-$m-fino.json"
done
aws cloudwatch get-metric-statistics --region "$REGION" --namespace AWS/Lambda --metric-name Invocations --dimensions "$DIM" \
  --start-time "$D_S" --end-time "$D_E" --period 300 --statistics Sum --output json > "$OUT/c5-$LABEL-Invocations-10d.json"
echo "Invocations 10 dias, buckets de 5 min con invocaciones (UTC):"
jq -r '.Datapoints|sort_by(.Timestamp)[]|select(.Sum>0)|"  \(.Timestamp) \(.Sum)"' "$OUT/c5-$LABEL-Invocations-10d.json"

echo "== 4) logs"
aws logs filter-log-events --region "$REGION" --log-group-name "/aws/lambda/$FN" --start-time "$S_MS" --end-time "$E_MS" --output json \
  > "$OUT/detail-c5-$LABEL-lambda-logs.json" 2> "$OUT/c5-$LABEL-lambda-logs.err" || true
echo "eventos de log 21:50-22:30: $(jq '.events|length' "$OUT/detail-c5-$LABEL-lambda-logs.json" 2>/dev/null || echo 'sin datos, ver c5-'"$LABEL"'-lambda-logs.err')"

echo "== 5) ECS"
for r in us-east-1 us-east-2; do
  for c in $(aws ecs list-clusters --region "$r" --query 'clusterArns[]' --output text 2>/dev/null); do
    n=$(aws ecs describe-services --region "$r" --cluster "$c" --services "$SVC" --query 'length(services)' --output text 2>/dev/null || echo 0)
    if [ "${n:-0}" -ge 1 ] 2>/dev/null; then
      CL="${c##*/}"; echo "servicio $SVC en cluster $CL ($r)"
      aws ecs describe-services --region "$r" --cluster "$c" --services "$SVC" --output json \
        | jq --argjson s "$S_MS" --argjson e "$E_MS" '{desired:.services[0].desiredCount, running:.services[0].runningCount, eventos_en_la_franja:[.services[0].events[] | select((.createdAt*1000) >= $s and (.createdAt*1000) <= $e)], eventos_mas_antiguo_en_buffer:(.services[0].events | last | .createdAt)}' \
        > "$OUT/c5-$LABEL-ecs-events.json"
      echo "eventos ECS en la franja: $(jq '.eventos_en_la_franja|length' "$OUT/c5-$LABEL-ecs-events.json"); evento mas antiguo del buffer (epoch o fecha): $(jq -r '.eventos_mas_antiguo_en_buffer' "$OUT/c5-$LABEL-ecs-events.json")"
      aws application-autoscaling describe-scaling-activities --region "$r" --service-namespace ecs --resource-id "service/$CL/$SVC" --output json > "$OUT/c5-$LABEL-aas-activities.json" 2>/dev/null || true
      echo "actividad de Application Auto Scaling 21:30-22:30 locales:"
      jq -r --arg s "$S_ISO" --arg e "$E_ISO" '.ScalingActivities[]? | select(.StartTime >= $s and .StartTime <= $e) | "  \(.StartTime) \(.StatusCode) \(.Description) | \(.Cause)"' "$OUT/c5-$LABEL-aas-activities.json" 2>/dev/null || true
      break 2
    fi
  done
done
echo "listo"

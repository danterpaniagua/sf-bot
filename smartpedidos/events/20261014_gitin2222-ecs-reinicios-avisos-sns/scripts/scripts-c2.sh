#!/usr/bin/env bash
# Event: 20261014_gitin2222-ecs-reinicios-avisos-sns
# C2 - Solo lectura (AWS, cuenta de SmartPedidos, region us-east-1, cluster smartfran-pedidos-production). Sigue a C1.
#      a) definicion (patron de eventos y destinos) de las 6 reglas ECS-*/ECR-*: C1 mostro que "ECS-Task-Definition-Version-Created" y "ECS-Task-ECSTaskStateChange-Team"
#         tienen casi el mismo conteo por hora (2735 vs 2723 en 14 dias); el patron dice si las dos reglas capturan los mismos eventos
#      b) Auto Scaling de los dos servicios: objetivos, politicas y actividades de escalado (historial de unas 6 semanas, con la causa de cada una); explica los picos de tareas
#      c) salud de los targets del balanceador (HealthyHostCount minimo y UnHealthyHostCount maximo por hora, 14 dias) y CPU/memoria maxima por hora de cada servicio
#      Salidas en data/c2-*. Credenciales AWS de solo lectura ya configuradas en el entorno. No imprime credenciales ni endpoints de suscripciones.
set -uo pipefail
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/data"
R="us-east-1"; C="smartfran-pedidos-production"
SERVICES="platform-service-production-service concentrador-service-production-service"
echo "cuenta: $(aws sts get-caller-identity --query Account --output text --region $R) | region $R | $(date -u +%FT%TZ)"
S=$(date -u -d '14 days ago' +%FT%T.000Z); E=$(date -u +%FT%T.000Z)

echo "== a) reglas: patron de eventos y destinos"
for RULE in $(jq -r '.[]' "$OUT/c1-rules.json"); do
  aws events describe-rule --name "$RULE" --region $R --output json \
    | jq '{Name, State, EventPattern: (.EventPattern | fromjson? // .EventPattern), ScheduleExpression}' > "$OUT/c2-rule-$RULE.json" || echo "FALLO describe-rule $RULE"
  aws events list-targets-by-rule --rule "$RULE" --region $R --output json \
    | jq '[.Targets[] | {Id, Arn, InputTransformer: (.InputTransformer // null), Input: (.Input // null)}]' > "$OUT/c2-targets-$RULE.json" || echo "FALLO list-targets $RULE"
  echo "-- $RULE"
  jq -c '{State, EventPattern}' "$OUT/c2-rule-$RULE.json" 2>/dev/null
  jq -r '.[].Arn | split(":") | last' "$OUT/c2-targets-$RULE.json" 2>/dev/null | sed 's/^/   destino: /'
done

echo "== b) Auto Scaling de los servicios"
for SV in $SERVICES; do
  RES="service/$C/$SV"
  aws application-autoscaling describe-scalable-targets --service-namespace ecs --resource-ids "$RES" --region $R --output json > "$OUT/c2-scalable-target-$SV.json" || echo "FALLO scalable-targets $SV"
  aws application-autoscaling describe-scaling-policies --service-namespace ecs --resource-id "$RES" --region $R --output json > "$OUT/c2-scaling-policies-$SV.json" || echo "FALLO scaling-policies $SV"
  aws application-autoscaling describe-scaling-activities --service-namespace ecs --resource-id "$RES" --region $R --output json > "$OUT/c2-scaling-activities-$SV.json" || echo "FALLO scaling-activities $SV"
  echo "-- $SV"
  jq -r '.ScalableTargets[] | "   min=\(.MinCapacity) max=\(.MaxCapacity)"' "$OUT/c2-scalable-target-$SV.json" 2>/dev/null
  jq -r '.ScalingPolicies[] | "   politica: \(.PolicyName) tipo=\(.PolicyType) " + ((.TargetTrackingScalingPolicyConfiguration // {}) | "objetivo=\(.TargetValue // "-") metrica=\(.PredefinedMetricSpecification.PredefinedMetricType // "-") enfriamiento_in=\(.ScaleInCooldown // "-") out=\(.ScaleOutCooldown // "-")")' "$OUT/c2-scaling-policies-$SV.json" 2>/dev/null
  echo "   actividades de escalado: $(jq '.ScalingActivities|length' "$OUT/c2-scaling-activities-$SV.json" 2>/dev/null) (la mas antigua: $(jq -r '.ScalingActivities|map(.StartTime)|min // "-"' "$OUT/c2-scaling-activities-$SV.json" 2>/dev/null))"
  echo "   por dia (-03:00) y resultado:"
  jq -r '.ScalingActivities[] | [(.StartTime | sub("\\.[0-9]+";"") | fromdateiso8601 - 10800 | strftime("%Y-%m-%d")), .StatusCode, (.Description | gsub("Setting desired count to ";"->"))] | @tsv' "$OUT/c2-scaling-activities-$SV.json" 2>/dev/null \
    | LC_ALL=C awk -F'\t' '{k=$1" "$2; n[k]++} END {for (k in n) printf "      %s  x%d\n", k, n[k]}' | LC_ALL=C sort | tail -25
done

echo "== c) salud de targets del balanceador y CPU/memoria por hora"
: > "$OUT/c2-tg-health-hourly.tsv"; : > "$OUT/c2-service-util-hourly.tsv"
for SV in $SERVICES; do
  TG=$(aws ecs describe-services --cluster "$C" --services "$SV" --region $R --query 'services[0].loadBalancers[0].targetGroupArn' --output text)
  if [ -n "$TG" ] && [ "$TG" != "None" ]; then
    aws elbv2 describe-target-groups --target-group-arns "$TG" --region $R --output json \
      | jq '{TargetGroupName: .TargetGroups[0].TargetGroupName, HealthCheckPath: .TargetGroups[0].HealthCheckPath, HealthCheckIntervalSeconds: .TargetGroups[0].HealthCheckIntervalSeconds, HealthCheckTimeoutSeconds: .TargetGroups[0].HealthCheckTimeoutSeconds, HealthyThresholdCount: .TargetGroups[0].HealthyThresholdCount, UnhealthyThresholdCount: .TargetGroups[0].UnhealthyThresholdCount, Matcher: .TargetGroups[0].Matcher, LoadBalancerArns: .TargetGroups[0].LoadBalancerArns}' > "$OUT/c2-tg-config-$SV.json"
    TGD=$(echo "$TG" | sed -E 's#^arn:aws:elasticloadbalancing:[^:]+:[0-9]+:##')
    LBD=$(jq -r '.LoadBalancerArns[0] // empty' "$OUT/c2-tg-config-$SV.json" | sed -E 's#^arn:aws:elasticloadbalancing:[^:]+:[0-9]+:loadbalancer/##')
    echo "-- $SV  grupo=$TGD  balanceador=$LBD"
    jq -c 'del(.LoadBalancerArns)' "$OUT/c2-tg-config-$SV.json"
    for M in "HealthyHostCount Minimum" "UnHealthyHostCount Maximum"; do
      set -- $M
      aws cloudwatch get-metric-statistics --namespace AWS/ApplicationELB --metric-name "$1" \
        --dimensions Name=TargetGroup,Value="$TGD" Name=LoadBalancer,Value="$LBD" \
        --start-time "$S" --end-time "$E" --period 3600 --statistics "$2" --region $R --output json \
        | jq -r --arg s "$SV" --arg m "$1" --arg k "$2" '.Datapoints[] | [$s, $m, .Timestamp, .[$k]] | @tsv' >> "$OUT/c2-tg-health-hourly.tsv" || echo "FALLO $1 $SV"
    done
  else
    echo "-- $SV: sin target group en el servicio"
  fi
  for M in CPUUtilization MemoryUtilization; do
    aws cloudwatch get-metric-statistics --namespace AWS/ECS --metric-name "$M" \
      --dimensions Name=ClusterName,Value="$C" Name=ServiceName,Value="$SV" \
      --start-time "$S" --end-time "$E" --period 3600 --statistics Maximum --region $R --output json \
      | jq -r --arg s "$SV" --arg m "$M" '.Datapoints[] | [$s, $m, .Timestamp, .Maximum] | @tsv' >> "$OUT/c2-service-util-hourly.tsv" || echo "FALLO $M $SV"
  done
done
echo "horas con UnHealthyHostCount > 0 (por servicio):"
LC_ALL=C awk -F'\t' '$2=="UnHealthyHostCount" && $4>0 {n[$1]++} END {for (s in n) printf "   %s  %d horas\n", s, n[s]}' "$OUT/c2-tg-health-hourly.tsv"
echo "horas con HealthyHostCount minimo < 1 (por servicio):"
LC_ALL=C awk -F'\t' '$2=="HealthyHostCount" && $4<1 {n[$1]++} END {for (s in n) printf "   %s  %d horas\n", s, n[s]}' "$OUT/c2-tg-health-hourly.tsv"
echo "maximo horario de CPU / memoria (%):"
LC_ALL=C awk -F'\t' '{k=$1" "$2; if ($4>m[k]) m[k]=$4} END {for (k in m) printf "   %s  max=%.0f\n", k, m[k]}' "$OUT/c2-service-util-hourly.tsv" | LC_ALL=C sort
echo listo

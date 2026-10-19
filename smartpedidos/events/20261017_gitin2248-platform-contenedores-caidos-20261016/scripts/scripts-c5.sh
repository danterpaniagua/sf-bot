#!/usr/bin/env bash
# Event: 20261017_gitin2248-platform-contenedores-caidos-20261016
# C5 - SOLO LECTURA contra AWS (cuenta 382381053403, us-east-1, cluster smartfran-pedidos-production). Comprobacion de la accion del usuario del 2026-10-17: "desired count de platform-service = 10".
#      (1) ECS: desiredCount, runningCount, pendingCount y despliegues del servicio platform-service-production-service, y sus ultimos 15 eventos (hora local -03:00 como la imprime la CLI de AWS: las marcas de ECS, Auto Scaling y CloudWatch salen con offset -03:00, no en UTC).
#      (2) Application Auto Scaling: objetivos escalables (min/max) y politicas del servicio, para ver si el escalado puede devolver el desired a un valor menor.
#      (3) CloudWatch Container Insights: DesiredTaskCount y RunningTaskCount (minimo cada 60 s) de las ultimas 6 horas: valores distintos de Desired con su primera hora, y tramos con Running < Desired.
#      No se imprime configuracion de contenedores, variables de entorno ni ARNs de roles. Salidas en data/c5/.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
R="us-east-1"; CL="smartfran-pedidos-production"; SV="platform-service-production-service"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261017_gitin2248-platform-contenedores-caidos-20261016/data/c5"; mkdir -p "$OUT"
ACCT=$(aws sts get-caller-identity --query Account --output text --region $R)
[ "$ACCT" = "382381053403" ] || { echo "GUARDA: la cuenta no es 382381053403"; exit 1; }
echo "run $(date -u +%FT%TZ) | cuenta $ACCT"
echo "== (1) ECS servicio"
aws ecs describe-services --region $R --cluster $CL --services $SV --output json > "$OUT/service.json"
jq -r '.services[0]|"desired=\(.desiredCount) running=\(.runningCount) pending=\(.pendingCount) status=\(.status) taskDefinition=\(.taskDefinition|split("/")|last)"' "$OUT/service.json"
jq -r '.services[0].deployments[]|["despliegue",.status,.rolloutState,("desired="+(.desiredCount|tostring)),("running="+(.runningCount|tostring)),("pending="+(.pendingCount|tostring)),(.taskDefinition|split("/")|last),.createdAt,.updatedAt]|@tsv' "$OUT/service.json"
echo "-- ultimos 15 eventos del servicio (hora local -03:00 como la imprime la CLI de AWS)"
jq -r '.services[0].events[0:15][]|[.createdAt[0:19],.message[0:200]]|@tsv' "$OUT/service.json"
echo; echo "== (2) Application Auto Scaling (namespace ecs)"
RID="service/$CL/$SV"
aws application-autoscaling describe-scalable-targets --region $R --service-namespace ecs --resource-ids "$RID" --output json > "$OUT/scalable-targets.json"
echo "objetivos escalables: $(jq '.ScalableTargets|length' "$OUT/scalable-targets.json")"
jq -r '.ScalableTargets[]|["min="+(.MinCapacity|tostring),"max="+(.MaxCapacity|tostring),.ScalableDimension,("creado="+(.CreationTime|tostring)[0:19])]|@tsv' "$OUT/scalable-targets.json"
aws application-autoscaling describe-scaling-policies --region $R --service-namespace ecs --resource-id "$RID" --output json > "$OUT/scaling-policies.json"
echo "politicas: $(jq '.ScalingPolicies|length' "$OUT/scaling-policies.json")"
jq -r '.ScalingPolicies[]|[.PolicyName,.PolicyType,(.TargetTrackingScalingPolicyConfiguration.TargetValue|tostring),(.TargetTrackingScalingPolicyConfiguration.PredefinedMetricSpecification.PredefinedMetricType // (.TargetTrackingScalingPolicyConfiguration.CustomizedMetricSpecification.MetricName // "-")),("scaleIn="+((.TargetTrackingScalingPolicyConfiguration.ScaleInCooldown // "-")|tostring)),("scaleOut="+((.TargetTrackingScalingPolicyConfiguration.ScaleOutCooldown // "-")|tostring))]|@tsv' "$OUT/scaling-policies.json"
aws application-autoscaling describe-scaling-activities --region $R --service-namespace ecs --resource-id "$RID" --max-items 10 --output json > "$OUT/scaling-activities.json"
echo "-- ultimas actividades de escalado (hora local -03:00 como la imprime la CLI de AWS)"
jq -r '.ScalingActivities[]|[.StartTime[0:19],.StatusCode,(.Cause|.[0:150])]|@tsv' "$OUT/scaling-activities.json"
echo; echo "== (3) CloudWatch Container Insights, ultimas 6 h, platform-service"
Q() { jq -nc --arg id "$1" --arg m "$2" --arg c "$CL" --arg s "$SV" '{Id:$id,MetricStat:{Metric:{Namespace:"ECS/ContainerInsights",MetricName:$m,Dimensions:[{Name:"ClusterName",Value:$c},{Name:"ServiceName",Value:$s}]},Period:60,Stat:"Minimum"},ReturnData:true}'; }
END=$(date -u +%Y-%m-%dT%H:%M:00Z); START=$(date -u -d "-6 hours" +%Y-%m-%dT%H:%M:00Z)
aws cloudwatch get-metric-data --region $R --start-time "$START" --end-time "$END" --metric-data-queries "$(jq -nc --argjson a "$(Q run RunningTaskCount)" --argjson b "$(Q des DesiredTaskCount)" '[$a,$b]')" --scan-by TimestampAscending --output json > "$OUT/metric-data.json"
echo "periodo $START -> $END | mensajes: $(jq -c .Messages "$OUT/metric-data.json") | puntos run=$(jq '.MetricDataResults[]|select(.Id=="run")|.Values|length' "$OUT/metric-data.json") des=$(jq '.MetricDataResults[]|select(.Id=="des")|.Values|length' "$OUT/metric-data.json")"
echo "-- cambios de Desired (hora local -03:00, valor)"
jq -r '.MetricDataResults[]|select(.Id=="des")|[.Timestamps,.Values]|transpose|.[]|[.[0][0:16],.[1]]|@tsv' "$OUT/metric-data.json" | awk -F'\t' '$2!=p{print;p=$2}'
echo "-- ultimos 10 puntos (hora, running, desired)"
jq -r '(.MetricDataResults[]|select(.Id=="run")) as $r|(.MetricDataResults[]|select(.Id=="des")) as $d|[range(0;($r.Values|length))]|.[-10:][]|[$r.Timestamps[.][0:16],$r.Values[.],($d.Values[.]//"-")]|@tsv' "$OUT/metric-data.json"
echo listo

#!/usr/bin/env bash
# Event: 20261014_gitin2222-ecs-reinicios-avisos-sns
# C1 - Solo lectura (AWS, cuenta de SmartPedidos, region us-east-1, cluster smartfran-pedidos-production).
#      a) servicios del cluster: cantidad deseada/corriendo, ultimos eventos del servicio (reinicios, "unhealthy", "stopped")
#      b) tareas detenidas que ECS todavia conserva (solo la ultima hora aprox.): stopCode, stoppedReason, exitCode y razon de cada contenedor
#      c) volumen de avisos: invocaciones por hora de las reglas de EventBridge ECS-* (14 dias) y mensajes publicados por hora en los topics SNS
#      d) suscripciones de los topics SNS, con los endpoints de email y SMS enmascarados (no se imprime ningun telefono ni correo)
#      Salidas en data/c1-*. Hay que correrlo con credenciales AWS de solo lectura ya configuradas en el entorno.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/data"
R="us-east-1"; C="smartfran-pedidos-production"
echo "cuenta: $(aws sts get-caller-identity --query Account --output text --region $R) | region $R | $(date -u +%FT%TZ)"
# a) servicios y sus eventos
aws ecs list-services --cluster "$C" --region $R --output json > "$OUT/c1-services-list.json"
SERVICES=$(jq -r '.serviceArns[]' "$OUT/c1-services-list.json" | tr '\n' ' ')
# shellcheck disable=SC2086
aws ecs describe-services --cluster "$C" --services $SERVICES --region $R --output json \
  | jq '{services:[.services[] | {serviceName, desiredCount, runningCount, pendingCount, taskDefinition, healthCheckGracePeriodSeconds, deployments:[.deployments[]|{status,rolloutState,desiredCount,runningCount,failedTasks,createdAt}], events:[.events[:30][]|{createdAt,message}]}]}' > "$OUT/c1-services.json"
echo "servicios: $(jq '.services|length' "$OUT/c1-services.json")"
jq -r '.services[] | "\(.serviceName)\tdeseadas=\(.desiredCount)\tcorriendo=\(.runningCount)\tpendientes=\(.pendingCount)"' "$OUT/c1-services.json"
# b) tareas detenidas conservadas por ECS
aws ecs list-tasks --cluster "$C" --desired-status STOPPED --region $R --output json > "$OUT/c1-stopped-list.json"
N=$(jq '.taskArns|length' "$OUT/c1-stopped-list.json"); echo "tareas detenidas conservadas: $N"
if [ "$N" -gt 0 ]; then
  jq -r '.taskArns[:100] | join(" ")' "$OUT/c1-stopped-list.json" > "$OUT/.stopped-arns.tmp"
  # shellcheck disable=SC2046
  aws ecs describe-tasks --cluster "$C" --tasks $(cat "$OUT/.stopped-arns.tmp") --region $R --output json \
    | jq '[.tasks[] | {group, taskDefinitionArn, createdAt, startedAt, stoppedAt, stopCode, stoppedReason, healthStatus, containers:[.containers[]|{name,exitCode,reason,lastStatus,healthStatus}]}]' > "$OUT/c1-stopped.json"
  rm -f "$OUT/.stopped-arns.tmp"
  echo "== por servicio, stopCode y razon (cantidad)"
  jq -r '.[] | [.group, .stopCode, (.stoppedReason // "-")] | @tsv' "$OUT/c1-stopped.json" | LC_ALL=C sort | uniq -c | LC_ALL=C sort -rn | head -20
fi
# c) volumen de avisos: reglas de EventBridge y topics SNS
S=$(date -u -d '14 days ago' +%FT%T.000Z); E=$(date -u +%FT%T.000Z)
aws events list-rules --region $R --query "Rules[?starts_with(Name,'ECS-') || starts_with(Name,'ECR-')].Name" --output json > "$OUT/c1-rules.json"
: > "$OUT/c1-rule-hourly.tsv"
for RULE in $(jq -r '.[]' "$OUT/c1-rules.json"); do
  aws cloudwatch get-metric-statistics --namespace AWS/Events --metric-name TriggeredRules --dimensions Name=RuleName,Value="$RULE" \
    --start-time "$S" --end-time "$E" --period 3600 --statistics Sum --region $R --output json \
    | jq -r --arg r "$RULE" '.Datapoints[] | [$r, .Timestamp, .Sum] | @tsv' >> "$OUT/c1-rule-hourly.tsv"
done
echo "== avisos por regla en 14 dias (suma de TriggeredRules)"
LC_ALL=C awk -F'\t' '{s[$1]+=$3; if ($3>m[$1]) m[$1]=$3} END {for (r in s) printf "%8d total  max/hora=%d  %s\n", s[r], m[r], r}' "$OUT/c1-rule-hourly.tsv" | LC_ALL=C sort -rn
aws sns list-topics --region $R --query 'Topics[].TopicArn' --output json > "$OUT/c1-topics.json"
: > "$OUT/c1-topic-hourly.tsv"
for T in SNS-SmartPedidosTeam-PROD Alertas-EventBridge-PROD; do
  aws cloudwatch get-metric-statistics --namespace AWS/SNS --metric-name NumberOfMessagesPublished --dimensions Name=TopicName,Value="$T" \
    --start-time "$S" --end-time "$E" --period 3600 --statistics Sum --region $R --output json \
    | jq -r --arg t "$T" '.Datapoints[] | [$t, .Timestamp, .Sum] | @tsv' >> "$OUT/c1-topic-hourly.tsv"
done
echo "== mensajes publicados por topic en 14 dias"
LC_ALL=C awk -F'\t' '{s[$1]+=$3; if ($3>m[$1]) m[$1]=$3} END {for (r in s) printf "%8d total  max/hora=%d  %s\n", s[r], m[r], r}' "$OUT/c1-topic-hourly.tsv" | LC_ALL=C sort -rn
# d) suscripciones con endpoints enmascarados
: > "$OUT/c1-subscriptions.tsv"
for T in $(jq -r '.[] | select(test("SNS-SmartPedidosTeam-PROD|Alertas-EventBridge-PROD"))' "$OUT/c1-topics.json"); do
  aws sns list-subscriptions-by-topic --topic-arn "$T" --region $R --output json \
    | jq -r --arg t "${T##*:}" '.Subscriptions[] | [$t, .Protocol,
        (if (.Protocol|test("^(email|email-json|sms)$")) then "(enmascarado)" else (.Endpoint | split(":") | last) end),
        .SubscriptionArn[-8:]] | @tsv' >> "$OUT/c1-subscriptions.tsv"
done
echo "== suscripciones (protocolo, destino sin datos personales)"; cat "$OUT/c1-subscriptions.tsv"
echo listo

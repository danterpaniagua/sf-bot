#!/usr/bin/env bash
# GITIN-2162 - Estancamientos de consumo en PRD_BranchMessages.fifo
# Comandos de solo lectura ejecutados durante la investigación. Cada salida está en data/.
# Reemplazar <profile> por el perfil AWS correspondiente. Fechas en ART (UTC-3).

D=/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261004_gitin2162-weekend-queue-age-escalation/data

# C1 - Métricas de la cola PRD_BranchMessages.fifo, 72 h, buckets de 5 min (antigüedad, profundidad, enviados, borrados)
for M in ApproximateAgeOfOldestMessage:Maximum ApproximateNumberOfMessagesVisible:Maximum NumberOfMessagesSent:Sum NumberOfMessagesDeleted:Sum; do
  aws cloudwatch get-metric-statistics \
    --namespace AWS/SQS --metric-name "${M%%:*}" \
    --dimensions Name=QueueName,Value=PRD_BranchMessages.fifo \
    --start-time "$(date -u -d '72 hours ago' +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 300 --statistics "${M##*:}" \
    --region us-east-1 --profile <profile> \
    --output json > "$D/sqs_branchmessages_${M%%:*}_72h.json"
done

# C2 - Estado y eventos de los servicios ECS
aws ecs describe-services \
  --cluster smartfran-pedidos-production \
  --services concentrador-service-production-service platform-service-production-service \
  --region us-east-1 --profile <profile> \
  --query 'services[].{name:serviceName,desired:desiredCount,running:runningCount,taskDef:taskDefinition,events:events[*].{t:createdAt,m:message}}' \
  --output json > "$D/ecs_services_events.json"

# C3 - Historial de actividades de Application Auto Scaling (ECS)
aws application-autoscaling describe-scaling-activities \
  --service-namespace ecs \
  --region us-east-1 --profile <profile> \
  --output json > "$D/ecs_scaling_activities.json"

# C4 - CPU y memoria de ambos servicios, 72 h
for S in platform-service-production-service concentrador-service-production-service; do
  for M in CPUUtilization MemoryUtilization; do
    aws cloudwatch get-metric-statistics \
      --namespace AWS/ECS --metric-name "$M" \
      --dimensions Name=ClusterName,Value=smartfran-pedidos-production Name=ServiceName,Value="$S" \
      --start-time "$(date -u -d '72 hours ago' +%Y-%m-%dT%H:%M:%S)" \
      --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
      --period 300 --statistics Average Maximum \
      --region us-east-1 --profile <profile> \
      --output json > "$D/ecs_${S%%-production-service}_${M}_72h.json"
  done
done

# C5 - Atributos de la cola (visibilidad, redrive, FIFO)
aws sqs get-queue-attributes \
  --queue-url https://sqs.us-east-1.amazonaws.com/382381053403/PRD_BranchMessages.fifo \
  --attribute-names All \
  --region us-east-1 --profile <profile> \
  --output json > "$D/sqs_branchmessages_attributes.json"

# C6 - Mensajes enviados a MainDeadLetter.fifo y mensajes en vuelo de PRD_BranchMessages.fifo, 72 h
aws cloudwatch get-metric-statistics \
  --namespace AWS/SQS --metric-name NumberOfMessagesSent \
  --dimensions Name=QueueName,Value=MainDeadLetter.fifo \
  --start-time "$(date -u -d '72 hours ago' +%Y-%m-%dT%H:%M:%S)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
  --period 300 --statistics Sum \
  --region us-east-1 --profile <profile> \
  --output json > "$D/sqs_maindeadletter_NumberOfMessagesSent_72h.json"
aws cloudwatch get-metric-statistics \
  --namespace AWS/SQS --metric-name ApproximateNumberOfMessagesNotVisible \
  --dimensions Name=QueueName,Value=PRD_BranchMessages.fifo \
  --start-time "$(date -u -d '72 hours ago' +%Y-%m-%dT%H:%M:%S)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
  --period 300 --statistics Maximum \
  --region us-east-1 --profile <profile> \
  --output json > "$D/sqs_branchmessages_ApproximateNumberOfMessagesNotVisible_72h.json"

# C7 - Target group de platform-service, definición de tarea :268 y métricas del ALB, 72 h
aws elbv2 describe-target-groups \
  --target-group-arns arn:aws:elasticloadbalancing:us-east-1:382381053403:targetgroup/platform-service-production-tg/8624eae8a791530b \
  --region us-east-1 --profile <profile> \
  --output json > "$D/alb_platform_tg_describe.json"
aws ecs describe-task-definition \
  --task-definition platform-service-production-task:268 \
  --region us-east-1 --profile <profile> \
  --query 'taskDefinition.{rev:revision,registeredAt:registeredAt,cpu:cpu,memory:memory,images:containerDefinitions[*].image}' \
  --output json > "$D/ecs_platform_taskdef_268.json"
for M in TargetResponseTime RequestCount HTTPCode_Target_5XX_Count HealthyHostCount UnHealthyHostCount; do
  case "$M" in
    TargetResponseTime) ST="Average Maximum" ;;
    RequestCount|HTTPCode_Target_5XX_Count) ST="Sum" ;;
    HealthyHostCount) ST="Minimum" ;;
    UnHealthyHostCount) ST="Maximum" ;;
  esac
  aws cloudwatch get-metric-statistics \
    --namespace AWS/ApplicationELB --metric-name "$M" \
    --dimensions Name=LoadBalancer,Value=app/pedidos-concentrador-alb/54b7236209d50ece Name=TargetGroup,Value=targetgroup/platform-service-production-tg/8624eae8a791530b \
    --start-time "$(date -u -d '72 hours ago' +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 300 --statistics $ST \
    --region us-east-1 --profile <profile> \
    --output json > "$D/alb_platform_${M}_72h.json"
done

# C8 - Eventos de triggers de Zabbix desde el jueves 01-10 (todos los hosts)
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
FROM=$(date -d '2026-10-01 16:00 -03' +%s); TILL=$(date +%s)
jq -n --arg k "$ZABBIX_API_KEY" --argjson f "$FROM" --argjson t "$TILL" \
  '{jsonrpc:"2.0",method:"event.get",id:1,auth:$k,params:{source:0,object:0,time_from:$f,time_till:$t,output:["eventid","objectid","clock","value","name","severity","r_eventid","acknowledged"],selectHosts:["host"],selectTags:"extend",sortfield:["clock"],sortorder:"ASC",limit:20000}}' \
| curl -s -H 'Content-Type: application/json-rpc' -d @- "$API" > "$D/zabbix_events_thu1_to_now.json"

# C9 - Segunda extracción: domingo 04-10 15:00 a lunes 05-10 (cola, escalado y CPU/memoria de platform-service)
S="$(date -u -d '2026-10-04 15:00 -03' +%Y-%m-%dT%H:%M:%S)"; E="$(date -u +%Y-%m-%dT%H:%M:%S)"
aws application-autoscaling describe-scaling-activities --service-namespace ecs \
  --region us-east-1 --profile <profile> --output json > "$D/ecs_scaling_activities_oct5.json"
aws ecs describe-services --cluster smartfran-pedidos-production \
  --services platform-service-production-service concentrador-service-production-service \
  --region us-east-1 --profile <profile> \
  --query 'services[].{name:serviceName,desired:desiredCount,running:runningCount,taskDef:taskDefinition,events:events[*].{t:createdAt,m:message}}' \
  --output json > "$D/ecs_services_events_oct5.json"
for M in ApproximateAgeOfOldestMessage:Maximum ApproximateNumberOfMessagesVisible:Maximum NumberOfMessagesSent:Sum NumberOfMessagesDeleted:Sum; do
  aws cloudwatch get-metric-statistics --namespace AWS/SQS --metric-name "${M%%:*}" \
    --dimensions Name=QueueName,Value=PRD_BranchMessages.fifo \
    --start-time "$S" --end-time "$E" --period 300 --statistics "${M##*:}" \
    --region us-east-1 --profile <profile> --output json > "$D/sqs_branchmessages_${M%%:*}_oct4pm_oct5.json"
done
for M in CPUUtilization MemoryUtilization; do
  aws cloudwatch get-metric-statistics --namespace AWS/ECS --metric-name "$M" \
    --dimensions Name=ClusterName,Value=smartfran-pedidos-production Name=ServiceName,Value=platform-service-production-service \
    --start-time "$S" --end-time "$E" --period 300 --statistics Average Maximum \
    --region us-east-1 --profile <profile> --output json > "$D/ecs_platform-service_${M}_oct4pm_oct5.json"
done

# C9 (continuación) - Eventos de Zabbix desde dom 04-10 16:00 y métricas del ALB de platform-service, dom 04-10 15:00 a lun 05-10
FROM=$(date -d '2026-10-04 16:00 -03' +%s); TILL=$(date +%s)
jq -n --arg k "$ZABBIX_API_KEY" --argjson f "$FROM" --argjson t "$TILL" \
  '{jsonrpc:"2.0",method:"event.get",id:1,auth:$k,params:{source:0,object:0,time_from:$f,time_till:$t,output:["eventid","objectid","clock","value","name","severity","r_eventid","acknowledged"],selectHosts:["host"],selectTags:"extend",sortfield:["clock"],sortorder:"ASC",limit:20000}}' \
| curl -s -H 'Content-Type: application/json-rpc' -d @- "$API" > "$D/zabbix_events_sun16_to_now.json"
for M in TargetResponseTime:Average,Maximum RequestCount:Sum UnHealthyHostCount:Maximum; do
  aws cloudwatch get-metric-statistics --namespace AWS/ApplicationELB --metric-name "${M%%:*}" \
    --dimensions Name=LoadBalancer,Value=app/pedidos-concentrador-alb/54b7236209d50ece Name=TargetGroup,Value=targetgroup/platform-service-production-tg/8624eae8a791530b \
    --start-time "$(date -u -d '2026-10-04 15:00 -03' +%Y-%m-%dT%H:%M:%S)" --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 300 --statistics $(echo "${M##*:}" | tr ',' ' ') \
    --region us-east-1 --profile <profile> --output json > "$D/alb_platform_${M%%:*}_oct4pm_oct5.json"
done

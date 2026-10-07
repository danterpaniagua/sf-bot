#!/usr/bin/env bash
# GITIN-1964 — comandos ejecutados durante la investigacion. No ejecutar en bloque.
EVT=/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260829_concentrador-cpu-spikes

# C1 - historial completo de eventos ECS, concentrador-service y platform-service
aws ecs describe-services --cluster smartfran-pedidos-production \
  --services concentrador-service-production-service platform-service-production-service \
  --region us-east-1 --profile <profile> \
  --query 'services[].{name:serviceName,events:events[*].{t:createdAt,m:message}}' \
  > "$EVT/1_ecs_service_events.json"

# C2 - CloudWatch CPUUtilization, concentrador-service (5 min, 2026-08-29 10:00 -03:00 en adelante)
aws cloudwatch get-metric-statistics --namespace AWS/ECS --metric-name CPUUtilization \
  --dimensions Name=ClusterName,Value=smartfran-pedidos-production Name=ServiceName,Value=concentrador-service-production-service \
  --start-time 2026-08-29T13:00:00Z --end-time <momento-de-consulta> --period 300 --statistics Average Maximum \
  --region us-east-1 --profile <profile> > "$EVT/2a_cpu_concentrador.json"

# C2b - CloudWatch CPUUtilization, platform-service (misma ventana, control)
aws cloudwatch get-metric-statistics --namespace AWS/ECS --metric-name CPUUtilization \
  --dimensions Name=ClusterName,Value=smartfran-pedidos-production Name=ServiceName,Value=platform-service-production-service \
  --start-time 2026-08-29T13:00:00Z --end-time <momento-de-consulta> --period 300 --statistics Average Maximum \
  --region us-east-1 --profile <profile> > "$EVT/2b_cpu_platform.json"

# C3 - task definition activo y desired/running count de concentrador-service (pre-mitigacion, :321)
aws ecs describe-services --cluster smartfran-pedidos-production \
  --services concentrador-service-production-service \
  --region us-east-1 --profile <profile> \
  --query 'services[0].{taskDef:taskDefinition,desired:desiredCount,running:runningCount}' \
  > "$EVT/3_concentrador_taskdef.json"

# C4 - cpu/memory del task definition :321 (confirma que sigue en la spec pre-GITIN-1783)
aws ecs describe-task-definition --task-definition concentrador-service-production-task:321 \
  --region us-east-1 --profile <profile> \
  --query 'taskDefinition.{registeredAt:registeredAt,cpu:cpu,memory:memory}' \
  > "$EVT/5_taskdef_321_capacity.json"

# C5 - configuracion de health check del target group de concentrador-service
aws elbv2 describe-target-groups \
  --target-group-arns arn:aws:elasticloadbalancing:us-east-1:382381053403:targetgroup/concetrador-serprod-tg/778da6245ee60c15 \
  --region us-east-1 --profile <profile> \
  --query 'TargetGroups[].{Path:HealthCheckPath,Timeout:HealthCheckTimeoutSeconds,Interval:HealthCheckIntervalSeconds,Unhealthy:UnhealthyThresholdCount,Matcher:Matcher}' \
  > "$EVT/6_tg_healthcheck_config.json"

# C6/C7/C8 - exportacion Graylog (sf-monitoreo.smartfran.com, UI), analizada localmente
#   Query: service:concentrador-service AND category:PERF
#   Rango: 2026-08-29 09:00-20:10 -03:00
#   Export guardado en: 7_graylog_perf_export.csv (55,860 filas)
#   Analisis (volumen por minuto, composicion por URL, distribucion de duration_ms) hecho con un script
#   Python ad-hoc sobre el CSV exportado, no versionado - resultados volcados en investigation.md.

# Mitigacion aplicada - registrada manualmente (no vía CLI), no ejecutada por este script:
#   Nueva revision de task definition concentrador-service-production-task:322 (cpu:1024, memory:2048)
#   Luego:
#   aws ecs update-service --cluster smartfran-pedidos-production \
#     --service concentrador-service-production-service \
#     --task-definition concentrador-service-production-task:322 \
#     --force-new-deployment --region us-east-1 --profile <profile>

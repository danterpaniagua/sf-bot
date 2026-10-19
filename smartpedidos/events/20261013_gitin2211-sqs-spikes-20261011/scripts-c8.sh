#!/usr/bin/env bash
# Event: 20261013_sqs-spikes-20261011
# C8 — Solo lectura contra CloudWatch (us-east-1). Pregunta del alcance: "escalo bien?". Tareas realmente en ejecucion de
#      platform-service-production-service (cluster smartfran-pedidos-production) minuto a minuto del 2026-10-11 21:50 a 22:45
#      locales (UTC-3), junto con la edad del mensaje mas viejo de PRD_BranchMessages.fifo y la CPU del servicio:
#        RunningTaskCount, DesiredTaskCount (ECS/ContainerInsights), CPUUtilization Average y Maximum (AWS/ECS),
#        ApproximateAgeOfOldestMessage Maximum (AWS/SQS).
# Uso:  bash scripts-c8.sh <etiqueta>   (etiqueta nueva por corrida; noclobber)
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
LABEL="${1:?etiqueta}"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261013_sqs-spikes-20261011/data"
C=smartfran-pedidos-production; S=platform-service-production-service
ci() { echo "{\"Id\":\"$1\",\"Label\":\"$1\",\"ReturnData\":true,\"MetricStat\":{\"Period\":60,\"Stat\":\"$3\",\"Metric\":{\"Namespace\":\"$2\",\"MetricName\":\"$4\",\"Dimensions\":[{\"Name\":\"ClusterName\",\"Value\":\"$C\"},{\"Name\":\"ServiceName\",\"Value\":\"$S\"}]}}}"; }
F="$OUT/c8-$LABEL.json"
aws cloudwatch get-metric-data --region us-east-1 --start-time 2026-10-12T00:50:00Z --end-time 2026-10-12T01:45:00Z --metric-data-queries \
"[$(ci running ECS/ContainerInsights Maximum RunningTaskCount),$(ci desired ECS/ContainerInsights Maximum DesiredTaskCount),$(ci cpu_avg AWS/ECS Average CPUUtilization),$(ci cpu_max AWS/ECS Maximum CPUUtilization),{\"Id\":\"age\",\"Label\":\"age\",\"ReturnData\":true,\"MetricStat\":{\"Period\":60,\"Stat\":\"Maximum\",\"Metric\":{\"Namespace\":\"AWS/SQS\",\"MetricName\":\"ApproximateAgeOfOldestMessage\",\"Dimensions\":[{\"Name\":\"QueueName\",\"Value\":\"PRD_BranchMessages.fifo\"}]}}}]" \
--output json > "$F"
echo "mensajes de CloudWatch: $(jq -c '.Messages' "$F"); puntos por serie: $(jq -c '[.MetricDataResults[]|{(.Id):(.Values|length)}]|add' "$F")"
echo "hora_local running desired cpu_avg cpu_max edad_s"
jq -r '[.MetricDataResults[]|{(.Id):([.Timestamps,.Values]|transpose|map({(.[0]):.[1]})|add)}]|add as $m
  | ([$m.running,$m.desired,$m.cpu_avg,$m.cpu_max,$m.age]|map(keys)|add|unique)[] as $t
  | [$t[11:16], ($m.running[$t]//"-"), ($m.desired[$t]//"-"), ($m.cpu_avg[$t]//"-"|if type=="number" then (.*10|round/10) else . end), ($m.cpu_max[$t]//"-"|if type=="number" then (.*10|round/10) else . end), ($m.age[$t]//"-")]|@tsv' "$F" | sort

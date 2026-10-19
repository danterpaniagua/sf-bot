#!/usr/bin/env bash
# Event: 20261014_gitin2222-ecs-reinicios-avisos-sns
# C3 - Solo lectura (AWS, cuenta de SmartPedidos, region us-east-1, cluster smartfran-pedidos-production). Se puede repetir; cada corrida escribe archivos con la hora en el nombre.
#      Motivo: ECS conserva las tareas detenidas solo cerca de una hora, y los mails del topic NO traen stopCode, stoppedReason ni exit code (la plantilla de la regla solo copia hora, estado, task definition).
#      Hay que correrlo lo antes posible despues de un aviso "Status: STOPPED" (el del 2026-10-14 23:48:28Z se pudo haber perdido; C2 corrio 8 minutos despues pero no incluye tareas detenidas).
#      Imprime por tarea detenida: hora de detencion (-03:00), servicio, revision de la task definition, stopCode, stoppedReason, exit code y razon de cada contenedor, y los ultimos 15 eventos de cada servicio.
set -uo pipefail
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/data"
R="us-east-1"; C="smartfran-pedidos-production"; TS=$(date -u +%Y%m%dT%H%M%SZ)
echo "cuenta: $(aws sts get-caller-identity --query Account --output text --region $R) | region $R | $TS"
aws ecs list-tasks --cluster "$C" --desired-status STOPPED --region $R --output json > "$OUT/c3-stopped-list-$TS.json"
N=$(jq '.taskArns|length' "$OUT/c3-stopped-list-$TS.json"); echo "tareas detenidas conservadas: $N"
if [ "$N" -gt 0 ]; then
  # shellcheck disable=SC2046
  aws ecs describe-tasks --cluster "$C" --tasks $(jq -r '.taskArns[:100] | join(" ")' "$OUT/c3-stopped-list-$TS.json") --region $R --output json \
    | jq '[.tasks[] | {group, taskDefinitionArn, createdAt, startedAt, stoppedAt, stopCode, stoppedReason, healthStatus, containers:[.containers[]|{name,exitCode,reason,lastStatus,healthStatus}]}] | sort_by(.stoppedAt)' > "$OUT/c3-stopped-$TS.json"
  echo "== tareas detenidas (stoppedAt | servicio | revision | vivio | stopCode | stoppedReason | contenedores exit/razon)"
  jq -r '.[] | [((.stoppedAt // "-")[0:19]), ((.group // "-")|sub("service:";"")), ((.taskDefinitionArn // "-")|split(":")|last),
        (try ((((.stoppedAt|sub("\\.[0-9]+";"")|sub("[+-][0-9:]+$";"Z")|fromdateiso8601) - (.startedAt // .createdAt|sub("\\.[0-9]+";"")|sub("[+-][0-9:]+$";"Z")|fromdateiso8601))/60|floor|tostring)+" min") catch "?"),
        .stopCode, (.stoppedReason // "-"), ([.containers[]|"\(.exitCode // "-")/\(.reason // "-")"]|join(","))] | @tsv' "$OUT/c3-stopped-$TS.json"
fi
aws ecs describe-services --cluster "$C" --services platform-service-production-service concentrador-service-production-service --region $R --output json \
  | jq '{services:[.services[]|{serviceName,desiredCount,runningCount,pendingCount,taskDefinition,events:[.events[:15][]|{createdAt,message}]}]}' > "$OUT/c3-services-$TS.json"
echo "== ultimos eventos de cada servicio"
jq -r '.services[] | .serviceName as $s | .events[] | [$s, .createdAt[0:19], .message] | @tsv' "$OUT/c3-services-$TS.json"
echo listo

#!/usr/bin/env bash
# Event: 20261014_gitin2222-ecs-reinicios-avisos-sns
# C40 - AWS CLI, SOLO LECTURA (us-east-1). El usuario informa (2026-10-16) que la correccion de Desarrollo ya esta desplegada. El PR #139 (sanitizerLog, commit d4ba5fe) se fusiono en develop a las 09:26 -03 (12:26 UTC).
#       Comprueba en ECS que despliegue esta en ejecucion: del servicio platform-service-production-service del cluster smartfran-pedidos-production muestra los despliegues (revision de la task definition, estado,
#       hora de creacion y de actualizacion, tareas deseadas/en ejecucion/pendientes/fallidas), los ultimos eventos del servicio, la fecha de registro y la etiqueta de la imagen de cada revision involucrada,
#       y las tareas detenidas que ECS conserva (hora de parada, codigo de salida del contenedor y revision) para contrastar antes/despues. No cambia nada.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
C="smartfran-pedidos-production"; SV="platform-service-production-service"; R="us-east-1"
TS=$(date -u +%Y%m%dT%H%M%SZ)
echo "run $TS | $C / $SV | $R"
D=$(aws ecs describe-services --cluster "$C" --services "$SV" --region "$R" --output json)
echo "== despliegues del servicio (estado | revision | desired/running/pending/failed | creado UTC | actualizado UTC | rollout)"
jq -r '.services[0].deployments[]|[.status,(.taskDefinition|split("/")|last),("d"+(.desiredCount|tostring)+"/r"+(.runningCount|tostring)+"/p"+(.pendingCount|tostring)+"/f"+(.failedTasks|tostring)),(.createdAt|tostring),(.updatedAt|tostring),(.rolloutState // "-")]|@tsv' <<<"$D"
echo "== ultimos 12 eventos del servicio"
jq -r '.services[0].events[:12][]|[(.createdAt|tostring),(.message|.[0:150])]|@tsv' <<<"$D"
echo "== revisiones de task definition involucradas (revision | registrada UTC | etiqueta de imagen)"
for td in $(jq -r '.services[0].deployments[].taskDefinition' <<<"$D"); do
  aws ecs describe-task-definition --task-definition "$td" --region "$R" --query 'taskDefinition.{rev:revision,reg:registeredAt,img:containerDefinitions[0].image}' --output json \
   | jq -r '[(.rev|tostring),(.reg|tostring),(.img|split(":")|last)]|@tsv'
done
echo "== tareas detenidas que ECS conserva (parada UTC | revision | codigo de salida | stopCode)"
ARNS=$(aws ecs list-tasks --cluster "$C" --service-name "$SV" --desired-status STOPPED --region "$R" --query 'taskArns' --output json 2>/dev/null || echo '[]')
if [ "$(jq length <<<"$ARNS")" -gt 0 ]; then
  aws ecs describe-tasks --cluster "$C" --tasks $(jq -r '.[]' <<<"$ARNS") --region "$R" --output json \
   | jq -r '.tasks|sort_by(.stoppedAt)|.[]|[(.stoppedAt|tostring),(.taskDefinitionArn|split("/")|last),("exit="+([.containers[]|.exitCode // "-"]|map(tostring)|join(","))),.stopCode]|@tsv'
else
  echo "(ECS no conserva tareas detenidas de este servicio en este momento)"
fi

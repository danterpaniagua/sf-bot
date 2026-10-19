#!/usr/bin/env bash
# Event: 20261014_gitin2222-ecs-reinicios-avisos-sns
# C4 - Regla EventBridge ECS-Task-ECSTaskStateChange-Team (topic SNS-SmartPedidosTeam-PROD, cuenta 382381053403, us-east-1).
#      Cambio: avisar solo cuando una tarea queda STOPPED y agregar al mail el motivo (servicio, stopCode, stoppedReason, hora, contenedores con exitCode).
#      Modos:  dry (por defecto, SOLO LECTURA)  -> guardas + prueba del patron nuevo con eventos de ejemplo (test-event-pattern) + imprime lo que cambiaria
#              apply (CAMBIA ESTADO)             -> snapshot de la regla y del destino, put-rule con el patron nuevo, put-targets con la plantilla nueva, verificacion
#              rollback <carpeta c4-run-...> (CAMBIA ESTADO) -> restaura el patron y el destino desde el snapshot de esa carpeta
#      No toca la otra regla duplicada (ECS-Task-Definition-Version-Created, topic Alertas-EventBridge-PROD): es otra decision.
#      Plantilla v2 (2026-10-14): el mail trae el nombre y el exitCode del primer contenedor (no el arreglo completo de contenedores, que incluye ARN, digest de imagen e IP privada).
#      Hipotesis no verificada: que EventBridge deje la linea en blanco (y no falle el envio) cuando falta exitCode, por ejemplo si el contenedor nunca arranco; se confirma con el primer aviso STOPPED real despues de aplicar. Rollback disponible.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
MODE="${1:-dry}"; SNAP="${2:-}"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/data"
R="us-east-1"; RULE="ECS-Task-ECSTaskStateChange-Team"; TOPIC="SNS-SmartPedidosTeam-PROD"; CLUSTER_ARN="arn:aws:ecs:us-east-1:382381053403:cluster/smartfran-pedidos-production"
TS=$(date -u +%Y%m%dT%H%M%SZ); RUN="$OUT/c4-run-$TS"
echo "cuenta: $(aws sts get-caller-identity --query Account --output text --region $R) | region $R | modo=$MODE | $TS"
[ "$(aws sts get-caller-identity --query Account --output text --region $R)" = "382381053403" ] || { echo "GUARDA: la cuenta no es 382381053403"; exit 1; }

if [ "$MODE" = "rollback" ]; then
  [ -f "$SNAP/before-rule.json" ] && [ -f "$SNAP/before-targets.json" ] || { echo "uso: $0 rollback <carpeta c4-run-...> (falta before-rule.json / before-targets.json)"; exit 1; }
  DESC=$(jq -r '.Description // empty' "$SNAP/before-rule.json")
  aws events put-rule --name "$RULE" --event-pattern "$(jq -r '.EventPattern' "$SNAP/before-rule.json")" --state "$(jq -r '.State' "$SNAP/before-rule.json")" ${DESC:+--description "$DESC"} --region $R --output json
  aws events put-targets --rule "$RULE" --targets "$(jq -c '.Targets' "$SNAP/before-targets.json")" --region $R --output json | tee /dev/null
  echo "rollback aplicado desde $SNAP"; exit 0
fi

mkdir -p "$RUN"
aws events describe-rule --name "$RULE" --region $R --output json > "$RUN/before-rule.json"
aws events list-targets-by-rule --rule "$RULE" --region $R --output json > "$RUN/before-targets.json"
echo "snapshot en $RUN"

# --- guardas sobre el estado actual
jq -e '.State=="ENABLED"' "$RUN/before-rule.json" >/dev/null || { echo "GUARDA: la regla no esta ENABLED"; exit 1; }
CUR=$(jq -c '.EventPattern|fromjson' "$RUN/before-rule.json")
ALREADY=0   # 1 = el patron ya filtra STOPPED (estado de una aplicacion previa); entonces solo se compara/actualiza la plantilla
if echo "$CUR" | jq -e '.detail.lastStatus==["STOPPED"]' >/dev/null; then ALREADY=1; echo "AVISO: el patron ya filtra lastStatus STOPPED (aplicacion previa); se compara la plantilla."; fi
if [ "$ALREADY" = 0 ]; then
  echo "$CUR" | jq -e '.["detail-type"]==["ECS Task State Change"] and .source==["aws.ecs"] and (.detail|has("lastStatus")|not)' >/dev/null || { echo "GUARDA: el patron actual no es el esperado: $CUR"; exit 1; }
else
  echo "$CUR" | jq -e '.["detail-type"]==["ECS Task State Change"] and .source==["aws.ecs"]' >/dev/null || { echo "GUARDA: el patron actual no es el esperado: $CUR"; exit 1; }
fi
jq -e '(.Targets|length)==1 and (.Targets[0].Arn|endswith(":'"$TOPIC"'"))' "$RUN/before-targets.json" >/dev/null || { echo "GUARDA: la regla no tiene exactamente un destino y ese destino no es $TOPIC"; exit 1; }

# --- patron y plantilla nuevos
NEWPAT=$(echo "$CUR" | jq -c '.detail.lastStatus=["STOPPED"]')
read -r -d '' TPL <<'EOT' || true
"A las <timestamp> se detuvo una tarea (<detail_type>) en el cluster <cluster>"
""
"Servicio: <group>"
"Status: <lastStatus>"
"Detenida: <stoppedAt>"
"Motivo (stopCode): <stopCode>"
"Detalle (stoppedReason): <stoppedReason>"
"Task Definition: <taskDefinitionArn>"
"Contenedor: <containerName> | exitCode: <exitCode>"
EOT
IT=$(jq -n --arg tpl "$TPL" '{InputPathsMap:{cluster:"$.detail.clusterArn", group:"$.detail.group", lastStatus:"$.detail.lastStatus", stoppedAt:"$.detail.stoppedAt", stopCode:"$.detail.stopCode", stoppedReason:"$.detail.stoppedReason", taskDefinitionArn:"$.detail.taskDefinitionArn", containerName:"$.detail.containers[0].name", exitCode:"$.detail.containers[0].exitCode", detail_type:"$.detail-type", timestamp:"$.time"}, InputTemplate:$tpl}')
if [ "$ALREADY" = 1 ] && [ "$(jq -S -c '.Targets[0].InputTransformer' "$RUN/before-targets.json")" = "$(echo "$IT" | jq -S -c .)" ]; then echo "YA APLICADO: el patron filtra STOPPED y la plantilla ya es la v2. No se hace nada."; exit 0; fi
NEWTARGETS=$(jq -c --argjson it "$IT" '.Targets | map(with_entries(select(.value != null)) | .InputTransformer = $it)' "$RUN/before-targets.json")
echo "$NEWPAT" > "$RUN/new-pattern.json"; echo "$NEWTARGETS" | jq . > "$RUN/new-targets.json"

# --- prueba del patron nuevo (solo lectura): STOPPED del cluster -> true; RUNNING -> false; STOPPED de otro cluster -> false
EVT() { jq -nc --arg st "$1" --arg cl "$2" '{version:"0",id:"11111111-2222-3333-4444-555555555555",account:"382381053403",source:"aws.ecs",time:"2026-10-14T23:48:28Z",region:"us-east-1",resources:["arn:aws:ecs:us-east-1:382381053403:task/x/y"],"detail-type":"ECS Task State Change",detail:{clusterArn:$cl,lastStatus:$st,desiredStatus:$st,group:"service:platform-service-production-service",stopCode:"EssentialContainerExited",stoppedReason:"ejemplo",taskDefinitionArn:"arn:aws:ecs:us-east-1:382381053403:task-definition/platform-service-production-task:272",containers:[{name:"c",exitCode:1}]}}'; }
T1=$(aws events test-event-pattern --event-pattern "$NEWPAT" --event "$(EVT STOPPED "$CLUSTER_ARN")" --region $R --query Result --output text)
T2=$(aws events test-event-pattern --event-pattern "$NEWPAT" --event "$(EVT RUNNING "$CLUSTER_ARN")" --region $R --query Result --output text)
T3=$(aws events test-event-pattern --event-pattern "$NEWPAT" --event "$(EVT STOPPED "arn:aws:ecs:us-east-1:382381053403:cluster/otro")" --region $R --query Result --output text)
echo "prueba del patron: STOPPED del cluster=$T1 (esperado True) | RUNNING=$T2 (esperado False) | STOPPED de otro cluster=$T3 (esperado False)"
[ "$T1" = "True" ] && [ "$T2" = "False" ] && [ "$T3" = "False" ] || { echo "GUARDA: la prueba del patron no dio lo esperado"; exit 1; }

echo "== patron actual";  echo "$CUR"
echo "== patron nuevo";   echo "$NEWPAT"
echo "== plantilla nueva"; echo "$TPL"
if [ "$MODE" != "apply" ]; then echo "DRY: no se cambio nada. Para aplicar: $0 apply"; exit 0; fi

# --- apply (cambia estado)
DESC=$(jq -r '.Description // empty' "$RUN/before-rule.json")
aws events put-rule --name "$RULE" --event-pattern "$NEWPAT" --state ENABLED ${DESC:+--description "$DESC"} --region $R --output json > "$RUN/put-rule.json"
aws events put-targets --rule "$RULE" --targets "$NEWTARGETS" --region $R --output json > "$RUN/put-targets.json"
[ "$(jq '.FailedEntryCount' "$RUN/put-targets.json")" = "0" ] || { echo "FALLO put-targets: $(cat "$RUN/put-targets.json")"; exit 1; }
aws events describe-rule --name "$RULE" --region $R --output json > "$RUN/after-rule.json"
aws events list-targets-by-rule --rule "$RULE" --region $R --output json > "$RUN/after-targets.json"
echo "== despues: patron";  jq -c '.EventPattern|fromjson' "$RUN/after-rule.json"
echo "== despues: destino y campos de la plantilla"; jq -c '.Targets[]|{Arn,paths:(.InputTransformer.InputPathsMap|keys)}' "$RUN/after-targets.json"
echo "aplicado. Rollback: $0 rollback $RUN"

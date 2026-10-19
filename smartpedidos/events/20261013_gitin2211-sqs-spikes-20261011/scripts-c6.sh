#!/usr/bin/env bash
# Event: 20261013_sqs-spikes-20261011
# C6 — Solo lectura (region us-east-1). Completa C5: como se dispara IntegrationLambdaEcsTaskProd y que hace.
#      1) Politica de recursos de la Lambda (quien puede invocarla) y suscripciones SNS del topic Pedidos_Production
#      2) Historial de estados de las alarmas sendMailOldestMessage y sendMailOldestMessage100 del 2026-10-11 21:30 a 22:30 locales
#      3) Invocaciones de la Lambda en 10 dias (periodo 900 s; C5 fallo por el limite de 1440 puntos)
#      4) Codigo de la Lambda: se descarga el zip en un directorio nuevo y vacio (dato no confiable: solo se lee, no se ejecuta)
# Uso:  bash scripts-c6.sh <etiqueta>   (etiqueta nueva por corrida; noclobber)
set -uo pipefail
LABEL="${1:?etiqueta}"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261013_sqs-spikes-20261011/data"
R=us-east-1; FN=IntegrationLambdaEcsTaskProd
TOPIC="arn:aws:sns:us-east-1:382381053403:Pedidos_Production"

echo "== 1) politica y suscripciones"
aws lambda get-policy --region $R --function-name $FN --output json 2> "$OUT/c6-$LABEL-policy.err" \
  | jq '.Policy|fromjson|.Statement[]|{Sid,Effect,Principal,Action,Condition,Resource}' > "$OUT/c6-$LABEL-lambda-policy.json" || true
echo "sentencias de la politica: $(jq -s 'length' "$OUT/c6-$LABEL-lambda-policy.json" 2>/dev/null)"; jq -c '{Principal,Condition}' "$OUT/c6-$LABEL-lambda-policy.json" 2>/dev/null
aws sns list-subscriptions-by-topic --region $R --topic-arn "$TOPIC" --output json 2> "$OUT/c6-$LABEL-sns.err" \
  | jq '[.Subscriptions[]|{Protocol,Endpoint:(if (.Protocol=="email" or .Protocol=="sms") then "(destino omitido)" else .Endpoint end),SubscriptionArn:(.SubscriptionArn|split(":")|last)}]' > "$OUT/c6-$LABEL-sns-subscriptions.json" || true
echo "suscripciones al topic (protocolo, destino salvo correos):"; jq -r '.[]|"  \(.Protocol) \(.Endpoint)"' "$OUT/c6-$LABEL-sns-subscriptions.json" 2>/dev/null

echo "== 2) historial de alarmas"
for a in sendMailOldestMessage sendMailOldestMessage100; do
  aws cloudwatch describe-alarm-history --region $R --alarm-name $a --history-item-type StateUpdate \
    --start-date "$(date -u -d '2026-10-11 21:30 -0300' +%FT%TZ)" --end-date "$(date -u -d '2026-10-11 22:30 -0300' +%FT%TZ)" --output json > "$OUT/c6-$LABEL-history-$a.json"
  echo "$a:"; jq -r '.AlarmHistoryItems|sort_by(.Timestamp)[]|"  \(.Timestamp) \(.HistorySummary)"' "$OUT/c6-$LABEL-history-$a.json"
done

echo "== 3) invocaciones 10 dias (UTC, buckets de 15 min con invocaciones)"
aws cloudwatch get-metric-statistics --region $R --namespace AWS/Lambda --metric-name Invocations --dimensions Name=FunctionName,Value=$FN \
  --start-time 2026-10-03T03:00:00Z --end-time 2026-10-13T03:00:00Z --period 900 --statistics Sum --output json > "$OUT/c6-$LABEL-Invocations-10d.json"
jq -r '.Datapoints|sort_by(.Timestamp)[]|select(.Sum>0)|"  \(.Timestamp) \(.Sum)"' "$OUT/c6-$LABEL-Invocations-10d.json"

echo "== 4) codigo"
CODE="$OUT/c6-$LABEL-lambda-code"; mkdir "$CODE"
URL=$(aws lambda get-function --region $R --function-name $FN --query 'Code.Location' --output text)
curl -sS -o "$CODE/code.zip" "$URL" && (cd "$CODE" && unzip -o -q code.zip && ls -la)
echo "listo (el codigo queda en $CODE; no ejecutarlo)"

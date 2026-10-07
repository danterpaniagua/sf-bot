#!/usr/bin/env bash
# Evento: 20261002_5713-no-new-orders-sqs  (GITIN-2161)
# Registro de los comandos ejecutados (solo lectura). Los alias sfmongosh / sfawscli son del operador y
# solo funcionan en una shell interactiva; la salida real de cada comando está en data/.
# Los scripts .js referenciados están en esta misma carpeta.

EV=/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261002_5713-no-new-orders-sqs

# C1 — Atributos de la cola 5713 (el perfil/alias de AWS lo aplicó el operador)
sfawscli sqs get-queue-attributes --region us-east-1 \
  --queue-url "https://sqs.us-east-1.amazonaws.com/382381053403/5713PRD_PlatformMessages.fifo" \
  --attribute-names All --output json > $EV/data/sqs_queue_attrs_5713.json 2> $EV/data/sqs_queue_attrs_5713.err

# C2 — CloudWatch: mensajes enviados / recibidos por la cola 5713, 48 h, buckets de 1 h
for M in NumberOfMessagesSent NumberOfMessagesReceived; do
  sfawscli cloudwatch get-metric-statistics --region us-east-1 \
    --namespace AWS/SQS --metric-name $M \
    --dimensions Name=QueueName,Value=5713PRD_PlatformMessages.fifo \
    --start-time "$(date -u -d '48 hours ago' +%Y-%m-%dT%H:%M:%S)" --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 3600 --statistics Sum --output json > $EV/data/sqs_${M}_5713_48h.json 2> $EV/data/sqs_${M}_5713_48h.err
done

# C3 — Sucursal 5713 (campos no secretos) y news de los últimos 7 días
sfmongosh --quiet --file $EV/mongo_branch_5713.js > $EV/data/mongo_branch_5713.json 2> $EV/data/mongo_branch_5713.err

# C4 — Plataformas de la sucursal 5713, pedidos de los últimos 14 días y últimos pedidos
sfmongosh --quiet --file $EV/mongo_orders_5713.js > $EV/data/mongo_orders_5713.json 2> $EV/data/mongo_orders_5713.err

# C5 — Línea de tiempo del pedido PediGrido PENDING (01/10) vs uno RECHAZADO (29/09) y dead letters
sfmongosh --quiet --file $EV/mongo_order_trace_5713.js > $EV/data/mongo_order_trace_5713.json 2> $EV/data/mongo_order_trace_5713.err

# C6 — Comparación de configuración de la sucursal 5713 con la sucursal de referencia 3013
sfmongosh --quiet --file $EV/mongo_compare_branch.js > $EV/data/mongo_compare_branch.json 2> $EV/data/mongo_compare_branch.err

# C7 — Atributos de la cola 3013 y diferencia contra la 5713 (atributos y política normalizados)
sfawscli sqs get-queue-attributes --region us-east-1 \
  --queue-url "https://sqs.us-east-1.amazonaws.com/382381053403/3013PRD_PlatformMessages.fifo" \
  --attribute-names All --output json > $EV/data/sqs_queue_attrs_3013.json 2> $EV/data/sqs_queue_attrs_3013.err
norm() { jq -S '.Attributes | del(.QueueArn,.CreatedTimestamp,.LastModifiedTimestamp,.ApproximateNumberOfMessages,.ApproximateNumberOfMessagesNotVisible,.ApproximateNumberOfMessagesDelayed) | .Policy |= (fromjson | tojson)' "$1" | sed "s/$2/BRANCH/g"; }
diff <(norm $EV/data/sqs_queue_attrs_5713.json 5713) <(norm $EV/data/sqs_queue_attrs_3013.json 3013) > $EV/data/sqs_queue_attrs_diff_3013.txt

# C8 — Existencia de las colas de otras sucursales de referencia
for B in 3013 4703 4616 3254 3640 5454; do
  echo "== $B"; sfawscli sqs get-queue-url --region us-east-1 --queue-name "${B}PRD_PlatformMessages.fifo" --output json 2>&1
done > $EV/data/sqs_reference_candidates.txt

# C9 — Cola de rechazo por sucursal cerrada, indicadores de apertura y trazas de las news de 5713
sfmongosh --quiet --file $EV/mongo_closed_path_5713.js > $EV/data/mongo_closed_path_5713.json 2> $EV/data/mongo_closed_path_5713.err

# C10 — Control: existencia de la colección de rechazo y comparación de pedidos PediGrido 5713 vs 3013
sfmongosh --quiet --file $EV/mongo_control_pedigrido.js > $EV/data/mongo_control_pedigrido.json 2> $EV/data/mongo_control_pedigrido.err

# C11 — Versión y fecha de instalación del agente en 5713 y 3013
sfmongosh --quiet --file $EV/mongo_agent_install_5713.js > $EV/data/mongo_agent_install_5713.json 2> $EV/data/mongo_agent_install_5713.err

# C12 — CloudWatch: lecturas vacías (sondeo) de la cola 5713, 14 días
sfawscli cloudwatch get-metric-statistics --region us-east-1 \
  --namespace AWS/SQS --metric-name NumberOfEmptyReceives \
  --dimensions Name=QueueName,Value=5713PRD_PlatformMessages.fifo \
  --start-time "$(date -u -d '14 days ago' +%Y-%m-%dT%H:%M:%S)" --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
  --period 3600 --statistics Sum --output json > $EV/data/sqs_EmptyReceives_5713_14d.json 2> $EV/data/sqs_EmptyReceives_5713_14d.err

# C13 — Pedidos recientes de 5713 y control de flujo de todas las plataformas (ejecutado dos veces: sin sufijo y _b)
sfmongosh --quiet --file $EV/mongo_fresh_5713.js > $EV/data/mongo_fresh_5713.json 2> $EV/data/mongo_fresh_5713.err
sfmongosh --quiet --file $EV/mongo_fresh_5713.js > $EV/data/mongo_fresh_5713_b.json 2> $EV/data/mongo_fresh_5713_b.err

# C14 — Sucursal anterior 5489 (Mongo) y su cola (SQS)
sfmongosh --quiet --file $EV/mongo_old_5489.js > $EV/data/mongo_old_5489.json 2> $EV/data/mongo_old_5489.err
sfawscli sqs get-queue-url --region us-east-1 --queue-name 5489PRD_PlatformMessages.fifo --output json > $EV/data/sqs_url_5489.json 2> $EV/data/sqs_url_5489.err
sfawscli sqs get-queue-attributes --region us-east-1 \
  --queue-url "https://sqs.us-east-1.amazonaws.com/382381053403/5489PRD_PlatformMessages.fifo" \
  --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible CreatedTimestamp \
  --output json > $EV/data/sqs_queue_attrs_5489.json 2> $EV/data/sqs_queue_attrs_5489.err

# C15 — Referencias de plataforma de 5713 contra el número nuevo/anterior (sin imprimir valores; dos ejecuciones: sin sufijo y _b)
sfmongosh --quiet --file $EV/mongo_refs_5713.js > $EV/data/mongo_refs_5713.json 2> $EV/data/mongo_refs_5713.err
sfmongosh --quiet --file $EV/mongo_refs_5713.js > $EV/data/mongo_refs_5713_b.json 2> $EV/data/mongo_refs_5713_b.err

# C16 — Graylog (stack SmartPedidos): rechazos "There is no branch for this order" (3 h y 30 min)
curl -s -u "$SML_GRAYLOG_API_KEY:token" \
  --data-urlencode 'query="There is no branch for this order"' --data-urlencode 'range=10800' --data-urlencode 'limit=100' \
  -G "http://sf-monitoreo.smartfran.com:9000/api/search/universal/relative" -H 'Accept: application/json' \
  > $EV/data/graylog_nobranch_3h.json 2> $EV/data/graylog_nobranch_3h.err
curl -s -u "$SML_GRAYLOG_API_KEY:token" \
  --data-urlencode 'query="There is no branch for this order"' --data-urlencode 'range=1800' --data-urlencode 'limit=100' \
  -G "http://sf-monitoreo.smartfran.com:9000/api/search/universal/relative" -H 'Accept: application/json' \
  > $EV/data/graylog_nobranch_30m_b.json 2> $EV/data/graylog_nobranch_30m_b.err

# C17 — Graylog: mensajes con branchId 5713 en las últimas 6 h (incluye errores de actualización de sucursal)
curl -s -u "$SML_GRAYLOG_API_KEY:token" \
  --data-urlencode 'query=msg_rest_newOrder_branchId:5713 OR msg_rest_body_branchId:5713' --data-urlencode 'range=21600' --data-urlencode 'limit=50' \
  -G "http://sf-monitoreo.smartfran.com:9000/api/search/universal/relative" -H 'Accept: application/json' \
  > $EV/data/graylog_branchfield_5713_6h.json 2> $EV/data/graylog_branchfield_5713_6h.err

# C18 — Últimas news y pedidos de 5713 con sus trazas de estado
sfmongosh --quiet --file $EV/mongo_latest_news_5713.js > $EV/data/mongo_latest_news_5713.json 2> $EV/data/mongo_latest_news_5713.err

# C19 — Resultado de plataforma por traza del pedido PedidosYa 2309501289
sfmongosh --quiet --file $EV/mongo_platformresult_5713.js > $EV/data/mongo_platformresult_5713.json 2> $EV/data/mongo_platformresult_5713.err

# C20 — ¿Existe entrada PediGrido en 5713 y quién retiene la referencia 5713/5489?
sfmongosh --quiet --file $EV/mongo_pedigrido_holders.js > $EV/data/mongo_pedigrido_holders.json 2> $EV/data/mongo_pedigrido_holders.err

# C21 — Re-ejecución de C18 el 05/10 (últimas news y pedidos de 5713)
sfmongosh --quiet --file $EV/mongo_latest_news_5713.js > $EV/data/mongo_latest_news_5713_oct5.json 2> $EV/data/mongo_latest_news_5713_oct5.err

# C22 — Pedidos de 5713 desde el 03/10 00:49 UTC: conteo por plataforma y estado, y trazas de PediGrido y PedidosYa
sfmongosh --quiet --file $EV/mongo_orders_since_oct3_5713.js > $EV/data/mongo_orders_since_oct3_5713.json 2> $EV/data/mongo_orders_since_oct3_5713.err

#!/usr/bin/env bash
# Event: 20260915_functionapp-onboarding
# Onboarding de SFC-FunctionAPP-Linux-Plan-PRO (4 Function Apps + slots stg2)
# al pipeline de Graylog, separacion de streams por app, promocion de
# campos de FunctionAppLogs en el pipeline de Logstash, y verificacion
# posterior (config en vivo + campos promovidos).

# === INVESTIGATION ===

# C1 — terraform-plan-targeted
# Plan acotado a los 5 recursos nuevos (evita el ruido de otros cambios
# pendientes ya presentes en el working tree antes de esta sesion).
terraform plan \
  -target=azurerm_monitor_diagnostic_setting.ticketprocess_pro \
  -target=azurerm_monitor_diagnostic_setting.codegenerator_pro_stg2 \
  -target=azurerm_monitor_diagnostic_setting.scheduledjobs_pro_stg2 \
  -target=azurerm_monitor_diagnostic_setting.poswasmrelay_pro_stg2 \
  -target=azurerm_monitor_diagnostic_setting.ticketprocess_pro_stg2

# C2 — az-function-execution-count
# Confirma invocaciones reales independientes de Graylog/Logstash, para
# descartar "la app esta inactiva" antes de sospechar del pipeline.
az monitor metrics list \
  --resource "/subscriptions/85c76dea-3304-4310-8656-bf21b28e4f4b/resourceGroups/SmartFran.Cloud.PRO/providers/Microsoft.Web/sites/<APP>" \
  --metric FunctionExecutionCount --interval PT1H --aggregation Total \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b --output table

# C3 — az-diagnostic-settings-check
# Nota: devuelve un array plano, NO envuelto en .value como la mayoria de
# los comandos `az ... list`.
az monitor diagnostic-settings list \
  --resource "/subscriptions/85c76dea-3304-4310-8656-bf21b28e4f4b/resourceGroups/SmartFran.Cloud.PRO/providers/Microsoft.Web/sites/<APP>" \
  -o json | jq '.[] | {name, eventHubName, eventHubAuthorizationRuleId, logs}'

# C4 — graylog-search-by-app-category
# Query base para verificar entrega end-to-end. IMPORTANTE: el campo `name`
# en Graylog queda en MAYUSCULAS (viene de resourceId) — una query con
# casing mixto devuelve 0 resultados de forma silenciosa (falso negativo
# real durante esta sesion, ver ops-events.md).
curl -s -G "https://sfcloud-monitoreo.smartfran.com/graylog/api/search/universal/relative" \
  -u "$GRAYLOG_API_KEY:token" -H "Accept: application/json" -H "X-Requested-By: cli" \
  --data-urlencode "query=name:<APP-MAYUSCULAS> AND category:FunctionAppLogs" \
  --data-urlencode "range=86400" --data-urlencode "limit=1" \
  | jq '{total_results, sample: .messages[0].message}'

# === AUDIT ===

# C5 — reference-index-set-pull
# Index sets existentes (Catalog/Orders/Person) usados como plantilla para
# el shape real de `data_tiering`, en vez de adivinarlo.
curl -s "https://sfcloud-monitoreo.smartfran.com/graylog/api/system/indices/index_sets" \
  -u "$GRAYLOG_API_KEY:token" -H "Accept: application/json" -H "X-Requested-By: cli" \
  | jq '.index_sets[] | select(.title | test("Catalog|Orders|Person"))'

# C6 — reference-stream-rules-pull
# Regla real de un stream ya funcionando (Orders), para el shape exacto del
# payload de creacion de streams (wrapper {"entity": {...}}).
curl -s "https://sfcloud-monitoreo.smartfran.com/graylog/api/streams/<STREAM_ID>/rules" \
  -u "$GRAYLOG_API_KEY:token" -H "Accept: application/json" -H "X-Requested-By: cli"

# C7 — ruby-parser-standalone-test
# Validacion del parser Python-dict-repr (para properties de FunctionAppLogs)
# contra 9 mensajes reales capturados, ANTES de tocar el pipeline en vivo.
ruby /tmp/cloud-graylog/full_behavior_test.rb

# === REMEDIATION ===

# ⚠️ C8 — terraform-apply-targeted
# 5 recursos: diagnostic setting de SFC-TicketProcess-PRO (renombrado desde
# TicketProcessAsync) + diagnostic settings de los 4 slots stg2.
terraform apply \
  -target=azurerm_monitor_diagnostic_setting.ticketprocess_pro \
  -target=azurerm_monitor_diagnostic_setting.codegenerator_pro_stg2 \
  -target=azurerm_monitor_diagnostic_setting.scheduledjobs_pro_stg2 \
  -target=azurerm_monitor_diagnostic_setting.poswasmrelay_pro_stg2 \
  -target=azurerm_monitor_diagnostic_setting.ticketprocess_pro_stg2

# ⚠️ C9 — graylog-create-index-set
# POST /system/indices/index_sets NO acepta "default" ni "can_be_default"
# (ambos son campos de solo lectura en el GET) — error descubierto en la
# primera prueba, mensaje de error lista las propiedades validas.
curl -s -X POST "https://sfcloud-monitoreo.smartfran.com/graylog/api/system/indices/index_sets" \
  -u "$GRAYLOG_API_KEY:token" -H "Accept: application/json" -H "Content-Type: application/json" -H "X-Requested-By: cli" \
  --data @indexset-<app>.json

# ⚠️ C10 — graylog-create-stream
# POST /streams requiere el payload envuelto en {"entity": {...}} directo
# (NO {"entity": {"type":..., "data": {...}}} — ese shape fallo con "Null
# title", el reference_path del error confirmo el mapeo correcto).
# Regla: field=name, type=1 (exact match), value=<APP-MAYUSCULAS>,
# remove_matches_from_default_stream=true.
curl -s -X POST "https://sfcloud-monitoreo.smartfran.com/graylog/api/streams" \
  -u "$GRAYLOG_API_KEY:token" -H "Accept: application/json" -H "Content-Type: application/json" -H "X-Requested-By: cli" \
  --data @stream-<app>.json

# ⚠️ C11 — graylog-resume-stream
# Los streams se crean pausados (disabled:true) — no reenrutan nada hasta
# resumirlos explicitamente.
curl -s -X POST "https://sfcloud-monitoreo.smartfran.com/graylog/api/streams/<STREAM_ID>/resume" \
  -u "$GRAYLOG_API_KEY:token" -H "Accept: application/json" -H "X-Requested-By: cli"

# ⚠️ C12 — logstash-pull-live-config
# Copia autoritativa de la config desplegada en la VM — necesaria porque el
# repo estaba desactualizado (le faltaba el fix GITIN-2034, ya aplicado en
# vivo pero nunca sincronizado al repo).
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo -t gadmin@sfcloud-monitoreo.smartfran.com \
  "sudo cat /etc/logstash/conf.d/azure-eventhub-to-graylog.conf" \
  > /tmp/cloud-graylog/live-azure-eventhub-to-graylog.conf

# ⚠️ C13 — logstash-deploy-updated-config
# Copia + verificacion de integridad (sha256) + validacion de sintaxis
# ANTES de reiniciar el servicio. Historial de este archivo incluye 3
# corrupciones de transferencia distintas por 3 mecanismos distintos, de
# ahi el chequeo de hash obligatorio.
scp -P 5689 -i ~/.ssh/sfcloud_monitoreo \
  /tmp/cloud-graylog/live-azure-eventhub-to-graylog.conf \
  gadmin@sfcloud-monitoreo.smartfran.com:~/azure-eventhub-to-graylog.conf
sha256sum /tmp/cloud-graylog/live-azure-eventhub-to-graylog.conf
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com \
  "sha256sum ~/azure-eventhub-to-graylog.conf"
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo -t gadmin@sfcloud-monitoreo.smartfran.com '
  sudo cp ~/azure-eventhub-to-graylog.conf /etc/logstash/conf.d/azure-eventhub-to-graylog.conf &&
  sudo chmod 640 /etc/logstash/conf.d/azure-eventhub-to-graylog.conf &&
  sudo chown root:logstash /etc/logstash/conf.d/azure-eventhub-to-graylog.conf &&
  sudo -u logstash /usr/share/logstash/bin/logstash --path.settings /etc/logstash -t
'

# ⚠️ C14 — logstash-restart-and-monitor
# `logstash -t` solo valida sintaxis, no ejecuta el codigo Ruby de los
# filtros — un incidente previo tuvo -t limpio y el servicio igual entro en
# crash loop tras el restart. Se revisa el contador de restarts
# explicitamente, no solo el status.
sudo systemctl restart logstash
sleep 10
sudo systemctl status logstash --no-pager
sudo systemctl show logstash -p NRestarts

# === VERIFICATION (sesion posterior, 2026-09-15) ===

# C15 — verify-live-config-pull
# Mismo comando que C12, corrido de nuevo despues del despliegue — SOLO
# lectura, no vuelve a desplegar nada. Devuelve secretos reales en texto
# plano (SharedAccessKey/AccountKey) — redactar el archivo de salida
# inmediatamente, nunca dejarlo persistido sin redactar.
EVT="cloud/events/20260915_functionapp-onboarding"
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo -t gadmin@sfcloud-monitoreo.smartfran.com \
  "sudo cat /etc/logstash/conf.d/azure-eventhub-to-graylog.conf" \
  > "${EVT}/data/live-azure-eventhub-to-graylog.conf"

# C16 — verify-config-diff-normalized
# El diff crudo contra la copia del repo muestra el archivo COMPLETO como
# distinto por el CRLF que agrega el -t de SSH — normalizar a LF antes de
# diffear, o el resultado es ilegible/enganoso.
tr -d '\r' < "${EVT}/data/live-azure-eventhub-to-graylog.conf" \
  > "${EVT}/data/live-azure-eventhub-to-graylog.LF.conf"
diff docs/azure-eventhub-to-graylog.conf \
     "${EVT}/data/live-azure-eventhub-to-graylog.LF.conf"

# C17 — verify-fields-per-app
# 1 query por app, category+name (name en MAYUSCULAS, ver H1), rango 6h —
# confirma FunctionName/FunctionInvocationId/FunctionEventName/AppLevel/
# Service/ClientService/message con datos reales, no solo con el harness
# de pruebas previo al despliegue.
for app in SFC-CODEGENERATOR-PRO SFC-SCHEDULEDJOBS-PRO SFC-POSWASMRELAY-PRO SFC-TICKETPROCESS-PRO; do
  curl -s -u "${GRAYLOG_API_KEY}:token" \
    --data-urlencode "query=category:\"FunctionAppLogs\" AND name:\"${app}\"" \
    --data-urlencode 'range=21600' --data-urlencode 'limit=3' \
    --data-urlencode 'fields=timestamp,FunctionName,FunctionInvocationId,FunctionEventName,AppLevel,Service,ClientService,message' \
    -G "https://sfcloud-monitoreo.smartfran.com/graylog/api/search/universal/relative" \
    -H 'Accept: application/json' \
    -o "${EVT}/data/validate_${app}.json"
done

# C18 — verify-functionname-exists-fleet
# Conteo fleet-wide de _exists_:FunctionName, 24h — confirma la promocion
# a escala, no solo en la muestra puntual de C17.
curl -s -u "${GRAYLOG_API_KEY}:token" \
  --data-urlencode 'query=category:"FunctionAppLogs" AND _exists_:FunctionName' \
  --data-urlencode 'range=86400' \
  -G "https://sfcloud-monitoreo.smartfran.com/graylog/api/search/universal/relative" \
  -H 'Accept: application/json' \
  -o "${EVT}/data/exists_functionname_24h.json"

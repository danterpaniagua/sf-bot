#!/usr/bin/env bash
# Event: 20260824_poswasmrelay-pro-graylog (GITIN-1924)
# Commands grouped by phase: Investigation / Audit / Remediation
# ⚠️ ACTION commands are clearly marked — write/state-changing.

# === INVESTIGATION ===

# C1 — Confirmar existencia de SFC-PosWasmRelay-PRO
az functionapp list --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --query "[?contains(name, 'PosWasmRelay')].{Name:name, ResourceGroup:resourceGroup, Kind:kind, State:state}" \
  --output table

# C2 — Confirmar ausencia de Diagnostic Settings previos
az monitor diagnostic-settings list \
  --resource /subscriptions/85c76dea-3304-4310-8656-bf21b28e4f4b/resourceGroups/SmartFran.Cloud.PRO/providers/Microsoft.Web/sites/SFC-PosWasmRelay-PRO \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b

# C3 — Conteo de mensajes Graylog Service:"smartfran-pos-wasm" por Environment (Views Search API, 3 pasos)
BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
SEARCH_ID=$(curl -s -u "${GRAYLOG_API_KEY}:token" \
  -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
  -d '{"queries":[{"id":"q1","query":{"type":"elasticsearch","query_string":"Service:\"smartfran-pos-wasm\""},"timerange":{"type":"relative","range":2592000},"search_types":[{"id":"agg1","type":"pivot","row_groups":[{"type":"values","field":"Environment","limit":20}],"series":[{"type":"count","id":"count()"}],"rollup":true}]}]}' \
  "${BASE}/views/search" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
JOB_ID=$(curl -s -u "${GRAYLOG_API_KEY}:token" -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
  -d '{}' "${BASE}/views/search/${SEARCH_ID}/execute" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
curl -s -i -u "${GRAYLOG_API_KEY}:token" -H "Accept: application/json" "${BASE}/views/search/status/${JOB_ID}"
# OUTPUT (2026-08-24): 39 mensajes Environment:"Production", 7 Environment:"Development" — origen del tráfico "Production" no confirmado (ver H4).

# C4 — Fetch de mensaje completo (todos los campos) por _id
SEARCH_ID=$(curl -s -u "${GRAYLOG_API_KEY}:token" \
  -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
  -d '{"queries":[{"id":"q1","query":{"type":"elasticsearch","query_string":"_id:\"<MESSAGE_ID>\""},"timerange":{"type":"relative","range":2592000},"search_types":[{"id":"msgs1","type":"messages","fields":[],"limit":1}]}]}' \
  "${BASE}/views/search" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
# ... execute + poll status igual que C3

# C5 — SSH: fetch de la configuración real de Logstash desplegada en producción
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com \
  "sudo cat /etc/logstash/conf.d/azure-eventhub-to-graylog.conf" \
  > ~/Documentos/git/cloud-graylog/docs/azure-eventhub-to-graylog.conf

# C6 — Confirmar ASPNETCORE_ENVIRONMENT en SFC-PosWasmRelay-DEV
az functionapp config appsettings list \
  --name SFC-PosWasmRelay-DEV \
  --resource-group SmartFran.Cloud \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --query "[?name=='ASPNETCORE_ENVIRONMENT']" -o table
# OUTPUT: ASPNETCORE_ENVIRONMENT = Development, SlotSetting = False — no explica el tráfico Environment:"Production" observado (ver H4).

# === REMEDIATION ===

# ⚠️ C7 — Terraform plan, acotado al recurso nuevo (Diagnostic Setting)
# (desde cloud-graylog/terraform/)
terraform plan \
  -target=azurerm_monitor_diagnostic_setting.poswasmrelay_pro \
  -target=data.azurerm_linux_function_app.poswasmrelay_pro \
  -out=gitin-1924.tfplan

# ⚠️ C8 — Terraform apply: crea el Diagnostic Setting de SFC-PosWasmRelay-PRO
terraform apply "gitin-1924.tfplan"
# OUTPUT: Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

# ⚠️ C9 — Graylog: creación de 2 Pipeline Rules (enrutamiento por Service+Environment)
curl -s -u "${GRAYLOG_API_KEY}:token" -H "Content-Type: application/json" -H "X-Requested-By: cli" \
  -d '{"title":"GITIN-1924: smartfran-pos-wasm to DEV","description":"Route POS WASM relay traffic (Service+Environment) into the DEV stream, GITIN-1924","source":"rule \"GITIN-1924: smartfran-pos-wasm to DEV\"\nwhen\n  to_string($message.Service) == \"smartfran-pos-wasm\" && to_string($message.Environment) == \"Development\"\nthen\n  route_to_stream(name: \"DEV\");\nend"}' \
  "${BASE}/system/pipelines/rule"
curl -s -u "${GRAYLOG_API_KEY}:token" -H "Content-Type: application/json" -H "X-Requested-By: cli" \
  -d '{"title":"GITIN-1924: smartfran-pos-wasm to PROD-Pos-AppServicePlan","description":"Route POS WASM relay traffic (Service+Environment) into the PROD-Pos-AppServicePlan stream, GITIN-1924","source":"rule \"GITIN-1924: smartfran-pos-wasm to PROD-Pos-AppServicePlan\"\nwhen\n  to_string($message.Service) == \"smartfran-pos-wasm\" && to_string($message.Environment) == \"Production\"\nthen\n  route_to_stream(name: \"PROD-Pos-AppServicePlan\");\nend"}' \
  "${BASE}/system/pipelines/rule"

# ⚠️ C10 — Graylog: creación del Pipeline (stage 0, match either, ambas reglas)
curl -s -u "${GRAYLOG_API_KEY}:token" -H "Content-Type: application/json" -H "X-Requested-By: cli" \
  -d '{"title":"GITIN-1924: POS WASM Service/Environment routing","description":"Routes Service:smartfran-pos-wasm traffic to DEV/PROD-Pos-AppServicePlan by Environment, GITIN-1924","source":"pipeline \"GITIN-1924: POS WASM Service/Environment routing\"\nstage 0 match either\nrule \"GITIN-1924: smartfran-pos-wasm to DEV\"\nrule \"GITIN-1924: smartfran-pos-wasm to PROD-Pos-AppServicePlan\"\nend\n"}' \
  "${BASE}/system/pipelines/pipeline"
# OUTPUT: pipeline id 6a8c612d4814bcaed31a570b

# C11 — Graylog: listar conexiones de pipelines a streams ANTES de modificar (evitar sobrescribir)
curl -s -u "${GRAYLOG_API_KEY}:token" -H "Accept: application/json" "${BASE}/system/pipelines/connections"
# OUTPUT: Default Stream ya tenía 2 pipelines conectados — "Default Routing" (GRAYLOG_IMMUTABLE_SCOPE) y
# "GITIN-1835 Sales CLEF formatting" (DEFAULT). El endpoint rechaza incluir el inmutable en el payload.

# ⚠️ C12 — Graylog: conectar el nuevo pipeline al Default Stream (omitiendo el pipeline inmutable)
curl -s -u "${GRAYLOG_API_KEY}:token" -H "Content-Type: application/json" -H "X-Requested-By: cli" -X POST \
  -d '{"stream_id":"000000000000000000000001","pipeline_ids":["6a7f29c54814bcaed30c7f9b","6a8c612d4814bcaed31a570b"]}' \
  "${BASE}/system/pipelines/connections/to_stream"

# C13 — Verificación: mensaje real posterior a la conexión, ruteado al stream DEV
# (mismo patrón 3 pasos que C3, query_string Service:"smartfran-pos-wasm", fields incluye "streams")
# OUTPUT (2026-08-24 15:28 UTC): streams: ["000000000000000000000001","6a7a1b8a34e7b9a985f43cbc"] — confirmado id = DEV, e indexado en dev__6.

# ⚠️ C14 — Deploy del fix de promoción TraceKey/SourceContext vía patch (NO overwrite de archivo completo)
scp -P 5689 -i ~/.ssh/sfcloud_monitoreo \
  gitin-1924-tracekey.patch gadmin@sfcloud-monitoreo.smartfran.com:/tmp/gitin-1924-tracekey.patch
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com \
  "cd /etc/logstash/conf.d && sudo patch --dry-run -p1 azure-eventhub-to-graylog.conf /tmp/gitin-1924-tracekey.patch"
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com \
  "cd /etc/logstash/conf.d && sudo patch -p1 azure-eventhub-to-graylog.conf /tmp/gitin-1924-tracekey.patch"

# C15 — Validación de sintaxis antes de reiniciar (obligatorio por convención del proyecto)
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com \
  "sudo -u logstash /usr/share/logstash/bin/logstash --path.settings /etc/logstash -t"
# OUTPUT: Configuration OK. Config Validation Result: OK.

# ⚠️ C16 — Reinicio de Logstash (interrumpe brevemente el pipeline compartido de TODOS los servicios onboarded)
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com \
  "sudo systemctl restart logstash"

# C17 — Confirmación post-reinicio
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com \
  "sudo systemctl status logstash --no-pager -l"
# OUTPUT: active (running), arranque limpio a las 15:54:09 UTC.

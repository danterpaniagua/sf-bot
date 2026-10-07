#!/usr/bin/env bash
# Event: 20260826_sfc-function-apps-graylog-onboarding (GITIN-1946)
# Commands grouped by phase: Investigation / Audit / Remediation

# === INVESTIGATION ===

# C1 — confirm-real-app-names-and-state
az functionapp list \
  --resource-group SmartFran.Cloud.PRO \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --query "[?contains(name, 'CodeGenerator') || contains(name, 'ScheduledJobs') || contains(name, 'TicketProcess')].{Name:name, Kind:kind, State:state}" \
  --output table

# C2 — confirm-no-preexisting-diagnostic-settings
for app in SFC-TicketProcessAsync-PRO SFC-CodeGenerator-PRO SFC-ScheduledJobs-PRO; do
  echo "=== $app ==="
  az monitor diagnostic-settings list \
    --resource "/subscriptions/85c76dea-3304-4310-8656-bf21b28e4f4b/resourceGroups/SmartFran.Cloud.PRO/providers/Microsoft.Web/sites/$app" \
    --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
    --output table
done

# === REMEDIATION ===

# ⚠️ C3 — terraform-plan-scoped (writes a plan file, not infrastructure — safe, but included for completeness)
cd cloud-graylog/terraform
terraform plan \
  -target=azurerm_monitor_diagnostic_setting.codegenerator_pro \
  -target=azurerm_monitor_diagnostic_setting.scheduledjobs_pro \
  -target=azurerm_monitor_diagnostic_setting.ticketprocessasync_pro_sfc \
  -out=gitin-1946.tfplan
# Result: Plan: 3 to add, 0 to change, 0 to destroy.

# ⚠️ C4 — terraform-apply (writes real Azure state)
terraform apply "gitin-1946.tfplan"
# Result: Apply complete! Resources: 3 added, 0 changed, 0 destroyed.

# === AUDIT ===

# C5 — confirm-real-invocation-activity (rules out "not invoked yet")
for app in SFC-CodeGenerator-PRO SFC-ScheduledJobs-PRO SFC-TicketProcessAsync-PRO; do
  echo "=== $app — functions & triggers ==="
  az functionapp function list \
    --name "$app" \
    --resource-group SmartFran.Cloud.PRO \
    --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
    --query "[].{Name:name, Trigger:config.bindings[0].type}" \
    --output table

  echo "=== $app — invocation count ==="
  az monitor metrics list \
    --resource "/subscriptions/85c76dea-3304-4310-8656-bf21b28e4f4b/resourceGroups/SmartFran.Cloud.PRO/providers/Microsoft.Web/sites/$app" \
    --metric "FunctionExecutionCount" \
    --interval PT1H \
    --output table
done
# Resultado: 85 (CodeGenerator), 242 (ScheduledJobs), 2 (TicketProcessAsync) ejecuciones reales en la última hora.

# C6 — graylog-search-by-app-name (structured field + broad full-text, both quoted correctly)
curl -s -u "$GRAYLOG_API_KEY:token" \
  -H "Accept: application/json" -H "X-Requested-By: cli" \
  --data-urlencode 'query="SFC-CodeGenerator-PRO" OR "SFC-ScheduledJobs-PRO" OR "SFC-TicketProcessAsync-PRO"' \
  --data-urlencode 'range=86400' \
  --data-urlencode 'fields=timestamp,message,source' \
  --data-urlencode 'limit=20' \
  -G "https://sfcloud-monitoreo.smartfran.com/graylog/api/search/universal/relative"
# Resultado: total_results: 0

# C7 — live-tail-real-output (confirms actual raw shape emitted, independent of Graylog delivery)
timeout 30 az webapp log tail \
  --name SFC-CodeGenerator-PRO \
  --resource-group SmartFran.Cloud.PRO \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b
# Resultado: shape nativo MS_FUNCTION_AZURE_MONITOR_EVENT (CSV + blob pseudo-JSON de comillas simples),
# no el JSON CLEF (Timestamp/Level/MessageTemplate/Properties) documentado en devs-log-structure.md.

# C8 — graylog-search-by-marker-string (confirma si el shape nativo llega a Graylog en cualquier forma)
curl -s -u "$GRAYLOG_API_KEY:token" \
  -H "Accept: application/json" -H "X-Requested-By: cli" \
  --data-urlencode 'query="MS_FUNCTION_AZURE_MONITOR_EVENT"' \
  --data-urlencode 'range=3600' \
  --data-urlencode 'fields=timestamp,message,source' \
  --data-urlencode 'limit=5' \
  -G "https://sfcloud-monitoreo.smartfran.com/graylog/api/search/universal/relative"
# Resultado: total_results: 0, used_indices: []

# C9 — confirm-diagnostic-setting-fully-enabled (descarta config incorrecta)
az monitor diagnostic-settings show \
  --name SmartFran.Cloud.PRO.CodeGenerator_DiagnosticSettings \
  --resource /subscriptions/85c76dea-3304-4310-8656-bf21b28e4f4b/resourceGroups/SmartFran.Cloud.PRO/providers/Microsoft.Web/sites/SFC-CodeGenerator-PRO \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --output json
# Resultado: FunctionAppLogs enabled:true, eventHubName/eventHubAuthorizationRuleId correctos.

# C10 — logstash-error-check (descarta excepciones de parseo)
ssh sfcloud-monitoreo "sudo journalctl -u logstash --since '30 minutes ago' | grep -iE 'error|exception|codegenerator|json' | tail -100"
# Resultado: vacío — sin excepciones, pero inconcluso (Logstash no loguea contenido por mensaje).

# C11 — logstash-pipeline-stats (descarta consumer stancado)
ssh sfcloud-monitoreo "curl -s http://localhost:9600/_node/stats/pipelines?pretty"
# Resultado: input azure_event_hubs activo, events.in creciendo de forma consistente con tráfico real
# conocido (Sales/Business/Orders) — el consumer no está detenido.

# C12 — pull-source-and-inspect-logging-wiring (descarta hipótesis de sink directo a Graylog; halla causa raíz real)
cd cloud/repo/SmartFran.Cloud && git fetch origin && git pull --ff-only origin dev
grep -rn "AddStateLogger\|UseSerilog\|AddSerilog" \
  Source/Common/Functions/SmartFran.Cloud.Functions.Business.CodeGenerator.LiteEditionV2/ \
  Source/Common/Functions/SmartFran.Cloud.Functions.ScheduledJobs/ \
  Source/Common/Functions/SmartFran.Cloud.Functions.Sales.TicketProcessAsync/
# Resultado: 0 coincidencias en las 3 apps. AddBusinessLogger en las 3 resuelve a un
# IBusinessLoggerProvider -> CosmosBusinessLogger (auditoría de negocio, no relacionado con
# logging operacional). El sink Serilog Console JSON CLEF nunca se invoca.

# === AUDIT (continuación, 2026-08-27) ===

# C13 — re-confirm-diagnostic-settings-all-3 (re-verificación posterior al cierre de la fase de infra)
for app in SFC-CodeGenerator-PRO SFC-ScheduledJobs-PRO SFC-TicketProcessAsync-PRO; do
  az monitor diagnostic-settings list \
    --resource "/subscriptions/85c76dea-3304-4310-8656-bf21b28e4f4b/resourceGroups/SmartFran.Cloud.PRO/providers/Microsoft.Web/sites/$app" \
    --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b -o json
done
# Resultado: las 3 apps con FunctionAppLogs enabled:true, mismo eventHubName ("app-logs") y misma
# eventHubAuthorizationRuleId — configuración idéntica y correcta en las tres, sin drift.

#!/usr/bin/env bash
# Event: 20260820_azure-functions-to-graylog (GITIN-1901, padre GITIN-1835)
# Comandos agrupados por fase: Investigación / Despliegue (cloud-graylog repo)
# Los comandos de Terraform corren en ~/Documentos/git/cloud-graylog/terraform/
# Los comandos ⚠️ modifican estado real (Azure)

# === INVESTIGACIÓN ===

# C1 — listar todas las Function Apps de la suscripción Smart IT - Grido
az functionapp list \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --query "[].{name:name, resourceGroup:resourceGroup, state:state, kind:kind, hostNames:defaultHostName}" \
  -o table

# C2 — confirmar que SFC-PosWasmRelay-DEV no tiene código de función desplegado
az functionapp function list \
  --name SFC-PosWasmRelay-DEV \
  --resource-group SmartFran.Cloud \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  -o table
# Resultado: vacío, sin error — confirmado por el usuario como estado esperado
# (Function App provisionada, sin código deployado todavía).

# C3 — obtener el resource ID de SFC-PosWasmRelay-DEV
az functionapp show \
  --name SFC-PosWasmRelay-DEV \
  --resource-group SmartFran.Cloud \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --query id -o tsv
# Resultado: /subscriptions/0190fa7d-4ccf-4e3d-beb1-323b5780bfc8/resourceGroups/
#            SmartFran.Cloud/providers/Microsoft.Web/sites/SFC-PosWasmRelay-DEV

# C4 — intentar confirmar categorías de Diagnostic Settings vía CLI
az monitor diagnostic-settings categories list \
  --resource "/subscriptions/0190fa7d-4ccf-4e3d-beb1-323b5780bfc8/resourceGroups/SmartFran.Cloud/providers/Microsoft.Web/sites/SFC-PosWasmRelay-DEV" \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  -o table
# Resultado: vacío, sin error — mismo quirk de API ya documentado en
# cloud-graylog/terraform/service_bus.tf para Service Bus (categorías no se
# enumeran vía este endpoint para ciertos tipos de recurso). Categoría real
# confirmada en su lugar vía Azure Portal (Function App → Diagnostic settings
# → Add diagnostic setting): "Function Application Logs" (= FunctionAppLogs),
# Site Content Change Audit Logs, Access Audit Logs, IPSecurity Audit logs,
# App Service Authentication logs (preview).

# === DESPLIEGUE (repo cloud-graylog/terraform/) ===

# C5 — verificar drift de disco no relacionado (OpenSearch, redimensionado
# manualmente fuera de Terraform a 512GB) tras corregir main.tf
cd ~/Documentos/git/cloud-graylog/terraform
terraform plan
# Resultado: azurerm_managed_disk.opensearch ya no aparece en el plan — drift
# resuelto. Plan mostró además 16 cambios y 1 recurso nuevo (service_bus_grido)
# no relacionados con este ticket, ya existentes sin commitear en el repo antes
# de esta sesión — no tocados.

# C6 — plan acotado (-target) para el nuevo recurso de este ticket, guardado
terraform plan \
  -target=data.azurerm_linux_function_app.poswasmrelay_dev \
  -target=azurerm_monitor_diagnostic_setting.poswasmrelay_dev \
  -out=gitin-1901.tfplan
# Resultado: Plan: 1 to add, 0 to change, 0 to destroy. Plan guardado en
# gitin-1901.tfplan.

# ⚠️ C7 — aplicar el plan guardado
terraform apply gitin-1901.tfplan
# Resultado: Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

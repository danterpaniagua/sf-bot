#!/usr/bin/env bash
# Event: 20260810_dev-environment-onboarding (GITIN-1794)
# Azure CLI commands run against the DEV RG. Terraform commands are run in a
# SEPARATE repo (~/Documentos/git/cloud-graylog/terraform/) — noted inline.
# Commands are grouped by phase: Investigation / Audit / Remediation
# ⚠️ ACTION commands are clearly marked

# === INVESTIGATION ===

# C1 — Confirmar subscripción activa
az account show --query "{name:name, id:id}" -o table

# C2 — Confirmar existencia del Resource Group
az group show --name "SmartFran.Cloud" --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 -o table

# C3 — Listar App Services del RG
az webapp list --resource-group "SmartFran.Cloud" --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 --query "[].{name:name, state:state, location:location, kind:kind}" -o table

# C4 — Relevar Diagnostic Settings actuales de las 8 apps DEV en alcance
for app in Sales Pos Catalog Platform Admin Person Business Orders; do
  echo "--- SmartFran-Cloud-${app}-DEV ---"
  az monitor diagnostic-settings list \
    --resource "/subscriptions/0190fa7d-4ccf-4e3d-beb1-323b5780bfc8/resourceGroups/SmartFran.Cloud/providers/Microsoft.Web/sites/SmartFran-Cloud-${app}-DEV" \
    --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
    -o table
done

# === AUDIT ===

# C5 — (solo lectura) Obtener la SSH public key real configurada en la VM de
# Graylog en producción — usada para completar var.ssh_public_key sin
# adivinar, evitando un reemplazo forzado de la VM en un terraform apply
# sin -target. No relacionado a las apps DEV.
az vm show \
  --resource-group SmartFran.Cloud.PRO \
  --name smartfran-graylog-pro \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --query "osProfile.linuxConfiguration.ssh.publicKeys[0].keyData" -o tsv

# C6 — terraform plan (repo cloud-graylog, directorio terraform/) — validado,
# no aplicado. Corrido con -target para acotar a los 8 diagnostic settings
# nuevos sin reevaluar VM/red/Event Hub existentes. Resultado: 8 to add, 0 to
# change, 0 to destroy.
#   cd ~/Documentos/git/cloud-graylog/terraform
#   terraform plan -out=tfplan \
#     -target=azurerm_monitor_diagnostic_setting.sales_dev \
#     -target=azurerm_monitor_diagnostic_setting.pos_dev \
#     -target=azurerm_monitor_diagnostic_setting.catalog_dev \
#     -target=azurerm_monitor_diagnostic_setting.platform_dev \
#     -target=azurerm_monitor_diagnostic_setting.admin_dev \
#     -target=azurerm_monitor_diagnostic_setting.person_dev \
#     -target=azurerm_monitor_diagnostic_setting.business_dev \
#     -target=azurerm_monitor_diagnostic_setting.orders_dev

# === REMEDIATION ===

# ⚠️ C7 — terraform apply (repo cloud-graylog, directorio terraform/) —
# pendiente, no ejecutado aún.
#   cd ~/Documentos/git/cloud-graylog/terraform
#   terraform apply tfplan

#!/usr/bin/env bash
# GITIN-2073 - App Service Plans -> Insights (Log Analytics workspace SmartFranCloudPro)
# Bloques de cambio de estado: APLICAR y ROLLBACK. Ejecutar cada uno completo, en subshell, desde una terminal con az logueado.
# Scope: Diagnostic Setting "AllMetrics" en los 9 App Service Plans de SmartFran.Cloud.PRO hacia el workspace SmartFranCloudPro.

# ---------------------------------------------------------------- APLICAR
(
set -euo pipefail
D=/home/dpaniagua/Documentos/git/bots/cloud/events/20260919_gitin2073-appserviceplan-insights-onboarding/data
SUB=85c76dea-3304-4310-8656-bf21b28e4f4b; RG=SmartFran.Cloud.PRO
WS=/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.OperationalInsights/workspaces/SmartFranCloudPro
NAME=plan-allmetrics-to-SmartFranCloudPro
EXPECTED='SFC-FunctionAPP-Linux-Plan-PRO SmartFran-Cloud-Admin-Plan-PRO SmartFran-Cloud-Business-Plan-PRO SmartFran-Cloud-Catalog-PRO SmartFran-Cloud-Orders-Plan-PRO SmartFran-Cloud-Person-Plan-PRO SmartFran-Cloud-Platform-Plan-PRO SmartFran-Cloud-Pos-Plan-PRO SmartFran-Cloud-Sales-Plan-PRO'
mkdir -p "$D/run1-apply"
# BEFORE + guards (nada se modifica si alguna falla)
az monitor log-analytics workspace show --ids "$WS" --subscription "$SUB" -o json > "$D/run1-apply/workspace-BEFORE.json"
az appservice plan list --resource-group "$RG" --subscription "$SUB" -o json > "$D/run1-apply/plans-BEFORE.json"
GOT=$(jq -r '[.[].name]|sort|join(" ")' "$D/run1-apply/plans-BEFORE.json")
[ "$GOT" = "$EXPECTED" ] || { echo "ABORTA: la lista de Plans no coincide con la esperada: $GOT"; exit 1; }
for ID in $(jq -r '.[].id' "$D/run1-apply/plans-BEFORE.json"); do
  N=$(basename "$ID")
  az monitor diagnostic-settings list --resource "$ID" --subscription "$SUB" -o json > "$D/run1-apply/diag-$N-BEFORE.json"
  C=$(jq -r 'if type=="array" then length else (.value|length) end' "$D/run1-apply/diag-$N-BEFORE.json")
  [ "$C" = "0" ] || { echo "ABORTA: $N ya tiene $C Diagnostic Settings"; exit 1; }
done
# APLICAR
for ID in $(jq -r '.[].id' "$D/run1-apply/plans-BEFORE.json"); do
  N=$(basename "$ID")
  az monitor diagnostic-settings create --name "$NAME" --resource "$ID" --workspace "$WS" \
    --metrics '[{"category":"AllMetrics","enabled":true}]' --subscription "$SUB" -o json > "$D/run1-apply/diag-$N-create.json"
done
# AFTER + verificación
for ID in $(jq -r '.[].id' "$D/run1-apply/plans-BEFORE.json"); do
  N=$(basename "$ID")
  az monitor diagnostic-settings list --resource "$ID" --subscription "$SUB" -o json > "$D/run1-apply/diag-$N-AFTER.json"
  jq -e --arg n "$NAME" --arg ws "$WS" 'if type=="array" then . else .value end | map(select(.name==$n and (.workspaceId|ascii_downcase)==($ws|ascii_downcase) and ([.metrics[]|select(.category=="AllMetrics" and .enabled==true)]|length)==1))|length==1' "$D/run1-apply/diag-$N-AFTER.json" >/dev/null \
    && echo "OK  $N" || { echo "FALLA verificación en $N"; exit 1; }
done
)

# ---------------------------------------------------------------- ROLLBACK (solo borra el setting creado arriba, por nombre exacto)
(
set -euo pipefail
D=/home/dpaniagua/Documentos/git/bots/cloud/events/20260919_gitin2073-appserviceplan-insights-onboarding/data
SUB=85c76dea-3304-4310-8656-bf21b28e4f4b; RG=SmartFran.Cloud.PRO
NAME=plan-allmetrics-to-SmartFranCloudPro
mkdir -p "$D/run1-rollback"
az appservice plan list --resource-group "$RG" --subscription "$SUB" -o json > "$D/run1-rollback/plans-pre.json"
for ID in $(jq -r '.[].id' "$D/run1-rollback/plans-pre.json"); do
  N=$(basename "$ID")
  az monitor diagnostic-settings list --resource "$ID" --subscription "$SUB" -o json > "$D/run1-rollback/diag-$N-pre.json"
  if jq -e --arg n "$NAME" 'if type=="array" then . else .value end | map(select(.name==$n))|length==1' "$D/run1-rollback/diag-$N-pre.json" >/dev/null; then
    az monitor diagnostic-settings delete --name "$NAME" --resource "$ID" --subscription "$SUB"
    echo "borrado $NAME en $N"
  else
    echo "sin cambios en $N (no existe $NAME)"
  fi
done
)

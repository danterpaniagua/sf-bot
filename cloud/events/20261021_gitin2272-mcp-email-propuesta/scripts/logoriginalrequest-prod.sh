#!/usr/bin/env bash
# C22 (solo lectura) - valor de la app setting LogOriginalRequest en los App Services PRO de SmartFran Cloud.
# Usa `az webapp config appsettings list` y se queda SOLO con la clave LogOriginalRequest (el resto de las settings tiene secretos y no se imprime).
# Suscripcion SmartIT Cloud, RG SmartFran.Cloud.PRO. Se ejecuta desde la estacion local con `az login` hecho. Requiere az y jq. Salida TSV a stdout.
# Uso: bash logoriginalrequest-prod.sh > data/c22-logoriginalrequest-prod.tsv
set -u
SUB="85c76dea-3304-4310-8656-bf21b28e4f4b"
RG="SmartFran.Cloud.PRO"
echo "# $(date -u +%FT%TZ) | suscripcion $SUB (SmartIT Cloud) | RG $RG | solo la clave LogOriginalRequest"
printf 'app_service\tLogOriginalRequest\n'
for S in Platform Person Business Catalog Sales Orders; do
  APP="SmartFran-Cloud-$S-PRO"
  OUT=$(az webapp config appsettings list --name "$APP" --resource-group "$RG" --subscription "$SUB" -o json 2>/dev/null) || { printf '%s\tERR (az fallo)\n' "$APP"; continue; }
  VAL=$(echo "$OUT" | jq -r '[.[] | select(.name == "LogOriginalRequest") | .value] | if length == 0 then "AUSENTE" else .[0] end' 2>/dev/null) || { printf '%s\tERR (jq fallo)\n' "$APP"; continue; }
  printf '%s\t%s\n' "$APP" "$VAL"
done

#!/usr/bin/env bash
# Event: 20261015_gitin2239-mobile-healthcheck-alerta-zabbix (GITIN-2239)
# C5 - Azure CLI (suscripcion Smart IT - Grido, 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8). Pregunta del usuario: ejecutar la comprobacion con "az" en lugar de entrar a cada servidor.
#      Usa "az vm run-command invoke" para correr scripts/check-healthcheck-file.ps1 (SOLO LECTURA: Test-Path, estado del servicio de Zabbix, lineas AllowKey/DenyKey y la respuesta del agente a vfs.file.exists)
#      en SFCG-MOBI-01, SFCG-MOBI-02, SFCG-WSV2-01 y SFCG-WSV2-02. Corre como SYSTEM, no como la cuenta del servicio de Zabbix: el Test-Path muestra si el archivo existe, no los permisos de esa cuenta.
#      Run Command ejecuta codigo en la VM (puede instalar la extension de Run Command la primera vez); la VM debe estar encendida (WSV2-02 se apaga de 00:00 a 09:00 -03:00).
#      Modos: dry (por defecto, SOLO LECTURA: busca las VMs y su grupo de recursos) | apply (EJECUTA el script en las 4 VMs)
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
MODE="${1:-dry}"
SUB="0190fa7d-4ccf-4e3d-beb1-323b5780bfc8"
DIR="/home/dpaniagua/Documentos/git/bots/loyalty/events/20261015_gitin2239-mobile-healthcheck-alerta-zabbix"
OUT="$DIR/data/c5"; mkdir -p "$OUT"
az vm list --subscription "$SUB" --query "[?starts_with(name,'SFCG-MOBI-0') || starts_with(name,'SFCG-WSV2-0')].{name:name,rg:resourceGroup}" -o json > "$OUT/vms.json"
echo "== VMs encontradas (nombre | grupo de recursos)"; jq -r '.[]|[.name,.rg]|@tsv' "$OUT/vms.json"
[ "$(jq length "$OUT/vms.json")" = "4" ] || { echo "GUARDA: se esperaban 4 VMs (MOBI-01/02, WSV2-01/02)"; exit 1; }
for v in $(jq -r '.[].name' "$OUT/vms.json"); do
  RG=$(jq -r --arg n "$v" '.[]|select(.name==$n)|.rg' "$OUT/vms.json")
  echo "-- $v estado: $(az vm get-instance-view --subscription "$SUB" -g "$RG" -n "$v" --query "instanceView.statuses[?starts_with(code,'PowerState')].displayStatus | [0]" -o tsv)"
done
if [ "$MODE" != "apply" ]; then echo "DRY: no se ejecuto nada en las VMs. Para ejecutar: $0 apply"; exit 0; fi
for v in $(jq -r '.[].name' "$OUT/vms.json"); do
  RG=$(jq -r --arg n "$v" '.[]|select(.name==$n)|.rg' "$OUT/vms.json")
  az vm run-command invoke --subscription "$SUB" -g "$RG" -n "$v" --command-id RunPowerShellScript --scripts @"$DIR/scripts/check-healthcheck-file.ps1" -o json > "$OUT/$v.json"
  echo; echo "================ $v"; jq -r '.value[]|.message' "$OUT/$v.json"
done
echo listo

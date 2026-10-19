#!/usr/bin/env bash
# Event: 20261016_unity-config-consistencia-zabbix
# C1 - Azure CLI (suscripcion Smart IT - Grido, 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8). Pedido del usuario (2026-10-16): comprobar en cada proyecto si existe Config\Unity.config (debe ser el mismo en todas las aplicaciones y proyectos).
#      Usa "az vm run-command invoke" para correr scripts/check-config-files.ps1 (SOLO LECTURA: Test-Path, tamano, fecha y MD5 de Config\Unity.config y de healthcheck.ashx por carpeta SmartLoyalty.*; no imprime contenido)
#      en las VMs de aplicacion de SmartLoyalty: SFCG-WEBS-01/02/03, SFCG-WSV2-01/02, SFCG-WSIT-01, SFCG-MOBI-01/02, SFCG-WSCG-01 y SFCG-TO-01 (nombres segun loyalty/docs/infrastructure.md; las que no existan en Azure se informan).
#      Run Command ejecuta codigo en la VM (puede instalar la extension la primera vez); la VM debe estar encendida (WSV2-02 se apaga de 00:00 a 09:00 -03:00). Corre como SYSTEM: Test-Path muestra si el archivo existe, no los permisos de otra cuenta.
#      Modos: dry (por defecto, SOLO LECTURA: busca las VMs, su grupo de recursos y su estado) | apply (EJECUTA el script en cada VM encendida y deja una tabla resumen)
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
MODE="${1:-dry}"
SUB="0190fa7d-4ccf-4e3d-beb1-323b5780bfc8"
DIR="/home/dpaniagua/Documentos/git/bots/loyalty/events/20261016_unity-config-consistencia-zabbix"
TS=$(date -u +%Y%m%dT%H%M%SZ); OUT="$DIR/data/c1-run-$TS"; mkdir -p "$OUT"
WANT='["SFCG-WEBS-01","SFCG-WEBS-02","SFCG-WEBS-03","SFCG-WSV2-01","SFCG-WSV2-02","SFCG-WSIT-01","SFCG-MOBI-01","SFCG-MOBI-02","SFCG-WSCG-01","SFCG-TO-01"]'
az vm list --subscription "$SUB" --query "[].{name:name,rg:resourceGroup}" -o json | jq -c --argjson w "$WANT" '[.[]|select(.name as $n|$w|index($n))]|sort_by(.name)' > "$OUT/vms.json"
echo "run $TS | VMs de aplicacion (nombre | grupo de recursos | estado)"
for v in $(jq -r '.[].name' "$OUT/vms.json"); do
  RG=$(jq -r --arg n "$v" '.[]|select(.name==$n)|.rg' "$OUT/vms.json")
  ST=$(az vm get-instance-view --subscription "$SUB" -g "$RG" -n "$v" --query "instanceView.statuses[?starts_with(code,'PowerState')].displayStatus | [0]" -o tsv)
  echo "$v | $RG | $ST"; jq --arg n "$v" --arg s "$ST" 'map(if .name==$n then .state=$s else . end)' "$OUT/vms.json" > "$OUT/vms.tmp" && mv "$OUT/vms.tmp" "$OUT/vms.json"
done
echo "no encontradas en Azure: $(jq -r --argjson w "$WANT" '[$w[] as $n|select(([.[].name]|index($n))|not)|$n]|join(", ")' "$OUT/vms.json")"
if [ "$MODE" != "apply" ]; then echo "DRY: no se ejecuto nada en las VMs. Para ejecutar: $0 apply"; exit 0; fi
: > "$OUT/tabla.tsv"
for v in $(jq -r '.[]|select(.state=="VM running")|.name' "$OUT/vms.json"); do
  RG=$(jq -r --arg n "$v" '.[]|select(.name==$n)|.rg' "$OUT/vms.json")
  az vm run-command invoke --subscription "$SUB" -g "$RG" -n "$v" --command-id RunPowerShellScript --scripts @"$DIR/scripts/check-config-files.ps1" -o json > "$OUT/$v.json"
  jq -r '.value[]|.message' "$OUT/$v.json" > "$OUT/$v.txt"
  echo; echo "================ $v"; cat "$OUT/$v.txt"
  awk -F'\t' 'NF>=8 && $1!="Servidor"' "$OUT/$v.txt" >> "$OUT/tabla.tsv"
done
echo; echo "== tabla (Servidor | Carpeta | Unity.config | Tamano | Escrito UTC | MD5 | healthcheck.ashx | MD5 hc | otros)"
cat "$OUT/tabla.tsv"
echo; echo "== valores distintos de MD5 de Unity.config (cantidad de archivos)"; awk -F'\t' '$3=="True"{print $6}' "$OUT/tabla.tsv" | sort | uniq -c
echo "== carpetas SIN Config\\Unity.config"; awk -F'\t' '$3!="True"{print $1" "$2}' "$OUT/tabla.tsv"
echo listo

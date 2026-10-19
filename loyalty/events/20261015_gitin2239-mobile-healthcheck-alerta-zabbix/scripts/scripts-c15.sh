#!/usr/bin/env bash
# Event: 20261015_gitin2239-mobile-healthcheck-alerta-zabbix (GITIN-2239)
# C15 - Azure CLI (suscripcion Smart IT - Grido, 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8). Pregunta del usuario (2026-10-16): copiar healthcheck.ashx de SFCG-WEBS-02 a SFCG-WEBS-01 (el de WEBS-01 tiene otro MD5 que el de WEBS-02/03, C1 de Unity.config).
#      ANTES de copiar nada: este script compara los tres archivos SIN imprimir su contenido, con "az vm run-command invoke" corriendo scripts/check-healthcheck-diff.ps1 (SOLO LECTURA) en SFCG-WEBS-01/02/03.
#      Muestra para cada servidor tamano, fecha, MD5, BOM, saltos de linea y MD5 normalizado (para saber si la diferencia es solo de formato), y compara linea a linea WEBS-01 contra WEBS-02 por el largo y el MD5 corto de cada linea.
#      Modos: dry (por defecto, SOLO LECTURA: busca las VMs y su estado) | apply (EJECUTA el script de solo lectura en las 3 VMs)
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
MODE="${1:-dry}"
SUB="0190fa7d-4ccf-4e3d-beb1-323b5780bfc8"
DIR="/home/dpaniagua/Documentos/git/bots/loyalty/events/20261015_gitin2239-mobile-healthcheck-alerta-zabbix"
TS=$(date -u +%Y%m%dT%H%M%SZ); OUT="$DIR/data/c15-run-$TS"; mkdir -p "$OUT"
az vm list --subscription "$SUB" --query "[?starts_with(name,'SFCG-WEBS-0')].{name:name,rg:resourceGroup}" -o json | jq -c 'sort_by(.name)' > "$OUT/vms.json"
echo "run $TS | VMs (nombre | grupo | estado)"
for v in $(jq -r '.[].name' "$OUT/vms.json"); do
  RG=$(jq -r --arg n "$v" '.[]|select(.name==$n)|.rg' "$OUT/vms.json")
  echo "$v | $RG | $(az vm get-instance-view --subscription "$SUB" -g "$RG" -n "$v" --query "instanceView.statuses[?starts_with(code,'PowerState')].displayStatus | [0]" -o tsv)"
done
[ "$(jq length "$OUT/vms.json")" = "3" ] || { echo "GUARDA: se esperaban 3 VMs (SFCG-WEBS-01/02/03)"; exit 1; }
if [ "$MODE" != "apply" ]; then echo "DRY: no se ejecuto nada en las VMs. Para ejecutar: $0 apply"; exit 0; fi
for v in $(jq -r '.[].name' "$OUT/vms.json"); do
  RG=$(jq -r --arg n "$v" '.[]|select(.name==$n)|.rg' "$OUT/vms.json")
  az vm run-command invoke --subscription "$SUB" -g "$RG" -n "$v" --command-id RunPowerShellScript --scripts @"$DIR/scripts/check-healthcheck-diff.ps1" -o json > "$OUT/$v.json"
  jq -r '.value[]|.message' "$OUT/$v.json" > "$OUT/$v.txt"
  echo; echo "================ $v"; sed -n '1,/^--- por linea/p' "$OUT/$v.txt"
done
echo; echo "================ comparacion linea a linea WEBS-01 vs WEBS-02 (n | largo | md5 corto)"
lines() { sed -n '/^--- por linea/,$p' "$OUT/$1.txt" | tail -n +2 | tr -d '\r'; }
diff <(lines SFCG-WEBS-01) <(lines SFCG-WEBS-02) > "$OUT/diff-01-02.txt" || true
if [ -s "$OUT/diff-01-02.txt" ]; then echo "lineas distintas (< = WEBS-01, > = WEBS-02):"; cat "$OUT/diff-01-02.txt"; else echo "sin diferencias por linea (la diferencia, si existe, es de formato: BOM o saltos de linea)"; fi
echo "== WEBS-02 vs WEBS-03"; diff <(lines SFCG-WEBS-02) <(lines SFCG-WEBS-03) > "$OUT/diff-02-03.txt" && echo "iguales linea a linea" || cat "$OUT/diff-02-03.txt"
echo listo

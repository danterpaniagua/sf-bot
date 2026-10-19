#!/usr/bin/env bash
# Event: 20261015_gitin2228-graylog-nvme0n3-latencia-disco
# C3 - SOLO LECTURA (az CLI). Disco de datos de OpenSearch de la VM de Graylog: SKU, tamano, IOPS/MBps maximos y metricas del disco/VM en 2026-10-15 06:00 a 18:30 UTC (cubre todos los episodios del dia; la alerta informada es 11:33 UTC).
#      Parametros: SUB (suscripcion de Cloud/Graylog), RG (grupo de recursos) y VM (nombre) se definen abajo; el mapeo VM <-> nvme0n3 es una inferencia (GITIN-2209), la LUN se confirma con C1 (lsblk) y con el campo lun de los discos de la VM.
#      Salida: data/c3/.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
SUB="85c76dea-3304-4310-8656-bf21b28e4f4b"; VM="smartfran-graylog-pro"   # cloud/docs/infrastructure.md: suscripcion SmartIT Cloud y VM de Graylog (eastus2); el mapeo con nvme0n3 sigue siendo una inferencia
RG=$(az vm list --subscription "$SUB" --query "[?name=='$VM'].resourceGroup | [0]" -o tsv); : "${RG:?no se encontro la VM $VM en la suscripcion}"; echo "RG=$RG VM=$VM"
OUT="/home/dpaniagua/Documentos/git/bots/cloud/events/20261015_gitin2228-graylog-nvme0n3-latencia-disco/data/c3"
mkdir -p "$OUT"
az vm show --subscription "$SUB" -g "$RG" -n "$VM" --query "{size:hardwareProfile.vmSize, os:storageProfile.osDisk.name, data:storageProfile.dataDisks[].{name:name,lun:lun,gb:diskSizeGb,caching:caching,managedId:managedDisk.id}}" -o json > "$OUT/vm-disks.json"
cat "$OUT/vm-disks.json"
for d in $(jq -r '.data[].name' "$OUT/vm-disks.json"); do
  az disk show --subscription "$SUB" -g "$RG" -n "$d" --query "{name:name,sku:sku.name,tier:tier,gb:diskSizeGB,iops:diskIOPSReadWrite,mbps:diskMBpsReadWrite,burst:burstingEnabled}" -o json > "$OUT/disk-$d.json"
  echo "== $d"; cat "$OUT/disk-$d.json"
  ID=$(az disk show --subscription "$SUB" -g "$RG" -n "$d" --query id -o tsv)
  for m in "Composite Disk Read Operations/sec" "Composite Disk Write Operations/sec" "Composite Disk Write Bytes/sec" "Disk IOPS Consumed Percentage" "Disk Bandwidth Consumed Percentage"; do
    az monitor metrics list --subscription "$SUB" --resource "$ID" --metric "$m" --interval PT1M --start-time 2026-10-15T06:00:00Z --end-time 2026-10-15T18:30:00Z --aggregation Maximum -o json > "$OUT/metric-$d-$(echo "$m" | tr ' /' '__').json" 2>&1 || echo "metrica no disponible: $m"
  done
done
VMID=$(az vm show --subscription "$SUB" -g "$RG" -n "$VM" --query id -o tsv)
for m in "VM Cached IOPS Consumed Percentage" "VM Uncached IOPS Consumed Percentage" "VM Uncached Bandwidth Consumed Percentage"; do
  az monitor metrics list --subscription "$SUB" --resource "$VMID" --metric "$m" --interval PT1M --start-time 2026-10-15T06:00:00Z --end-time 2026-10-15T18:30:00Z --aggregation Maximum -o json > "$OUT/metric-vm-$(echo "$m" | tr ' /' '__').json" 2>&1 || echo "metrica no disponible: $m"
done
echo listo

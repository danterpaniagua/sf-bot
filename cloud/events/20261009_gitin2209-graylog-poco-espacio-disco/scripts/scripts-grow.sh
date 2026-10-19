#!/usr/bin/env bash
# Event: 20261009_gitin2209-graylog-poco-espacio-disco
# C2 — Crece la particion y el filesystem XFS de /var/lib/opensearch en la VM de Graylog de SmartCloud para usar los
#      256 GB que se agregaron al disco (nvme0n3: 768G con particion nvme0n3p1 de 512G). En linea, sin detener OpenSearch.
#      DRYRUN=1 (por omision): solo guardas, estado actual y "growpart -N"; NO modifica nada.
#      DRYRUN=0 : MODIFICA LA VM — growpart (tabla de particiones) + xfs_growfs. XFS no se puede reducir: no hay reversa.
# Uso:  DRYRUN=1 bash <ruta>/scripts-grow.sh > <ruta>/data/grow-dryrun.txt 2>&1
#       DRYRUN=0 bash <ruta>/scripts-grow.sh > <ruta>/data/grow-apply.txt 2>&1
set -euo pipefail
DRYRUN="${DRYRUN:-1}"
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com "DRYRUN=$DRYRUN bash -s" <<'REMOTE'
set -euo pipefail
DISK=/dev/nvme0n3; PART=/dev/nvme0n3p1; MNT=/var/lib/opensearch
echo "== $(hostname) $(date -u +'%F %T UTC') DRYRUN=$DRYRUN"
echo "== guardas"
[ "$(findmnt -n -o SOURCE "$MNT")" = "$PART" ] || { echo "GUARDA: $MNT no esta montado desde $PART"; exit 1; }
[ "$(findmnt -n -o FSTYPE "$MNT")" = "xfs" ] || { echo "GUARDA: $MNT no es xfs"; exit 1; }
[ "$(lsblk -n -o NAME "$DISK" | wc -l)" = 2 ] || { echo "GUARDA: $DISK no tiene exactamente una particion"; exit 1; }
DISK_B=$(lsblk -bndo SIZE "$DISK"); PART_B=$(lsblk -bndo SIZE "$PART")
[ "$DISK_B" -gt $((PART_B + 100*1024*1024*1024)) ] || { echo "GUARDA: no hay mas de 100 GB sin usar en $DISK (disco=$DISK_B particion=$PART_B)"; exit 1; }
command -v growpart >/dev/null || { echo "GUARDA: falta growpart (paquete cloud-guest-utils)"; exit 1; }
echo "guardas OK: disco=$((DISK_B/1024/1024/1024))G particion=$((PART_B/1024/1024/1024))G"
echo "== ANTES"; lsblk "$DISK"; df -h "$MNT"; sudo -n xfs_info "$MNT" | head -3
echo "== growpart -N"; sudo -n growpart -N "$DISK" 1
if [ "$DRYRUN" != "0" ]; then echo "DRYRUN: no se modifico nada"; exit 0; fi
echo "== growpart"; sudo -n growpart "$DISK" 1
echo "== xfs_growfs"; sudo -n xfs_growfs "$MNT"
echo "== DESPUES"; lsblk "$DISK"; df -h "$MNT"
REMOTE

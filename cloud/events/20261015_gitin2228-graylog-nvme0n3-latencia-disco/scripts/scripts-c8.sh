#!/usr/bin/env bash
# C8 - prueba de read_ahead_kb en nvme0n3 de sfcloud-monitoreo (cambio en caliente, no persiste tras reiniciar).
# Uso: ssh sfcloud-monitoreo "bash -s -- <modo>" < scripts-c8.sh > data/c8-<modo>-....txt
#   show      solo lectura: valor actual y 3 muestras de iostat
#   apply     pone read_ahead_kb en 128 (solo si hoy vale 65536)
#   rollback  vuelve a 65536 (solo si hoy vale 128)
set -u
MODE="${1:-show}"; DEV=nvme0n3; F=/sys/block/$DEV/queue/read_ahead_kb
echo "== host: $(hostname) | $(date -u +%FT%TZ) | modo: $MODE"
[ "$(hostname)" = "sfcloud-monitoreo" ] || { echo "ABORTA: host distinto de sfcloud-monitoreo"; exit 1; }
[ -r "$F" ] || { echo "ABORTA: no existe $F"; exit 1; }
echo "== lsblk (confirma que $DEV es el disco de /var/lib/opensearch)"; lsblk -o NAME,SIZE,MOUNTPOINT /dev/$DEV
CUR=$(cat "$F"); echo "== read_ahead_kb actual: $CUR"
case "$MODE" in
  show) ;;
  apply)    [ "$CUR" = "65536" ] || { echo "ABORTA: el valor actual no es 65536"; exit 1; }
            echo 128 | sudo tee "$F" >/dev/null; echo "== read_ahead_kb nuevo: $(cat $F)" ;;
  rollback) [ "$CUR" = "128" ]   || { echo "ABORTA: el valor actual no es 128"; exit 1; }
            echo 65536 | sudo tee "$F" >/dev/null; echo "== read_ahead_kb nuevo: $(cat $F)" ;;
  *) echo "modo desconocido"; exit 1 ;;
esac
echo "== iostat $DEV (3 x 5 s)"; iostat -x -d "$DEV" 5 3

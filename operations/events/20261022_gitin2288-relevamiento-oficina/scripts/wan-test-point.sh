#!/usr/bin/env bash
# Read-only: measures the public IP, ping loss/jitter, and single-stream download/upload against Cloudflare
# from the host where it runs. Usage: wan-test-point.sh <label>   e.g. dedicated-modem-direct
# Output: /home/dpaniagua/Documentos/git/bots/operations/events/20261022_gitin2288-relevamiento-oficina/data/wan-<label>-<YYYYMMDD-HHMM>.txt
set -u
export LC_ALL=C
label="${1:?label required}"
base=/home/dpaniagua/Documentos/git/bots/operations/events/20261022_gitin2288-relevamiento-oficina
out="$base/data/wan-${label}-$(date +%Y%m%d-%H%M).txt"
tmp="$(mktemp)"
{
  echo "label: $label"
  echo "host: $(hostname)  start: $(date '+%F %T')"
  echo "iface/default route:"; ip route show default
  dev="$(ip route show default | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
  echo "iface=$dev link_speed_mbps=$(cat /sys/class/net/$dev/speed 2>/dev/null || echo n/a)"
  echo "public_ip: $(curl -s --max-time 10 https://ifconfig.me)"
  echo "--- ping 1.1.1.1 x60 (1 s)"
  ping -c 60 -i 1 -q 1.1.1.1 | tail -n 2
  for i in 1 2 3; do
    echo "--- download 50 MB run $i"
    curl -s -o /dev/null --max-time 120 -w 'speed_download_bytes_s=%{speed_download} time_total=%{time_total}\n' "https://speed.cloudflare.com/__down?bytes=50000000"
  done
  for i in 1 2 3; do
    echo "--- upload 25 MB run $i"
    head -c 25000000 /dev/zero | curl -s -o /dev/null --max-time 120 -X POST --data-binary @- -w 'speed_upload_bytes_s=%{speed_upload} time_total=%{time_total}\n' "https://speed.cloudflare.com/__up"
  done
  echo "end: $(date '+%F %T')"
} > "$tmp" 2>&1
cat "$tmp" > "$out"
rm -f "$tmp"
echo "$out"

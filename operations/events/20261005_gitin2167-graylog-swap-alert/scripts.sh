#!/usr/bin/env bash
# Event: 20261005_gitin2167-graylog-swap-alert
# Host: nodo OpenSearch "sfcloud-monitoreo" (hostname del SO no confirmado)
# Outputs reales en data/ (pegados por el usuario; no se redirigieron con el comando)
# ⚠️ ACTION commands are clearly marked

# === INVESTIGATION ===
# C1 — Estado de memoria y swap
free -h
# data/free-h-before-and-after.txt

# C2 — Swappiness y swap por proceso (top 10, kB)
cat /proc/sys/vm/swappiness
for f in /proc/[0-9]*/status; do awk '/^Name:/{n=$2} /^VmSwap:/{s=$2} END{if(s>0) print s, n}' "$f"; done | sort -rn | head
# data/swappiness-and-vmswap-by-process.txt

# C3 — Mapeo de PIDs Java a servicios + actividad de swap en vivo
for f in /proc/[0-9]*/status; do awk '/^Pid:/{p=$2} /^Name:/{n=$2} /^VmSwap:/{s=$2} END{if(s>0 && n=="java") print s, p}' "$f"; done | sort -rn | while read s p; do echo "$s kB pid=$p $(tr '\0' ' ' < /proc/$p/cmdline | grep -oE 'opensearch|graylog|logstash|-Xm[sx][0-9]+[mg]' | sort -u | tr '\n' ' ')"; done
vmstat 5 6
# data/java-pid-map-and-vmstat.txt

# C4 — Flags de heap de OpenSearch (cmdline) e intento de jcmd (falló: attach)
tr '\0' '\n' < /proc/2771/cmdline | grep -nE '^-Xm[sx]'
sudo jcmd 2771 VM.flags | tr ' ' '\n' | grep -E 'InitialHeapSize|MaxHeapSize'
# data/opensearch-cmdline-xm-flags-and-jcmd-error.txt

# C5 — Heap efectivo vía API de OpenSearch
curl -s 'localhost:9200/_cat/nodes?v&h=name,heap.max,heap.percent,ram.max,ram.percent'
# data/opensearch-cat-nodes.txt

# C6 — Contenido de /etc/fstab
cat /etc/fstab
# data/etc-fstab.txt

# C8 — Hostname y origen de los flags -Xm* de OpenSearch (vía SSH)
ssh <user>@sf-monitoreo.smartfran.com 'hostname; sudo grep -rnE "^-Xm[sx]|OPENSEARCH_JAVA_OPTS|Xm[sx][0-9]+[mg]" /etc/opensearch/jvm.options /etc/opensearch/jvm.options.d/ /etc/default/opensearch /usr/lib/systemd/system/opensearch.service /etc/systemd/system/opensearch.service.d/ 2>&1'
# data/opensearch-xm-flag-sources.txt, data/hostname.txt

# === REMEDIATION ===
# ⚠️ C7 — Crear, formatear y activar swap file de 4 GiB (output de mkswap capturado; dd/chmod/swapon sin output)
sudo dd if=/dev/zero of=/var/lib/mongodb/swapfile bs=1M count=4096 status=progress
sudo chmod 600 /var/lib/mongodb/swapfile
sudo mkswap /var/lib/mongodb/swapfile
sudo swapon /var/lib/mongodb/swapfile
# data/mkswap-output.txt

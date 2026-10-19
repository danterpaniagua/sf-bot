#!/usr/bin/env bash
# Event: 20261015_gitin2228-graylog-nvme0n3-latencia-disco
# C4 - SOLO LECTURA. Se ejecuta EN la VM de Cloud Graylog (ssh no interactivo; mismo uso que scripts-c1.sh). Nada se escribe en la VM.
#      Uso:  ssh <usuario>@<host-graylog> 'sudo bash -s' < /home/dpaniagua/Documentos/git/bots/cloud/events/20261015_gitin2228-graylog-nvme0n3-latencia-disco/scripts/scripts-c4.sh > /home/dpaniagua/Documentos/git/bots/cloud/events/20261015_gitin2228-graylog-nvme0n3-latencia-disco/data/c4-vm-$(date -u +%Y%m%dT%H%M%SZ).txt 2>&1
#      Preguntas (C1/C3): (1) de donde sale read_ahead_kb = 65536 (udev, tuned, servicio, rc.local); (2) que procesos leen/escriben en el disco ahora (muestra de 30 s por proceso);
#      (3) estadisticas de merges de OpenSearch (el nombre de la metrica estaba mal en C1); (4) latencias por dispositivo ahora y el historial de sar de hoy para nvme0n3.
export LC_ALL=C
echo "== host: $(hostname) | $(date -u +%FT%TZ)"
echo "== read_ahead actual de cada nvme (kB) y blockdev --getra (sectores de 512 B)"
for d in /sys/block/nvme*; do n=$(basename $d); echo "$n: read_ahead_kb=$(cat $d/queue/read_ahead_kb) getra=$(blockdev --getra /dev/$n 2>&1)"; done
echo "== donde se define read_ahead (udev, tuned, systemd, rc.local, sysctl)"
grep -rIn "read_ahead\|readahead\|getra\|setra" /etc/udev/rules.d /usr/lib/udev/rules.d /etc/tuned /usr/lib/tuned /etc/systemd /etc/rc.local /etc/sysctl.conf /etc/sysctl.d /etc/cron.d 2>/dev/null | head -20
echo "== tuned activo (si existe)"; command -v tuned-adm >/dev/null && tuned-adm active 2>&1 || echo "tuned-adm no instalado"
echo "== E/S por proceso, muestra de 30 s (pidstat -d si existe; si no, delta de /proc/<pid>/io de los 8 procesos con mas lectura+escritura)"
if command -v pidstat >/dev/null; then pidstat -d 5 6 2>&1 | grep -v "^$" | tail -40
else
  declare -A r0 w0; for p in $(ls /proc | grep -E '^[0-9]+$'); do [ -r /proc/$p/io ] && { r0[$p]=$(awk '/^read_bytes/{print $2}' /proc/$p/io 2>/dev/null); w0[$p]=$(awk '/^write_bytes/{print $2}' /proc/$p/io 2>/dev/null); }; done
  sleep 30
  for p in "${!r0[@]}"; do [ -r /proc/$p/io ] || continue; r1=$(awk '/^read_bytes/{print $2}' /proc/$p/io 2>/dev/null); w1=$(awk '/^write_bytes/{print $2}' /proc/$p/io 2>/dev/null); echo "$(( (${r1:-0}-${r0[$p]:-0}) + (${w1:-0}-${w0[$p]:-0}) )) $(( (${r1:-0}-${r0[$p]:-0})/30 )) $(( (${w1:-0}-${w0[$p]:-0})/30 )) pid=$p uid=$(stat -c %u /proc/$p) cmd=$(tr '\0' ' ' < /proc/$p/cmdline | cut -c1-90)"; done | sort -rn | head -8 | awk '{print "total_bytes_30s="$1" lectura_B/s="$2" escritura_B/s="$3" "$4" "$5" "$6" "$7" "$8" "$9}'
fi
echo "== servicio de cada uid de java (nombre de usuario y unidad systemd, sin otros datos)"
for p in $(pgrep java); do echo "pid=$p user=$(ps -o user= -p $p) unit=$(systemctl status $p 2>/dev/null | head -1 | cut -c1-90)"; done
echo "== OpenSearch: estadisticas de merge (metrica indices/merge)"
curl -s -m 10 'localhost:9200/_nodes/stats/indices/merge?filter_path=nodes.*.indices.merges' 2>&1
echo; echo "== OpenSearch: segmentos totales y tamano de los indices activos (top 10)"; curl -s -m 10 'localhost:9200/_cat/indices?v&h=index,pri,rep,segments.count,store.size&s=store.size:desc' 2>&1 | head -11
echo "== iostat -x de nvme0n3 y nvme0n2 (3 muestras de 5 s)"; command -v iostat >/dev/null && iostat -dxm nvme0n2 nvme0n3 5 3 || echo "iostat no instalado"
echo "== sar -d de hoy, solo nvme0n3, con await mayor a 100 ms (hora UTC del host)"; command -v sar >/dev/null && sar -d -p 2>&1 | awk '/DEV/ && !h {for(i=1;i<=NF;i++) if($i=="await") c=i; print; h=1; next} c && $0 ~ /nvme0n3/ && $c+0>100' | head -40 || echo "sar no instalado"
echo listo

#!/usr/bin/env bash
# Event: 20261015_gitin2228-graylog-nvme0n3-latencia-disco
# C5 - SOLO LECTURA. Se ejecuta EN la VM de Cloud Graylog (ssh no interactivo, sudo). Nada se escribe en la VM: todo va a stdout.
#      Objetivo: capturar EN VIVO una rafaga de lectura (o de latencia alta) de nvme0n3 y ver quien la produce (hipotesis (d) de C3).
#      Muestrea nvme0n3 cada 5 s durante DUR segundos (por defecto 1800). Cuando r/s > 100, r_await > 100 ms o w_await > 100 ms toma una foto
#      (como maximo una por minuto): E/S por proceso (3 s), tareas activas de OpenSearch (solo accion y duracion, sin descripcion para no
#      traer texto de consultas), pools de hilos y hot threads.
#      Uso:  ssh <usuario>@<host-graylog> 'sudo env DUR=3600 bash -s' < /home/dpaniagua/Documentos/git/bots/cloud/events/20261015_gitin2228-graylog-nvme0n3-latencia-disco/scripts/scripts-c5.sh > /home/dpaniagua/Documentos/git/bots/cloud/events/20261015_gitin2228-graylog-nvme0n3-latencia-disco/data/c5-vm-$(date -u +%Y%m%dT%H%M%SZ).txt 2>&1
export LC_ALL=C
DUR=${DUR:-1800}; INT=5; LAST=-100000
echo "== host: $(hostname) | inicio $(date -u +%FT%TZ) | DUR=${DUR}s INT=${INT}s"
command -v iostat >/dev/null || { echo "iostat no instalado"; exit 1; }
end=$((SECONDS+DUR))
while [ "$SECONDS" -lt "$end" ]; do
  out=$(iostat -dxy nvme0n3 "$INT" 1)
  ts=$(date -u +%FT%TZ)
  row=$(echo "$out" | awk '/^Device/{for(i=1;i<=NF;i++)h[$i]=i} /^nvme0n3/{printf "%s %s %s %s %s %s %s", $h["r/s"], $h["rkB/s"], $h["r_await"], $h["w/s"], $h["w_await"], $h["aqu-sz"], $h["%util"]}')
  set -- $row
  echo "$ts r/s=${1:-NA} rkB/s=${2:-NA} r_await=${3:-NA} w/s=${4:-NA} w_await=${5:-NA} aqu-sz=${6:-NA} util=${7:-NA}"
  hit=$(awk -v r="${1:-0}" -v ra="${3:-0}" -v wa="${5:-0}" 'BEGIN{print ((r+0>100)||(ra+0>100)||(wa+0>100))?1:0}')
  if [ "$hit" = 1 ] && [ $((SECONDS-LAST)) -ge 60 ]; then
    LAST=$SECONDS
    echo "---- FOTO $ts (umbral superado)"
    echo "-- E/S por proceso (3 s)"
    if command -v pidstat >/dev/null; then pidstat -d 1 3 2>&1 | grep -v '^$' | grep -E 'Average|UID' | head -15
    else
      declare -A r0 w0; for p in $(ls /proc | grep -E '^[0-9]+$'); do [ -r /proc/$p/io ] && { r0[$p]=$(awk '/^read_bytes/{print $2}' /proc/$p/io 2>/dev/null); w0[$p]=$(awk '/^write_bytes/{print $2}' /proc/$p/io 2>/dev/null); }; done
      sleep 3
      for p in "${!r0[@]}"; do [ -r /proc/$p/io ] || continue; r1=$(awk '/^read_bytes/{print $2}' /proc/$p/io 2>/dev/null); w1=$(awk '/^write_bytes/{print $2}' /proc/$p/io 2>/dev/null); echo "$(( ${r1:-0}-${r0[$p]:-0} )) $(( ${w1:-0}-${w0[$p]:-0} )) pid=$p cmd=$(tr '\0' ' ' < /proc/$p/cmdline | cut -c1-60)"; done | sort -rn | head -6 | awk '{print "lectura_B_3s="$1" escritura_B_3s="$2" "$3" "$4" "$5}'
    fi
    echo "-- OpenSearch: tareas activas (accion y duracion, sin descripcion)"
    curl -s -m 5 'localhost:9200/_tasks?filter_path=nodes.*.tasks.*.action,nodes.*.tasks.*.running_time_in_nanos' | head -c 2500; echo
    echo "-- OpenSearch: pools de hilos (search, write, force_merge)"
    curl -s -m 5 'localhost:9200/_cat/thread_pool/search,write,force_merge?v&h=name,active,queue,rejected' 2>&1 | head -6
    echo "-- OpenSearch: hot threads (3)"
    curl -s -m 8 'localhost:9200/_nodes/hot_threads?threads=3&type=cpu' 2>&1 | head -40
  fi
done
echo "== fin $(date -u +%FT%TZ)"

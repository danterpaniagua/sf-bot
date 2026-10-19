#!/usr/bin/env bash
# Event: 20261015_gitin2228-graylog-nvme0n3-latencia-disco
# C1 - SOLO LECTURA. Se ejecuta EN la VM de Cloud Graylog (via ssh no interactivo, ver comando de uso).
#      Salida a stdout; el comando de uso la redirige a data/c1-vm-<fecha>.txt (nada se escribe en la VM salvo /tmp del propio bash).
#      Uso (desde la maquina local):  ssh <usuario>@<host-graylog> 'sudo bash -s' < scripts-c1.sh > data/c1-vm-$(date -u +%Y%m%dT%H%M%SZ).txt 2>&1
#      Masking: no lista usuarios, tokens ni IPs de clientes; las consultas a OpenSearch son solo _cat/_nodes/stats.
export LC_ALL=C
echo "== host: $(hostname) | $(date -u +%FT%TZ) | zona local: $(date +%Z%z)"
echo "== lsblk"; lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL,ROTA
echo "== df /var/lib/opensearch /var/lib/mongodb /"; df -h /var/lib/opensearch /var/lib/mongodb / 2>&1
echo "== mount opciones"; findmnt -o TARGET,SOURCE,FSTYPE,OPTIONS /var/lib/opensearch
echo "== scheduler / cola nvme0n3"; for f in scheduler nr_requests read_ahead_kb rotational; do echo -n "$f: "; cat /sys/block/nvme0n3/queue/$f 2>&1 || cat /sys/block/nvme0n3/queue/$f; done
echo "== iostat -x (3 muestras de 5 s) si existe"
if command -v iostat >/dev/null; then iostat -dxm nvme0n3 5 3; else echo "iostat no instalado (paquete sysstat)"; fi
echo "== sar -d historico de hoy (sysstat) si existe"
if command -v sar >/dev/null; then for f in /var/log/sysstat/sa$(date +%d) /var/log/sa/sa$(date +%d); do [ -f "$f" ] && { echo "archivo $f"; sar -d -p -f "$f" | awk 'NR<4 || /nvme0n3|DEV/' | head -400; break; }; done; else echo "sar no instalado"; fi
echo "== fstrim / timers"; systemctl list-timers --all --no-pager 2>&1 | grep -Ei "fstrim|logrotate|apt|snap|backup|sysstat" 
echo "== kernel: errores nvme/xfs/blk ultimas 24 h"; journalctl -k --since "-24h" --no-pager 2>&1 | grep -Ei "nvme|xfs|blk_update|I/O error|hung task|timeout" | tail -50
echo "== procesos con mas I/O (pidstat -d si existe)"; command -v pidstat >/dev/null && pidstat -d 5 2 | tail -25 || echo "pidstat no instalado"
echo "== OpenSearch: nodo y disco"
curl -s -m 10 'localhost:9200/_cat/allocation?v&h=node,shards,disk.indices,disk.used,disk.avail,disk.percent' 2>&1
curl -s -m 10 'localhost:9200/_nodes/stats/fs,indices/merge,indexing?filter_path=nodes.*.fs.io_stats,nodes.*.fs.total,nodes.*.indices.merges,nodes.*.indices.indexing.index_total,nodes.*.indices.indexing.index_time_in_millis' 2>&1 | head -c 4000; echo
echo "== OpenSearch: tareas en curso (merge/snapshot/forcemerge/delete)"; curl -s -m 10 'localhost:9200/_cat/tasks?v&detailed=false&h=action,running_time,node' 2>&1 | head -30
echo "== OpenSearch: thread_pool write y pending tasks"; curl -s -m 10 'localhost:9200/_cat/thread_pool/write?v&h=node_name,active,queue,rejected,completed' 2>&1; curl -s -m 10 'localhost:9200/_cat/pending_tasks?v' 2>&1
echo "== OpenSearch: indices mas grandes y activos (top 15 por tamano)"; curl -s -m 10 'localhost:9200/_cat/indices?v&h=index,health,pri,rep,docs.count,store.size&s=store.size:desc' 2>&1 | head -16
echo "== Graylog journal"; du -sh /var/lib/graylog-server/journal 2>&1
echo "listo"

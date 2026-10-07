#!/usr/bin/env bash
# GITIN-1174: read-only inventory of the Grafana/Prometheus VM (compose dir /home/ubuntu/grafana-prometheus).
# Usage:  GRAFANA_HOST=<ssh host or user@host> ./scripts.sh
# Runs ONE non-interactive ssh with a read-only script (no writes, no restarts, no docker exec) and stores the output in data/.
# Secret-like values (PASSWORD/SECRET/KEY/TOKEN/PASS ...) are masked on the VM before they leave it.
set -eu
: "${GRAFANA_HOST:?set GRAFANA_HOST, e.g. ubuntu@<vm-address>}"
E=/home/dpaniagua/Documentos/git/bots/operations/events/20261001_gitin1174-grafana-7x-update/data
mkdir -p "$E"
D=/home/ubuntu/grafana-prometheus

ssh "$GRAFANA_HOST" 'bash -s' > "$E/vm_inventory_20261001.txt" 2>&1 <<'REMOTE' || true
D=/home/ubuntu/grafana-prometheus
mask() { sed -E 's/((PASSWORD|SECRET|KEY|TOKEN|PASS|API)[A-Za-z0-9_]*[ ]*[:=][ ]*).*/\1<MASKED>/I'; }
echo "== host";            hostname; date -u +%FT%TZ; uname -srm; uptime
echo "== docker";          docker --version; docker compose version 2>&1 | head -1
echo "== dir listing";     ls -la "$D"
echo "== compose files";   ls -la "$D"/docker-compose* 2>&1
echo "== docker-compose.yml (masked)"; mask < "$D/docker-compose.yml"
echo "== running containers"; docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
echo "== images";          docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}\t{{.Size}}'
echo "== grafana health (version)"; curl -s --max-time 5 localhost:3000/api/health; echo
echo "== disk";            df -h /home/ubuntu | tail -2
echo "== sizes";           du -sh "$D"/db "$D"/prometheus-data "$D"/letsencrypt 2>&1
echo "== grafana db dir";  ls -la "$D/db" 2>&1 | head -12
echo "== installed plugins (dir names)"; ls "$D/db/plugins" 2>&1
echo "== cron (backups?)"; crontab -l 2>&1 | head -20; ls /etc/cron.d 2>&1
REMOTE
echo "done: $E/vm_inventory_20261001.txt"

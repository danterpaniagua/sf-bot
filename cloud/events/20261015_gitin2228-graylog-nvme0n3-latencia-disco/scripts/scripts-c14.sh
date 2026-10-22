#!/usr/bin/env bash
# C14 (solo lectura) - indices de OpenSearch con fecha de creacion, tamano y edad, para estimar cuanto se borraria al normalizar a 30 dias.
# Se ejecuta en la VM sfcloud-monitoreo: ssh sfcloud-monitoreo "bash -s" < scripts-c14.sh > data/c14-...txt
set -u
[ "$(hostname)" = "sfcloud-monitoreo" ] || { echo "ABORTA: host distinto de sfcloud-monitoreo"; exit 1; }
echo "== host: $(hostname) | $(date -u +%FT%TZ)"
echo "== indices (nombre, creacion UTC, edad en dias, GB, documentos), mas viejos primero"
curl -s -m 20 'localhost:9200/_cat/indices?h=index,creation.date.string,store.size,docs.count&bytes=b&s=creation.date' 2>&1 \
| awk -v now="$(date -u +%s)" '
    { cmd="date -u -d \"" $2 "\" +%s 2>/dev/null"; cmd | getline ts; close(cmd);
      age = (ts=="" ? "?" : sprintf("%.1f", (now-ts)/86400));
      printf "%s\t%s\t%s\t%.2f\t%s\n", $1, $2, age, $3/1073741824, $4 }'

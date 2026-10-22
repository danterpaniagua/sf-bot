#!/usr/bin/env bash
# C7 (solo lectura) - origen (IP cliente y user-agent) de las busquedas de Graylog de las 18:14, 18:16-18:17 y 18:27 UTC del 2026-10-20.
# Se ejecuta desde la estacion local: ssh sfcloud-monitoreo "bash -s" < scripts-c7.sh > data/c7-...txt
set -u
echo "== host: $(hostname) | $(date -u +%FT%TZ)"
echo "== formato de log (primera linea sin query)"
for f in /var/log/nginx/access.log /var/log/nginx/access.log.1; do
  [ -r "$f" ] || sudo test -r "$f" || continue
  sudo grep -E '20/Oct/2026:18:(1[4-7]|27):' "$f" 2>/dev/null | grep -E 'views/search|views/searchjobs|search/validate|/graylog/search|views/[0-9a-f]{24}' \
    | awk '{ t=substr($4,14,5); ua=""; n=split($0,a,"\""); if (n>=6) ua=a[6]; print t, $1, $9, ua }' | cut -c1-200 | sort | uniq -c
done

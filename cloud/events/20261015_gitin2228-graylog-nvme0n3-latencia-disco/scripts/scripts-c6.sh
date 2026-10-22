#!/usr/bin/env bash
# C6 (solo lectura) - buscar un comando o prueba manual durante la captura C5 (2026-10-20 17:22-18:23 UTC).
# Se ejecuta desde la estacion local: ssh sfcloud-monitoreo "bash -s" < scripts-c6.sh > data/c6-...txt (imprime a stdout).
set -u
S="2026-10-20 17:15:00"; U="2026-10-20 18:30:00"   # hora del host (UTC)
{
  echo "== host: $(hostname) | $(date -u +%FT%TZ)"
  echo "== sesiones y logins en la ventana (sshd, login)"
  journalctl --since "$S" --until "$U" -u ssh -u sshd --no-pager 2>/dev/null | grep -Ei 'Accepted|session opened|session closed' | sed -E 's/from [0-9.]+/from <ip>/'
  echo "== comandos via sudo en la ventana"
  journalctl --since "$S" --until "$U" -t sudo --no-pager 2>/dev/null | grep -E 'COMMAND=' | sed -E 's/^.*(sudo\[[0-9]+\]: )/\1/'
  echo "== peticiones por minuto a nginx (rutas search/views/messages, sin query ni IP)"
  for f in /var/log/nginx/access.log /var/log/nginx/access.log.1; do
    [ -r "$f" ] && sudo grep -E '20/Oct/2026:(17:(1[5-9]|[2-5][0-9])|18:[0-2][0-9])' "$f" 2>/dev/null
  done | awk '{ t=substr($4,14,5); split($7,p,"?"); if (p[1] ~ /search|views|messages|dashboards|events/) c[t" "p[1]]++ } END { for (k in c) print c[k], k }' | sort -k2,2 -k1,1nr | head -80
  echo "== procesos de usuario con mas tiempo de CPU/IO ahora (referencia)"
  ps -eo user,pid,lstart,etime,cmd --sort=lstart | awk '$1!="root"' | cut -c1-200 | head -40
} 2>&1

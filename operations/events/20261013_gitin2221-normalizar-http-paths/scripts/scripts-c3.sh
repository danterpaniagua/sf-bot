#!/usr/bin/env bash
# Event: 20261013_gitin2221-normalizar-http-paths
# C3 — Solo lectura. Estado real de la VM despues de 'deploy.sh apply' (el log de apply quedo incompleto: 'tee /dev/stderr' trunco el archivo):
#      sha256 del config vivo vs. el respaldo vs. el esperado, si el bloque esta en el config vivo, la tabla, desde cuando corre logstash,
#      y errores del servicio en los ultimos 15 minutos (redactados). Salida en data/c3-state.txt (+ resumen por stdout).
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
OUT="/home/dpaniagua/Documentos/git/bots/operations/events/20261013_gitin2221-normalizar-http-paths/data"
VM() { ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com "$1"; }
RED() { sed -E 's/((connection|conn|secret|password|passwd|key|token|sas)[A-Za-z_]*[[:space:]]*[=:>]+[[:space:]]*).*/\1"REDACTED"/I; s/(SharedAccessKey=|AccountKey=)[^"; ]*/\1REDACTED/g'; }
VM "date -u +'%F %T UTC'; echo '-- archivos'; sudo ls -l --time-style=long-iso /etc/logstash/conf.d/ /etc/logstash/normalized-paths.json; echo '-- sha256 (esperado antes del cambio: 728bb77c357293006166f7fdf30be3bd4f9b6495243e63400414c087d91bc56a)'; sudo sha256sum /etc/logstash/conf.d/azure-eventhub-to-graylog.conf /etc/logstash/conf.d/azure-eventhub-to-graylog.conf.bak-GITIN-2221; echo '-- lineas con NormalizedPath en el config vivo'; sudo grep -c NormalizedPath /etc/logstash/conf.d/azure-eventhub-to-graylog.conf; echo '-- servicio'; systemctl is-active logstash; systemctl show logstash -p ActiveEnterTimestamp -p MainPID; echo '-- errores/avisos de los ultimos 15 min'; sudo journalctl -u logstash --since '-15min' --no-pager | grep -i -E 'error|exception|fatal|ruby' | cut -c1-260 | tail -25" 2>&1 | RED > "$OUT/c3-state.txt"
sed -n 1,/^-- servicio/p "$OUT/c3-state.txt" | grep -v '^-- servicio' | cut -c1-200
grep -c . "$OUT/c3-state.txt" | sed 's/^/lineas en c3-state.txt: /'
echo listo

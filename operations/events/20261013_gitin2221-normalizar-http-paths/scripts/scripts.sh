#!/usr/bin/env bash
# Event: 20261013_gitin2221-normalizar-http-paths
# C1 — Solo lectura. Baja la configuracion VIVA de Logstash de la VM de Graylog de SmartCloud (sfcloud-monitoreo) por SSH no
#      interactivo, para armar el patch de NormalizedPath contra lo realmente desplegado (no contra la copia local de cloud-graylog).
#      El .conf trae cadenas de conexion: se redactan en el origen (sed) antes de guardar; nunca se escribe un secreto en el repo.
#      Salidas en data/: logstash-conf.d-listing.txt, logstash-version.txt, azure-eventhub-to-graylog.conf.redacted
# Uso:  bash <ruta>/scripts.sh > <ruta>/data/pull-log.txt 2>&1
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
OUT="/home/dpaniagua/Documentos/git/bots/operations/events/20261013_gitin2221-normalizar-http-paths/data"
VM() { ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com "$1"; }
VM "sudo ls -l --time-style=long-iso /etc/logstash/conf.d/ /etc/logstash/ | head -60; date -u +'%F %T UTC'" > "$OUT/logstash-conf.d-listing.txt"
VM "sudo /usr/share/logstash/bin/logstash --version 2>&1 | tail -2" > "$OUT/logstash-version.txt"
VM "sudo cat /etc/logstash/conf.d/azure-eventhub-to-graylog.conf" \
  | sed -E 's/((connection|conn|secret|password|passwd|key|token|sas)[A-Za-z_]*[[:space:]]*=>[[:space:]]*).*/\1"REDACTED"/I; s/(Endpoint=sb:\/\/|SharedAccessKey=|AccountKey=)[^"; ]*/\1REDACTED/g' \
  > "$OUT/azure-eventhub-to-graylog.conf.redacted"
echo "listado: $(wc -l < "$OUT/logstash-conf.d-listing.txt") lineas | conf redactado: $(wc -l < "$OUT/azure-eventhub-to-graylog.conf.redacted") lineas"
echo "lineas redactadas: $(grep -c 'REDACTED' "$OUT/azure-eventhub-to-graylog.conf.redacted")"
echo "posibles secretos restantes (debe ser 0): $(grep -c -i -E 'SharedAccessKey=[A-Za-z0-9+/=]{10}|AccountKey=[A-Za-z0-9+/=]{10}' "$OUT/azure-eventhub-to-graylog.conf.redacted" || true)"
echo listo

#!/usr/bin/env bash
# Event: 20261013_gitin2221-normalizar-http-paths
# C2 — Solo lectura. Vuelve a bajar la configuracion VIVA de Logstash (redactada igual que C1) y la compara con la de C1, para
#      confirmar que no cambio antes de armar el patch. Tambien lee pipelines.yml y comprueba si ya existe la tabla de rutas
#      /etc/logstash/normalized-paths.json en la VM. Salidas en data/ con sufijo c2.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
OUT="/home/dpaniagua/Documentos/git/bots/operations/events/20261013_gitin2221-normalizar-http-paths/data"
VM() { ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com "$1"; }
VM "date -u +'%F %T UTC'; sudo ls -l --time-style=long-iso /etc/logstash/conf.d/azure-eventhub-to-graylog.conf; sudo sha256sum /etc/logstash/conf.d/azure-eventhub-to-graylog.conf; sudo ls -l /etc/logstash/normalized-paths.json 2>&1 || true; sudo cat /etc/logstash/pipelines.yml; id logstash; systemctl is-active logstash" 2>&1 \
  | sed -E 's/((connection|conn|secret|password|passwd|key|token|sas)[A-Za-z_]*[[:space:]]*[=:>]+[[:space:]]*).*/\1"REDACTED"/I' > "$OUT/logstash-state-c2.txt"
VM "sudo cat /etc/logstash/conf.d/azure-eventhub-to-graylog.conf" \
  | sed -E 's/((connection|conn|secret|password|passwd|key|token|sas)[A-Za-z_]*[[:space:]]*=>[[:space:]]*).*/\1"REDACTED"/I; s/(Endpoint=sb:\/\/|SharedAccessKey=|AccountKey=)[^"; ]*/\1REDACTED/g' \
  > "$OUT/azure-eventhub-to-graylog.conf.redacted-c2"
echo "lineas: $(wc -l < "$OUT/azure-eventhub-to-graylog.conf.redacted-c2") | secretos restantes (debe ser 0): $(grep -c -i -E 'SharedAccessKey=[A-Za-z0-9+/=]{10}|AccountKey=[A-Za-z0-9+/=]{10}' "$OUT/azure-eventhub-to-graylog.conf.redacted-c2" || true)"
if diff -q "$OUT/azure-eventhub-to-graylog.conf.redacted" "$OUT/azure-eventhub-to-graylog.conf.redacted-c2" > /dev/null; then echo "conf viva: IGUAL que en C1"; else echo "conf viva: CAMBIO desde C1"; diff "$OUT/azure-eventhub-to-graylog.conf.redacted" "$OUT/azure-eventhub-to-graylog.conf.redacted-c2" | head -40; fi
echo listo

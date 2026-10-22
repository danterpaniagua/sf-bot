#!/usr/bin/env bash
# C11 (solo lectura) - cuantos mensajes AppLevel=Unknown parecen errores, por servicio, ultimas 24 h.
# Cuenta por palabra clave en el campo message (texto completo); no guarda ni muestra el contenido de los mensajes.
# Se ejecuta desde la estacion local. Requiere GRAYLOG_API_KEY y jq. Salida TSV a stdout.
# Uso: bash scripts-c11.sh > data/c11-graylog-unknown-errors.tsv
set -u
BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
RANGE=86400
[ -n "${GRAYLOG_API_KEY:-}" ] || { echo "ABORTA: GRAYLOG_API_KEY no definida" >&2; exit 1; }
SERVICES="SMARTFRAN-CLOUD-ADMIN-PRO SMARTFRAN-CLOUD-BUSINESS-PRO SMARTFRAN-CLOUD-CATALOG-PRO SMARTFRAN-CLOUD-ORDERS-PRO SMARTFRAN-CLOUD-PERSON-PRO SMARTFRAN-CLOUD-PLATFORM-PRO SMARTFRAN-CLOUD-POS-PRO SMARTFRAN-CLOUD-SALES-PRO"

count() {
  local out
  out=$(curl -s --max-time 180 -u "$GRAYLOG_API_KEY:token" -H 'Accept: application/json' \
        --data-urlencode "query=$1" --data-urlencode "range=$RANGE" --data-urlencode 'limit=1' \
        -G "$BASE/search/universal/relative") || { echo ERR; return; }
  echo "$out" | jq -r 'if .total_results == null then "ERR" else .total_results end' 2>/dev/null || echo ERR
}

echo "# $(date -u +%FT%TZ) | rango ${RANGE}s | host consultado: sfcloud-monitoreo (Graylog SmartCloud)"
printf 'servicio\tunknown_total\texception\terror\tfail\tfatal\ttimeout\tcon_alguna_palabra\n'
for S in $SERVICES; do
  echo "$(date -u +%T) consultando $S" >&2
  B="name:$S AND AppLevel:\"Unknown\""
  T=$(count "$B")
  E1=$(count "$B AND message:exception")
  E2=$(count "$B AND message:error")
  E3=$(count "$B AND message:(fail OR failed OR failure)")
  E4=$(count "$B AND message:fatal")
  E5=$(count "$B AND message:(timeout OR timedout)")
  ANY=$(count "$B AND message:(exception OR error OR fail OR failed OR failure OR fatal OR timeout OR timedout)")
  if [[ "$T$E1$E2$E3$E4$E5$ANY" =~ ERR ]]; then
    printf '%s\tERR\t(una consulta fallo: revisar la clave, el nombre del servicio o la URL)\n' "$S"; continue
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$S" "$T" "$E1" "$E2" "$E3" "$E4" "$E5" "$ANY"
done

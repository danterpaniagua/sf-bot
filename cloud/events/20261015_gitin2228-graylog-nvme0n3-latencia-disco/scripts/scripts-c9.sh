#!/usr/bin/env bash
# C9 (solo lectura) - volumen de mensajes por nivel (AppLevel) y por servicio en SmartCloud Graylog, ultimas 24 h.
# Grupo 7 d = Information + sin AppLevel; grupo 30 d = Warning + Error + Fatal. Debug, Verbose y otros valores se cuentan aparte.
# Se ejecuta desde la estacion local (no en la VM). Requiere GRAYLOG_API_KEY y jq. Salida TSV a stdout.
# Uso: bash scripts-c9.sh > data/c9-graylog-level-counts.tsv
set -u
BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
RANGE=86400
[ -n "${GRAYLOG_API_KEY:-}" ] || { echo "ABORTA: GRAYLOG_API_KEY no definida" >&2; exit 1; }
# Nombres del campo `name` (ajustar: solo se vieron SALES y BUSINESS en scripts previos; el resto es supuesto).
SERVICES="ALL SMARTFRAN-CLOUD-ADMIN-PRO SMARTFRAN-CLOUD-BUSINESS-PRO SMARTFRAN-CLOUD-CATALOG-PRO SMARTFRAN-CLOUD-ORDERS-PRO SMARTFRAN-CLOUD-PERSON-PRO SMARTFRAN-CLOUD-PLATFORM-PRO SMARTFRAN-CLOUD-POS-PRO SMARTFRAN-CLOUD-SALES-PRO"

count() {  # $1 = consulta Graylog
  local out
  out=$(curl -s --max-time 180 -u "$GRAYLOG_API_KEY:token" -H 'Accept: application/json' \
        --data-urlencode "query=$1" --data-urlencode "range=$RANGE" --data-urlencode 'limit=1' \
        -G "$BASE/search/universal/relative") || { echo ERR; return; }
  echo "$out" | jq -r 'if .total_results == null then "ERR" else .total_results end' 2>/dev/null || echo ERR
}

echo "# $(date -u +%FT%TZ) | rango ${RANGE}s | host consultado: sfcloud-monitoreo (Graylog SmartCloud)"
printf 'servicio\ttotal\tInformation\tsin_AppLevel\tgrupo_7d\tWarning\tError\tFatal\tgrupo_30d\tDebug\tVerbose\totros_valores\n'
for S in $SERVICES; do
  echo "$(date -u +%T) consultando $S" >&2
  if [ "$S" = ALL ]; then F="*"; else F="name:$S"; fi
  T=$(count "$F")
  I=$(count "$F AND AppLevel:\"Information\"")
  N=$(count "$F AND NOT _exists_:AppLevel")
  W=$(count "$F AND AppLevel:\"Warning\"")
  E=$(count "$F AND AppLevel:\"Error\"")
  X=$(count "$F AND AppLevel:\"Fatal\"")
  D=$(count "$F AND AppLevel:\"Debug\"")
  V=$(count "$F AND AppLevel:\"Verbose\"")
  if [[ "$T$I$N$W$E$X$D$V" =~ ERR ]]; then
    printf '%s\tERR\t(una consulta fallo: revisar la clave, el nombre del servicio o la URL)\n' "$S"; continue
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$S" "$T" "$I" "$N" "$((I+N))" "$W" "$E" "$X" "$((W+E+X))" "$D" "$V" "$((T-I-N-W-E-X-D-V))"
done

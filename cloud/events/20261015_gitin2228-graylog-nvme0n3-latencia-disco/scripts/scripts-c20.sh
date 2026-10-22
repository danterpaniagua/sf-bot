#!/usr/bin/env bash
# C20 (solo lectura) - linea base de tiempo de busqueda en Graylog SmartCloud: mismas consultas fijas, 3 repeticiones cada una.
# Servicios: Business, Orders, Sales. Consultas: Information, y Warning/Error. Rangos: 1, 7 y 15 dias (15 d = limite actual).
# Mide el tiempo que informa Graylog (campo `time`, ms) y los resultados. Una busqueda cancelada o con error sale con estado ERR.
# Correr fuera de horas pico (lee el disco lento). Repetir igual despues del cambio de retencion y comparar.
# Se ejecuta desde la estacion local. Requiere GRAYLOG_API_KEY y jq. Salida TSV a stdout.
# Uso: bash scripts-c20.sh > data/c20-search-baseline-<antes|despues>.tsv
set -u
BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
[ -n "${GRAYLOG_API_KEY:-}" ] || { echo "ABORTA: GRAYLOG_API_KEY no definida" >&2; exit 1; }
SERVICES="SMARTFRAN-CLOUD-BUSINESS-PRO SMARTFRAN-CLOUD-ORDERS-PRO SMARTFRAN-CLOUD-SALES-PRO"
RANGES="86400 604800 1296000"
echo "# $(date -u +%FT%TZ) | host consultado: sfcloud-monitoreo (Graylog SmartCloud) | tiempo informado por Graylog en ms"
printf 'servicio\tnivel\tdias\tcorrida\ttiempo_ms\tresultados\testado\n'
for S in $SERVICES; do
  for LV in 'Information:AppLevel:"Information"' 'WarnError:AppLevel:("Warning" OR "Error")'; do
    NAME=${LV%%:*}; Q=${LV#*:}
    for R in $RANGES; do
      for RUN in 1 2 3; do
        echo "$(date -u +%T) $S $NAME ${R}s corrida $RUN" >&2
        OUT=$(curl -s --max-time 75 -u "$GRAYLOG_API_KEY:token" -H 'Accept: application/json' \
              --data-urlencode "query=name:$S AND $Q" --data-urlencode "range=$R" --data-urlencode 'limit=1' \
              -G "$BASE/search/universal/relative")
        T=$(echo "$OUT" | jq -r '.time // empty' 2>/dev/null); N=$(echo "$OUT" | jq -r '.total_results // empty' 2>/dev/null)
        if [ -n "$T" ]; then ST=ok; else ST=ERR; T=""; N=""; fi
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$S" "$NAME" "$((R/86400))" "$RUN" "$T" "$N" "$ST"
      done
    done
  done
done

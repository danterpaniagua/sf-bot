#!/usr/bin/env bash
# C18 - limite de busqueda en Graylog SmartCloud: cancel_after_seconds=60 y query_time_range_limit=P30D (solo esas dos claves).
# Se ejecuta desde la estacion local. Requiere GRAYLOG_API_KEY y jq. Salida a stdout (redirigir a data/).
# Uso: bash scripts-c18.sh <modo>
#   show      solo lectura: valores actuales
#   apply     PUT con las dos claves nuevas, solo si hoy valen cancel_after_seconds=0 y query_time_range_limit=PT0S
#   rollback  PUT que devuelve esas dos claves a 0 y PT0S, solo si hoy valen 60 y P30D
# El PUT reenvia el objeto completo leido en vivo (las demas claves quedan iguales) y se verifica con un GET posterior.
set -u
MODE="${1:-show}"
BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
CFG="system/cluster_config/org.graylog2.indexer.searches.SearchesClusterConfig"
[ -n "${GRAYLOG_API_KEY:-}" ] || { echo "ABORTA: GRAYLOG_API_KEY no definida" >&2; exit 1; }
get() { curl -s --max-time 60 -u "$GRAYLOG_API_KEY:token" -H 'Accept: application/json' "$BASE/$1"; }
put() { curl -s --max-time 60 -o /dev/null -w '%{http_code}' -X PUT -u "$GRAYLOG_API_KEY:token" -H 'Accept: application/json' \
          -H 'Content-Type: application/json' -H 'X-Requested-By: cli' --data "$2" "$BASE/$1"; }
show() { echo "$1" | jq -c '{cancel_after_seconds, query_time_range_limit}'; }

HOST=$(get system | jq -r '.hostname // "?"')
echo "== $(date -u +%FT%TZ) | servidor: $HOST | modo: $MODE"
case "$HOST" in sfcloud-monitoreo*) ;; *) echo "ABORTA: el servidor no es sfcloud-monitoreo"; exit 1;; esac
BEFORE=$(get "$CFG"); echo "$BEFORE" | jq -e . >/dev/null 2>&1 || { echo "ABORTA: respuesta no valida"; echo "$BEFORE" | head -c 300; exit 1; }
CA=$(echo "$BEFORE" | jq -r '.cancel_after_seconds'); QL=$(echo "$BEFORE" | jq -r '.query_time_range_limit')
echo "== antes: $(show "$BEFORE")"
case "$MODE" in
  show) exit 0 ;;
  apply)    [ "$CA" = "0" ] && [ "$QL" = "PT0S" ] || { echo "ABORTA: los valores actuales no son 0 / PT0S"; exit 1; }
            NEW=$(echo "$BEFORE" | jq -c '.cancel_after_seconds = 60 | .query_time_range_limit = "P30D"') ;;
  rollback) [ "$CA" = "60" ] && [ "$QL" = "P30D" ] || { echo "ABORTA: los valores actuales no son 60 / P30D"; exit 1; }
            NEW=$(echo "$BEFORE" | jq -c '.cancel_after_seconds = 0 | .query_time_range_limit = "PT0S"') ;;
  *) echo "modo desconocido"; exit 1 ;;
esac
echo "== PUT codigo HTTP: $(put "$CFG" "$NEW")"
AFTER=$(get "$CFG"); echo "== despues: $(show "$AFTER")"
echo "== otras claves sin cambios: $(diff <(echo "$BEFORE" | jq -S 'del(.cancel_after_seconds,.query_time_range_limit)') <(echo "$AFTER" | jq -S 'del(.cancel_after_seconds,.query_time_range_limit)') >/dev/null && echo si || echo NO)"

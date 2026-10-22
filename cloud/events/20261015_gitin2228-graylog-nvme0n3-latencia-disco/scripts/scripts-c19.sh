#!/usr/bin/env bash
# C19 - limite de rango de busqueda en Graylog SmartCloud: query_time_range_limit de P30D a P15D (cancel_after_seconds=60 no se toca).
# Se ejecuta desde la estacion local. Requiere GRAYLOG_API_KEY y jq. Salida a stdout (redirigir a data/).
# Uso: bash scripts-c19.sh <modo>
#   show      solo lectura: valores actuales
#   apply     PUT con query_time_range_limit=P15D, solo si hoy valen cancel_after_seconds=60 y query_time_range_limit=P30D
#   rollback  PUT que devuelve query_time_range_limit a P30D, solo si hoy valen 60 y P15D
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
  apply)    [ "$CA" = "60" ] && [ "$QL" = "P30D" ] || { echo "ABORTA: los valores actuales no son 60 / P30D"; exit 1; }
            NEW=$(echo "$BEFORE" | jq -c '.query_time_range_limit = "P15D"') ;;
  rollback) [ "$CA" = "60" ] && [ "$QL" = "P15D" ] || { echo "ABORTA: los valores actuales no son 60 / P15D"; exit 1; }
            NEW=$(echo "$BEFORE" | jq -c '.query_time_range_limit = "P30D"') ;;
  *) echo "modo desconocido"; exit 1 ;;
esac
echo "== PUT codigo HTTP: $(put "$CFG" "$NEW")"
AFTER=$(get "$CFG"); echo "== despues: $(show "$AFTER")"
echo "== otras claves sin cambios: $(diff <(echo "$BEFORE" | jq -S 'del(.cancel_after_seconds,.query_time_range_limit)') <(echo "$AFTER" | jq -S 'del(.cancel_after_seconds,.query_time_range_limit)') >/dev/null && echo si || echo NO)"

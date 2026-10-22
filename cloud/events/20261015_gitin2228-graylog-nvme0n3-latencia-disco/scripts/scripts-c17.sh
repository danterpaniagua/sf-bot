#!/usr/bin/env bash
# C17 (solo lectura) - configuracion de busqueda de Graylog SmartCloud: limite de rango de tiempo de las consultas y opciones relacionadas.
# Lee la version del servidor y el objeto cluster_config de SearchesClusterConfig (ruta vista en el log de nginx). No escribe nada.
# Se ejecuta desde la estacion local. Requiere GRAYLOG_API_KEY y jq. Salida a stdout.
# Uso: bash scripts-c17.sh > data/c17-graylog-search-settings.json
set -u
BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
[ -n "${GRAYLOG_API_KEY:-}" ] || { echo "ABORTA: GRAYLOG_API_KEY no definida" >&2; exit 1; }
get() { curl -s --max-time 60 -u "$GRAYLOG_API_KEY:token" -H 'Accept: application/json' "$BASE/$1"; }
V=$(get 'system' | jq -c '{version, hostname, is_processing}' 2>/dev/null || echo '"ERR: no se pudo leer /system"')
C=$(get 'system/cluster_config/org.graylog2.indexer.searches.SearchesClusterConfig')
echo "$C" | jq -e . >/dev/null 2>&1 || { echo "ERR: SearchesClusterConfig no devolvio JSON valido" ; echo "$C" | head -c 300; exit 1; }
jq -n --arg ts "$(date -u +%FT%TZ)" --argjson version "$V" --argjson searches "$C" \
  '{consultado_utc: $ts, servidor: $version, SearchesClusterConfig: $searches}'

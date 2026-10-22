#!/usr/bin/env bash
# C10 (solo lectura) - valores reales de AppLevel (y de campos de nivel alternativos) por servicio, en una muestra de mensajes de la ultima hora.
# No guarda el texto de los mensajes: solo cuenta los valores de los campos de nivel.
# Se ejecuta desde la estacion local. Requiere GRAYLOG_API_KEY y jq. Salida a stdout.
# Uso: bash scripts-c10.sh > data/c10-graylog-level-values.txt
set -u
BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
[ -n "${GRAYLOG_API_KEY:-}" ] || { echo "ABORTA: GRAYLOG_API_KEY no definida" >&2; exit 1; }
SERVICES="SMARTFRAN-CLOUD-ADMIN-PRO SMARTFRAN-CLOUD-BUSINESS-PRO SMARTFRAN-CLOUD-CATALOG-PRO SMARTFRAN-CLOUD-ORDERS-PRO SMARTFRAN-CLOUD-PERSON-PRO SMARTFRAN-CLOUD-PLATFORM-PRO SMARTFRAN-CLOUD-POS-PRO SMARTFRAN-CLOUD-SALES-PRO"
echo "# $(date -u +%FT%TZ) | muestra: hasta 500 mensajes de la ultima hora por servicio"
for S in $SERVICES; do
  echo "$(date -u +%T) consultando $S" >&2
  echo "== $S"
  curl -s --max-time 180 -u "$GRAYLOG_API_KEY:token" -H 'Accept: application/json' \
    --data-urlencode "query=name:$S" --data-urlencode 'range=3600' --data-urlencode 'limit=500' \
    --data-urlencode 'fields=AppLevel,Level,level,LogLevel,name' \
    -G "$BASE/search/universal/relative" \
  | jq -r '
      if .messages == null then "ERR: respuesta sin messages"
      else
        (.messages | length) as $n
        | "mensajes en la muestra: \($n)",
          ( [ .messages[].message | {a: (.AppLevel // "<ausente>"), l: (.Level // .level // .LogLevel // "<ausente>")} ]
            | group_by([.a, .l]) | map("AppLevel=\(.[0].a)\tLevel/level/LogLevel=\(.[0].l)\tn=\(length)") | .[] )
      end' 2>&1
done

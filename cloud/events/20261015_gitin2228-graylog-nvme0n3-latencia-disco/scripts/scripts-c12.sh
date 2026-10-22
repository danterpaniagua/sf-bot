#!/usr/bin/env bash
# C12 (solo lectura) - que son los mensajes AppLevel=Unknown: campos que traen, SourceContext y largo de message, por servicio.
# Muestra de hasta 200 mensajes de la ultima hora por servicio. NO imprime ningun texto de mensaje: solo nombres de campo,
# valores de SourceContext (nombres de clase) y largos.
# Se ejecuta desde la estacion local. Requiere GRAYLOG_API_KEY y jq. Salida a stdout.
# Uso: bash scripts-c12.sh > data/c12-graylog-unknown-sample.txt
set -u
BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
[ -n "${GRAYLOG_API_KEY:-}" ] || { echo "ABORTA: GRAYLOG_API_KEY no definida" >&2; exit 1; }
SERVICES="SMARTFRAN-CLOUD-ADMIN-PRO SMARTFRAN-CLOUD-BUSINESS-PRO SMARTFRAN-CLOUD-CATALOG-PRO SMARTFRAN-CLOUD-ORDERS-PRO SMARTFRAN-CLOUD-PERSON-PRO SMARTFRAN-CLOUD-PLATFORM-PRO SMARTFRAN-CLOUD-POS-PRO SMARTFRAN-CLOUD-SALES-PRO"
echo "# $(date -u +%FT%TZ) | muestra: hasta 200 mensajes AppLevel=Unknown de la ultima hora por servicio"
for S in $SERVICES; do
  echo "$(date -u +%T) consultando $S" >&2
  echo "== $S"
  curl -s --max-time 180 -u "$GRAYLOG_API_KEY:token" -H 'Accept: application/json' \
    --data-urlencode "query=name:$S AND AppLevel:\"Unknown\"" --data-urlencode 'range=3600' --data-urlencode 'limit=200' \
    -G "$BASE/search/universal/relative" \
  | jq -r '
      if .messages == null then "ERR: respuesta sin messages"
      else
        [.messages[].message] as $m
        | "mensajes en la muestra: \($m|length)",
          "-- campos presentes (nombre: cantidad de mensajes que lo traen)",
          ( [ $m[] | keys[] ] | group_by(.) | map("\(.[0]): \(length)") | .[] ),
          "-- SourceContext (valor: cantidad; hasta 10)",
          ( [ $m[] | (.SourceContext // "<ausente>") ] | group_by(.) | map({v:.[0], n:length}) | sort_by(-.n) | .[0:10][] | "\(.v): \(.n)" ),
          "-- largo de message (caracteres)",
          ( [ $m[] | ((.message // "") | length) ] | sort
            | if length == 0 then "sin datos" else "min=\(.[0]) mediana=\(.[length/2|floor]) max=\(.[-1]) vacios=\([.[]|select(.==0)]|length)" end )
      end' 2>&1
done

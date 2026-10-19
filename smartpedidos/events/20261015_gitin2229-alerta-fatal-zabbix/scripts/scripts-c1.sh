#!/usr/bin/env bash
# Event: 20261015_gitin2229-alerta-fatal-zabbix
# C1 - SOLO LECTURA contra la API REST de Graylog de SmartPedidos (sf-monitoreo.smartfran.com:9000). Token en $SML_GRAYLOG_API_KEY (nunca literal).
#      Opcion elegida por el usuario: item HTTP agent de Zabbix que consulta esta API con el token. Este script prueba las consultas candidatas con rango relativo
#      (search/universal/relative, la misma forma que usaria Zabbix) y guarda SOLO los conteos y la forma de la respuesta (claves), no el texto de los mensajes.
#      Salidas en data/c1/: counts.tsv, shape-<n>.txt
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${SML_GRAYLOG_API_KEY:?definir SML_GRAYLOG_API_KEY en el entorno}"
BASE="http://sf-monitoreo.smartfran.com:9000/api"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261015_gitin2229-alerta-fatal-zabbix/data/c1"
mkdir -p "$OUT"
q() { # $1 etiqueta, $2 consulta, $3 rango en segundos
  curl -sS -G -u "$SML_GRAYLOG_API_KEY:token" -H 'Accept: application/json' "$BASE/search/universal/relative" \
    --data-urlencode "query=$2" --data-urlencode "range=$3" --data-urlencode "limit=1" --data-urlencode "fields=timestamp,level" -o "$OUT/raw-$1.json" -w '%{http_code}'
}
printf 'etiqueta\tconsulta\trango_s\thttp\ttotal_results\n' > "$OUT/counts.tsv"
n=0
while IFS='|' read -r label query; do
  for range in 300 3600 50400; do
    n=$((n+1))
    code=$(q "$label-$range" "$query" "$range" || echo curl-fallo)
    total=$(jq -r '.total_results // "sin-campo"' "$OUT/raw-$label-$range.json" 2>/dev/null || echo "no-json")
    printf '%s\t%s\t%s\t%s\t%s\n' "$label" "$query" "$range" "$code" "$total" >> "$OUT/counts.tsv"
  done
done <<'QRY'
a-fatal-texto|"[INFRA/FATAL]" AND "platforms-service"
b-fatal-unhandled|"[INFRA/FATAL] unhandled_rejection"
c-level-fatal|level:FATAL AND "platforms-service"
d-fatal-solo|"[INFRA/FATAL]"
QRY
cat "$OUT/counts.tsv"
echo; echo "== forma de la respuesta (claves de primer nivel y de un mensaje; sin valores)"
f="$OUT/raw-a-fatal-texto-50400.json"
jq -r 'keys|join(",")' "$f"
jq -r '(.messages[0].message // {}) | keys | join(",")' "$f" 2>/dev/null || true
rm -f "$OUT"/raw-*.json
echo "(los raw-*.json se borraron del directorio de salida: solo quedan los conteos)"
echo listo

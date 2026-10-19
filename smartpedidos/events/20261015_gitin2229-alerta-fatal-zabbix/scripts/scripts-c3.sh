#!/usr/bin/env bash
# Event: 20261015_gitin2229-alerta-fatal-zabbix
# C3 - SOLO LECTURA contra la API REST de Graylog de SmartPedidos. Token en $SML_GRAYLOG_API_KEY (nunca literal).
#      C1 dejo sin capturar la forma de una respuesta correcta (la consulta "a" dio HTTP 500). Este script pide la consulta "[INFRA/FATAL]" (rango 14 h, limit=1)
#      y muestra SOLO claves y tipos: claves de primer nivel, tipo de total_results y claves de un mensaje (sin valores). Tambien repite la consulta "a" y prueba seis
#      formas de escribir la consulta con el servicio (la "a" de C1 dio 500); en caso de error muestra 300 caracteres del cuerpo (mensaje de error, sin datos de mensajes).
#      Salida en data/c3/shape.txt
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${SML_GRAYLOG_API_KEY:?definir SML_GRAYLOG_API_KEY en el entorno}"
BASE="http://sf-monitoreo.smartfran.com:9000/api"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261015_gitin2229-alerta-fatal-zabbix/data/c3"
mkdir -p "$OUT"; T=$(mktemp)
get() { curl -sS -G -u "$SML_GRAYLOG_API_KEY:token" -H 'Accept: application/json' "$BASE/search/universal/relative" --data-urlencode "query=$1" --data-urlencode "range=$2" --data-urlencode "limit=1" -o "$T" -w '%{http_code}'; }
{
  code=$(get '"[INFRA/FATAL]"' 50400); echo "consulta d (14 h): HTTP $code"
  echo "claves de primer nivel: $(jq -r 'keys|join(",")' "$T")"
  echo "tipo de total_results: $(jq -r '.total_results|type' "$T") | valor: $(jq -r '.total_results' "$T")"
  echo "claves de un mensaje: $(jq -r '(.messages[0].message // {})|keys|join(",")' "$T")"
  echo "campo level presente en el mensaje: $(jq -r '(.messages[0].message // {})|has("level")' "$T") | tipo: $(jq -r '(.messages[0].message.level // null)|type' "$T")"
  echo; echo "== formas de escribir la consulta con el servicio (rango 14 h): HTTP | total_results | cuerpo si no es 200 (300 caracteres)"
  while IFS= read -r q; do
    code=$(get "$q" 50400 || echo curl-fallo)
    if [ "$code" = "200" ]; then echo "$code | $(jq -r '.total_results' "$T") | $q"; else echo "$code | - | $q | $(head -c 300 "$T" | tr '\n' ' ')"; fi
  done <<'QRY'
"[INFRA/FATAL]" AND "platforms-service"
"platforms-service" AND "[INFRA/FATAL]"
"[INFRA/FATAL] unhandled_rejection" AND "platforms-service"
+"[INFRA/FATAL]" +"platforms-service"
message:"[INFRA/FATAL]" AND "platforms-service"
"[INFRA/FATAL]" AND platforms-service
QRY
} > "$OUT/shape.txt" 2>&1
rm -f "$T"; cat "$OUT/shape.txt"; echo listo

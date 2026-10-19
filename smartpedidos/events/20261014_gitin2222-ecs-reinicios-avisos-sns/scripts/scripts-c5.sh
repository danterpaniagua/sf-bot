#!/usr/bin/env bash
# Event: 20261014_gitin2222-ecs-reinicios-avisos-sns
# C5 - SOLO LECTURA contra sf-monitoreo.smartfran.com:9000 (Graylog de SmartPedidos). Token en $SML_GRAYLOG_API_KEY (nunca literal).
#      C3 mostro que las tareas de platform-service se detienen con stopCode EssentialContainerExited (el contenedor sale solo, exit code 1), no por deploy, escalado ni health check.
#      Este script trae los mensajes de platforms-service de los ~2 minutos previos a cada detencion y muestra los de nivel error / palabras de caida, para ver que paso antes de la salida.
#      Ventanas (hora UTC, de data/c3-stopped-20261015T003522Z.json: stoppedAt -03:00 + 3 h) y 3 reemplazos vistos en los eventos del servicio (21:15:48, 21:16:17, 21:31:20 -03:00).
#      Salidas en data/c5/: detail-<ventana>.json (mensajes crudos, pueden tener datos de ordenes/cuentas; .json esta excluido de git por **.json -- no pegarlos ni subirlos) y resumen-<ventana>.tsv (enmascarado: correos y numeros de 7+ digitos).
#      Consultas segun docs/graylog_infrastructure.md: solo GET search/universal/absolute, fechas ISO con Z, una frase entre comillas.
# Uso:  mkdir -p <ruta>/data/c5 && bash <ruta>/scripts-c5.sh > <ruta>/data/c5/pull-log.txt 2>&1
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${SML_GRAYLOG_API_KEY:?definir SML_GRAYLOG_API_KEY en el entorno}"
BASE="http://sf-monitoreo.smartfran.com:9000/api"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/data/c5"
SVC='"platforms-service"'
BEFORE=120; AFTER=15
WINDOWS="s2044 2026-10-14T23:44:38Z
s2048 2026-10-14T23:48:28Z
s2109 2026-10-15T00:09:46Z
s2121a 2026-10-15T00:21:33Z
s2121b 2026-10-15T00:21:38Z
d2115 2026-10-15T00:15:48Z
d2116 2026-10-15T00:16:17Z
d2131 2026-10-15T00:31:20Z"
mkdir -p "$OUT"
fmt() { date -u -d "@$1" +"%Y-%m-%dT%H:%M:%S.000Z"; }
mask() { sed -E 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]+/[correo]/g; s/[0-9]{7,}/[num]/g'; }
KEYS='uncaught|unhandled|fatal|exception|sigterm|sigint|exit|econn|etimedout|enotfound|mongo|enomem|heap|crash|reject|panic|abort|terminat'

probe=$(curl -sS -G -u "$SML_GRAYLOG_API_KEY:token" -H 'Accept: application/json' "$BASE/search/universal/absolute" \
  --data-urlencode "query=$SVC" --data-urlencode "from=$(fmt $(( $(date +%s) - 600 )))" --data-urlencode "to=$(fmt "$(date +%s)")" --data-urlencode "limit=1" --data-urlencode "fields=timestamp")
echo "prueba: mensajes de platforms-service en los ultimos 10 min = $(jq -r '.total_results' <<<"$probe")"

# 0) El codigo de platforms-service (api/src/index.js, desde el commit b56d403 del 2026-10-08) registra [INFRA/FATAL] unhandled_rejection / uncaught_exception y sale con process.exit(1).
#    Se buscan esos mensajes en las ultimas 14 horas (una consulta por termino: Graylog responde 500 a las consultas con OR/AND).
NOW=$(date +%s); FROM0=$((NOW - 14*3600))
for TERM in unhandled_rejection uncaught_exception; do
  code=$(curl -sS -G -u "$SML_GRAYLOG_API_KEY:token" -H 'Accept: application/json' -o "$OUT/detail-fatal-$TERM.json" -w '%{http_code}' "$BASE/search/universal/absolute" \
    --data-urlencode "query=\"$TERM\"" --data-urlencode "from=$(fmt "$FROM0")" --data-urlencode "to=$(fmt "$NOW")" --data-urlencode "limit=500" \
    --data-urlencode "fields=timestamp,source,message" --data-urlencode "sort=timestamp:asc") || code=curl-fallo
  echo "== FATAL \"$TERM\" ultimas 14 h HTTP=$code"
  [ "$code" = 200 ] || { head -c 300 "$OUT/detail-fatal-$TERM.json"; echo; continue; }
  echo "   coincidencias: $(jq -r '.total_results' "$OUT/detail-fatal-$TERM.json") (devueltas $(jq -r '.messages|length' "$OUT/detail-fatal-$TERM.json"), limite 500)"
  jq -r '.messages[].message as $m | ($m.message | fromjson? // {message: $m.message}) as $j
     | [$m.timestamp[0:19], ($j.level // "-" | tostring), (($j.message // "") | tostring)[0:60], (($j.rest // {}) | tostring | gsub("[\t\n]"; " "))[0:260]] | @tsv' "$OUT/detail-fatal-$TERM.json" | mask > "$OUT/resumen-fatal-$TERM.tsv"
  echo "   por hora (UTC):"; cut -c1-13 "$OUT/resumen-fatal-$TERM.tsv" | LC_ALL=C sort | uniq -c | sed 's/^/      /'
  echo "   mensajes de error mas frecuentes (campo rest, 120 caracteres, enmascarado):"
  cut -f4 "$OUT/resumen-fatal-$TERM.tsv" | cut -c1-120 | LC_ALL=C sort | uniq -c | LC_ALL=C sort -rn | head -8 | sed 's/^/      /'
done

while read -r label stop; do
  [ -n "$label" ] || continue
  t=$(date -u -d "$stop" +%s); f=$((t - BEFORE)); to=$((t + AFTER))
  code=$(curl -sS -G -u "$SML_GRAYLOG_API_KEY:token" -H 'Accept: application/json' -o "$OUT/detail-$label.json" -w '%{http_code}' "$BASE/search/universal/absolute" \
    --data-urlencode "query=$SVC" --data-urlencode "from=$(fmt "$f")" --data-urlencode "to=$(fmt "$to")" --data-urlencode "limit=3000" \
    --data-urlencode "fields=timestamp,source,message" --data-urlencode "sort=timestamp:asc") || code=curl-fallo
  echo "== $label parada=$stop ventana=$(fmt "$f")..$(fmt "$to") HTTP=$code"
  [ "$code" = 200 ] || { head -c 300 "$OUT/detail-$label.json"; echo; continue; }
  total=$(jq -r '.total_results' "$OUT/detail-$label.json"); got=$(jq -r '.messages|length' "$OUT/detail-$label.json")
  echo "   mensajes: total=$total devueltos=$got$( [ "$got" -lt "$total" ] && echo '  (INCOMPLETO: se alcanzo el limite 3000)')"
  # mensajes con nivel error o palabras de caida; la columna message es JSON (timestamp, service, level, category, message)
  jq -r --arg keys "$KEYS" '.messages[].message as $m
     | ($m.message | fromjson? // {message: $m.message}) as $j
     | select((($j.level // "") | tostring | test("err|fatal|crit|warn"; "i")) or ((($j.message // "") | tostring) | test($keys; "i")))
     | [$m.timestamp[11:23], ($m.source // "-"), (($j.level // "-") | tostring), (($j.category // "-") | tostring), ((($j.message // "") | tostring | gsub("[\t\n]"; " "))[0:220])] | @tsv' \
     "$OUT/detail-$label.json" | mask > "$OUT/resumen-$label.tsv"
  echo "   lineas error/warn/palabras de caida: $(wc -l < "$OUT/resumen-$label.tsv")"
  echo "   niveles presentes (todos los mensajes):"
  jq -r '.messages[].message.message | (fromjson? // {}) | (.level // "-") | tostring' "$OUT/detail-$label.json" | LC_ALL=C sort | uniq -c | LC_ALL=C sort -rn | head -6 | sed 's/^/      /'
  echo "   ultimas 12 lineas error/warn/caida antes de la parada (hora UTC, origen, nivel, categoria, mensaje enmascarado):"
  tail -12 "$OUT/resumen-$label.tsv" | cut -c1-300 | sed 's/^/      /'
done <<<"$WINDOWS"
echo listo

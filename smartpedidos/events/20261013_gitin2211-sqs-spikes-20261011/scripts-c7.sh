#!/usr/bin/env bash
# Event: 20261013_sqs-spikes-20261011
# C7 — Solo lectura contra sf-monitoreo.smartfran.com:9000 (Graylog 5.2.12 de SmartPedidos; token en $SML_GRAYLOG_API_KEY, nunca literal).
#      Objetivo (alcance del usuario): por que la cola PRD_BranchMessages.fifo tiene mensajes de ~200 s o mas. El 2026-10-11 el consumo
#      se detuvo 21:58-22:02 locales (UTC-3). Aqui: que registra platforms-service por minuto antes, durante y despues, para ver si
#      se calla, si registra errores/timeouts de SQS o Mongo, o si ocurre otra cosa a la vez.
#      Consulta: la frase "platforms-service" (una sola frase; las consultas booleanas devuelven HTTP 500 en este Graylog).
#      Por minuto: total de mensajes y hasta LIMIT mensajes (timestamp, message) en archivos detail-* (excluidos del control de
#      versiones: pueden traer datos de pedidos). El resumen agrupa por nivel, categoria y texto normalizado (digitos y uuid -> #).
# Uso:  DAY=2026-10-11 FROM=21:50 TO=22:10 TAG=evento bash scripts-c7.sh > data/c7-evento-summary.txt 2>&1
#       Control (franja tranquila): DAY=2026-10-11 FROM=21:20 TO=21:40 TAG=control ...
set -uo pipefail
: "${SML_GRAYLOG_API_KEY:?definir SML_GRAYLOG_API_KEY en el entorno}"
BASE="http://sf-monitoreo.smartfran.com:9000/api"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261013_sqs-spikes-20261011/data"
DAY="${DAY:-2026-10-11}"; FROM="${FROM:-21:50}"; TO="${TO:-22:10}"; TAG="${TAG:-evento}"; LIMIT="${LIMIT:-3000}"
QUERY='"platforms-service"'
fmt() { date -u -d "@$1" +"%Y-%m-%dT%H:%M:%S.000Z"; }
t0=$(date -d "$DAY $FROM:00 -0300" +%s); t1=$(date -d "$DAY $TO:00 -0300" +%s)
gl() { curl -sS -G -u "$SML_GRAYLOG_API_KEY:token" -H 'Accept: application/json' -w '\n%{http_code}' "$BASE/search/universal/absolute" "$@"; }

echo "franja local $DAY $FROM-$TO ($(fmt $t0) a $(fmt $t1) UTC), consulta $QUERY, limite $LIMIT por minuto"
echo "minuto_local total traidos http"
t=$t0
while [ "$t" -lt "$t1" ]; do
  e=$((t + 60)); hhmm=$(date -d "@$t" +%H%M)
  resp=$(gl --data-urlencode "query=$QUERY" --data-urlencode "from=$(fmt $t)" --data-urlencode "to=$(fmt $e)" \
        --data-urlencode "limit=$LIMIT" --data-urlencode "fields=timestamp,message" --data-urlencode "sort=timestamp:asc")
  code=$(tail -n1 <<<"$resp"); body=$(sed '$d' <<<"$resp")
  printf '%s' "$body" > "$OUT/detail-c7-$TAG-min-$hhmm.json"
  if [ "$code" = 200 ]; then
    printf '%s %s %s %s\n' "$(date -d "@$t" +%H:%M)" "$(jq -r '.total_results' <<<"$body")" "$(jq -r '.messages|length' <<<"$body")" "$code"
  else
    printf '%s - - %s\n' "$(date -d "@$t" +%H:%M)" "$code"
  fi
  t=$e
done

echo
echo "== textos mas frecuentes por minuto (nivel categoria texto normalizado)"
t=$t0
while [ "$t" -lt "$t1" ]; do
  hhmm=$(date -d "@$t" +%H%M); f="$OUT/detail-c7-$TAG-min-$hhmm.json"
  echo "-- $(date -d "@$t" +%H:%M)"
  jq -r '.messages[]?.message.message
         | (try fromjson catch {level:"?",category:"?",message:.})
         | "\(.level // "?") \(.category // "?") \((.message // "")[0:90])"
         | gsub("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}";"<uuid>") | gsub("[0-9]+";"#")' "$f" 2>/dev/null \
    | sort | uniq -c | sort -rn | head -8
  t=$((t + 60))
done
echo "listo"

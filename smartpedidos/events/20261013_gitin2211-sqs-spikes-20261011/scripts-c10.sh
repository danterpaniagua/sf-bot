#!/usr/bin/env bash
# Event: 20261013_sqs-spikes-20261011
# C10 — Solo lectura contra sf-monitoreo.smartfran.com:9000 (token en $SML_GRAYLOG_API_KEY, nunca literal).
#       Repite la descarga por minuto de C7 (frase "platforms-service") alrededor de los otros 11 inicios de estancamiento de
#       PRD_BranchMessages.fifo (C4), de 3 min antes del inicio a 8 min despues. Archivos detail-c10-<fecha>-<HHMM>-min-<HHMM>.json
#       (excluidos del control de versiones). El analisis (llamadas del lado del consumidor por minuto y latencias) se hace luego en local.
#       Hora local UTC-3. Los inicios vienen de data/c4-run1-runs.txt.
# Uso:  bash scripts-c10.sh > data/c10-run1-summary.txt 2>&1
set -uo pipefail
: "${SML_GRAYLOG_API_KEY:?definir SML_GRAYLOG_API_KEY en el entorno}"
BASE="http://sf-monitoreo.smartfran.com:9000/api"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261013_sqs-spikes-20261011/data"
LIMIT=3000
STARTS="${STARTS:-2026-10-03T13:09 2026-10-03T21:43 2026-10-03T22:44 2026-10-04T11:19 2026-10-04T19:09 2026-10-04T20:15 2026-10-05T08:55 2026-10-06T21:01 2026-10-09T22:33 2026-10-10T19:42 2026-10-12T16:56}"   # override: STARTS="2026-10-13T00:30" bash scripts-c10.sh
fmt() { date -u -d "@$1" +"%Y-%m-%dT%H:%M:%S.000Z"; }
for st in $STARTS; do
  s0=$(date -d "${st/T/ } -0300" +%s); from=$((s0 - 180)); to=$((s0 + 480))
  tag="${st/T/-}"; tag="${tag//:/}"
  echo "== inicio $st local: $(date -d "@$from" +%H:%M)-$(date -d "@$to" +%H:%M)"
  t=$from
  while [ "$t" -lt "$to" ]; do
    e=$((t + 60)); hhmm=$(date -d "@$t" +%H%M)
    resp=$(curl -sS -G -u "$SML_GRAYLOG_API_KEY:token" -H 'Accept: application/json' -w '\n%{http_code}' "$BASE/search/universal/absolute" \
      --data-urlencode 'query="platforms-service"' --data-urlencode "from=$(fmt $t)" --data-urlencode "to=$(fmt $e)" \
      --data-urlencode "limit=$LIMIT" --data-urlencode "fields=timestamp,message" --data-urlencode "sort=timestamp:asc")
    code=$(tail -n1 <<<"$resp"); body=$(sed '$d' <<<"$resp")
    printf '%s' "$body" > "$OUT/detail-c10-$tag-min-$hhmm.json"
    if [ "$code" = 200 ]; then printf '  %s total=%s traidos=%s\n' "$(date -d "@$t" +%H:%M)" "$(jq -r '.total_results' <<<"$body")" "$(jq -r '.messages|length' <<<"$body")"
    else printf '  %s http=%s\n' "$(date -d "@$t" +%H:%M)" "$code"; fi
    t=$e
  done
done
echo "listo"

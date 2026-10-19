#!/usr/bin/env bash
# Event: 20261009_gitin2208-graylog-error-spikes
# C3 — Solo lectura contra sf-monitoreo.smartfran.com:9000: busca senales de reinicio/despliegue de concentrador-service
#      en las ventanas de los picos del 2026-10-09 (hora local UTC-3) y en una ventana de control sin picos:
#        W1 07:50-08:10   W2 09:00-09:35   CONTROL 10:20-10:55
#      Por ventana: (a) mensajes por minuto de concentrador-service (todos los niveles; una caida a cero y un retorno
#      indican reinicio), (b) mensajes con palabras de arranque/cierre (database_connected, listening, started, SIGTERM,
#      shutdown...), hasta 300 por ventana, solo timestamp/source/message.
# Salidas en data/restarts/. Token en $SML_GRAYLOG_API_KEY (nunca literal).
# Uso:  mkdir -p <ruta>/data/restarts && bash <ruta>/scripts-restarts.sh > <ruta>/data/restarts/pull-log.txt 2>&1
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR

: "${SML_GRAYLOG_API_KEY:?definir SML_GRAYLOG_API_KEY en el entorno}"
BASE="http://sf-monitoreo.smartfran.com:9000/api"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261009_gitin2208-graylog-error-spikes/data/restarts"
DAY="${DAY:-2026-10-09}"
SVC="${SVC:-\"concentrador-service\"}"
TERMS="${TERMS:-database_connected listening started starting startup SIGTERM SIGINT shutdown graceful bootstrap}"   # un termino por consulta
WINDOWS="${WINDOWS:-w1 w2 control}"; MINUTES_FOR="${MINUTES_FOR:-w1 w2 control}"   # ventanas a correr / a las que se les cuenta por minuto
mkdir -p "$OUT"

fmt() { date -u -d "@$1" +"%Y-%m-%dT%H:%M:%S.000Z"; }
at() { date -d "$DAY $1:00 -0300" +%s; }
gl() { curl -sS -f -G -u "$SML_GRAYLOG_API_KEY:token" -H 'Accept: application/json' "$BASE/$1" "${@:2}"; }
search() { # search <query> <desde> <hasta> <limite> <campos>
  gl search/universal/absolute --data-urlencode "query=$1" --data-urlencode "from=$(fmt "$2")" --data-urlencode "to=$(fmt "$3")" \
     --data-urlencode "limit=$4" --data-urlencode "fields=$5" --data-urlencode "sort=timestamp:asc"
}

probe=$(search "$SVC" $(( $(date +%s) - 600 )) "$(date +%s)" 1 timestamp)
echo "prueba: mensajes de $SVC en los ultimos 10 min = $(jq -r '.total_results' <<<"$probe")  | newest(UTC)=$(jq -r '.messages[0].message.timestamp // "ninguno"' <<<"$probe")"

try_search() { # try_search <query> <desde> <hasta> <limite> <campos> -> JSON, o {"error":...} si Graylog responde distinto de 200
  local resp code body
  resp=$(curl -sS -G -u "$SML_GRAYLOG_API_KEY:token" -H 'Accept: application/json' -w $'\n%{http_code}' "$BASE/search/universal/absolute" \
     --data-urlencode "query=$1" --data-urlencode "from=$(fmt "$2")" --data-urlencode "to=$(fmt "$3")" \
     --data-urlencode "limit=$4" --data-urlencode "fields=$5" --data-urlencode "sort=timestamp:asc") || { echo '{"error":"curl fallo"}'; return 0; }
  code="${resp##*$'\n'}"; body="${resp%$'\n'*}"
  if [ "$code" = 200 ]; then echo "$body"; else jq -nc --arg c "$code" --arg b "${body:0:300}" '{error:("HTTP "+$c), body:$b}'; fi
}

run_window() { # run_window <etiqueta> <hh:mm-inicio> <hh:mm-fin>
  local label="$1" t0 t1; t0=$(at "$2"); t1=$(at "$3")
  echo "== $label $2-$3 local ($(fmt "$t0") .. $(fmt "$t1"))"
  case " $MINUTES_FOR " in *" $label "*)
    : > "$OUT/perminute-$label.tsv"
    local t="$t0"
    while [ "$t" -lt "$t1" ]; do
      local n; n=$(search "$SVC" "$t" $((t + 60)) 1 timestamp | jq -r '.total_results')
      printf '%s\t%s\n' "$(date -d "@$t" +%H:%M)" "$n" >> "$OUT/perminute-$label.tsv"
      t=$((t + 60))
    done
    echo "   minutos=$(wc -l < "$OUT/perminute-$label.tsv")";;
  esac
  : > "$OUT/startup-terms-$label.tsv"
  for term in $TERMS; do
    r=$(try_search "$SVC AND $term" "$t0" "$t1" 20 "timestamp,source,message")
    if [ "$(jq -r 'has("error")' <<<"$r")" = true ]; then
      printf '%s\tERROR\t%s\t%s\n' "$term" "$(jq -r '.error' <<<"$r")" "$(jq -r '.body // ""' <<<"$r" | tr '\t\n' '  ' | cut -c1-200)" >> "$OUT/startup-terms-$label.tsv"
    else
      printf '%s\t%s\n' "$term" "$(jq -r '.total_results' <<<"$r")" >> "$OUT/startup-terms-$label.tsv"
      [ "$(jq -r '.total_results' <<<"$r")" != 0 ] && jq -c --arg term "$term" '{term:$term, total:.total_results, messages:[.messages[].message | {timestamp, source, message}]}' <<<"$r" >> "$OUT/startup-messages-$label.jsonl"
    fi
  done
  echo "   terminos (termino, total):" ; sed 's/^/     /' "$OUT/startup-terms-$label.tsv"
}
for w in $WINDOWS; do
  case "$w" in w1) run_window w1 07:50 08:10;; w2) run_window w2 09:00 09:35;; control) run_window control 10:20 10:55;; esac
done
echo "listo"

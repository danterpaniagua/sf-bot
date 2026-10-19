#!/usr/bin/env bash
# Event: 20261008_mobile-spike-detection-effectiveness
# C1 — Solo lectura contra la API de Zabbix: triggers de MOBI (IIS Spike 26742-26747 y colapso 26898),
#      sus items, historial, eventos y alertas de la ventana. Salidas en data/.
# Uso (ZABBIX_API_KEY definida en el entorno, nunca literal; ajustar DAY/START/END/PAD si hace falta):
#   DAY=2026-10-08 START=14:00 END=15:00 bash <ruta>/scripts.sh > <ruta>/data/pull-log.txt 2>&1
#   Macros vivas (solo lectura): ONLY_MACROS=1 OUT=<ruta>/data/macros bash <ruta>/scripts.sh > <ruta>/data/macros/pull-log.txt 2>&1
#   Corrida 3 (14 dias): OUT=<ruta>/data/run3-14d FROM_DAY=2026-09-25 TO_DAY=2026-10-08 PAD=0 bash <ruta>/scripts.sh > <ruta>/data/run3-14d/pull-log.txt 2>&1
#   Corrida 2 (todo el dia): OUT=<ruta>/data/run2-dia DAY=2026-10-08 START=00:00 END=17:30 PAD=0 bash <ruta>/scripts.sh > <ruta>/data/run2-dia/pull-log.txt 2>&1
# C2 — scripts-burst-apply.sh: MODIFICA ZABBIX (2 macros globales + 2 triggers 'IIS Spike - Burst'); guardas antes de escribir, snapshots en data/burst-apply/
# C3 — scripts-burst-rollback.sh: MODIFICA ZABBIX (borra solo lo registrado en data/burst-apply/created-ids.json)
# C4 — scripts-action7.sh: solo lectura de la accion 7 (operaciones, recuperacion, escalamiento, filtro) y sus envios; salidas en data/action7/
set -euo pipefail

: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
URL="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="${OUT:-/home/dpaniagua/Documentos/git/bots/operations/events/20261008_mobile-spike-detection-effectiveness/data}"   # OUT distinto para no pisar una corrida anterior
mkdir -p "$OUT"
DAY="${DAY:-2026-10-08}"; START="${START:-14:00}"; END="${END:-15:00}"; PAD="${PAD:-1800}"   # hora local UTC-3, PAD en segundos
TRIGGERS='["26742","26743","26744","26745","26746","26747","26898"]'

if [ -n "${FROM_DAY:-}" ] && [ -n "${TO_DAY:-}" ]; then   # rango de dias completos (hora local UTC-3); el fin se acota a "ahora"
  T0=$(date -d "$FROM_DAY 00:00:00 -0300" +%s); T1=$(date -d "$TO_DAY 23:59:59 -0300" +%s)
  NOW=$(date +%s); [ "$T1" -gt "$NOW" ] && T1=$NOW
  DAY="$FROM_DAY..$TO_DAY"; START="00:00"; END="23:59"
else
  T0=$(date -d "$DAY $START:00 -0300" +%s); T1=$(date -d "$DAY $END:00 -0300" +%s)
fi
F=$((T0 - PAD)); T=$((T1 + PAD))
echo "ventana UTC-3 ${DAY} ${START}-${END}  epoch ${T0}-${T1}  con margen de ${PAD}s: ${F}-${T}"
echo "{\"day\":\"$DAY\",\"start\":\"$START\",\"end\":\"$END\",\"pad_seconds\":$PAD,\"t0\":$T0,\"t1\":$T1,\"from\":$F,\"to\":$T}" > "$OUT/window.json"

zbx() { # zbx <metodo> <params-json>  -> imprime .result o aborta con el error de la API
  jq -n --arg auth "$ZABBIX_API_KEY" --arg m "$1" --argjson p "$2" \
    '{jsonrpc:"2.0",id:1,method:$m,params:$p,auth:$auth}' \
  | curl -sS -H 'Content-Type: application/json-rpc' --data-binary @- "$URL" \
  | jq 'if .error then ("API error: " + (.error|tostring)) | halt_error(1) else .result end'
}

# 0) Solo macros (ONLY_MACROS=1): valores vivos de los umbrales y ventanas de MOBI, en host, plantillas y globales
if [ "${ONLY_MACROS:-0}" = "1" ]; then
  zbx host.get '{"filter":{"host":["SFCG-MOBI-01","SFCG-MOBI-02"]},"output":["hostid","host"],"selectParentTemplates":["templateid","name"]}' > "$OUT/macros-hosts.json"
  HOSTIDS=$(jq -c '[.[] | .hostid, (.parentTemplates[].templateid)] | unique' "$OUT/macros-hosts.json")
  zbx usermacro.get "{\"hostids\":$HOSTIDS,\"output\":[\"hostmacroid\",\"hostid\",\"macro\",\"value\",\"type\"],\"search\":{\"macro\":[\"MOBILE_PCOUNT\",\"MOBI.COLLAPSE\",\"MOBI\"]},\"searchByAny\":true}" > "$OUT/macros-host-template.json"
  zbx usermacro.get '{"globalmacro":true,"output":["globalmacroid","macro","value","type"],"search":{"macro":["MOBILE_PCOUNT","MOBI.COLLAPSE","MOBI"]},"searchByAny":true}' > "$OUT/macros-global.json"
  echo "macros: host/plantilla $(jq 'length' "$OUT/macros-host-template.json"), globales $(jq 'length' "$OUT/macros-global.json")"
  exit 0
fi

# 1) Triggers (expresion cruda, sin expandir macros) con sus items, hosts, funciones y tags
zbx trigger.get "{\"triggerids\":$TRIGGERS,\"output\":[\"triggerid\",\"description\",\"expression\",\"recovery_expression\",\"recovery_mode\",\"priority\",\"status\",\"value\",\"lastchange\"],\"selectItems\":[\"itemid\",\"name\",\"key_\",\"value_type\",\"history\",\"delay\"],\"selectHosts\":[\"host\"],\"selectFunctions\":\"extend\",\"selectTags\":\"extend\"}" > "$OUT/triggers.json"
ITEMS=$(jq -c '[.[].items[].itemid] | unique' "$OUT/triggers.json")
echo "items: $ITEMS"

# 2) Eventos de esos triggers en la ventana (problemas y recuperaciones)
zbx event.get "{\"source\":0,\"object\":0,\"objectids\":$TRIGGERS,\"time_from\":$F,\"time_till\":$T,\"output\":\"extend\",\"select_acknowledges\":\"count\",\"sortfield\":[\"clock\",\"eventid\"],\"sortorder\":\"ASC\"}" > "$OUT/events.json"
EVENTIDS=$(jq -c '[.[].eventid]' "$OUT/events.json")
echo "eventos: $(jq 'length' "$OUT/events.json")"

# 3) Intentos de notificacion de esos eventos (sin sendto ni mensaje)
if [ "$(jq 'length' "$OUT/events.json")" -gt 0 ]; then
  zbx alert.get "{\"eventids\":$EVENTIDS,\"output\":[\"alertid\",\"actionid\",\"eventid\",\"clock\",\"mediatypeid\",\"status\",\"retries\",\"error\",\"esc_step\",\"alerttype\"],\"sortfield\":\"clock\",\"sortorder\":\"ASC\"}" > "$OUT/alerts.json"
else
  echo '[]' > "$OUT/alerts.json"
fi
echo "alertas: $(jq 'length' "$OUT/alerts.json")"

# 4) Historial de los items en la ventana, por tipo de valor (0 flotante, 3 entero sin signo)
for vt in 0 3; do
  IDS=$(jq -c "[.[].items[] | select(.value_type==\"$vt\") | .itemid] | unique" "$OUT/triggers.json")
  if [ "$IDS" != "[]" ]; then
    zbx history.get "{\"history\":$vt,\"itemids\":$IDS,\"time_from\":$F,\"time_till\":$T,\"output\":\"extend\",\"sortfield\":\"clock\",\"sortorder\":\"ASC\"}" > "$OUT/history-type$vt.json"
    echo "historial tipo $vt: $(jq 'length' "$OUT/history-type$vt.json") muestras"
  fi
done
echo "listo"

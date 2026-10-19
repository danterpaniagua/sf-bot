#!/usr/bin/env bash
# Event: 20261015_gitin2228-graylog-nvme0n3-latencia-disco
# C2 - SOLO LECTURA contra la API de Zabbix (sf-monitoreo.smartfran.com:8080, 6.0.32; token en $ZABBIX_API_KEY).
#      Busca el host "Cloud Graylog", los items cuyo nombre/clave contienen nvme0n3 (await de lectura/escritura), su historia
#      en la ventana 08:00-09:00 hora local (-03:00 = 11:00-12:00 UTC; si la hora de la alerta es otra, cambiar DESDE/HASTA) y los eventos de ese trigger de hoy.
#      Salidas en data/c2/: items.json, history-<itemid>.json, events.json, resumen en stdout.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/cloud/events/20261015_gitin2228-graylog-nvme0n3-latencia-disco/data/c2"
mkdir -p "$OUT"
DESDE=$(date -u -d "2026-10-15 10:30:00" +%s); HASTA=$(date -u -d "2026-10-15 12:30:00" +%s)
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
call host.get '{"search":{"name":"Cloud Graylog"},"output":["hostid","name"]}' > "$OUT/host.json"
jq -r '.[]|[.hostid,.name]|@tsv' "$OUT/host.json"
HID=$(jq -r '.[0].hostid // empty' "$OUT/host.json"); [ -n "$HID" ] || { echo "GUARDA: host no encontrado"; exit 1; }
call item.get "$(jq -n --arg h "$HID" '{hostids:[$h],search:{key_:"nvme0n3"},output:["itemid","name","key_","delay","value_type","units","lastvalue","history"]}')" > "$OUT/items.json"
echo "== items nvme0n3"; jq -r '.[]|[.itemid,.name,.key_,.delay,.units,.lastvalue,("history="+.history)]|@tsv' "$OUT/items.json"
for i in $(jq -r '.[]|select(.name|test("await|read|write|r_await|w_await|queue";"i"))|.itemid' "$OUT/items.json" | head -8); do
  call history.get "$(jq -n --arg i "$i" --argjson f "$DESDE" --argjson t "$HASTA" '{itemids:[$i],history:0,time_from:$f,time_till:$t,output:["clock","value"],sortfield:"clock",sortorder:"ASC",limit:5000}')" > "$OUT/history-$i.json"
  echo "== item $i: $(jq length "$OUT/history-$i.json") puntos | max $(jq -r 'map(.value|tonumber)|max // "-"' "$OUT/history-$i.json") | puntos > 20: $(jq '[.[]|select((.value|tonumber)>20)]|length' "$OUT/history-$i.json")"
  jq -r '.[]|select((.value|tonumber)>20)|[((.clock|tonumber)-10800|strftime("%H:%M:%S -03:00")),.value]|@tsv' "$OUT/history-$i.json" | head -60
done
call event.get "$(jq -n --arg h "$HID" --argjson f "$DESDE" '{hostids:[$h],time_from:$f,output:["eventid","name","clock","r_eventid","severity"],sortfield:["clock"],sortorder:"ASC",source:0,object:0}')" > "$OUT/events.json"
echo "== eventos del host desde la ventana"; jq -r '.[]|[((.clock|tonumber)-10800|strftime("%F %T -03:00")),.severity,.name]|@tsv' "$OUT/events.json"
echo listo

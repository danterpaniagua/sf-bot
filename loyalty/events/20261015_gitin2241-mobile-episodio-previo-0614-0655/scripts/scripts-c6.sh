#!/usr/bin/env bash
# Event: 20261015_gitin2241-mobile-episodio-previo-0614-0655 (GITIN-2241)
# C6 - Zabbix 6.0.32 (sf-monitoreo.smartfran.com:8080; token en $ZABBIX_API_KEY). SOLO LECTURA (history.get con itemid explicito).
#      Recurrencia: item web.test.fail["[PROD] MobileApp"] (id 51571, un punto cada 30 s; valor distinto de 0 = paso fallido) entre 08:50 y 10:30 UTC de cada dia del 2026-10-09 al 2026-10-15
#      (una ventana por dia: el limite de lectura es 5000 puntos). Por dia: puntos devueltos, puntos con falla, primera y ultima hora con falla, valores distintos.
#      El historial de estos items puede estar recortado por retencion: un dia con 0 puntos es "sin dato", no "sin falla".
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
export LC_ALL=C
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/loyalty/events/20261015_gitin2241-mobile-episodio-previo-0614-0655/data"
TS=$(date -u +%Y%m%dT%H%M%SZ); RUN="$OUT/c6-run-$TS"; mkdir -p "$RUN"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
echo "run $TS | item 51571 web.test.fail | ventana diaria 08:50-10:30 UTC"
for d in 2026-10-09 2026-10-10 2026-10-11 2026-10-12 2026-10-13 2026-10-14 2026-10-15; do
  F=$(date -u -d "${d}T08:50:00Z" +%s); T=$(date -u -d "${d}T10:30:00Z" +%s)
  call history.get "$(jq -n --argjson f "$F" --argjson t "$T" '{history:3,itemids:["51571"],time_from:$f,time_till:$t,output:"extend",sortfield:"clock",sortorder:"ASC",limit:5000}')" > "$RUN/hist-$d.json"
  WD=$(date -u -d "$d" +%a)
  jq -r --arg d "$d" --arg wd "$WD" '[.[]|{c:(.clock|tonumber),v:.value}] as $a|[$a[]|select(.v!="0")] as $f
    | "\($d) (\($wd)): puntos=\($a|length) fallas=\($f|length) primera=\(if ($f|length)>0 then ($f[0].c|strftime("%T")) else "-" end) ultima=\(if ($f|length)>0 then ($f[-1].c|strftime("%T")) else "-" end) valores=\([$a[]|.v]|unique|join(","))"' "$RUN/hist-$d.json"
done
echo; echo "guardado en $RUN"

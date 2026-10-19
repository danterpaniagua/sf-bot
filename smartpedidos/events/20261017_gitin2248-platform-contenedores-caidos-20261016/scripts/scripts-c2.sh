#!/usr/bin/env bash
# Event: 20261017_gitin2248-platform-contenedores-caidos-20261016
# C2 - SOLO LECTURA contra la API de Zabbix (sf-monitoreo.smartfran.com:8080, 6.0.32; token en $ZABBIX_API_KEY). Dia 2026-10-16 -03:00 (03:00Z a 03:00Z del 17).
#      (1) Eventos (event.get, source 0, object 0) cuyo nombre contiene "Running tasks below desired" o "Graylog: Platform FATAL detected": hora (-03:00), valor (1 problema, 0 recuperacion) y nombre. Se imprime la cantidad.
#      (2) Historia del item 54607 (conteo de lineas FATAL de platforms-service en los ultimos 5 min, cada minuto, host "Zabbix server"): puntos, minutos con valor > 0, maximo y episodios (tramos continuos con valor > 0).
#      Un resultado vacio se contrasta con el conteo de puntos: 0 puntos es "sin dato", no "sin eventos". Salidas en data/c2/.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
export LC_ALL=C
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261017_gitin2248-platform-contenedores-caidos-20261016/data/c2"
mkdir -p "$OUT"
FROM=$(date -u -d "2026-10-16T03:00:00Z" +%s); TILL=$(date -u -d "2026-10-17T03:00:00Z" +%s)
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
echo "run $(date -u +%FT%TZ) | ventana $FROM-$TILL"
for n in "Running tasks below desired" "Graylog: Platform FATAL detected"; do
  call event.get "$(jq -n --arg n "$n" --argjson f "$FROM" --argjson t "$TILL" '{source:0,object:0,time_from:$f,time_till:$t,search:{name:$n},output:["eventid","clock","value","name","objectid"],sortfield:["clock","eventid"],sortorder:"ASC",limit:1000}')" > "$OUT/events-$(echo "$n" | tr -c 'A-Za-z0-9' '_').json"
  f="$OUT/events-$(echo "$n" | tr -c 'A-Za-z0-9' '_').json"
  echo; echo "== eventos \"$n\": $(jq length "$f") (problemas $(jq '[.[]|select(.value=="1")]|length' "$f"), recuperaciones $(jq '[.[]|select(.value=="0")]|length' "$f"))"
  jq -r '.[]|[((.clock|tonumber-10800)|strftime("%m-%d %H:%M:%S")),(if .value=="1" then "PROBLEMA" else "recuperado" end),.name]|@tsv' "$f" | head -80
done
echo; echo "== item 54607: tipo y datos"
call item.get '{"itemids":["54607"],"output":["itemid","key_","value_type","delay","lastvalue","lastclock"],"selectHosts":["host"]}' > "$OUT/item-54607.json"; jq -c '.[0]' "$OUT/item-54607.json"
VT=$(jq -r '.[0].value_type' "$OUT/item-54607.json")
call history.get "$(jq -n --argjson vt "$VT" --argjson f "$FROM" --argjson t "$TILL" '{history:$vt,itemids:["54607"],time_from:$f,time_till:$t,output:"extend",sortfield:"clock",sortorder:"ASC",limit:5000}')" > "$OUT/hist-54607.json"
jq -r '[.[]|{c:(.clock|tonumber),v:(.value|tonumber)}] as $a
  | "puntos=\($a|length) (esperados ~1440) | minutos con FATAL>0: \([$a[]|select(.v>0)]|length) | maximo: \($a|map(.v)|max)",
    "episodios (tramos con valor > 0; inicio -03:00 -> fin, minutos, maximo):",
    ( reduce $a[] as $x ({runs:[],cur:null};
        if $x.v>0 then (if .cur==null then .cur={s:$x.c,e:$x.c,m:$x.v,n:1} else (.cur.e=$x.c|.cur.n+=1|.cur.m=([.cur.m,$x.v]|max)) end)
        else (if .cur!=null then (.runs+=[.cur]|.cur=null) else . end) end) | (.runs+(if .cur then [.cur] else [] end))[]
      | "  \((.s-10800)|strftime("%H:%M")) -> \((.e-10800)|strftime("%H:%M")) (\(.n) min, max \(.m))" )' "$OUT/hist-54607.json" | head -80
echo listo

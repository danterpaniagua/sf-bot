#!/usr/bin/env bash
# Event: 20261017_gitin2248-platform-contenedores-caidos-20261016
# C4 - SOLO LECTURA contra la API de Zabbix (sf-monitoreo.smartfran.com:8080, 6.0.32; token en $ZABBIX_API_KEY). Eficacia de las alertas nuevas, parte de entrega y del resto de las alertas.
#      (1) Notificaciones (alert.get) del 2026-10-16 -03:00 (03:00Z a 03:00Z del 17) para los eventos de "Running tasks below desired" y "Graylog: Platform FATAL detected" (ids tomados de data/c2/events-*.json):
#          cantidad por accion y por estado (0 no enviada, 1 enviada, 2 fallida, 3 nueva), reintentos, y cuantos eventos no tienen ninguna notificacion. NO se pide ni se imprime el destinatario (sendto) ni el usuario; el texto de error se enmascara y se corta.
#      (2) Eventos de las demas alertas nuevas entre 2026-10-15 00:00 y ahora (-03:00): nombres que contengan "ealthcheck", "Concentrador FATAL", "check without data": cantidad por nombre y hora de cada problema.
#      Un resultado vacio se contrasta con los conteos: 0 filas es "sin dato", no "sin eventos". Salidas en data/c4/.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
export LC_ALL=C
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
B="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261017_gitin2248-platform-contenedores-caidos-20261016/data"; OUT="$B/c4"; mkdir -p "$OUT"
FROM=$(date -u -d "2026-10-16T03:00:00Z" +%s); TILL=$(date -u -d "2026-10-17T03:00:00Z" +%s)
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
echo "run $(date -u +%FT%TZ)"
jq -s '[.[][]|{eventid,value,clock,name:(.name|if test("FATAL") then "FATAL" else "ECS" end)}]' "$B"/c2/events-*.json > "$OUT/eventos-16-10.json"
IDS=$(jq -c '[.[].eventid]' "$OUT/eventos-16-10.json")
echo "== (1) eventos de 16-10: $(jq length "$OUT/eventos-16-10.json") (ECS $(jq '[.[]|select(.name=="ECS")]|length' "$OUT/eventos-16-10.json"), FATAL $(jq '[.[]|select(.name=="FATAL")]|length' "$OUT/eventos-16-10.json"))"
call alert.get "$(jq -n --argjson ids "$IDS" '{eventids:$ids,output:["alertid","actionid","eventid","status","retries","mediatypeid","alerttype","clock","error"],selectMediatypes:["name"],limit:20000}')" > "$OUT/alertas.json"
echo "alertas devueltas: $(jq length "$OUT/alertas.json")"
echo "== por accion, tipo de medio y estado (0 no enviada, 1 enviada, 2 fallida, 3 nueva): accion | medio | estado | cantidad | reintentos maximos"
jq -r 'group_by([.actionid,(.mediatypes[0].name // .mediatypeid),.status])[]|[.[0].actionid,(.[0].mediatypes[0].name // .[0].mediatypeid),.[0].status,length,([.[].retries|tonumber]|max)]|@tsv' "$OUT/alertas.json"
echo "== eventos de la lista sin ninguna notificacion: $(jq -n --slurpfile e "$OUT/eventos-16-10.json" --slurpfile a "$OUT/alertas.json" '($a[0]|map(.eventid)|unique) as $got|[$e[0][]|select(.eventid as $x|$got|index($x)|not)]|length')"
echo "== notificaciones fallidas (estado 2): hasta 10, error enmascarado y cortado"
jq -r '[.[]|select(.status=="2")][0:10][]|[.alertid,.actionid,.eventid,(.error|gsub("[0-9]{7,}";"[num]")|gsub("[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+";"[correo]")|.[0:120])]|@tsv' "$OUT/alertas.json"
echo; echo "== (2) otras alertas nuevas: eventos desde 2026-10-15 00:00 -03:00 hasta ahora"
S2=$(date -u -d "2026-10-15T03:00:00Z" +%s)
call event.get "$(jq -n --argjson f "$S2" '{source:0,object:0,time_from:$f,searchByAny:true,search:{name:["ealthcheck","Concentrador FATAL","check without data"]},output:["eventid","clock","value","name","objectid"],sortfield:["clock","eventid"],sortorder:"ASC",limit:3000}')" > "$OUT/eventos-otras-alertas.json"
echo "eventos: $(jq length "$OUT/eventos-otras-alertas.json")"
jq -r 'group_by(.name)[]|[.[0].name,"problemas="+(map(select(.value=="1"))|length|tostring),"recuperaciones="+(map(select(.value=="0"))|length|tostring)]|@tsv' "$OUT/eventos-otras-alertas.json"
echo "== problemas (hora -03:00 | nombre), hasta 60"
jq -r '.[]|select(.value=="1")|[((.clock|tonumber-10800)|strftime("%m-%d %H:%M:%S")),.name]|@tsv' "$OUT/eventos-otras-alertas.json" | head -60
echo listo

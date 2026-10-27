#!/usr/bin/env bash
# Event: 20261026_gitin2316-sml-spikes-webservice (GITIN-2316)
# C1 - SOLO LECTURA contra la API de Zabbix (6.0.x; token en $ZABBIX_API_KEY).
#      Pedido del usuario: "POST + GET WEBS 01". Lee de SFCG-WEBS-01 los items de IIS "Get Requests/sec" y "Post Requests/sec"
#      (y "Total Method Requests/sec" si existe) en una ventana y muestra por minuto GET, POST y total, mas maximo, promedio y los 10 minutos mas altos.
#      La ventana NO fue indicada por el usuario: se pasa como argumentos en hora local UTC-3 ("YYYY-MM-DD HH:MM"); sin argumentos usa las ultimas 24 h.
#      Uso: bash scripts-c1.sh ["2026-10-26 08:00" "2026-10-26 18:00"]
#      Salidas en data/c1/ (JSON crudo por item). Todo lo impreso en UTC y en UTC-3.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/loyalty/events/20261026_gitin2316-sml-spikes-webservice/data/c1"
mkdir -p "$OUT"
if [ $# -ge 2 ]; then
  FROM=$(date -d "$1 -0300" +%s); TO=$(date -d "$2 -0300" +%s)
else
  TO=$(date +%s); FROM=$((TO - 86400))
fi
echo "ventana UTC: $(date -u -d @"$FROM" +%FT%TZ) a $(date -u -d @"$TO" +%FT%TZ)  (local UTC-3: $(date -d @"$FROM" +%F\ %R) a $(date -d @"$TO" +%F\ %R) segun la zona de este equipo)"

call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }

call host.get '{"search":{"host":"WEBS-01"},"output":["hostid","host","name","status"]}' > "$OUT/host.json"
echo "== host (id | tecnico | nombre | status 0=activo)"
jq -r '.[]|[.hostid,.host,.name,.status]|@tsv' "$OUT/host.json"
[ "$(jq length "$OUT/host.json")" = "1" ] || { echo "se esperaba exactamente 1 host para WEBS-01; revisar host.json" >&2; exit 1; }
HOSTID=$(jq -r '.[0].hostid' "$OUT/host.json")

call item.get "{\"hostids\":[\"$HOSTID\"],\"search\":{\"key_\":\"Requests/sec\"},\"output\":[\"itemid\",\"name\",\"key_\",\"value_type\",\"delay\",\"status\",\"state\",\"lastclock\"]}" > "$OUT/items.json"
echo; echo "== items de requests por segundo (itemid | nombre | clave | tipo de valor 0=float | delay | status 0=activo | state 0=normal)"
jq -r '.[]|[.itemid,.name,.key_,.value_type,.delay,.status,.state]|@tsv' "$OUT/items.json"

# GET, POST y Total: se eligen por la clave sin distinguir mayusculas
jq -c '[.[]|select(.key_|test("Get Requests/sec";"i"))|{id:.itemid,k:"GET",vt:.value_type}]
     + [.[]|select(.key_|test("Post Requests/sec";"i"))|{id:.itemid,k:"POST",vt:.value_type}]
     + [.[]|select(.key_|test("Total Method Requests/sec";"i"))|{id:.itemid,k:"TOTAL",vt:.value_type}]' "$OUT/items.json" > "$OUT/selected.json"
echo; echo "== items elegidos"; jq -r '.[]|[.k,.id,.vt]|@tsv' "$OUT/selected.json"
[ "$(jq length "$OUT/selected.json")" != "0" ] || { echo "ningun item GET/POST/TOTAL en WEBS-01; ver items.json" >&2; exit 1; }

# historial crudo por item (un archivo por item); si el historial esta vacio en la ventana se avisa
for row in $(jq -r '.[]|"\(.k):\(.id):\(.vt)"' "$OUT/selected.json"); do
  k=${row%%:*}; rest=${row#*:}; id=${rest%%:*}; vt=${rest##*:}
  call history.get "{\"history\":$vt,\"itemids\":[\"$id\"],\"time_from\":$FROM,\"time_till\":$TO,\"output\":\"extend\",\"sortfield\":\"clock\",\"sortorder\":\"ASC\",\"limit\":100000}" > "$OUT/hist-$k-$id.json"
  echo "historial $k item $id: $(jq length "$OUT/hist-$k-$id.json") puntos"
done

# union por minuto (clock redondeado al minuto): promedio del minuto de cada serie
for k in GET POST TOTAL; do
  f=$(ls "$OUT"/hist-$k-*.json 2>/dev/null | head -1 || true)
  [ -n "$f" ] || { echo "[]" > "$OUT/min-$k.json"; continue; }
  jq '[.[]|{m:((.clock|tonumber)/60|floor*60),v:(.value|tonumber)}]|group_by(.m)|map({m:.[0].m,v:(map(.v)|add/length)})' "$f" > "$OUT/min-$k.json"
done
jq -s '
  def idx(a): reduce a[] as $r ({}; .[($r.m|tostring)] = $r.v);
  (idx(.[0])) as $g | (idx(.[1])) as $p | (idx(.[2])) as $t
  | ([.[0][].m, .[1][].m, .[2][].m] | unique) as $ms
  | $ms | map({m:., get:($g[tostring] // null), post:($p[tostring] // null), total:($t[tostring] // null)})
' "$OUT/min-GET.json" "$OUT/min-POST.json" "$OUT/min-TOTAL.json" > "$OUT/minutes.json"

echo; echo "== por minuto (UTC | UTC-3 | GET/s | POST/s | TOTAL/s), solo minutos con TOTAL o GET+POST >= 15 req/s; la lista completa esta en data/c1/minutes.json"
jq -r '.[]|select(((.total // ((.get//0)+(.post//0))) >= 15))|[(.m|strftime("%F %R")),((.m-10800)|strftime("%F %R")),(.get//"-"),(.post//"-"),(.total//"-")]|@tsv' "$OUT/minutes.json" | head -200
echo; echo "== resumen por serie (serie | minutos | maximo | promedio)"
for k in GET POST TOTAL; do
  jq -r --arg k "$k" 'map(.v)|if length==0 then [$k,0,"-","-"] else [$k,length,max,(add/length)] end|@tsv' "$OUT/min-$k.json"
done
echo; echo "== 10 minutos mas altos de GET+POST (UTC | UTC-3 | GET | POST | suma)"
jq -r 'map(select(.get!=null or .post!=null)|. + {sum:((.get//0)+(.post//0))})|sort_by(-.sum)|.[0:10][]|[(.m|strftime("%F %R")),((.m-10800)|strftime("%F %R")),(.get//"-"),(.post//"-"),.sum]|@tsv' "$OUT/minutes.json"
echo listo

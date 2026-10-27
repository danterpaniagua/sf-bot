#!/usr/bin/env bash
# Event: 20261026_gitin2316-sml-spikes-webservice (GITIN-2316)
# C2 - SOLO LECTURA contra la API de Zabbix (6.0.x; token en $ZABBIX_API_KEY).
#      Pedido del usuario: evento entre las 21:00 (UTC-3) de 2026-10-26 y ahora. Para SFCG-WEBS-01/02/03 muestra por minuto GET, POST y Total de requests/s
#      (items _Total) y la CPU (system.cpu.util), en hora UTC y UTC-3. C1 solo miro WEBS-01 entre 08:00 y 18:00 y no mostro picos de requests.
#      Uso: bash scripts-c2.sh ["2026-10-26 21:00" ["2026-10-26 22:00"]]   (sin 2do argumento: hasta ahora; sin argumentos: 21:00 de hoy). Hosts: variable HOSTS (por defecto WEBS-01 WEBS-02 WEBS-03).
#      Salidas en data/c2/ (JSON crudo y minutos por host).
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/loyalty/events/20261026_gitin2316-sml-spikes-webservice/data/c2"
HOSTS="${HOSTS:-WEBS-01 WEBS-02 WEBS-03}"
mkdir -p "$OUT"
FROM=$(date -d "${1:-2026-10-26 21:00} -0300" +%s)
TO=$( [ $# -ge 2 ] && date -d "$2 -0300" +%s || date +%s )
echo "ventana UTC: $(date -u -d @"$FROM" +%FT%TZ) a $(date -u -d @"$TO" +%FT%TZ)  (UTC-3: $(date -u -d @$((FROM-10800)) +%F\ %R) a $(date -u -d @$((TO-10800)) +%F\ %R))"

call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }

for H in $HOSTS; do
  echo; echo "===== SFCG-$H"
  call host.get "{\"search\":{\"host\":\"$H\"},\"output\":[\"hostid\",\"host\",\"name\",\"status\"]}" > "$OUT/host-$H.json"
  [ "$(jq length "$OUT/host-$H.json")" = "1" ] || { echo "se esperaba 1 host para $H; ver host-$H.json" >&2; exit 1; }
  HOSTID=$(jq -r '.[0].hostid' "$OUT/host-$H.json")
  echo "host: $(jq -r '.[0]|[.hostid,.host,.name,.status]|@tsv' "$OUT/host-$H.json")"
  call item.get "{\"hostids\":[\"$HOSTID\"],\"search\":{\"key_\":\"_Total\"},\"output\":[\"itemid\",\"name\",\"key_\",\"value_type\"]}" > "$OUT/items-req-$H.json"
  call item.get "{\"hostids\":[\"$HOSTID\"],\"search\":{\"key_\":\"system.cpu.util\"},\"output\":[\"itemid\",\"name\",\"key_\",\"value_type\"]}" > "$OUT/items-cpu-$H.json"
  jq -c -s '
    ([.[0][]|select(.key_|test("Get Requests/Sec";"i"))|{id:.itemid,k:"GET",vt:.value_type}][0:1])
  + ([.[0][]|select(.key_|test("Post Requests/Sec";"i"))|{id:.itemid,k:"POST",vt:.value_type}][0:1])
  + ([.[0][]|select(.key_|test("Total Method Requests/Sec";"i"))|{id:.itemid,k:"TOTAL",vt:.value_type}][0:1])
  + ([.[1][]|select(.key_|test("^system\\.cpu\\.util(\\[|$)"))|{id:.itemid,k:"CPU",vt:.value_type}][0:1])' \
    "$OUT/items-req-$H.json" "$OUT/items-cpu-$H.json" > "$OUT/selected-$H.json"
  echo "items: $(jq -r 'map("\(.k)=\(.id)")|join(" ")' "$OUT/selected-$H.json")"
  for k in GET POST TOTAL CPU; do
    id=$(jq -r --arg k "$k" '.[]|select(.k==$k)|.id' "$OUT/selected-$H.json"); vt=$(jq -r --arg k "$k" '.[]|select(.k==$k)|.vt' "$OUT/selected-$H.json")
    if [ -z "$id" ]; then echo "[]" > "$OUT/min-$H-$k.json"; echo "sin item $k"; continue; fi
    call history.get "{\"history\":$vt,\"itemids\":[\"$id\"],\"time_from\":$FROM,\"time_till\":$TO,\"output\":\"extend\",\"sortfield\":\"clock\",\"sortorder\":\"ASC\",\"limit\":100000}" > "$OUT/hist-$H-$k.json"
    jq '[.[]|{m:((.clock|tonumber)/60|floor*60),v:(.value|tonumber)}]|group_by(.m)|map({m:.[0].m,v:(map(.v)|add/length)})' "$OUT/hist-$H-$k.json" > "$OUT/min-$H-$k.json"
    echo "  $k: $(jq length "$OUT/hist-$H-$k.json") puntos, $(jq length "$OUT/min-$H-$k.json") minutos"
  done
  jq -s '
    def idx(a): reduce a[] as $r ({}; .[($r.m|tostring)] = $r.v);
    (idx(.[0])) as $g | (idx(.[1])) as $p | (idx(.[2])) as $t | (idx(.[3])) as $c
    | ([.[][].m] | unique) | map({m:., get:($g[tostring] // null), post:($p[tostring] // null), total:($t[tostring] // null), cpu:($c[tostring] // null)})' \
    "$OUT/min-$H-GET.json" "$OUT/min-$H-POST.json" "$OUT/min-$H-TOTAL.json" "$OUT/min-$H-CPU.json" > "$OUT/minutes-$H.json"
  echo "-- resumen (serie | minutos | maximo | promedio)"
  for k in get post total cpu; do
    jq -r --arg k "$k" '[.[]|.[$k]|select(.!=null)]|if length==0 then [$k,0,"-","-"] else [$k,length,max,(add/length)] end|@tsv' "$OUT/minutes-$H.json"
  done
  echo "-- por minuto (UTC-3 | GET/s | POST/s | TOTAL/s | CPU %), redondeado a 2 decimales"
  jq -r '.[]|[((.m-10800)|strftime("%H:%M")),((.get//-1)*100|round/100),((.post//-1)*100|round/100),((.total//-1)*100|round/100),((.cpu//-1)*100|round/100)]|@tsv' "$OUT/minutes-$H.json"
done
echo; echo "(-0,01 / -1 = sin dato en ese minuto)"; echo listo

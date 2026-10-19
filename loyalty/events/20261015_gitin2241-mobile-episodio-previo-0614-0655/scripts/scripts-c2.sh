#!/usr/bin/env bash
# Event: 20261015_gitin2241-mobile-episodio-previo-0614-0655 (GITIN-2241)
# C2 - Zabbix 6.0.32 (sf-monitoreo.smartfran.com:8080; token en $ZABBIX_API_KEY). SOLO LECTURA (item.get, history.get).
#      Ventana fija del 2026-10-15 08:30 a 10:30 UTC (05:30 a 07:30 -03:00); el episodio de PediGrido es 09:14-09:55 UTC.
#      (1) Items del escenario web "[PROD] MobileApp" (host Zabbix Proxy; web items: "webitems": true) e item de peticiones totales de IIS de SFCG-MOBI-01/02 (clave documentada en docs/zabbix_observability.md: perf_counter_en["\Web Service(_Total)\Total Method Requests/Sec", 60]):
#          cantidad de puntos de historial devueltos, minimo, maximo, promedio; para los codigos de respuesta, los puntos distintos de 200 con su hora.
#      (2) Si el historial de la ventana esta vacio (retencion), lo avisa (trend.get no existe en Zabbix 6.0.32).
#      Imprime siempre la cantidad de puntos: un item con 0 puntos es "sin dato", no "sin problema".
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
export LC_ALL=C
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/loyalty/events/20261015_gitin2241-mobile-episodio-previo-0614-0655/data"
TS=$(date -u +%Y%m%dT%H%M%SZ); RUN="$OUT/c2-run-$TS"; mkdir -p "$RUN"
FROM=$(date -u -d "2026-10-15T08:30:00Z" +%s); TILL=$(date -u -d "2026-10-15T10:30:00Z" +%s)
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
echo "run $TS | ventana $FROM-$TILL (2026-10-15 08:30-10:30 UTC)"

# --- items candidatos
call item.get '{"webitems":true,"output":["itemid","name","key_","value_type","delay","state","lastvalue","lastclock"],"selectHosts":["host"],"search":{"key_":"MobileApp"}}' > "$RUN/items-web.json"
call item.get '{"output":["itemid","name","key_","value_type","delay","state","lastvalue","lastclock"],"selectHosts":["host"],"search":{"key_":"Total Method Requests/Sec"},"host":["SFCG-MOBI-01","SFCG-MOBI-02"]}' > "$RUN/items-iis.json"
echo "== items encontrados: web=$(jq length "$RUN/items-web.json") iis/peticiones=$(jq length "$RUN/items-iis.json")"
jq -s 'add' "$RUN/items-web.json" "$RUN/items-iis.json" > "$RUN/items.json"
jq -r '.[]|[.itemid,.hosts[0].host,.key_,("tipo="+.value_type),("delay="+.delay)]|@tsv' "$RUN/items.json"

# --- historial y tendencias por item
echo; echo "== por item: puntos de historial en la ventana | min | max | promedio  (codigos de respuesta: puntos distintos de 200)"
jq -c '.[]' "$RUN/items.json" | while read -r it; do
  id=$(jq -r .itemid <<<"$it"); vt=$(jq -r .value_type <<<"$it"); key=$(jq -r .key_ <<<"$it"); host=$(jq -r '.hosts[0].host' <<<"$it")
  call history.get "$(jq -n --arg id "$id" --argjson vt "$vt" --argjson f "$FROM" --argjson t "$TILL" '{history:$vt,itemids:[$id],time_from:$f,time_till:$t,output:"extend",sortfield:"clock",sortorder:"ASC",limit:5000}')" > "$RUN/hist-$id.json"
  n=$(jq length "$RUN/hist-$id.json")
  echo "-- $host | $key | puntos=$n"
  if [ "$n" -gt 0 ] && [ "$vt" != "0" ] && [ "$vt" != "3" ]; then
    echo "   item de texto (tipo $vt): $(jq -r '[.[]|.value]|unique|length' "$RUN/hist-$id.json") valores distintos; no se resume"
  elif [ "$n" -gt 0 ]; then
    jq -r '[.[]|.value|tonumber] as $v|"   min=\($v|min) max=\($v|max) prom=\(($v|add)/($v|length))"' "$RUN/hist-$id.json"
    case "$key" in *rspcode*) jq -r '.[]|select((.value|tonumber)!=200)|"   no-200: "+((.clock|tonumber)|strftime("%FT%TZ"))+" valor="+.value' "$RUN/hist-$id.json";; esac
  else
    echo "   historial vacio en la ventana (posible retencion de 7 dias; la API no ofrece tendencias en 6.0.32, docs/zabbix_observability.md): sin dato, no es ausencia de problema"
  fi
done
echo; echo "guardado en $RUN"

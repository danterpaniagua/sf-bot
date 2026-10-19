#!/usr/bin/env bash
# Event: 20261015_gitin2241-mobile-episodio-previo-0614-0655 (GITIN-2241)
# C3 - Zabbix 6.0.32 (sf-monitoreo.smartfran.com:8080; token en $ZABBIX_API_KEY). SOLO LECTURA (history.get con itemids explicitos, item.get de listado).
#      Ventana fija del 2026-10-15 08:30 a 10:30 UTC. Episodio visto en C2: 09:15:27 a 09:56:29 UTC (escenario "[PROD] MobileApp", paso 2 con timeout de 15 s).
#      Items (ids de data/c2-run-20261016T151621Z/items.json), todos numericos:
#        web, tiempo de respuesta y codigo por paso: 51574/51575 (POST Account/Login), 51577/51578 (AdditionalInformation Puntos LoadBalancer), 54603/54604 (healthcheck)
#        SFCG-MOBI-01: 52818 cola de peticiones, 52819 reciclados del app pool, 52820 estado del app pool, 52821 uptime del app pool
#        SFCG-MOBI-02: 52814 cola de peticiones, 52815 reciclados, 52816 estado, 52817 uptime
#      Por item imprime: puntos dentro del episodio (09:14:00-09:57:00) y fuera, minimo/maximo/promedio de cada parte, y los cambios de valor (hora y valor) para los contadores de estado.
#      Un item con 0 puntos es "sin dato". Ademas lista los items de peticiones/IIS de SFCG-MOBI-01/02 (clave que contenga "_Total" o nombre con "Request") para saber que existe.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
export LC_ALL=C
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/loyalty/events/20261015_gitin2241-mobile-episodio-previo-0614-0655/data"
TS=$(date -u +%Y%m%dT%H%M%SZ); RUN="$OUT/c3-run-$TS"; mkdir -p "$RUN"
FROM=$(date -u -d "2026-10-15T08:30:00Z" +%s); TILL=$(date -u -d "2026-10-15T10:30:00Z" +%s)
EF=$(date -u -d "2026-10-15T09:14:00Z" +%s); ET=$(date -u -d "2026-10-15T09:57:00Z" +%s)
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
echo "run $TS | ventana $FROM-$TILL | episodio $EF-$ET (09:14:00-09:57:00 UTC)"
ITEMS="51574 51575 51577 51578 54603 54604 52814 52815 52816 52817 52818 52819 52820 52821"
call item.get "$(jq -n --arg ids "$ITEMS" '{itemids:($ids|split(" ")),webitems:true,output:["itemid","key_","value_type"],selectHosts:["host"]}')" > "$RUN/items.json"
echo "== items pedidos: $(echo $ITEMS | wc -w) | devueltos: $(jq length "$RUN/items.json") | tipos distintos de numerico (0 o 3): $(jq '[.[]|select(.value_type!="0" and .value_type!="3")]|length' "$RUN/items.json")"
echo "== por item: dentro del episodio (n min max prom) | fuera (n min max prom)"
jq -c '.[]|select(.value_type=="0" or .value_type=="3")' "$RUN/items.json" | while read -r it; do
  id=$(jq -r .itemid <<<"$it"); vt=$(jq -r .value_type <<<"$it"); key=$(jq -r .key_ <<<"$it"); host=$(jq -r '.hosts[0].host' <<<"$it")
  call history.get "$(jq -n --arg id "$id" --argjson vt "$vt" --argjson f "$FROM" --argjson t "$TILL" '{history:$vt,itemids:[$id],time_from:$f,time_till:$t,output:"extend",sortfield:"clock",sortorder:"ASC",limit:5000}')" > "$RUN/hist-$id.json"
  echo "-- $id | $host | $key | puntos=$(jq length "$RUN/hist-$id.json")"
  jq -r --argjson ef "$EF" --argjson et "$ET" '[.[]|{c:(.clock|tonumber),v:(.value|tonumber)}] as $a
    | def st(x): if (x|length)==0 then "n=0" else "n=\(x|length) min=\(x|min) max=\(x|max) prom=\((x|add)/(x|length)|.*100|round/100)" end;
      "   dentro: "+st([$a[]|select(.c>=$ef and .c<$et)|.v])+" | fuera: "+st([$a[]|select(.c<$ef or .c>=$et)|.v])' "$RUN/hist-$id.json"
  case "$key" in *Recycles*|*State*|*Uptime*) echo "   cambios de valor (hora UTC valor), maximo 15:"; jq -r '[.[]|{c:(.clock|tonumber),v:.value}] as $a|[range(0;$a|length)|select(.==0 or $a[.].v!=$a[.-1].v)]|.[0:15][]|"     "+($a[.].c|strftime("%T"))+" "+$a[.].v' "$RUN/hist-$id.json";; esac
done
echo; echo "== items de peticiones/IIS de SFCG-MOBI-01/02 (clave con _Total o nombre con Request): id | host | clave"
call item.get '{"output":["itemid","name","key_","delay"],"selectHosts":["host"],"searchByAny":true,"search":{"key_":"_Total","name":"Request"},"host":["SFCG-MOBI-01","SFCG-MOBI-02"]}' > "$RUN/items-iis-list.json"
jq -r '.[]|[.itemid,.hosts[0].host,.key_,("delay="+.delay)]|@tsv' "$RUN/items-iis-list.json"
echo "items listados: $(jq length "$RUN/items-iis-list.json")"
echo; echo "guardado en $RUN"

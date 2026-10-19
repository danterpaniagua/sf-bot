#!/usr/bin/env bash
# Event: 20261015_gitin2241-mobile-episodio-previo-0614-0655 (GITIN-2241)
# C4 - Zabbix 6.0.32 (sf-monitoreo.smartfran.com:8080; token en $ZABBIX_API_KEY). SOLO LECTURA (history.get con itemids explicitos).
#      Historial de "Current Application Pool Uptime" (un punto por minuto, se reinicia a 0 con un reciclado) de SFCG-MOBI-01 (item 52821) y SFCG-MOBI-02 (item 52817),
#      de 2026-10-15 00:00 a 2026-10-16 00:00 UTC (la retencion informada para estos items es 7 dias, docs/zabbix_observability.md).
#      Por servidor: cantidad de puntos, primer y ultimo punto, huecos de mas de 150 s (inicio, fin, minutos) y reinicios (el valor baja respecto del anterior: hora y valor antes/despues).
#      C3 mostro 0 puntos de SFCG-MOBI-02 entre 08:30 y 10:30 UTC; esto busca cuando empieza y cuando termina esa ausencia y si hubo un reinicio del app pool.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
export LC_ALL=C
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/loyalty/events/20261015_gitin2241-mobile-episodio-previo-0614-0655/data"
TS=$(date -u +%Y%m%dT%H%M%SZ); RUN="$OUT/c4-run-$TS"; mkdir -p "$RUN"
FROM=$(date -u -d "2026-10-15T00:00:00Z" +%s); TILL=$(date -u -d "2026-10-16T00:00:00Z" +%s)
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
echo "run $TS | ventana $FROM-$TILL (2026-10-15 00:00 a 2026-10-16 00:00 UTC)"
for pair in "52821 SFCG-MOBI-01" "52817 SFCG-MOBI-02"; do
  set -- $pair; id=$1; host=$2
  call history.get "$(jq -n --arg id "$id" --argjson f "$FROM" --argjson t "$TILL" '{history:0,itemids:[$id],time_from:$f,time_till:$t,output:"extend",sortfield:"clock",sortorder:"ASC",limit:5000}')" > "$RUN/hist-$id.json"
  n=$(jq length "$RUN/hist-$id.json")
  echo; echo "== $host | item $id | puntos=$n (esperados ~1440 si no hay huecos; el limite de lectura es 5000)"
  if [ "$n" -gt 0 ]; then
    jq -r '[.[]|{c:(.clock|tonumber),v:(.value|tonumber)}] as $a
      | "   primer punto: \($a[0].c|strftime("%FT%TZ")) ultimo: \($a[-1].c|strftime("%FT%TZ"))",
        "   huecos > 150 s (inicio -> fin, minutos):",
        ([range(1;$a|length)|select($a[.].c-$a[.-1].c>150)|"     \($a[.-1].c|strftime("%T")) -> \($a[.].c|strftime("%T")) (\((($a[.].c-$a[.-1].c)/60)|round) min)"]|if length==0 then ["     ninguno"] else .[0:30] end|.[]),
        "   reinicios (valor baja):",
        ([range(1;$a|length)|select($a[.].v<$a[.-1].v)|"     \($a[.].c|strftime("%T")) antes=\($a[.-1].v|round) despues=\($a[.].v|round)"]|if length==0 then ["     ninguno"] else .[0:30] end|.[]),
        "   uptime en el primer punto: \($a[0].v|round) s"' "$RUN/hist-$id.json"
  fi
done
echo; echo "guardado en $RUN"

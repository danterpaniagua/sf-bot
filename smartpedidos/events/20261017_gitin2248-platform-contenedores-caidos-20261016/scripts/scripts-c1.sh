#!/usr/bin/env bash
# Event: 20261017_gitin2248-platform-contenedores-caidos-20261016
# C1 - SOLO LECTURA contra CloudWatch (cuenta 382381053403, us-east-1, cluster smartfran-pedidos-production). Adaptado de scripts-c22.sh del evento 20261014_gitin2222-ecs-reinicios-avisos-sns.
#      Container Insights por servicio (ClusterName + ServiceName): RunningTaskCount y DesiredTaskCount, periodo 60 s, estadistico Minimum, para los dias -03:00 del 13, 14, 15 y 16 de octubre de 2026
#      (cada dia = 03:00Z a 03:00Z del siguiente; 2026-10-17 corrige el fin de ventana: "+1 day" sin la fecha en formato Z lo leia como zona +01:00 y cortaba la ultima hora, 1380 puntos en vez de 1440). Por dia y servicio: cantidad de tramos con Running < Desired, minutos totales, minimo de Running y de Desired. El detalle de tramos se imprime solo para el 16-10.
#      Es una vista de ejecucion (una parada se ve como un descenso), no un conteo de eventos de parada. CloudWatch conserva 1 minuto por 15 dias.
#      Salidas en data/c1/.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
R="us-east-1"; CL="smartfran-pedidos-production"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261017_gitin2248-platform-contenedores-caidos-20261016/data/c1"
mkdir -p "$OUT"
ACCT=$(aws sts get-caller-identity --query Account --output text --region $R)
[ "$ACCT" = "382381053403" ] || { echo "GUARDA: la cuenta no es 382381053403"; exit 1; }
Q() { jq -nc --arg id "$1" --arg m "$2" --arg c "$CL" --arg s "$3" '{Id:$id,MetricStat:{Metric:{Namespace:"ECS/ContainerInsights",MetricName:$m,Dimensions:[{Name:"ClusterName",Value:$c},{Name:"ServiceName",Value:$s}]},Period:60,Stat:"Minimum"},ReturnData:true}'; }
QUERIES=$(jq -nc --argjson a "$(Q plat_run RunningTaskCount platform-service-production-service)" --argjson b "$(Q plat_des DesiredTaskCount platform-service-production-service)" --argjson c "$(Q conc_run RunningTaskCount concentrador-service-production-service)" --argjson d "$(Q conc_des DesiredTaskCount concentrador-service-production-service)" '[$a,$b,$c,$d]')
echo "run $(date -u +%FT%TZ) | cuenta $ACCT"
echo "dia(-03:00) | servicio | puntos Running | tramos Running<Desired | minutos | minimo Running | minimo Desired"
for d in 2026-10-13 2026-10-14 2026-10-15 2026-10-16; do
  S="${d}T03:00:00Z"; E=$(date -u -d "${d}T03:00:00Z + 1 day" +%Y-%m-%dT%H:%M:00Z)
  aws cloudwatch get-metric-data --region $R --start-time "$S" --end-time "$E" --metric-data-queries "$QUERIES" --scan-by TimestampAscending --output json > "$OUT/metric-data-$d.json"
  [ "$(jq '.Messages|length' "$OUT/metric-data-$d.json")" = "0" ] || echo "AVISO $d Messages: $(jq -c .Messages "$OUT/metric-data-$d.json")"
  for svc in plat conc; do
    jq -r --arg s "$svc" --arg d "$d" '
      (.MetricDataResults[]|select(.Id==($s+"_run"))) as $r | (.MetricDataResults[]|select(.Id==($s+"_des"))) as $de |
      [ range(0; ($r.Timestamps|length)) as $k | {t:$r.Timestamps[$k], v:$r.Values[$k], d:(($de.Timestamps|index($r.Timestamps[$k])) as $i | if $i==null then null else $de.Values[$i] end)} ] as $p |
      (reduce $p[] as $x ({runs:[],cur:null};
        if ($x.d != null and $x.v < $x.d) then (if .cur==null then .cur={s:$x.t,e:$x.t,m:$x.v,d:$x.d,n:1} else (.cur.e=$x.t | .cur.n+=1 | .cur.m=([.cur.m,$x.v]|min)) end)
        else (if .cur!=null then (.runs+=[.cur] | .cur=null) else . end) end) | (.runs + (if .cur then [.cur] else [] end))) as $runs |
      "\($d) | \($s) | \($r.Values|length) | \($runs|length) | \([$runs[].n]|add//0) | \($r.Values|min) | \($de.Values|min)"' "$OUT/metric-data-$d.json"
  done
done
echo; echo "== 16-10 (-03:00), platform: tramos con Running < Desired (inicio -03:00 | fin | minutos | minimo de Running | Desired)"
jq -r '
  (.MetricDataResults[]|select(.Id=="plat_run")) as $r | (.MetricDataResults[]|select(.Id=="plat_des")) as $de |
  [ range(0; ($r.Timestamps|length)) as $k | {t:$r.Timestamps[$k], v:$r.Values[$k], d:(($de.Timestamps|index($r.Timestamps[$k])) as $i | if $i==null then null else $de.Values[$i] end)} ] as $p |
  reduce $p[] as $x ({runs:[],cur:null};
    if ($x.d != null and $x.v < $x.d) then (if .cur==null then .cur={s:$x.t,e:$x.t,m:$x.v,d:$x.d,n:1} else (.cur.e=$x.t | .cur.n+=1 | .cur.m=([.cur.m,$x.v]|min)) end)
    else (if .cur!=null then (.runs+=[.cur] | .cur=null) else . end) end) | (.runs + (if .cur then [.cur] else [] end))[] |
  [ .s[5:16], .e[5:16], .n, .m, .d ] | @tsv' "$OUT/metric-data-2026-10-16.json"   # CloudWatch ya devuelve las marcas en -03:00 (hora local de la CLI), se imprimen tal cual
echo listo

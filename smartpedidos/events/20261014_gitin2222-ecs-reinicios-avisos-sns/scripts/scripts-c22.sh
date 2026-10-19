#!/usr/bin/env bash
# Event: 20261014_gitin2222-ecs-reinicios-avisos-sns
# C22 - SOLO LECTURA contra CloudWatch (cuenta 382381053403, us-east-1). Pregunta del usuario: el item de Zabbix "AWS ECS Cluster: Task Count" suma platform + concentrador; se quiere ver cada servicio por separado.
#       Pide a CloudWatch Container Insights, por servicio (dimensiones ClusterName + ServiceName), RunningTaskCount y DesiredTaskCount con periodo de 60 s y estadistico Minimum (el minimo de cada minuto)
#       para las ultimas N horas (por defecto 24) y lista los tramos continuos en que el minimo de Running estuvo por debajo de Desired (hora -03:00).
#       Uso: bash scripts-c22.sh [horas]. Salidas en data/c22/.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
H="${1:-24}"; R="us-east-1"; CL="smartfran-pedidos-production"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/data/c22"
mkdir -p "$OUT"
ACCT=$(aws sts get-caller-identity --query Account --output text --region $R)
[ "$ACCT" = "382381053403" ] || { echo "GUARDA: la cuenta no es 382381053403"; exit 1; }
END=$(date -u +%Y-%m-%dT%H:%M:00Z); START=$(date -u -d "-${H} hours" +%Y-%m-%dT%H:%M:00Z)
Q() { jq -nc --arg id "$1" --arg m "$2" --arg c "$CL" --arg s "$3" '{Id:$id,MetricStat:{Metric:{Namespace:"ECS/ContainerInsights",MetricName:$m,Dimensions:[{Name:"ClusterName",Value:$c},{Name:"ServiceName",Value:$s}]},Period:60,Stat:"Minimum"},ReturnData:true}'; }
QUERIES=$(jq -nc --argjson a "$(Q plat_run RunningTaskCount platform-service-production-service)" --argjson b "$(Q plat_des DesiredTaskCount platform-service-production-service)" --argjson c "$(Q conc_run RunningTaskCount concentrador-service-production-service)" --argjson d "$(Q conc_des DesiredTaskCount concentrador-service-production-service)" '[$a,$b,$c,$d]')
aws cloudwatch get-metric-data --region $R --start-time "$START" --end-time "$END" --metric-data-queries "$QUERIES" --scan-by TimestampAscending --output json > "$OUT/metric-data.json"
echo "== periodo $START -> $END | mensajes: $(jq -c '.Messages' "$OUT/metric-data.json")"
echo "== puntos por serie: $(jq -c '[.MetricDataResults[]|{(.Id):(.Values|length)}]|add' "$OUT/metric-data.json")"
for svc in plat conc; do
  echo; echo "== $svc: tramos continuos con minimo(Running) < minimo(Desired) (inicio -03:00 | fin | minutos | minimo de Running | Desired)"
  jq -r --arg s "$svc" '
    (.MetricDataResults[]|select(.Id==($s+"_run"))) as $r | (.MetricDataResults[]|select(.Id==($s+"_des"))) as $d |
    [ range(0; ($r.Timestamps|length)) as $k | {t:$r.Timestamps[$k], v:$r.Values[$k], d:(($d.Timestamps|index($r.Timestamps[$k])) as $i | if $i==null then null else $d.Values[$i] end)} ] as $p |
    reduce $p[] as $x ({runs:[],cur:null};
      if ($x.d != null and $x.v < $x.d) then (if .cur==null then .cur={s:$x.t,e:$x.t,m:$x.v,d:$x.d,n:1} else (.cur.e=$x.t | .cur.n+=1 | .cur.m=([.cur.m,$x.v]|min)) end)
      else (if .cur!=null then (.runs+=[.cur] | .cur=null) else . end) end) | (.runs + (if .cur then [.cur] else [] end))[] |
    [ (.s|sub("\\+00:00$";"Z")|fromdateiso8601-10800|strftime("%m-%d %H:%M")), (.e|sub("\\+00:00$";"Z")|fromdateiso8601-10800|strftime("%m-%d %H:%M")), .n, .m, .d ] | @tsv' "$OUT/metric-data.json"
done
echo listo

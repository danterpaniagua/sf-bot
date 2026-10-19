#!/usr/bin/env bash
# GITIN-2252 — read-only (CloudWatch get-metric-data), account 382381053403, us-east-1, cluster smartfran-pedidos-production.
# platform-service and concentrador-service: Container Insights RunningTaskCount / DesiredTaskCount (Minimum, 60 s) and AWS/ECS CPUUtilization of platform-service and concentrador-service (Average and Maximum, 60 s),
# for the -03:00 days 2026-10-16, 17 and 18 (each day 03:00Z to 03:00Z of the next; 18-10 until now). Raw JSON goes to data/platform-since-friday-<HHMM>/. Analysis: platform-since-friday-analyze.py.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
R=us-east-1; CL=smartfran-pedidos-production; T=$(date +%H%M)
OUT=/home/dpaniagua/Documentos/git/bots/operations/events/20261018_gitin2252-guardia-dia-de-la-madre/data/platform-since-friday-$T
mkdir -p "$OUT"
ACCT=$(aws sts get-caller-identity --query Account --output text --region $R)
[ "$ACCT" = "382381053403" ] || { echo "GUARDA: la cuenta no es 382381053403"; exit 1; }
CI() { jq -nc --arg id "$1" --arg m "$2" --arg c "$CL" --arg s "$3" '{Id:$id,MetricStat:{Metric:{Namespace:"ECS/ContainerInsights",MetricName:$m,Dimensions:[{Name:"ClusterName",Value:$c},{Name:"ServiceName",Value:$s}]},Period:60,Stat:"Minimum"},ReturnData:true}'; }
EC() { jq -nc --arg id "$1" --arg st "$2" --arg c "$CL" --arg s "$3" '{Id:$id,MetricStat:{Metric:{Namespace:"AWS/ECS",MetricName:"CPUUtilization",Dimensions:[{Name:"ClusterName",Value:$c},{Name:"ServiceName",Value:$s}]},Period:60,Stat:$st},ReturnData:true}'; }
P=platform-service-production-service; C=concentrador-service-production-service
QUERIES=$(jq -nc --argjson a "$(CI plat_run RunningTaskCount $P)" --argjson b "$(CI plat_des DesiredTaskCount $P)" --argjson c "$(CI conc_run RunningTaskCount $C)" --argjson d "$(CI conc_des DesiredTaskCount $C)" --argjson e "$(EC plat_cpu_avg Average $P)" --argjson f "$(EC plat_cpu_max Maximum $P)" --argjson g "$(EC conc_cpu_avg Average $C)" --argjson h "$(EC conc_cpu_max Maximum $C)" '[$a,$b,$c,$d,$e,$f,$g,$h]')
echo "run $(date -u +%FT%TZ) | cuenta $ACCT | salida $OUT"
for d in 2026-10-16 2026-10-17 2026-10-18; do
  S="${d}T03:00:00Z"; E=$(date -u -d "${d}T03:00:00Z + 1 day" +%Y-%m-%dT%H:%M:00Z)
  NOW=$(date -u +%Y-%m-%dT%H:%M:00Z); [[ "$E" > "$NOW" ]] && E=$NOW
  aws cloudwatch get-metric-data --region $R --start-time "$S" --end-time "$E" --metric-data-queries "$QUERIES" --scan-by TimestampAscending --output json > "$OUT/metric-data-$d.json"
  echo "$d: Messages=$(jq -c '.Messages' "$OUT/metric-data-$d.json") series=$(jq '[.MetricDataResults[]|.Values|length]|@json' -r "$OUT/metric-data-$d.json")"
done
echo "listo; analizar con: python3 -I platform-since-friday-analyze.py $OUT"

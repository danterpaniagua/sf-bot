#!/usr/bin/env bash
# Event: 20261017_gitin2248-platform-contenedores-caidos-20261016
# C7 - SOLO LECTURA contra CloudWatch (cuenta 382381053403, us-east-1, cluster smartfran-pedidos-production, servicio platform-service-production-service).
#      Container Insights: RunningTaskCount y DesiredTaskCount cada 60 s desde 2026-10-05 hasta ahora (Container Insights guarda 15 dias con esa resolucion).
#      Por dia local (-03:00): minutos con Running < Desired y cantidad de tramos (cada entrada en esa condicion cuenta uno).
#      Por hora local del dia de hoy: lo mismo, para ver si cambia despues del despliegue de la revision 275 (registrada 2026-10-19 12:03).
#      Fechas de referencia: revision 270 (10.11.0) 2026-10-08 09:45; revision 271 (10.11.1) 2026-10-13 09:40 (primera registrada despues de la fusion del PR #135 con el commit b56d403, el 2026-10-09);
#      revision 273 (10.11.3) 2026-10-16 09:36; revision 274 2026-10-19 09:45; revision 275 (10.11.5) 2026-10-19 12:03 (commit 643d17f de las 11:55 que comenta process.exit(1)).
#      La CLI de AWS imprime las marcas en hora local (-03:00) en esta maquina: se toman tal cual; si vinieran en UTC (+00:00) se convierten (corregido tras el primer intento del 2026-10-19, que fallo con esas marcas).
#      Salidas en data/c7/. No se imprime configuracion de contenedores ni variables de entorno.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
R="us-east-1"; CL="smartfran-pedidos-production"; SV="platform-service-production-service"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261017_gitin2248-platform-contenedores-caidos-20261016/data/c7"; mkdir -p "$OUT"
ACCT=$(aws sts get-caller-identity --query Account --output text --region $R)
[ "$ACCT" = "382381053403" ] || { echo "GUARDA: la cuenta no es 382381053403"; exit 1; }
echo "run $(date -u +%FT%TZ) | cuenta $ACCT"
Q() { jq -nc --arg id "$1" --arg m "$2" --arg c "$CL" --arg s "$SV" '{Id:$id,MetricStat:{Metric:{Namespace:"ECS/ContainerInsights",MetricName:$m,Dimensions:[{Name:"ClusterName",Value:$c},{Name:"ServiceName",Value:$s}]},Period:60,Stat:"Minimum"},ReturnData:true}'; }
START="2026-10-05T03:00:00Z"; END=$(date -u +%Y-%m-%dT%H:%M:00Z)
aws cloudwatch get-metric-data --region $R --start-time "$START" --end-time "$END" \
  --metric-data-queries "$(jq -nc --argjson a "$(Q run RunningTaskCount)" --argjson b "$(Q des DesiredTaskCount)" '[$a,$b]')" --scan-by TimestampAscending --output json > "$OUT/metric-data.json"
echo "periodo $START -> $END | mensajes: $(jq -c '.Messages' "$OUT/metric-data.json") | puntos run=$(jq '[.MetricDataResults[]|select(.Id=="run")|.Values|length]|add' "$OUT/metric-data.json") des=$(jq '[.MetricDataResults[]|select(.Id=="des")|.Values|length]|add' "$OUT/metric-data.json")"

# puntos unidos por marca de tiempo, hora local (-03:00): {t:"YYYY-MM-DDTHH:MM", run, des, dip}
JOIN='
  ([.MetricDataResults[]|select(.Id=="des")|[.Timestamps,.Values]|transpose|map({(.[0]):.[1]})|add]|add) as $d
  | [.MetricDataResults[]|select(.Id=="run")|[.Timestamps,.Values]|transpose[]
     | {t:(.[0]|if test("-03:00$") then .[0:16] else (sub("\\+00:00$";"Z")|fromdateiso8601-10800|todate|.[0:16]) end), run:.[1], des:($d[.[0]]//null)}
     | .dip=((.des!=null) and (.run<.des))]'
echo; echo "== por dia local: minutos con datos, minutos con Running < Desired, tramos, Desired minimo y maximo"
jq -r "$JOIN"' | group_by(.t[0:10])[] | . as $g
  | {dia:$g[0].t[0:10], min:($g|length), dips:([$g[]|select(.dip)]|length),
     tramos:([range(0;($g|length))|select($g[.].dip and (.==0 or ($g[.-1].dip|not)))]|length),
     dmin:([$g[].des|select(.!=null)]|min), dmax:([$g[].des|select(.!=null)]|max)}
  | [.dia,.min,.dips,.tramos,.dmin,.dmax]|@tsv' "$OUT/metric-data.json" | sort | (printf 'dia\tmin\tmin_running_menor\ttramos\tdesired_min\tdesired_max\n'; cat)
echo; echo "== hoy por hora local (-03:00): minutos con datos, minutos con Running < Desired, tramos"
TODAY=$(date -d "-3 hours" -u +%F)
jq -r --arg today "$TODAY" "$JOIN"' | map(select(.t[0:10]==$today)) | group_by(.t[0:13])[] | . as $g
  | [$g[0].t[0:13],($g|length),([$g[]|select(.dip)]|length),([range(0;($g|length))|select($g[.].dip and (.==0 or ($g[.-1].dip|not)))]|length)]|@tsv' "$OUT/metric-data.json" | (printf 'hora\tmin\tmin_running_menor\ttramos\n'; cat)
echo listo

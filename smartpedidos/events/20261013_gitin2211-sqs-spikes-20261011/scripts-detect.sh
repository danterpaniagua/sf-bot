#!/usr/bin/env bash
# Event: 20261013_sqs-spikes-20261011
# DETECT — Solo lectura contra CloudWatch (AWS/SQS, us-east-1). Lista cada ocurrencia de "parada del consumo" de
#          PRD_BranchMessages.fifo en un rango cualquiera: corridas de >= 2 minutos seguidos con enviados > 0 y borrados = 0
#          (la regla que coincidio con las 12 paradas del 03-10 al 12-10), con visibles maximos, edad maxima (hasta 6 min despues
#          del fin) y si la edad paso de 200 s. Tambien lista los minutos con edad >= 200 s.
#          Datos a 60 s; hasta ~10 dias por corrida (4 series x 1440 puntos x dias, limite 100.800 puntos).
# Uso:  FROM="2026-10-13 00:00" TO="2026-10-13 12:00" bash scripts-detect.sh <etiqueta>     (horas locales UTC-3; por defecto hoy 00:00 hasta ahora)
#       La etiqueta debe ser nueva en cada corrida (noclobber).
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
LABEL="${1:?etiqueta}"
FROM="${FROM:-$(date +%F) 00:00}"; TO="${TO:-$(date +'%F %H:%M')}"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261013_sqs-spikes-20261011/data"
Qn=PRD_BranchMessages.fifo
S=$(date -u -d "$FROM -0300" +%FT%TZ); E=$(date -u -d "$TO -0300" +%FT%TZ)
q() { echo "{\"Id\":\"$1\",\"Label\":\"$1\",\"ReturnData\":true,\"MetricStat\":{\"Period\":60,\"Stat\":\"$2\",\"Metric\":{\"Namespace\":\"AWS/SQS\",\"MetricName\":\"$3\",\"Dimensions\":[{\"Name\":\"QueueName\",\"Value\":\"$Qn\"}]}}}"; }
F="$OUT/detect-$LABEL.json"
aws cloudwatch get-metric-data --region us-east-1 --start-time "$S" --end-time "$E" --metric-data-queries \
"[$(q sent Sum NumberOfMessagesSent),$(q deleted Sum NumberOfMessagesDeleted),$(q visible Maximum ApproximateNumberOfMessagesVisible),$(q age Maximum ApproximateAgeOfOldestMessage)]" \
--output json > "$F"
echo "rango local $FROM a $TO ($S a $E UTC); mensajes de CloudWatch: $(jq -c '.Messages' "$F"); estados: $(jq -r '[.MetricDataResults[]|.StatusCode]|join(",")' "$F")"
jq -r '[.MetricDataResults[]|{(.Id):([.Timestamps,.Values]|transpose|map({(.[0]):.[1]})|add)}]|add as $m
  | ($m.sent // {}|keys)[] as $t | [$t, ($t|sub("-03:00$";"Z")|fromdateiso8601), $m.sent[$t], ($m.deleted[$t]//0), ($m.visible[$t]//0), ($m.age[$t]//0)] | @tsv' "$F" | sort > "$OUT/detect-$LABEL-minutes.tsv"
echo "minutos con enviados: $(wc -l < "$OUT/detect-$LABEL-minutes.tsv")"
echo "== paradas (corridas de >= 2 min con enviados>0 y borrados=0): inicio_local largo_min visibles_max edad_max(+6min) supera_200s"
LC_ALL=C awk -F'\t' '{ts[NR]=$1; ep[NR]=$2; s[NR]=$3; d[NR]=$4; v[NR]=$5; a[NR]=$6}
  END{ i=1; while(i<=NR){ if(s[i]>0 && d[i]==0){ j=i; while(j+1<=NR && s[j+1]>0 && d[j+1]==0 && ep[j+1]==ep[j]+60) j++;
        len=j-i+1; if(len>=2){ mv=0; ma=0; for(k=1;k<=NR;k++){ if(ep[k]>=ep[i] && ep[k]<=ep[j]+360){ if(v[k]+0>mv) mv=v[k]+0; if(a[k]+0>ma) ma=a[k]+0 } }
          printf "%s %d %d %d %s\n", ts[i], len, mv, ma, (ma>200?"SI":"no") } i=j+1 } else i++ } }' "$OUT/detect-$LABEL-minutes.tsv"
echo "== minutos con edad >= 200 s (hora_local edad_s)"
LC_ALL=C awk -F'\t' '$6+0>=200{print $1, $6}' "$OUT/detect-$LABEL-minutes.tsv"
echo "listo"

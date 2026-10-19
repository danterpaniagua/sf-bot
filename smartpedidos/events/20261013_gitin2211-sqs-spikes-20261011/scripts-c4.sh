#!/usr/bin/env bash
# Event: 20261013_sqs-spikes-20261011
# C4 — Solo lectura contra CloudWatch (AWS/SQS, us-east-1), cola PRD_BranchMessages.fifo, 10 dias a 60 s.
#      Prueba si "enviados > 0 y borrados = 0 durante >= 2 minutos seguidos" (el consumidor dejo de borrar) detecta los
#      episodios de edad alta y cuantas veces ocurre sin que la edad llegue a 250 s. Un minuto sin dato de Deleted con
#      Sent > 0 se cuenta como borrados = 0 (SQS no informa metricas sin actividad).
#      Salida: corridas de >= 2 min con inicio local, largo, visibles maximos y edad maxima hasta 6 min despues del fin.
# Uso:  bash scripts-c4.sh <etiqueta>   (etiqueta nueva por corrida; noclobber)
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
LABEL="${1:?etiqueta}"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261013_sqs-spikes-20261011/data"
Qn=PRD_BranchMessages.fifo
q() { echo "{\"Id\":\"$1\",\"Label\":\"$1\",\"ReturnData\":true,\"MetricStat\":{\"Period\":60,\"Stat\":\"$2\",\"Metric\":{\"Namespace\":\"AWS/SQS\",\"MetricName\":\"$3\",\"Dimensions\":[{\"Name\":\"QueueName\",\"Value\":\"$Qn\"}]}}}"; }
F="$OUT/c4-$LABEL-10d-60s.json"
aws cloudwatch get-metric-data --region us-east-1 --start-time 2026-10-03T03:00:00Z --end-time 2026-10-13T03:00:00Z --metric-data-queries \
"[$(q sent Sum NumberOfMessagesSent),$(q deleted Sum NumberOfMessagesDeleted),$(q visible Maximum ApproximateNumberOfMessagesVisible),$(q age Maximum ApproximateAgeOfOldestMessage)]" \
--output json > "$F"
echo "mensajes de CloudWatch: $(jq -c '.Messages' "$F") ; paginas: $(jq -r '[.MetricDataResults[]|.StatusCode]|join(",")' "$F")"
jq -r '[.MetricDataResults[]|{(.Id):([.Timestamps,.Values]|transpose|map({(.[0]):.[1]})|add)}]|add as $m
  | ($m.sent|keys)[] as $t | [$t, ($t|sub("-03:00$";"Z")|fromdateiso8601), $m.sent[$t], ($m.deleted[$t]//0), ($m.visible[$t]//0), ($m.age[$t]//0)] | @tsv' "$F" | sort > "$OUT/c4-$LABEL-minutes.tsv"
echo "minutos con Sent: $(wc -l < "$OUT/c4-$LABEL-minutes.tsv")"
echo "corridas de >= 2 min con enviados>0 y borrados=0 (inicio_local largo_min visibles_max edad_max_hasta_+6min):"
LC_ALL=C awk -F'\t' '{ts[NR]=$1; ep[NR]=$2; s[NR]=$3; d[NR]=$4; v[NR]=$5; a[NR]=$6}
  END{ i=1; while(i<=NR){ if(s[i]>0 && d[i]==0){ j=i; while(j+1<=NR && s[j+1]>0 && d[j+1]==0 && ep[j+1]==ep[j]+60) j++;
        len=j-i+1; if(len>=2){ mv=0; ma=0; for(k=1;k<=NR;k++){ if(ep[k]>=ep[i] && ep[k]<=ep[j]+360){ if(v[k]>mv) mv=v[k]; if(a[k]>ma) ma=a[k] } }
          printf "%s %d %d %d\n", ts[i], len, mv, ma } i=j+1 } else i++ } }' "$OUT/c4-$LABEL-minutes.tsv"

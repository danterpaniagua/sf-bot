#!/usr/bin/env bash
# Event: 20261015_gitin2238-mobile-caida-healthcheck-eliminado (GITIN-2238)
# C1 - SOLO LECTURA (Azure CLI, suscripcion Smart IT - Grido 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8, grupo de recursos DefaultGroup01).
#      Mide DESDE EL LADO DEL BALANCEADOR la caida de MobileAppService del 2026-10-15: disponibilidad de la sonda de salud por servidor (DipAvailability, un valor por backend) y del frontend (VipAvailability)
#      entre las 11:30 y las 16:30 UTC (08:30 a 13:30 -03:00) con granularidad de 1 minuto, y la definicion actual de las sondas. Responde: cuando dejo de enviar trafico a cada servidor, cuando volvio,
#      y si los dos servidores cayeron a la vez. Resumen: tramos continuos con disponibilidad menor a 100 por backend.
#      Salidas en data/c1/.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
SUB="0190fa7d-4ccf-4e3d-beb1-323b5780bfc8"; RG="DefaultGroup01"; LB="SFCG-MOBI-LB"
OUT="/home/dpaniagua/Documentos/git/bots/loyalty/events/20261015_gitin2238-mobile-caida-healthcheck-eliminado/data/c1"
mkdir -p "$OUT"
ID="/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Network/loadBalancers/$LB"
az monitor metrics list --subscription "$SUB" --resource "$ID" --metric DipAvailability --dimension BackendIPAddress --interval PT1M --aggregation Average --start-time 2026-10-15T11:30:00Z --end-time 2026-10-15T16:30:00Z -o json > "$OUT/dipavailability.json"
az monitor metrics list --subscription "$SUB" --resource "$ID" --metric VipAvailability --interval PT1M --aggregation Average --start-time 2026-10-15T11:30:00Z --end-time 2026-10-15T16:30:00Z -o json > "$OUT/vipavailability.json"
az network lb probe list --subscription "$SUB" -g "$RG" --lb-name "$LB" -o json > "$OUT/probes.json"
echo "== sondas actuales (nombre | protocolo | puerto | ruta | intervalo s | umbral)"; jq -r '.[]|[.name,.protocol,.port,.requestPath,.intervalInSeconds,.probeThreshold]|@tsv' "$OUT/probes.json"
echo; echo "== DipAvailability por backend: tramos con promedio < 100 (hora UTC inicio | fin | minutos | minimo)"
jq -r '.value[0].timeseries[]|(.metadatavalues[0].value) as $b|[.data[]|select(.average!=null)] as $p|reduce $p[] as $x ({runs:[],cur:null};
   if $x.average < 100 then (if .cur==null then .cur={s:$x.timeStamp,e:$x.timeStamp,m:$x.average,n:1} else (.cur.e=$x.timeStamp|.cur.n+=1|.cur.m=([.cur.m,$x.average]|min)) end)
   else (if .cur!=null then (.runs+=[.cur]|.cur=null) else . end) end)|(.runs+(if .cur then [.cur] else [] end))[]|[$b,.s[11:16],.e[11:16],.n,.m]|@tsv' "$OUT/dipavailability.json"
echo; echo "== VipAvailability (frontend): tramos con promedio < 100"
jq -r '.value[0].timeseries[0].data as $d|[$d[]|select(.average!=null)] as $p|reduce $p[] as $x ({runs:[],cur:null};
   if $x.average < 100 then (if .cur==null then .cur={s:$x.timeStamp,e:$x.timeStamp,m:$x.average,n:1} else (.cur.e=$x.timeStamp|.cur.n+=1|.cur.m=([.cur.m,$x.average]|min)) end)
   else (if .cur!=null then (.runs+=[.cur]|.cur=null) else . end) end)|(.runs+(if .cur then [.cur] else [] end))[]|[.s[11:16],.e[11:16],.n,.m]|@tsv' "$OUT/vipavailability.json"
echo listo

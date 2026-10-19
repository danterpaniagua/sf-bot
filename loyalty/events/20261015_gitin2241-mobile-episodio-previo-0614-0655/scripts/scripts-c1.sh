#!/usr/bin/env bash
# Event: 20261015_gitin2241-mobile-episodio-previo-0614-0655
# C1 - SOLO LECTURA (Azure CLI, suscripcion Smart IT - Grido 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8, grupo de recursos DefaultGroup01).
#      Disponibilidad de la sonda de salud de SFCG-MOBI-LB entre las 08:30 y las 10:30 UTC (05:30 a 07:30 -03:00) a 1 minuto, por backend (DipAvailability) y del frontend (VipAvailability),
#      para ver si y cuanto cayo cada servidor durante el episodio de 09:14-09:55 UTC que informo PediGrido. Resume los tramos con disponibilidad menor a 100.
#      Salidas en data/c1/.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
SUB="0190fa7d-4ccf-4e3d-beb1-323b5780bfc8"; RG="DefaultGroup01"; LB="SFCG-MOBI-LB"
OUT="/home/dpaniagua/Documentos/git/bots/loyalty/events/20261015_gitin2241-mobile-episodio-previo-0614-0655/data/c1"
mkdir -p "$OUT"
ID="/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Network/loadBalancers/$LB"
az monitor metrics list --subscription "$SUB" --resource "$ID" --metric DipAvailability --dimension BackendIPAddress --interval PT1M --aggregation Average --start-time 2026-10-15T08:30:00Z --end-time 2026-10-15T10:30:00Z -o json > "$OUT/dipavailability.json"
az monitor metrics list --subscription "$SUB" --resource "$ID" --metric VipAvailability --interval PT1M --aggregation Average --start-time 2026-10-15T08:30:00Z --end-time 2026-10-15T10:30:00Z -o json > "$OUT/vipavailability.json"
echo "== DipAvailability por backend: tramos con promedio < 100 (backend | inicio UTC | fin | minutos | minimo)"
jq -r '.value[0].timeseries[]|(.metadatavalues[0].value) as $b|[.data[]|select(.average!=null)] as $p|reduce $p[] as $x ({runs:[],cur:null};
   if $x.average < 100 then (if .cur==null then .cur={s:$x.timeStamp,e:$x.timeStamp,m:$x.average,n:1} else (.cur.e=$x.timeStamp|.cur.n+=1|.cur.m=([.cur.m,$x.average]|min)) end)
   else (if .cur!=null then (.runs+=[.cur]|.cur=null) else . end) end)|(.runs+(if .cur then [.cur] else [] end))[]|[$b,.s[11:16],.e[11:16],.n,.m]|@tsv' "$OUT/dipavailability.json"
echo; echo "== VipAvailability (frontend): tramos con promedio < 100"
jq -r '.value[0].timeseries[0].data as $d|[$d[]|select(.average!=null)] as $p|reduce $p[] as $x ({runs:[],cur:null};
   if $x.average < 100 then (if .cur==null then .cur={s:$x.timeStamp,e:$x.timeStamp,m:$x.average,n:1} else (.cur.e=$x.timeStamp|.cur.n+=1|.cur.m=([.cur.m,$x.average]|min)) end)
   else (if .cur!=null then (.runs+=[.cur]|.cur=null) else . end) end)|(.runs+(if .cur then [.cur] else [] end))[]|[.s[11:16],.e[11:16],.n,.m]|@tsv' "$OUT/vipavailability.json"
echo listo

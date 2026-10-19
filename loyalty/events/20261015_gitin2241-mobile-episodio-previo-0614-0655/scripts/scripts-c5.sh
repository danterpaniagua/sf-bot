#!/usr/bin/env bash
# Event: 20261015_gitin2241-mobile-episodio-previo-0614-0655 (GITIN-2241)
# C5 - SOLO LECTURA (Azure CLI, suscripcion Smart IT - Grido 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8, grupo de recursos DefaultGroup01).
#      C4 mostro que SFCG-MOBI-02 no envio datos a Zabbix de 04:00:17 a 11:50:17 UTC del 2026-10-15. Esto mira el lado de Azure en 2026-10-14 23:00 a 2026-10-15 16:30 UTC:
#      (1) VMs cuyo nombre contiene MOBI (nombre e id).
#      (2) Metricas de plataforma de cada VM a 5 min: "VmAvailabilityMetric" y "Percentage CPU": puntos con valor, y tramos sin valor (inicio, fin, minutos) y su valor minimo/maximo.
#      (3) Registro de actividad del grupo de recursos en la misma ventana, filtrado en el cliente a las VMs MOBI y a las operaciones que no son lecturas. El registro corta en 50 resultados sin paginar y --resource-id no acota
#          (docs/ memoria del repo): se imprime la cantidad devuelta y una advertencia si llega a 50. El campo "caller" NO se guarda (puede ser un correo); solo si es un usuario (contiene @) o no.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
SUB="0190fa7d-4ccf-4e3d-beb1-323b5780bfc8"; RG="DefaultGroup01"
OUT="/home/dpaniagua/Documentos/git/bots/loyalty/events/20261015_gitin2241-mobile-episodio-previo-0614-0655/data"
TS=$(date -u +%Y%m%dT%H%M%SZ); RUN="$OUT/c5-run-$TS"; mkdir -p "$RUN"
ST="2026-10-14T23:00:00Z"; EN="2026-10-15T16:30:00Z"
echo "run $TS | ventana $ST a $EN"
az vm list --subscription "$SUB" -g "$RG" --query "[?contains(name,'MOBI')].{name:name,id:id}" -o json > "$RUN/vms.json"
echo "== VMs MOBI: $(jq length "$RUN/vms.json")"; jq -r '.[]|.name' "$RUN/vms.json"
jq -c '.[]' "$RUN/vms.json" | while read -r vm; do
  name=$(jq -r .name <<<"$vm"); id=$(jq -r .id <<<"$vm")
  for metric in VmAvailabilityMetric "Percentage CPU"; do
    f="$RUN/metric-$name-${metric// /_}.json"
    if az monitor metrics list --subscription "$SUB" --resource "$id" --metric "$metric" --interval PT5M --aggregation Average --start-time "$ST" --end-time "$EN" -o json > "$f" 2> "$f.err"; then
      echo; echo "== $name | $metric"
      jq -r '.value[0].timeseries[0].data as $d|"   puntos=\($d|length) con valor=\([$d[]|select(.average!=null)]|length) min=\([$d[]|.average|select(.!=null)]|min) max=\([$d[]|.average|select(.!=null)]|max)",
        "   tramos sin valor (inicio -> fin, puntos de 5 min):",
        ([range(0;$d|length)|select($d[.].average==null and (.==0 or $d[.-1].average!=null))] as $s
          |[$s[]|. as $i|([range($i;$d|length)|select($d[.].average!=null)]|.[0]//($d|length)) as $e|"     \($d[$i].timeStamp[11:16]) -> \(if $e<($d|length) then $d[$e].timeStamp[11:16] else "fin de ventana" end) (\($e-$i) puntos)"]
          |if length==0 then ["     ninguno"] else .[0:20] end|.[])' "$f"
    else
      echo; echo "== $name | $metric | la metrica no se pudo leer: $(head -c 300 "$f.err")"
    fi
  done
done
echo; echo "== registro de actividad del grupo $RG (todas las filas, sin lecturas), filtrado en el cliente a recursos MOBI"
az monitor activity-log list --subscription "$SUB" --resource-group "$RG" --start-time "$ST" --end-time "$EN" \
  --query "[].{t:eventTimestamp,op:operationName.value,st:status.value,sub:subStatus.value,rid:resourceId,user:contains(to_string(caller),'@')}" -o json > "$RUN/activity.json"
N=$(jq length "$RUN/activity.json"); echo "filas devueltas: $N"; [ "$N" -ge 50 ] && echo "ADVERTENCIA: 50 filas = tope del comando; el resultado puede estar cortado (acotar la ventana)"
jq -r '.[]|select((.rid|test("MOBI";"i")) and (.op|test("read|list";"i")|not))|[.t[0:19],.op,.st,.sub,("usuario="+(.user|tostring)),(.rid|split("/")|last)]|@tsv' "$RUN/activity.json" | sort | head -60
echo; echo "guardado en $RUN"

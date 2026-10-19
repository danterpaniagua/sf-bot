#!/usr/bin/env bash
# Event: 20261014_gitin2222-ecs-reinicios-avisos-sns
# C32 - SOLO LECTURA contra la API de Zabbix (6.0.32; token en $ZABBIX_API_KEY).
#       El usuario dice que no creo las macros {$AWS.ECS.CLUSTER.SERVICE.RUNNING.DIP}=1000 de los hosts descubiertos (ids 7451, 7455, 7459) y los scripts de este ticket tampoco.
#       Este script consulta el REGISTRO DE AUDITORIA de Zabbix (auditlog.get) de las ultimas 36 h para esos recursos y, como referencia, para las macros que si se conocen
#       (7446, 7447 de este ticket; 7448-7450 del ticket del Graylog), el prototipo de host 10620 y los tres hosts descubiertos: quien (id de usuario; el nombre se enmascara), cuando, que accion, desde que red (IP enmascarada)
#       y los detalles recortados. Requiere que la auditoria este habilitada en Administracion -> General -> Registro de auditoria; si no hay filas, no significa que nadie lo hizo.
#       Salidas en data/c32/.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/data/c32"
mkdir -p "$OUT"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
FROM=$(( $(date +%s) - 36*3600 ))
call auditlog.get "$(jq -n --argjson f "$FROM" '{output:"extend",time_from:$f,filter:{resourceid:["7446","7447","7448","7449","7450","7451","7455","7459","10620","10666","10667","10668"]},sortfield:"clock",sortorder:"ASC",limit:500}')" > "$OUT/auditlog.json"
echo "== filas de auditoria (36 h): $(jq length "$OUT/auditlog.json")"
echo "== hora UTC | usuario (id; nombre enmascarado) | accion 0=alta 1=cambio 2=baja 3=ingreso 4=salida 9=ejecucion | tipo de recurso | recurso (id nombre) | red (IP /24) | detalles (200 car.)"
jq -r '.[]|[(.clock|tonumber|strftime("%m-%d %H:%M:%S")),("u"+(.userid // "-")+" ("+((.username // "-")|.[0:2]+"***")+")"),.action,.resourcetype,((.resourceid // "-")+" "+(.resourcename // "")),((.ip // "-")|sub("\\.[0-9]+$";".x")),((.details // "")|gsub("\n";" ")|.[0:200])]|@tsv' "$OUT/auditlog.json"
echo listo

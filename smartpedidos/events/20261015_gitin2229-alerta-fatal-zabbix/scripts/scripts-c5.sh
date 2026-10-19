#!/usr/bin/env bash
# Event: 20261015_gitin2229-alerta-fatal-zabbix
# C5 - Zabbix 6.0.32 (sf-monitoreo.smartfran.com:8080; token en $ZABBIX_API_KEY). Crea en el host "Zabbix server" (10084):
#      - 2 macros de host: {$GRAYLOG.PLATFORM.FATAL.MAX}=0 y {$GRAYLOG.NODATA.WINDOW}=10m
#      - item HTTP agent "Graylog: Platform FATAL messages (last 5 min)" (clave graylog.platform.fatal.count): GET a la API de Graylog de SmartPedidos
#        (search/universal/relative, rango 300 s, consulta msg_level:FATAL AND msg_service:"platforms-service"), autenticacion Basic con usuario {$SML_GRAYLOG_API_KEY} y clave "token",
#        preprocesado JSONPath $.total_results, intervalo 1m, historia 14d, tendencias 365d
#      - trigger "Graylog: Platform FATAL detected" (High): last(item) > {$GRAYLOG.PLATFORM.FATAL.MAX}
#      - trigger "Graylog: Platform FATAL check without data" (Average): nodata(item, {$GRAYLOG.NODATA.WINDOW})=1
#      Tags de ambos: scope=availability, service=platform-service, action=GCHAT, scope=OPE, scope=SP (los toma la accion 11 "Google Chat SmartPedidos to Operaciones", GITIN-2222).
#      Modos: dry (por defecto, SOLO LECTURA) | apply (CAMBIA ESTADO) | rollback <carpeta c5-run-...> (CAMBIA ESTADO: borra triggers, item y macros creados, segun los ids guardados)
#      Guardas: cuenta/host correctos; la macro {$SML_GRAYLOG_API_KEY} debe existir en el host y ser de tipo secreto (1); la clave del item no debe existir.
#      El valor de la macro secreta nunca se lee ni se escribe.
#      v2 (tras el fallo del primer apply: formato de headers en 6.0): headers como objeto {nombre: valor}; los parametros de busqueda van codificados en la URL (query_fields vacio);
#      las dos macros nuevas pueden existir ya (creadas por el primer apply, ids 7449 y 7450): se reutilizan si su valor es el esperado.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
MODE="${1:-dry}"; SNAP="${2:-}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261015_gitin2229-alerta-fatal-zabbix/data"
HOSTID=10084; KEY="graylog.platform.fatal.count"; HN="Zabbix server"
QUERY='msg_level:FATAL AND msg_service:"platforms-service"'
URL="http://sf-monitoreo.smartfran.com:9000/api/search/universal/relative"
TS=$(date -u +%Y%m%dT%H%M%SZ); RUN="$OUT/c5-run-$TS"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }

if [ "$MODE" = "rollback" ]; then
  [ -f "$SNAP/created-ids.json" ] || { echo "uso: $0 rollback <carpeta c5-run-...> (falta created-ids.json)"; exit 1; }
  for t in $(jq -r '.triggerids[]?' "$SNAP/created-ids.json"); do call trigger.delete "[\"$t\"]" >/dev/null; echo "trigger $t borrado"; done
  for i in $(jq -r '.itemids[]?' "$SNAP/created-ids.json"); do call item.delete "[\"$i\"]" >/dev/null; echo "item $i borrado"; done
  for m in $(jq -r '.macroids[]?' "$SNAP/created-ids.json"); do call usermacro.delete "[\"$m\"]" >/dev/null; echo "macro $m borrada"; done
  echo "rollback aplicado desde $SNAP"; exit 0
fi

mkdir -p "$RUN"; echo "modo=$MODE | $TS | carpeta $RUN"
call host.get "{\"hostids\":[\"$HOSTID\"],\"output\":[\"hostid\",\"name\",\"status\",\"flags\"]}" > "$RUN/before-host.json"
jq -e --arg n "$HN" '.[0].name==$n and .[0].flags=="0" and .[0].status=="0"' "$RUN/before-host.json" >/dev/null || { echo "GUARDA: el host $HOSTID no es '$HN' manual y activo"; exit 1; }
call usermacro.get "{\"hostids\":[\"$HOSTID\"],\"output\":[\"hostmacroid\",\"macro\",\"type\"],\"filter\":{\"macro\":[\"{\$SML_GRAYLOG_API_KEY}\",\"{\$GRAYLOG.PLATFORM.FATAL.MAX}\",\"{\$GRAYLOG.NODATA.WINDOW}\"]}}" > "$RUN/before-macros.json"
call usermacro.get "{\"hostids\":[\"$HOSTID\"],\"output\":[\"hostmacroid\",\"macro\",\"value\"],\"filter\":{\"macro\":[\"{\$GRAYLOG.PLATFORM.FATAL.MAX}\",\"{\$GRAYLOG.NODATA.WINDOW}\"]}}" > "$RUN/before-new-macros.json"
jq -e '[.[]|select(.macro=="{$SML_GRAYLOG_API_KEY}" and .type=="1")]|length==1' "$RUN/before-macros.json" >/dev/null || { echo "GUARDA: la macro {\$SML_GRAYLOG_API_KEY} no existe en el host o no es de tipo secreto (1). Cambiarla a 'Secret text' en el frontend."; exit 1; }
jq -e '[.[]|select(.macro=="{$GRAYLOG.PLATFORM.FATAL.MAX}" and .value!="0")]|length==0' "$RUN/before-new-macros.json" >/dev/null || { echo "GUARDA: {\$GRAYLOG.PLATFORM.FATAL.MAX} existe con un valor distinto de 0"; exit 1; }
jq -e '[.[]|select(.macro=="{$GRAYLOG.NODATA.WINDOW}" and .value!="10m")]|length==0' "$RUN/before-new-macros.json" >/dev/null || { echo "GUARDA: {\$GRAYLOG.NODATA.WINDOW} existe con un valor distinto de 10m"; exit 1; }
echo "macros nuevas ya existentes (se reutilizan): $(jq -c '[.[].macro]' "$RUN/before-new-macros.json")"
call item.get "{\"hostids\":[\"$HOSTID\"],\"filter\":{\"key_\":\"$KEY\"},\"output\":[\"itemid\"]}" > "$RUN/before-item.json"
jq -e 'length==0' "$RUN/before-item.json" >/dev/null || { echo "GUARDA: la clave $KEY ya existe en el host"; exit 1; }

QS="query=$(jq -rn --arg q "$QUERY" '$q|@uri')&range=300&limit=1&fields=timestamp"
ITEM=$(jq -n --arg host "$HOSTID" --arg key "$KEY" --arg url "$URL?$QS" '{
  hostid:$host, name:"Graylog: Platform FATAL messages (last 5 min)", key_:$key, type:19, value_type:3, delay:"1m", history:"14d", trends:"365d",
  url:$url, request_method:0, retrieve_mode:0, timeout:"10s", authtype:1, username:"{$SML_GRAYLOG_API_KEY}", password:"token",
  headers:{Accept:"application/json"},
  description:"GITIN-2229. Cantidad de mensajes [INFRA/FATAL] de platforms-service en los ultimos 5 minutos (API REST de Graylog de SmartPedidos).",
  preprocessing:[{type:"12",params:"$.total_results",error_handler:"0",error_handler_params:""}]}')
TAGS='[{"tag":"scope","value":"availability"},{"tag":"service","value":"platform-service"},{"tag":"action","value":"GCHAT"},{"tag":"scope","value":"OPE"},{"tag":"scope","value":"SP"}]'
TRG1=$(jq -n --argjson tags "$TAGS" --arg e "last(/$HN/$KEY)>{\$GRAYLOG.PLATFORM.FATAL.MAX}" '{description:"Graylog: Platform FATAL detected", expression:$e, priority:4, manual_close:0, opdata:"FATAL en los ultimos 5 min: {ITEM.LASTVALUE1}", comments:"GITIN-2229. Mensajes [INFRA/FATAL] de platforms-service en Graylog: el proceso termina con process.exit(1) (GITIN-2222).", tags:$tags}')
TRG2=$(jq -n --argjson tags "$TAGS" --arg e "nodata(/$HN/$KEY,{\$GRAYLOG.NODATA.WINDOW})=1" '{description:"Graylog: Platform FATAL check without data", expression:$e, priority:3, manual_close:0, comments:"GITIN-2229. El item que consulta Graylog no devuelve datos (Graylog inaccesible, token invalido o consulta con error).", tags:$tags}')
echo "$ITEM" | jq 'del(.password)' > "$RUN/new-item.json"; echo "$TRG1" > "$RUN/new-trigger1.json"; echo "$TRG2" > "$RUN/new-trigger2.json"
echo "== item (sin password)"; jq -c '{name,key_,delay,url,headers,authtype,username}' "$RUN/new-item.json"
echo "== triggers"; jq -r '.expression' "$RUN/new-trigger1.json" "$RUN/new-trigger2.json"
if [ "$MODE" != "apply" ]; then echo "DRY: no se cambio nada. Para aplicar: $0 apply"; exit 0; fi

# --- apply (cambia estado)
mk() { # $1 macro, $2 valor, $3 descripcion -> imprime el hostmacroid (existente o nuevo)
  local id; id=$(jq -r --arg m "$1" '.[]|select(.macro==$m)|.hostmacroid' "$RUN/before-new-macros.json")
  if [ -n "$id" ]; then echo "$id"; else call usermacro.create "$(jq -n --arg h "$HOSTID" --arg m "$1" --arg v "$2" --arg d "$3" '{hostid:$h,macro:$m,value:$v,description:$d}')" | jq -r '.hostmacroids[0]'; fi
}
M1=$(mk '{$GRAYLOG.PLATFORM.FATAL.MAX}' 0 'GITIN-2229: umbral de mensajes FATAL de Platform en 5 min')
M2=$(mk '{$GRAYLOG.NODATA.WINDOW}' 10m 'GITIN-2229: ventana de nodata del item de Graylog')
echo "{\"macroids\":[\"$M1\",\"$M2\"],\"itemids\":[],\"triggerids\":[]}" > "$RUN/created-ids.json"
I=$(call item.create "$ITEM" | jq -r '.itemids[0]')
jq --arg i "$I" '.itemids=[$i]' "$RUN/created-ids.json" > "$RUN/c.tmp" && mv "$RUN/c.tmp" "$RUN/created-ids.json"
T1=$(call trigger.create "$TRG1" | jq -r '.triggerids[0]')
T2=$(call trigger.create "$TRG2" | jq -r '.triggerids[0]')
jq --arg a "$T1" --arg b "$T2" '.triggerids=[$a,$b]' "$RUN/created-ids.json" > "$RUN/c.tmp" && mv "$RUN/c.tmp" "$RUN/created-ids.json"
cat "$RUN/created-ids.json"
echo "esperando 75 s a la primera lectura del item..."; sleep 75
call item.get "{\"itemids\":[\"$I\"],\"output\":[\"itemid\",\"state\",\"lastvalue\",\"lastclock\",\"error\"]}" > "$RUN/after-item.json"
jq -c '.[0]|{itemid,state,lastvalue,lastclock,error}' "$RUN/after-item.json"
call trigger.get "{\"triggerids\":[\"$T1\",\"$T2\"],\"output\":[\"triggerid\",\"description\",\"value\",\"state\",\"error\"],\"selectTags\":\"extend\"}" > "$RUN/after-triggers.json"
jq -c '.[]|{triggerid,description,value,state,error}' "$RUN/after-triggers.json"
echo "aplicado. Rollback: $0 rollback $RUN"

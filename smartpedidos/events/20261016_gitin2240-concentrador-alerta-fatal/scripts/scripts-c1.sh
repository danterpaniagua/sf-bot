#!/usr/bin/env bash
# Event: 20261016_gitin2240-concentrador-alerta-fatal
# C1 - Zabbix 6.0.32 (sf-monitoreo.smartfran.com:8080; token en $ZABBIX_API_KEY). Misma regla que GITIN-2229 (Platform), para concentrador-service. Pedido del usuario: crearla aunque hoy no haya mensajes FATAL.
#      Crea en el host "Zabbix server" (10084):
#      - macro de host {$GRAYLOG.CONCENTRADOR.FATAL.MAX}=0 (la ventana {$GRAYLOG.NODATA.WINDOW}=10m YA existe, es la de GITIN-2229: se reutiliza y el rollback NO la borra)
#      - item HTTP agent "Graylog: Concentrador FATAL messages (last 5 min)" (clave graylog.concentrador.fatal.count): GET a la API de Graylog de SmartPedidos (search/universal/relative, rango 300 s,
#        consulta msg_level:FATAL AND msg_service:"concentrador-service"), autenticacion Basic con usuario {$SML_GRAYLOG_API_KEY} y clave "token", JSONPath $.total_results, 1m, historia 14d, tendencias 365d
#      - trigger "Graylog: Concentrador FATAL detected" (High): last(item) > {$GRAYLOG.CONCENTRADOR.FATAL.MAX}
#      - trigger "Graylog: Concentrador FATAL check without data" (Average): nodata(item, {$GRAYLOG.NODATA.WINDOW})=1
#      Etiquetas de ambos: las de Platform (scope=availability, service=concentrador-service, action=GCHAT, scope=OPE, scope=SP) + friendlyname y SVC_FRIENDLYNAME = "Graylog FATAL Concentrador" + env=PROD
#      (asi las toman desde el inicio la accion 11, la 12 y el dashboard).
#      OJO: concentrador-service hoy NO registra FATAL (GITIN-2229, C7): el item devolvera 0 y el trigger High no se abrira hasta que Desarrollo agregue el registro FATAL (GITIN-1477). El trigger "sin datos" si avisa si Graylog o el token fallan.
#      Modos: dry (por defecto, SOLO LECTURA; ademas consulta Graylog con la misma consulta, si SML_GRAYLOG_API_KEY esta definida) | apply (CAMBIA ESTADO) | rollback <carpeta c1-run-...> (CAMBIA ESTADO)
#      Guardas: host correcto; la macro {$SML_GRAYLOG_API_KEY} debe existir y ser secreta (tipo 1); {$GRAYLOG.NODATA.WINDOW} debe existir con 10m; la clave del item no debe existir. Ningun secreto se lee ni se imprime.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
MODE="${1:-dry}"; SNAP="${2:-}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261016_gitin2240-concentrador-alerta-fatal/data"
HOSTID=10084; KEY="graylog.concentrador.fatal.count"; HN="Zabbix server"; MAC="{\$GRAYLOG.CONCENTRADOR.FATAL.MAX}"
QUERY='msg_level:FATAL AND msg_service:"concentrador-service"'
URL="http://sf-monitoreo.smartfran.com:9000/api/search/universal/relative"
TS=$(date -u +%Y%m%dT%H%M%SZ); RUN="$OUT/c1-run-$TS"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }

if [ "$MODE" = "rollback" ]; then
  [ -f "$SNAP/created-ids.json" ] || { echo "uso: $0 rollback <carpeta c1-run-...> (falta created-ids.json)"; exit 1; }
  for t in $(jq -r '.triggerids[]?' "$SNAP/created-ids.json"); do call trigger.delete "[\"$t\"]" >/dev/null; echo "trigger $t borrado"; done
  for i in $(jq -r '.itemids[]?' "$SNAP/created-ids.json"); do call item.delete "[\"$i\"]" >/dev/null; echo "item $i borrado"; done
  for m in $(jq -r '.macroids[]?' "$SNAP/created-ids.json"); do call usermacro.delete "[\"$m\"]" >/dev/null; echo "macro $m borrada"; done
  echo "rollback aplicado desde $SNAP"; exit 0
fi

mkdir -p "$RUN"; echo "modo=$MODE | $TS | carpeta $RUN"
call host.get "{\"hostids\":[\"$HOSTID\"],\"output\":[\"hostid\",\"name\",\"status\",\"flags\"]}" > "$RUN/before-host.json"
jq -e --arg n "$HN" '.[0].name==$n and .[0].flags=="0" and .[0].status=="0"' "$RUN/before-host.json" >/dev/null || { echo "GUARDA: el host $HOSTID no es '$HN' manual y activo"; exit 1; }
call usermacro.get "{\"hostids\":[\"$HOSTID\"],\"output\":[\"hostmacroid\",\"macro\",\"type\",\"value\"],\"filter\":{\"macro\":[\"{\$SML_GRAYLOG_API_KEY}\",\"$MAC\",\"{\$GRAYLOG.NODATA.WINDOW}\"]}}" > "$RUN/before-macros-con-valor.json"
jq '[.[]|if .type=="1" then del(.value) else . end]' "$RUN/before-macros-con-valor.json" > "$RUN/before-macros.json"; rm -f "$RUN/before-macros-con-valor.json"
jq -e '[.[]|select(.macro=="{$SML_GRAYLOG_API_KEY}" and .type=="1")]|length==1' "$RUN/before-macros.json" >/dev/null || { echo "GUARDA: la macro {\$SML_GRAYLOG_API_KEY} no existe en el host o no es de tipo secreto (1)"; exit 1; }
jq -e '[.[]|select(.macro=="{$GRAYLOG.NODATA.WINDOW}" and .value=="10m")]|length==1' "$RUN/before-macros.json" >/dev/null || { echo "GUARDA: {\$GRAYLOG.NODATA.WINDOW} no existe con el valor 10m"; exit 1; }
jq -e --arg m "$MAC" '[.[]|select(.macro==$m and .value!="0")]|length==0' "$RUN/before-macros.json" >/dev/null || { echo "GUARDA: $MAC existe con un valor distinto de 0"; exit 1; }
call item.get "{\"hostids\":[\"$HOSTID\"],\"filter\":{\"key_\":\"$KEY\"},\"output\":[\"itemid\"]}" > "$RUN/before-item.json"
jq -e 'length==0' "$RUN/before-item.json" >/dev/null || { echo "GUARDA: la clave $KEY ya existe en el host"; exit 1; }

# consulta de solo lectura a Graylog con la misma consulta (la clave va por stdin a curl, no queda en la lista de procesos)
if [ -n "${SML_GRAYLOG_API_KEY:-}" ]; then
  for R in 300 604800; do
    CODE=$(printf 'user = "%s:token"\n' "$SML_GRAYLOG_API_KEY" | curl -sS -K - -G -H 'Accept: application/json' -o "$RUN/graylog-$R.json" -w '%{http_code}' --data-urlencode "query=$QUERY" --data-urlencode "range=$R" --data-urlencode "limit=1" --data-urlencode "fields=timestamp" "$URL" || true)
    echo "Graylog rango ${R}s: HTTP $CODE | cuerpo=$(wc -c < "$RUN/graylog-$R.json") bytes | total_results=$(jq -r '.total_results // "sin total"' "$RUN/graylog-$R.json" 2>/dev/null || echo "cuerpo no es JSON")"
  done
else
  echo "Graylog: SML_GRAYLOG_API_KEY no definida en el entorno, se omite la consulta de verificacion"
fi

QS="query=$(jq -rn --arg q "$QUERY" '$q|@uri')&range=300&limit=1&fields=timestamp"
ITEM=$(jq -n --arg host "$HOSTID" --arg key "$KEY" --arg url "$URL?$QS" '{
  hostid:$host, name:"Graylog: Concentrador FATAL messages (last 5 min)", key_:$key, type:19, value_type:3, delay:"1m", history:"14d", trends:"365d",
  url:$url, request_method:0, retrieve_mode:0, timeout:"10s", authtype:1, username:"{$SML_GRAYLOG_API_KEY}", password:"token",
  headers:{Accept:"application/json"},
  description:"GITIN-2240. Cantidad de mensajes [INFRA/FATAL] de concentrador-service en los ultimos 5 minutos (API REST de Graylog de SmartPedidos). Hoy el servicio no registra FATAL: el valor es 0 hasta que Desarrollo lo agregue (GITIN-1477).",
  preprocessing:[{type:"12",params:"$.total_results",error_handler:"0",error_handler_params:""}]}')
TAGS='[{"tag":"scope","value":"availability"},{"tag":"service","value":"concentrador-service"},{"tag":"action","value":"GCHAT"},{"tag":"scope","value":"OPE"},{"tag":"scope","value":"SP"},{"tag":"SVC_FRIENDLYNAME","value":"Graylog FATAL Concentrador"},{"tag":"friendlyname","value":"Graylog FATAL Concentrador"},{"tag":"env","value":"PROD"}]'
TRG1=$(jq -n --argjson tags "$TAGS" --arg e "last(/$HN/$KEY)>$MAC" '{description:"Graylog: Concentrador FATAL detected", expression:$e, priority:4, manual_close:0, opdata:"FATAL en los ultimos 5 min: {ITEM.LASTVALUE1}", comments:"GITIN-2240. Mensajes [INFRA/FATAL] de concentrador-service en Graylog. No se abrira hasta que el servicio registre FATAL (GITIN-1477).", tags:$tags}')
TRG2=$(jq -n --argjson tags "$TAGS" --arg e "nodata(/$HN/$KEY,{\$GRAYLOG.NODATA.WINDOW})=1" '{description:"Graylog: Concentrador FATAL check without data", expression:$e, priority:3, manual_close:0, comments:"GITIN-2240. El item que consulta Graylog no devuelve datos (Graylog inaccesible, token invalido o consulta con error).", tags:$tags}')
echo "$ITEM" | jq 'del(.password)' > "$RUN/new-item.json"; echo "$TRG1" > "$RUN/new-trigger1.json"; echo "$TRG2" > "$RUN/new-trigger2.json"
echo "== item (sin password)"; jq -c '{name,key_,delay,url,headers,authtype,username}' "$RUN/new-item.json"
echo "== triggers"; jq -r '.expression' "$RUN/new-trigger1.json" "$RUN/new-trigger2.json"
echo "== etiquetas"; jq -c '[.tags[]|"\(.tag)=\(.value)"]' "$RUN/new-trigger1.json"
if [ "$MODE" != "apply" ]; then echo "DRY: no se cambio nada. Para aplicar: $0 apply"; exit 0; fi

# --- apply (cambia estado)
MID=$(jq -r --arg m "$MAC" '.[]|select(.macro==$m)|.hostmacroid' "$RUN/before-macros.json")
[ -n "$MID" ] || MID=$(call usermacro.create "$(jq -n --arg h "$HOSTID" --arg m "$MAC" '{hostid:$h,macro:$m,value:"0",description:"GITIN-2240: umbral de mensajes FATAL de Concentrador en 5 min"}')" | jq -r '.hostmacroids[0]')
echo "{\"macroids\":[\"$MID\"],\"itemids\":[],\"triggerids\":[]}" > "$RUN/created-ids.json"
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
jq -c '.[]|{triggerid,description,value,state,error,tags:[.tags[]|"\(.tag)=\(.value)"]}' "$RUN/after-triggers.json"
echo "aplicado. Rollback: $0 rollback $RUN"

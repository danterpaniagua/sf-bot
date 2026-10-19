#!/usr/bin/env bash
# Event: 20261015_gitin2239-mobile-healthcheck-alerta-zabbix (GITIN-2239)
# C2 - Zabbix 6.0.32 (sf-monitoreo.smartfran.com:8080; token en $ZABBIX_API_KEY). Crea, para cada healthcheck PROD con escenario web (hoy [PROD] MobileApp y [PROD] WebServiceV2, host "Zabbix Proxy"):
#      - trigger HIGH  "Healthcheck <escenario>: HTTP code not 200": count(codigo,{$HC.FAIL.WINDOW},"ne",200)>={$HC.FAIL.MIN} or nodata(codigo,{$HC.NODATA.WINDOW})=1
#      - trigger WARNING "Healthcheck <escenario>: slow response": avg(tiempo,{$HC.RESP.WINDOW})>{$HC.RESP.WARN}, recuperacion avg(...)<{$HC.RESP.WARN.RECOVERY}; depende del trigger HIGH del mismo healthcheck
#      Todos los umbrales van en macros del host: HC.FAIL.WINDOW=3m, HC.FAIL.MIN=3, HC.NODATA.WINDOW=3m, HC.RESP.WINDOW=5m, HC.RESP.WARN=2 (segundos), HC.RESP.WARN.RECOVERY=1.6
#      Etiquetas de tarjeta del Chat: SVC_FRIENDLYNAME (titulo del problema) y friendlyname en minuscula (titulo de la recuperacion), como en los triggers de Mobile (GITIN-2156).
#      Etiquetas (ruta a la accion 7 "Google Chat Loyalty to Operaciones"): scope=OPE, scope=GIT-SML-OPE, service_group=LOYALTY, action=GCHAT, check=healthcheck, service=<escenario>
#      No toca los triggers existentes de WebServiceV2 (26860, 26861).
#      Modos: dry (por defecto, SOLO LECTURA) | apply (CAMBIA ESTADO) | rollback <carpeta c2-run-...> (CAMBIA ESTADO: borra triggers y macros creados, segun los ids guardados)
#      Guardas: el host y sus items existen; ninguna de las macros ni de los triggers nuevos existe ya. Hipotesis no verificada: que Zabbix 6.0 acepte el operador "ne" y macros como periodo en count()/avg()/nodata(); si el servidor los rechaza, el apply se detiene en el primer trigger.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
MODE="${1:-dry}"; SNAP="${2:-}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/loyalty/events/20261015_gitin2239-mobile-healthcheck-alerta-zabbix/data"
HOSTID=10610
TS=$(date -u +%Y%m%dT%H%M%SZ); RUN="$OUT/c2-run-$TS"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }

if [ "$MODE" = "rollback" ]; then
  [ -f "$SNAP/created-ids.json" ] || { echo "uso: $0 rollback <carpeta c2-run-...> (falta created-ids.json)"; exit 1; }
  for t in $(jq -r '.triggerids_slow[]?, .triggerids_code[]?' "$SNAP/created-ids.json"); do call trigger.delete "[\"$t\"]" >/dev/null; echo "trigger $t borrado"; done
  for m in $(jq -r '.macroids[]?' "$SNAP/created-ids.json"); do call usermacro.delete "[\"$m\"]" >/dev/null; echo "macro $m borrada"; done
  echo "rollback aplicado desde $SNAP"; exit 0
fi

mkdir -p "$RUN"; echo "modo=$MODE | $TS | carpeta $RUN"
HCS='[{"svc":"MobileApp","scn":"[PROD] MobileApp","step":"healthcheck"},{"svc":"WebServiceV2","scn":"[PROD] WebServiceV2","step":"Healthcheck"}]'
call host.get "{\"hostids\":[\"$HOSTID\"],\"output\":[\"hostid\",\"host\",\"name\",\"status\"]}" > "$RUN/before-host.json"
jq -e '.[0].name=="Zabbix Proxy" and .[0].status=="0"' "$RUN/before-host.json" >/dev/null || { echo "GUARDA: el host $HOSTID no es 'Zabbix Proxy' activo"; exit 1; }
HOST=$(jq -r '.[0].host' "$RUN/before-host.json"); echo "nombre tecnico del host para las expresiones: $HOST"
KEYS=$(jq -c --argjson h "$HCS" '[ $h[] | ("web.test.rspcode[\"\(.scn)\",\(.step)]", "web.test.time[\"\(.scn)\",\(.step),resp]") ]' <<<null)
call item.get "$(jq -n --argjson k "$KEYS" --arg h "$HOSTID" '{webitems:true,hostids:[$h],filter:{key_:$k},output:["itemid","key_","value_type","units"]}')" > "$RUN/before-items.json"
jq -e --argjson k "$KEYS" '(map(.key_)|sort)==($k|sort)' "$RUN/before-items.json" >/dev/null || { echo "GUARDA: no estan los 4 items esperados en el host. Encontrados: $(jq -c '[.[].key_]' "$RUN/before-items.json")"; exit 1; }
MACROS='[{"m":"{$HC.FAIL.WINDOW}","v":"3m","d":"GITIN-2239: ventana para contar respuestas distintas de 200 en un healthcheck"},{"m":"{$HC.FAIL.MIN}","v":"3","d":"GITIN-2239: cantidad minima de respuestas distintas de 200 en la ventana"},{"m":"{$HC.NODATA.WINDOW}","v":"3m","d":"GITIN-2239: ventana sin datos (timeouts o conexion cortada) de un healthcheck"},{"m":"{$HC.RESP.WINDOW}","v":"5m","d":"GITIN-2239: ventana del promedio de tiempo de respuesta"},{"m":"{$HC.RESP.WARN}","v":"2","d":"GITIN-2239: umbral de respuesta lenta (segundos)"},{"m":"{$HC.RESP.WARN.RECOVERY}","v":"1.6","d":"GITIN-2239: recuperacion de respuesta lenta (segundos)"}]'
call usermacro.get "$(jq -n --arg h "$HOSTID" --argjson m "$(jq -c '[.[].m]' <<<"$MACROS")" '{hostids:[$h],output:["macro"],filter:{macro:$m}}')" > "$RUN/before-macros.json"
jq -e 'length==0' "$RUN/before-macros.json" >/dev/null || { echo "GUARDA: ya existe alguna macro HC.*: $(jq -c '[.[].macro]' "$RUN/before-macros.json")"; exit 1; }
DESCS=$(jq -c --argjson h "$HCS" '[ $h[] | ("Healthcheck \(.scn): HTTP code not 200", "Healthcheck \(.scn): slow response") ]' <<<null)
call trigger.get "$(jq -n --arg h "$HOSTID" --argjson d "$DESCS" '{hostids:[$h],filter:{description:$d},output:["triggerid","description"]}')" > "$RUN/before-triggers.json"
jq -e 'length==0' "$RUN/before-triggers.json" >/dev/null || { echo "GUARDA: ya existen triggers con esos nombres"; exit 1; }

TAGS() { jq -nc --arg s "$1" '[{tag:"scope",value:"OPE"},{tag:"scope",value:"GIT-SML-OPE"},{tag:"service_group",value:"LOYALTY"},{tag:"action",value:"GCHAT"},{tag:"check",value:"healthcheck"},{tag:"service",value:$s},{tag:"SVC_FRIENDLYNAME",value:("Healthcheck "+$s)},{tag:"friendlyname",value:("Healthcheck "+$s)}]'; }
CODE_EXPR() { echo "count(/$HOST/web.test.rspcode[\"$1\",$2],{\$HC.FAIL.WINDOW},\"ne\",200)>={\$HC.FAIL.MIN} or nodata(/$HOST/web.test.rspcode[\"$1\",$2],{\$HC.NODATA.WINDOW})=1"; }
SLOW_EXPR() { echo "avg(/$HOST/web.test.time[\"$1\",$2,resp],{\$HC.RESP.WINDOW})>{\$HC.RESP.WARN}"; }
SLOW_REC()  { echo "avg(/$HOST/web.test.time[\"$1\",$2,resp],{\$HC.RESP.WINDOW})<{\$HC.RESP.WARN.RECOVERY}"; }
echo "== triggers que se crearian"
for i in $(seq 0 $(( $(jq length <<<"$HCS") - 1 ))); do
  SCN=$(jq -r ".[$i].scn" <<<"$HCS"); STEP=$(jq -r ".[$i].step" <<<"$HCS")
  echo "- HIGH    Healthcheck $SCN: HTTP code not 200  ::  $(CODE_EXPR "$SCN" "$STEP")"
  echo "- WARNING Healthcheck $SCN: slow response  ::  $(SLOW_EXPR "$SCN" "$STEP")  | recuperacion: $(SLOW_REC "$SCN" "$STEP")"
done
echo "== macros: $(jq -r '[.[]|"\(.m)=\(.v)"]|join(", ")' <<<"$MACROS")"
if [ "$MODE" != "apply" ]; then echo "DRY: no se cambio nada. Para aplicar: $0 apply"; exit 0; fi

# --- apply (cambia estado)
echo '{"macroids":[],"triggerids_code":[],"triggerids_slow":[]}' > "$RUN/created-ids.json"
for k in $(seq 0 $(( $(jq length <<<"$MACROS") - 1 ))); do
  ID=$(call usermacro.create "$(jq -n --arg h "$HOSTID" --argjson m "$(jq -c ".[$k]" <<<"$MACROS")" '{hostid:$h,macro:$m.m,value:$m.v,description:$m.d}')" | jq -r '.hostmacroids[0]')
  jq --arg i "$ID" '.macroids+=[$i]' "$RUN/created-ids.json" > "$RUN/c.tmp" && mv "$RUN/c.tmp" "$RUN/created-ids.json"
done
for i in $(seq 0 $(( $(jq length <<<"$HCS") - 1 ))); do
  SVC=$(jq -r ".[$i].svc" <<<"$HCS"); SCN=$(jq -r ".[$i].scn" <<<"$HCS"); STEP=$(jq -r ".[$i].step" <<<"$HCS")
  T1=$(call trigger.create "$(jq -n --arg d "Healthcheck $SCN: HTTP code not 200" --arg e "$(CODE_EXPR "$SCN" "$STEP")" --argjson tags "$(TAGS "$SVC")" '{description:$d,expression:$e,priority:4,manual_close:0,opdata:"Codigo de respuesta: {ITEM.LASTVALUE1}",comments:"GITIN-2239. El paso healthcheck devuelve un codigo distinto de 200 o no responde (timeout/conexion cortada).",tags:$tags}')" | jq -r '.triggerids[0]')
  jq --arg i "$T1" '.triggerids_code+=[$i]' "$RUN/created-ids.json" > "$RUN/c.tmp" && mv "$RUN/c.tmp" "$RUN/created-ids.json"
  T2=$(call trigger.create "$(jq -n --arg d "Healthcheck $SCN: slow response" --arg e "$(SLOW_EXPR "$SCN" "$STEP")" --arg r "$(SLOW_REC "$SCN" "$STEP")" --arg t "$T1" --argjson tags "$(TAGS "$SVC")" '{description:$d,expression:$e,recovery_mode:1,recovery_expression:$r,priority:2,manual_close:0,opdata:"Ultimo tiempo: {ITEM.LASTVALUE1} s (umbral {$HC.RESP.WARN} s)",comments:"GITIN-2239. Promedio del tiempo de respuesta del healthcheck por encima del umbral.",dependencies:[{triggerid:$t}],tags:$tags}')" | jq -r '.triggerids[0]')
  jq --arg i "$T2" '.triggerids_slow+=[$i]' "$RUN/created-ids.json" > "$RUN/c.tmp" && mv "$RUN/c.tmp" "$RUN/created-ids.json"
done
cat "$RUN/created-ids.json"
call trigger.get "$(jq -n --argjson ids "$(jq -c '.triggerids_code+.triggerids_slow' "$RUN/created-ids.json")" '{triggerids:$ids,output:["triggerid","description","priority","value","state","error","status"],selectTags:"extend"}')" > "$RUN/after-triggers.json"
jq -c '.[]|{triggerid,description,priority,value,state,error,status}' "$RUN/after-triggers.json"
echo "aplicado. Rollback: $0 rollback $RUN"

#!/usr/bin/env bash
# Event: 20261015_gitin2239-mobile-healthcheck-alerta-zabbix (GITIN-2239)
# C4 - Zabbix 6.0.32 (sf-monitoreo.smartfran.com:8080; token en $ZABBIX_API_KEY). Alerta sobre el ARCHIVO healthcheck.ashx (pedido del usuario), por servidor.
#      Hosts (C3): SFCG-MOBI-01 (10659), SFCG-MOBI-02 (10660), SFCG-WSV2-01 (10665), SFCG-WSV2-02 (10678); todos con agente activo (items tipo 7) detras del proxy 10609.
#      Crea en cada host: macros {$HC.FILE.PATH} (ruta del archivo; DEDUCIDA de eventos anteriores, no verificada en los servidores) y {$HC.FILE.WINDOW}=2m;
#      item de agente activo "healthcheck.ashx exists" con clave vfs.file.exists[{$HC.FILE.PATH}] cada 1m;
#      y, SOLO si despues de esperar el primer valor este es 1 en todos los hosts, un trigger HIGH "Healthcheck file missing on <host>":  max(item,{$HC.FILE.WINDOW})=0
#      con las mismas etiquetas de ruteo y de tarjeta que los otros triggers de healthcheck (GITIN-2239).
#      Si el primer valor no es 1 (ruta incorrecta, archivo ausente o clave no soportada por el agente) NO se crean los triggers: se informa y se corrige la macro de ruta (sin recrear nada).
#      Modos: dry (por defecto, SOLO LECTURA) | apply (CAMBIA ESTADO; tarda unos 4 minutos) | rollback <carpeta c4-run-...> (CAMBIA ESTADO: borra triggers, items y macros creados)
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
MODE="${1:-dry}"; SNAP="${2:-}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/loyalty/events/20261015_gitin2239-mobile-healthcheck-alerta-zabbix/data"
TS=$(date -u +%Y%m%dT%H%M%SZ); RUN="$OUT/c4-run-$TS"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
if [ "$MODE" = "rollback" ]; then
  [ -f "$SNAP/created-ids.json" ] || { echo "uso: $0 rollback <carpeta c4-run-...> (falta created-ids.json)"; exit 1; }
  for t in $(jq -r '.triggerids[]?' "$SNAP/created-ids.json"); do call trigger.delete "[\"$t\"]" >/dev/null; echo "trigger $t borrado"; done
  for i in $(jq -r '.itemids[]?' "$SNAP/created-ids.json"); do call item.delete "[\"$i\"]" >/dev/null; echo "item $i borrado"; done
  for m in $(jq -r '.macroids[]?' "$SNAP/created-ids.json"); do call usermacro.delete "[\"$m\"]" >/dev/null; echo "macro $m borrada"; done
  echo "rollback aplicado desde $SNAP"; exit 0
fi
mkdir -p "$RUN"; echo "modo=$MODE | $TS | carpeta $RUN"
HOSTS='[{"id":"10659","host":"SFCG-MOBI-01","svc":"MobileApp","path":"D:\\SmartLoyalty.MobileAppService\\healthcheck.ashx"},{"id":"10660","host":"SFCG-MOBI-02","svc":"MobileApp","path":"D:\\SmartLoyalty.MobileAppService\\healthcheck.ashx"},{"id":"10665","host":"SFCG-WSV2-01","svc":"WebServiceV2","path":"D:\\SmartLoyalty.WebServiceV2\\healthcheck.ashx"},{"id":"10678","host":"SFCG-WSV2-02","svc":"WebServiceV2","path":"D:\\SmartLoyalty.WebServiceV2\\healthcheck.ashx"}]'
call host.get "$(jq -n --argjson h "$HOSTS" '{hostids:[$h[].id],output:["hostid","host","status"]}')" > "$RUN/before-hosts.json"
jq -e --argjson h "$HOSTS" '(length==4) and (all(.status=="0")) and ((map({(.hostid):.host})|add)==($h|map({(.id):.host})|add))' "$RUN/before-hosts.json" >/dev/null || { echo "GUARDA: los hosts no son los esperados o no estan activos"; jq -c '[.[]|{hostid,host,status}]' "$RUN/before-hosts.json"; exit 1; }
KEY='vfs.file.exists[{$HC.FILE.PATH}]'
call item.get "$(jq -n --argjson h "$HOSTS" --arg k "$KEY" '{hostids:[$h[].id],filter:{key_:$k},output:["itemid","hostid"]}')" > "$RUN/before-items.json"
jq -e 'length==0' "$RUN/before-items.json" >/dev/null || { echo "GUARDA: ya existe un item con esa clave en alguno de los hosts"; exit 1; }
call usermacro.get "$(jq -n --argjson h "$HOSTS" '{hostids:[$h[].id],output:["macro","hostid"],filter:{macro:["{$HC.FILE.PATH}","{$HC.FILE.WINDOW}"]}}')" > "$RUN/before-macros.json"
jq -e 'length==0' "$RUN/before-macros.json" >/dev/null || { echo "GUARDA: ya existen macros HC.FILE.* en alguno de los hosts"; exit 1; }
TAGS() { jq -nc --arg s "$1" --arg h "$2" '[{tag:"scope",value:"OPE"},{tag:"scope",value:"GIT-SML-OPE"},{tag:"service_group",value:"LOYALTY"},{tag:"action",value:"GCHAT"},{tag:"check",value:"healthcheck-file"},{tag:"service",value:$s},{tag:"SVC_FRIENDLYNAME",value:("Healthcheck file "+$h)},{tag:"friendlyname",value:("Healthcheck file "+$h)}]'; }
EXPR() { echo "max(/$1/vfs.file.exists[{\$HC.FILE.PATH}],{\$HC.FILE.WINDOW})=0"; }
echo "== se crearian (por host): macro {\$HC.FILE.PATH}, macro {\$HC.FILE.WINDOW}=2m, item $KEY (agente activo, 1m), trigger HIGH"
jq -r '.[]|"- \(.host): \(.path)"' <<<"$HOSTS"
for i in $(seq 0 3); do echo "  trigger: Healthcheck file missing on $(jq -r ".[$i].host" <<<"$HOSTS")  ::  $(EXPR "$(jq -r ".[$i].host" <<<"$HOSTS")")"; done
if [ "$MODE" != "apply" ]; then echo "DRY: no se cambio nada. Para aplicar: $0 apply"; exit 0; fi

# --- apply (cambia estado)
echo '{"macroids":[],"itemids":[],"triggerids":[]}' > "$RUN/created-ids.json"
SAVE() { jq --arg k "$1" --arg v "$2" '.[$k]+=[$v]' "$RUN/created-ids.json" > "$RUN/c.tmp" && mv "$RUN/c.tmp" "$RUN/created-ids.json"; }
for i in $(seq 0 3); do
  H=$(jq -r ".[$i].id" <<<"$HOSTS"); P=$(jq -r ".[$i].path" <<<"$HOSTS")
  SAVE macroids "$(call usermacro.create "$(jq -n --arg h "$H" --arg v "$P" '{hostid:$h,macro:"{$HC.FILE.PATH}",value:$v,description:"GITIN-2239: ruta del archivo healthcheck.ashx (deducida de eventos anteriores)"}')" | jq -r '.hostmacroids[0]')"
  SAVE macroids "$(call usermacro.create "$(jq -n --arg h "$H" '{hostid:$h,macro:"{$HC.FILE.WINDOW}",value:"2m",description:"GITIN-2239: ventana en la que el archivo debe faltar para alertar"}')" | jq -r '.hostmacroids[0]')"
  SAVE itemids "$(call item.create "$(jq -n --arg h "$H" --arg k "$KEY" '{hostid:$h,name:"healthcheck.ashx exists",key_:$k,type:7,value_type:3,delay:"1m",history:"14d",trends:"365d",description:"GITIN-2239. 1 si el archivo healthcheck.ashx existe en el servidor; 0 si falta. Ruta en la macro {$HC.FILE.PATH}."}')" | jq -r '.itemids[0]')"
done
cat "$RUN/created-ids.json"
echo "esperando 200 s al primer valor de los items (el agente activo refresca su lista cada ~2 min)..."; sleep 200
call item.get "$(jq -n --argjson ids "$(jq -c '.itemids' "$RUN/created-ids.json")" '{itemids:$ids,output:["itemid","hostid","state","lastvalue","lastclock","error"],selectHosts:["host"]}')" > "$RUN/after-items.json"
jq -r '.[]|[.hosts[0].host,"state="+.state,"valor="+.lastvalue,"error="+.error]|@tsv' "$RUN/after-items.json"
if ! jq -e 'all(.state=="0" and .lastvalue=="1")' "$RUN/after-items.json" >/dev/null; then
  echo "AVISO: no todos los items devolvieron 1 (ruta incorrecta, archivo ausente, agente sin responder o clave denegada). NO se crearon los triggers."
  echo "Corregir la macro {\$HC.FILE.PATH} del host afectado y volver a leer; o rollback: $0 rollback $RUN"; exit 2
fi
for i in $(seq 0 3); do
  HN=$(jq -r ".[$i].host" <<<"$HOSTS"); SVC=$(jq -r ".[$i].svc" <<<"$HOSTS")
  SAVE triggerids "$(call trigger.create "$(jq -n --arg d "Healthcheck file missing on $HN" --arg e "$(EXPR "$HN")" --argjson tags "$(TAGS "$SVC" "$HN")" '{description:$d,expression:$e,priority:4,manual_close:0,opdata:"Archivo: {$HC.FILE.PATH}",comments:"GITIN-2239. El archivo healthcheck.ashx no existe en el servidor: el balanceador lo usa como sonda y deja de enviarle trafico (incidente GITIN-2238).",tags:$tags}')" | jq -r '.triggerids[0]')"
done
call trigger.get "$(jq -n --argjson ids "$(jq -c '.triggerids' "$RUN/created-ids.json")" '{triggerids:$ids,output:["triggerid","description","priority","value","state","error","status"]}')" > "$RUN/after-triggers.json"
jq -c '.[]' "$RUN/after-triggers.json"
echo "aplicado. Rollback: $0 rollback $RUN"

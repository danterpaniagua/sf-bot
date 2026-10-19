#!/usr/bin/env bash
# Event: 20261015_gitin2239-mobile-healthcheck-alerta-zabbix (GITIN-2239)
# C6 - Zabbix 6.0.32 (sf-monitoreo.smartfran.com:8080; token en $ZABBIX_API_KEY). Corrige la alerta del ARCHIVO healthcheck.ashx.
#      Resultado de C5 (az run-command): el agente (LocalSystem, sin AllowKey/DenyKey) responde 1 a vfs.file.exists con la ruta literal en los 4 servidores:
#      D:\SmartLoyalty.MobileAppService\healthcheck.ashx (MOBI-01/02), D:\SmartLoyalty.WebServiceV2\healthcheck.ashx (WSV2-01) y E:\SmartLoyalty.WebServiceV2\healthcheck.ashx (WSV2-02).
#      Los items de C4 usaban la clave vfs.file.exists[{$HC.FILE.PATH}] y leian 0: el problema esta en como llega la macro con barras invertidas a la clave, no en la ruta ni en el agente.
#      Este script: a) cambia la clave de los 4 items de C4 a la ruta literal (item.update; sin macro); b) borra las 4 macros {$HC.FILE.PATH} (ya no se usan; queda {$HC.FILE.WINDOW});
#      c) espera ~200 s y lee los items; d) SOLO si los 4 valen 1, crea los 4 triggers HIGH "Healthcheck file missing on <host>" con max(item,{$HC.FILE.WINDOW})=0 y las mismas etiquetas que los otros healthchecks.
#      Correccion (2026-10-15, tras la primera ejecucion): el lastvalue "0" de los items de C4 y de C6 era solo "sin dato todavia" (lastclock = 1970), no un valor leido; la conclusion de C6 sobre la macro era erronea. Ahora se espera (hasta ~6 min) a que TODOS tengan lastclock > 0 antes de mirar el valor.
#      Modos: dry (por defecto, SOLO LECTURA) | apply (CAMBIA ESTADO; hasta ~7 min) | triggers (CAMBIA ESTADO: salta los cambios de items y solo espera valores y crea los triggers; para reanudar tras un apply que se detuvo) | rollback <carpeta c6-run-...> (CAMBIA ESTADO: borra los triggers creados)
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
MODE="${1:-dry}"; SNAP="${2:-}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
DIR="/home/dpaniagua/Documentos/git/bots/loyalty/events/20261015_gitin2239-mobile-healthcheck-alerta-zabbix"; OUT="$DIR/data"
C4="$OUT/c4-run-20261015T170526Z/created-ids.json"
TS=$(date -u +%Y%m%dT%H%M%SZ); RUN="$OUT/c6-run-$TS"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
if [ "$MODE" = "rollback" ]; then
  [ -f "$SNAP/created-ids.json" ] || { echo "uso: $0 rollback <carpeta c6-run-...>"; exit 1; }
  for t in $(jq -r '.triggerids[]?' "$SNAP/created-ids.json"); do call trigger.delete "[\"$t\"]" >/dev/null; echo "trigger $t borrado"; done
  echo "rollback aplicado (los items quedan con la clave literal)"; exit 0
fi
[ -f "$C4" ] || { echo "GUARDA: falta $C4"; exit 1; }
mkdir -p "$RUN"; echo "modo=$MODE | $TS | carpeta $RUN"
HOSTS='[{"id":"10659","host":"SFCG-MOBI-01","svc":"MobileApp","path":"D:\\SmartLoyalty.MobileAppService\\healthcheck.ashx"},{"id":"10660","host":"SFCG-MOBI-02","svc":"MobileApp","path":"D:\\SmartLoyalty.MobileAppService\\healthcheck.ashx"},{"id":"10665","host":"SFCG-WSV2-01","svc":"WebServiceV2","path":"D:\\SmartLoyalty.WebServiceV2\\healthcheck.ashx"},{"id":"10678","host":"SFCG-WSV2-02","svc":"WebServiceV2","path":"E:\\SmartLoyalty.WebServiceV2\\healthcheck.ashx"}]'
call item.get "$(jq -n --argjson ids "$(jq -c '.itemids' "$C4")" '{itemids:$ids,output:["itemid","hostid","key_","type","delay"],selectHosts:["host"]}')" > "$RUN/before-items.json"
jq -e '(length==4) and all((.key_|startswith("vfs.file.exists[")) and .type=="7")' "$RUN/before-items.json" >/dev/null || { echo "GUARDA: los items de C4 no estan como se esperaba"; jq -c '[.[]|{itemid,key_,type}]' "$RUN/before-items.json"; exit 1; }
call usermacro.get "$(jq -n --argjson ids "$(jq -c '.macroids' "$C4")" '{hostmacroids:$ids,output:["hostmacroid","macro","hostid"]}')" > "$RUN/before-macros.json"
call trigger.get "$(jq -n --argjson h "$(jq -c '[.[].id]' <<<"$HOSTS")" '{hostids:$h,search:{description:"Healthcheck file missing on"},output:["triggerid"]}')" > "$RUN/before-triggers.json"
jq -e 'length==0' "$RUN/before-triggers.json" >/dev/null || { echo "GUARDA: ya existen triggers 'Healthcheck file missing on'"; exit 1; }
KEYOF() { echo "vfs.file.exists[$1]"; }
TAGS() { jq -nc --arg s "$1" --arg h "$2" '[{tag:"scope",value:"OPE"},{tag:"scope",value:"GIT-SML-OPE"},{tag:"service_group",value:"LOYALTY"},{tag:"action",value:"GCHAT"},{tag:"check",value:"healthcheck-file"},{tag:"service",value:$s},{tag:"SVC_FRIENDLYNAME",value:("Healthcheck file "+$h)},{tag:"friendlyname",value:("Healthcheck file "+$h)}]'; }
echo "== cambios previstos (host | clave nueva | trigger)"
for i in 0 1 2 3; do H=$(jq -r ".[$i].host" <<<"$HOSTS"); P=$(jq -r ".[$i].path" <<<"$HOSTS"); echo "- $H | $(KEYOF "$P") | max(/$H/$(KEYOF "$P"),{\$HC.FILE.WINDOW})=0"; done
echo "- se borran las macros {\$HC.FILE.PATH} (ids $(jq -c '[.[]|select(.macro=="{$HC.FILE.PATH}")|.hostmacroid]' "$RUN/before-macros.json"))"
if [ "$MODE" != "apply" ] && [ "$MODE" != "triggers" ]; then echo "DRY: no se cambio nada. Para aplicar: $0 apply"; exit 0; fi
# --- apply (cambia estado)
echo '{"triggerids":[]}' > "$RUN/created-ids.json"
if [ "$MODE" = "apply" ]; then
  for i in 0 1 2 3; do
    H=$(jq -r ".[$i].id" <<<"$HOSTS"); P=$(jq -r ".[$i].path" <<<"$HOSTS"); IT=$(jq -r --arg h "$H" '.[]|select(.hostid==$h)|.itemid' "$RUN/before-items.json")
    call item.update "$(jq -n --arg i "$IT" --arg k "$(KEYOF "$P")" '{itemid:$i,key_:$k,description:"GITIN-2239. 1 si el archivo healthcheck.ashx existe en el servidor; 0 si falta."}')" >/dev/null
    echo "item $IT -> $(KEYOF "$P")"
  done
  for m in $(jq -r '.[]|select(.macro=="{$HC.FILE.PATH}")|.hostmacroid' "$RUN/before-macros.json"); do call usermacro.delete "[\"$m\"]" >/dev/null; echo "macro $m borrada"; done
fi
IDS=$(jq -c '[.[].itemid]' "$RUN/before-items.json")
for n in $(seq 1 12); do
  call item.get "$(jq -n --argjson ids "$IDS" '{itemids:$ids,output:["itemid","key_","state","lastvalue","lastclock","error"],selectHosts:["host"]}')" > "$RUN/after-items.json"
  if jq -e 'all((.lastclock|tonumber) > 0)' "$RUN/after-items.json" >/dev/null; then break; fi
  echo "esperando valores ($n/12): $(jq -r '[.[]|select((.lastclock|tonumber)==0)|.hosts[0].host]|join(",")' "$RUN/after-items.json") sin dato todavia"; sleep 30
done
jq -r '.[]|[.hosts[0].host,"state="+.state,"valor="+.lastvalue,"hora_dato="+((.lastclock|tonumber)|if .>0 then strftime("%FT%TZ") else "ninguno" end),"error="+.error]|@tsv' "$RUN/after-items.json"
if ! jq -e 'all((.lastclock|tonumber)>0 and .state=="0" and .lastvalue=="1")' "$RUN/after-items.json" >/dev/null; then echo "AVISO: faltan datos o algun item no vale 1. NO se crearon los triggers. Reintentar mas tarde con: $0 triggers"; exit 2; fi
for i in 0 1 2 3; do
  H=$(jq -r ".[$i].host" <<<"$HOSTS"); S=$(jq -r ".[$i].svc" <<<"$HOSTS"); P=$(jq -r ".[$i].path" <<<"$HOSTS")
  T=$(call trigger.create "$(jq -n --arg d "Healthcheck file missing on $H" --arg e "max(/$H/$(KEYOF "$P"),{\$HC.FILE.WINDOW})=0" --arg p "$P" --argjson tags "$(TAGS "$S" "$H")" '{description:$d,expression:$e,priority:4,manual_close:0,opdata:("Archivo: "+$p),comments:"GITIN-2239. El archivo healthcheck.ashx no existe en el servidor: el balanceador lo usa como sonda y deja de enviarle trafico (incidente GITIN-2238).",tags:$tags}')" | jq -r '.triggerids[0]')
  jq --arg i "$T" '.triggerids+=[$i]' "$RUN/created-ids.json" > "$RUN/c.tmp" && mv "$RUN/c.tmp" "$RUN/created-ids.json"
done
call trigger.get "$(jq -n --argjson ids "$(jq -c '.triggerids' "$RUN/created-ids.json")" '{triggerids:$ids,output:["triggerid","description","priority","value","state","error","status"]}')" > "$RUN/after-triggers.json"
jq -c '.[]' "$RUN/after-triggers.json"
echo "aplicado. Rollback (solo triggers): $0 rollback $RUN"

#!/usr/bin/env bash
# Event: 20261015_gitin2239-mobile-healthcheck-alerta-zabbix (GITIN-2239)
# C12 - Zabbix 6.0.32 (sf-monitoreo.smartfran.com:8080; token en $ZABBIX_API_KEY). Alerta sobre el ARCHIVO de healthcheck de los servidores WebService (pedido del usuario, 2026-10-16), mismo patron que C4/C6.
#       Hosts (C10, data/c10-read-log-20261016T120728Z.txt): SFCG-WEBS-01 (10661), SFCG-WEBS-02 (10662), SFCG-WEBS-03 (10663); agente activo (plantillas "... by Zabbix agent active"), detras del proxy 10609, sin items vfs.file.exists.
#       Ruta (dada por el usuario, no verificada): C:\SmartFran\SmartLoyalty.WebService\healthcheck.ashx en los tres. healthcheckv2.ashx de WEBS-01 era una prueba y el balanceador no la usa (user-stated, 2026-10-16): NO se incluye. Son 3 archivos = 3 items y 3 triggers.
#       Lecciones de C4/C6: la clave lleva la RUTA LITERAL (no una macro: el valor con barras invertidas no llegaba bien a la clave); un lastvalue "0" con lastclock 1970 es "sin dato todavia", no una lectura;
#       los triggers se crean SOLO si los 3 items ya tienen dato y valen 1 (si no, se informa y no se crea ninguno).
#       Crea: por host la macro {$HC.FILE.WINDOW}=2m; por archivo un item de agente activo "<archivo> exists" (1m) y, si todos valen 1, un trigger HIGH max(item,{$HC.FILE.WINDOW})=0
#       con las etiquetas de ruteo de los otros healthchecks de GITIN-2239 + env=PROD (asi tambien los toma la accion 12 hacia Operaciones por Chat y Telegram).
#       Modos: dry (por defecto, SOLO LECTURA) | apply (CAMBIA ESTADO; hasta ~8 min) | triggers <carpeta c12-run-...> (CAMBIA ESTADO: reanuda tras un apply que paro por falta de dato/valor y crea los triggers) | rollback <carpeta c12-run-...> (CAMBIA ESTADO: borra triggers, items y macros creados)
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
MODE="${1:-dry}"; SNAP="${2:-}"
API="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
OUT="/home/dpaniagua/Documentos/git/bots/loyalty/events/20261015_gitin2239-mobile-healthcheck-alerta-zabbix/data"
TS=$(date -u +%Y%m%dT%H%M%SZ); RUN="$OUT/c12-run-$TS"
call() { jq -n --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,auth:$a,id:1}' \
  | curl -sS -H 'Content-Type: application/json-rpc' -d @- "$API" | jq 'if .error then error("API: " + (.error|tostring)) else .result end'; }
if [ "$MODE" = "rollback" ]; then
  [ -f "$SNAP/created-ids.json" ] || { echo "uso: $0 rollback <carpeta c12-run-...> (falta created-ids.json)"; exit 1; }
  for t in $(jq -r '.triggerids[]?' "$SNAP/created-ids.json"); do call trigger.delete "[\"$t\"]" >/dev/null; echo "trigger $t borrado"; done
  for i in $(jq -r '.itemids[]?' "$SNAP/created-ids.json"); do call item.delete "[\"$i\"]" >/dev/null; echo "item $i borrado"; done
  for m in $(jq -r '.macroids[]?' "$SNAP/created-ids.json"); do call usermacro.delete "[\"$m\"]" >/dev/null; echo "macro $m borrada"; done
  echo "rollback aplicado desde $SNAP"; exit 0
fi
D='C:\SmartFran\SmartLoyalty.WebService\'
FILES='[{"id":"10661","host":"SFCG-WEBS-01","file":"healthcheck.ashx","label":"Healthcheck file"},{"id":"10662","host":"SFCG-WEBS-02","file":"healthcheck.ashx","label":"Healthcheck file"},{"id":"10663","host":"SFCG-WEBS-03","file":"healthcheck.ashx","label":"Healthcheck file"}]'
FILES=$(jq -c --arg d "$D" 'map(.path=($d+.file))' <<<"$FILES")
KEYOF() { echo "vfs.file.exists[$1]"; }
TAGS() { jq -nc --arg h "$1" --arg l "$2" '[{tag:"scope",value:"OPE"},{tag:"scope",value:"GIT-SML-OPE"},{tag:"service_group",value:"LOYALTY"},{tag:"action",value:"GCHAT"},{tag:"check",value:"healthcheck-file"},{tag:"service",value:"WebService"},{tag:"SVC_FRIENDLYNAME",value:($l+" "+$h)},{tag:"friendlyname",value:($l+" "+$h)},{tag:"env",value:"PROD"}]'; }
MK_TRIGGERS() { # $1 = carpeta con created-ids.json
  local R="$1"
  call item.get "$(jq -n --argjson ids "$(jq -c '.itemids' "$R/created-ids.json")" '{itemids:$ids,output:["itemid","hostid","key_","state","lastvalue","lastclock","error"],selectHosts:["host"]}')" > "$R/after-items.json"
  for n in $(seq 1 14); do
    call item.get "$(jq -n --argjson ids "$(jq -c '.itemids' "$R/created-ids.json")" '{itemids:$ids,output:["itemid","hostid","key_","state","lastvalue","lastclock","error"],selectHosts:["host"]}')" > "$R/after-items.json"
    if jq -e 'all((.lastclock|tonumber) > 0)' "$R/after-items.json" >/dev/null; then break; fi
    echo "esperando valores ($n/14): $(jq -r '[.[]|select((.lastclock|tonumber)==0)|.hosts[0].host]|join(",")' "$R/after-items.json") sin dato todavia"; sleep 30
  done
  jq -r '.[]|[.hosts[0].host,.key_,"state="+.state,"valor="+.lastvalue,"hora_dato="+((.lastclock|tonumber)|if .>0 then strftime("%FT%TZ") else "ninguno" end),"error="+.error]|@tsv' "$R/after-items.json"
  if ! jq -e 'length==3 and all((.lastclock|tonumber)>0 and .state=="0" and .lastvalue=="1")' "$R/after-items.json" >/dev/null; then
    echo "AVISO: faltan datos o algun item no vale 1 (ruta incorrecta, archivo ausente, agente sin responder o clave denegada). NO se crearon los triggers. Reintentar mas tarde con: $0 triggers $R  |  deshacer: $0 rollback $R"; exit 2
  fi
  for i in 0 1 2; do
    H=$(jq -r ".[$i].host" <<<"$FILES"); P=$(jq -r ".[$i].path" <<<"$FILES"); L=$(jq -r ".[$i].label" <<<"$FILES"); F=$(jq -r ".[$i].file" <<<"$FILES")
    T=$(call trigger.create "$(jq -n --arg d "$L missing on $H" --arg e "max(/$H/$(KEYOF "$P"),{\$HC.FILE.WINDOW})=0" --arg p "$P" --argjson tags "$(TAGS "$H" "$L")" '{description:$d,expression:$e,priority:4,manual_close:0,opdata:("Archivo: "+$p),comments:"GITIN-2239. El archivo de healthcheck no existe en el servidor WebService (ruta indicada por el usuario).",tags:$tags}')" | jq -r '.triggerids[0]')
    jq --arg i "$T" '.triggerids+=[$i]' "$R/created-ids.json" > "$R/c.tmp" && mv "$R/c.tmp" "$R/created-ids.json"
    echo "trigger $T: $L missing on $H ($F)"
  done
  call trigger.get "$(jq -n --argjson ids "$(jq -c '.triggerids' "$R/created-ids.json")" '{triggerids:$ids,output:["triggerid","description","priority","value","state","error","status"],selectTags:"extend"}')" > "$R/after-triggers.json"
  jq -c '.[]|{triggerid,description,priority,value,state,error,env:([.tags[]|select(.tag=="env")|.value])}' "$R/after-triggers.json"
  echo "aplicado. Rollback: $0 rollback $R"
}
if [ "$MODE" = "triggers" ]; then
  [ -f "$SNAP/created-ids.json" ] || { echo "uso: $0 triggers <carpeta c12-run-...>"; exit 1; }
  jq -e '(.itemids|length)==3 and ((.triggerids // [])|length)==0' "$SNAP/created-ids.json" >/dev/null || { echo "GUARDA: la carpeta no tiene 3 items o ya tiene triggers"; exit 1; }
  MK_TRIGGERS "$SNAP"; exit 0
fi
mkdir -p "$RUN"; echo "modo=$MODE | $TS | carpeta $RUN"
call host.get "$(jq -n --argjson f "$FILES" '{hostids:([$f[].id]|unique),output:["hostid","host","status","flags"]}')" > "$RUN/before-hosts.json"
jq -e --argjson f "$FILES" '(length==3) and all(.status=="0" and .flags=="0") and ((map({(.hostid):.host})|add)==($f|map({(.id):.host})|add))' "$RUN/before-hosts.json" >/dev/null || { echo "GUARDA: los hosts no son los esperados (SFCG-WEBS-01/02/03), manuales y activos"; jq -c '[.[]|{hostid,host,status,flags}]' "$RUN/before-hosts.json"; exit 1; }
call item.get "$(jq -n --argjson f "$FILES" '{hostids:([$f[].id]|unique),search:{key_:"vfs.file.exists"},output:["itemid","key_"]}')" > "$RUN/before-items.json"
jq -e 'length==0' "$RUN/before-items.json" >/dev/null || { echo "GUARDA: ya existen items vfs.file.exists en alguno de los hosts"; exit 1; }
call usermacro.get "$(jq -n --argjson f "$FILES" '{hostids:([$f[].id]|unique),output:["macro","hostid"],filter:{macro:["{$HC.FILE.WINDOW}"]}}')" > "$RUN/before-macros.json"
jq -e 'length==0' "$RUN/before-macros.json" >/dev/null || { echo "GUARDA: ya existe {\$HC.FILE.WINDOW} en alguno de los hosts"; exit 1; }
call trigger.get "$(jq -n --argjson f "$FILES" '{hostids:([$f[].id]|unique),search:{description:"ile missing on"},output:["triggerid"]}')" > "$RUN/before-triggers.json"
jq -e 'length==0' "$RUN/before-triggers.json" >/dev/null || { echo "GUARDA: ya existen triggers 'file missing on' en alguno de los hosts"; exit 1; }
echo "== se crearian: macro {\$HC.FILE.WINDOW}=2m en 3 hosts; 3 items de agente activo (1m); 3 triggers HIGH si los 3 items valen 1"
for i in 0 1 2; do H=$(jq -r ".[$i].host" <<<"$FILES"); P=$(jq -r ".[$i].path" <<<"$FILES"); L=$(jq -r ".[$i].label" <<<"$FILES"); echo "- $H | $(KEYOF "$P") | trigger: $L missing on $H :: max(/$H/$(KEYOF "$P"),{\$HC.FILE.WINDOW})=0"; done
echo "- etiquetas del primer trigger: $(TAGS "$(jq -r '.[0].host' <<<"$FILES")" "$(jq -r '.[0].label' <<<"$FILES")" | jq -c '[.[]|"\(.tag)=\(.value)"]')"
if [ "$MODE" != "apply" ]; then echo "DRY: no se cambio nada. Para aplicar: $0 apply"; exit 0; fi

# --- apply (cambia estado)
echo '{"macroids":[],"itemids":[],"triggerids":[]}' > "$RUN/created-ids.json"
SAVE() { jq --arg k "$1" --arg v "$2" '.[$k]+=[$v]' "$RUN/created-ids.json" > "$RUN/c.tmp" && mv "$RUN/c.tmp" "$RUN/created-ids.json"; }
for H in $(jq -r '[.[].id]|unique[]' <<<"$FILES"); do
  SAVE macroids "$(call usermacro.create "$(jq -n --arg h "$H" '{hostid:$h,macro:"{$HC.FILE.WINDOW}",value:"2m",description:"GITIN-2239: ventana en la que el archivo debe faltar para alertar"}')" | jq -r '.hostmacroids[0]')"
done
for i in 0 1 2; do
  H=$(jq -r ".[$i].id" <<<"$FILES"); P=$(jq -r ".[$i].path" <<<"$FILES"); F=$(jq -r ".[$i].file" <<<"$FILES")
  SAVE itemids "$(call item.create "$(jq -n --arg h "$H" --arg k "$(KEYOF "$P")" --arg n "$F exists" --arg f "$F" '{hostid:$h,name:$n,key_:$k,type:7,value_type:3,delay:"1m",history:"14d",trends:"365d",description:("GITIN-2239. 1 si el archivo "+$f+" existe en el servidor; 0 si falta.")}')" | jq -r '.itemids[0]')"
done
cat "$RUN/created-ids.json"
echo "esperando 120 s al primer valor (el agente activo refresca su lista cada ~2 min)..."; sleep 120
MK_TRIGGERS "$RUN"

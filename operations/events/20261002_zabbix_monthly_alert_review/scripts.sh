#!/bin/bash
# GITIN-2156 - Revision de alertas de Zabbix (septiembre 2026)
# Todos los comandos son de solo lectura contra la API de Zabbix.
# Ventana: 2026-09-01 00:00 -03:00 (1788231600) a 2026-10-01 00:00 -03:00 (1790823600)

D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php

# 1. eventos de problemas/recuperaciones -> data/events-2026-09.json
# 2. notificaciones (alert.get) -> data/alerts-2026-09.json
# 3. macros globales, triggers SSL y MOBI, historia _Total GET/POST MOBI -> data/*.json
#    (ver mensajes de la sesion; ejecutados el 2026-10-02)

# 4. Items de CPU/RAM de MOBI-01/02 y su historia de septiembre
curl -s -X POST $API -H 'Content-Type: application/json-rpc' \
  -d '{"jsonrpc":"2.0","method":"item.get","id":5,"auth":"'"$ZABBIX_API_KEY"'","params":{"filter":{"host":["SFCG-MOBI-01","SFCG-MOBI-02"]},"search":{"key_":["system.cpu.util","vm.memory.util","vm.memory.size[pavailable]"]},"searchByAny":true,"output":["itemid","name","key_","history","trends","value_type"],"selectHosts":["host"]}}' \
  > $D/mobi-cpuram-items.json

for id in $(jq -r '.result[] | select(.value_type=="0") | .itemid' $D/mobi-cpuram-items.json); do
  curl -s -X POST $API -H 'Content-Type: application/json-rpc' \
    -d '{"jsonrpc":"2.0","method":"history.get","id":6,"auth":"'"$ZABBIX_API_KEY"'","params":{"itemids":["'$id'"],"history":0,"time_from":1788231600,"time_till":1790823600,"output":["clock","value"],"sortfield":"clock","sortorder":"ASC","limit":50000}}' \
    > $D/mobi-cpuram-history-$id.json
done

# ---------------------------------------------------------------------------
# 5. APLICAR tiers MOBI IIS Spike via API (45/75/100, OK 40, ventanas 10m/5m/3m, recovery 20m)
#    CAMBIA ESTADO en Zabbix de produccion. Snapshot previo en data/*-BEFORE.json
# ---------------------------------------------------------------------------
(
set -euo pipefail
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
call(){ jq -n --arg m "$1" --arg k "$ZABBIX_API_KEY" --argjson p "$2" '{jsonrpc:"2.0",method:$m,id:1,auth:$k,params:$p}' \
  | curl -s -X POST $API -H 'Content-Type: application/json-rpc' -d @- > "$3"
  if jq -e '.error' "$3" >/dev/null; then echo "ERROR en $1 (ver $3)"; jq .error "$3"; exit 1; fi; }

# 5.1 snapshot previo
call trigger.get '{"triggerids":["26742","26743","26744","26745","26746","26747"],"output":["triggerid","description","expression","recovery_expression","priority"],"selectHosts":["host"],"selectDependencies":["triggerid"]}' $D/mobi-spike-triggers-BEFORE.json
call usermacro.get '{"globalmacro":true,"output":["globalmacroid","macro","value"]}' $D/global-macros-BEFORE.json

# 5.2 guardas: cada triggerid sigue siendo el trigger esperado
for row in "26742 SFCG-MOBI-01" "26743 SFCG-MOBI-01" "26744 SFCG-MOBI-01" "26745 SFCG-MOBI-02" "26746 SFCG-MOBI-02" "26747 SFCG-MOBI-02"; do
  set -- $row
  jq -e --arg id "$1" --arg h "$2" '.result[]|select(.triggerid==$id and .hosts[0].host==$h and (.description|startswith("IIS Spike")))' $D/mobi-spike-triggers-BEFORE.json >/dev/null \
    || { echo "GUARDA FALLIDA: trigger $1 no es IIS Spike de $2"; exit 1; }
done
# la macro a editar existe y las nuevas no existen todavia
TIMEOK_ID=$(jq -r '.result[]|select(.macro=="{$MOBILE_PCOUNT_SPIKE_TIME_OK}")|.globalmacroid' $D/global-macros-BEFORE.json)
[ -n "$TIMEOK_ID" ] || { echo "no existe {\$MOBILE_PCOUNT_SPIKE_TIME_OK}"; exit 1; }
! jq -e '.result[]|select(.macro|test("SPIKE_(WARN|AVG|HIGH|OK):MOBI\\}|SPIKE_TIME_(WARN|AVG|HIGH)\\}"))' $D/global-macros-BEFORE.json >/dev/null \
  || { echo "ya existen macros nuevas, abortando"; exit 1; }

# 5.3 macros globales
call usermacro.createglobal '[{"macro":"{$MOBILE_PCOUNT_SPIKE_WARN:MOBI}","value":"45"},{"macro":"{$MOBILE_PCOUNT_SPIKE_AVG:MOBI}","value":"75"},{"macro":"{$MOBILE_PCOUNT_SPIKE_HIGH:MOBI}","value":"100"},{"macro":"{$MOBILE_PCOUNT_SPIKE_OK:MOBI}","value":"40"},{"macro":"{$MOBILE_PCOUNT_SPIKE_TIME_WARN}","value":"10m"},{"macro":"{$MOBILE_PCOUNT_SPIKE_TIME_AVG}","value":"5m"},{"macro":"{$MOBILE_PCOUNT_SPIKE_TIME_HIGH}","value":"3m"}]' $D/apply-1-create-macros.json
call usermacro.updateglobal "{\"globalmacroid\":\"$TIMEOK_ID\",\"value\":\"20m\"}" $D/apply-2-update-time-ok.json

# 5.4 triggers
ITEM='perf_counter_en["\Web Service(_Total)\Total Method Requests/Sec", 60]'
for row in "26742 SFCG-MOBI-01 WARN" "26743 SFCG-MOBI-01 AVG" "26744 SFCG-MOBI-01 HIGH" "26745 SFCG-MOBI-02 WARN" "26746 SFCG-MOBI-02 AVG" "26747 SFCG-MOBI-02 HIGH"; do
  set -- $row; id=$1; H=$2; T=$3
  name="IIS Spike - More than {\$MOBILE_PCOUNT_SPIKE_${T}:MOBI} Method Total requests per second in {\$MOBILE_PCOUNT_SPIKE_TIME_$T}"
  expr="avg(/$H/$ITEM,{\$MOBILE_PCOUNT_SPIKE_TIME_$T})>={\$MOBILE_PCOUNT_SPIKE_${T}:MOBI}"
  rec="avg(/$H/$ITEM,{\$MOBILE_PCOUNT_SPIKE_TIME_OK})<={\$MOBILE_PCOUNT_SPIKE_OK:MOBI}"
  p=$(jq -n --arg id "$id" --arg d "$name" --arg e "$expr" --arg r "$rec" '{triggerid:$id,description:$d,expression:$e,recovery_expression:$r}')
  call trigger.update "$p" $D/apply-3-trigger-$id.json
  echo "trigger $id ($H $T) actualizado"
done

# 5.5 estado posterior
call trigger.get '{"triggerids":["26742","26743","26744","26745","26746","26747"],"output":["triggerid","description","expression","recovery_expression","priority","state","error"],"selectHosts":["host"],"selectDependencies":["triggerid"]}' $D/mobi-spike-triggers-AFTER.json
echo "OK - revisar $D/mobi-spike-triggers-AFTER.json (state/error vacios, dependencias intactas)"
)

# ---------------------------------------------------------------------------
# 6. ROLLBACK de 5: restaura triggers desde *-BEFORE.json, borra macros nuevas, TIME_OK vuelve a 5m
#    CAMBIA ESTADO en Zabbix de produccion.
# ---------------------------------------------------------------------------
(
set -euo pipefail
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
call(){ jq -n --arg m "$1" --arg k "$ZABBIX_API_KEY" --argjson p "$2" '{jsonrpc:"2.0",method:$m,id:1,auth:$k,params:$p}' \
  | curl -s -X POST $API -H 'Content-Type: application/json-rpc' -d @- > "$3"
  if jq -e '.error' "$3" >/dev/null; then echo "ERROR en $1 (ver $3)"; jq .error "$3"; exit 1; fi; }
# NOTA: el snapshot BEFORE guarda expresiones con ids de funcion ({38197}), que trigger.update no acepta.
# Se reconstruyen las expresiones originales explicitamente (macros :MOBI01/:MOBI02 y {$MOBILE_PCOUNT_SPIKE_TIME}).
ITEM='perf_counter_en["\Web Service(_Total)\Total Method Requests/Sec", 60]'
for row in "26742 SFCG-MOBI-01 WARN MOBI01" "26743 SFCG-MOBI-01 AVG MOBI01" "26744 SFCG-MOBI-01 HIGH MOBI01" "26745 SFCG-MOBI-02 WARN MOBI02" "26746 SFCG-MOBI-02 AVG MOBI02" "26747 SFCG-MOBI-02 HIGH MOBI02"; do
  set -- $row; id=$1; H=$2; T=$3; C=$4
  name="IIS Spike - More than {\$MOBILE_PCOUNT_SPIKE_${T}:$C} Method Total requests per second in {\$MOBILE_PCOUNT_SPIKE_TIME}"
  expr="avg(/$H/$ITEM,{\$MOBILE_PCOUNT_SPIKE_TIME})>={\$MOBILE_PCOUNT_SPIKE_${T}:$C}"
  rec="avg(/$H/$ITEM,{\$MOBILE_PCOUNT_SPIKE_TIME_OK})<={\$MOBILE_PCOUNT_SPIKE_OK:$C}"
  p=$(jq -n --arg id "$id" --arg d "$name" --arg e "$expr" --arg r "$rec" '{triggerid:$id,description:$d,expression:$e,recovery_expression:$r}')
  call trigger.update "$p" $D/rollback-trigger-$id.json
done
call usermacro.get '{"globalmacro":true,"output":["globalmacroid","macro","value"]}' $D/global-macros-ROLLBACK-pre.json
NEW=$(jq -c '[.result[]|select(.macro|test("SPIKE_(WARN|AVG|HIGH|OK):MOBI\\}|SPIKE_TIME_(WARN|AVG|HIGH)\\}"))|.globalmacroid]' $D/global-macros-ROLLBACK-pre.json)
call usermacro.deleteglobal "$NEW" $D/rollback-delete-macros.json
TIMEOK_ID=$(jq -r '.result[]|select(.macro=="{$MOBILE_PCOUNT_SPIKE_TIME_OK}")|.globalmacroid' $D/global-macros-ROLLBACK-pre.json)
call usermacro.updateglobal "{\"globalmacroid\":\"$TIMEOK_ID\",\"value\":\"5m\"}" $D/rollback-time-ok.json
echo "rollback aplicado"
)

# ---------------------------------------------------------------------------
# 7. DESHABILITAR trio legacy "IIS More than N ... for 10m" en MOBI-01/02 (triggers 26133-26138)
#    CAMBIA ESTADO en Zabbix de produccion. status 1 = deshabilitado (reversible).
# ---------------------------------------------------------------------------
(
set -euo pipefail
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
call(){ jq -n --arg m "$1" --arg k "$ZABBIX_API_KEY" --argjson p "$2" '{jsonrpc:"2.0",method:$m,id:1,auth:$k,params:$p}' \
  | curl -s -X POST $API -H 'Content-Type: application/json-rpc' -d @- > "$3"
  if jq -e '.error' "$3" >/dev/null; then echo "ERROR en $1 (ver $3)"; jq .error "$3"; exit 1; fi; }
call trigger.get '{"triggerids":["26133","26134","26135","26136","26137","26138"],"output":["triggerid","description","status","priority"],"selectHosts":["host"]}' $D/legacy-trio-BEFORE.json
for row in "26133 SFCG-MOBI-01" "26134 SFCG-MOBI-01" "26135 SFCG-MOBI-01" "26136 SFCG-MOBI-02" "26137 SFCG-MOBI-02" "26138 SFCG-MOBI-02"; do
  set -- $row
  jq -e --arg id "$1" --arg h "$2" '.result[]|select(.triggerid==$id and .hosts[0].host==$h and (.description|startswith("IIS More than")))' $D/legacy-trio-BEFORE.json >/dev/null \
    || { echo "GUARDA FALLIDA: trigger $1 no es IIS More than de $2"; exit 1; }
done
for id in 26133 26134 26135 26136 26137 26138; do
  call trigger.update "{\"triggerid\":\"$id\",\"status\":\"1\"}" $D/disable-legacy-$id.json
  echo "trigger $id deshabilitado"
done
call trigger.get '{"triggerids":["26133","26134","26135","26136","26137","26138"],"output":["triggerid","description","status"],"selectHosts":["host"]}' $D/legacy-trio-AFTER.json
echo "OK - revisar $D/legacy-trio-AFTER.json (status 1 en los seis)"
)

# ROLLBACK de 7: vuelve a habilitar los seis (status 0)
(
set -euo pipefail
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
for id in 26133 26134 26135 26136 26137 26138; do
  jq -n --arg k "$ZABBIX_API_KEY" --arg id "$id" '{jsonrpc:"2.0",method:"trigger.update",id:1,auth:$k,params:{triggerid:$id,status:"0"}}' \
    | curl -s -X POST $API -H 'Content-Type: application/json-rpc' -d @- > $D/rollback-legacy-$id.json
  jq -e '.error' $D/rollback-legacy-$id.json >/dev/null && { echo "ERROR trigger $id"; exit 1; }
  echo "trigger $id habilitado"
done
)


# ---------------------------------------------------------------------------
# 8. Tags de ruteo para IIS Spike MOBI (triggers 26742-26747), sin email:
#    action: TELE,GCHAT,MAIL -> TELE,GCHAT ; + SVC_FRIENDLYNAME ; + (ROUTE=1) scope:GIT-SML y service_group:CLOUD
#    (scope/service_group son necesarios para matchear la accion 7 "Google Chat ... Operaciones";
#     tambien matchea la accion 8). ROUTE=0 aplica solo action + SVC_FRIENDLYNAME.
#    CAMBIA ESTADO en Zabbix de produccion. Conserva el resto de los tags.
# ---------------------------------------------------------------------------
(
set -euo pipefail
ROUTE=1
SVC='Mobile Total Requests (req/s)'
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
call(){ jq -n --arg m "$1" --arg k "$ZABBIX_API_KEY" --argjson p "$2" '{jsonrpc:"2.0",method:$m,id:1,auth:$k,params:$p}' \
  | curl -s -X POST $API -H 'Content-Type: application/json-rpc' -d @- > "$3"
  if jq -e '.error' "$3" >/dev/null; then echo "ERROR en $1 (ver $3)"; jq .error "$3"; exit 1; fi; }
call trigger.get '{"triggerids":["26742","26743","26744","26745","26746","26747"],"output":["triggerid","description"],"selectHosts":["host"],"selectTags":["tag","value"]}' $D/mobi-spike-tags-BEFORE.json
for row in "26742 SFCG-MOBI-01" "26743 SFCG-MOBI-01" "26744 SFCG-MOBI-01" "26745 SFCG-MOBI-02" "26746 SFCG-MOBI-02" "26747 SFCG-MOBI-02"; do
  set -- $row
  jq -e --arg id "$1" --arg h "$2" '.result[]|select(.triggerid==$id and .hosts[0].host==$h and (.description|startswith("IIS Spike")))' $D/mobi-spike-tags-BEFORE.json >/dev/null \
    || { echo "GUARDA FALLIDA: trigger $1 no es IIS Spike de $2"; exit 1; }
done
for id in 26742 26743 26744 26745 26746 26747; do
  p=$(jq --arg id "$id" --arg svc "$SVC" --argjson route "$ROUTE" '.result[]|select(.triggerid==$id)|
    {triggerid:$id,tags:(
      ((.tags|map(select(((.tag=="action" and .value=="TELE,GCHAT,MAIL")or(.tag=="SVC_FRIENDLYNAME"))|not)))
       + [{"tag":"action","value":"TELE,GCHAT"},{"tag":"SVC_FRIENDLYNAME","value":$svc}]
       + (if $route==1 then [{"tag":"scope","value":"GIT-SML"},{"tag":"service_group","value":"CLOUD"}] else [] end))
      | unique_by([.tag,.value]))}' $D/mobi-spike-tags-BEFORE.json)
  call trigger.update "$p" $D/tags-apply-$id.json
  echo "trigger $id: tags actualizados"
done
call trigger.get '{"triggerids":["26742","26743","26744","26745","26746","26747"],"output":["triggerid"],"selectTags":["tag","value"]}' $D/mobi-spike-tags-AFTER.json
echo "OK - revisar $D/mobi-spike-tags-AFTER.json"
)

# ROLLBACK de 8: restaura los tags originales desde mobi-spike-tags-BEFORE.json
(
set -euo pipefail
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
for id in 26742 26743 26744 26745 26746 26747; do
  p=$(jq --arg id "$id" '.result[]|select(.triggerid==$id)|{triggerid:$id,tags:.tags}' $D/mobi-spike-tags-BEFORE.json)
  jq -n --arg k "$ZABBIX_API_KEY" --argjson p "$p" '{jsonrpc:"2.0",method:"trigger.update",id:1,auth:$k,params:$p}' \
    | curl -s -X POST $API -H 'Content-Type: application/json-rpc' -d @- > $D/tags-rollback-$id.json
  jq -e '.error' $D/tags-rollback-$id.json >/dev/null && { echo "ERROR trigger $id"; exit 1; }
  echo "trigger $id: tags restaurados"
done
)

# ---------------------------------------------------------------------------
# 9. (Opcion 2, solo OPE) Cambiar scope:GIT-SML -> scope:GIT-SML-OPE en los Spike MOBI (26742-26747)
#    La accion 7 (Operaciones) matchea "scope contiene GIT-SML"; la accion 8 (Project Leaders) exige scope = GIT-SML exacto,
#    por lo que con GIT-SML-OPE solo recibe OPE. CAMBIA ESTADO en Zabbix de produccion.
#    Rollback: el rollback del paso 8 restaura los tags originales desde mobi-spike-tags-BEFORE.json (snapshot previo al paso 8).
# ---------------------------------------------------------------------------
(
set -euo pipefail
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
call(){ jq -n --arg m "$1" --arg k "$ZABBIX_API_KEY" --argjson p "$2" '{jsonrpc:"2.0",method:$m,id:1,auth:$k,params:$p}' \
  | curl -s -X POST $API -H 'Content-Type: application/json-rpc' -d @- > "$3"
  if jq -e '.error' "$3" >/dev/null; then echo "ERROR en $1 (ver $3)"; jq .error "$3"; exit 1; fi; }
call trigger.get '{"triggerids":["26742","26743","26744","26745","26746","26747"],"output":["triggerid","description"],"selectHosts":["host"],"selectTags":["tag","value"]}' $D/mobi-spike-tags9-BEFORE.json
for row in "26742 SFCG-MOBI-01" "26743 SFCG-MOBI-01" "26744 SFCG-MOBI-01" "26745 SFCG-MOBI-02" "26746 SFCG-MOBI-02" "26747 SFCG-MOBI-02"; do
  set -- $row
  jq -e --arg id "$1" --arg h "$2" '.result[]|select(.triggerid==$id and .hosts[0].host==$h and (.description|startswith("IIS Spike")) and (.tags|any(.tag=="scope" and .value=="GIT-SML")))' $D/mobi-spike-tags9-BEFORE.json >/dev/null \
    || { echo "GUARDA FALLIDA: trigger $1 no es IIS Spike de $2 o no tiene scope:GIT-SML"; exit 1; }
done
for id in 26742 26743 26744 26745 26746 26747; do
  p=$(jq --arg id "$id" '.result[]|select(.triggerid==$id)|{triggerid:$id,tags:((.tags|map(select((.tag=="scope" and .value=="GIT-SML")|not)))+[{"tag":"scope","value":"GIT-SML-OPE"}]|unique_by([.tag,.value]))}' $D/mobi-spike-tags9-BEFORE.json)
  call trigger.update "$p" $D/tags9-apply-$id.json
  echo "trigger $id: scope:GIT-SML -> scope:GIT-SML-OPE"
done
call trigger.get '{"triggerids":["26742","26743","26744","26745","26746","26747"],"output":["triggerid"],"selectTags":["tag","value"]}' $D/mobi-spike-tags9-AFTER.json
echo "OK - revisar $D/mobi-spike-tags9-AFTER.json"
)

# ---------------------------------------------------------------------------
# 10b. (NO APLICADO - variante alternativa con OR LOYALTY/CLOUD) Accion 7 "Google Chat Loyalty to Operaciones"
#     APLICADO el 2026-10-02 en su lugar (10a): action.update filter evaltype 1 con scope = GIT-SML-OPE AND action ~ GCHAT AND service_group = LOYALTY
#     (resultado en data/action7-AFTER.json; su rollback es el de abajo, que restaura las 4 condiciones originales).
#     Bloque alternativo (no ejecutado):
#     antes: scope ~ GIT-SML AND action ~ GCHAT AND service_group = LOYALTY AND service_group = CLOUD   (evaltype And: exige LOYALTY y CLOUD a la vez)
#     ahora: scope ~ GIT-SML AND action ~ GCHAT AND (service_group = LOYALTY OR service_group = CLOUD)   (evaltype 3, formula "A and B and (C or D)")
#     CAMBIA ESTADO en Zabbix de produccion (filtro de una accion compartida; no toca status ni destinatarios).
# ---------------------------------------------------------------------------
(
set -euo pipefail
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
call(){ jq -n --arg m "$1" --arg k "$ZABBIX_API_KEY" --argjson p "$2" '{jsonrpc:"2.0",method:$m,id:1,auth:$k,params:$p}' \
  | curl -s -X POST $API -H 'Content-Type: application/json-rpc' -d @- > "$3"
  if jq -e '.error' "$3" >/dev/null; then echo "ERROR en $1 (ver $3)"; jq .error "$3"; exit 1; fi; }
call action.get '{"actionids":["7"],"output":["actionid","name","status"],"selectFilter":"extend"}' $D/action7-BEFORE.json
jq -e '.result[0]|select(.name=="Google Chat Loyalty to Operaciones" and (.filter.conditions|any(.value=="CLOUD" and .value2=="service_group")))' $D/action7-BEFORE.json >/dev/null \
  || { echo "GUARDA FALLIDA: la accion 7 no es la esperada o ya no tiene la condicion service_group=CLOUD"; exit 1; }
call action.update '{"actionid":"7","filter":{"evaltype":"3","formula":"A and B and (C or D)","conditions":[{"formulaid":"A","conditiontype":"26","operator":"2","value":"GIT-SML","value2":"scope"},{"formulaid":"B","conditiontype":"26","operator":"2","value":"GCHAT","value2":"action"},{"formulaid":"C","conditiontype":"26","operator":"0","value":"LOYALTY","value2":"service_group"},{"formulaid":"D","conditiontype":"26","operator":"0","value":"CLOUD","value2":"service_group"}]}}' $D/action7-apply.json
call action.get '{"actionids":["7"],"output":["actionid","name","status"],"selectFilter":"extend"}' $D/action7-AFTER.json
jq '.result[0]|{name,status,evaltype:.filter.evaltype,formula:.filter.formula,conditions:(.filter.conditions|map({formulaid,conditiontype,operator,value,value2}))}' $D/action7-AFTER.json
)

# ROLLBACK de 10: restaura las 4 condiciones originales
(
set -euo pipefail
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
jq -n --arg k "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:"action.update",id:1,auth:$k,params:{actionid:"7",filter:{evaltype:"1",conditions:[{conditiontype:"26",operator:"2",value:"GIT-SML",value2:"scope"},{conditiontype:"26",operator:"2",value:"GCHAT",value2:"action"},{conditiontype:"26",operator:"0",value:"LOYALTY",value2:"service_group"},{conditiontype:"26",operator:"0",value:"CLOUD",value2:"service_group"}]}}}' \
  | curl -s -X POST $API -H 'Content-Type: application/json-rpc' -d @- > $D/action7-rollback.json
jq -e '.error' $D/action7-rollback.json >/dev/null && { echo "ERROR"; jq .error $D/action7-rollback.json; exit 1; }
echo "accion 7 restaurada"
)

# ---------------------------------------------------------------------------
# 11. Quitar service_group:CLOUD de los Spike MOBI (26742-26747). EJECUTAR DESPUES DEL PASO 10.
#     CAMBIA ESTADO en Zabbix de produccion. Conserva el resto de los tags.
# ---------------------------------------------------------------------------
(
set -euo pipefail
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
call(){ jq -n --arg m "$1" --arg k "$ZABBIX_API_KEY" --argjson p "$2" '{jsonrpc:"2.0",method:$m,id:1,auth:$k,params:$p}' \
  | curl -s -X POST $API -H 'Content-Type: application/json-rpc' -d @- > "$3"
  if jq -e '.error' "$3" >/dev/null; then echo "ERROR en $1 (ver $3)"; jq .error "$3"; exit 1; fi; }
call trigger.get '{"triggerids":["26742","26743","26744","26745","26746","26747"],"output":["triggerid","description"],"selectHosts":["host"],"selectTags":["tag","value"]}' $D/mobi-spike-tags10-BEFORE.json
for row in "26742 SFCG-MOBI-01" "26743 SFCG-MOBI-01" "26744 SFCG-MOBI-01" "26745 SFCG-MOBI-02" "26746 SFCG-MOBI-02" "26747 SFCG-MOBI-02"; do
  set -- $row
  jq -e --arg id "$1" --arg h "$2" '.result[]|select(.triggerid==$id and .hosts[0].host==$h and (.description|startswith("IIS Spike")) and (.tags|any(.tag=="scope" and .value=="GIT-SML-OPE")) and (.tags|any(.tag=="service_group" and .value=="CLOUD")))' $D/mobi-spike-tags10-BEFORE.json >/dev/null \
    || { echo "GUARDA FALLIDA: trigger $1 no es IIS Spike de $2, o no tiene scope:GIT-SML-OPE / service_group:CLOUD"; exit 1; }
done
for id in 26742 26743 26744 26745 26746 26747; do
  p=$(jq --arg id "$id" '.result[]|select(.triggerid==$id)|{triggerid:$id,tags:(.tags|map(select((.tag=="service_group" and .value=="CLOUD")|not)))}' $D/mobi-spike-tags10-BEFORE.json)
  call trigger.update "$p" $D/tags10-apply-$id.json
  echo "trigger $id: service_group:CLOUD quitado"
done
call trigger.get '{"triggerids":["26742","26743","26744","26745","26746","26747"],"output":["triggerid"],"selectTags":["tag","value"]}' $D/mobi-spike-tags10-AFTER.json
echo "OK - revisar $D/mobi-spike-tags10-AFTER.json"
)

# ROLLBACK de 11: restaura los tags desde mobi-spike-tags10-BEFORE.json
(
set -euo pipefail
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
for id in 26742 26743 26744 26745 26746 26747; do
  p=$(jq --arg id "$id" '.result[]|select(.triggerid==$id)|{triggerid:$id,tags:.tags}' $D/mobi-spike-tags10-BEFORE.json)
  jq -n --arg k "$ZABBIX_API_KEY" --argjson p "$p" '{jsonrpc:"2.0",method:"trigger.update",id:1,auth:$k,params:$p}' \
    | curl -s -X POST $API -H 'Content-Type: application/json-rpc' -d @- > $D/tags10-rollback-$id.json
  jq -e '.error' $D/tags10-rollback-$id.json >/dev/null && { echo "ERROR trigger $id"; exit 1; }
  echo "trigger $id: tags restaurados"
done
)

# ---------------------------------------------------------------------------
# 12. SSL: tiers de certs automatizados (MobileAppService, ClubSite AR, Website) -> contexto :LE = 15/10/7 dias, OK 30
#     Crea {$SSL_CERT_WARN|AVERAGE|HIGH|OK:LE} y reapunta 9 triggers (expresion, recovery y nombre).
#     NO cambia dependencias (ver investigation.md: direccion invertida, paso aparte). CAMBIA ESTADO en Zabbix de produccion.
# ---------------------------------------------------------------------------
(
set -euo pipefail
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
call(){ jq -n --arg m "$1" --arg k "$ZABBIX_API_KEY" --argjson p "$2" '{jsonrpc:"2.0",method:$m,id:1,auth:$k,params:$p}' \
  | curl -s -X POST $API -H 'Content-Type: application/json-rpc' -d @- > "$3"
  if jq -e '.error' "$3" >/dev/null; then echo "ERROR en $1 (ver $3)"; jq .error "$3"; exit 1; fi; }
ROWS="25902|Clubsite AR|clubsite_ar|WARN|>
25915|Clubsite AR|clubsite_ar|AVERAGE|>
25904|Clubsite AR|clubsite_ar|HIGH|>
25918|Website|website|WARN|>
25919|Website|website|AVERAGE|>
25920|Website|website|HIGH|>
25914|MobileAppService|mobileappservice|WARN|>=
26282|MobileAppService|mobileappservice|AVERAGE|>=
26284|MobileAppService|mobileappservice|HIGH|>="
call trigger.get '{"triggerids":["25902","25915","25904","25918","25919","25920","25914","26282","26284"],"output":["triggerid","description","expression","recovery_expression"],"selectHosts":["host"]}' $D/ssl-auto-BEFORE.json
call usermacro.get '{"globalmacro":true,"output":["globalmacroid","macro","value"]}' $D/ssl-macros-BEFORE.json
while IFS='|' read -r id svc slug tier op; do
  jq -e --arg id "$id" --arg s "SSL $svc a menos de" '.result[]|select(.triggerid==$id and .hosts[0].host=="Zabbix server" and (.description|startswith($s)))' $D/ssl-auto-BEFORE.json >/dev/null \
    || { echo "GUARDA FALLIDA: trigger $id no es '$svc' $tier en Zabbix server"; exit 1; }
done <<< "$ROWS"
! jq -e '.result[]|select(.macro|test("^\\{\\$SSL_CERT_(WARN|AVERAGE|HIGH|OK):LE\\}$"))' $D/ssl-macros-BEFORE.json >/dev/null || { echo "ya existen macros :LE, abortando"; exit 1; }
call usermacro.createglobal '[{"macro":"{$SSL_CERT_WARN:LE}","value":"15"},{"macro":"{$SSL_CERT_AVERAGE:LE}","value":"10"},{"macro":"{$SSL_CERT_HIGH:LE}","value":"7"},{"macro":"{$SSL_CERT_OK:LE}","value":"30"}]' $D/ssl-apply-1-macros.json
while IFS='|' read -r id svc slug tier op; do
  KEY="log[/var/log/zabbix/ssl_${slug}.log,,utf-8,,,,,,]"
  name="SSL $svc a menos de {\$SSL_CERT_${tier}:LE} dias de vencer"
  expr="last(/Zabbix server/${KEY},#1)<{\$SSL_CERT_${tier}:LE}"
  rec="last(/Zabbix server/${KEY},#1)${op}{\$SSL_CERT_OK:LE}"
  p=$(jq -n --arg id "$id" --arg d "$name" --arg e "$expr" --arg r "$rec" '{triggerid:$id,description:$d,expression:$e,recovery_expression:$r}')
  call trigger.update "$p" $D/ssl-apply-2-trigger-$id.json
  echo "trigger $id ($svc $tier) -> contexto :LE"
done <<< "$ROWS"
call trigger.get '{"triggerids":["25902","25915","25904","25918","25919","25920","25914","26282","26284"],"output":["triggerid","description","expression","recovery_expression","state","error"],"selectFunctions":["functionid","parameter"],"selectDependencies":["triggerid"]}' $D/ssl-auto-AFTER.json
echo "OK - revisar $D/ssl-auto-AFTER.json (state/error vacios)"
)

# ROLLBACK de 12: restaura expresiones originales (macros por defecto / :MOBI), nombres desde el snapshot, y borra las macros :LE
(
set -euo pipefail
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
call(){ jq -n --arg m "$1" --arg k "$ZABBIX_API_KEY" --argjson p "$2" '{jsonrpc:"2.0",method:$m,id:1,auth:$k,params:$p}' \
  | curl -s -X POST $API -H 'Content-Type: application/json-rpc' -d @- > "$3"
  if jq -e '.error' "$3" >/dev/null; then echo "ERROR en $1 (ver $3)"; jq .error "$3"; exit 1; fi; }
ROWS="25902|clubsite_ar|WARN||>
25915|clubsite_ar|AVERAGE||>
25904|clubsite_ar|HIGH||>
25918|website|WARN||>
25919|website|AVERAGE||>
25920|website|HIGH||>
25914|mobileappservice|WARN|:MOBI|>=
26282|mobileappservice|AVERAGE|:MOBI|>=
26284|mobileappservice|HIGH|:MOBI|>="
while IFS='|' read -r id slug tier ctx op; do
  KEY="log[/var/log/zabbix/ssl_${slug}.log,,utf-8,,,,,,]"
  expr="last(/Zabbix server/${KEY},#1)<{\$SSL_CERT_${tier}${ctx}}"
  rec="last(/Zabbix server/${KEY},#1)${op}{\$SSL_CERT_OK${ctx}}"
  desc=$(jq -r --arg id "$id" '.result[]|select(.triggerid==$id)|.description' $D/ssl-auto-BEFORE.json)
  p=$(jq -n --arg id "$id" --arg d "$desc" --arg e "$expr" --arg r "$rec" --arg e2 "$expr" '{triggerid:$id,description:$d,expression:$e2,recovery_expression:$r}')
  call trigger.update "$p" $D/ssl-rollback-trigger-$id.json
done <<< "$ROWS"
call usermacro.get '{"globalmacro":true,"output":["globalmacroid","macro","value"]}' $D/ssl-macros-ROLLBACK-pre.json
NEW=$(jq -c '[.result[]|select(.macro|test("^\\{\\$SSL_CERT_(WARN|AVERAGE|HIGH|OK):LE\\}$"))|.globalmacroid]' $D/ssl-macros-ROLLBACK-pre.json)
call usermacro.deleteglobal "$NEW" $D/ssl-rollback-delete-macros.json
echo "rollback aplicado"
)

# ---------------------------------------------------------------------------
# 13. SSL: corregir direccion de dependencias en los 8 servicios (24 triggers de vencimiento en "Zabbix server")
#     antes (invertido): Average depende de Warning; High depende de Average (Bot-Security: de Warning; Clubsite AR: de FacturaSend Average)
#     ahora: High sin dependencias; Average depende de High; Warning depende de Average y High
#     Orden High -> Average -> Warning para no crear dependencias circulares durante el cambio. CAMBIA ESTADO en produccion.
# ---------------------------------------------------------------------------
(
set -euo pipefail
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
call(){ jq -n --arg m "$1" --arg k "$ZABBIX_API_KEY" --argjson p "$2" '{jsonrpc:"2.0",method:$m,id:1,auth:$k,params:$p}' \
  | curl -s -X POST $API -H 'Content-Type: application/json-rpc' -d @- > "$3"
  if jq -e '.error' "$3" >/dev/null; then echo "ERROR en $1 (ver $3)"; jq .error "$3"; exit 1; fi; }
ROWS="Bot-Security|26566|26569|26567
Clubsite AR|25902|25915|25904
Clubsite PY|25906|25907|25913
FacturaSend|26283|25903|25917
MobileAppService|25914|26282|26284
smartfran|25912|25911|25926
WebServiceV2|25924|25925|25908
Website|25918|25919|25920"
call trigger.get '{"triggerids":["26566","26569","26567","25902","25915","25904","25906","25907","25913","26283","25903","25917","25914","26282","26284","25912","25911","25926","25924","25925","25908","25918","25919","25920"],"output":["triggerid","description","priority"],"selectHosts":["host"],"selectDependencies":["triggerid"]}' $D/ssl-deps-BEFORE.json
[ "$(jq '.result|length' $D/ssl-deps-BEFORE.json)" = "24" ] || { echo "GUARDA FALLIDA: se esperaban 24 triggers"; exit 1; }
while IFS='|' read -r svc w a h; do
  for row in "$w|WARN|2" "$a|AVERAGE|3" "$h|HIGH|4"; do
    IFS='|' read -r id tier pr <<< "$row"
    jq -e --arg id "$id" --arg s "$svc" --arg t "SSL_CERT_$tier" --arg pr "$pr" '.result[]|select(.triggerid==$id and .priority==$pr and .hosts[0].host=="Zabbix server" and (.description|ascii_downcase|contains($s|ascii_downcase)) and (.description|contains($t)))' $D/ssl-deps-BEFORE.json >/dev/null \
      || { echo "GUARDA FALLIDA: trigger $id no es '$svc' $tier"; exit 1; }
  done
done <<< "$ROWS"
while IFS='|' read -r svc w a h; do
  call trigger.update "{\"triggerid\":\"$h\",\"dependencies\":[]}" $D/ssl-deps-apply-$h.json
  call trigger.update "{\"triggerid\":\"$a\",\"dependencies\":[{\"triggerid\":\"$h\"}]}" $D/ssl-deps-apply-$a.json
  call trigger.update "{\"triggerid\":\"$w\",\"dependencies\":[{\"triggerid\":\"$a\"},{\"triggerid\":\"$h\"}]}" $D/ssl-deps-apply-$w.json
  echo "$svc: High sin dependencias; Average -> High; Warning -> Average, High"
done <<< "$ROWS"
call trigger.get '{"triggerids":["26566","26569","26567","25902","25915","25904","25906","25907","25913","26283","25903","25917","25914","26282","26284","25912","25911","25926","25924","25925","25908","25918","25919","25920"],"output":["triggerid","description","priority"],"selectDependencies":["triggerid"]}' $D/ssl-deps-AFTER.json
jq -r '.result|sort_by(.description)[]|"\(.triggerid) [\(.priority)] deps=\([.dependencies[].triggerid]|join(","))"' $D/ssl-deps-AFTER.json
echo "OK - revisar $D/ssl-deps-AFTER.json"
)

# ROLLBACK de 13: restaura las dependencias originales desde ssl-deps-BEFORE.json (orden Warning -> Average -> High)
(
set -euo pipefail
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
call(){ jq -n --arg m "$1" --arg k "$ZABBIX_API_KEY" --argjson p "$2" '{jsonrpc:"2.0",method:$m,id:1,auth:$k,params:$p}' \
  | curl -s -X POST $API -H 'Content-Type: application/json-rpc' -d @- > "$3"
  if jq -e '.error' "$3" >/dev/null; then echo "ERROR en $1 (ver $3)"; jq .error "$3"; exit 1; fi; }
ROWS="Bot-Security|26566|26569|26567
Clubsite AR|25902|25915|25904
Clubsite PY|25906|25907|25913
FacturaSend|26283|25903|25917
MobileAppService|25914|26282|26284
smartfran|25912|25911|25926
WebServiceV2|25924|25925|25908
Website|25918|25919|25920"
while IFS='|' read -r svc w a h; do
  for id in $w $a $h; do
    p=$(jq --arg id "$id" '.result[]|select(.triggerid==$id)|{triggerid:$id,dependencies:[.dependencies[]|{triggerid}]}' $D/ssl-deps-BEFORE.json)
    call trigger.update "$p" $D/ssl-deps-rollback-$id.json
  done
  echo "$svc: dependencias originales restauradas"
done <<< "$ROWS"
)

# ---------------------------------------------------------------------------
# 14. SSL "No data from SSL <x> from 1 day": ventana 1d -> macro {$SSL_CERT_NODATA_WINDOW} = 2d (8 triggers)
#     CAMBIA ESTADO en Zabbix de produccion. Rollback al final de este bloque.
# ---------------------------------------------------------------------------
(
set -euo pipefail
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
call(){ jq -n --arg m "$1" --arg k "$ZABBIX_API_KEY" --argjson p "$2" '{jsonrpc:"2.0",method:$m,id:1,auth:$k,params:$p}' \
  | curl -s -X POST $API -H 'Content-Type: application/json-rpc' -d @- > "$3"
  if jq -e '.error' "$3" >/dev/null; then echo "ERROR en $1 (ver $3)"; jq .error "$3"; exit 1; fi; }
ROWS="26568|Bot-Security|bot-security
25910|Clubsite AR|clubsite_ar
25909|Clubsite PY|clubsite_py
25916|FacturaSend|fs-api
26285|MobileAppService|mobileappservice
25905|Smartfran|smartfran
25923|WebServiceV2|webservicev2
25921|Website|website"
call trigger.get '{"triggerids":["26568","25910","25909","25916","26285","25905","25923","25921"],"output":["triggerid","description","expression"],"selectHosts":["host"]}' $D/ssl-nodata-BEFORE.json
call usermacro.get '{"globalmacro":true,"output":["globalmacroid","macro","value"]}' $D/ssl-nodata-macros-BEFORE.json
[ "$(jq '.result|length' $D/ssl-nodata-BEFORE.json)" = "8" ] || { echo "GUARDA FALLIDA: se esperaban 8 triggers"; exit 1; }
while IFS='|' read -r id svc slug; do
  jq -e --arg id "$id" --arg s "$svc" '.result[]|select(.triggerid==$id and .hosts[0].host=="Zabbix server" and (.description|startswith("No data from SSL")) and (.description|ascii_downcase|contains($s|ascii_downcase)) and (.description|contains("from 1 day")))' $D/ssl-nodata-BEFORE.json >/dev/null \
    || { echo "GUARDA FALLIDA: trigger $id no es el No data de $svc (o ya no dice 'from 1 day')"; exit 1; }
done <<< "$ROWS"
! jq -e '.result[]|select(.macro=="{$SSL_CERT_NODATA_WINDOW}")' $D/ssl-nodata-macros-BEFORE.json >/dev/null || { echo "ya existe {\$SSL_CERT_NODATA_WINDOW}, abortando"; exit 1; }
call usermacro.createglobal '[{"macro":"{$SSL_CERT_NODATA_WINDOW}","value":"2d"}]' $D/ssl-nodata-apply-macro.json
while IFS='|' read -r id svc slug; do
  KEY="log[/var/log/zabbix/ssl_${slug}.log,,utf-8,,,,,,]"
  name=$(jq -r --arg id "$id" '.result[]|select(.triggerid==$id)|.description|sub("from 1 day";"from {$SSL_CERT_NODATA_WINDOW}")' $D/ssl-nodata-BEFORE.json)
  p=$(jq -n --arg id "$id" --arg d "$name" --arg e "nodata(/Zabbix server/${KEY},{\$SSL_CERT_NODATA_WINDOW})=1" '{triggerid:$id,description:$d,expression:$e}')
  call trigger.update "$p" $D/ssl-nodata-apply-$id.json
  echo "trigger $id ($svc): nodata 1d -> {\$SSL_CERT_NODATA_WINDOW}"
done <<< "$ROWS"
call trigger.get '{"triggerids":["26568","25910","25909","25916","26285","25905","25923","25921"],"output":["triggerid","description","state","error"],"selectFunctions":["functionid","parameter"]}' $D/ssl-nodata-AFTER.json
jq -r '.result[]|"\(.triggerid) state=\(.state) err=\(.error) | \(.description) | \([.functions[].parameter]|join(";"))"' $D/ssl-nodata-AFTER.json
)

# ROLLBACK de 14: nombres originales, ventana 1d explicita, borra la macro
(
set -euo pipefail
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
call(){ jq -n --arg m "$1" --arg k "$ZABBIX_API_KEY" --argjson p "$2" '{jsonrpc:"2.0",method:$m,id:1,auth:$k,params:$p}' \
  | curl -s -X POST $API -H 'Content-Type: application/json-rpc' -d @- > "$3"
  if jq -e '.error' "$3" >/dev/null; then echo "ERROR en $1 (ver $3)"; jq .error "$3"; exit 1; fi; }
ROWS="26568|bot-security
25910|clubsite_ar
25909|clubsite_py
25916|fs-api
26285|mobileappservice
25905|smartfran
25923|webservicev2
25921|website"
while IFS='|' read -r id slug; do
  KEY="log[/var/log/zabbix/ssl_${slug}.log,,utf-8,,,,,,]"
  desc=$(jq -r --arg id "$id" '.result[]|select(.triggerid==$id)|.description' $D/ssl-nodata-BEFORE.json)
  p=$(jq -n --arg id "$id" --arg d "$desc" --arg e "nodata(/Zabbix server/${KEY},1d)=1" '{triggerid:$id,description:$d,expression:$e}')
  call trigger.update "$p" $D/ssl-nodata-rollback-$id.json
done <<< "$ROWS"
call usermacro.get '{"globalmacro":true,"output":["globalmacroid","macro"]}' $D/ssl-nodata-macros-ROLLBACK-pre.json
NEW=$(jq -c '[.result[]|select(.macro=="{$SSL_CERT_NODATA_WINDOW}")|.globalmacroid]' $D/ssl-nodata-macros-ROLLBACK-pre.json)
call usermacro.deleteglobal "$NEW" $D/ssl-nodata-rollback-macro.json
echo "rollback aplicado"
)

# ---------------------------------------------------------------------------
# 15. SSL: tag SVC_FRIENDLYNAME = "SSL <servicio>" en los 32 triggers (24 vencimiento + 8 No data); conserva el resto de los tags
#     CAMBIA ESTADO en Zabbix de produccion. Rollback al final de este bloque.
# ---------------------------------------------------------------------------
(
set -euo pipefail
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
call(){ jq -n --arg m "$1" --arg k "$ZABBIX_API_KEY" --argjson p "$2" '{jsonrpc:"2.0",method:$m,id:1,auth:$k,params:$p}' \
  | curl -s -X POST $API -H 'Content-Type: application/json-rpc' -d @- > "$3"
  if jq -e '.error' "$3" >/dev/null; then echo "ERROR en $1 (ver $3)"; jq .error "$3"; exit 1; fi; }
ROWS="Bot-Security|SSL Bot-Security|26566 26569 26567 26568
Clubsite AR|SSL Clubsite AR|25902 25915 25904 25910
Clubsite PY|SSL Clubsite PY|25906 25907 25913 25909
FacturaSend|SSL FacturaSend|26283 25903 25917 25916
MobileAppService|SSL MobileAppService|25914 26282 26284 26285
smartfran|SSL www.smartfran|25912 25911 25926 25905
WebServiceV2|SSL WebServiceV2|25924 25925 25908 25923
Website|SSL Website|25918 25919 25920 25921"
ALL='["26566","26569","26567","26568","25902","25915","25904","25910","25906","25907","25913","25909","26283","25903","25917","25916","25914","26282","26284","26285","25912","25911","25926","25905","25924","25925","25908","25923","25918","25919","25920","25921"]'
call trigger.get "{\"triggerids\":$ALL,\"output\":[\"triggerid\",\"description\"],\"selectHosts\":[\"host\"],\"selectTags\":[\"tag\",\"value\"]}" $D/ssl-tags15-BEFORE.json
[ "$(jq '.result|length' $D/ssl-tags15-BEFORE.json)" = "32" ] || { echo "GUARDA FALLIDA: se esperaban 32 triggers"; exit 1; }
while IFS='|' read -r svc disp ids; do
  for id in $ids; do
    jq -e --arg id "$id" --arg s "$svc" '.result[]|select(.triggerid==$id and .hosts[0].host=="Zabbix server" and (.description|ascii_downcase|contains($s|ascii_downcase)))' $D/ssl-tags15-BEFORE.json >/dev/null \
      || { echo "GUARDA FALLIDA: trigger $id no corresponde a $svc"; exit 1; }
  done
done <<< "$ROWS"
while IFS='|' read -r svc disp ids; do
  for id in $ids; do
    p=$(jq --arg id "$id" --arg v "$disp" '.result[]|select(.triggerid==$id)|{triggerid:$id,tags:((.tags|map(select(.tag!="SVC_FRIENDLYNAME")))+[{"tag":"SVC_FRIENDLYNAME","value":$v}])}' $D/ssl-tags15-BEFORE.json)
    call trigger.update "$p" $D/ssl-tags15-apply-$id.json
  done
  echo "$svc: SVC_FRIENDLYNAME=$disp en 4 triggers"
done <<< "$ROWS"
call trigger.get "{\"triggerids\":$ALL,\"output\":[\"triggerid\"],\"selectTags\":[\"tag\",\"value\"]}" $D/ssl-tags15-AFTER.json
jq -r '.result|length as $n|"triggers con SVC_FRIENDLYNAME: \([.[]|select(.tags|any(.tag=="SVC_FRIENDLYNAME"))]|length) de \($n)"' $D/ssl-tags15-AFTER.json
)

# ROLLBACK de 15: restaura los tags desde ssl-tags15-BEFORE.json
(
set -euo pipefail
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
for id in $(jq -r '.result[].triggerid' $D/ssl-tags15-BEFORE.json); do
  p=$(jq --arg id "$id" '.result[]|select(.triggerid==$id)|{triggerid:$id,tags:.tags}' $D/ssl-tags15-BEFORE.json)
  jq -n --arg k "$ZABBIX_API_KEY" --argjson p "$p" '{jsonrpc:"2.0",method:"trigger.update",id:1,auth:$k,params:$p}' \
    | curl -s -X POST $API -H 'Content-Type: application/json-rpc' -d @- > $D/ssl-tags15-rollback-$id.json
  jq -e '.error' $D/ssl-tags15-rollback-$id.json >/dev/null && { echo "ERROR trigger $id"; exit 1; }
done
echo "tags restaurados"
)

# ---------------------------------------------------------------------------
# 16. Limpieza de macros globales sin uso: {$MOBILE_PCOUNT_SPIKE_(WARN|AVG|HIGH|OK):MOBI01|MOBI02}, {$MOBILE_PCOUNT_SPIKE_TIME},
#     {$SSL_CERT_(WARN|AVERAGE|HIGH|OK):MOBI}  (13 macros). Revisa uso en TODOS los triggers (nombre, expresion, recovery y parametros de
#     funciones) e items (nombre, key, delay) y ABORTA sin borrar nada si encuentra alguno. CAMBIA ESTADO en produccion.
# ---------------------------------------------------------------------------
(
set -euo pipefail
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
call(){ jq -n --arg m "$1" --arg k "$ZABBIX_API_KEY" --argjson p "$2" '{jsonrpc:"2.0",method:$m,id:1,auth:$k,params:$p}' \
  | curl -s -X POST $API -H 'Content-Type: application/json-rpc' -d @- > "$3"
  if jq -e '.error' "$3" >/dev/null; then echo "ERROR en $1 (ver $3)"; jq .error "$3"; exit 1; fi; }
PAT='MOBILE_PCOUNT_SPIKE_(WARN|AVG|HIGH|OK):MOBI0[12]\}|MOBILE_PCOUNT_SPIKE_TIME\}|SSL_CERT_(WARN|AVERAGE|HIGH|OK):MOBI\}'
call trigger.get '{"output":["triggerid","description","expression","recovery_expression"],"selectFunctions":["parameter"]}' $D/macro-cleanup-triggers.json
call item.get '{"output":["itemid","name","key_","delay"]}' $D/macro-cleanup-items.json
call usermacro.get '{"globalmacro":true,"output":["globalmacroid","macro","value"]}' $D/macro-cleanup-BEFORE.json
TH=$(jq --arg p "$PAT" '[.result[]|select((.description+" "+.expression+" "+.recovery_expression+" "+([.functions[].parameter]|join(" ")))|test($p))|{triggerid,description}]' $D/macro-cleanup-triggers.json)
IH=$(jq --arg p "$PAT" '[.result[]|select((.name+" "+.key_+" "+.delay)|test($p))|{itemid,name}]' $D/macro-cleanup-items.json)
echo "triggers que aun usan las macros: $(echo "$TH"|jq length); items: $(echo "$IH"|jq length)"
if [ "$(echo "$TH"|jq length)" != "0" ] || [ "$(echo "$IH"|jq length)" != "0" ]; then echo "$TH"; echo "$IH"; echo "ABORTADO: macros en uso, no se borro nada"; exit 1; fi
IDS=$(jq -c '[.result[]|select(.macro|test("^\\{\\$MOBILE_PCOUNT_SPIKE_(WARN|AVG|HIGH|OK):MOBI0[12]\\}$|^\\{\\$MOBILE_PCOUNT_SPIKE_TIME\\}$|^\\{\\$SSL_CERT_(WARN|AVERAGE|HIGH|OK):MOBI\\}$"))|.globalmacroid]' $D/macro-cleanup-BEFORE.json)
echo "macros a borrar: $(echo "$IDS"|jq length) (esperadas: 13)"
jq -r '.result[]|select(.macro|test("^\\{\\$MOBILE_PCOUNT_SPIKE_(WARN|AVG|HIGH|OK):MOBI0[12]\\}$|^\\{\\$MOBILE_PCOUNT_SPIKE_TIME\\}$|^\\{\\$SSL_CERT_(WARN|AVERAGE|HIGH|OK):MOBI\\}$"))|"  \(.macro) = \(.value)"' $D/macro-cleanup-BEFORE.json
[ "$(echo "$IDS"|jq length)" = "13" ] || { echo "ABORTADO: no son 13 macros, revisar la lista"; exit 1; }
call usermacro.deleteglobal "$IDS" $D/macro-cleanup-apply.json
echo "OK - 13 macros globales borradas (valores en $D/macro-cleanup-BEFORE.json)"
)

# ROLLBACK de 16: recrea las 13 macros con sus valores originales
(
set -euo pipefail
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
P=$(jq -c '[.result[]|select(.macro|test("^\\{\\$MOBILE_PCOUNT_SPIKE_(WARN|AVG|HIGH|OK):MOBI0[12]\\}$|^\\{\\$MOBILE_PCOUNT_SPIKE_TIME\\}$|^\\{\\$SSL_CERT_(WARN|AVERAGE|HIGH|OK):MOBI\\}$"))|{macro,value}]' $D/macro-cleanup-BEFORE.json)
jq -n --arg k "$ZABBIX_API_KEY" --argjson p "$P" '{jsonrpc:"2.0",method:"usermacro.createglobal",id:1,auth:$k,params:$p}' \
  | curl -s -X POST $API -H 'Content-Type: application/json-rpc' -d @- > $D/macro-cleanup-rollback.json
jq -e '.error' $D/macro-cleanup-rollback.json >/dev/null && { echo "ERROR"; jq .error $D/macro-cleanup-rollback.json; exit 1; }
echo "macros restauradas"
)

# ---------------------------------------------------------------------------
# 17. Accion 7 (Operaciones Chat): service_group = LOYALTY OR CLOUD  (para enrutar ARCA, service_group:CLOUD, a OPE)
#     antes: scope = GIT-SML-OPE AND action ~ GCHAT AND service_group = LOYALTY            (evaltype And)
#     ahora: scope = GIT-SML-OPE AND action ~ GCHAT AND (service_group = LOYALTY OR = CLOUD) (evaltype 3, "A and B and (C or D)")
#     CAMBIA ESTADO en Zabbix de produccion. Rollback al final del bloque.
# ---------------------------------------------------------------------------
(
set -euo pipefail
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
call(){ jq -n --arg m "$1" --arg k "$ZABBIX_API_KEY" --argjson p "$2" '{jsonrpc:"2.0",method:$m,id:1,auth:$k,params:$p}' \
  | curl -s -X POST $API -H 'Content-Type: application/json-rpc' -d @- > "$3"
  if jq -e '.error' "$3" >/dev/null; then echo "ERROR en $1 (ver $3)"; jq .error "$3"; exit 1; fi; }
call action.get '{"actionids":["7"],"output":["actionid","name","status"],"selectFilter":"extend"}' $D/action7-v2-BEFORE.json
jq -e '.result[0]|select(.name=="Google Chat Loyalty to Operaciones" and .filter.evaltype=="1" and (.filter.conditions|length)==3 and (.filter.conditions|any(.value=="GIT-SML-OPE" and .value2=="scope" and .operator=="0")) and (.filter.conditions|any(.value=="LOYALTY" and .value2=="service_group")) and ((.filter.conditions|any(.value=="CLOUD"))|not))' $D/action7-v2-BEFORE.json >/dev/null \
  || { echo "GUARDA FALLIDA: la accion 7 no tiene el filtro esperado (scope=GIT-SML-OPE, GCHAT, LOYALTY)"; exit 1; }
call action.update '{"actionid":"7","filter":{"evaltype":"3","formula":"A and B and (C or D)","conditions":[{"formulaid":"A","conditiontype":"26","operator":"0","value":"GIT-SML-OPE","value2":"scope"},{"formulaid":"B","conditiontype":"26","operator":"2","value":"GCHAT","value2":"action"},{"formulaid":"C","conditiontype":"26","operator":"0","value":"LOYALTY","value2":"service_group"},{"formulaid":"D","conditiontype":"26","operator":"0","value":"CLOUD","value2":"service_group"}]}}' $D/action7-v2-apply.json
call action.get '{"actionids":["7"],"output":["actionid","name","status"],"selectFilter":"extend"}' $D/action7-v2-AFTER.json
jq '.result[0]|{name,status,evaltype:.filter.evaltype,formula:.filter.formula,conditions:(.filter.conditions|map({formulaid,operator,value,value2}))}' $D/action7-v2-AFTER.json
)

# ROLLBACK de 17: vuelve a las 3 condiciones con evaltype And
(
set -euo pipefail
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
jq -n --arg k "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:"action.update",id:1,auth:$k,params:{actionid:"7",filter:{evaltype:"1",conditions:[{conditiontype:"26",operator:"0",value:"GIT-SML-OPE",value2:"scope"},{conditiontype:"26",operator:"2",value:"GCHAT",value2:"action"},{conditiontype:"26",operator:"0",value:"LOYALTY",value2:"service_group"}]}}}' \
  | curl -s -X POST $API -H 'Content-Type: application/json-rpc' -d @- > $D/action7-v2-rollback.json
jq -e '.error' $D/action7-v2-rollback.json >/dev/null && { echo "ERROR"; jq .error $D/action7-v2-rollback.json; exit 1; }
echo "accion 7 restaurada (3 condiciones, And)"
)

# ---------------------------------------------------------------------------
# 18. ARCA -> Operaciones Chat: en TODOS los triggers "ARCA*" de Zabbix server agrega scope:GIT-SML-OPE (conserva scope:GIT-SML) y
#     SVC_FRIENDLYNAME (variable SVC). Ejecutar DESPUES del paso 17. CAMBIA ESTADO en produccion. Rollback al final del bloque.
# ---------------------------------------------------------------------------
(
set -euo pipefail
SVC='ARCA'
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
call(){ jq -n --arg m "$1" --arg k "$ZABBIX_API_KEY" --argjson p "$2" '{jsonrpc:"2.0",method:$m,id:1,auth:$k,params:$p}' \
  | curl -s -X POST $API -H 'Content-Type: application/json-rpc' -d @- > "$3"
  if jq -e '.error' "$3" >/dev/null; then echo "ERROR en $1 (ver $3)"; jq .error "$3"; exit 1; fi; }
call trigger.get '{"filter":{"host":["Zabbix server"]},"search":{"description":"ARCA"},"output":["triggerid","description","priority"],"selectHosts":["host"],"selectTags":["tag","value"]}' $D/arca-tags-BEFORE.json
N=$(jq '.result|length' $D/arca-tags-BEFORE.json)
echo "triggers ARCA encontrados: $N"; jq -r '.result[]|"  \(.triggerid) [\(.priority)] \(.description)"' $D/arca-tags-BEFORE.json
{ [ "$N" -ge 4 ] && [ "$N" -le 6 ]; } || { echo "GUARDA FALLIDA: se esperaban entre 4 y 6 triggers ARCA"; exit 1; }
jq -e '.result|all((.description|startswith("ARCA")) and (.tags|any(.tag=="service_group" and .value=="CLOUD")) and (.tags|any(.tag=="scope" and .value=="GIT-SML")))' $D/arca-tags-BEFORE.json >/dev/null \
  || { echo "GUARDA FALLIDA: algun trigger no empieza con ARCA o no tiene service_group:CLOUD y scope:GIT-SML"; exit 1; }
for id in $(jq -r '.result[].triggerid' $D/arca-tags-BEFORE.json); do
  p=$(jq --arg id "$id" --arg v "$SVC" '.result[]|select(.triggerid==$id)|{triggerid:$id,tags:((.tags|map(select(.tag!="SVC_FRIENDLYNAME"))+[{"tag":"scope","value":"GIT-SML-OPE"},{"tag":"SVC_FRIENDLYNAME","value":$v}])|unique_by([.tag,.value]))}' $D/arca-tags-BEFORE.json)
  call trigger.update "$p" $D/arca-tags-apply-$id.json
  echo "trigger $id: scope:GIT-SML-OPE + SVC_FRIENDLYNAME=$SVC"
done
call trigger.get '{"filter":{"host":["Zabbix server"]},"search":{"description":"ARCA"},"output":["triggerid","description"],"selectTags":["tag","value"]}' $D/arca-tags-AFTER.json
jq -r '.result[]|"\(.triggerid) \(.description): \([.tags[]|select(.tag=="scope" or .tag=="service_group" or .tag=="action" or .tag=="SVC_FRIENDLYNAME")|"\(.tag)=\(.value)"]|join(" "))"' $D/arca-tags-AFTER.json
)

# ROLLBACK de 18: restaura los tags desde arca-tags-BEFORE.json
(
set -euo pipefail
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
for id in $(jq -r '.result[].triggerid' $D/arca-tags-BEFORE.json); do
  p=$(jq --arg id "$id" '.result[]|select(.triggerid==$id)|{triggerid:$id,tags:.tags}' $D/arca-tags-BEFORE.json)
  jq -n --arg k "$ZABBIX_API_KEY" --argjson p "$p" '{jsonrpc:"2.0",method:"trigger.update",id:1,auth:$k,params:$p}' \
    | curl -s -X POST $API -H 'Content-Type: application/json-rpc' -d @- > $D/arca-tags-rollback-$id.json
  jq -e '.error' $D/arca-tags-rollback-$id.json >/dev/null && { echo "ERROR trigger $id"; exit 1; }
done
echo "tags ARCA restaurados"
)

# ---------------------------------------------------------------------------
# 19. IIS request queue: arreglar {$IIS.QUEUE.MAX.WARN} vacio (plantilla "IIS by Zabbix agent active", templateid 10326) y agregar 3 niveles
#     Macros de plantilla WARN/AVG/HIGH (10/50/200), ventana {$IIS.QUEUE.MAX.TIME}=5m (sin cambio); 2 prototipos nuevos (Average, High);
#     Warning (16917) depende de Average, High y 16914 ("app pool no Running"); tags de ruteo (ROUTE=1); historial del item prototype 7d -> 365d (1 anio).
#     AFECTA a los 12 hosts que enlazan la plantilla. Los triggers descubiertos se actualizan en la proxima ejecucion de LLD.
#     CAMBIA ESTADO en Zabbix de produccion. Rollback al final del bloque.
# ---------------------------------------------------------------------------
(
set -euo pipefail
WARN=10; AVG=50; HIGH=200; ROUTE=1; HIST=365d
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
call(){ jq -n --arg m "$1" --arg k "$ZABBIX_API_KEY" --argjson p "$2" '{jsonrpc:"2.0",method:$m,id:1,auth:$k,params:$p}' \
  | curl -s -X POST $API -H 'Content-Type: application/json-rpc' -d @- > "$3"
  if jq -e '.error' "$3" >/dev/null; then echo "ERROR en $1 (ver $3)"; jq .error "$3"; exit 1; fi; }
call triggerprototype.get '{"triggerids":["16917","16914"],"output":["triggerid","description","expression","priority"],"selectDependencies":["triggerid"],"selectTags":["tag","value"],"selectFunctions":["functionid","parameter"]}' $D/iis-queue-apply-BEFORE-protos.json
call itemprototype.get '{"itemids":["31051"],"output":["itemid","key_","history"]}' $D/iis-queue-apply-BEFORE-itemproto.json
call usermacro.get '{"hostids":["10326"],"output":["hostmacroid","macro","value"]}' $D/iis-queue-apply-BEFORE-macros.json
call triggerprototype.get '{"templateids":["10326"],"output":["triggerid","description"]}' $D/iis-queue-apply-BEFORE-allprotos.json
jq -e '.result[]|select(.triggerid=="16917" and .description=="IIS: Request queue of {#APPPOOL} is too large")' $D/iis-queue-apply-BEFORE-protos.json >/dev/null || { echo "GUARDA FALLIDA: prototipo 16917 no es el esperado"; exit 1; }
jq -e '.result[]|select(.triggerid=="16914" and (.description|startswith("IIS: Application pool {#APPPOOL} is not in Running state")))' $D/iis-queue-apply-BEFORE-protos.json >/dev/null || { echo "GUARDA FALLIDA: prototipo 16914 no es el esperado"; exit 1; }
jq -e '.result[]|select(.hostmacroid=="1328" and .macro=="{$IIS.QUEUE.MAX.WARN}" and .value=="")' $D/iis-queue-apply-BEFORE-macros.json >/dev/null || { echo "GUARDA FALLIDA: la macro WARN ya no esta vacia"; exit 1; }
! jq -e '.result[]|select(.macro=="{$IIS.QUEUE.MAX.AVG}" or .macro=="{$IIS.QUEUE.MAX.HIGH}")' $D/iis-queue-apply-BEFORE-macros.json >/dev/null || { echo "ya existen AVG/HIGH en la plantilla"; exit 1; }
jq -e '.result[]|select(.triggerid=="31051" or .itemid=="31051")|select(.history=="7d")' $D/iis-queue-apply-BEFORE-itemproto.json >/dev/null || { echo "GUARDA FALLIDA: item prototype 31051 no tiene history 7d"; exit 1; }
! jq -e '.result[]|select(.description|test("\\((Average|High)\\)"))' $D/iis-queue-apply-BEFORE-allprotos.json >/dev/null || { echo "ya hay prototipos Average/High"; exit 1; }
TAGS='[{"tag":"scope","value":"performance"}]'
[ "$ROUTE" = 1 ] && TAGS='[{"tag":"scope","value":"performance"},{"tag":"scope","value":"GIT-SML-OPE"},{"tag":"service_group","value":"LOYALTY"},{"tag":"action","value":"GCHAT"},{"tag":"SVC_FRIENDLYNAME","value":"IIS request queue"}]'
KEY='perf_counter_en["\HTTP Service Request Queues({#APPPOOL})\CurrentQueueSize"]'
mk(){ jq -n --arg d "IIS: Request queue of {#APPPOOL} is too large ($1)" --arg e "min(/IIS by Zabbix agent active/${KEY},{\$IIS.QUEUE.MAX.TIME})>{\$IIS.QUEUE.MAX.$3}" --arg p "$2" --argjson deps "$4" --argjson tags "$TAGS" '{description:$d,expression:$e,priority:$p,dependencies:$deps,tags:$tags}'; }
call usermacro.update "{\"hostmacroid\":\"1328\",\"value\":\"$WARN\"}" $D/iis-queue-apply-1-macro-warn.json
call usermacro.create "[{\"hostid\":\"10326\",\"macro\":\"{\$IIS.QUEUE.MAX.AVG}\",\"value\":\"$AVG\"},{\"hostid\":\"10326\",\"macro\":\"{\$IIS.QUEUE.MAX.HIGH}\",\"value\":\"$HIGH\"}]" $D/iis-queue-apply-2-macros-new.json
call triggerprototype.create "$(mk High 4 HIGH '[{"triggerid":"16914"}]')" $D/iis-queue-apply-3-proto-high.json
HID=$(jq -r '.result.triggerids[0]' $D/iis-queue-apply-3-proto-high.json)
call triggerprototype.create "$(mk Average 3 AVG "[{\"triggerid\":\"$HID\"},{\"triggerid\":\"16914\"}]")" $D/iis-queue-apply-4-proto-avg.json
AID=$(jq -r '.result.triggerids[0]' $D/iis-queue-apply-4-proto-avg.json)
call triggerprototype.update "$(jq -n --argjson tags "$TAGS" --arg a "$AID" --arg h "$HID" '{triggerid:"16917",dependencies:[{triggerid:$a},{triggerid:$h},{triggerid:"16914"}],tags:$tags}')" $D/iis-queue-apply-5-proto-warn.json
call itemprototype.update "{\"itemid\":\"31051\",\"history\":\"$HIST\"}" $D/iis-queue-apply-6-itemproto.json
echo "prototipos creados: High=$HID Average=$AID"
call triggerprototype.get '{"templateids":["10326"],"output":["triggerid","description","expression","priority"],"selectDependencies":["triggerid"],"selectTags":["tag","value"],"selectFunctions":["functionid","parameter"]}' $D/iis-queue-apply-AFTER-protos.json
jq -r '.result[]|select(.description|test("Request queue"))|"\(.triggerid) [\(.priority)] \(.description) deps=\([.dependencies[].triggerid]|join(","))"' $D/iis-queue-apply-AFTER-protos.json
)

# ROLLBACK de 19: Warning vuelve a depender solo de 16914 con su tag original; borra los 2 prototipos nuevos y las macros AVG/HIGH; WARN vuelve a ''; history 7d
(
set -euo pipefail
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
call(){ jq -n --arg m "$1" --arg k "$ZABBIX_API_KEY" --argjson p "$2" '{jsonrpc:"2.0",method:$m,id:1,auth:$k,params:$p}' \
  | curl -s -X POST $API -H 'Content-Type: application/json-rpc' -d @- > "$3"
  if jq -e '.error' "$3" >/dev/null; then echo "ERROR en $1 (ver $3)"; jq .error "$3"; exit 1; fi; }
HID=$(jq -r '.result.triggerids[0]' $D/iis-queue-apply-3-proto-high.json); AID=$(jq -r '.result.triggerids[0]' $D/iis-queue-apply-4-proto-avg.json)
call triggerprototype.update '{"triggerid":"16917","dependencies":[{"triggerid":"16914"}],"tags":[{"tag":"scope","value":"performance"}]}' $D/iis-queue-rollback-1-warn.json
call triggerprototype.delete "[\"$AID\",\"$HID\"]" $D/iis-queue-rollback-2-delete-protos.json
call usermacro.get '{"hostids":["10326"],"output":["hostmacroid","macro"]}' $D/iis-queue-rollback-pre-macros.json
NEW=$(jq -c '[.result[]|select(.macro=="{$IIS.QUEUE.MAX.AVG}" or .macro=="{$IIS.QUEUE.MAX.HIGH}")|.hostmacroid]' $D/iis-queue-rollback-pre-macros.json)
call usermacro.delete "$NEW" $D/iis-queue-rollback-3-delete-macros.json
call usermacro.update '{"hostmacroid":"1328","value":""}' $D/iis-queue-rollback-4-warn-empty.json
call itemprototype.update '{"itemid":"31051","history":"7d"}' $D/iis-queue-rollback-5-itemproto.json
echo "rollback aplicado"
)

# ---------------------------------------------------------------------------
# 20. Caida brusca -> detector de colapso a ~0 req/s (posible bloqueo del WAF de Grido) en MOBI-02
#     Reutiliza el trigger 26287 (MOBI-02, ahora High) y deshabilita 26286 (MOBI-01) y 26448 (suma, High, depende de ambos).
#     Condicion: max(5m) <= 0.2 req/s  Y  en los 30m previos (desplazados 5m) al menos 15 minutos con > 1 req/s  Y  >= 25 muestras en 30m
#     (no dispara de madrugada/mananas de bajo trafico ni tras el arranque nocturno de MOBI-02). Recuperacion: avg(3m) >= 1 req/s.
#     CAMBIA ESTADO en Zabbix de produccion. Rollback al final del bloque (reconstruye la expresion original desde las funciones del snapshot).
# ---------------------------------------------------------------------------
(
set -euo pipefail
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
call(){ jq -n --arg m "$1" --arg k "$ZABBIX_API_KEY" --argjson p "$2" '{jsonrpc:"2.0",method:$m,id:1,auth:$k,params:$p}' \
  | curl -s -X POST $API -H 'Content-Type: application/json-rpc' -d @- > "$3"
  if jq -e '.error' "$3" >/dev/null; then echo "ERROR en $1 (ver $3)"; jq .error "$3"; exit 1; fi; }
H=SFCG-MOBI-02
KEY='perf_counter_en["\Web Service(_Total)\Total Method Requests/Sec", 60]'
call trigger.get '{"triggerids":["26286","26287","26448"],"output":["triggerid","description","expression","recovery_expression","priority","status"],"selectHosts":["host"],"selectFunctions":["functionid","function","parameter"],"selectTags":["tag","value"],"selectDependencies":["triggerid"]}' $D/caida-apply-BEFORE.json
call usermacro.get '{"globalmacro":true,"output":["globalmacroid","macro","value"]}' $D/caida-apply-macros-BEFORE.json
for row in "26286 SFCG-MOBI-01" "26287 SFCG-MOBI-02" "26448 SFCG-MOBI-01"; do
  set -- $row
  jq -e --arg id "$1" --arg h "$2" '.result[]|select(.triggerid==$id and .hosts[0].host==$h and (.description|startswith("Caída brusca")))' $D/caida-apply-BEFORE.json >/dev/null \
    || { echo "GUARDA FALLIDA: trigger $1 no es Caída brusca de $2"; exit 1; }
done
! jq -e '.result[]|select(.macro|startswith("{$MOBI.COLLAPSE."))' $D/caida-apply-macros-BEFORE.json >/dev/null || { echo "ya existen macros {\$MOBI.COLLAPSE.*}, abortando"; exit 1; }
call usermacro.createglobal '[{"macro":"{$MOBI.COLLAPSE.WINDOW}","value":"5m"},{"macro":"{$MOBI.COLLAPSE.ABS}","value":"0.2"},{"macro":"{$MOBI.COLLAPSE.MINVAL}","value":"1"},{"macro":"{$MOBI.COLLAPSE.MINCOUNT}","value":"15"},{"macro":"{$MOBI.COLLAPSE.PRESENT}","value":"25"},{"macro":"{$MOBI.COLLAPSE.RECWIN}","value":"3m"},{"macro":"{$MOBI.COLLAPSE.REC}","value":"1"}]' $D/caida-apply-1-macros.json
name='MOBI-02: request rate under {$MOBI.COLLAPSE.ABS} req/s for {$MOBI.COLLAPSE.WINDOW} (possible Grido WAF block)'
expr="max(/$H/${KEY},{\$MOBI.COLLAPSE.WINDOW})<={\$MOBI.COLLAPSE.ABS} and count(/$H/${KEY},30m:now-5m,\"gt\",{\$MOBI.COLLAPSE.MINVAL})>={\$MOBI.COLLAPSE.MINCOUNT} and count(/$H/${KEY},30m)>={\$MOBI.COLLAPSE.PRESENT}"
rec="avg(/$H/${KEY},{\$MOBI.COLLAPSE.RECWIN})>={\$MOBI.COLLAPSE.REC}"
p=$(jq --arg d "$name" --arg e "$expr" --arg r "$rec" '.result[]|select(.triggerid=="26287")|{triggerid:"26287",description:$d,expression:$e,recovery_expression:$r,priority:"4",tags:((.tags|map(select(.tag!="SVC_FRIENDLYNAME" and ((.tag=="action" and .value=="TELE,GCHAT,MAIL")|not)))+[{"tag":"action","value":"TELE,GCHAT"},{"tag":"scope","value":"GIT-SML-OPE"},{"tag":"SVC_FRIENDLYNAME","value":"Mobile request rate"}])|unique_by([.tag,.value]))}' $D/caida-apply-BEFORE.json)
call trigger.update "$p" $D/caida-apply-2-trigger-26287.json
call trigger.update '{"triggerid":"26286","status":"1"}' $D/caida-apply-3-disable-26286.json
call trigger.update '{"triggerid":"26448","status":"1"}' $D/caida-apply-4-disable-26448.json
call trigger.get '{"triggerids":["26286","26287","26448"],"output":["triggerid","description","priority","status","state","error"],"selectFunctions":["functionid","function","parameter"],"selectTags":["tag","value"]}' $D/caida-apply-AFTER.json
jq -r '.result[]|"\(.triggerid) [\(.priority)] status=\(.status) state=\(.state) err=\(.error) | \(.description) | \([.functions[]|"\(.function)(\(.parameter))"]|join("; "))"' $D/caida-apply-AFTER.json
)

# ROLLBACK de 20: restaura la expresion original de 26287 (reescrita explicita), prioridad/tags/estado, rehabilita 26286 y 26448 y borra las macros {$MOBI.COLLAPSE.*}
(
set -euo pipefail
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
call(){ jq -n --arg m "$1" --arg k "$ZABBIX_API_KEY" --argjson p "$2" '{jsonrpc:"2.0",method:$m,id:1,auth:$k,params:$p}' \
  | curl -s -X POST $API -H 'Content-Type: application/json-rpc' -d @- > "$3"
  if jq -e '.error' "$3" >/dev/null; then echo "ERROR en $1 (ver $3)"; jq .error "$3"; exit 1; fi; }
KEY='perf_counter_en["\Web Service(_Total)\Total Method Requests/Sec", 60]'
# selectFunctions en 6.0.32 devuelve solo functionid y parameter (sin el nombre de la funcion), asi que la expresion original se reescribe explicita
# (estructura tomada del snapshot crudo: {f1}<({f2}*(1-PCT/100)) and {f2}>MINACT ; recuperacion {f3}>OKACT ; f1=min(item,MINACT) f2=avg(item,10m) f3=avg(item,OKTIME))
H=SFCG-MOBI-02
EO="min(/$H/${KEY},{\$DROP.MIN.ACTIVITY:MOBI})<(avg(/$H/${KEY},10m)*(1-{\$DROP.PCT:MOBI}/100)) and avg(/$H/${KEY},10m)>{\$DROP.MIN.ACTIVITY:MOBI}"
RO="avg(/$H/${KEY},{\$DROP.OK.ACTIVITY.TIME:MOBI})>{\$DROP.OK.ACTIVITY:MOBI}"
p=$(jq --arg e "$EO" --arg r "$RO" '.result[]|select(.triggerid=="26287")|{triggerid:"26287",description:.description,expression:$e,recovery_expression:$r,priority:.priority,status:.status,tags:.tags}' $D/caida-apply-BEFORE.json)
call trigger.update "$p" $D/caida-rollback-1-trigger-26287.json
call trigger.update '{"triggerid":"26286","status":"0"}' $D/caida-rollback-2-enable-26286.json
call trigger.update '{"triggerid":"26448","status":"0"}' $D/caida-rollback-3-enable-26448.json
call usermacro.get '{"globalmacro":true,"output":["globalmacroid","macro"]}' $D/caida-rollback-pre-macros.json
NEW=$(jq -c '[.result[]|select(.macro|startswith("{$MOBI.COLLAPSE."))|.globalmacroid]' $D/caida-rollback-pre-macros.json)
call usermacro.deleteglobal "$NEW" $D/caida-rollback-4-delete-macros.json
echo "rollback aplicado"
)

# ---------------------------------------------------------------------------
# 20b. REANUDAR el paso 20 (la primera ejecucion creo las 7 macros {$MOBI.COLLAPSE.*} y se detuvo en un filtro jq invalido, antes de tocar triggers).
#      Reutiliza el snapshot caida-apply-BEFORE.json (valido: ningun trigger cambio) tras verificar que las macros existen y que los triggers siguen intactos.
#      Escribe archivos nuevos (noclobber). CAMBIA ESTADO en Zabbix de produccion. El rollback del paso 20 sigue siendo valido.
# ---------------------------------------------------------------------------
(
set -euo pipefail
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
call(){ jq -n --arg m "$1" --arg k "$ZABBIX_API_KEY" --argjson p "$2" '{jsonrpc:"2.0",method:$m,id:1,auth:$k,params:$p}' \
  | curl -s -X POST $API -H 'Content-Type: application/json-rpc' -d @- > "$3"
  if jq -e '.error' "$3" >/dev/null; then echo "ERROR en $1 (ver $3)"; jq .error "$3"; exit 1; fi; }
H=SFCG-MOBI-02
KEY='perf_counter_en["\Web Service(_Total)\Total Method Requests/Sec", 60]'
[ -s $D/caida-apply-BEFORE.json ] || { echo "falta caida-apply-BEFORE.json"; exit 1; }
call usermacro.get '{"globalmacro":true,"output":["globalmacroid","macro","value"]}' $D/caida-resume-macros.json
[ "$(jq '[.result[]|select(.macro|startswith("{$MOBI.COLLAPSE."))]|length' $D/caida-resume-macros.json)" = "7" ] || { echo "GUARDA FALLIDA: no hay exactamente 7 macros {\$MOBI.COLLAPSE.*}"; exit 1; }
call trigger.get '{"triggerids":["26286","26287","26448"],"output":["triggerid","description","priority","status"],"selectHosts":["host"]}' $D/caida-resume-check.json
for row in "26286 SFCG-MOBI-01" "26287 SFCG-MOBI-02" "26448 SFCG-MOBI-01"; do
  set -- $row
  jq -e --arg id "$1" --arg h "$2" '.result[]|select(.triggerid==$id and .hosts[0].host==$h and .status=="0" and (.description|startswith("Caída brusca")))' $D/caida-resume-check.json >/dev/null \
    || { echo "GUARDA FALLIDA: trigger $1 ya no es Caída brusca habilitado de $2"; exit 1; }
done
name='MOBI-02: request rate under {$MOBI.COLLAPSE.ABS} req/s for {$MOBI.COLLAPSE.WINDOW} (possible Grido WAF block)'
expr="max(/$H/${KEY},{\$MOBI.COLLAPSE.WINDOW})<={\$MOBI.COLLAPSE.ABS} and count(/$H/${KEY},30m:now-5m,\"gt\",{\$MOBI.COLLAPSE.MINVAL})>={\$MOBI.COLLAPSE.MINCOUNT} and count(/$H/${KEY},30m)>={\$MOBI.COLLAPSE.PRESENT}"
rec="avg(/$H/${KEY},{\$MOBI.COLLAPSE.RECWIN})>={\$MOBI.COLLAPSE.REC}"
p=$(jq --arg d "$name" --arg e "$expr" --arg r "$rec" '.result[]|select(.triggerid=="26287")|{triggerid:"26287",description:$d,expression:$e,recovery_expression:$r,priority:"4",tags:((.tags|map(select(.tag!="SVC_FRIENDLYNAME" and ((.tag=="action" and .value=="TELE,GCHAT,MAIL")|not)))+[{"tag":"action","value":"TELE,GCHAT"},{"tag":"scope","value":"GIT-SML-OPE"},{"tag":"SVC_FRIENDLYNAME","value":"Mobile request rate"}])|unique_by([.tag,.value]))}' $D/caida-apply-BEFORE.json)
call trigger.update "$p" $D/caida-apply-2-trigger-26287.json
call trigger.update '{"triggerid":"26286","status":"1"}' $D/caida-apply-3-disable-26286.json
call trigger.update '{"triggerid":"26448","status":"1"}' $D/caida-apply-4-disable-26448.json
call trigger.get '{"triggerids":["26286","26287","26448"],"output":["triggerid","description","priority","status","state","error"],"selectFunctions":["functionid","function","parameter"],"selectTags":["tag","value"]}' $D/caida-apply-AFTER.json
jq -r '.result[]|"\(.triggerid) [\(.priority)] status=\(.status) state=\(.state) err=\(.error) | \(.description) | \([.functions[]|"\(.function)(\(.parameter))"]|join("; "))"' $D/caida-apply-AFTER.json
)

# ---------------------------------------------------------------------------
# 21. Caida brusca a nivel de SERVICIO: item calculado "total del servicio" (MOBI-01 + MOBI-02 solo si MOBI-02 reporta en los ultimos 3m, sin valor viejo)
#     y un trigger nuevo High sobre ese item con el mismo detector (max(5m)<=0.2, >=15 de 30m con >1 req/s, >=25 muestras en 30m; recuperacion avg(3m)>=1).
#     El trigger 26287 (version solo MOBI-02) queda DESHABILITADO (no borrado). El item y el trigger se crean en SFCG-MOBI-01.
#     CAMBIA ESTADO en Zabbix de produccion. Si la API rechaza la formula (operador de comparacion), el bloque aborta antes de crear nada mas.
#     El detector queda silencioso ~35 min tras crear el item (necesita 25 muestras y 15 minutos con trafico).
# ---------------------------------------------------------------------------
(
set -euo pipefail
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
call(){ jq -n --arg m "$1" --arg k "$ZABBIX_API_KEY" --argjson p "$2" '{jsonrpc:"2.0",method:$m,id:1,auth:$k,params:$p}' \
  | curl -s -X POST $API -H 'Content-Type: application/json-rpc' -d @- > "$3"
  if jq -e '.error' "$3" >/dev/null; then echo "ERROR en $1 (ver $3)"; jq .error "$3"; exit 1; fi; }
H1=SFCG-MOBI-01; H2=SFCG-MOBI-02
KEY='perf_counter_en["\Web Service(_Total)\Total Method Requests/Sec", 60]'
SKEY='iis.total.requests.mobis.service'
call host.get "{\"filter\":{\"host\":[\"$H1\"]},\"output\":[\"hostid\",\"host\"]}" $D/svc-host.json
HID=$(jq -r '.result[0].hostid' $D/svc-host.json); [ -n "$HID" ] && [ "$HID" != "null" ] || { echo "no encuentro $H1"; exit 1; }
call item.get "{\"hostids\":[\"$HID\"],\"filter\":{\"key_\":\"$SKEY\"},\"output\":[\"itemid\"]}" $D/svc-item-exists.json
[ "$(jq '.result|length' $D/svc-item-exists.json)" = "0" ] || { echo "ya existe el item $SKEY, abortando"; exit 1; }
call trigger.get '{"triggerids":["26287"],"output":["triggerid","description","priority","status"],"selectHosts":["host"],"selectTags":["tag","value"]}' $D/svc-BEFORE-26287.json
jq -e '.result[]|select(.triggerid=="26287" and .status=="0" and .priority=="4" and (.description|startswith("MOBI-02: request rate under")))' $D/svc-BEFORE-26287.json >/dev/null || { echo "GUARDA FALLIDA: 26287 no es el detector MOBI-02 habilitado"; exit 1; }
FORMULA="last(/$H1/${KEY})+last(/$H2/${KEY})*(count(/$H2/${KEY},3m)>0)"
ip=$(jq -n --arg h "$HID" --arg k "$SKEY" --arg f "$FORMULA" '{hostid:$h,name:"IIS Total Method Requests/sec - MOBI service (MOBI-02 counted only while it reports)",key_:$k,type:15,value_type:0,params:$f,delay:"1m",history:"365d",trends:"730d",units:"req/s",description:"Service total of Total Method Requests/Sec: MOBI-01 plus MOBI-02 when MOBI-02 reported in the last 3 minutes (avoids the stale last() value of the old sum item)."}')
call item.create "$ip" $D/svc-apply-1-item.json
echo "item creado: $(jq -r '.result.itemids[0]' $D/svc-apply-1-item.json)"
name='MOBI service: request rate under {$MOBI.COLLAPSE.ABS} req/s for {$MOBI.COLLAPSE.WINDOW} (possible Grido WAF block)'
expr="max(/$H1/${SKEY},{\$MOBI.COLLAPSE.WINDOW})<={\$MOBI.COLLAPSE.ABS} and count(/$H1/${SKEY},30m:now-5m,\"gt\",{\$MOBI.COLLAPSE.MINVAL})>={\$MOBI.COLLAPSE.MINCOUNT} and count(/$H1/${SKEY},30m)>={\$MOBI.COLLAPSE.PRESENT}"
rec="avg(/$H1/${SKEY},{\$MOBI.COLLAPSE.RECWIN})>={\$MOBI.COLLAPSE.REC}"
tp=$(jq --arg d "$name" --arg e "$expr" --arg r "$rec" '.result[]|select(.triggerid=="26287")|{description:$d,expression:$e,recovery_mode:"1",recovery_expression:$r,priority:"4",tags:((.tags|map(select(.tag!="SVC_FRIENDLYNAME"))+[{"tag":"SVC_FRIENDLYNAME","value":"Mobile service request rate"}])|unique_by([.tag,.value]))}' $D/svc-BEFORE-26287.json)
call trigger.create "$tp" $D/svc-apply-2-trigger.json
echo "trigger creado: $(jq -r '.result.triggerids[0]' $D/svc-apply-2-trigger.json)"
call trigger.update '{"triggerid":"26287","status":"1"}' $D/svc-apply-3-disable-26287.json
NEWT=$(jq -r '.result.triggerids[0]' $D/svc-apply-2-trigger.json)
call trigger.get "{\"triggerids\":[\"$NEWT\",\"26287\"],\"output\":[\"triggerid\",\"description\",\"priority\",\"status\",\"state\",\"error\"],\"selectHosts\":[\"host\"],\"selectTags\":[\"tag\",\"value\"],\"selectFunctions\":[\"functionid\",\"parameter\"]}" $D/svc-apply-AFTER.json
jq -r '.result[]|"\(.triggerid) [\(.priority)] \(.hosts[0].host) status=\(.status) state=\(.state) err=\(.error) | \(.description)"' $D/svc-apply-AFTER.json
call item.get "{\"itemids\":[\"$(jq -r '.result.itemids[0]' $D/svc-apply-1-item.json)\"],\"output\":[\"itemid\",\"name\",\"key_\",\"params\",\"state\",\"error\",\"delay\",\"history\"]}" $D/svc-apply-AFTER-item.json
jq -r '.result[]|"item \(.itemid) state=\(.state) err=\(.error) | \(.params)"' $D/svc-apply-AFTER-item.json
)

# ROLLBACK de 21: borra el trigger y el item nuevos y rehabilita 26287
(
set -euo pipefail
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
call(){ jq -n --arg m "$1" --arg k "$ZABBIX_API_KEY" --argjson p "$2" '{jsonrpc:"2.0",method:$m,id:1,auth:$k,params:$p}' \
  | curl -s -X POST $API -H 'Content-Type: application/json-rpc' -d @- > "$3"
  if jq -e '.error' "$3" >/dev/null; then echo "ERROR en $1 (ver $3)"; jq .error "$3"; exit 1; fi; }
call trigger.update '{"triggerid":"26287","status":"0"}' $D/svc-rollback-1-enable-26287.json
[ -s $D/svc-apply-2-trigger.json ] && call trigger.delete "[\"$(jq -r '.result.triggerids[0]' $D/svc-apply-2-trigger.json)\"]" $D/svc-rollback-2-delete-trigger.json
[ -s $D/svc-apply-1-item.json ] && call item.delete "[\"$(jq -r '.result.itemids[0]' $D/svc-apply-1-item.json)\"]" $D/svc-rollback-3-delete-item.json
echo "rollback aplicado"
)

# ---------------------------------------------------------------------------
# 22. Trigger 26898 (MOBI service collapse): SVC_FRIENDLYNAME y friendlyname = "Mobile request rate" (tarjeta de problema y de recuperacion con el mismo nombre)
#     CAMBIA ESTADO en Zabbix de produccion. Conserva el resto de los tags. Rollback al final del bloque.
# ---------------------------------------------------------------------------
(
set -euo pipefail
NAME='Mobile request rate'
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
call(){ jq -n --arg m "$1" --arg k "$ZABBIX_API_KEY" --argjson p "$2" '{jsonrpc:"2.0",method:$m,id:1,auth:$k,params:$p}' \
  | curl -s -X POST $API -H 'Content-Type: application/json-rpc' -d @- > "$3"
  if jq -e '.error' "$3" >/dev/null; then echo "ERROR en $1 (ver $3)"; jq .error "$3"; exit 1; fi; }
call trigger.get '{"triggerids":["26898"],"output":["triggerid","description"],"selectHosts":["host"],"selectTags":["tag","value"]}' $D/tags22-BEFORE.json
jq -e '.result[]|select(.triggerid=="26898" and .hosts[0].host=="SFCG-MOBI-01" and (.description|startswith("MOBI service: request rate under")))' $D/tags22-BEFORE.json >/dev/null || { echo "GUARDA FALLIDA: 26898 no es el trigger esperado"; exit 1; }
p=$(jq --arg n "$NAME" '.result[]|select(.triggerid=="26898")|{triggerid:"26898",tags:((.tags|map(select(.tag!="SVC_FRIENDLYNAME" and .tag!="friendlyname"))+[{"tag":"SVC_FRIENDLYNAME","value":$n},{"tag":"friendlyname","value":$n}])|unique_by([.tag,.value]))}' $D/tags22-BEFORE.json)
call trigger.update "$p" $D/tags22-apply.json
call trigger.get '{"triggerids":["26898"],"output":["triggerid"],"selectTags":["tag","value"]}' $D/tags22-AFTER.json
jq -r '.result[0].tags|map(select(.tag=="SVC_FRIENDLYNAME" or .tag=="friendlyname")|"\(.tag)=\(.value)")|join("  ")' $D/tags22-AFTER.json
jq -r '"tags totales: \(.result[0].tags|length)"' $D/tags22-AFTER.json
)

# ROLLBACK de 22: restaura los tags desde tags22-BEFORE.json
(
set -euo pipefail
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
p=$(jq '.result[]|select(.triggerid=="26898")|{triggerid:"26898",tags:.tags}' $D/tags22-BEFORE.json)
jq -n --arg k "$ZABBIX_API_KEY" --argjson p "$p" '{jsonrpc:"2.0",method:"trigger.update",id:1,auth:$k,params:$p}' | curl -s -X POST $API -H 'Content-Type: application/json-rpc' -d @- > $D/tags22-rollback.json
jq -e '.error' $D/tags22-rollback.json >/dev/null && { echo "ERROR"; jq .error $D/tags22-rollback.json; exit 1; }
echo "tags restaurados"
)

# ---------------------------------------------------------------------------
# 23. Triggers IIS Spike MOBI (26742-26747): friendlyname = SVC_FRIENDLYNAME = "Mobile Total Requests (req/s)" (tarjetas de problema y recuperacion con el mismo nombre)
#     CAMBIA ESTADO en Zabbix de produccion. Conserva el resto de los tags. Rollback al final del bloque.
# ---------------------------------------------------------------------------
(
set -euo pipefail
NAME='Mobile Total Requests (req/s)'
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
call(){ jq -n --arg m "$1" --arg k "$ZABBIX_API_KEY" --argjson p "$2" '{jsonrpc:"2.0",method:$m,id:1,auth:$k,params:$p}' \
  | curl -s -X POST $API -H 'Content-Type: application/json-rpc' -d @- > "$3"
  if jq -e '.error' "$3" >/dev/null; then echo "ERROR en $1 (ver $3)"; jq .error "$3"; exit 1; fi; }
call trigger.get '{"triggerids":["26742","26743","26744","26745","26746","26747"],"output":["triggerid","description"],"selectHosts":["host"],"selectTags":["tag","value"]}' $D/tags23-BEFORE.json
for row in "26742 SFCG-MOBI-01" "26743 SFCG-MOBI-01" "26744 SFCG-MOBI-01" "26745 SFCG-MOBI-02" "26746 SFCG-MOBI-02" "26747 SFCG-MOBI-02"; do
  set -- $row
  jq -e --arg id "$1" --arg h "$2" '.result[]|select(.triggerid==$id and .hosts[0].host==$h and (.description|startswith("IIS Spike")) and (.tags|any(.tag=="SVC_FRIENDLYNAME")))' $D/tags23-BEFORE.json >/dev/null \
    || { echo "GUARDA FALLIDA: trigger $1 no es IIS Spike de $2 o no tiene SVC_FRIENDLYNAME"; exit 1; }
done
for id in 26742 26743 26744 26745 26746 26747; do
  p=$(jq --arg id "$id" --arg n "$NAME" '.result[]|select(.triggerid==$id)|{triggerid:$id,tags:((.tags|map(select(.tag!="SVC_FRIENDLYNAME" and .tag!="friendlyname"))+[{"tag":"SVC_FRIENDLYNAME","value":$n},{"tag":"friendlyname","value":$n}])|unique_by([.tag,.value]))}' $D/tags23-BEFORE.json)
  call trigger.update "$p" $D/tags23-apply-$id.json
  echo "trigger $id: SVC_FRIENDLYNAME y friendlyname = $NAME"
done
call trigger.get '{"triggerids":["26742","26743","26744","26745","26746","26747"],"output":["triggerid"],"selectTags":["tag","value"]}' $D/tags23-AFTER.json
jq -r '.result[]|"\(.triggerid): tags=\(.tags|length) \(.tags|map(select(.tag=="SVC_FRIENDLYNAME" or .tag=="friendlyname")|"\(.tag)=\(.value)")|join(" | "))"' $D/tags23-AFTER.json
)

# ROLLBACK de 23: restaura los tags desde tags23-BEFORE.json
(
set -euo pipefail
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
for id in 26742 26743 26744 26745 26746 26747; do
  p=$(jq --arg id "$id" '.result[]|select(.triggerid==$id)|{triggerid:$id,tags:.tags}' $D/tags23-BEFORE.json)
  jq -n --arg k "$ZABBIX_API_KEY" --argjson p "$p" '{jsonrpc:"2.0",method:"trigger.update",id:1,auth:$k,params:$p}' | curl -s -X POST $API -H 'Content-Type: application/json-rpc' -d @- > $D/tags23-rollback-$id.json
  jq -e '.error' $D/tags23-rollback-$id.json >/dev/null && { echo "ERROR trigger $id"; exit 1; }
done
echo "tags restaurados"
)

# ---------------------------------------------------------------------------
# 24. Etiquetas mal asignadas en los 7 triggers MOBI en alcance (IIS Spike 26742-26747 y "MOBILE-02 IIS sin datos" 26748):
#     metric: POST Requests -> Total Requests ; service: webservice -> mobile (leen "IIS: Method Total requests per second", ids 52797 / 52755). Conserva el resto de los tags.
#     CAMBIA ESTADO en Zabbix de produccion. Rollback al final del bloque.
# ---------------------------------------------------------------------------
(
set -euo pipefail
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
call(){ jq -n --arg m "$1" --arg k "$ZABBIX_API_KEY" --argjson p "$2" '{jsonrpc:"2.0",method:$m,id:1,auth:$k,params:$p}' \
  | curl -s -X POST $API -H 'Content-Type: application/json-rpc' -d @- > "$3"
  if jq -e '.error' "$3" >/dev/null; then echo "ERROR en $1 (ver $3)"; jq .error "$3"; exit 1; fi; }
call trigger.get '{"triggerids":["26742","26743","26744","26745","26746","26747","26748"],"output":["triggerid","description"],"selectHosts":["host"],"selectTags":["tag","value"]}' $D/tags24-BEFORE.json
for row in "26742 SFCG-MOBI-01" "26743 SFCG-MOBI-01" "26744 SFCG-MOBI-01" "26745 SFCG-MOBI-02" "26746 SFCG-MOBI-02" "26747 SFCG-MOBI-02" "26748 SFCG-MOBI-02"; do
  set -- $row
  jq -e --arg id "$1" --arg h "$2" '.result[]|select(.triggerid==$id and .hosts[0].host==$h and (.tags|any(.tag=="metric" and .value=="POST Requests")) and (.tags|any(.tag=="service" and .value=="webservice")))' $D/tags24-BEFORE.json >/dev/null \
    || { echo "GUARDA FALLIDA: trigger $1 no es de $2 o ya no tiene metric=POST Requests y service=webservice"; exit 1; }
done
for id in 26742 26743 26744 26745 26746 26747 26748; do
  p=$(jq --arg id "$id" '.result[]|select(.triggerid==$id)|{triggerid:$id,tags:(.tags|map(if (.tag=="metric" and .value=="POST Requests") then {"tag":"metric","value":"Total Requests"} elif (.tag=="service" and .value=="webservice") then {"tag":"service","value":"mobile"} else . end)|unique_by([.tag,.value]))}' $D/tags24-BEFORE.json)
  call trigger.update "$p" $D/tags24-apply-$id.json
  echo "trigger $id: metric=Total Requests, service=mobile"
done
call trigger.get '{"triggerids":["26742","26743","26744","26745","26746","26747","26748"],"output":["triggerid"],"selectTags":["tag","value"]}' $D/tags24-AFTER.json
jq -r '.result[]|"\(.triggerid): tags=\(.tags|length) \(.tags|map(select(.tag=="metric" or .tag=="service")|"\(.tag)=\(.value)")|join(" | "))"' $D/tags24-AFTER.json
)

# ROLLBACK de 24: restaura los tags desde tags24-BEFORE.json
(
set -euo pipefail
D=/home/dpaniagua/Documentos/git/bots/operations/events/20261002_zabbix_monthly_alert_review/data
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
for id in 26742 26743 26744 26745 26746 26747 26748; do
  p=$(jq --arg id "$id" '.result[]|select(.triggerid==$id)|{triggerid:$id,tags:.tags}' $D/tags24-BEFORE.json)
  jq -n --arg k "$ZABBIX_API_KEY" --argjson p "$p" '{jsonrpc:"2.0",method:"trigger.update",id:1,auth:$k,params:$p}' | curl -s -X POST $API -H 'Content-Type: application/json-rpc' -d @- > $D/tags24-rollback-$id.json
  jq -e '.error' $D/tags24-rollback-$id.json >/dev/null && { echo "ERROR trigger $id"; exit 1; }
done
echo "tags restaurados"
)

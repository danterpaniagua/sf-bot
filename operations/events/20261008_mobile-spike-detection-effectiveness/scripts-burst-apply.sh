#!/usr/bin/env bash
# Event: 20261008_mobile-spike-detection-effectiveness
# C2 — MODIFICA ZABBIX: crea 2 macros globales y 2 triggers "IIS Spike - Burst" (SFCG-MOBI-01 y SFCG-MOBI-02).
# Nada se modifica si falla una guarda (todas corren antes de la primera escritura).
#   Disparo : last(item) >= {$MOBILE_PCOUNT_BURST:MOBI}                         (por omision 60 req/s)
#   Recupera: max(item, {$MOBILE_PCOUNT_BURST_TIME}) < {$MOBILE_PCOUNT_SPIKE_OK:MOBI}  (5m, y 40 req/s: macro existente)
# Tags: copia exacta de los del trigger 26744 (High), asi enruta igual (accion 7, Operaciones Chat).
# Uso (ZABBIX_API_KEY en el entorno; PRIORITY=2|3|4, BURST, BURST_TIME opcionales):
#   bash <ruta>/scripts-burst-apply.sh > <ruta>/data/burst-apply/apply-log.txt 2>&1
# Reversa: scripts-burst-rollback.sh (usa data/burst-apply/created-ids.json).
set -euo pipefail

: "${ZABBIX_API_KEY:?definir ZABBIX_API_KEY en el entorno}"
URL="http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php"
EV="/home/dpaniagua/Documentos/git/bots/operations/events/20261008_mobile-spike-detection-effectiveness"
OUT="$EV/data/burst-apply"
PRIORITY="${PRIORITY:-3}"; BURST="${BURST:-60}"; BURST_TIME="${BURST_TIME:-5m}"
KEY='perf_counter_en["\Web Service(_Total)\Total Method Requests/Sec", 60]'
ITEMNAME='IIS: Method Total requests per second'
HOSTS='["SFCG-MOBI-01","SFCG-MOBI-02"]'
DESC='IIS Spike - Burst: {$MOBILE_PCOUNT_BURST:MOBI}+ Method Total requests per second in a single sample'

mkdir -p "$OUT"
[ ! -e "$OUT/created-ids.json" ] || { echo "ABORTA: $OUT/created-ids.json ya existe (ya se aplico). Mover los archivos a data/burst-apply/run<N>/ antes de repetir."; exit 1; }
case "$PRIORITY" in 2|3|4) ;; *) echo "ABORTA: PRIORITY debe ser 2, 3 o 4"; exit 1;; esac

zbx() { # zbx <metodo> <params-json>  -> imprime .result o aborta con el error de la API
  jq -n --arg auth "$ZABBIX_API_KEY" --arg m "$1" --argjson p "$2" \
    '{jsonrpc:"2.0",id:1,method:$m,params:$p,auth:$auth}' \
  | curl -sS -H 'Content-Type: application/json-rpc' --data-binary @- "$URL" \
  | jq 'if .error then ("API error: " + (.error|tostring)) | halt_error(1) else .result end'
}
fail() { echo "GUARDA: $*  -> no se modifico nada"; exit 1; }

echo "== guardas (solo lectura)"
hosts=$(zbx host.get "{\"filter\":{\"host\":$HOSTS},\"output\":[\"hostid\",\"host\"]}")
echo "$hosts" > "$OUT/before-hosts.json"
[ "$(jq length <<<"$hosts")" = 2 ] || fail "no encuentro los 2 hosts SFCG-MOBI-01/02"
HOSTIDS=$(jq -c '[.[].hostid]' <<<"$hosts")

items='[]'
for h in $(jq -r '.[]' <<<"$HOSTS"); do
  hid=$(jq -r --arg h "$h" '.[] | select(.host==$h) | .hostid' <<<"$hosts")
  it=$(zbx item.get "$(jq -nc --arg id "$hid" --arg k "$KEY" '{hostids:[$id],filter:{key_:$k},output:["itemid","name","key_","status","value_type"]}')")
  [ "$(jq length <<<"$it")" = 1 ] || fail "$h: el item con la clave esperada no existe o hay mas de uno"
  [ "$(jq -r '.[0].name' <<<"$it")" = "$ITEMNAME" ] || fail "$h: el nombre del item no es '$ITEMNAME'"
  [ "$(jq -r '.[0].status' <<<"$it")" = 0 ] || fail "$h: el item esta deshabilitado"
  items=$(jq -c --argjson a "$items" '$a + .' <<<"$it")
done
echo "$items" > "$OUT/before-items.json"

ref=$(zbx trigger.get '{"triggerids":["26744"],"output":["triggerid","description"],"selectTags":["tag","value"],"selectHosts":["host"]}')
echo "$ref" > "$OUT/before-reference-trigger-26744.json"
[ "$(jq -r '.[0].description // ""' <<<"$ref" | cut -c1-21)" = "IIS Spike - More than" ] || fail "el trigger 26744 no es el High de IIS Spike"
[ "$(jq -r '.[0].hosts[0].host' <<<"$ref")" = "SFCG-MOBI-01" ] || fail "el trigger 26744 no pertenece a SFCG-MOBI-01"
[ "$(jq '.[0].tags | length' <<<"$ref")" -ge 10 ] || fail "el trigger 26744 tiene menos de 10 tags"
TAGS=$(jq -c '[.[0].tags[] | {tag, value}]' <<<"$ref")

exist=$(zbx trigger.get "{\"hostids\":$HOSTIDS,\"search\":{\"description\":\"IIS Spike - Burst\"},\"output\":[\"triggerid\",\"description\"]}")
echo "$exist" > "$OUT/before-existing-burst-triggers.json"
[ "$(jq length <<<"$exist")" = 0 ] || fail "ya existe un trigger 'IIS Spike - Burst' en esos hosts"

gm=$(zbx usermacro.get '{"globalmacro":true,"output":["globalmacroid","macro","value"],"search":{"macro":["MOBILE_PCOUNT_BURST","MOBILE_PCOUNT_SPIKE_OK"]},"searchByAny":true}')
echo "$gm" > "$OUT/before-global-macros.json"
[ "$(jq '[.[] | select(.macro | startswith("{$MOBILE_PCOUNT_BURST"))] | length' <<<"$gm")" = 0 ] || fail "ya existen macros {\$MOBILE_PCOUNT_BURST*}"
[ "$(jq -r '[.[] | select(.macro=="{$MOBILE_PCOUNT_SPIKE_OK:MOBI}")][0].value // ""' <<<"$gm")" = "40" ] || fail "{\$MOBILE_PCOUNT_SPIKE_OK:MOBI} no existe o no vale 40"
echo "guardas OK: hosts=$HOSTIDS prioridad=$PRIORITY umbral=$BURST ventana=$BURST_TIME"

echo "== 1/2 macros globales"
mpayload=$(jq -nc --arg b "$BURST" --arg t "$BURST_TIME" '[
  {macro:"{$MOBILE_PCOUNT_BURST:MOBI}", value:$b, description:"IIS Spike - Burst: umbral de la ultima muestra (req/s) en MOBI"},
  {macro:"{$MOBILE_PCOUNT_BURST_TIME}", value:$t, description:"IIS Spike - Burst: ventana del maximo para recuperar"}]')
mres=$(zbx usermacro.createglobal "$mpayload")
echo "$mres" > "$OUT/created-macros.json"

echo "== 2/2 triggers"
tpayload=$(jq -nc --argjson tags "$TAGS" --arg key "$KEY" --argjson prio "$PRIORITY" --arg desc "$DESC" --argjson hosts "$HOSTS" '
  [ $hosts[] as $h | {
      description: $desc,
      expression: ("last(/" + $h + "/" + $key + ")>={$MOBILE_PCOUNT_BURST:MOBI}"),
      recovery_mode: 1,
      recovery_expression: ("max(/" + $h + "/" + $key + ",{$MOBILE_PCOUNT_BURST_TIME})<{$MOBILE_PCOUNT_SPIKE_OK:MOBI}"),
      priority: $prio, status: 0, manual_close: 0,
      opdata: "Current: {ITEM.LASTVALUE1} req/s",
      comments: "Detector de rafagas (follow-up de GITIN-2156): dispara con una sola muestra por encima del umbral; recupera cuando el maximo de la ventana baja del umbral de recuperacion.",
      tags: $tags } ]')
tres=$(zbx trigger.create "$tpayload")
echo "$tres" > "$OUT/created-triggers.json"
jq -n --argjson t "$tres" --argjson m "$mres" '{triggerids:$t.triggerids, globalmacroids:$m.globalmacroids}' > "$OUT/created-ids.json"

echo "== verificacion (AFTER)"
ids=$(jq -c '.triggerids' "$OUT/created-ids.json")
after=$(zbx trigger.get "{\"triggerids\":$ids,\"output\":[\"triggerid\",\"description\",\"expression\",\"recovery_expression\",\"priority\",\"status\",\"value\",\"state\",\"error\"],\"selectHosts\":[\"host\"],\"selectTags\":[\"tag\",\"value\"]}")
echo "$after" > "$OUT/after-triggers.json"
zbx usermacro.get '{"globalmacro":true,"output":["globalmacroid","macro","value"],"search":{"macro":"MOBILE_PCOUNT_BURST"}}' > "$OUT/after-global-macros.json"
jq -r '.[] | "trigger \(.triggerid) \(.hosts[0].host) prioridad=\(.priority) status=\(.status) valor=\(.value) estado=\(.state) error=[\(.error)] tags=\(.tags|length)"' <<<"$after"
bad=$(jq '[.[] | select(.status!="0" or .state!="0" or .error!="" or (.tags|length)!=12)] | length' <<<"$after")
[ "$bad" = 0 ] && echo "OK: 2 triggers creados, soportados y con los 12 tags" || { echo "ATENCION: $bad trigger(s) con estado no soportado, deshabilitado, con error o tags distintos; revisar y, si hace falta, correr scripts-burst-rollback.sh"; exit 2; }

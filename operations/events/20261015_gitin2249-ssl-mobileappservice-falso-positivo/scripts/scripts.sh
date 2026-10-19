#!/usr/bin/env bash
# GITIN-2249 — SSL MobileAppService falso positivo. Solo lectura sobre Zabbix; cada paso escribe un archivo de evidencia en data/.
EV=/home/dpaniagua/Documentos/git/bots/operations/events/20261015_gitin2249-ssl-mobileappservice-falso-positivo
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
call(){ curl -s -X POST "$API" -H 'Content-Type: application/json' -d "$1"; }

# 1. Historial del item 53392 del 2026-10-14 al 2026-10-15 (UTC-3), history=2 (tipo incorrecto: el item es value_type 3; resultado vacio)
mkdir -p "$EV/data"
curl -s -X POST "$API" -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"history.get","id":1,"auth":"'"$ZABBIX_API_KEY"'","params":{"itemids":["53392"],"history":2,"time_from":'"$(date -d '2026-10-14 00:00 -03' +%s)"',"time_till":'"$(date -d '2026-10-16 00:00 -03' +%s)"',"output":["clock","value"],"sortfield":"clock","sortorder":"ASC","limit":500}}' \
  > "$EV/data/item-53392-history-2026-10-14_15.json"

# 2. Busqueda del item y ultimos 20 valores en los cinco tipos de historial -> history type 3 tiene datos
{
echo "== item.get por key =="
call '{"jsonrpc":"2.0","method":"item.get","id":1,"auth":"'"$ZABBIX_API_KEY"'","params":{"search":{"key_":"ssl_mobileappservice"},"output":["itemid","name","key_","value_type","lastclock","lastvalue","status","state","delay","history"],"selectHosts":["host"]}}'
echo; echo "== item.get itemid 53392 =="
call '{"jsonrpc":"2.0","method":"item.get","id":2,"auth":"'"$ZABBIX_API_KEY"'","params":{"itemids":["53392"],"output":["itemid","name","key_","value_type","lastclock","lastvalue","status","state","delay","history"]}}'
for h in 0 1 2 3 4; do
  echo; echo "== history.get type $h, ultimos 20 sin filtro de tiempo =="
  call '{"jsonrpc":"2.0","method":"history.get","id":3,"auth":"'"$ZABBIX_API_KEY"'","params":{"itemids":["53392"],"history":'$h',"output":["clock","value"],"sortfield":"clock","sortorder":"DESC","limit":20}}'
done
echo
} > "$EV/data/item-53392-lookup-2026-10-18.txt"

# 3. Estado de los 3 triggers SSL de MobileAppService y sus eventos desde 2026-10-14
{
echo "== trigger.get 25914 26282 26284 =="
call '{"jsonrpc":"2.0","method":"trigger.get","id":4,"auth":"'"$ZABBIX_API_KEY"'","params":{"triggerids":["25914","26282","26284"],"output":["triggerid","description","value","lastchange","status","priority","state","error"]}}'
echo; echo "== event.get desde 2026-10-14 =="
call '{"jsonrpc":"2.0","method":"event.get","id":5,"auth":"'"$ZABBIX_API_KEY"'","params":{"objectids":["25914","26282","26284"],"source":0,"object":0,"time_from":'"$(date -d '2026-10-14 00:00 -03' +%s)"',"output":["eventid","objectid","clock","value","r_eventid","acknowledged"],"sortfield":["clock"],"sortorder":"ASC","limit":100}}'
echo; echo "== global macros SSL_CERT *:LE =="
call '{"jsonrpc":"2.0","method":"usermacro.get","id":6,"auth":"'"$ZABBIX_API_KEY"'","params":{"globalmacro":true,"search":{"macro":"SSL_CERT"},"output":["macro","value"]}}'
echo
} > "$EV/data/mobi-ssl-triggers-events-2026-10-18.txt"

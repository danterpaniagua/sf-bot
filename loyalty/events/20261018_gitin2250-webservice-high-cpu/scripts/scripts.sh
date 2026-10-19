#!/usr/bin/env bash
# GITIN-2250 — WebService High CPU (SFCG-WEBS-02). Solo lectura sobre Zabbix; cada paso escribe un archivo de evidencia en data/.
EV=/home/dpaniagua/Documentos/git/bots/loyalty/events/20261018_gitin2250-webservice-high-cpu
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
call(){ curl -s -X POST "$API" -H 'Content-Type: application/json' -d "$1"; }

# 1. Ítems de CPU de SFCG-WEBS-01/02/03 y su historial de las últimas 12 horas
mkdir -p "$EV/data"
T1=$(date +%s); T0=$((T1 - 12*3600))
{
echo "== ventana: $(date -d @$T0 '+%F %T %z') a $(date -d @$T1 '+%F %T %z') =="
ITEMS=$(call '{"jsonrpc":"2.0","method":"item.get","id":1,"auth":"'"$ZABBIX_API_KEY"'","params":{"filter":{"host":["SFCG-WEBS-01","SFCG-WEBS-02","SFCG-WEBS-03"]},"search":{"key_":"system.cpu.util"},"output":["itemid","name","key_","value_type","lastvalue","lastclock","delay"],"selectHosts":["host"]}}')
echo "== items =="; echo "$ITEMS" | jq -c '.result[]'
for id in $(echo "$ITEMS" | jq -r '.result[].itemid'); do
  vt=$(echo "$ITEMS" | jq -r --arg id "$id" '.result[] | select(.itemid==$id) | .value_type')
  echo "== history item $id (value_type $vt) =="
  call '{"jsonrpc":"2.0","method":"history.get","id":2,"auth":"'"$ZABBIX_API_KEY"'","params":{"itemids":["'$id'"],"history":'$vt',"time_from":'$T0',"time_till":'$T1',"output":["clock","value"],"sortfield":"clock","sortorder":"ASC","limit":5000}}' | jq -c '.result[]'
done
} > "$EV/data/cpu-webs-01-02-03-last12h.txt" 2>&1

# 2. Items de peticiones/IIS de SFCG-WEBS-01/02/03 y su historial de las ultimas 6 horas
EV=/home/dpaniagua/Documentos/git/bots/loyalty/events/20261018_gitin2250-webservice-high-cpu
T1=$(date +%s); T0=$((T1 - 6*3600))
{
echo "== ventana: $(date -d @$T0 '+%F %T %z') a $(date -d @$T1 '+%F %T %z') =="
ITEMS=$(call '{"jsonrpc":"2.0","method":"item.get","id":3,"auth":"'"$ZABBIX_API_KEY"'","params":{"filter":{"host":["SFCG-WEBS-01","SFCG-WEBS-02","SFCG-WEBS-03"]},"search":{"name":["Request","IIS","w3wp","Queue","Connections"]},"searchByAny":true,"output":["itemid","name","key_","value_type","lastvalue","delay"],"selectHosts":["host"]}}')
echo "== items =="; echo "$ITEMS" | jq -c '.result[]'
for id in $(echo "$ITEMS" | jq -r '.result[] | select(.value_type=="0" or .value_type=="3") | .itemid'); do
  vt=$(echo "$ITEMS" | jq -r --arg id "$id" '.result[] | select(.itemid==$id) | .value_type')
  echo "== history item $id (value_type $vt) =="
  call '{"jsonrpc":"2.0","method":"history.get","id":4,"auth":"'"$ZABBIX_API_KEY"'","params":{"itemids":["'$id'"],"history":'$vt',"time_from":'$T0',"time_till":'$T1',"output":["clock","value"],"sortfield":"clock","sortorder":"ASC","limit":400}}' | jq -c '.result[]'
done
} > "$EV/data/iis-items-webs-last6h.txt" 2>&1

# 3. Inventario de balanceadores y gateways (solo lectura). Resultado: SFCG-WEBS-LB (reglas, sondeos); la consulta uso backendIpConfigurations (minuscula) y devolvio members:null -> se corrige en el paso 4.
# 4. SFCG-WEBS-LB: pools con sus miembros, a que pool apunta la regla, y disponibilidad por backend (DipAvailability) de las ultimas 6 h
EV=/home/dpaniagua/Documentos/git/bots/loyalty/events/20261018_gitin2250-webservice-high-cpu
SUB=0190fa7d-4ccf-4e3d-beb1-323b5780bfc8
{
echo "== pools =="
az network lb address-pool list --subscription $SUB -g DefaultGroup01 --lb-name SFCG-WEBS-LB -o json
echo "== regla =="
az network lb rule list --subscription $SUB -g DefaultGroup01 --lb-name SFCG-WEBS-LB --query "[].{name:name,pool:backendAddressPool.id,probe:probe.id,idle:idleTimeoutInMinutes,dist:loadDistribution}" -o json
echo "== NICs de las VMs WEBS (IP y pools a los que pertenecen) =="
az network nic list --subscription $SUB --query "[?contains(name,'WEBS')].{nic:name,ips:ipConfigurations[].{ip:privateIPAddress,pools:loadBalancerBackendAddressPools[].id}}" -o json
echo "== DipAvailability por backend, ultimas 6 h (UTC) =="
LBID=$(az network lb show --subscription $SUB -g DefaultGroup01 -n SFCG-WEBS-LB --query id -o tsv)
az monitor metrics list --subscription $SUB --resource "$LBID" --metric DipAvailability --dimension BackendIPAddress --interval PT5M --aggregation Average --start-time "$(date -u -d '-6 hours' +%FT%TZ)" --end-time "$(date -u +%FT%TZ)" -o json
} > "$EV/data/azure-webs-lb-pools-dip-2026-10-18.txt" 2>&1

# 5. WEBS-02: conexiones actuales (51151), POST/s (51166) y CPU (51190) de los ultimos 45 minutos, para ver si el trafico ya se redirigio a los otros dos
EV=/home/dpaniagua/Documentos/git/bots/loyalty/events/20261018_gitin2250-webservice-high-cpu
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
call(){ curl -s -X POST "$API" -H 'Content-Type: application/json' -d "$1"; }
T1=$(date +%s); T0=$((T1 - 45*60))
{
echo "== ventana: $(date -d @$T0 '+%F %T %z') a $(date -d @$T1 '+%F %T %z') =="
for id in 51151 51166 51190; do
  echo "== history item $id =="
  call '{"jsonrpc":"2.0","method":"history.get","id":5,"auth":"'"$ZABBIX_API_KEY"'","params":{"itemids":["'$id'"],"history":0,"time_from":'$T0',"time_till":'$T1',"output":["clock","value"],"sortfield":"clock","sortorder":"ASC","limit":100}}' | jq -c '.result[]'
done
} > "$EV/data/webs02-conn-post-cpu-last45m.txt" 2>&1

# 6. Despues del reinicio de SFCG-WEBS-02: CPU de WEBS-01/02/03 (51092, 51190, 51288) y DipAvailability por backend, ultima hora
EV=/home/dpaniagua/Documentos/git/bots/loyalty/events/20261018_gitin2250-webservice-high-cpu
SUB=0190fa7d-4ccf-4e3d-beb1-323b5780bfc8
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
call(){ curl -s -X POST "$API" -H 'Content-Type: application/json' -d "$1"; }
T1=$(date +%s); T0=$((T1 - 60*60))
{
echo "== ahora: $(date '+%F %T %z') =="
for id in 51092 51190 51288; do
  echo "== Zabbix CPU item $id =="
  call '{"jsonrpc":"2.0","method":"history.get","id":7,"auth":"'"$ZABBIX_API_KEY"'","params":{"itemids":["'$id'"],"history":0,"time_from":'$T0',"time_till":'$T1',"output":["clock","value"],"sortfield":"clock","sortorder":"ASC","limit":100}}' | jq -c '.result[]'
done
echo "== DipAvailability por backend, PT1M, ultima hora (UTC) =="
LBID=$(az network lb show --subscription $SUB -g DefaultGroup01 -n SFCG-WEBS-LB --query id -o tsv)
az monitor metrics list --subscription $SUB --resource "$LBID" --metric DipAvailability --dimension BackendIPAddress --interval PT1M --aggregation Average --start-time "$(date -u -d '-60 minutes' +%FT%TZ)" --end-time "$(date -u +%FT%TZ)" -o json
} > "$EV/data/webs-after-reboot-2026-10-18.txt" 2>&1

# 7. Salud del balanceador ahora (DipAvailability PT1M, ultima hora), IP de las NIC WEBS y dos items de WEBS-02 (51182 ping TCP 8080, 51429 estado del app pool)
EV=/home/dpaniagua/Documentos/git/bots/loyalty/events/20261018_gitin2250-webservice-high-cpu
SUB=0190fa7d-4ccf-4e3d-beb1-323b5780bfc8
API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
call(){ curl -s -X POST "$API" -H 'Content-Type: application/json' -d "$1"; }
T1=$(date +%s); T0=$((T1 - 60*60))
{
echo "== ahora: $(date '+%F %T %z') =="
echo "== NICs WEBS: IP privada =="
az network nic list --subscription $SUB -g DefaultGroup01 --query "[?contains(name,'webs')].{nic:name,ips:ipConfigurations[].privateIPAddress}" -o json
echo "== DipAvailability por backend, PT1M, ultima hora (UTC) =="
LBID=$(az network lb show --subscription $SUB -g DefaultGroup01 -n SFCG-WEBS-LB --query id -o tsv)
az monitor metrics list --subscription $SUB --resource "$LBID" --metric DipAvailability --dimension BackendIPAddress --interval PT1M --aggregation Average --start-time "$(date -u -d '-60 minutes' +%FT%TZ)" --end-time "$(date -u +%FT%TZ)" -o json
for id in 51182 51429; do
  echo "== Zabbix history item $id (WEBS-02: 51182 = ping TCP 8080, 51429 = estado app pool) =="
  call '{"jsonrpc":"2.0","method":"history.get","id":6,"auth":"'"$ZABBIX_API_KEY"'","params":{"itemids":["'$id'"],"history":3,"time_from":'$T0',"time_till":'$T1',"output":["clock","value"],"sortfield":"clock","sortorder":"ASC","limit":100}}' | jq -c '.result[]'
done
} > "$EV/data/webs02-lb-health-now-2026-10-18.txt" 2>&1

# 8. Estado de la VM SFCG-WEBS-02 tras el reinicio (instance view) y ultimo arranque segun la VM
{
echo "== ahora: $(date '+%F %T %z') =="
az vm get-instance-view --subscription $SUB -g DefaultGroup01 -n SFCG-WEBS-02 --query "{statuses:instanceView.statuses[].{code:code,time:time},agent:instanceView.vmAgent.statuses[].{code:code,msg:displayStatus,time:time}}" -o json
az vm run-command invoke --subscription $SUB -g DefaultGroup01 -n SFCG-WEBS-02 --command-id RunPowerShellScript --scripts "\$o=Get-CimInstance Win32_OperatingSystem; \"host=\$env:COMPUTERNAME ahora(UTC)=\$((Get-Date).ToUniversalTime().ToString('MM-dd HH:mm:ss')) arranque(UTC)=\$(\$o.LastBootUpTime.ToUniversalTime().ToString('MM-dd HH:mm:ss')) CPU%=\$((Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter \"Name='_Total'\").PercentProcessorTime)\"" --query "value[].message" -o tsv
} > "$EV/data/webs02-vm-state-after-reboot-2026-10-18.txt" 2>&1

# 9. Triggers de CPU de SFCG-WEBS-02, sus eventos y alertas, y las acciones de Zabbix (solo lectura)
T0=$(date -d '2026-10-18 00:00 -03' +%s)
{
echo "== ahora: $(date '+%F %T %z') =="
TR=$(call '{"jsonrpc":"2.0","method":"trigger.get","id":10,"auth":"'"$ZABBIX_API_KEY"'","params":{"hostids":["10662"],"search":{"description":"CPU"},"output":["triggerid","description","expression","recovery_expression","recovery_mode","priority","status","state","value","lastchange","error"],"selectTags":"extend","selectDependencies":["triggerid","description"],"selectFunctions":["functionid","function","parameter"]}}')
echo "$TR" | jq -c '.result[]'
IDS=$(echo "$TR" | jq -c '[.result[].triggerid]')
EVT=$(call '{"jsonrpc":"2.0","method":"event.get","id":13,"auth":"'"$ZABBIX_API_KEY"'","params":{"objectids":'"$IDS"',"source":0,"object":0,"time_from":'$T0',"output":["eventid","objectid","clock","value","r_eventid","acknowledged"],"sortfield":["clock"],"sortorder":"ASC","limit":100}}')
echo "$EVT" | jq -c '.result[]'
EIDS=$(echo "$EVT" | jq -c '[.result[].eventid]')
call '{"jsonrpc":"2.0","method":"alert.get","id":14,"auth":"'"$ZABBIX_API_KEY"'","params":{"eventids":'"$EIDS"',"output":["alertid","actionid","eventid","clock","status","retries","error","mediatypeid"]}}' | jq -c '.result[]'
call '{"jsonrpc":"2.0","method":"action.get","id":15,"auth":"'"$ZABBIX_API_KEY"'","params":{"output":["actionid","name","status","eventsource"],"selectFilter":["evaltype","formula","conditions"]}}' | jq -c '.result[]'
} > "$EV/data/webs02-alerting-1556.txt" 2>&1

# Ejecuciones remotas con "az vm run-command invoke" (cada una escribio su archivo en data/):
#   scripts/webs02-remote-triage.ps1 -> SFCG-WEBS-02 (data/webs02-remote-triage-2026-10-18.txt; repetido en data/webs-after-reboot-1540.txt)
#   scripts/webs-w3wp-compare.ps1   -> SFCG-WEBS-01/02/03 (data/webs-w3wp-compare-1541.txt)
#   scripts/webs-wmi-probe.ps1      -> SFCG-WEBS-02/03 (data/webs-wmi-probe-1547.txt, mas items WMI de Zabbix)
#   scripts/webs-wmi-cost.ps1       -> SFCG-WEBS-01/02/03 (data/webs-wmi-cost-1549.txt)
# Sin ejecutar: scripts/webs-healthcheck-compare.ps1, scripts/webs02-processes.ps1, y el paso 5 de este archivo.

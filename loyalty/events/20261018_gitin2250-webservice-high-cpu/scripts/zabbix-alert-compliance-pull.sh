#!/usr/bin/env bash
# Read-only pull for the alert-normalizer audit, for ANY Zabbix instance: enabled hosts (with host groups and host tags), monitored triggers with tags,
# trigger actions (conditions and operations), media types (no secrets), user groups. Writes ONE file; analyse it with alert_matrix.py.
# Usage: API=https://your-zabbix/api_jsonrpc.php ZABBIX_API_KEY=... zabbix-alert-compliance-pull.sh <output file>
set -euo pipefail
API=${API:?set API to the instance api_jsonrpc.php URL}
: "${ZABBIX_API_KEY:?ZABBIX_API_KEY not set}"
OUTF=${1:?usage: $0 <output file>}
call(){ curl -s -X POST "$API" -H 'Content-Type: application/json' -d "$1"; }
{
echo "== ahora: $(date '+%F %T %z') api=$(echo "$API" | sed 's|^\(https\?://[^/]*\).*|\1|') =="
echo "== version =="
curl -s -X POST "$API" -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","method":"apiinfo.version","id":0,"params":[]}'; echo
echo "== hosts =="
call '{"jsonrpc":"2.0","method":"host.get","id":1,"auth":"'"$ZABBIX_API_KEY"'","params":{"output":["hostid","host","name","status"],"selectGroups":["name"],"selectTags":["tag","value"]}}' \
  | jq -c '.result[]|{hostid,host,name,status,groups:[.groups[]?.name],tags:[.tags[]?|"\(.tag)=\(.value)"]}'
echo "== triggers (monitored) =="
call '{"jsonrpc":"2.0","method":"trigger.get","id":2,"auth":"'"$ZABBIX_API_KEY"'","params":{"monitored":true,"output":["triggerid","description","priority","status","value"],"selectHosts":["host"],"selectTags":["tag","value"]}}' \
  | jq -c '.result[]|{host:.hosts[0].host,id:.triggerid,p:.priority,st:.status,v:.value,d:.description,tags:[.tags[]|"\(.tag)=\(.value)"]}'
echo "== trigger actions =="
call '{"jsonrpc":"2.0","method":"action.get","id":3,"auth":"'"$ZABBIX_API_KEY"'","params":{"filter":{"eventsource":0},"output":["actionid","name","status"],"selectFilter":["evaltype","formula","conditions"],"selectOperations":["operationtype","opmessage","opmessage_grp","opmessage_usr"]}}' | jq -c '.result[]'
echo "== media types (no secrets) =="
call '{"jsonrpc":"2.0","method":"mediatype.get","id":4,"auth":"'"$ZABBIX_API_KEY"'","params":{"output":["mediatypeid","name","type","status"]}}' | jq -c '.result[]'
} > "$OUTF" 2>&1
echo "wrote $OUTF"

#!/usr/bin/env bash
# GITIN-2324: read-only check after the UI changes. Scenarios (steps), web items (last value), triggers with tags, action 12 filter.
# expandExpression is used on the triggers: the expressions written for this ticket contain no macros, so the expansion hides nothing.
# Usage: API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php ZABBIX_API_KEY=... webscenario-check.sh <output file>
set -euo pipefail
API=${API:?set API}
: "${ZABBIX_API_KEY:?ZABBIX_API_KEY not set}"
OUTF=${1:?usage: $0 <output file>}
call(){ curl -s -X POST "$API" -H 'Content-Type: application/json' -d "$1"; }
{
echo "== ahora: $(date '+%F %T %z') =="
echo "== scenarios (steps) =="
call '{"jsonrpc":"2.0","method":"httptest.get","id":1,"auth":"'"$ZABBIX_API_KEY"'","params":{"output":["httptestid","name","delay","retries","status"],"hostids":"10610","filter":{"name":["[PROD] WebServiceCG","Loyalty Test02","Loyalty PreProd"]},"selectSteps":"extend"}}' \
 | jq -c '.result[]|{httptestid,name,delay,retries,status,steps:(.steps|sort_by(.no|tonumber)|map(select(.name|test("WebServiceCG|Swagger"))|{httpstepid,no,name,url,timeout,status_codes,follow_redirects,retrieve_mode})),n_steps:(.steps|length)}'
echo "== web items: fail/error/rspcode of those scenarios (last value) =="
call '{"jsonrpc":"2.0","method":"item.get","id":2,"auth":"'"$ZABBIX_API_KEY"'","params":{"webitems":true,"hostids":"10610","output":["itemid","key_","lastvalue","lastclock","status","state"],"search":{"key_":["[PROD] WebServiceCG","Loyalty Test02","Loyalty PreProd"]},"searchByAny":true}}' \
 | jq -c '.result[]|select(.key_|test("web.test.fail|web.test.error|WebServiceCG"))|{key_,lastvalue:(.lastvalue|.[0:80]),lastclock:(.lastclock|tonumber|strflocaltime("%F %T")),status,state}'
echo "== triggers on host 10610 with WebServiceCG in the name =="
call '{"jsonrpc":"2.0","method":"trigger.get","id":3,"auth":"'"$ZABBIX_API_KEY"'","params":{"output":["triggerid","description","expression","priority","status","value","state"],"hostids":"10610","search":{"description":"WebServiceCG"},"expandExpression":true,"selectTags":"extend"}}' \
 | jq -c '.result[]'
echo "== action 12 (routing of env=PROD) =="
call '{"jsonrpc":"2.0","method":"action.get","id":4,"auth":"'"$ZABBIX_API_KEY"'","params":{"output":["actionid","name","status","eventsource"],"actionids":"12","selectFilter":"extend"}}' | jq -c '.result[]'
echo "== all enabled trigger actions: name, status, conditions (to see what env=DEV matches) =="
call '{"jsonrpc":"2.0","method":"action.get","id":5,"auth":"'"$ZABBIX_API_KEY"'","params":{"output":["actionid","name","status"],"filter":{"eventsource":"0"},"selectFilter":"extend"}}' \
 | jq -c '.result[]|{actionid,name,status,evaltype:.filter.evaltype,conditions:[.filter.conditions[]|{conditiontype,operator,value,value2}]}'
} > "$OUTF" 2>&1
echo "wrote $OUTF"

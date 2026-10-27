#!/usr/bin/env bash
# GITIN-2324: read-only. Live definition of scenarios 8 (Loyalty Test02) and 9 (Loyalty PreProd) and the triggers hanging on their web items.
# Fields that can carry secrets are only counted, never printed (headers, variables, posts, query_fields).
# Usage: API=http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php ZABBIX_API_KEY=... webscenario-read.sh <output file>
set -euo pipefail
API=${API:?set API}
: "${ZABBIX_API_KEY:?ZABBIX_API_KEY not set}"
OUTF=${1:?usage: $0 <output file>}
call(){ curl -s -X POST "$API" -H 'Content-Type: application/json' -d "$1"; }
{
echo "== ahora: $(date '+%F %T %z') =="
echo "== httptest 8, 9 =="
call '{"jsonrpc":"2.0","method":"httptest.get","id":1,"auth":"'"$ZABBIX_API_KEY"'","params":{"output":["httptestid","name","delay","retries","status"],"httptestids":["8","9"],"selectSteps":"extend"}}' \
 | jq -c '.result[]|{httptestid,name,delay,retries,status,steps:(.steps|sort_by(.no|tonumber)|map({httpstepid,no,name,url,timeout,status_codes,required,follow_redirects,retrieve_mode,n_headers:(.headers|length),n_variables:(.variables|length),n_posts:(.posts|length),n_query:(.query_fields|length)}))}'
echo "== web items of both scenarios with their triggers =="
call '{"jsonrpc":"2.0","method":"item.get","id":2,"auth":"'"$ZABBIX_API_KEY"'","params":{"webitems":true,"hostids":"10610","output":["itemid","key_"],"search":{"key_":["Loyalty Test02","Loyalty PreProd"]},"searchByAny":true,"selectTriggers":["triggerid","description","priority","status"]}}' \
 | jq -c '.result[]|select(.triggers|length>0)|{itemid,key_,triggers}'
echo "== (items without triggers omitted) =="
} > "$OUTF" 2>&1
echo "wrote $OUTF"

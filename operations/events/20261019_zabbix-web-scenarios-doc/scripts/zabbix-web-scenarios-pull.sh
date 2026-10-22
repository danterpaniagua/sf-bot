#!/usr/bin/env bash
# Read-only pull of every Zabbix web scenario (httptest.get with full step definitions) plus the last value of its fail/error web items,
# for the post-deployment documentation of the web scenarios. Writes ONE file.
# Fields that can carry secrets are masked at pull time (the masked file is the only one written to the repo):
#   scenario: http_user, http_password, ssl_key_password, ssl_cert_file, ssl_key_file (deleted); headers, variables (values masked)
#   step: headers, variables, posts, query_fields (values masked); url (userinfo and the value of token/key/secret/pass/pwd/sig/auth query parameters masked)
# Everything else (name, delay, retries, status, status_codes, required, timeout, follow_redirects, retrieve_mode, url host and path) is raw.
# Usage: API=https://your-zabbix/api_jsonrpc.php ZABBIX_API_KEY=... zabbix-web-scenarios-pull.sh <output file>
set -euo pipefail
API=${API:?set API to the instance api_jsonrpc.php URL}
: "${ZABBIX_API_KEY:?ZABBIX_API_KEY not set}"
OUTF=${1:?usage: $0 <output file>}
call(){ curl -s -X POST "$API" -H 'Content-Type: application/json' -d "$1"; }
MASK='
def mask: if type=="array" then map(if type=="object" and has("value") then .value="<masked>" else . end)
          elif type=="string" and length>0 then "<masked \(length) chars>" else . end;
def murl: if type=="string" then sub("//[^/@]*@";"//<masked>@") | gsub("(?i)(?<k>[^?&=]*(token|key|secret|pass|pwd|sig|auth)[^?&=]*)=[^&]*";"\(.k)=<masked>") else . end;
.result[]
| del(.http_user,.http_password,.ssl_key_password,.ssl_cert_file,.ssl_key_file)
| (.headers,.variables) |= mask
| .steps |= map((.headers,.variables,.posts,.query_fields) |= mask | .url |= murl)
'
{
echo "== ahora: $(date '+%F %T %z') api=$(echo "$API" | sed 's|^\(https\?://[^/]*\).*|\1|') =="
echo "== version =="
curl -s -X POST "$API" -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","method":"apiinfo.version","id":0,"params":[]}'; echo
echo "== httptests (secret-bearing fields masked, see header) =="
call '{"jsonrpc":"2.0","method":"httptest.get","id":1,"auth":"'"$ZABBIX_API_KEY"'","params":{"output":"extend","selectSteps":"extend","selectHosts":["hostid","host","name"]}}' | jq -c "$MASK"
echo "== web.test fail/error items (last value) =="
call '{"jsonrpc":"2.0","method":"item.get","id":2,"auth":"'"$ZABBIX_API_KEY"'","params":{"webitems":true,"output":["itemid","hostid","key_","lastvalue","lastclock"],"search":{"key_":["web.test.fail","web.test.error"]},"searchByAny":true,"selectHosts":["host"]}}' \
  | jq -c '.result[]|{host:.hosts[0].host,key_,lastvalue,lastclock}'
} > "$OUTF" 2>&1
echo "wrote $OUTF"

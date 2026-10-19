#!/usr/bin/env bash
# GITIN-2250 — read-only post-apply check (*.get only). Reads back what the 17:29-20:37 applies created:
#  1. 84 CPU/RAM tier triggers: state, error, how many in PROBLEM, tag env:PROD present
#  2. Healthcheck trigger 27018 (raw functions) and V1 triggers 25746/25753: value, state, error
#  3. 14 committed-bytes items (54637-54650): last value, state, error
#  4. disk: trigger prototypes 22495-22497, 22499-22500, 27019 and the triggers they discovered on the 14 prod hosts (count per host, routing tags, PROBLEM)
#  5. alerts since FROM: counts per action and media type, status, errors, and events behind them
# FROM is a UTC epoch; default 2026-10-18 20:28 UTC-3 (time of the env:PROD apply).
set -euo pipefail
API=${API:-http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php}
: "${ZABBIX_API_KEY:?ZABBIX_API_KEY not set}"
FROM=${FROM:-$(date -u -d '2026-10-18 23:28:00' +%s)}
rpc() {
  local r
  r=$(jq -nc --arg m "$1" --argjson p "$2" --arg a "$ZABBIX_API_KEY" '{jsonrpc:"2.0",method:$m,params:$p,id:1,auth:$a}' \
      | curl -s -X POST "$API" -H 'Content-Type: application/json' -d @-)
  if [ "$(jq 'has("error")' <<<"$r")" = true ]; then echo "ERROR $1: $(jq -c .error <<<"$r")" >&2; return 1; fi
  jq -c .result <<<"$r"
}
echo "== now: $(date '+%F %T %z'); alerts from epoch $FROM ($(date -u -d @"$FROM" '+%F %T UTC')) =="
TF='{output:["triggerid","description","value","state","error","lastchange","priority"],selectTags:["tag","value"],selectHosts:["host"]}'
echo "-- 1. tier triggers"
{ rpc trigger.get "$(jq -nc --arg s "CPU utilization above" "$TF + {search:{description:\$s}}")"; rpc trigger.get "$(jq -nc --arg s "Memory committed above" "$TF + {search:{description:\$s}}")"; } | jq -s 'add' > /tmp/gitin2250-tiers.$$.json
jq -c '{n:length,problem:(map(select(.value=="1"))|length),unknown_state:(map(select(.state!="0"))|length),with_error:(map(select(.error!=""))|length),with_envprod:(map(select(.tags|any(.tag=="env" and .value=="PROD")))|length)}' /tmp/gitin2250-tiers.$$.json
jq -c '.[]|select(.value=="1" or .state!="0" or .error!="")|{triggerid,host:.hosts[0].host,d:.description,p:.priority,v:.value,state,error,last:(.lastchange|tonumber|strftime("%F %T UTC"))}' /tmp/gitin2250-tiers.$$.json
rm -f /tmp/gitin2250-tiers.$$.json
echo "-- 2. Healthcheck trigger 27018 (raw) and V1 triggers"
rpc trigger.get '{"triggerids":["27018","25746","25753"],"output":["triggerid","description","expression","recovery_expression","value","state","error","lastchange","priority"],"selectFunctions":"extend","selectTags":["tag","value"]}' \
 | jq -c '.[]|{triggerid,d:.description,expr:.expression,rec:.recovery_expression,v:.value,state,error,last:(.lastchange|tonumber|strftime("%F %T UTC")),fn:[.functions[]|"\(.itemid):\(.function)(\(.parameter))"],tags:(.tags|length)}'
echo "-- 3. committed-bytes items"
rpc item.get '{"search":{"key_":"Committed Bytes In Use"},"output":["itemid","key_","lastvalue","lastclock","state","error"],"selectHosts":["host"]}' \
 | jq -c '.[]|{itemid,host:.hosts[0].host,last:.lastvalue,at:(if .lastclock=="0" then "never" else (.lastclock|tonumber|strftime("%H:%M:%S UTC")) end),state,error}'
echo "-- 4. disk prototypes (template 10351) and discovered triggers on prod hosts"
rpc triggerprototype.get '{"triggerids":["22495","22496","22497","22499","22500","27019"],"output":["triggerid","description","priority"],"selectTags":["tag","value"]}' \
 | jq -c '.[]|{triggerid,d:.description,p:.priority,routed:(.tags|any(.tag=="action" and .value=="GCHAT"))}'
HOSTS=$(rpc host.get '{"filter":{"host":["SFCG-CLUB-01","SFCG-CLUB-02","SFCG-JENKINS-01","SFCG-MOBI-01","SFCG-MOBI-02","SFCG-SMTP-01","SFCG-TO-01","SFCG-WEBS-01","SFCG-WEBS-02","SFCG-WEBS-03","SFCG-WSCG-01","SFCG-WSIT-01","SFCG-WSV2-01","SFCG-WSV2-02"]},"output":["hostid","host"]}')
echo "prod hosts found: $(jq length <<<"$HOSTS")"
DT=$(rpc trigger.get "$(jq -nc --argjson h "$(jq -c '[.[].hostid]' <<<"$HOSTS")" '{hostids:$h,output:["triggerid","description","value","state","error","priority"],selectTags:["tag","value"],selectHosts:["host"],search:{description:"Disk space is"},filter:{status:0}}')")
echo "discovered 'Disk space is ...' triggers: $(jq length <<<"$DT")"
echo "per host (very high / critically low / low, routed with action:GCHAT, in PROBLEM):"
jq -c 'group_by(.hosts[0].host)[]|{host:.[0].hosts[0].host,very_high:(map(select(.description|test("very high")))|length),critical:(map(select(.description|test("critically low")))|length),low:(map(select(.description|test("is low")))|length),routed:(map(select(.tags|any(.tag=="action" and .value=="GCHAT")))|length),problem:(map(select(.value=="1"))|length)}' <<<"$DT"
jq -c '.[]|select(.value=="1")|{host:.hosts[0].host,d:.description,p:.priority}' <<<"$DT"
echo "-- 5. alerts since FROM"
AL=$(rpc alert.get "$(jq -nc --argjson f "$FROM" '{time_from:$f,output:["alertid","eventid","actionid","mediatypeid","status","error","clock"],limit:1000}')")
echo "alerts: $(jq length <<<"$AL") (limit 1000)"
echo "per action / media type / status (status 0 not sent, 1 sent, 2 failed):"
jq -c 'group_by([.actionid,.mediatypeid,.status])[]|{action:.[0].actionid,media:.[0].mediatypeid,status:.[0].status,n:length,with_error:(map(select(.error!=""))|length)}' <<<"$AL"
EIDS=$(jq -c '[.[].eventid]|unique' <<<"$AL")
if [ "$(jq length <<<"$EIDS")" -gt 0 ]; then
  echo "events behind the alerts:"
  rpc event.get "$(jq -nc --argjson e "$EIDS" '{eventids:$e,output:["eventid","name","clock","severity","value"],selectHosts:["host"]}')" | jq -c '.[]|{eventid,at:(.clock|tonumber|strftime("%H:%M:%S UTC")),host:.hosts[0].host,n:.name,sev:.severity}' | head -60
  echo "alerts per event (duplicates between actions 7 and 12 show as >1 per media type):"
  jq -c 'group_by(.eventid)[]|{eventid:.[0].eventid,n:length,by:(group_by(.actionid)|map("\(.[0].actionid):\(length)")|join(","))}' <<<"$AL" | head -60
fi

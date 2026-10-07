#!/usr/bin/env bash
# Event: 20260824_mobile_iis_spike_detection
# Zabbix API: sf-monitoreo.smartfran.com:8080, auth via $ZABBIX_API_KEY
# Commands are grouped by phase: Investigation / Audit / Remediation
# ⚠️ ACTION commands are clearly marked

# === INVESTIGATION ===

# C1 — resolve host "Mobile" name/id (technical + visible name)
curl -sS -X POST "http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php" \
  -H 'Content-Type: application/json-rpc' \
  -d '{
    "jsonrpc": "2.0",
    "method": "host.get",
    "params": {
      "output": ["hostid", "host", "name"],
      "search": {"host": "Mobile", "name": "Mobile"},
      "searchByAny": true
    },
    "auth": "'"$ZABBIX_API_KEY"'",
    "id": 1
  }'

# C2 — find existing "IIS Method Total requests per second" triggers fleet-wide
curl -sS -X POST "http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php" \
  -H 'Content-Type: application/json-rpc' \
  -d '{
    "jsonrpc": "2.0",
    "method": "trigger.get",
    "params": {
      "output": "extend",
      "search": {"description": "Method Total requests per second"},
      "selectHosts": ["hostid", "host"],
      "selectItems": ["itemid", "key_", "name", "value_type", "delay"]
    },
    "auth": "'"$ZABBIX_API_KEY"'",
    "id": 1
  }'

# C3 — decode Mobile 02's real trigger expressions (function refs -> resolved)
curl -sS -X POST "http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php" \
  -H 'Content-Type: application/json-rpc' \
  -d '{
    "jsonrpc": "2.0",
    "method": "trigger.get",
    "params": {
      "output": "extend",
      "expandExpression": true,
      "triggerids": ["26136", "26137", "26138"],
      "selectHosts": ["host"]
    },
    "auth": "'"$ZABBIX_API_KEY"'",
    "id": 1
  }'

# C4 — check host-level macro overrides for Mobile 02 (came back empty -> global macros)
curl -sS -X POST "http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php" \
  -H 'Content-Type: application/json-rpc' \
  -d '{
    "jsonrpc": "2.0",
    "method": "usermacro.get",
    "params": {
      "output": "extend",
      "hostids": ["10660"],
      "search": {"macro": "PERF_COUNT_TRIG"}
    },
    "auth": "'"$ZABBIX_API_KEY"'",
    "id": 1
  }'

# C5 — confirm template linkage for both Mobile hosts
curl -sS -X POST "http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php" \
  -H 'Content-Type: application/json-rpc' \
  -d '{
    "jsonrpc": "2.0",
    "method": "host.get",
    "params": {
      "output": ["hostid", "host"],
      "hostids": ["10659", "10660"],
      "selectParentTemplates": ["templateid", "host"],
      "selectMacros": "extend"
    },
    "auth": "'"$ZABBIX_API_KEY"'",
    "id": 1
  }'

# C6 — pull 14 days of history, Mobile 02 (itemid 52755)
curl -sS -X POST "http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php" \
  -H 'Content-Type: application/json-rpc' \
  -d '{
    "jsonrpc": "2.0",
    "method": "history.get",
    "params": {
      "output": "extend",
      "history": 0,
      "itemids": ["52755"],
      "time_from": '"$(date -d '14 days ago' +%s)"',
      "sortfield": "clock",
      "sortorder": "ASC"
    },
    "auth": "'"$ZABBIX_API_KEY"'",
    "id": 1
  }'

# C7 — pull 14 days of history, Mobile 01 (itemid 52797)
curl -sS -X POST "http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php" \
  -H 'Content-Type: application/json-rpc' \
  -d '{
    "jsonrpc": "2.0",
    "method": "history.get",
    "params": {
      "output": "extend",
      "history": 0,
      "itemids": ["52797"],
      "time_from": '"$(date -d '14 days ago' +%s)"',
      "sortfield": "clock",
      "sortorder": "ASC"
    },
    "auth": "'"$ZABBIX_API_KEY"'",
    "id": 1
  }'
# Local analysis of C6/C7 output: percentiles (p50/p90/p95/p99/p99.9), rolling
# 2m/3m/5m averages, and gap-duration detection between consecutive samples —
# done with a local Python one-liner against the saved JSON, not a Zabbix API call.

# === AUDIT ===

# C8 — pull tags from the reference "IIS More than {AVERAGE}..." trigger
# (fleet-wide reference to determine which tag set the new triggers need)
curl -sS -X POST "http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php" \
  -H 'Content-Type: application/json-rpc' \
  -d '{
    "jsonrpc": "2.0",
    "method": "trigger.get",
    "params": {
      "output": ["triggerid", "description", "priority"],
      "search": {"description": "IIS More than {$PERF_COUNT_TRIG_AVERAGE} Method Total requests per second for {$PERF_COUNT_TRIG_TIME_NOK}"},
      "selectHosts": ["host"],
      "selectTags": "extend"
    },
    "auth": "'"$ZABBIX_API_KEY"'",
    "id": 1
  }'

# C9 — list all trigger actions to confirm which one actually routes on this tag set
curl -sS -X POST "http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php" \
  -H 'Content-Type: application/json-rpc' \
  -d '{
    "jsonrpc": "2.0",
    "method": "action.get",
    "params": {
      "output": "extend",
      "selectFilter": "extend",
      "selectOperations": "extend"
    },
    "auth": "'"$ZABBIX_API_KEY"'",
    "id": 1
  }'

# === REMEDIATION (frontend / manual) ===

# The following were created manually via Data collection -> Hosts -> Macros/Triggers
# in the Zabbix UI, not scripted: 11 global macros (MOBILE_PCOUNT_SPIKE_* family +
# MOBILE_PCOUNT_NODATA_WINDOW:MOBI02), 3 Spike triggers on SFCG-MOBI-01 (triggerids
# 26742-26744), 3 Spike triggers on SFCG-MOBI-02 (26745-26747), 1 nodata trigger on
# SFCG-MOBI-02 (26748), plus the trigger dependency chains on all 7.

# ⚠️ C10 — apply routing tags (matching C8's tag set) to all 7 new triggers
TAGS='[
  {"tag":"cloud","value":"Azure"},
  {"tag":"component","value":"IIS"},
  {"tag":"env","value":"PROD"},
  {"tag":"friendlyname","value":"Performance Counters Total Request"},
  {"tag":"metric","value":"POST Requests"},
  {"tag":"service","value":"webservice"},
  {"tag":"type","value":"API"},
  {"tag":"action","value":"TELE,GCHAT,MAIL"},
  {"tag":"service_group","value":"LOYALTY"},
  {"tag":"scope","value":"OPE"}
]'

for TID in 26742 26743 26744 26745 26746 26747 26748; do
  curl -sS -X POST "http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php" \
    -H 'Content-Type: application/json-rpc' \
    -d '{
      "jsonrpc": "2.0",
      "method": "trigger.update",
      "params": {
        "triggerid": "'"$TID"'",
        "tags": '"$TAGS"'
      },
      "auth": "'"$ZABBIX_API_KEY"'",
      "id": 1
    }'
done

# C11 — confirm all 7 triggers carry the full tag set
curl -sS -X POST "http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php" \
  -H 'Content-Type: application/json-rpc' \
  -d '{
    "jsonrpc": "2.0",
    "method": "trigger.get",
    "params": {
      "output": ["triggerid", "description"],
      "triggerids": ["26742","26743","26744","26745","26746","26747","26748"],
      "selectTags": "extend"
    },
    "auth": "'"$ZABBIX_API_KEY"'",
    "id": 1
  }'

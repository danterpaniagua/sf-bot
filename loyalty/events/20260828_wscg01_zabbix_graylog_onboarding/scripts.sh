# GITIN-1961 — SFCG-WSCG-01 Zabbix inventory/validation queries
# Endpoint/auth per ope-zabbix skill: http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php,
# token passed inside the JSON-RPC body as "auth" (6.0.32 predates the Bearer-header method).

EVENTDIR="loyalty/events/20260828_wscg01_zabbix_graylog_onboarding"

# 1) Host record — proxy assignment, interfaces, macros
curl -s http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0",
    "method": "host.get",
    "params": {
      "output": ["hostid","host","status","proxy_hostid"],
      "selectInterfaces": "extend",
      "selectMacros": "extend",
      "filter": {"host": ["SFCG-WSCG-01"]}
    },
    "auth": "'"$ZABBIX_API_KEY"'",
    "id": 1
  }' | jq . > "$EVENTDIR/wscg01-host.json"

# 2) All triggers on the host — severity, status, tags
curl -s http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0",
    "method": "trigger.get",
    "params": {
      "output": ["triggerid","description","priority","status"],
      "selectTags": "extend",
      "host": "SFCG-WSCG-01",
      "sortfield": "priority",
      "sortorder": "DESC"
    },
    "auth": "'"$ZABBIX_API_KEY"'",
    "id": 2
  }' | jq . > "$EVENTDIR/wscg01-triggers.json"

# 3) Items with last values
curl -s http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0",
    "method": "item.get",
    "params": {
      "output": ["itemid","name","key_","lastvalue","lastclock","status"],
      "host": "SFCG-WSCG-01",
      "sortfield": "name"
    },
    "auth": "'"$ZABBIX_API_KEY"'",
    "id": 3
  }' | jq . > "$EVENTDIR/wscg01-items.json"

# 4) Which alert actions are actually enabled right now
curl -s http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0",
    "method": "action.get",
    "params": {
      "output": "extend",
      "selectFilter": "extend",
      "selectOperations": "extend"
    },
    "auth": "'"$ZABBIX_API_KEY"'",
    "id": 4
  }' | jq . > "$EVENTDIR/zabbix-actions.json"

# 5) SSL item lookup on SFCG-WSCG-01 (confirmed empty — cert monitoring lives on
#    the Zabbix server host instead, see docs/infrastructure.md)
curl -s http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0",
    "method": "item.get",
    "params": {
      "output": ["itemid","name","key_","lastvalue","lastclock","status"],
      "host": "SFCG-WSCG-01",
      "search": {"key_": "get_ssl_enddate_webservicecg"},
      "selectTriggers": ["triggerid","description","priority","status"]
    },
    "auth": "'"$ZABBIX_API_KEY"'",
    "id": 5
  }' | jq . > "$EVENTDIR/wscg01-ssl-item.json"

# 6) Diagnostics for the never-collected GET/POST rate items (54599/54600) —
#    state/error field, to see the exact Zabbix-reported failure class
#    (mirrors the "does not exist" -> "not enough data" -> real-value
#    progression documented in GITIN-1956 for SFCG-WSV2-02)
curl -s http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0",
    "method": "item.get",
    "params": {
      "output": ["itemid","name","key_","lastvalue","lastclock","status","state","error"],
      "itemids": ["54599","54600"]
    },
    "auth": "'"$ZABBIX_API_KEY"'",
    "id": 6
  }' | jq . > "$EVENTDIR/wscg01-getpost-item-state.json"

# 7) Sibling host reference — SFCG-WSV2-01's equivalent GET/POST items and any
#    trigger(s) attached to them, to clone the correct config once we know
#    what SFCG-WSCG-01 actually needs
curl -s http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0",
    "method": "item.get",
    "params": {
      "output": ["itemid","name","key_","lastvalue","lastclock","status","state","error","delay","tags"],
      "host": "SFCG-WSV2-01",
      "search": {"name": "Requests per second"},
      "selectTriggers": ["triggerid","description","priority","status","expression","tags"]
    },
    "auth": "'"$ZABBIX_API_KEY"'",
    "id": 7
  }' | jq . > "$EVENTDIR/wsv2-01-getpost-reference.json"

# 8) Full trigger definitions (resolved expression syntax, tags, dependencies)
#    for the 3-tier Method Total requests/sec trigger on SFCG-WSV2-01 — needed
#    to clone onto SFCG-WSCG-01's equivalent _Total item (itemid 53770), which
#    has zero triggers despite the item collecting fine
curl -s http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0",
    "method": "trigger.get",
    "params": {
      "output": "extend",
      "selectTags": "extend",
      "selectDependencies": "extend",
      "triggerids": ["26139","26140","26141"]
    },
    "auth": "'"$ZABBIX_API_KEY"'",
    "id": 8
  }' | jq . > "$EVENTDIR/wsv2-01-total-requests-triggers-full.json"

# 9) Global macro contexts for PERF_COUNT_TRIG_* — check whether WEBSCG01
#    already has values, and what sibling services (e.g. WEBSV201) use as
#    a reference for sane thresholds
curl -s http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0",
    "method": "usermacro.get",
    "params": {
      "output": "extend",
      "globalmacro": true,
      "search": {"macro": "PERF_COUNT_TRIG"},
      "searchWildcardsEnabled": true
    },
    "auth": "'"$ZABBIX_API_KEY"'",
    "id": 9
  }' | jq . > "$EVENTDIR/perf-count-trig-global-macros.json"

# 10) SFCG-WSV2-01 host-level macros + its linked templates (with each
#     template's own macros) — PERF_COUNT_TRIG_* isn't a global macro, so it
#     must live at host or template level; need to find which and confirm the
#     WEBSCG01 context convention
curl -s http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0",
    "method": "host.get",
    "params": {
      "output": ["hostid","host"],
      "selectMacros": "extend",
      "selectParentTemplates": ["templateid","name"],
      "filter": {"host": ["SFCG-WSV2-01"]}
    },
    "auth": "'"$ZABBIX_API_KEY"'",
    "id": 10
  }' | jq . > "$EVENTDIR/wsv2-01-host-macros-templates.json"

# 11) Template-level macros for "IIS by Zabbix agent active" (templateid
#     10326) — PERF_COUNT_TRIG_* isn't global or host-level, so it must be
#     defined here (or on a parent template this one links from)
curl -s http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0",
    "method": "template.get",
    "params": {
      "output": ["templateid","name"],
      "selectMacros": "extend",
      "selectParentTemplates": ["templateid","name"],
      "templateids": ["10326"]
    },
    "auth": "'"$ZABBIX_API_KEY"'",
    "id": 11
  }' | jq . > "$EVENTDIR/iis-template-macros.json"

# 19) ALL trigger tags, instance-wide (not filtered to one host) — to review
#     tag usage/efficiency against the actions in zabbix-actions.json
curl -s http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0",
    "method": "trigger.get",
    "params": {
      "output": ["triggerid","description","priority","status"],
      "selectTags": "extend",
      "selectHosts": ["host"],
      "sortfield": "priority",
      "sortorder": "DESC"
    },
    "auth": "'"$ZABBIX_API_KEY"'",
    "id": 19
  }' | jq . > "$EVENTDIR/all-trigger-tags.json"

# 20) ALL host-level tags, instance-wide — host tags also propagate into
#     event tags for action matching, not just trigger-level tags
curl -s http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0",
    "method": "host.get",
    "params": {
      "output": ["hostid","host"],
      "selectTags": "extend"
    },
    "auth": "'"$ZABBIX_API_KEY"'",
    "id": 20
  }' | jq . > "$EVENTDIR/all-host-tags.json"

# 19b) ALL trigger tags, real monitored hosts only (excludes template-level
#      triggers, which polluted query 19 with hundreds of stock vendor
#      templates' default tags)
curl -s http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0",
    "method": "trigger.get",
    "params": {
      "output": ["triggerid","description","priority","status"],
      "selectTags": "extend",
      "selectHosts": ["host"],
      "monitored": true,
      "sortfield": "priority",
      "sortorder": "DESC"
    },
    "auth": "'"$ZABBIX_API_KEY"'",
    "id": 21
  }' | jq . > "$EVENTDIR/all-trigger-tags-real-hosts.json"

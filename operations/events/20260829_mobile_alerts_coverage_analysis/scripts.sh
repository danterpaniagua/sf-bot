#!/bin/bash
# GITIN-1965 — MobileAppService Req/s traffic-baseline analysis
# Zabbix API: http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php
# Auth token passed in JSON body (6.0.32 predates Bearer header support)
# Hostids known from GITIN-1918: SFCG-MOBI-01=10659, SFCG-MOBI-02=10660
#
# NOTE on provenance: the GET/POST weekend data actually analyzed here was
# originally fetched via two now-retired scripts (fetch_weekend_get_post.sh,
# fetch_today_get_post.sh — both executed for real against live Zabbix,
# output confirmed). Those were later refactored into the single dynamic
# fetch_get_post_weeks.sh (C4 below) for maintainability; analyze_weekend_get_post.py
# was verified to reproduce identical numbers against the already-fetched data,
# but fetch_get_post_weeks.sh itself has NOT yet been run end-to-end against
# live Zabbix — flagged as a pending action, not claimed as executed.
#
# Also note: trigger.get/action.get fleet-wide inventory was NOT run in this
# session. The GITIN-1918-routing and threshold-gap conclusions below were
# cross-referenced from docs/zabbix_observability.md (GITIN-1961/GITIN-1966
# audit, a different ticket's session) — a legitimate source, but distinct
# from a command actually run here.

# C1 — full item inventory for both Mobile hosts (which template metrics are actually enabled)
curl -s -X POST http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php \
  -H 'Content-Type: application/json-rpc' \
  -d '{
    "jsonrpc": "2.0",
    "method": "item.get",
    "params": {
      "output": ["itemid", "hostid", "name", "key_", "status", "value_type", "delay"],
      "hostids": ["10659", "10660"],
      "sortfield": "name"
    },
    "auth": "'"$ZABBIX_API_KEY"'",
    "id": 2
  }' | python3 -m json.tool
# OUTPUT (2026-08-29): saved to data/c2_all_items.json. Found the GET/POST "_Total"-instance
# pair used below (52784/52792 Mobi01, 52742/52750 Mobi02), a duplicate newer pair on
# {$IIS.APP.NAME} instance (53257-53260, visibility-only per GITIN-1966), two custom
# aggregate items (53249/53250, 53735), and the CPU/RAM utilization items used in C5-C7.

# C2 — confirm History storage period on the GET/POST items before relying on now-Nw lookups
curl -s -X POST http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php \
  -H 'Content-Type: application/json-rpc' \
  -d '{
    "jsonrpc": "2.0",
    "method": "item.get",
    "params": {
      "output": ["itemid", "hostid", "name", "history", "trends"],
      "itemids": ["52784", "52792", "52742", "52750"]
    },
    "auth": "'"$ZABBIX_API_KEY"'",
    "id": 7
  }' | python3 -m json.tool
# OUTPUT (2026-08-31): all 4 at history=180d, trends=730d — comfortably covers any
# now-Nw lookup within a ~6 month window.

# C3 — analyze_weekend_get_post.py (script, executed repeatedly against the fetched
# GET/POST weekend data): summarizes all data/*_mobi01_get.json weekends found on disk
# (auto-discovered, most recent = "now" vs. the rest as baseline). Outputs: per-host/
# per-metric percentiles, per-service (Mobi01+Mobi02 combined) totals for PM-level
# reporting, and an hour-by-hour Sat/Sun breakdown (local UTC-3).
# Usage: python3 analyze_weekend_get_post.py

# C4 — fetch_get_post_weeks.sh (script, WRITTEN but NOT YET RUN against live Zabbix
# in this session — see provenance note above): dynamic weekend GET/POST history
# puller. Computes the most recent Saturday relative to "now" and pulls it plus N
# prior weekends (default 3), no hardcoded dates. Next data refresh will be its
# first real execution.
# Usage: ./fetch_get_post_weeks.sh [weeks_back]

# C5 — check History storage period on CPU/RAM utilization items
curl -s -X POST http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php \
  -H 'Content-Type: application/json-rpc' \
  -d '{
    "jsonrpc": "2.0",
    "method": "item.get",
    "params": {
      "output": ["itemid", "hostid", "name", "history", "trends"],
      "itemids": ["50609", "50665", "50616", "50672"]
    },
    "auth": "'"$ZABBIX_API_KEY"'",
    "id": 8
  }' | python3 -m json.tool
# OUTPUT (2026-08-31): all 4 at history=7d, trends=365d (CPU util 50609/50665, Memory
# util 50616/50672) — inconsistent with GET/POST's 180d on the same hosts.

# C6 — ⚠️ ACTION: raise CPU/RAM history retention from 7d to 180d, matching GET/POST.
# Same 1m polling interval on all 4 items, so this is the same order-of-magnitude
# storage increase already accepted for the GET/POST pair, not a new tier.
curl -s -X POST http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php \
  -H 'Content-Type: application/json-rpc' \
  -d '{
    "jsonrpc": "2.0",
    "method": "item.update",
    "params": [
      {"itemid": "50609", "history": "180d"},
      {"itemid": "50616", "history": "180d"},
      {"itemid": "50665", "history": "180d"},
      {"itemid": "50672", "history": "180d"}
    ],
    "auth": "'"$ZABBIX_API_KEY"'",
    "id": 9
  }' | python3 -m json.tool
# OUTPUT (2026-08-31): {"result":{"itemids":["50609","50616","50665","50672"]}} — applied.

# C7 — verify C6 took effect
curl -s -X POST http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php \
  -H 'Content-Type: application/json-rpc' \
  -d '{
    "jsonrpc": "2.0",
    "method": "item.get",
    "params": {
      "output": ["itemid", "hostid", "name", "history", "trends"],
      "itemids": ["50609", "50616", "50665", "50672"]
    },
    "auth": "'"$ZABBIX_API_KEY"'",
    "id": 10
  }' | python3 -m json.tool
# OUTPUT (2026-08-31): all 4 now history=180d, trends=365d — confirmed applied.

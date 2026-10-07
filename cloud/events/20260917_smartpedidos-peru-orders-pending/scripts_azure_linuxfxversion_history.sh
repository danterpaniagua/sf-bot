#!/usr/bin/env bash
# Event: 20260917_smartpedidos-peru-orders-pending (GITIN-2068)
# Corrected after the first attempt returned unfiltered raw activity-log
# entries (including identity claims for gastona@smartfran.com -- that file
# was deleted, never committed). This version projects ONLY 4 safe fields
# at the query level -- structurally cannot include "claims" regardless of
# whether the row-filter part works -- then filters for Orders-PRO locally.

# C20 — safe projection only, no row filter (avoids the silent-fallback
# issue from the first attempt)
az monitor activity-log list \
  --resource-group SmartFran.Cloud.PRO \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --start-time 2026-08-18T00:00:00Z \
  --end-time 2026-09-17T23:59:59Z \
  --query "[].{time:eventTimestamp, operation:operationName.localizedValue, caller:caller, resourceId:resourceId, status:status.localizedValue}" \
  -o json \
  > data/orders_pro_activity_log_30d_raw.json

# C20b — local filter for Orders-PRO specifically, on the already-safe file
python3 -c "
import json
with open('data/orders_pro_activity_log_30d_raw.json') as f:
    entries = json.load(f)
filtered = [e for e in entries if 'smartfran-cloud-orders-pro' in (e.get('resourceId') or '').lower() and '/slots/' not in (e.get('resourceId') or '').lower()]
with open('data/orders_pro_activity_log_30d.json', 'w') as f:
    json.dump(filtered, f, indent=2)
print(f'{len(filtered)} matching entries written to data/orders_pro_activity_log_30d.json')
"

# C20c — the raw (unfiltered but claims-free) file is no longer needed once
# the filtered one is confirmed good -- remove it
rm -f data/orders_pro_activity_log_30d_raw.json

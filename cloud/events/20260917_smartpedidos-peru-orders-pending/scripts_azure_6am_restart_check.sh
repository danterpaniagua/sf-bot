#!/usr/bin/env bash
# Event: 20260917_smartpedidos-peru-orders-pending (GITIN-2068)
# Checking for a restart (not a code deploy) around 06:00 ART today --
# would not appear in deployment history, only the Activity Log. Reusing
# the safe two-step pattern (projection-only query, then local filter) to
# avoid pulling identity claims again.

az monitor activity-log list \
  --resource-group SmartFran.Cloud.PRO \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --start-time 2026-09-17T00:00:00Z \
  --end-time 2026-09-17T23:59:59Z \
  --query "[].{time:eventTimestamp, operation:operationName.localizedValue, caller:caller, resourceId:resourceId, status:status.localizedValue}" \
  -o json \
  > data/orders_pro_today_raw.json

python3 -c "
import json
with open('data/orders_pro_today_raw.json') as f:
    entries = json.load(f)
filtered = [e for e in entries if 'smartfran-cloud-orders-pro' in (e.get('resourceId') or '').lower()]
filtered.sort(key=lambda e: e.get('time') or '')
with open('data/orders_pro_today_all_ops.json', 'w') as f:
    json.dump(filtered, f, indent=2)
print(f'{len(filtered)} entries today for Orders-PRO (any slot)')
for e in filtered:
    print(e['time'], '|', e['operation'], '|', e.get('caller'), '|', e['status'])
"

rm -f data/orders_pro_today_raw.json

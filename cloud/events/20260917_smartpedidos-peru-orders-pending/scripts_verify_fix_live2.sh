#!/usr/bin/env bash
# Event: 20260917_smartpedidos-peru-orders-pending (GITIN-2068)
# Checking for a stg2 deploy or swap AFTER the fix commits landed
# (15:50-15:59 ART today) that we may have missed in earlier checks (which
# predated the fix merge).

# C24 — stg2 slot deployment history, fresh pull
az webapp log deployment list \
  --name SmartFran-Cloud-Orders-PRO \
  --slot stg2 \
  --resource-group SmartFran.Cloud.PRO \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --query "[].{start:start_time, end:end_time, deployer:deployer, active:active}" \
  -o json \
  > data/orders_pro_stg2_fresh.json

# C25 — any swap operation, whole RG, for the rest of today (from 15:45 ART
# = 18:45 UTC onward), by raw operation ID
az monitor activity-log list \
  --resource-group SmartFran.Cloud.PRO \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --start-time 2026-09-17T18:45:00Z \
  --end-time 2026-09-17T23:59:59Z \
  --query "[].{time:eventTimestamp, operation:operationName.value, resourceId:resourceId, status:status.localizedValue}" \
  -o json \
  > data/rg_late_raw.json

python3 -c "
import json
with open('data/rg_late_raw.json') as f:
    entries = json.load(f)
swaps = [e for e in entries if 'swap' in (e.get('operation') or '').lower() and 'orders' in (e.get('resourceId') or '').lower()]
swaps.sort(key=lambda e: e.get('time') or '')
print(f'{len(swaps)} Orders-related swap entries after 18:45 UTC')
for e in swaps:
    print(e['time'], '|', e['operation'], '|', e['status'])
"
rm -f data/rg_late_raw.json

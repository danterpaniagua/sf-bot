#!/usr/bin/env bash
# Event: 20260917_smartpedidos-peru-orders-pending (GITIN-2068)
# Widening the search: any SwapWebSite operation today, anywhere in the
# resource group, regardless of which app -- in case the 6am swap the user
# remembers was for a different resource than SmartFran-Cloud-Orders-PRO.

az monitor activity-log list \
  --resource-group SmartFran.Cloud.PRO \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --start-time 2026-09-17T00:00:00Z \
  --end-time 2026-09-17T23:59:59Z \
  --query "[].{time:eventTimestamp, operation:operationName.value, resourceId:resourceId, status:status.localizedValue}" \
  -o json \
  > data/rg_today_raw.json

python3 -c "
import json
with open('data/rg_today_raw.json') as f:
    entries = json.load(f)
swaps = [e for e in entries if 'swap' in (e.get('operation') or '').lower()]
swaps.sort(key=lambda e: e.get('time') or '')
with open('data/rg_today_all_swaps.json', 'w') as f:
    json.dump(swaps, f, indent=2)
print(f'{len(swaps)} swap-related entries today, any resource, whole RG')
for e in swaps:
    print(e['time'], '|', e['operation'], '|', e['resourceId'])
"

rm -f data/rg_today_raw.json

#!/usr/bin/env bash
# Event: 20260917_smartpedidos-peru-orders-pending (GITIN-2068)
# Corroborating: a slot swap on Orders-PRO around 14:00 today allegedly
# recycled the last remaining .NET 8 instance, turning a partial/intermittent
# failure into a deterministic one for every new Peru order from that point.
# Checking Azure's own activity log for the swap operation itself, plus
# instance start times to see if they cluster right after ~14:00.

# C16 — Azure Activity Log: any swap/restart operation on Orders-PRO today
az monitor activity-log list \
  --resource-group SmartFran.Cloud.PRO \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --start-time 2026-09-17T00:00:00Z \
  --end-time 2026-09-17T23:59:59Z \
  --query "[?contains(resourceId, 'SmartFran-Cloud-Orders-PRO')].{time:eventTimestamp, operation:operationName.localizedValue, caller:caller, status:status.localizedValue}" \
  -o json \
  > data/orders_pro_activity_log_today.json

# C17 — instance start times (already requested earlier, re-included here
# since it's directly relevant to confirming the swap's effect)
az webapp list-instances \
  --name SmartFran-Cloud-Orders-PRO \
  --resource-group SmartFran.Cloud.PRO \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  -o json \
  > data/orders_pro_instances_detail.json

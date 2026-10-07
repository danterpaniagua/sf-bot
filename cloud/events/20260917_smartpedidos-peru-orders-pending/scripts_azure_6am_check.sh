#!/usr/bin/env bash
# Event: 20260917_smartpedidos-peru-orders-pending (GITIN-2068)
# User says there was also a deploy today at 06:00 ART (09:00 UTC) -- not
# present in the production-slot deployment history pulled earlier. Checking
# the stg2 slot (the automatic push-to-main target per Orders.PRO.yml) and
# re-pulling production history with an explicit higher limit in case the
# first pull was truncated.

# C18 — production slot, explicit higher limit (in case default truncated)
az webapp log deployment list \
  --name SmartFran-Cloud-Orders-PRO \
  --resource-group SmartFran.Cloud.PRO \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --query "[].{start:start_time, end:end_time, active:active, id:id}" \
  -o json \
  > data/orders_pro_deployment_history_full.json

# C19 — stg2 slot deployment history (automatic push-to-main target)
az webapp log deployment list \
  --name SmartFran-Cloud-Orders-PRO \
  --slot stg2 \
  --resource-group SmartFran.Cloud.PRO \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --query "[].{start:start_time, end:end_time, active:active, id:id}" \
  -o json \
  > data/orders_pro_stg2_deployment_history.json

#!/usr/bin/env bash
# Event: 20260917_smartpedidos-peru-orders-pending (GITIN-2068)
# URGENT check: the fix (commit 958dfa2, "v02.45.02 fix timezone") deployed
# directly to production at 16:10:52 ART, ~2 minutes before the 16:13 swap
# brought in the pre-fix stg2 build (last built 2026-09-16, a day before the
# fix existed). Checking which deployment is CURRENTLY marked active in
# production right now, fresh.

az webapp log deployment list \
  --name SmartFran-Cloud-Orders-PRO \
  --resource-group SmartFran.Cloud.PRO \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --query "[].{start:start_time, end:end_time, deployer:deployer, active:active, id:id}" \
  -o json \
  > data/orders_pro_current_active.json

#!/usr/bin/env bash
# Event: 20260917_smartpedidos-peru-orders-pending (GITIN-2068)
# Sanity check: does SmartFran-Cloud-Orders-PRO actually have a stg2 slot
# configured at all? (The earlier --slot stg2 query returned real data, which
# implies yes, but confirming directly via deployment slot list.)

az webapp deployment slot list \
  --name SmartFran-Cloud-Orders-PRO \
  --resource-group SmartFran.Cloud.PRO \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --query "[].{name:name, state:state, hostNames:hostNames}" \
  -o json \
  > data/orders_pro_slots_list.json

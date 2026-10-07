#!/usr/bin/env bash
# Event: 20260917_smartpedidos-peru-orders-pending (GITIN-2068)
# Checking whether SmartFran-Cloud-Orders-PRO runs multiple instances, and
# whether they've been recycled/scaled recently -- working theory for why
# only a small, growing-over-time subset of Peru orders fail (deterministic
# code, so intermittent failure across most-vs-some orders is more
# consistent with inconsistent instance images than with message content).

# C1 — current instance count / SKU for the Orders App Service Plan
az appservice plan show \
  --name SmartFran-Cloud-Orders-Plan-PRO \
  --resource-group SmartFran.Cloud.PRO \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --query "{sku:sku, numberOfSites:numberOfSites, capacity:sku.capacity}" \
  -o json \
  > data/orders_pro_plan_instances.json

# C2 — actual running instances for the Orders web app (per-instance detail,
# including instance IDs -- useful to see if they have different start
# times, implying different provisioning/image versions)
az webapp list-instances \
  --name SmartFran-Cloud-Orders-PRO \
  --resource-group SmartFran.Cloud.PRO \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  -o json \
  > data/orders_pro_instances_detail.json

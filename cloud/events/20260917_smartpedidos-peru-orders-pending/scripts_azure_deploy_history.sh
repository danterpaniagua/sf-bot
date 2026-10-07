#!/usr/bin/env bash
# Event: 20260917_smartpedidos-peru-orders-pending (GITIN-2068)
# Cross-checking the git-derived timeline (deploy Sept 16-17 via the
# "Stg => PRO" release merges) against Azure's own deployment history and
# current live runtime config for Orders-PRO. Read-only.

# C14 — deployment history (real deploy timestamps, not commit timestamps)
# Corrected: "az webapp deployment list" is not a valid subcommand.
az webapp log deployment list \
  --name SmartFran-Cloud-Orders-PRO \
  --resource-group SmartFran.Cloud.PRO \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  -o json \
  > data/orders_pro_deployment_history.json

# C15 — current live runtime stack (linuxFxVersion) -- confirms net10.0 is
# actually what's running right now, not just what was built
az webapp config show \
  --name SmartFran-Cloud-Orders-PRO \
  --resource-group SmartFran.Cloud.PRO \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --query "{linuxFxVersion:linuxFxVersion, netFrameworkVersion:netFrameworkVersion}" \
  -o json \
  > data/orders_pro_runtime_config.json

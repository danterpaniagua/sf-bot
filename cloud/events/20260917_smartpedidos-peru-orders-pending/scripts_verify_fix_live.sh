#!/usr/bin/env bash
# Event: 20260917_smartpedidos-peru-orders-pending (GITIN-2068)
# The fix commits (d5d87db50, 86bab37f9) landed at 15:50/15:59 ART today --
# just before the 16:13 swap. Checking whether the swap could have
# overwritten a just-deployed fix with the older stg2 build, and whether
# the exception has actually stopped occurring live.

# C21 — any deploy/activity on Orders-PRO after 16:15 ART (19:15 UTC) today
az webapp log deployment list \
  --name SmartFran-Cloud-Orders-PRO \
  --resource-group SmartFran.Cloud.PRO \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --query "[?start_time > '2026-09-17T19:15:00Z'].{start:start_time, end:end_time, deployer:deployer, active:active}" \
  -o json \
  > data/orders_pro_deploys_after_swap.json

# C22 — Graylog: any TimeZoneNotFoundException since the swap (19:13 UTC)
curl -s -u "$GRAYLOG_API_KEY:token" \
  --data-urlencode 'query=Service:Orders AND "TimeZoneNotFoundException"' \
  --data-urlencode 'from=2026-09-17T19:13:00.000Z' \
  --data-urlencode 'to=2026-09-17T23:59:59.000Z' \
  --data-urlencode 'limit=100' \
  -G "https://sfcloud-monitoreo.smartfran.com/graylog/api/search/universal/absolute" \
  -H 'Accept: application/json' \
  > data/graylog_tznotfound_since_swap.json

# C23 — Graylog: sanity check that Orders is still logging at all in this
# window (avoid trusting a 0 that's actually a data gap)
curl -s -u "$GRAYLOG_API_KEY:token" \
  --data-urlencode 'query=Service:Orders' \
  --data-urlencode 'from=2026-09-17T19:13:00.000Z' \
  --data-urlencode 'to=2026-09-17T23:59:59.000Z' \
  --data-urlencode 'limit=5' \
  -G "https://sfcloud-monitoreo.smartfran.com/graylog/api/search/universal/absolute" \
  -H 'Accept: application/json' \
  > data/graylog_orders_sanity_since_swap.json

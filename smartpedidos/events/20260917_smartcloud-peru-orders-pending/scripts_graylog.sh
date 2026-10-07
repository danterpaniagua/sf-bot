#!/usr/bin/env bash
# Event: 20260917_smartcloud-peru-orders-pending (GITIN-2068)
# The older sf-monitoreo Graylog (5.2.12) broke on an oversized 13-day
# relative range ("Missing search type result!" ApiError) -- confirmed
# working fine at a normal 7-day relative range (sanity check, 54M+ results
# from the Default Stream). Retrying the order-id search with an ABSOLUTE
# range instead, covering the order's real creation window
# (2026-09-06T03:13:38Z), to sidestep the relative-range issue entirely.

curl -s -u "$SML_GRAYLOG_API_KEY:token" \
  --data-urlencode 'query=2270509683' \
  --data-urlencode 'from=2026-09-05T00:00:00.000Z' \
  --data-urlencode 'to=2026-09-10T00:00:00.000Z' \
  --data-urlencode 'limit=100' \
  -G "http://sf-monitoreo.smartfran.com:9000/api/search/universal/absolute" \
  -H 'Accept: application/json' \
  > /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260917_smartcloud-peru-orders-pending/data/graylog_smloyalty_order_2270509683_absolute.json

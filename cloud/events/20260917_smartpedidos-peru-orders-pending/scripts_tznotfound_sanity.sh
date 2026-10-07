#!/usr/bin/env bash
# Sanity check before trusting the 0-result history query: can Graylog find
# the CONFIRMED occurrence from today (branch 5454, ~2026-09-17T18:33:04Z,
# from the user-provided raw Azure export) at all? If this also returns 0,
# the query/field assumption is wrong, not the history.

# C13a — drop the Service:Orders filter entirely, free-text only, narrow
# window around the confirmed occurrence
curl -s -u "$GRAYLOG_API_KEY:token" \
  --data-urlencode 'query=TimeZoneNotFoundException' \
  --data-urlencode 'from=2026-09-17T18:00:00.000Z' \
  --data-urlencode 'to=2026-09-17T19:00:00.000Z' \
  --data-urlencode 'limit=50' \
  -G "https://sfcloud-monitoreo.smartfran.com/graylog/api/search/universal/absolute" \
  -H 'Accept: application/json' \
  > data/graylog_tznotfound_sanity_freetext.json

# C13b — same window, filter on the branch's queue name instead of Service,
# in case "Service:Orders" doesn't match this raw export's field shape
curl -s -u "$GRAYLOG_API_KEY:token" \
  --data-urlencode 'query=5454PRD_PlatformMessages' \
  --data-urlencode 'from=2026-09-17T18:00:00.000Z' \
  --data-urlencode 'to=2026-09-17T19:00:00.000Z' \
  --data-urlencode 'limit=50' \
  -G "https://sfcloud-monitoreo.smartfran.com/graylog/api/search/universal/absolute" \
  -H 'Accept: application/json' \
  > data/graylog_tznotfound_sanity_queuename.json

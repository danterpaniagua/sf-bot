#!/usr/bin/env bash
# Event: 20260917_smartpedidos-peru-orders-pending (GITIN-2068)
# Checking whether TimeZoneNotFoundException in Orders predates today, and
# specifically whether it predates the 2026-09-07 .NET 8->10 migration --
# would change the "why now" narrative if it does.

# C12 — Graylog: all TimeZoneNotFoundException hits in Orders, absolute
# range from well before the earliest known stuck order (2026-09-01) through
# today, to see the actual first-occurrence date.
curl -s -u "$GRAYLOG_API_KEY:token" \
  --data-urlencode 'query=Service:Orders AND "TimeZoneNotFoundException"' \
  --data-urlencode 'from=2026-09-01T00:00:00.000Z' \
  --data-urlencode 'to=2026-09-17T23:59:59.000Z' \
  --data-urlencode 'limit=300' \
  -G "https://sfcloud-monitoreo.smartfran.com/graylog/api/search/universal/absolute" \
  -H 'Accept: application/json' \
  > data/graylog_tznotfound_history.json

#!/usr/bin/env bash
# Event: 20260917_smartpedidos-peru-orders-pending (GITIN-2068)
# Read-only investigation only — no remediation applied yet (see
# gitin2068-timezone-fix.patch for the drafted, not-yet-applied code fix).

# === INVESTIGATION ===

# C1 — Azure App Configuration: onboarded tenants (organizations key).
# FAILED — 403, missing "App Configuration Data Reader" RBAC role on the
# logged-in identity (dantep@smartfran.com), confirmed via C3 below.
az appconfig kv show \
  --name SmartFran-Cloud-Settings-PRO \
  --key organizations \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --auth-mode login \
  > data/appconfig_organizations.json

# C2 — Azure App Configuration: per-tenant SQS mapping version
# (OrderSQSVersion key). Same 403/RBAC failure as C1.
az appconfig kv show \
  --name SmartFran-Cloud-Settings-PRO \
  --key OrderSQSVersion \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --auth-mode login \
  > data/appconfig_ordersqsversion.json

# C3 — confirm logged-in identity/subscription (ruled out auth as the cause
# of C1/C2's failure; confirmed correct identity/subscription, RBAC gap
# specifically on the App Configuration data plane)
az account show --output json \
  > data/az_account_show.json

# C4 — confirm the App Configuration resource itself is reachable (ARM
# control-plane `show`, only needs plain Reader — succeeded, isolating the
# C1/C2 failure to the data-plane RBAC role specifically)
az appconfig show \
  --name SmartFran-Cloud-Settings-PRO \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --query id -o tsv \
  > data/appconfig_resource_id.txt

# C5 — Graylog: Orders service errors, last 24h (broad first pass)
curl -s -u "$GRAYLOG_API_KEY:token" \
  --data-urlencode 'query=Service:Orders AND AppLevel:Error' \
  --data-urlencode 'range=86400' --data-urlencode 'limit=100' \
  -G "https://sfcloud-monitoreo.smartfran.com/graylog/api/search/universal/relative" \
  -H 'Accept: application/json' \
  > data/graylog_orders_errors_24h.json

# C6 — Graylog connectivity/health check
curl -s -u "$GRAYLOG_API_KEY:token" \
  "https://sfcloud-monitoreo.smartfran.com/graylog/api/system" \
  -H 'Accept: application/json' \
  > data/graylog_system_health.json

# C7 — Graylog: confirm Orders service has any logs at all, last 1h (rule
# out "no data reaching Graylog" as a confound before trusting C5's 0 result)
curl -s -u "$GRAYLOG_API_KEY:token" \
  --data-urlencode 'query=Service:Orders' \
  --data-urlencode 'range=3600' --data-urlencode 'limit=5' \
  -G "https://sfcloud-monitoreo.smartfran.com/graylog/api/search/universal/relative" \
  -H 'Accept: application/json' \
  > data/graylog_orders_any_1h.json

# C8 — Graylog: free-text search for "Peru" across Orders service, last 24h
# (corrected after an initial leading-wildcard query failed with a parse
# error). Found 22 hits, 20 from Orders API — real Grido-Peru orders,
# TenantId d3186bc6d7b2 (GRIDO), confirming Peru routes through the
# already-onboarded GRIDO tenant, not a separate/unregistered one.
curl -s -u "$GRAYLOG_API_KEY:token" \
  --data-urlencode 'query=Peru OR peru OR PERU' \
  --data-urlencode 'range=86400' --data-urlencode 'limit=100' \
  -G "https://sfcloud-monitoreo.smartfran.com/graylog/api/search/universal/relative" \
  -H 'Accept: application/json' \
  > data/graylog_peru_freetext_24h.json

# C9 — Graylog: trace a specific known-stuck order (2270509683, branch 5610,
# per SmartPedidos-side identification — see
# smartpedidos/events/20260917_smartcloud-peru-orders-pending/) across its
# full 13-day age. ZERO results — this order never appears in Orders API
# logs at all, across its entire lifetime.
curl -s -u "$GRAYLOG_API_KEY:token" \
  --data-urlencode 'query=Service:Orders AND "2270509683"' \
  --data-urlencode 'range=1123200' --data-urlencode 'limit=200' \
  -G "https://sfcloud-monitoreo.smartfran.com/graylog/api/search/universal/relative" \
  -H 'Accept: application/json' \
  > data/graylog_order_2270509683_trace.json

# C10 — live Azure AppServiceConsoleLogs export (user-provided, not queried
# via this script) showed the actual root cause: a live
# System.TimeZoneNotFoundException in MessageProcessor.SetTimeZones,
# 2026-09-17T18:33:04Z, branch 5454 (Peru). Not re-run here — captured
# directly from the source, see investigation.md for the full stack trace
# (not persisted as a repo file — contains embedded live JWT/AWS credential
# material, see "Hallazgos secundarios" in ops.md).

# C11 — source repo checks (read-only, no output file — git plumbing):
#   git diff origin/main origin/dev --stat -- \
#     Source/Services/Orders/.../TimeZoneCountries.cs \
#     Source/Services/Orders/.../MessageProcessor.cs
#   -> confirmed byte-identical between origin/main (faca32f1, 2026-09-17)
#      and origin/dev (37470e4f, 2026-09-16); the drafted fix applies
#      cleanly to what's actually deployed to PRO, not just dev.
#   git show c7fa45721 --stat
#   -> confirmed the Sept 7 net8.0->net10.0 "Migracion Framework" (GSFC-998)
#      commit, and that it left every PRO GitHub Actions workflow's
#      DOTNET_CORE_VERSION pin unchanged (still 7.0.x/8.0.x) while updating
#      every DEV/STG/TEST workflow to 10.0.x — see "Hallazgos secundarios".

#!/usr/bin/env bash
# Event: 20260825_sales-caerequest-408-timeout (GITIN-1940)
# Deploy the StatusCode/Path/Method/ElapsedMilliseconds/ClientIP promotion
# block to the live Logstash pipeline on the Graylog VM, via a local patch
# file (see gitin-1940.patch in this same folder) applied over non-interactive
# SSH. Do NOT scp the local docs/azure-eventhub-to-graylog.conf over the live
# file directly — it has its Event Hub/Storage connection strings redacted to
# "NO" (this repo's convention, no real secrets committed); overwriting the
# live file with it would break ingestion fleet-wide. scp also does not work
# in this environment — use ssh + stdin redirection instead.

# === PRE-DEPLOY: verify live conf status (do this before trusting the patch) ===

# D0 — fetch the live conf read-only; confirm it still matches the context
# lines the patch expects before applying (already done once this session,
# 2026-08-26 — re-run if any time has passed or another change may have landed)
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com \
  "sudo cat /etc/logstash/conf.d/azure-eventhub-to-graylog.conf" \
  > /tmp/live-azure-eventhub-to-graylog.conf

# === DEPLOY ===

# D1 — copy the local patch file to the VM (run from bots/ repo root)
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com \
  "cat > /tmp/gitin-1940.patch" < cloud/events/20260825_sales-caerequest-408-timeout/gitin-1940.patch

# D2 — backup the live file, then dry-run the patch (read-only check)
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com \
  "sudo cp /etc/logstash/conf.d/azure-eventhub-to-graylog.conf /etc/logstash/conf.d/azure-eventhub-to-graylog.conf.bak-GITIN-1940 && sudo patch --dry-run -p0 -d /etc/logstash/conf.d/ < /tmp/gitin-1940.patch"

# D3 — apply the patch for real
#
# +------------------------------------------------------------+
# |  STATE-CHANGING COMMAND -- VERIFY TARGET BEFORE RUNNING    |
# |  This command modifies, deletes, or writes state.          |
# |  Confirm: environment / database / host is the intended one|
# |  This action may be IRREVERSIBLE                           |
# +------------------------------------------------------------+
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com \
  "sudo patch -p0 -d /etc/logstash/conf.d/ < /tmp/gitin-1940.patch"

# D4 — validate syntax — catches parse errors, NOT ruby runtime errors (past
# incident: -t passed, service still crash-looped —
# operations/events/20260701_logstash-deployment ops-events.md)
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com \
  "sudo -u logstash /usr/share/logstash/bin/logstash --path.settings /etc/logstash -t"

# D5 — restart
#
# +------------------------------------------------------------+
# |  STATE-CHANGING COMMAND -- VERIFY TARGET BEFORE RUNNING    |
# |  This command modifies, deletes, or writes state.          |
# |  Confirm: environment / database / host is the intended one|
# |  This action may be IRREVERSIBLE                           |
# +------------------------------------------------------------+
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com \
  "sudo systemctl restart logstash"

# D6 — confirm it's actually up, not crash-looping
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com \
  "sudo systemctl status logstash --no-pager"

# === VERIFICATION ===

# V1 — list Graylog streams (read-only, confirms per-app routing before/after)
curl -s -u "${GRAYLOG_API_KEY}:token" \
  -H "Accept: application/json" \
  "https://sfcloud-monitoreo.smartfran.com/graylog/api/streams" | python3 -m json.tool

# V2 — Graylog UI or API field-exists queries, 15-30 min post-restart, general traffic:
# _exists_:StatusCode
# _exists_:Path
# _exists_:Method
# _exists_:ElapsedMilliseconds
# _exists_:ClientIP
# Service:Sales AND Environment:Production AND Path:"/api/v1/WsFeAr/CaeRequest" AND StatusCode:408

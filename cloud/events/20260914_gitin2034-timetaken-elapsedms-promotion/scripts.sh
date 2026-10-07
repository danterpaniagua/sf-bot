#!/usr/bin/env bash
# Event: 20260914_gitin2034-timetaken-elapsedms-promotion (GITIN-2034)
# Fix the AppServiceHTTPLogs branch of the GITIN-1940 Logstash block: it only
# handled "properties" (lowercase) as a pre-stringified JSON String, but Azure
# also sends this category in a flat/unwrapped shape where this pipeline's own
# initial `json` filter parses "properties" into a live Hash instead — causing
# all 5 promoted fields (Method/Path/StatusCode/ElapsedMilliseconds/ClientIP)
# to silently not promote for messages in that shape. See investigation.md.
#
# Deploy via local patch file (gitin-2034.patch, this folder) applied over
# non-interactive SSH — same convention as GITIN-1940. Do NOT scp the local
# docs/azure-eventhub-to-graylog.conf copy over the live file (redacted
# secrets would overwrite the real ones). scp does not work in this
# environment either way — ssh + stdin redirection only.

# === INVESTIGATION ===

# C1 — fetch the live conf (read-only), used to trace the actual bug
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com \
  "sudo cat /etc/logstash/conf.d/azure-eventhub-to-graylog.conf" \
  > data/live-azure-eventhub-to-graylog.conf

# C2 — Graylog: AppServiceHTTPLogs sample check (Admin-PRO/Orders-PRO, confirmed working)
curl -s -u "$GRAYLOG_API_KEY:token" \
  --data-urlencode 'query=category:AppServiceHTTPLogs' \
  --data-urlencode 'range=3600' --data-urlencode 'limit=5' \
  -G "https://sfcloud-monitoreo.smartfran.com/graylog/api/search/universal/relative" \
  -H 'Accept: application/json' \
  > data/graylog_appservicehttplogs_sample.json

# C3 — Graylog: indexing failures check (found 64,866 unrelated `time` field failures)
curl -s -u "$GRAYLOG_API_KEY:token" \
  "https://sfcloud-monitoreo.smartfran.com/graylog/api/system/indexer/failures?limit=50" \
  -H 'Accept: application/json' \
  > data/graylog_index_failures.json

# C4 — Graylog: the specific broken message by _id, confirmed the actual root cause
curl -s -u "$GRAYLOG_API_KEY:token" \
  --data-urlencode 'query=_id:"b4966b92-b038-11f1-be92-7c1e52beabec"' \
  --data-urlencode 'range=604800' --data-urlencode 'limit=1' \
  -G "https://sfcloud-monitoreo.smartfran.com/graylog/api/search/universal/relative" \
  -H 'Accept: application/json' \
  > data/graylog_msg_b4966b92.json

# === REMEDIATION — attempt #1, FAILED, reverted (2026-09-14) ===

# D0 — verify live conf status before trusting the patch
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com \
  "sudo cat /etc/logstash/conf.d/azure-eventhub-to-graylog.conf" \
  > /tmp/live-azure-eventhub-to-graylog.conf

# D1 — copy the local patch file to the VM
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com \
  "cat > /tmp/gitin-2034.patch" < /home/dpaniagua/Documentos/git/bots/cloud/events/20260914_gitin2034-timetaken-elapsedms-promotion/gitin-2034.patch

# D2 — backup the live file, then dry-run the patch (read-only check)
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com \
  "sudo cp /etc/logstash/conf.d/azure-eventhub-to-graylog.conf /etc/logstash/conf.d/azure-eventhub-to-graylog.conf.bak-GITIN-2034 && sudo patch --dry-run -p0 -d /etc/logstash/conf.d/ < /tmp/gitin-2034.patch"

# ⚠️ D3 — apply the patch for real (attempt #1 — this patch version had a bug)
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com \
  "sudo patch -p0 -d /etc/logstash/conf.d/ < /tmp/gitin-2034.patch"

# D4 — validate syntax — FAILED on attempt #1: patch #1's comment text used an
# apostrophe ("pipeline's own initial") inside the Logstash `code => '...'`
# single-quoted string, closing it prematurely. Caught here before restart —
# Logstash was never restarted with the broken config, no service impact.
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com \
  "sudo -u logstash /usr/share/logstash/bin/logstash --path.settings /etc/logstash -t"

# ⚠️ D4b — revert from the D2 backup after the D4 failure above
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com \
  "sudo cp /etc/logstash/conf.d/azure-eventhub-to-graylog.conf.bak-GITIN-2034 /etc/logstash/conf.d/azure-eventhub-to-graylog.conf && sudo -u logstash /usr/share/logstash/bin/logstash --path.settings /etc/logstash -t"
# -> Configuration OK, confirmed reverted to known-good state.

# === REMEDIATION — attempt #2, SUCCESS (2026-09-14) ===
# gitin-2034.patch regenerated locally with the apostrophe removed; verified
# via a local Python quote-balance scan of the full code block, `ruby -c` on
# the extracted Ruby code (Syntax OK), and confirmed no added line contains a
# single-quote character at all, before re-deploying.

# D1b — copy the corrected patch to the VM
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com \
  "cat > /tmp/gitin-2034.patch" < /home/dpaniagua/Documentos/git/bots/cloud/events/20260914_gitin2034-timetaken-elapsedms-promotion/gitin-2034.patch

# D2b — dry-run the corrected patch
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com \
  "sudo patch --dry-run -p0 -d /etc/logstash/conf.d/ < /tmp/gitin-2034.patch"

# ⚠️ D3b — apply the corrected patch
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com \
  "sudo patch -p0 -d /etc/logstash/conf.d/ < /tmp/gitin-2034.patch"

# D4c — validate syntax — Configuration OK
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com \
  "sudo -u logstash /usr/share/logstash/bin/logstash --path.settings /etc/logstash -t"

# ⚠️ D5 — restart
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com \
  "sudo systemctl restart logstash"

# D6 — confirm healthy — active (running), Event Hub receivers opened
# successfully on both partitions, no errors
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com \
  "sudo systemctl status logstash --no-pager -l"

# === VERIFICATION — post-deploy (2026-09-14) ===

# V1 — confirm the 5 promoted fields are now populated on real live traffic
# (68 total matches, 5 min window, all 10 sampled messages confirmed correct)
curl -s -u "$GRAYLOG_API_KEY:token" \
  --data-urlencode 'query=category:AppServiceHTTPLogs AND name:SMARTFRAN-CLOUD-SALES-PRO' \
  --data-urlencode 'range=300' --data-urlencode 'limit=10' \
  -G "https://sfcloud-monitoreo.smartfran.com/graylog/api/search/universal/relative" \
  -H 'Accept: application/json' \
  > data/graylog_verify_post_deploy.json

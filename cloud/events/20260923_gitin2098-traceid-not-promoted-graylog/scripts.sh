#!/usr/bin/env bash
# Event: 20260923_gitin2098-traceid-not-promoted-graylog (GITIN-2098)
# Promote TraceId/SpanId/ParentId (W3C trace triple, confirmed universal via
# Provider.Logger.Core/W3CAndAmbientTraceEnricher.cs) to bare top-level Graylog
# fields, same pattern as GITIN-1883 (TraceKey/TenantId/Service/Environment).
# See investigation.md for full source-code trace.

# === INVESTIGATION ===

# C1 — fetch the live conf (read-only) before drafting a patch — the local
# cloud-graylog/docs/ mirror has drifted from live before (GITIN-1905, GITIN-2034)
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com \
  "sudo cat /etc/logstash/conf.d/azure-eventhub-to-graylog.conf" \
  > /home/dpaniagua/Documentos/git/bots/cloud/events/20260923_gitin2098-traceid-not-promoted-graylog/data/live-azure-eventhub-to-graylog.conf
# Result: after redacting the 2 real secrets it returned (event_hub_connections/
# storage_connection -> "NO", same placeholder convention as every other
# committed live-conf pull in this repo — see investigation.md), the file was
# byte-identical to the cloud-graylog/docs/ mirror. Mirror confirmed in sync,
# patch below drafted against it directly.

# === REMEDIATION ===

# D1 — copy the local patch file to the VM
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com \
  "cat > /tmp/gitin-2098.patch" < /home/dpaniagua/Documentos/git/bots/cloud/events/20260923_gitin2098-traceid-not-promoted-graylog/gitin-2098.patch

# D2 — backup the live file, then dry-run the patch (read-only check)
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com \
  "sudo cp /etc/logstash/conf.d/azure-eventhub-to-graylog.conf /etc/logstash/conf.d/azure-eventhub-to-graylog.conf.bak-GITIN-2098 && sudo patch --dry-run -p0 -d /etc/logstash/conf.d/ < /tmp/gitin-2098.patch"

# D3 — apply the patch for real
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com \
  "sudo patch -p0 -d /etc/logstash/conf.d/ < /tmp/gitin-2098.patch"

# D4 — validate syntax (syntax only, not runtime — GITIN-2034 found a config
# that passed -t but still crash-looped, so D6 below still matters)
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com \
  "sudo -u logstash /usr/share/logstash/bin/logstash --path.settings /etc/logstash -t"

# D4-ROLLBACK — only if D4 fails syntax validation. Do NOT proceed to D5 in
# that case; restore from the D2 backup instead (same recovery pattern as the
# GITIN-2034 incident).
# ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com \
#   "sudo cp /etc/logstash/conf.d/azure-eventhub-to-graylog.conf.bak-GITIN-2098 /etc/logstash/conf.d/azure-eventhub-to-graylog.conf && sudo -u logstash /usr/share/logstash/bin/logstash --path.settings /etc/logstash -t"

# D5 — restart
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com \
  "sudo systemctl restart logstash"

# D6 — confirm healthy (active/running, Event Hub receivers opened on both
# partitions, no errors)
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com \
  "sudo systemctl status logstash --no-pager -l"

# === VERIFICATION — post-deploy ===

# V1 — confirm TraceId/SpanId/ParentId now populated on real live traffic,
# Sales (direct-GELF branch)
curl -s -u "$GRAYLOG_API_KEY:token" \
  --data-urlencode 'query=_exists_:TraceId AND name:SMARTFRAN-CLOUD-SALES-PRO' \
  --data-urlencode 'range=300' --data-urlencode 'limit=10' \
  -G "https://sfcloud-monitoreo.smartfran.com/graylog/api/search/universal/relative" \
  -H 'Accept: application/json' \
  > /home/dpaniagua/Documentos/git/bots/cloud/events/20260923_gitin2098-traceid-not-promoted-graylog/data/graylog_verify_sales_post_deploy.json

# V2 — confirm on an Event Hub app (Business-PRO)
curl -s -u "$GRAYLOG_API_KEY:token" \
  --data-urlencode 'query=_exists_:TraceId AND name:SMARTFRAN-CLOUD-BUSINESS-PRO' \
  --data-urlencode 'range=300' --data-urlencode 'limit=10' \
  -G "https://sfcloud-monitoreo.smartfran.com/graylog/api/search/universal/relative" \
  -H 'Accept: application/json' \
  > /home/dpaniagua/Documentos/git/bots/cloud/events/20260923_gitin2098-traceid-not-promoted-graylog/data/graylog_verify_business_post_deploy.json

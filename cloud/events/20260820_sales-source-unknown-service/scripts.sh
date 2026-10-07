#!/usr/bin/env bash
# Event: 20260820_sales-source-unknown-service (GITIN-1908)
# Commands are grouped by phase: Investigation
# No remediation commands — investigation only, no state changed.

BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"

# === INVESTIGATION ===

# C1 — Pull live source for both "CLEF source" pipeline rules (GITIN-1835)
curl -s -u "${GRAYLOG_API_KEY}:token" -H "Accept: application/json" \
  "${BASE}/system/pipelines/rule" | \
  jq -r '.[] | select(.title | contains("CLEF source")) | {id, title, source}'
# OUTPUT: both rules already key on bare `Service`, not `Properties_Service` —
# migrated at the same time as the rule GITIN-1905 checked. Refutes the
# original stale-field-name theory.

# C2 — Views Search: count + sample messages with source:"unknown-service", last 24h
curl -s -u "${GRAYLOG_API_KEY}:token" \
  -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
  -d '{
    "queries": [{
      "id": "q1",
      "query": {"type": "elasticsearch", "query_string": "source:\"unknown-service\""},
      "timerange": {"type": "relative", "range": 86400},
      "search_types": [{"id": "msgs1", "type": "messages", "limit": 20}]
    }]
  }' \
  "${BASE}/views/search"
# then:
curl -s -u "${GRAYLOG_API_KEY}:token" \
  -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
  -d '{}' "${BASE}/views/search/<SEARCH_ID>/execute"
# then poll:
curl -s -u "${GRAYLOG_API_KEY}:token" -H "Accept: application/json" \
  "${BASE}/views/search/status/<EXECUTION_ID>"
# OUTPUT: total_results 223916 (24h). 20/20 sampled are ASP.NET Core built-in
# framework diagnostics (SourceContext Microsoft.AspNetCore.Hosting.Diagnostics
# / Microsoft.AspNetCore.Cors.Infrastructure.CorsService) from Sales PRO
# (Host smartfran-cloud-sales-pro.azurewebsites.net) — none carry a `Service`
# key in Properties.

# C3 — Same query excluding ASP.NET Core framework SourceContext, to check
#      whether any non-framework messages remain
curl -s -u "${GRAYLOG_API_KEY}:token" \
  -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
  -d '{
    "queries": [{
      "id": "q1",
      "query": {"type": "elasticsearch", "query_string": "source:\"unknown-service\" AND NOT SourceContext:Microsoft.AspNetCore.*"},
      "timerange": {"type": "relative", "range": 86400},
      "search_types": [{"id": "msgs1", "type": "messages", "limit": 20}]
    }]
  }' \
  "${BASE}/views/search"
# then execute + poll status, same pattern as C2
# OUTPUT: total_results 1268 (24h, 0.6% of the 223916). 20 sampled split:
#   12/20 SourceContext SmartFran.Cloud.Sales.Application.Services.VirtualWallet.SignalR.WalletNotificationService
#         ("Notificación enviada: Orden creada ORD...") — Sales' own app code,
#         not routed through the standard SmartFranLogExtensions helpers.
#    8/20 SourceContext Microsoft.Azure.SignalR.ServiceConnection /
#         Microsoft.Azure.SignalR.DefaultServiceEventHandler — Azure SignalR
#         SDK's own internal logging, same class as the ASP.NET Core noise.

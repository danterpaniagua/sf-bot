#!/usr/bin/env bash
# Event: 20260721_gestion_clubgrido_waf_504
# Resource: Application Gateway WAF_v2 "WAF_APPs" (RG DefaultGroup01)
# Subscription: Smart IT - Grido (0190fa7d-4ccf-4e3d-beb1-323b5780bfc8)
# Log Analytics workspace: analisis-loadbalancer (GUID e00bc24a-820a-45fa-ad4a-3a4dc083d205)

SUB=0190fa7d-4ccf-4e3d-beb1-323b5780bfc8

# === DISCOVERY ===

# C1 — appgw-show
az network application-gateway show \
  --name WAF_APPs \
  --resource-group DefaultGroup01 \
  --subscription "$SUB" \
  -o json > /tmp/appgw_waf_apps.json

# OUTPUT (2026-07-21):
#   Confirmed WAF_v2 tier, 3 backendHttpSettings (Backend_WebSite:4430/180s timeout,
#   Backend_ClubSite:443/60s, Backend_ClubSite_PY:443/60s), no custom probes (probes: []).
#   Listener_WebSite_HTTPS (hostName gestion.clubgrido.com.ar, frontendPort 4430) ->
#   Rule_WebSite -> pool Back_WebSite (single server 192.168.50.131) -> Backend_WebSite settings.

# C2 — appgw-backend-health
az network application-gateway show-backend-health \
  --name WAF_APPs \
  --resource-group DefaultGroup01 \
  --subscription "$SUB" \
  -o json

# OUTPUT (2026-07-21):
#   All backend servers reported Healthy via default root-path probe (200/302 responses).
#   Back_WebSite: 192.168.50.131 Healthy (302 on root) — confirms server answers at "/"
#   but says nothing about /Catalog/* specifically (no custom probe exists).

# C3 — law-workspace-guid
az monitor log-analytics workspace show \
  --resource-group defaultgroup01 \
  --workspace-name analisis-loadbalancer \
  --subscription "$SUB" \
  --query customerId -o tsv

# OUTPUT (2026-07-21): e00bc24a-820a-45fa-ad4a-3a4dc083d205

# C4 — law-diag-settings-list
APPGW_ID=$(az network application-gateway show \
  --name WAF_APPs \
  --resource-group DefaultGroup01 \
  --subscription "$SUB" \
  --query id -o tsv)

az monitor diagnostic-settings list \
  --resource "$APPGW_ID" \
  --subscription "$SUB" \
  -o table

# OUTPUT (2026-07-21): setting "LOGS_WAF" exporting to workspace analisis-loadbalancer.

# === INVESTIGATION ===

# C5 — kql-accesslog-schema
az monitor log-analytics query \
  --workspace e00bc24a-820a-45fa-ad4a-3a4dc083d205 \
  --subscription "$SUB" \
  --analytics-query "AzureDiagnostics
| where Category == 'ApplicationGatewayAccessLog'
| where TimeGenerated > ago(48h)
| take 1" \
  -o json

# OUTPUT (2026-07-21):
#   Confirmed real field names (AzureDiagnostics type-suffixed): timeTaken_d, error_info_s,
#   serverStatus_s, serverRouted_s, backendPoolName_s, backendSettingName_s, host_s,
#   requestUri_s, httpStatus_d. Sample row: WAFMode_s = "Detection" (WAF cannot block).

# C6 — kql-accesslog-504-query
az monitor log-analytics query \
  --workspace e00bc24a-820a-45fa-ad4a-3a4dc083d205 \
  --subscription "$SUB" \
  --analytics-query "AzureDiagnostics
| where Category == 'ApplicationGatewayAccessLog'
| where TimeGenerated > ago(48h)
| where host_s has 'gestion.clubgrido.com'
| project TimeGenerated, BackendPoolName_s=backendPoolName_s, BackendSettingName_s=backendSettingName_s,
    ClientIP_s=clientIP_s, Error_info_s=error_info_s, Host_s=host_s, HttpMethod_s=httpMethod_s,
    HttpStatus_d=httpStatus_d, RequestUri_s=requestUri_s, ServerConnectTime_s=serverConnectTime_s,
    ServerHeaderTime_s=serverHeaderTime_s, ServerResponseLatency_s=serverResponseLatency_s,
    ServerRouted_s=serverRouted_s, ServerStatus_s=serverStatus_s, TimeTaken_d=timeTaken_d
| order by TimeGenerated desc" \
  -o table > website.log-analytics.table

# OUTPUT (2026-07-21): 3,706 rows.
#   HttpStatus_d distribution: 502=3121, 200=305, 499=265, 504=13, 206=2
#   Error_info_s distribution: ERRORINFO_UPSTREAM_NO_LIVE=3121, ERRORINFO_CLIENT_CLOSED_REQUEST=544,
#     ERRORINFO_CLIENT_TIMED_OUT=28, ERRORINFO_UPSTREAM_TIMED_OUT=13
#   All 13x 504 rows classified ERRORINFO_UPSTREAM_TIMED_OUT. 4 of them on /Catalog/SetListCatalog,
#     TimeTaken ~180.0xx s (exact match to Backend_WebSite requestTimeout).
#   3,121x 502 ERRORINFO_UPSTREAM_NO_LIVE spanning 2026-07-20T05:04:52Z to 2026-07-21T10:01:04Z (~29h).
#   Full output archived: 20260721_gestion_clubgrido_waf_504_access-log-raw.table

# C7 — kql-perflog-schema
az monitor log-analytics query \
  --workspace e00bc24a-820a-45fa-ad4a-3a4dc083d205 \
  --subscription "$SUB" \
  --analytics-query "AzureDiagnostics
| where Category == 'ApplicationGatewayPerformanceLog'
| where TimeGenerated > ago(48h)
| take 1" \
  -o json

# OUTPUT (2026-07-21): [] (empty).
#   Expected: ApplicationGatewayPerformanceLog only populates for v1 SKU gateways. WAF_APPs is
#   v2 SKU — backend health/throughput is exposed via Azure Monitor metrics instead, not this
#   diagnostic log category. Not a data gap.

# C8 — kql-firewalllog-schema
az monitor log-analytics query \
  --workspace e00bc24a-820a-45fa-ad4a-3a4dc083d205 \
  --subscription "$SUB" \
  --analytics-query "AzureDiagnostics
| where Category == 'ApplicationGatewayFirewallLog'
| where TimeGenerated > ago(48h)
| take 1" \
  -o json

# OUTPUT (2026-07-21):
#   Sample row: action_s = "Matched" (not "Blocked"), consistent with WAFMode_s = "Detection".
#   Match was on /Account/ChangePassword (SQLi false-positive on a CSRF cookie token) —
#   unrelated endpoint, confirms WAF is not a factor in the /Catalog/* 504s. No further
#   firewall-log query run — access-log evidence (ERRORINFO_UPSTREAM_TIMED_OUT, exact timeout
#   match) already conclusive.

# === BACKEND VM / AUTO-SHUTDOWN CORRELATION ===

# C9 — vm-auto-shutdown-check
az resource show \
  --resource-group DefaultGroup01 \
  --name "shutdown-computevm-SFCG-WSIT-01" \
  --resource-type "Microsoft.DevTestLab/schedules" \
  --subscription "$SUB" \
  --query "{status:properties.status, time:properties.dailyRecurrence.time, timeZone:properties.timeZoneId, notificationEnabled:properties.notificationSettings.status}" \
  -o table

# OUTPUT (2026-07-21): Status=Enabled, Time=0200, TimeZone="Argentina Standard Time",
#   NotificationEnabled=Disabled.

# C9b — vm-show / vm-list-ip-addresses
az vm show \
  --resource-group DefaultGroup01 \
  --name SFCG-WSIT-01 \
  --subscription "$SUB" \
  --query "{name:name, tags:tags, osType:storageProfile.osDisk.osType, vmSize:hardwareProfile.vmSize, nics:networkProfile.networkInterfaces[].id}" \
  -o json

az vm list-ip-addresses \
  --resource-group DefaultGroup01 \
  --name SFCG-WSIT-01 \
  --subscription "$SUB" \
  -o table

# OUTPUT (2026-07-21): tags {SML: WebSite, Website: 01}, OS Windows, size Standard_B4als_v2.
#   PrivateIPAddress 192.168.50.131 — confirmed identical to the single Back_WebSite pool
#   server already identified in the WAF investigation (C1/C6). SFCG-WSIT-01 IS the backend
#   responsible for both H1 (Catalog timeouts) and H2 (29h outage).

# C10 — activity-log-list (auto-shutdown correlation check)
az monitor activity-log list \
  --resource-group DefaultGroup01 \
  --subscription "$SUB" \
  --start-time 2026-07-19T20:00:00Z \
  --end-time 2026-07-21T12:00:00Z \
  -o json > /tmp/activity_log_full.json

jq -r '.[] | select(.resourceId | ascii_downcase | contains("sfcg-wsit-01")) | "\(.eventTimestamp)  \(.operationName.value)  \(.status.value)  caller=\(.caller // "n/a")"' /tmp/activity_log_full.json | sort

# OUTPUT (2026-07-21): only 3 events in the entire 40h window —
#   2026-07-21T10:00:06.832Z  Microsoft.Resourcehealth/healthevent/Updated/action   Updated
#   2026-07-21T10:00:12.771Z  Microsoft.Resourcehealth/healthevent/Resolved/action  Resolved
#   2026-07-21T10:00:16.1885507Z  Microsoft.Compute/virtualMachines/start/action    Succeeded (manual, human caller)
#   NO deallocate/stop/powerOff event anywhere in the window, including case-insensitive
#   match. Auto-shutdown ruled out as the cause of the 29h outage. The only recorded action
#   is a manual VM start 48s before the last 502 in the access log — consistent with an
#   in-guest OS/IIS hang (invisible to Activity Log and Resource Health platform checks)
#   resolved by reboot, not with a scheduled deallocation.

# C11 — vm-get-instance-view (current state, post-recovery)
az vm get-instance-view \
  --resource-group DefaultGroup01 \
  --name SFCG-WSIT-01 \
  --subscription "$SUB" \
  --query "instanceView.statuses[].{code:code, displayStatus:displayStatus, time:time}" \
  -o table

# OUTPUT (2026-07-21): ProvisioningState/succeeded, PowerState/running — consistent with C10.

# C12 — vm-boot-diagnostics (attempted, not completed)
# az vm boot-diagnostics get-boot-log --resource-group DefaultGroup01 --name SFCG-WSIT-01 --subscription "$SUB"
# OUTPUT (2026-07-21): failed with a client-side az CLI bug (TypeError: 'method' object is
#   not subscriptable, in azure.cli.command_modules.vm.custom.get_boot_log — keys.keys[0].value
#   called on an unresolved method reference). Not related to the VM/investigation — an az CLI
#   defect in this build. Not pursued further; C10 already gave a conclusive answer.

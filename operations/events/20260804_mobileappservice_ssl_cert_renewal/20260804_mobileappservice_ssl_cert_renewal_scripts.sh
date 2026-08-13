#!/usr/bin/env bash
# Event: 20260804_mobileappservice_ssl_cert_renewal
# Commands are grouped by phase: Investigation / Audit / Remediation
# Subscription: Smart IT - Grido (0190fa7d-4ccf-4e3d-beb1-323b5780bfc8)

# === INVESTIGATION ===

# C1 — find NICs matching 'mobi' in DefaultGroup01 (initial uppercase 'MOBI' filter returned empty — resource names are lowercase)
az network nic list \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --resource-group DEFAULTGROUP01 \
  --query "[?contains(name, 'mobi')].{NIC:name, VM:virtualMachine.id, BackendPool:ipConfigurations[0].loadBalancerBackendAddressPools[0].id}" \
  -o table
# OUTPUT (2026-08-04):
# NIC              VM                                                   BackendPool
# sfcg-mobi-0110   (none — orphaned, no VM attached)
# sfcg-mobi-01421  .../virtualMachines/SFCG-MOBI-01                     .../loadBalancers/SFCG-MOBI-LB/backendAddressPools/SFCG-MOBI-LB-backendpool01
# sfcg-mobi-02639  .../virtualMachines/SFCG-MOBI-02                     .../loadBalancers/SFCG-MOBI-LB/backendAddressPools/SFCG-MOBI-LB-backendpool01

# C2 — LB rules for SFCG-MOBI-LB
az network lb rule list \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --resource-group DefaultGroup01 \
  --lb-name SFCG-MOBI-LB \
  -o table
# OUTPUT (2026-08-04):
# Name: SFCG-MOBI-LB-lbrule02, Protocol: Tcp, FrontendPort: 8043, BackendPort: 8043,
# LoadDistribution: SourceIPProtocol (session affinity by source IP — the "one to one" behavior), ProvisioningState: Succeeded
# Only one rule exists — no port 80 or 443 rule on this LB.

# C3 — backend health (attempted, not supported for this LB)
az network lb show-backend-health \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --resource-group DefaultGroup01 \
  --name SFCG-MOBI-LB \
  -o table
# OUTPUT (2026-08-04): 404 Not Found — backendHealth API not supported for this LB (likely Basic SKU). Not blocking, skipped.

# C4 — LB frontend IP configuration
az network lb frontend-ip list \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --resource-group DefaultGroup01 \
  --lb-name SFCG-MOBI-LB \
  -o table
# OUTPUT (2026-08-04): SFCG-MOBI-LB-frontendconfig01, Dynamic, Succeeded

# C5 — public IPs in the resource group matching 'mobi' or the known IP
az network public-ip list \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --resource-group DefaultGroup01 \
  --query "[?contains(name,'mobi') || contains(ipAddress,'20.121.19.174')].{Name:name, IP:ipAddress, AssociatedTo:ipConfiguration.id}" \
  -o table
# OUTPUT (2026-08-04): SFCG-MOBI-LB-publicip, 20.121.19.174, associated to SFCG-MOBI-LB frontendIPConfigurations/SFCG-MOBI-LB-frontendconfig01
# Confirms the LB (not either VM NIC directly) owns the public IP.

# C6 — DNS provider for the public domain
dig NS clubgrido.com.ar +short
dig mobileservice.clubgrido.com.ar +short
# OUTPUT (2026-08-04):
# NS: pdns07.domaincontrol.com., pdns08.domaincontrol.com.  (GoDaddy DNS)
# A: 20.121.19.174 (matches SFCG-MOBI-LB-publicip)

# C7 — current cert served on the public endpoint (issuer, validity, SANs)
echo | openssl s_client -connect mobileservice.clubgrido.com.ar:8043 \
  -servername mobileservice.clubgrido.com.ar 2>/dev/null \
  | openssl x509 -noout -issuer -subject -dates -serial
# OUTPUT (2026-08-04):
# issuer=C = US, O = Let's Encrypt, CN = E7
# subject=CN = mobileservice.clubgrido.com.ar
# notBefore=May 11 13:28:05 2026 GMT
# notAfter=Aug  9 13:28:04 2026 GMT   <-- 5 days from today, HIGH urgency
# serial=0622488DB0F4985889F2CAE8A570DAA3EC1B
# ECDSA P-256, single SAN (mobileservice.clubgrido.com.ar only), no existing automation evident

# === AUDIT ===

# === REMEDIATION ===

# C8 — capture old binding on SFCG-MOBI-01 before win-acme swaps it (rollback reference)
netsh http show sslcert ipport=0.0.0.0:8043
# OUTPUT (2026-08-04):
# Certificate Hash: 7e2b79194383fa97379640631fb1b077ad212da8
# Application ID: {4dc3e181-e14b-4a21-b022-59fc669b0914}
# Certificate Store Name: My
# Rollback if needed:
# netsh http delete sslcert ipport=0.0.0.0:8043
# netsh http add sslcert ipport=0.0.0.0:8043 certhash=7e2b79194383fa97379640631fb1b077ad212da8 appid='{4dc3e181-e14b-4a21-b022-59fc669b0914}' certstorename=My

# C9 — win-acme (wacs.exe, interactive) — attempted GoDaddy DNS-01, failed (Unauthorized/403 ACCESS_DENIED,
# account-level GoDaddy API restriction, confirmed via direct curl test). See investigation.md "Pivot" section.

# ⚠️ C10 — win-acme (wacs.exe, interactive), manual DNS-01, issues new cert and rebinds SFCG-MOBI-01
# site SmartLoyalty.MobileAppService, port 8043. Store: Cert:\LocalMachine\WebHosting.
# OUTPUT (2026-08-04): Certificate [Manual] mobileservice.clubgrido.com.ar created.
# New thumbprint 0FDAC0F3042B55C8B067DBEB0B9767365F022A2A, valid 2026-08-04 to 2026-11-02.
# Scheduled Task "win-acme renew" created, wacs.exe --renew, start 09:00 + 4h random delay,
# configured with a named user account (not SYSTEM default) — account not yet confirmed.
# Next renewal 2026-09-28 will fail unattended (manual validation) unless Azure DNS delegation lands first.

# C11 — capture old binding on SFCG-MOBI-02 before touching it (rollback reference)
netsh http show sslcert ipport=0.0.0.0:8043
# OUTPUT (2026-08-04):
# Certificate Hash: 7e2b79194383fa97379640631fb1b077ad212da8  (identical to SFCG-MOBI-01's old binding —
#   confirms the original cert+key was shared/manually duplicated across both VMs each cycle)
# Application ID: {4dc3e181-e14b-4a21-b022-59fc669b0914}
# Certificate Store Name: My
# Rollback if needed:
# netsh http delete sslcert ipport=0.0.0.0:8043
# netsh http add sslcert ipport=0.0.0.0:8043 certhash=7e2b79194383fa97379640631fb1b077ad212da8 appid='{4dc3e181-e14b-4a21-b022-59fc669b0914}' certstorename=My

# ⚠️ C12 — win-acme (wacs.exe, interactive), manual DNS-01, issues new cert and rebinds SFCG-MOBI-02
# site SmartLoyalty.MobileAppService, port 8043. Store: Cert:\LocalMachine\WebHosting.
# Export/import from -01 not viable — private key generated non-exportable by win-acme's store plugin.
# Scheduled Task start time set to 13:00 (staggered from -01's 09:00) to avoid same-window overlap;
# user account set to SYSTEM default this time.

# === INVESTIGATION (2026-08-05) — "scheduled task did not run, ran when I log in" report ===

# C13 — win-acme renew task: Principal, Triggers, TaskInfo, Settings (run first against -01, confirmed after the fact)
$task = Get-ScheduledTask -TaskName "win-acme renew*"
$task.Principal | Format-List UserId, LogonType, RunLevel
$task.Triggers | Format-List
Get-ScheduledTaskInfo -TaskName $task.TaskName | Format-List LastRunTime, LastTaskResult, NextRunTime
$task.Settings | Format-List StartWhenAvailable, MultipleInstances, DisallowStartIfOnBatteries
(Get-CimInstance Win32_OperatingSystem).LastBootUpTime
# OUTPUT (2026-08-05, SFCG-MOBI-01):
# UserId: SYSTEM, LogonType: ServiceAccount, RunLevel: Highest
# Trigger: StartBoundary 2026-08-04T09:00:00, DaysInterval 1, RandomDelay PT4H
# LastRunTime 2026-08-05 11:18:18, LastTaskResult 0, NextRunTime 2026-08-06
# StartWhenAvailable: True, MultipleInstances: IgnoreNew, DisallowStartIfOnBatteries: False
# LastBootUpTime: 2026-07-23 10:43:35 (13 days continuous uptime — rules out boot-catchup)

# C14 — Task Scheduler event log for this task, bounded by StartTime (unbounded query hangs — full-channel scan)
Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-TaskScheduler/Operational'; StartTime=(Get-Date '2026-08-04')} |
  Where-Object { $_.Message -match 'win-acme renew' } |
  Select-Object TimeCreated, Id, Message | Sort-Object TimeCreated
# OUTPUT (2026-08-05, SFCG-MOBI-01): event ID 107 at 2026-08-05 11:18:37 — "launched ... due to a time
# trigger condition" — confirms normal schedule-driven fire, not logon-triggered. 08-04 18:18:56 run
# (no ID 107) was win-acme's own post-setup test run, not the daily trigger.

# C15 — same diagnostic set repeated on SFCG-MOBI-02
# OUTPUT (2026-08-05, SFCG-MOBI-02):
# UserId: SYSTEM, LogonType: ServiceAccount (same as -01)
# Trigger: StartBoundary 2026-08-04T09:00:00, DaysInterval 1, RandomDelay PT4H (same as -01)
# LastRunTime 2026-08-05 11:53:53, LastTaskResult 0, NextRunTime 2026-08-06
# LastBootUpTime: 2026-08-05 11:50:39 — only 3m14s before LastRunTime: StartWhenAvailable catchup,
# VM was down through its scheduled window today.

# === AUDIT (2026-08-05) — why was SFCG-MOBI-02 down? ===

# C16 — Azure VM auto-shutdown schedules in DefaultGroup01
az resource list -g DefaultGroup01 --resource-type "Microsoft.DevTestLab/schedules" \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 -o table
# OUTPUT (2026-08-05): shutdown schedule resources exist for most of the fleet, including both
# SFCG-MOBI-01 and SFCG-MOBI-02 (plus WEBS-*, CLUB-*, JENKINS-01, SONARQUBE, SMTP-02, TO-01,
# WSIT-01, WSV2-01, sfvm20 — out of scope for this ticket).

# C17 — schedule detail for SFCG-MOBI-01 and SFCG-MOBI-02
az resource show -g DefaultGroup01 --resource-type "Microsoft.DevTestLab/schedules" \
  -n shutdown-computevm-SFCG-MOBI-01 --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 -o json
az resource show -g DefaultGroup01 --resource-type "Microsoft.DevTestLab/schedules" \
  -n shutdown-computevm-SFCG-MOBI-02 --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 -o json
# OUTPUT (2026-08-05):
# -01: status "Disabled" (dormant — explains 13-day uptime)
# -02: status "Enabled", dailyRecurrence.time "0100", timeZoneId "Argentina Standard Time",
#      createdDate 2023-04-28. Azure VM auto-shutdown has no built-in auto-start counterpart.

# C18 — searched Automation Accounts (sfcgautomation, SFCG-AUTOM) for a start-VM runbook targeting
# MOBI-02 — dead end, no match by name or script content (StartVM12/15/25, StopVM09/10/12/15/25 in
# sfcgautomation don't reference MOBI by name or parameter; job-schedule links pass no parameters).
# Not pursued further — see C19.

# C19 — Logic Apps across the subscription
az resource list --resource-type "Microsoft.Logic/workflows" \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 -o table
# OUTPUT (2026-08-05): Start_Mobile02_11AM (DefaultGroup01) — pairs with the 01:00 shutdown to
# restart SFCG-MOBI-02 daily around 11:00 ART. Same convention exists fleet-wide (Start_Mobi01_08AM,
# WEBS01_Start_09AM, CLUB01_START, etc.) — intentional design, not an oversight specific to -02.

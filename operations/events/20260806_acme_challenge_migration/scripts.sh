#!/usr/bin/env bash
# Event: 20260806_acme_challenge_migration (GITIN-1774)
# Commands are grouped by phase: Investigation / Audit / Remediation
# ⚠️ ACTION commands are clearly marked
# Subscription: Smart IT - Grido (0190fa7d-4ccf-4e3d-beb1-323b5780bfc8)

# === REMEDIATION ===

# ⚠️ C1 — create Azure DNS zone for the _acme-challenge subdomain (mobileservice only, scope for other hostnames not yet confirmed)
az network dns zone create \
  --name "_acme-challenge.mobileservice.clubgrido.com.ar" \
  --resource-group DefaultGroup01 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8
# OUTPUT (2026-08-06): zone created, numberOfRecordSets: 2 (default SOA/NS), zoneType: Public

# C2 — retrieve the Azure-assigned nameservers, needed for the GoDaddy NS delegation record
az network dns zone show \
  --name "_acme-challenge.mobileservice.clubgrido.com.ar" \
  --resource-group DefaultGroup01 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --query nameServers -o tsv
# OUTPUT (2026-08-06):
# ns1-01.azure-dns.com.
# ns2-01.azure-dns.net.
# ns3-01.azure-dns.org.
# ns4-01.azure-dns.info.

# --- MANUAL STEP (GoDaddy UI, not scriptable) ---
# Added NS record for host "_acme-challenge.mobileservice" with the 4 nameservers above.

# ⚠️ C3 — create Service Principal for win-acme's Azure DNS plugin (no --subscription: az ad is tenant-scoped, not subscription-scoped)
az ad sp create-for-rbac --name "winacme-mobileservice-dns" --skip-assignment
# OUTPUT (2026-08-06): appId 3cca7e2a-5b4a-4b0d-87ee-4390af90346f, tenant 33ee786b-c072-4326-8759-7be9b82e9801
# Client secret NOT recorded here — shown once by Azure, stored outside this repo.

# ⚠️ C4 — grant DNS Zone Contributor on the zone to that Service Principal
az role assignment create \
  --assignee "3cca7e2a-5b4a-4b0d-87ee-4390af90346f" \
  --role "DNS Zone Contributor" \
  --scope "/subscriptions/0190fa7d-4ccf-4e3d-beb1-323b5780bfc8/resourceGroups/defaultgroup01/providers/Microsoft.Network/dnszones/_acme-challenge.mobileservice.clubgrido.com.ar" \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8
# OUTPUT (2026-08-06): success, principalId 68f5c410-df61-4bd4-904a-9de056077e02, scope matches exactly

# === AUDIT ===

# C5 — confirm NS delegation is live and resolving
dig _acme-challenge.mobileservice.clubgrido.com.ar
# OUTPUT (2026-08-06): status: NOERROR, AUTHORITY section shows zone's own SOA from ns1-01.azure-dns.com.
# ANSWER: 0 (expected, no A record needed in this zone)

# === REMEDIATION (per-VM, repeated on SFCG-MOBI-01 and SFCG-MOBI-02) ===

# ⚠️ C6 — install win-acme's Azure DNS validation plugin (PowerShell, on each VM)
# First attempt used a guessed filename and got 404 — verified real name via GitHub API instead:
#   curl -s "https://api.github.com/repos/win-acme/win-acme/releases/tags/v2.2.9.1701" | grep -i azure
#   -> plugin.validation.dns.azure.v2.2.9.1701.zip
# cd C:\win-acme
# Invoke-WebRequest -Uri "https://github.com/win-acme/win-acme/releases/download/v2.2.9.1701/plugin.validation.dns.azure.v2.2.9.1701.zip" -OutFile "C:\win-acme\azure-dns-plugin.zip"
# Expand-Archive -Path "C:\win-acme\azure-dns-plugin.zip" -DestinationPath "C:\win-acme" -Force
# Get-ChildItem C:\win-acme -Recurse | Unblock-File

# ⚠️ C7 — wacs.exe interactive: Manage renewals (A) -> Edit (E) -> Validation (5) -> Azure DNS
# Menu path and prompts documented in operations/docs/mobileappservice_ssl_renewal_runbook.md section 5.4
# SFCG-MOBI-01: vault save = n (no reuse case on that VM)
# SFCG-MOBI-02: vault save = y, name "winacme-mobileservice-dns", comment describing scope/role
# Both: AzureCloud, no managed identity, tenant/appId as above, AzureSubscriptionId as above,
# AzureHostedZone "_acme-challenge.mobileservice.clubgrido.com.ar", scheduled task kept on SYSTEM

# === AUDIT (per-VM verification) ===

# C8 — confirm the scheduled task (unattended, not the interactive wizard run) completed successfully
# Task Scheduler Event Viewer output (SFCG-MOBI-01): "Task Scheduler successfully finished
#   ... for user NT AUTHORITY\SYSTEM"
# Same confirmed on SFCG-MOBI-02.

# C9 — confirm fresh certificate thumbprint on each VM
Get-ChildItem Cert:\LocalMachine\WebHosting | Where-Object { $_.Subject -like "*mobileservice*" } | Select-Object Thumbprint, NotBefore, NotAfter, Subject
# OUTPUT (2026-08-06):
# SFCG-MOBI-01: 059B73F29D2F2879FE3E5D5412D8BEAF638816DD, NotBefore 2026-08-06, NotAfter 2026-11-04
# SFCG-MOBI-02: 73C2B039A82297F091D6F3A2367B8C56F0A1B902, NotBefore 2026-08-06, NotAfter 2026-11-04

# C10 — public endpoint verification, through the LB (not bypassed)
echo | openssl s_client -connect mobileservice.clubgrido.com.ar:8043 -servername mobileservice.clubgrido.com.ar 2>/dev/null | openssl x509 -noout -issuer -subject -dates -serial
# OUTPUT (2026-08-06): notBefore/notAfter match SFCG-MOBI-02's cert exactly (session affinity routed here),
# issuer Let's Encrypt (YE2), confirms public endpoint serves the renewed certificate correctly.

#!/usr/bin/env bash
# GITIN-1771 — Automatizar SSL WebSite (gestion.clubgrido.com.ar / SFCG-WSIT-01)
# Commands executed 2026-09-22 during the off-hours window. win-acme's own wizard steps are
# interactive (RDP session on SFCG-WSIT-01) and not reproduced here as literal commands — see
# investigation.md for the full choice-by-choice sequence for both runs.

# === Precheck: Backend_WebSite trusted root certs before adding letsencrypt-isrg-root-x1 ===
az network application-gateway http-settings show \
  --gateway-name WAF_APPs --resource-group DefaultGroup01 \
  --name Backend_WebSite --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --query "trustedRootCertificates[].id" -o tsv
# OUTPUT: only 2023.gestion.clubgrido_CA present -> data/backend_website_root_certs_precheck.txt

# ⚠️ ACTION — add letsencrypt-isrg-root-x1 (already uploaded to the gateway from GITIN-1770)
az network application-gateway http-settings update \
  --gateway-name WAF_APPs --resource-group DefaultGroup01 \
  --name Backend_WebSite --root-certs 2023.gestion.clubgrido_CA letsencrypt-isrg-root-x1 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8
# OUTPUT: Succeeded, both certs present -> data/backend_website_rootcert_update_result.json

az network application-gateway show-backend-health \
  --name WAF_APPs --resource-group DefaultGroup01 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 -o json
# OUTPUT: Back_WebSite (192.168.50.131) Healthy -> data/backend_health_post_rootcert_update.json

# === Off-hours window: win-acme prep ===

# ⚠️ ACTION — new SP secret scoped to SFCG-WSIT-01 (--append mandatory, preserves every other
# VM's existing renewal)
az ad app credential reset --id 3cca7e2a-5b4a-4b0d-87ee-4390af90346f --append
# OUTPUT: new secret generated, not recorded in this repo (real credential — see CLAUDE.md rule).
# Saved in win-acme's local DPAPI vault on SFCG-WSIT-01 as "winacme-website-dns".

# win-acme + plugins install on SFCG-WSIT-01, PowerShell, portable install at C:\win-acme
# (matches MobileAppService/ClubSite AR convention -- NOTE: config/renewal data itself resolves
# separately, to C:\ProgramData\win-acme\acme-v02.api.letsencrypt.org\, per win-acme's own default
# BaseDirectory behavior, unrelated to where the exe is installed):
#
# New-Item -ItemType Directory -Force -Path C:\win-acme | Out-Null
# Invoke-WebRequest -Uri "https://github.com/win-acme/win-acme/releases/download/v2.2.9.1701/win-acme.v2.2.9.1701.x64.pluggable.zip" -OutFile "C:\win-acme\win-acme.zip"
# Expand-Archive -Path "C:\win-acme\win-acme.zip" -DestinationPath "C:\win-acme" -Force
# Get-ChildItem C:\win-acme -Recurse | Unblock-File
# (repeated for plugin.validation.dns.azure.v2.2.9.1701.zip and plugin.store.keyvault.v2.2.9.1701.zip)

# === Precheck: IIS binding scope on SFCG-WSIT-01, before running the wizard ===
# Get-WebBinding | Where-Object { $_.bindingInformation -like "*4430*" } | Select-Object protocol,bindingInformation,certificateHash,certificateStoreName
# OUTPUT: two bindings share one hash -- gestion.clubgrido.com.ar (site SmartLoyalty.WebSite) and
# a blank-hostname catch-all (site "DefaultAppPool"). -> data/sfcg_wsit01_webbinding_precheck.txt

# Get-Website "DefaultAppPool" | Select-Object Name, State, PhysicalPath, ApplicationPool
# OUTPUT: PhysicalPath D:\SmartLoyalty.WebSite -- same directory as the real site, not a separate
# app. Resolves the blank-hostname binding as safe to update alongside the real one.

# === win-acme Run 1 (public cert -> Key Vault) -- interactive wizard on SFCG-WSIT-01 ===
# Full choice sequence: Manual input -> gestion.clubgrido.com.ar -> separate cert per host ->
# Validation Azure DNS (AzureCloud, no MSI, tenant 33ee786b-..., client 3cca7e2a-...,
# secret typed+saved as "winacme-website-dns", zone _acme-challenge.gestion.clubgrido.com.ar) ->
# RSA key -> Store Key Vault (sfcg-waf-apps-kv, cert name gestion-clubgrido-com-ar) -> no
# additional store -> no installation step -> agreed ToS, email operaciones@smartfran.com.ar
# OUTPUT: DNS-01 validation succeeded after 1 retry (30s). Certificate issued and downloaded.
# "Store with KeyVault... Unauthorized" in the summary log -- FALSE ALARM, this is Key Vault's
# standard OAuth challenge/retry, not a real failure (verified via the full verbose log, see
# investigation.md). Certificate genuinely stored -- confirmed independently below.

az keyvault certificate show --vault-name sfcg-waf-apps-kv --name gestion-clubgrido-com-ar \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --query "{thumbprint: x509ThumbprintHex, notBefore: attributes.notBefore, expires: attributes.expires, enabled: attributes.enabled}" -o json
# OUTPUT: enabled=true, thumbprint B366BF5A972778D1C3908234BA0C8E83020C6181,
# valid 2026-09-22 to 2026-12-21 -> data/run1_keyvault_cert_verification.json

# ⚠️ ACTION — create gateway ssl-cert object referencing the versionless KV secret (so the
# gateway auto-picks up future renewals without a redeploy)
az network application-gateway ssl-cert create \
  --gateway-name WAF_APPs --resource-group DefaultGroup01 \
  --name gestion-clubgrido-com-ar-kv \
  --key-vault-secret-id "https://sfcg-waf-apps-kv.vault.azure.net/secrets/gestion-clubgrido-com-ar" \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8
# OUTPUT: Succeeded -> data/run1_gateway_listener_repoint.json

# ⚠️ ACTION — repoint the listener from the old direct-PFX cert (website_2024) to the new object
az network application-gateway http-listener update \
  --gateway-name WAF_APPs --resource-group DefaultGroup01 \
  --name Listener_WebSite_HTTPS --ssl-cert gestion-clubgrido-com-ar-kv \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8
# OUTPUT: Succeeded -> data/run1_gateway_listener_repoint.json

az network application-gateway show-backend-health \
  --name WAF_APPs --resource-group DefaultGroup01 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 -o json
# OUTPUT: Back_WebSite still Healthy -> data/backend_health_post_listener_repoint.json

# === win-acme Run 2 (backend-leg cert -> Windows Cert Store + IIS) -- interactive wizard ===
# Full choice sequence: Manual input -> gestion.clubgrido.com.ar -> separate cert per host ->
# Validation Azure DNS (reused saved secret "winacme-website-dns") -> Store Windows Certificate
# Store, [My] -> no additional store -> Installation: Create/update IIS bindings, site
# SmartLoyalty.WebSite -> no additional installation step.
# CRITICAL CHOICE: prompted "Existing renewal: [Manual] gestion.clubgrido.com.ar - Overwrite
# settings? (y*/n)" -- answered "n" (NOT the default), to keep this as a second, independent
# renewal entry rather than overwriting Run 1's Key Vault renewal config.
# OUTPUT: reused cached DNS-01 authorization (no new TXT round-trip). Certificate installed to
# My store + CA chain (YR2, Root YR). IIS binding gestion.clubgrido.com.ar:4430 updated.
# "Committing 1 https binding changes" -- literally one, verified below.

# Get-WebBinding | Where-Object { $_.bindingInformation -like "*4430*" } | Format-List protocol,bindingInformation,certificateHash,certificateStoreName
# OUTPUT: gestion.clubgrido.com.ar binding on new hash B366BF5A972778D1C3908234BA0C8E83020C6181;
# DefaultAppPool's blank-hostname binding still on the OLD hash -- contradicts the runbook's
# general "updates all bindings sharing the old hash" claim, corrected in
# operations/docs/waf_apps_cert_automation_runbook.md.

# ⚠️ ACTION — manually update the DefaultAppPool binding to match (same app, confirmed safe
# during the precheck above)
# Get-WebBinding -Name "DefaultAppPool" -Protocol https -Port 4430 | ForEach-Object { $_.AddSslCertificate("B366BF5A972778D1C3908234BA0C8E83020C6181", "My") }
# OUTPUT: both bindings now on the new hash, confirmed via Get-WebBinding re-check.

az network application-gateway show-backend-health \
  --name WAF_APPs --resource-group DefaultGroup01 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 -o json \
  > data/backend_health_final.json
# OUTPUT: Back_WebSite still Healthy -> data/backend_health_final.json. No disruption across
# either run.

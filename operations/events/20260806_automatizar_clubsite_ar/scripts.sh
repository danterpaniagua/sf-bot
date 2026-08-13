#!/usr/bin/env bash
# Event: 20260806_automatizar_clubsite_ar (GITIN-1770)
# Commands are grouped by phase: Investigation / Audit / Remediation
# ⚠️ ACTION commands are clearly marked
# Subscription: Smart IT - Grido (0190fa7d-4ccf-4e3d-beb1-323b5780bfc8)

# === INVESTIGATION ===

# C1 — listener -> certificate mapping for all WAF_APPs listeners (shared with 1769/1771)
az network application-gateway show --name WAF_APPs --resource-group DefaultGroup01 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 -o json \
  | jq '.httpListeners[] | {name, hostName, sslCertificate: .sslCertificate.id}'
# OUTPUT (2026-08-06): Listener_ClubSite_HTTPS (www.clubgrido.com.ar) -> clubgrido.2023.2024
# Listener_ClubSite_HTTPS_PY -> www.clubgrido.com.py_2026_v2, Listener_WebSite_HTTPS -> website_2024
# Confirms clubgrido.2023.2024 is live, not orphaned as initially guessed by name pattern.

# C2 — routing rules, to check HTTP-01 viability (does the HTTP listener route to a real backend or just redirect?)
az network application-gateway show --name WAF_APPs --resource-group DefaultGroup01 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 -o json \
  | jq '.requestRoutingRules[] | {name, listener: .httpListener.id, redirectConfig: .redirectConfiguration.id, backendPool: .backendAddressPool.id, backendSettings: .backendHttpSettings.id}'
# OUTPUT (2026-08-06): Rule_Clubsite_HTTP_AR has redirectConfig set, backendPool: null — pure
# HTTP->HTTPS redirect, no real backend. HTTP-01 ruled out for AR (and PY, same pattern).

# C3 — check for existing Key Vaults reusable for this purpose
az keyvault list --resource-group DefaultGroup01 --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 -o table
az keyvault list --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 -o table
# OUTPUT (2026-08-06): two existing vaults found, both unrelated (SmartFran-Cloud-KV-Dev in a
# different project/RG; MigracionSRVAD7838kv in a different region/RG) — neither reused, new vault created (C4).

# C4 — check WAF_APPs current managed identity
az network application-gateway show --name WAF_APPs --resource-group DefaultGroup01 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 --query identity -o json
# OUTPUT (2026-08-06): null — no identity existed before this ticket.

# === REMEDIATION ===

# ⚠️ C5 — create purpose-specific Key Vault, RBAC authorization model
az keyvault create \
  --name sfcg-waf-apps-kv \
  --resource-group DefaultGroup01 \
  --location eastus \
  --enable-rbac-authorization true \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8
# OUTPUT (2026-08-06): created successfully, enableRbacAuthorization: true, vaultUri:
# https://sfcg-waf-apps-kv.vault.azure.net/

# ⚠️ C6 — create User-Assigned Managed Identity for the gateway to read Key Vault secrets
az identity create \
  --name waf-apps-kv-identity \
  --resource-group DefaultGroup01 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8
# OUTPUT (2026-08-06): principalId 023f97a9-075c-4755-93cd-31d440bbafe6, clientId 976ab98d-57af-453e-b898-a9f3d3f39205

# ⚠️ C7 — attach that identity to the Application Gateway
# First attempt used wrong flag (--identities, plural, and just the name) — corrected to --identity
# (singular) with the full resource ID, per the CLI's own error/help text.
az network application-gateway identity assign \
  --gateway-name WAF_APPs \
  --resource-group DefaultGroup01 \
  --identity /subscriptions/0190fa7d-4ccf-4e3d-beb1-323b5780bfc8/resourcegroups/DefaultGroup01/providers/Microsoft.ManagedIdentity/userAssignedIdentities/waf-apps-kv-identity \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8
# OUTPUT (2026-08-06): confirmed via a follow-up `az network application-gateway show` — identity
# block now shows waf-apps-kv-identity attached correctly.

# ⚠️ C8 — grant that identity read access to the new Key Vault
az role assignment create \
  --assignee "023f97a9-075c-4755-93cd-31d440bbafe6" \
  --role "Key Vault Secrets User" \
  --scope "/subscriptions/0190fa7d-4ccf-4e3d-beb1-323b5780bfc8/resourceGroups/DefaultGroup01/providers/Microsoft.KeyVault/vaults/sfcg-waf-apps-kv" \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8
# OUTPUT (2026-08-07): success. roleDefinitionId 4633458b-17de-408a-b874-0445c86b69e6 (Key Vault
# Secrets User), principalId and scope match exactly.

# ⚠️ C9 — create Azure DNS zone for this hostname's ACME challenge
az network dns zone create \
  --name "_acme-challenge.www.clubgrido.com.ar" \
  --resource-group DefaultGroup01 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8

az network dns zone show \
  --name "_acme-challenge.www.clubgrido.com.ar" \
  --resource-group DefaultGroup01 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --query nameServers -o tsv
# OUTPUT (2026-08-06): created successfully. Nameservers: ns1-03.azure-dns.com., ns2-03.azure-dns.net.,
# ns3-03.azure-dns.org., ns4-03.azure-dns.info. (different server set than the Mobile zone's, as expected
# for a separate zone). First attempt at this command failed with "argument --resource-group/-g: expected
# one argument" because $RG/$ZONE/$SUBSCRIPTION exports from an earlier message weren't present in the
# shell that ran it — fixed by inlining the literal values instead of relying on prior exports.

# ⚠️ C10 — grant the existing win-acme Service Principal DNS Zone Contributor on this new zone
# (reusing the SP created for GITIN-1774, appId 3cca7e2a-5b4a-4b0d-87ee-4390af90346f — new role
# assignment scoped to this new zone, existing assignment on the Mobile zone is untouched)
az role assignment create \
  --assignee "3cca7e2a-5b4a-4b0d-87ee-4390af90346f" \
  --role "DNS Zone Contributor" \
  --scope "/subscriptions/0190fa7d-4ccf-4e3d-beb1-323b5780bfc8/resourceGroups/DefaultGroup01/providers/Microsoft.Network/dnszones/_acme-challenge.www.clubgrido.com.ar" \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8
# OUTPUT: pending.

# --- MANUAL STEP (GoDaddy UI) ---
# Added NS record for host "_acme-challenge.www" under clubgrido.com.ar, pointing to the
# nameservers from C9. Confirmed resolving via dig (AUTHORITY section shows the zone's own SOA).
# Also fixed a pre-existing wrong NS record on the MobileAppService zone in the same session
# (ns2 had "azure-dns.com" instead of "azure-dns.net" — copy-paste slip, unrelated to this ticket
# but caught while adding these records).

# === win-acme install on SFCG-CLUB-01 ===
# Base build + Azure DNS plugin (same as GITIN-1774) + Key Vault store plugin (new — filename
# confirmed via GitHub API, not guessed: plugin.store.keyvault.v2.2.9.1701.zip)

# C11 — first certificate attempt failed: AADSTS7000215 "Invalid client secret provided" —
# the secret's ID was entered instead of its value. Found via win-acme's own log file
# (C:\ProgramData\win-acme\acme-v02.api.letsencrypt.org\Log\log-*.txt), not assumed to be
# RBAC propagation delay despite the error surfacing right after a role assignment.

# ⚠️ C12 — add a new client secret to the existing app registration WITHOUT invalidating the
# original (which SFCG-MOBI-01/02's working renewals still use) — --append is the key flag.
az ad app credential reset --id 3cca7e2a-5b4a-4b0d-87ee-4390af90346f --append
# OUTPUT: new secret value generated, not recorded in this repo.

# ⚠️ C13 — grant the SP write access to the Key Vault (missing permission found before it
# caused a second failed run, not after)
az role assignment create \
  --assignee "3cca7e2a-5b4a-4b0d-87ee-4390af90346f" \
  --role "Key Vault Certificates Officer" \
  --scope "/subscriptions/0190fa7d-4ccf-4e3d-beb1-323b5780bfc8/resourceGroups/DefaultGroup01/providers/Microsoft.KeyVault/vaults/sfcg-waf-apps-kv" \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8
# OUTPUT (2026-08-07): success, principalId 68f5c410-df61-4bd4-904a-9de056077e02, scope matches.

# C14 — second attempt, with correct secret + KV write permission: SUCCESS.
# "Certificate [Manual] www.clubgrido.com.ar created" — RSA 3072-bit, imported to
# https://sfcg-waf-apps-kv.vault.azure.net/certificates/www-clubgrido-com-ar/c4c8b43fee694817b49d795cf24524ed,
# ~3 month validity. Scheduled Task created (SYSTEM), next renewal check after 2026/10/1.
# Note: a 401 Unauthorized appeared in the log immediately before the successful 200 OK import —
# this is Key Vault's standard OAuth challenge-response handshake (unauthenticated probe discovers
# the auth endpoint via WWW-Authenticate, client retries with a real token), not an error.

# C15 — attempted self-verification via CLI, got Forbidden — the identity running az cli has no
# data-plane role on this RBAC-mode vault (creating a vault grants no automatic access to the
# creator). Not pursued further this session since win-acme's own log already confirmed success.
az keyvault certificate show --vault-name sfcg-waf-apps-kv --name www-clubgrido-com-ar \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --query "{thumbprint: x509ThumbprintHex, notBefore: attributes.notBefore, expires: attributes.expires, enabled: attributes.enabled}" -o json
# OUTPUT: 403 Forbidden, ForbiddenByRbac — expected given no role assignment for this caller yet.

# === REMEDIATION: backend trust-chain fix (Gateway->Backend leg, critical finding) ===
# SFCG-CLUB-01 backend cert (Let's Encrypt, from the IIS-binding automation below) is untrusted
# by Backend_ClubSite's HTTP settings (trustedRootCertificates only lists clubsite_CA, the old
# GoDaddy chain) -> confirmed Unhealthy via show-backend-health. Uploading the LE chain as
# trusted roots so the gateway accepts it.

# ⚠️ C16 — upload Let's Encrypt intermediate (YR1)
az network application-gateway root-cert create \
  --gateway-name WAF_APPs --resource-group DefaultGroup01 \
  --name letsencrypt-yr1 --cert-file "yr1-intermediate.cer" \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8
# OUTPUT (2026-08-07): FAILED — ApplicationGatewayTrustedRootCertificateInvalidData.

# ⚠️ C17 — upload Let's Encrypt cross-signed root (Root YR)
az network application-gateway root-cert create \
  --gateway-name WAF_APPs --resource-group DefaultGroup01 \
  --name letsencrypt-root-yr --cert-file "root-yr.cer" \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8
# OUTPUT (2026-08-07): FAILED — ApplicationGatewayTrustedRootCertificateInvalidData.

# ⚠️ C18 — upload ISRG Root X1 (true self-signed root)
az network application-gateway root-cert create \
  --gateway-name WAF_APPs --resource-group DefaultGroup01 \
  --name letsencrypt-isrg-root-x1 --cert-file "isrg-root-x1.cer" \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8
# OUTPUT (2026-08-07): SUCCESS — confirmed via `az network application-gateway show`, object
# letsencrypt-isrg-root-x1 present under trustedRootCertificates.

# Diagnosis: C16/C17's files were exported from SFCG-CLUB-01's local cert store via PowerShell's
# Export-Certificate, which defaults to binary DER — rejected by the API as invalid data. C18's
# file came from a different source and was already base64-encoded, hence the success. Fix:
# re-encode C16/C17's files to base64/PEM on SFCG-CLUB-01 before retrying.

# C19 — re-encoded both files to base64/PEM (openssl locally, certutil -encode on
# SFCG-CLUB-01 independently — same result) and retried C16/C17. IDENTICAL failure
# (ApplicationGatewayTrustedRootCertificateInvalidData) — rules out format as the cause.

# C20 — local diagnosis: inspect actual cert contents to find the real difference
for f in isrg-root-x1.cer yr1-intermediate.cer root-yr.cer; do
  openssl x509 -inform DER -in "$f" -noout -subject -issuer -dates -text
done
# OUTPUT (2026-08-07): isrg-root-x1.cer is self-signed (Issuer = Subject = "ISRG Root X1").
# yr1-intermediate.cer (Subject "Let's Encrypt YR1", Issuer "Root YR") and root-yr.cer
# (Subject "ISRG Root YR", Issuer "ISRG Root X1") are both intermediates, not self-signed.
# Conclusion: Application Gateway's trustedRootCertificates only accepts the self-signed
# root — intermediates must be served by the backend's own TLS chain, not uploaded here.
# No further root-cert create needed for yr1/root-yr; letsencrypt-isrg-root-x1 alone is
# the correct (and only) object to attach to Backend_ClubSite.

# ⚠️ C21 — attach the self-signed root to Backend_ClubSite (keep clubsite_CA too)
az network application-gateway http-settings update \
  --gateway-name WAF_APPs --resource-group DefaultGroup01 \
  --name Backend_ClubSite \
  --root-certs clubsite_CA letsencrypt-isrg-root-x1 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8
# OUTPUT (2026-08-07): SUCCESS — trustedRootCertificates now lists both objects.

# C22 — re-check backend health
az network application-gateway show-backend-health \
  --name WAF_APPs --resource-group DefaultGroup01 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 -o json
# OUTPUT (2026-08-07): SFCG-CLUB-01 (192.168.50.121) and SFCG-CLUB-02 (192.168.50.122) both
# Healthy in Back_ClubSite (HTTP 200 probe). Back_ClubSite_PY/Back_WebSite unaffected.
# Confirms fix: self-signed root alone was sufficient, IIS already serves the YR1
# intermediate correctly. Backend trust-chain break resolved, full redundancy restored.

# === SFCG-CLUB-02: backend certificate, independent issuance ===
# win-acme base + Azure DNS validation plugin only (no Key Vault store plugin needed here).

# C23 — win-acme's local vault on SFCG-CLUB-01 can't be reused (DPAPI-encrypted, per-machine,
# no cross-VM sync) — new secret added to the same app registration.
# ⚠️
az ad app credential reset --id 3cca7e2a-5b4a-4b0d-87ee-4390af90346f --append
# OUTPUT: new secret value generated, not recorded in this repo. Saved in win-acme's local
# vault on SFCG-CLUB-02 as "winacme-clubsite-ar-dns".

# C24 — win-acme wizard on SFCG-CLUB-02: Source manual (www.clubgrido.com.ar, separate cert
# per host to exclude www.clubgrido.com.py), Validation Azure DNS (same zone
# _acme-challenge.www.clubgrido.com.ar), RSA key, Store Windows Certificate Store (My),
# Installation IIS binding (SmartLoyalty.ClubSite).
# OUTPUT (2026-08-07): SUCCESS — "Certificate [Manual] www.clubgrido.com.ar created", issued
# via Let's Encrypt intermediate YR2 (sibling of -01's YR1, same Root YR -> ISRG Root X1
# chain). win-acme imported YR2 and Root YR into the local CA store. IIS binding updated for
# www.clubgrido.com.ar only (new hash 2DDBE702E6961B89FC97E9B834EDF23C8E6CB55A), PY/default
# binding untouched (0BB9D0CB...). Scheduled Task created (SYSTEM), next renewal after 2026/10/1.

# C25 — verify new binding locally
Get-WebBinding | Where-Object { $_.bindingInformation -like "*443*" } | Format-List protocol,bindingInformation,certificateHash,certificateStoreName
# OUTPUT (2026-08-07): www.clubgrido.com.ar -> 2DDBE702E6961B89FC97E9B834EDF23C8E6CB55A (new).
# PY/default -> 0BB9D0CBDB426A421C162EE71B59A39F4A43DBB9 (unchanged). Scoping confirmed safe.

# C26 — re-check backend health
az network application-gateway show-backend-health \
  --name WAF_APPs --resource-group DefaultGroup01 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 -o json
# OUTPUT (2026-08-07): SFCG-CLUB-02 (192.168.50.122) Healthy in Back_ClubSite, alongside
# SFCG-CLUB-01. Confirms letsencrypt-isrg-root-x1 alone is sufficient regardless of which
# sibling intermediate (YR1/YR2) issued the leaf cert. Backend automation complete on both nodes.

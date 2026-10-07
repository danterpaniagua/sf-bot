#!/usr/bin/env bash
# Event: 20260806_automatizar_clubsite_py
# Commands are grouped by phase: Investigation / Audit / Remediation
# ⚠️ ACTION commands are clearly marked

# === REMEDIATION ===

# ⚠️ C1 — create Azure DNS zone for the _acme-challenge subdomain (same pattern as GITIN-1774/GITIN-1770)
az network dns zone create \
  --name "_acme-challenge.www.clubgrido.com.py" \
  --resource-group DefaultGroup01 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  > operations/events/20260806_automatizar_clubsite_py/data/dns_zone_create.json
# OUTPUT (2026-09-01): zone created, numberOfRecordSets: 2 (default SOA/NS), zoneType: Public

# C2 — retrieve the Azure-assigned nameservers, needed for the NS delegation request to IT Grido
az network dns zone show \
  --name "_acme-challenge.www.clubgrido.com.py" \
  --resource-group DefaultGroup01 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --query nameServers -o tsv \
  > operations/events/20260806_automatizar_clubsite_py/data/dns_zone_nameservers.txt
# OUTPUT (2026-09-01):
# ns1-07.azure-dns.com.
# ns2-07.azure-dns.net.
# ns3-07.azure-dns.org.
# ns4-07.azure-dns.info.

# ⚠️ C3 — grant the existing win-acme Service Principal DNS Zone Contributor on this zone
# (reusing the SP created for GITIN-1774, appId 3cca7e2a-5b4a-4b0d-87ee-4390af90346f — same SP
# used for GITIN-1770's AR zone, new role assignment scoped only to this PY zone)
az role assignment create \
  --assignee "3cca7e2a-5b4a-4b0d-87ee-4390af90346f" \
  --role "DNS Zone Contributor" \
  --scope "/subscriptions/0190fa7d-4ccf-4e3d-beb1-323b5780bfc8/resourceGroups/DefaultGroup01/providers/Microsoft.Network/dnszones/_acme-challenge.www.clubgrido.com.py" \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  > operations/events/20260806_automatizar_clubsite_py/data/role_assignment_create.json
# OUTPUT (2026-09-09): created successfully. roleDefinitionId befefa01-2a29-4197-83a8-272ff33ce314
# (DNS Zone Contributor), principalId 68f5c410-df61-4bd4-904a-9de056077e02, scope confirmed as the
# PY zone only.

# === INVESTIGATION — why Backend_ClubSite_PY.trustedRootCertificates is null (vs AR's clubsite_CA pre-fix) ===

# C4a — quick reachability check to the backend VNet (fails fast, 5s, instead of the TCP blackhole
# hang seen when openssl s_client is run directly against 192.168.50.x from outside that network)
for ip in 192.168.50.121 192.168.50.122; do
  echo "=== $ip:443 ===" >> operations/events/20260806_automatizar_clubsite_py/data/backend_reachability_check.txt
  timeout 5 bash -c "echo > /dev/tcp/$ip/443" \
    && echo "reachable" >> operations/events/20260806_automatizar_clubsite_py/data/backend_reachability_check.txt \
    || echo "NOT reachable (timeout/refused)" >> operations/events/20260806_automatizar_clubsite_py/data/backend_reachability_check.txt
done

# C4 — what certificate chain does the PY backend actually present over TLS (SNI-specific)?
# Same physical servers as AR (Back_ClubSite_PY shares 192.168.50.121/.122), so the only variable
# is which cert IIS serves for this specific hostname binding.
# -connect_timeout added so a blocked path fails fast instead of hanging indefinitely.
openssl s_client -connect 192.168.50.121:443 -connect_timeout 5 -servername www.clubgrido.com.py -showcerts </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates \
  > operations/events/20260806_automatizar_clubsite_py/data/py_backend_cert_chain_check.txt

# C5 — same check against .122, in case the two nodes serve different certs (shouldn't, but confirm not assume)
openssl s_client -connect 192.168.50.122:443 -connect_timeout 5 -servername www.clubgrido.com.py -showcerts </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates \
  >> operations/events/20260806_automatizar_clubsite_py/data/py_backend_cert_chain_check.txt

# C6 — same check for AR's hostname on the same servers, for a direct side-by-side comparison
openssl s_client -connect 192.168.50.121:443 -connect_timeout 5 -servername www.clubgrido.com.ar -showcerts </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates \
  > operations/events/20260806_automatizar_clubsite_py/data/ar_backend_cert_chain_check.txt

# C7 — list the gateway's registered trusted-root objects (names only, to identify what clubsite_CA is)
az network application-gateway show \
  --name WAF_APPs --resource-group DefaultGroup01 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --query "trustedRootCertificates[].name" -o tsv \
  > operations/events/20260806_automatizar_clubsite_py/data/gateway_trusted_root_names.txt
# OUTPUT (2026-09-09):
# clubsite_CA
# www.ca.py
# 2023.gestion.clubgrido_CA
# clubgrido_PY_2024_CA_ROOT
# letsencrypt-isrg-root-x1
# Two PY-specific objects exist (www.ca.py, clubgrido_PY_2024_CA_ROOT) but neither is attached to
# Backend_ClubSite_PY (trustedRootCertificates confirmed null) — candidates for either an orphaned
# upload (like the 6 orphaned PFX certs found earlier) or a stale/unused reference. Still need the
# actual backend cert's issuer (blocked on network access to 192.168.50.x — see C4a) to tell which.

# === INVESTIGATION (continued) — run locally on SFCG-CLUB-01/.02 via RDP/PowerShell, remote
# openssl from outside the 192.168.50.x VNet did not work. VM runs Windows/IIS.

# C8 — confirm current HTTPS bindings and their cert hash/store
Get-WebBinding | Where-Object { $_.bindingInformation -like "*443*" } | Format-List protocol,bindingInformation,certificateHash,certificateStoreName
# OUTPUT (2026-09-09, SFCG-CLUB-01): default (*:443:) and www.clubgrido.com.py both on hash
# 0BB9D0CBDB426A421C162EE71B59A39F4A43DBB9, store My (unchanged since GITIN-1770's C25 check on
# 2026-08-07). www.clubgrido.com.ar now on CAD38F9746AAC0363FCE7C668D50520272E77E13, store
# WebHosting (the new Let's Encrypt cert from GITIN-1770's backend remediation) -- confirms the
# two hostnames are on genuinely different certs/stores, not shared.

# C9 — pull the PY binding's leaf cert Subject/Issuer directly
Get-ChildItem "Cert:\LocalMachine\My\0BB9D0CBDB426A421C162EE71B59A39F4A43DBB9" | Select-Object Subject, Issuer, NotBefore, NotAfter | Format-List

# C10 — build and inspect the FULL chain for that cert (leaf -> intermediate(s) -> root), to see
# whether the root is a well-known public CA (would explain null trustedRootCertificates working)
# or something else
$cert = Get-ChildItem "Cert:\LocalMachine\My\0BB9D0CBDB426A421C162EE71B59A39F4A43DBB9"
$chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
$chain.Build($cert) | Out-Null
$chain.ChainElements | ForEach-Object { $_.Certificate } | Select-Object Subject, Issuer, Thumbprint | Format-List
# OUTPUT (2026-09-09, SFCG-CLUB-01): leaf CN=www.clubgrido.com.py, issuer YE2/Let's Encrypt,
# NotBefore 6/17/2026, NotAfter 9/15/2026 (6 days from today). Full chain: leaf -> YE2 -> Root YE
# -> ISRG Root X2 -> ISRG Root X1 (self-signed). ANSWERS the trustedRootCertificates:null question:
# the backend cert already chains to ISRG Root X1, a well-known public CA that Azure App Gateway v2
# trusts by default when no explicit trustedRootCertificates is set -- no gap, no orphaned-object
# mystery. www.ca.py/clubgrido_PY_2024_CA_ROOT (C7) are unrelated/unused for this binding.
# URGENT, separate from the above: this cert predates the GITIN-1768 epic entirely (NotBefore
# 6/17/2026, before GITIN-1774 started 2026-08-06) -- not issued by any automation this project
# has set up. Expires in 6 days. Whether anything currently auto-renews it is UNCONFIRMED -- check
# for a win-acme scheduled task next (C11) before assuming either way.

# C11 — check for an existing win-acme scheduled task/renewal covering this hostname, before
# assuming the 9/15 expiry is unmanaged
Get-ScheduledTask | Where-Object { $_.TaskName -like "*win-acme*" -or $_.TaskName -like "*wacs*" } | Select-Object TaskName, State
# OUTPUT (2026-09-09, SFCG-CLUB-01): task "win-acme renew (acme-v02.api.letsencrypt.org)" exists,
# State: Ready. This task is VM-wide (runs ALL configured renewals when triggered), not proof by
# itself that www.clubgrido.com.py specifically is among them -- verify against the actual
# renewal configs next (C12), don't infer from the task's mere existence.

# C12 — list win-acme's actual renewal configs on this host, to confirm (not infer) whether
# www.clubgrido.com.py is actually covered
Get-ChildItem "C:\ProgramData\win-acme\acme-v02.api.letsencrypt.org\Renewals\*.renewal.json" | ForEach-Object {
  $j = Get-Content $_.FullName -Raw | ConvertFrom-Json
  [PSCustomObject]@{ File = $_.Name; FriendlyName = $j.LastFriendlyName; Renewal = $j.Date }
} | Format-Table -AutoSize
# OUTPUT (2026-09-09, SFCG-CLUB-01): path does not exist -- C:\ProgramData\win-acme\... isn't
# where this install keeps its data. Base folder location not yet confirmed. See C12b.

# C12b — locate win-acme's actual base/config folder on this host (don't assume ProgramData;
# could be under the SYSTEM profile's AppData, or a custom --configpath used at install time)
Get-ChildItem "C:\ProgramData\win-acme" -ErrorAction SilentlyContinue
Get-ChildItem "C:\Windows\System32\config\systemprofile\AppData\Roaming\win-acme" -Recurse -ErrorAction SilentlyContinue | Select-Object FullName
Get-ChildItem "C:\Windows\System32\config\systemprofile\AppData\Local\win-acme" -Recurse -ErrorAction SilentlyContinue | Select-Object FullName
# Fallback if neither exists: find wacs.exe itself and ask it directly
Get-ChildItem -Path C:\ -Filter "wacs.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object FullName
# OUTPUT (2026-09-09, SFCG-CLUB-01): install found at C:\win-acme (portable-mode install, not
# ProgramData/registry-registered -- confirms why the ProgramData path in C11/C12 didn't exist).

# C12c — list win-acme's renewal configs directly under its own install folder (portable-mode
# installs commonly keep config alongside the exe rather than in ProgramData)
Get-ChildItem "C:\win-acme" -Recurse -Filter "*.renewal.json" -ErrorAction SilentlyContinue | ForEach-Object {
  $j = Get-Content $_.FullName -Raw | ConvertFrom-Json
  [PSCustomObject]@{ File = $_.Name; FriendlyName = $j.LastFriendlyName; Renewal = $j.Date }
} | Format-Table -AutoSize
# If that returns nothing, list the whole tree to find where config actually lives:
# Get-ChildItem "C:\win-acme" -Recurse -Directory | Select-Object FullName
# OUTPUT (2026-09-09, SFCG-CLUB-01): no renewal.json under C:\win-acme. Only subfolder is
# C:\win-acme\Scripts -- this is likely just the exe's working directory (holding IIS
# install-hook scripts), not win-acme's actual BaseDirectory/config path.

# C12d — read the scheduled task's real command/arguments directly, instead of guessing more
# candidate paths -- settles where config lives and whether --configpath is customized
Get-ScheduledTask -TaskName "win-acme renew (acme-v02.api.letsencrypt.org)" | Select-Object -ExpandProperty Actions | Select-Object Execute, Arguments, WorkingDirectory
# OUTPUT (2026-09-09, SFCG-CLUB-01): Execute C:\win-acme\wacs.exe, Arguments "--renew --baseuri
# https://acme-v02.api.letsencrypt.org/", WorkingDirectory C:\win-acme. No --configpath flag --
# config path comes from win-acme's default resolution (identity-dependent) or a local
# settings.json override, neither confirmed yet. See C12e.

# C12e — confirm the identity the task runs as (default config path differs: ProgramData if
# elevated/SYSTEM, AppData\Roaming of the running user otherwise) and check for a settings.json
# override in win-acme's own folder
(Get-ScheduledTask -TaskName "win-acme renew (acme-v02.api.letsencrypt.org)").Principal | Select-Object UserId, RunLevel, LogonType
Get-Content "C:\win-acme\settings.json" -Raw -ErrorAction SilentlyContinue
# OUTPUT (2026-09-09, SFCG-CLUB-01): UserId SYSTEM, RunLevel Highest, LogonType ServiceAccount --
# elevated. settings.json Client.ConfigurationPath is null (no override). Per win-acme's own
# default resolution, null + elevated/SYSTEM => %ProgramData%\win-acme\<baseuri>, i.e. the exact
# path C11/C12 already tried and got "does not exist" for. Inconsistent -- recheck the base
# folder directly (not the deeper \Renewals path) before concluding anything, in case it's
# hidden/ACL-restricted rather than genuinely absent.

# C12f — recheck C:\ProgramData\win-acme itself (base folder, -Force for hidden items) since the
# default-path logic says it should exist here
Get-ChildItem "C:\ProgramData" -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*win-acme*" -or $_.Name -like "*wacs*" }
Get-ChildItem "C:\ProgramData\win-acme" -Force -Recurse -ErrorAction SilentlyContinue | Select-Object FullName
# OUTPUT (2026-09-09, SFCG-CLUB-01): base folder confirmed at
# C:\ProgramData\win-acme\acme-v02.api.letsencrypt.org (created 8/7/2026, matches GITIN-1770's
# backend-cert work timeline). C11/C12's earlier "does not exist" error was due to assuming a
# \Renewals subfolder that doesn't exist in this win-acme version -- .renewal.json files sit
# directly under the baseuri folder. Exactly ONE renewal file exists:
# SwTuz4cBaEqYqmX6WK7cCw.renewal.json -- one file for two possible certs (AR/PY) strongly
# suggests it only covers AR, not PY. Confirm which hostname next (C12g), don't assume.

# C12g — read the one renewal config's target hostname directly
Get-Content "C:\ProgramData\win-acme\acme-v02.api.letsencrypt.org\SwTuz4cBaEqYqmX6WK7cCw.renewal.json" -Raw \
  | ConvertFrom-Json | Select-Object -ExpandProperty TargetPluginOptions | Select-Object CommonName, AlternativeNames
# OUTPUT (2026-09-09, SFCG-CLUB-01): CommonName www.clubgrido.com.ar, AlternativeNames
# {www.clubgrido.com.ar}. CONFIRMED: the one renewal config on this host covers AR only. PY's
# backend cert (0BB9D0CB..., expires 2026-09-15) has NO automated renewal on SFCG-CLUB-01. The
# "task exists because AR/PY share the VM" hypothesis is disproven -- the task is real but only
# acts on AR's renewal object. URGENT: 6 days to expiry, unmanaged.

# === REMEDIATION — PY win-acme wizard prep ===

# C13 — confirm the SP still has Key Vault Certificates Officer on the shared vault (granted
# vault-wide during GITIN-1770's C13, should already cover PY -- confirm, don't assume, per the
# same "find it before it causes a failed run" lesson from AR's first attempt)
az role assignment list \
  --assignee "3cca7e2a-5b4a-4b0d-87ee-4390af90346f" \
  --scope "/subscriptions/0190fa7d-4ccf-4e3d-beb1-323b5780bfc8/resourceGroups/DefaultGroup01/providers/Microsoft.KeyVault/vaults/sfcg-waf-apps-kv" \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --query "[].roleDefinitionName" -o tsv \
  > operations/events/20260806_automatizar_clubsite_py/data/sp_keyvault_role_check.txt
# OUTPUT (2026-09-09): "Key Vault Certificates Officer" -- already granted vault-wide from
# GITIN-1770, confirmed covering PY, no gap.

# C14 — win-acme wizard run on SFCG-CLUB-01 (interactive, full transcript in
# data/py_backend_winacme_wizard_output.txt): Manual source www.clubgrido.com.py, Single cert,
# Azure DNS validation (reused vault credential winacme-clubsitear-dns), RSA key, dual store
# (Key Vault sfcg-waf-apps-kv/www-clubgrido-com-py + Windows Cert Store My), IIS installation
# on SmartLoyalty.ClubSite.
# OUTPUT (2026-09-09): DNS-01 validation succeeded (1 retry, normal propagation delay).
# CertificateStore step fully succeeded: installed in store My, IIS binding
# "www.clubgrido.com.py:443" updated (1 binding changed -- confirms the default/no-SNI binding
# was NOT touched, as intended). Renewal added, next due 2026/11/3, backend-cert urgency resolved
# assuming this holds. KeyVault step 1/2 showed only "[HTTP] Request completed with status
# Unauthorized" with no confirming success line after it (unlike GITIN-1770's log, which showed
# a 401-then-200 pair) -- AMBIGUOUS, not assumed successful. Verify directly (C15). Separately,
# the gateway's public listener (Listener_ClubSite_HTTPS_PY) still references the old PFX object
# www.clubgrido.com.py_2026_v2, NOT this new Key Vault secret -- this run didn't touch the
# listener; migrating it is a separate still-pending step regardless of C15's outcome.

# C15 — verify whether the Key Vault upload actually succeeded, don't trust the ambiguous log line
az keyvault certificate show --vault-name sfcg-waf-apps-kv --name www-clubgrido-com-py \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --query "{thumbprint: x509ThumbprintHex, notBefore: attributes.notBefore, expires: attributes.expires, enabled: attributes.enabled}" -o json \
  > operations/events/20260806_automatizar_clubsite_py/data/py_keyvault_cert_check.json
# OUTPUT (2026-09-09): enabled true, notBefore 2026-09-09, expires 2026-12-08, thumbprint
# AEB418D0B53C10BAE2FFA0FFB16701B211F64C67. CONFIRMED: Key Vault upload succeeded -- C14's
# "Unauthorized" log line was the same benign OAuth challenge/retry pattern GITIN-1770 saw, not
# a real failure. Backend-cert urgency for SFCG-CLUB-01 resolved.

# C16 — re-check backend health after the cert swap (new Let's Encrypt cert replacing the old
# one -- same trust chain/root, shouldn't break, but confirm rather than assume)
az network application-gateway show-backend-health \
  --name WAF_APPs --resource-group DefaultGroup01 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 -o json \
  > operations/events/20260806_automatizar_clubsite_py/data/backend_health_after_py_reissue.json
# OUTPUT (2026-09-09): SFCG-CLUB-01 (192.168.50.121) Healthy on Back_ClubSite, Back_ClubSite_PY,
# and Back_WebSite. SFCG-CLUB-02 (192.168.50.122) UNHEALTHY on both Back_ClubSite and
# Back_ClubSite_PY -- DELIBERATE per user: IIS intentionally stopped on .122 pending its own
# cert update (same pattern as GITIN-1770's independent .02 pass for AR). Next: repeat the
# win-acme backend-only flow on .122 (Windows Cert Store + IIS, no Key Vault).

# C17 — user independently confirmed via the WAF (gateway) itself: the public listener's current
# certificate still shows NotBefore 17 Jun 2026 / NotAfter 15 Sep 2026 -- the OLD cert, same
# expiry as what the backend leg had before C14. Confirms Listener_ClubSite_HTTPS_PY was never
# migrated off the direct PFX object (www.clubgrido.com.py_2026_v2) -- URGENT, same 6-day window
# as the backend leg, just on the public-facing side this time.

# ⚠️ C18 — create a gateway ssl-cert object referencing the new Key Vault secret by its
# VERSIONLESS URI (deliberate -- so the gateway auto-picks up future rotations, no manual
# reconfig each renewal, per the pattern documented in GITIN-1770's investigation.md line 35;
# the actual az commands for AR's own migration were never captured in that ticket's scripts.sh,
# so this is reconstructed from that description + standard az syntax, not a copied prior command)
az network application-gateway ssl-cert create \
  --gateway-name WAF_APPs --resource-group DefaultGroup01 \
  --name www-clubgrido-com-py-kv \
  --key-vault-secret-id "https://sfcg-waf-apps-kv.vault.azure.net/secrets/www-clubgrido-com-py" \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  > operations/events/20260806_automatizar_clubsite_py/data/gateway_ssl_cert_create.json
# OUTPUT (2026-09-09): Succeeded. keyVaultSecretId confirmed versionless
# (https://sfcg-waf-apps-kv.vault.azure.net/secrets/www-clubgrido-com-py, no GUID suffix).

# ⚠️ C19 — repoint the listener from the old PFX object to the new Key Vault-backed ssl-cert
az network application-gateway http-listener update \
  --gateway-name WAF_APPs --resource-group DefaultGroup01 \
  --name Listener_ClubSite_HTTPS_PY \
  --ssl-cert www-clubgrido-com-py-kv \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  > operations/events/20260806_automatizar_clubsite_py/data/gateway_listener_update.json
# OUTPUT (2026-09-09): Succeeded. sslCertificate.id now www-clubgrido-com-py-kv (Key Vault-backed),
# hostName unchanged (www.clubgrido.com.py). Response already confirms the new mapping directly --
# C20's separate re-check is redundant, not run. Public listener migration COMPLETE. Old PFX
# object www.clubgrido.com.py_2026_v2 is now orphaned, same pattern as AR's clubgrido.2023.2024
# (GITIN-1770 left that decision open -- "clean up vs. keep as temporary backup" -- same choice
# applies here, not decided yet).

# C20 — confirm the listener mapping actually changed
az network application-gateway show --name WAF_APPs --resource-group DefaultGroup01 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 -o json \
  | jq '.httpListeners[] | select(.name=="Listener_ClubSite_HTTPS_PY") | {name, hostName, sslCertificate: .sslCertificate.id}' \
  > operations/events/20260806_automatizar_clubsite_py/data/listener_mapping_after_migration.json

# === REMEDIATION — SFCG-CLUB-02 backend-only pass ===

# C21 — win-acme wizard on SFCG-CLUB-02 (interactive): backend-only (no Key Vault, that secret is
# already covered by .01's upload). Source manual www.clubgrido.com.py, Single cert, Azure DNS
# validation (reused vault credential winacme-clubsite-ar-dns from GITIN-1770's AR setup on this
# machine), RSA key, Store Windows Certificate Store only (My), Installation IIS binding on
# SmartLoyalty.ClubSite.
# NOTE: first attempt hit "No IIS sites detected" -- IIS (W3SVC) was stopped on this host (user
# had intentionally taken it down pending this cert update). Started W3SVC + confirmed site/pool
# both Started via Get-Website/Get-WebAppPoolState, but wacs.exe had cached "no sites" from
# before IIS came up -- retrying the menu selection within the same process didn't re-scan.
# Aborted and restarted wacs.exe fresh; detected the site correctly on the second attempt.
# Second attempt also hit a data-entry error (literal "host www.clubgrido.com.py" submitted
# instead of just the hostname) -- aborted, retried, entered correctly on the third attempt.
# OUTPUT (2026-09-09): SUCCESS on third attempt. DNS-01 validated. Renewal added, next due
# 2026/11/3. Kept the existing scheduled task (n to "replace existing task?") since it already
# runs --renew, which processes all due renewal configs, not per-cert.

# C22 — verify only the PY-specific binding changed, not the default/no-SNI binding
Get-WebBinding | Where-Object { $_.bindingInformation -like "*443*" } | Format-List protocol,bindingInformation,certificateHash,certificateStoreName
# OUTPUT (2026-09-09, SFCG-CLUB-02): www.clubgrido.com.py -> E6F1914274B020010A09E08FB9DC27A86E9721BB
# (new). Default (*:443:) unchanged at 0BB9D0CBDB426A421C162EE71B59A39F4A43DBB9. AR unchanged at
# 2DDBE702E6961B89FC97E9B834EDF23C8E6CB55A. Clean scoping confirmed, same as .01.

# C23 — re-check backend health from the gateway side after .02's fix
az network application-gateway show-backend-health \
  --name WAF_APPs --resource-group DefaultGroup01 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 -o json \
  > operations/events/20260806_automatizar_clubsite_py/data/backend_health_after_02_fix.json
# OUTPUT (2026-09-09): both SFCG-CLUB-01 (.121) and SFCG-CLUB-02 (.122) Healthy on all three
# pools (Back_ClubSite, Back_ClubSite_PY, Back_WebSite). Full redundancy restored. GITIN-1769's
# technical work complete: public cert (Key Vault, both nodes' backend certs covered), backend
# leg automated on both nodes, no expiry risk remaining.

# === INVESTIGATION — possible install/config-path mismatch on SFCG-CLUB-02 ===
# User caught: AR's existing scheduled task on .02 (from GITIN-1770) invokes
# C:\ProgramData\win-acme\wacs.exe, but the PY wizard just now was run from C:\win-acme\wacs.exe
# -- a DIFFERENT binary on the same host. Unlike .01 (single install at C:\win-acme, config
# resolved to C:\ProgramData\win-acme\acme-v02.api.letsencrypt.org\ per settings.json's null
# ConfigurationPath), .02 may have TWO separate win-acme installs with independently-resolved
# config paths. If PY's renewal.json landed somewhere the existing task's binary doesn't read
# from, it won't auto-renew despite "Adding renewal..." reporting success. Must verify, not
# assume either way.

# C24 — find where PY's just-created renewal config actually landed on .02
Get-ChildItem "C:\ProgramData\win-acme" -Recurse -Filter "*.renewal.json" -Force -ErrorAction SilentlyContinue | Select-Object FullName
Get-ChildItem "C:\win-acme" -Recurse -Filter "*.renewal.json" -Force -ErrorAction SilentlyContinue | Select-Object FullName
# OUTPUT (2026-09-09, SFCG-CLUB-02): two files in C:\ProgramData\win-acme\acme-v02.api.letsencrypt.org\
# (fvLWlnO5R0ug9bf7igVq7A.renewal.json, y5Y5RT8-BkuvGTMdTWuICg.renewal.json), none under C:\win-acme.
# CONFIRMED: despite running the wizard from a different binary (C:\win-acme\wacs.exe) than AR's
# scheduled task (C:\ProgramData\win-acme\wacs.exe), both installs resolve to the SAME default
# config path (ConfigurationPath: null in both settings.json -> elevated default ProgramData).
# PY's new renewal landed in the same shared location AR's existing task actually reads from --
# the mismatch the user flagged does NOT block auto-renewal. See C26 to confirm which file is which.

# C25 — check both installs' settings.json for a ConfigurationPath override, and confirm both
# wacs.exe binaries actually exist as described
Get-Content "C:\ProgramData\win-acme\settings.json" -Raw -ErrorAction SilentlyContinue
Get-Content "C:\win-acme\settings.json" -Raw -ErrorAction SilentlyContinue
Test-Path "C:\ProgramData\win-acme\wacs.exe"
Test-Path "C:\win-acme\wacs.exe"
# OUTPUT (2026-09-09): both settings.json identical, ConfigurationPath null. Both wacs.exe exist
# -- genuinely two separate binaries, confirmed, not just one referenced two ways.

# C26 — confirm which renewal file is PY vs AR, don't assume by file order
Get-ChildItem "C:\ProgramData\win-acme\acme-v02.api.letsencrypt.org\*.renewal.json" | ForEach-Object {
  $j = Get-Content $_.FullName -Raw | ConvertFrom-Json
  [PSCustomObject]@{ File = $_.Name; CommonName = $j.TargetPluginOptions.CommonName }
} | Format-Table -AutoSize
# OUTPUT (2026-09-09): fvLWlnO5R0ug9bf7igVq7A.renewal.json = www.clubgrido.com.py,
# y5Y5RT8-BkuvGTMdTWuICg.renewal.json = www.clubgrido.com.ar. CONFIRMED: both renewals share the
# config path AR's existing scheduled task reads from -- the two-binary situation the user
# flagged does not create an auto-renewal gap.

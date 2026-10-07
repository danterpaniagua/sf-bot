# Investigation: Automatizar renovación SSL — WebSite (GITIN-1771)

Jira: https://smartit-ar.atlassian.net/browse/GITIN-1771 (subtask of epic https://smartit-ar.atlassian.net/browse/GITIN-1768)

## Context (from prior sessions, `operations/events/20260807_automatizar_ssl_loyalty_epic/`)

- Hostname: `gestion.clubgrido.com.ar`
- Host: `SFCG-WSIT-01`, single server, no redundancy (per `loyalty/docs/infrastructure.md`)
- Public ingress: Application Gateway WAF `WAF_APPs` (`DefaultGroup01`) — same gateway ClubSite AR/PY already use
- Epic map status as of 2026-08-07: **SinAutomatizar** (not started)
- Jira board status (per user, 2026-09-13): **Bloqueado**

## Established pattern (from the completed ClubSite AR case, GITIN-1770)

For a WAF_APPs-fronted single-node service, the pattern is:
1. Confirm the exact listener/hostname/certificate mapping on `WAF_APPs` (don't assume from naming).
2. Create an Azure DNS zone `_acme-challenge.<hostname>` in `DefaultGroup01`.
3. Grant the existing win-acme Service Principal (`winacme-mobileservice-dns`, appId `3cca7e2a-5b4a-4b0d-87ee-4390af90346f`) `DNS Zone Contributor` on that new zone — reuse, don't create a new SP.
4. Add the delegating NS record for `_acme-challenge.gestion` under `clubgrido.com.ar` at the registrar (GoDaddy) pointing to the new zone's nameservers — **manual step, GoDaddy UI, not automatable via this repo's tooling**.
5. Run win-acme on `SFCG-WSIT-01` (Azure DNS validation plugin + Key Vault store plugin, same `sfcg-waf-apps-kv` vault already created for ClubSite AR) to issue and install the cert.
6. Verify the Application Gateway backend trust chain accepts the new cert's chain (ClubSite AR needed `letsencrypt-isrg-root-x1` uploaded as a trusted root on the relevant backend HTTP settings — check whether `Backend_WebSite` already trusts it or needs the same fix).

## Confirmed (2026-09-13)

- `gestion.clubgrido.com.ar` **is** on `WAF_APPs`: `Listener_WebSite_HTTPS`, cert `website_2024`, real backend (not just redirect) — `Back_WebSite`/`Backend_WebSite`. Same pattern as ClubSite AR.
- `Backend_WebSite`'s `trustedRootCertificates` only had the old GoDaddy CA (`2023.gestion.clubgrido_CA`) — same trust-chain gap ClubSite AR had before its fix. `letsencrypt-isrg-root-x1` already exists on the gateway from that prior fix, so this only needed adding it to `Backend_WebSite`'s list, not re-uploading.
- Executed: Azure DNS zone `_acme-challenge.gestion.clubgrido.com.ar` created (nameservers `ns1-09.azure-dns.com.`/`ns2-09.azure-dns.net.`/`ns3-09.azure-dns.org.`/`ns4-09.azure-dns.info.`); win-acme SP (`3cca7e2a-...`, principalId `68f5c410-df61-4bd4-904a-9de056077e02`) granted `DNS Zone Contributor` on it.

GoDaddy NS delegation confirmed done — user pasted the full `clubgrido.com.ar` zone file, showing `_acme-challenge.gestion` NS records pointing to the correct zone (`ns1-4-09.azure-dns.*`). Independently verified externally via `dig +short NS _acme-challenge.gestion.clubgrido.com.ar` — resolves correctly, delegation is live.

**Naming trap spotted in that zone file, worth recording**: `webservice2.clubgrido.com.ar` → `13.82.96.104` is a **different, unrelated host** from `webservicev2.smartfran.com` → `52.186.168.27` (the actual subject of GITIN-1772). Same near-identical name, different domain, different IP, different service. Don't conflate them in any future work on either ticket.

## Update (2026-09-22)

**Trust-chain fix applied and verified.** Precheck (`data/backend_website_root_certs_precheck.txt`) confirmed `Backend_WebSite` still only had `2023.gestion.clubgrido_CA`. Ran `az network application-gateway http-settings update` adding `letsencrypt-isrg-root-x1` alongside the existing cert (result: `data/backend_website_rootcert_update_result.json`, `provisioningState: Succeeded`, both certs present). Post-change backend health check (`data/backend_health_post_rootcert_update.json`): `Back_WebSite`'s single node (`192.168.50.131`, `SFCG-WSIT-01`) is **Healthy** — no disruption.

Unrelated finding surfaced by the same health check, **not part of this ticket's scope** — flagged to the user, not investigated further here: `Back_ClubSite`'s second node (`192.168.50.122`) shows `Unhealthy` ("Cannot connect to backend server"). ClubSite AR issue, unrelated to WebSite/GITIN-1771.

## Still open

- **win-acme install on `SFCG-WSIT-01`** (Azure DNS + Key Vault store plugins for the public cert, same `sfcg-waf-apps-kv` vault as ClubSite AR; plus a second win-acme configuration on the same host for the backend-leg cert → Windows Cert Store + IIS binding, mirroring ClubSite AR's two-part pattern) — not started. This is the piece that needs the off-hours window (single-node, no redundancy, live IIS binding change) — matches the original `loyalty/todo/TODO.md` note "do outside working hours."
- Board status shown as **Bloqueado** — no technical blocker found so far (same shape as the already-completed ClubSite AR); flagged to the user, not independently resolved.

## Precheck (2026-09-22): IIS binding scope on `SFCG-WSIT-01`, resolved

`Get-WebBinding` on port 4430 showed **two bindings sharing one certificate hash** (`EAD5C7798E9F50FD7B0DAA162BFB7BFC88E9BE41`): the real `gestion.clubgrido.com.ar` hostname binding (site `SmartLoyalty.WebSite`) and a blank-hostname catch-all (`*:4430:`, site literally named `DefaultAppPool`). This broke the ClubSite AR runbook's safety assumption for the IIS install step ("updates every binding sharing the old hash — safe only if each hostname has a distinct hash"), since both share one hash here. **Resolved**: `Get-Website "DefaultAppPool"` shows `PhysicalPath: D:\SmartLoyalty.WebSite` — same directory as the real site, not a separate application. Letting win-acme's install step update both bindings is correct, not a risk. Full detail: `data/sfcg_wsit01_webbinding_precheck.txt`.

## Off-hours window plan — full checklist

**Before the window (no risk, do anytime):**
```bash
az ad app credential reset --id 3cca7e2a-5b4a-4b0d-87ee-4390af90346f --append
```
New secret for the win-acme SP scoped to this host (win-acme's local credential vault is DPAPI-encrypted, per-machine — ClubSite's saved secret can't be reused). `--append` is mandatory — without it, every other VM's renewal breaks.

**Install win-acme on `SFCG-WSIT-01`** (portable install at `C:\win-acme`, matching the MobileAppService/ClubSite AR convention — note this is a *different* path from where the renewal config itself lands, `C:\ProgramData\win-acme\acme-v02.api.letsencrypt.org\`, which caused real confusion during ClubSite PY's setup):
```powershell
New-Item -ItemType Directory -Force -Path C:\win-acme | Out-Null
Invoke-WebRequest -Uri "https://github.com/win-acme/win-acme/releases/download/v2.2.9.1701/win-acme.v2.2.9.1701.x64.pluggable.zip" -OutFile "C:\win-acme\win-acme.zip"
Expand-Archive -Path "C:\win-acme\win-acme.zip" -DestinationPath "C:\win-acme" -Force
Get-ChildItem C:\win-acme -Recurse | Unblock-File

cd C:\win-acme
Invoke-WebRequest -Uri "https://github.com/win-acme/win-acme/releases/download/v2.2.9.1701/plugin.validation.dns.azure.v2.2.9.1701.zip" -OutFile "C:\win-acme\azure-dns-plugin.zip"
Expand-Archive -Path "C:\win-acme\azure-dns-plugin.zip" -DestinationPath "C:\win-acme" -Force
Get-ChildItem C:\win-acme -Recurse | Unblock-File

Invoke-WebRequest -Uri "https://github.com/win-acme/win-acme/releases/download/v2.2.9.1701/plugin.store.keyvault.v2.2.9.1701.zip" -OutFile "C:\win-acme\keyvault-plugin.zip"
Expand-Archive -Path "C:\win-acme\keyvault-plugin.zip" -DestinationPath "C:\win-acme" -Force
Get-ChildItem C:\win-acme -Recurse | Unblock-File
```

**During the window, interactive (`cd C:\win-acme; .\wacs.exe` → `M`):**

*Run 1 — public cert:* Source manual, `gestion.clubgrido.com.ar` → Validation Azure DNS (`AzureCloud`, no managed identity, the new SP secret, zone `_acme-challenge.gestion.clubgrido.com.ar`) → Store Key Vault (`sfcg-waf-apps-kv`) → no Installation step.

*Run 2 — backend-leg cert:* Source manual, `gestion.clubgrido.com.ar` (same zone) → Validation Azure DNS (same SP secret) → Store Windows Certificate Store, `My` → Installation IIS binding — site `SmartLoyalty.WebSite` (confirmed via `Get-WebBinding`/`Get-Website` above; the `DefaultAppPool` binding update happens automatically alongside it, confirmed safe).

**After both runs:**
```powershell
Get-WebBinding | Where-Object { $_.bindingInformation -like "*4430*" } | Format-List protocol,bindingInformation,certificateHash,certificateStoreName
```
Confirm both bindings' hash changed together (expected, per the precheck resolution above).

```bash
az network application-gateway show-backend-health --name WAF_APPs --resource-group DefaultGroup01 --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 -o json
```
Confirm `Back_WebSite` stays `Healthy`.

## Off-hours window — Run 1 (public cert) complete (2026-09-22)

Executed the full win-acme wizard on `SFCG-WSIT-01` per the plan above. One false alarm during execution, corrected: the wizard's log summary showed `Store with KeyVault... [HTTP] Request completed with status Unauthorized`, which looked like a real failure and triggered an unnecessary side investigation (RBAC role re-check — still correct; Key Vault network ACLs — fully open, not the cause). **Resolved**: pulled the full verbose log (`Get-ChildItem ".../Log/log-*.txt" | ... | Select-String "KeyVault|Unauthorized..."`) and confirmed this was just Key Vault's standard OAuth challenge-response — the immediate retry with a bearer token attached returned `OK` with the full certificate object. Independently verified via `az keyvault certificate show`: cert exists, `enabled: true`, valid 2026-09-22 through 2026-12-21, thumbprint `B366BF5A972778D1C3908234BA0C8E83020C6181` (`data/run1_keyvault_cert_verification.json`).

Gateway repointed from the old direct-PFX cert (`website_2024`) to the new Key Vault-backed object, matching ClubSite AR's naming convention (`<hostname>-kv`, confirmed live via `az network application-gateway show`): created `gestion-clubgrido-com-ar-kv` referencing the **versionless** secret URI, then updated `Listener_WebSite_HTTPS` to use it. Both succeeded (`data/run1_gateway_listener_repoint.json`). Backend health re-confirmed after the repoint: `Back_WebSite` (192.168.50.131) still `Healthy` (`data/backend_health_post_listener_repoint.json`) — no disruption.

**Run 1 (public cert) is fully complete.** Only Run 2 (backend-leg cert → Windows Cert Store + IIS binding on `SFCG-WSIT-01`) remains.

## Off-hours window — Run 2 (backend-leg cert) complete (2026-09-22)

Second win-acme wizard on `SFCG-WSIT-01`, same host, different store/install target (Windows Certificate Store `My` + IIS binding, not Key Vault). Reused the cached DNS-01 authorization from Run 1 (same hostname, within Let's Encrypt's reuse window) — no new TXT record round-trip needed.

**Real decision point during the wizard**: win-acme detected an existing renewal entry with the same display name (`[Manual] gestion.clubgrido.com.ar`, from Run 1) and asked "Overwrite settings? (y*/n)" — default is **yes**. Answered **n** instead — accepting the default would have replaced Run 1's Key Vault renewal configuration with this run's Windows Cert Store/IIS config under one entry, silently breaking automatic renewal for one of the two independent certs this whole runbook is built around. Confirmed both entries now exist independently under **A: Manage renewals**.

Certificate installed to `My` store (CA chain — `YR2` intermediate, `Root YR` — imported alongside), then `Installing with IIS...` updated the `gestion.clubgrido.com.ar:4430` binding. **Verified, not assumed**: the log said "Committing 1 https binding changes," which turned out to mean literally one — `Get-WebBinding` confirmed only the hostname-specific binding got the new hash (`B366BF5A972778D1C3908234BA0C8E83020C6181`); `DefaultAppPool`'s blank-hostname binding (same app, per the earlier precheck) still had the old hash (`EAD5C7798E9F50FD7B0DAA162BFB7BFC88E9BE41`). This contradicts the runbook's general claim that the IIS plugin updates *every* binding sharing the old hash — it was actually scoped to just the targeted site. Fixed manually: `Get-WebBinding -Name "DefaultAppPool" -Protocol https -Port 4430 | ForEach-Object { $_.AddSslCertificate("B366BF5A972778D1C3908234BA0C8E83020C6181", "My") }` — both bindings now consistent.

Final backend health check (`data/backend_health_final.json`): `Back_WebSite` (192.168.50.131) still `Healthy`. No disruption across either run.

## Status

**GITIN-1771 complete.** Both certs issued and installed: public leg in Key Vault (gateway listener repointed), backend leg in the Windows Certificate Store with IIS bindings updated (both the real hostname binding and the co-located `DefaultAppPool` one). Two independent win-acme renewal entries confirmed tracked separately. Backend health verified healthy throughout.

**Live end-to-end verification (2026-09-22, post-close)**: `openssl s_client -connect gestion.clubgrido.com.ar:4430 -servername gestion.clubgrido.com.ar | openssl x509 -noout -subject -issuer -dates` confirms the gateway is genuinely serving the new certificate — `CN=gestion.clubgrido.com.ar`, issuer Let's Encrypt YR2, valid 2026-09-22 to 2026-12-21. Real TLS handshake check, not just Azure API state. A browser cert-viewer check in the same session briefly showed an unrelated GoDaddy intermediate cert (likely a stale/cached view) — the direct `openssl` check resolved the ambiguity definitively. Runbook note worth carrying forward to `operations/docs/waf_apps_cert_automation_runbook.md`: the IIS install plugin's "updates all bindings sharing the old hash" claim doesn't always hold — verify with `Get-WebBinding` after any future run rather than assume.

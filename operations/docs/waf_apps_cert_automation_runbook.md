# Runbook — SSL certificate automation on `WAF_APPs` (Key Vault + Application Gateway)

> Source: story `GITIN-1768`. First implemented and **complete** case: `GITIN-1770` (ClubSite AR), event `operations/events/20260806_automatizar_clubsite_ar/`, covering both the public certificate (section 4) and the backend certificate (section 6, added after a critical finding outside the original scope). Designed to be reused for `GITIN-1769` (ClubSite PY, blocked, see section 5) and `GITIN-1771` (WebSite): **check on both whether the gateway also re-encrypts end to end to its backend**; if so section 6 applies too, not only section 4.

## 1. Goal

Automate SSL certificate renewal for the hostnames served by the Application Gateway/WAF `WAF_APPs`, without a manual PFX upload each cycle. Unlike MobileAppService (`operations/docs/mobileappservice_ssl_renewal_runbook.md`), the certificate lives in **Azure Key Vault**, not in a VM's local store: the gateway picks up a new version automatically when it rotates.

## 2. Relevant topology

- **Application Gateway `WAF_APPs`** (WAF_v2, resource group `DefaultGroup01`), no managed identity (`identity: null`, confirmed 2026-08-06; added in `GITIN-1770`).
- **9 certificate objects uploaded directly (PFX)** to the gateway at the time of this work, none integrated with Key Vault. Only 3 are in use (confirmed via `.httpListeners[].sslCertificate`): `clubgrido.2023.2024` (ClubSite AR), `www.clubgrido.com.py_2026_v2` (ClubSite PY), `website_2024` (WebSite). The other 6 are orphans of earlier manual renewals.
- **HTTP-01 is not viable for any hostname of this gateway**: the existing HTTP listeners (`Listener_ClubSite_HTTP_AR` / `_PY`) are pure redirects to HTTPS (`redirectConfig` set, `backendPool: null`), with no backend able to serve a challenge file.
- **DNS-01 is the only viable method**, as for MobileAppService, but it needs admin access to the domain (see section 5 for `clubgrido.com.py`, with no access).

## 3. Automation resources (shared by all hostnames of this gateway)

| Resource | Name | Scope |
|---|---|---|
| Key Vault | `sfcg-waf-apps-kv` | Shared: one secret/certificate per hostname |
| Managed Identity (read) | `waf-apps-kv-identity` | Attached to `WAF_APPs`, role `Key Vault Secrets User` on `sfcg-waf-apps-kv` |
| Service Principal (DNS write) | `winacme-mobileservice-dns` (reused from `GITIN-1774`, inherited name) | Role `DNS Zone Contributor`: one new role assignment per extra `_acme-challenge.*` zone, not one broad assignment |

Do not create a new Managed Identity or Service Principal per hostname: reuse the above and add only the missing role assignments (new DNS zone → new `DNS Zone Contributor` assignment scoped to that zone).

## 4. Procedure (per hostname)

### 4.1 Confirm the real certificate and listener

```bash
az network application-gateway show --name WAF_APPs --resource-group DefaultGroup01 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 -o json \
  | jq '.httpListeners[] | {name, hostName, sslCertificate: .sslCertificate.id}'
```

Do not infer which certificate belongs to which listener from the name: `clubgrido.2023.2024` looked orphaned by name and was in use.

### 4.2 Azure DNS zone for the hostname

```bash
az network dns zone create --name "_acme-challenge.<hostname>" --resource-group DefaultGroup01 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8

az network dns zone show --name "_acme-challenge.<hostname>" --resource-group DefaultGroup01 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 --query nameServers -o tsv
```

Delegate by hand in the DNS panel (NS record, host `_acme-challenge.<subdomain>`): **needs admin access to that specific domain**. Check with `dig _acme-challenge.<hostname>` that the `AUTHORITY` section returns the new zone's own SOA, not the parent domain's.

### 4.3 Service Principal permission on the new zone

```bash
az role assignment create \
  --assignee "<appId of the existing Service Principal>" \
  --role "DNS Zone Contributor" \
  --scope "/subscriptions/0190fa7d-4ccf-4e3d-beb1-323b5780bfc8/resourceGroups/DefaultGroup01/providers/Microsoft.Network/dnszones/_acme-challenge.<hostname>" \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8
```

### 4.4 Key Vault and Managed Identity (once for the whole gateway, already done)

```bash
az keyvault create --name sfcg-waf-apps-kv --resource-group DefaultGroup01 --location eastus \
  --enable-rbac-authorization true --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8

az identity create --name waf-apps-kv-identity --resource-group DefaultGroup01 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8

az network application-gateway identity assign --gateway-name WAF_APPs --resource-group DefaultGroup01 \
  --identity /subscriptions/0190fa7d-4ccf-4e3d-beb1-323b5780bfc8/resourcegroups/DefaultGroup01/providers/Microsoft.ManagedIdentity/userAssignedIdentities/waf-apps-kv-identity \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8

az role assignment create --assignee "<identity principalId>" --role "Key Vault Secrets User" \
  --scope "/subscriptions/0190fa7d-4ccf-4e3d-beb1-323b5780bfc8/resourceGroups/DefaultGroup01/providers/Microsoft.KeyVault/vaults/sfcg-waf-apps-kv" \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8
```

Do not repeat for more hostnames: it already covers the whole gateway.

### 4.5 win-acme: host, plugins and issuance

**Host chosen for ClubSite AR: `SFCG-CLUB-01`** (`192.168.50.121`, confirmed real member of `Back_ClubSite` via `az network nic list`, not just by name). A new dedicated VM and a serverless alternative (`keyvault-acmebot`, third-party Azure Functions project built for exactly this pattern) were evaluated and not chosen for now: existing infrastructure is reused.

Install on that host: the pluggable win-acme build (`win-acme.v2.2.9.1701.x64.pluggable.zip`) + the Azure DNS DNS-01 validation plugin (`plugin.validation.dns.azure.v2.2.9.1701.zip`, same as `GITIN-1774`) + the Key Vault store plugin (`plugin.store.keyvault.v2.2.9.1701.zip`); exact names confirmed against the GitHub API.

Wizard (`wacs.exe` → M, full options): Source manual (the specific hostname, not the whole IIS site) → Validation Azure DNS (`AzureCloud`, no managed identity, Service Principal credentials, zone `_acme-challenge.<hostname>`) → Store Key Vault (vault name, no managed identity; it uses the same Service Principal credentials, which need `Key Vault Certificates Officer` on the vault, not only `DNS Zone Contributor`) → no Installation step (no local binding for the public certificate). The gateway picks up the new secret version automatically in ~4 h, without redeploy, as long as the listener's `sslCertificate` references the secret URI **without version** (`.../secrets/<name>`, no trailing version GUID): with an explicit version the gateway stays pinned to it forever.

### 4.6 Repoint the listener to the Key Vault certificate

Create a gateway certificate object that references the Key Vault secret by its **versionless** URI, then point the listener at it (the exact commands used for ClubSite PY and WebSite; ClubSite AR's were never captured). The old direct-PFX object becomes orphaned (whether to delete it is a separate decision, still open for `clubgrido.2023.2024` and `www.clubgrido.com.py_2026_v2`). Check that the public endpoint serves the new certificate (`openssl s_client -connect <host>:443 -servername <host>`) and that the validity dates match, since a listener left on the old PFX keeps the old expiry (ClubSite PY was in that state until 2026-09-09).

```bash
# ⚠️ ACTION — create the gateway ssl-cert object (versionless secret URI)
az network application-gateway ssl-cert create \
  --gateway-name WAF_APPs --resource-group DefaultGroup01 \
  --name <host-with-dashes>-kv \
  --key-vault-secret-id "https://sfcg-waf-apps-kv.vault.azure.net/secrets/<cert-name>" \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8

# ⚠️ ACTION — repoint the listener
az network application-gateway http-listener update \
  --gateway-name WAF_APPs --resource-group DefaultGroup01 \
  --name <Listener_..._HTTPS> --ssl-cert <host-with-dashes>-kv \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8
```

## 5. Notes

- **`GITIN-1769` (ClubSite PY) is blocked**: without admin access to the `clubgrido.com.py` domain the delegation NS record cannot be added. HTTP-01 is not viable either (same redirect-without-backend finding as ClubSite AR). No automation path until DNS access is obtained or a path routing rule for `/.well-known/acme-challenge/*` is added.
- This runbook assumes `GITIN-1771` (WebSite) follows the same pattern; not yet verified whether `gestion.clubgrido.com.ar` has the same DNS access as `clubgrido.com.ar` (it should, same domain), nor whether its HTTP listener (if any) has the same redirect-without-backend problem.

## 6. Backend certificate (Gateway→Backend leg, if the gateway re-encrypts end to end)

**Before automating only section 4 and closing the ticket, confirm whether the gateway decrypts and re-encrypts toward the backend** (`backendHttpSettingsCollection[].protocol: Https` with `trustedRootCertificates` set). If so there are **two completely independent certificates** per hostname: the public one (section 4, on the listener) and the backend one (this section, local to each backend VM via IIS). Automating only one and leaving the other as a purchased/manual certificate is a total-outage risk unrelated to the public certificate's validity; this is how `GITIN-1770` found a GoDaddy backend certificate expiring 2026-11-13, outside the ticket's original scope.

### 6.1 Issuance and installation (per backend VM, independent on each)

Each backend VM runs its own automation with its **own private key**: do not copy certificates/private keys between VMs (same criterion as MobileAppService). Install win-acme with the Azure DNS DNS-01 validation plugin only (**not** the Key Vault store plugin: the backend certificate does not go to Key Vault).

Wizard: Source manual (the specific hostname). If the IIS site has several SNI hostnames (ClubSite serves `.ar` and `.py` on one site) the wizard asks how to group (`1: by domain`, `2: by host`, `3: by IIS site`, `4: single certificate`): **choose "2: by host"** and select only the wanted hostname, so the other hostnames of the site are not pulled into the same issuance → Validation Azure DNS (same zone as section 4) → Store Windows Certificate Store, Local Computer, same store name as the existing bindings (check with `Get-WebBinding`, normally `My`) → Installation "Create or update bindings in IIS", select the corresponding site.

The IIS installation plugin updates the bindings of the site chosen in the wizard that used the old certificate. **Do not assume it updates *all* server bindings sharing the old hash, even on another site (GITIN-1771, 2026-09-22):** on WebSite, two bindings on the same port (`gestion.clubgrido.com.ar` and a hostname-less binding of the `DefaultAppPool` site, same app, different IIS site) shared the old hash before the wizard; afterwards `Get-WebBinding` showed only the chosen site's binding was updated, and the other kept the old certificate until fixed by hand (`AddSslCertificate`). **Always check `Get-WebBinding` after installing, not only before:** whether the plugin touches every shared binding was not confirmed consistently across runs.

**win-acme's local credential vault (where the Service Principal secret can be stored for reuse) is DPAPI-encrypted and local to each machine; it is not synced between VMs.** A secret stored on VM A is unusable from VM B. For the second VM onwards, generate a new secret for the same Service Principal (`az ad app credential reset --append`; never without `--append`, it would invalidate the secrets other VMs already use) instead of reusing the stored one.

**A second win-acme run on the same host offers to overwrite the existing renewal** (the backend certificate has the same entry name as the public one). Answer `n` (the default is `y*`): overwriting merges both renewals into one entry and silently breaks the automatic renewal of one of them until the next expiry (GITIN-1771).

**Several hostnames on one host share one win-acme configuration.** Two installs (`C:\ProgramData\win-acme\wacs.exe` and `C:\win-acme\wacs.exe`) both use `C:\ProgramData\win-acme\acme-v02.api.letsencrypt.org\`, and the single scheduled task renews every `.renewal.json` there. To know whether a hostname has automation, list those files and read each one's `TargetPluginOptions.CommonName`: on `SFCG-CLUB-01` the AR renewal did not cover `www.clubgrido.com.py`, whose Let's Encrypt backend certificate (issued 2026-06-17, outside the epic) had no renewal at all and would have expired 2026-09-15. Do not assume a certificate that is already Let's Encrypt is automated. If `W3SVC` is stopped when the wizard starts it reports "No IIS sites detected" and keeps that cached: start IIS, quit and restart `wacs.exe`.

Let's Encrypt can issue through different "sibling" intermediates on each run (e.g. `YR1`/`YR2`, or `E5`/`E6`/`R10`/`R11` depending on the time); all chain to the same self-signed root. Do not assume the intermediate name stays the same between runs.

**Check what the backend HTTP settings already trust before the first backend issuance:** `Backend_WebSite` trusted only the old GoDaddy CA, the same gap ClubSite AR had. The fix is to add the root already uploaded to the gateway, `letsencrypt-isrg-root-x1`, to that HTTP setting's `trustedRootCertificates` (`http-settings update --root-certs`, listing the existing names plus the new one); `Back_WebSite` was Healthy before and after.

**The win-acme log line `Store with KeyVault ... Unauthorized` is the normal Key Vault OAuth challenge** (first request without a token, immediate retry with it), not a failure. Confirm with `az keyvault certificate show` (enabled, validity dates); do not start RBAC/network checks because of that line (GITIN-1771).

### 6.2 Trust chain in `trustedRootCertificates`

**Only the self-signed root certificate goes in `trustedRootCertificates`, never an intermediate.** Check with `openssl x509 -noout -subject -issuer` before uploading: if `Issuer` ≠ `Subject` it is an intermediate and `az network application-gateway root-cert create` rejects it with `ApplicationGatewayTrustedRootCertificateInvalidData`, whether the file is DER or base64/PEM (confirmed in `GITIN-1770`, two failed attempts with both formats before finding the real cause). The intermediate need not be uploaded to the gateway: the backend IIS serves it in the TLS handshake if win-acme installed it correctly (check that the certificate is in the local `CA` store, not only `My`).

**Order and expectations:** when the first backend node moves to the Let's Encrypt chain before the root is trusted, that node is `Unhealthy` in `show-backend-health` (expected) and the site runs on the other node until `letsencrypt-isrg-root-x1` is attached to the HTTP settings (ClubSite AR, 2026-08-07); the root alone is enough, whichever sibling intermediate (`YR1`, `YR2`, `YE2`) is issued. If `trustedRootCertificates` is empty on the HTTP settings (as on `Backend_ClubSite_PY`), the gateway uses the well-known public CAs by default, so a backend certificate chaining to ISRG Root X1 needs nothing: that is not a gap. When IIS on a node is stopped on purpose, that node shows `Unhealthy` too.

```bash
# Quick diagnosis: self-signed root or intermediate?
openssl x509 -inform DER -in certificate.cer -noout -subject -issuer
# Issuer == Subject -> self-signed root, valid for trustedRootCertificates
# Issuer != Subject -> intermediate, do NOT upload here

# ⚠️ ACTION — upload the root cert to the gateway
az network application-gateway root-cert create \
  --gateway-name WAF_APPs --resource-group DefaultGroup01 \
  --name <name> --cert-file <file> \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8

# ⚠️ ACTION — attach the root cert to the matching backend HTTP settings
az network application-gateway http-settings update \
  --gateway-name WAF_APPs --resource-group DefaultGroup01 \
  --name <Backend_X> --root-certs <list of existing names> <new name> \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8

# Check — every backend pool address must be Healthy
az network application-gateway show-backend-health \
  --name WAF_APPs --resource-group DefaultGroup01 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 -o json
```

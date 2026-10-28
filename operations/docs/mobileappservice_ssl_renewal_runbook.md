# Runbook — MobileAppService SSL certificate renewal (`SFCG-MOBI-01/02`)

> Source: ticket `GITIN-1786` (manual stopgap, section 4), event `operations/events/20260804_mobileappservice_ssl_cert_renewal/`. Final automation (section 5) implemented under `GITIN-1774`, event `operations/events/20260806_acme_challenge_migration/`. The events hold the full investigation (network topology, why GoDaddy was discarded as DNS-01 validator, etc.).

## 1. Goal

Renew the public SSL certificate of MobileAppService (`https://mobileservice.clubgrido.com.ar:8043`), both manually (stopgap, used 2026-08-04) and in its final automated form (delegation to Azure DNS, section 5). Section 4 stays as rollback reference; the real renewal no longer needs any manual step.

## 2. Relevant topology

- **Hosts:** `SFCG-MOBI-01` and `SFCG-MOBI-02`, Windows/IIS, `DefaultGroup01`, subscription Smart IT - Grido (`0190fa7d-4ccf-4e3d-beb1-323b5780bfc8`). IIS site `SmartLoyalty.MobileAppService`, HTTPS binding on port **8043**.
- **Independent certificate per VM.** No shared Central Certificate Store (CCS): each VM issues and renews its own certificate. win-acme creates **non-exportable** private keys by default, so the `.pfx` cannot be copied between VMs; repeat the procedure on each.
- **Load Balancer `SFCG-MOBI-LB`** (layer 4, no WAF/Application Gateway): a single TCP 8043→8043 rule, `SourceIPProtocol` distribution (source-IP affinity: a client always lands on the same backend VM). **There is no port 80/443 rule**, so ACME HTTP-01 is not viable without opening a new rule just for it; always use DNS-01.
- **DNS:** `clubgrido.com.ar` is managed at **GoDaddy** (`pdns07/08.domaincontrol.com`). The GoDaddy account **has no access to its Domains API** (`403 ACCESS_DENIED`, confirmed 2026-08-04): do not use win-acme's GoDaddy plugin until that changes.

## 3. Prerequisites

- RDP/PowerShell administrator access to `SFCG-MOBI-01` and `SFCG-MOBI-02`.
- Access to the GoDaddy panel to add/remove `clubgrido.com.ar` DNS records: only for the historical manual procedure (section 4) or the one-time NS delegation record (section 5, already done). Normal renewals need no manual access.
- win-acme (`wacs.exe`), **x64 pluggable** build (not `trimmed`; this distinction is not fully verified against the exact version used: if the plugin store does not load, check in the tool) from `https://github.com/win-acme/win-acme/releases`.

## 4. Manual procedure (stopgap)

Repeat on each VM independently (`-01`, then `-02`).

### 4.1 Capture the previous SSL binding (rollback reference)

```powershell
netsh http show sslcert ipport=0.0.0.0:8043
```

Save `Certificate Hash`, `Application ID` and `Certificate Store Name`: needed to revert.

### 4.2 Install win-acme

```powershell
New-Item -ItemType Directory -Force -Path C:\win-acme | Out-Null
Invoke-WebRequest -Uri "https://github.com/win-acme/win-acme/releases/download/v2.2.9.1701/win-acme.v2.2.9.1701.x64.pluggable.zip" -OutFile "C:\win-acme\win-acme.zip"
Expand-Archive -Path "C:\win-acme\win-acme.zip" -DestinationPath "C:\win-acme" -Force
Get-ChildItem C:\win-acme -Recurse | Unblock-File
```

(Check the current URL/version on the releases page.)

### 4.3 Run the wizard

```powershell
cd C:\win-acme
.\wacs.exe
```

As administrator. Menu sequence:

| Step | Option |
|---|---|
| Main menu | **M** — Create certificate (full options) |
| Domain source | **2** — Manual input → `mobileservice.clubgrido.com.ar` |
| Certificate split | **4** — Single certificate |
| Validation | **[dns] Create verification records manually** (the exact number varies with installed plugins: confirm on screen) |
| TXT record | Add `_acme-challenge.mobileservice.clubgrido.com.ar` by hand in the GoDaddy panel with the given value, wait for confirmation, continue |
| Key type | **1** — Elliptic Curve key (matches the current certificate) |
| Storage | **4** — Windows Certificate Store (Local Computer) |
| Specific store | **3** — Default (WebHosting) |
| Another store step? | **5** — No (additional) store steps |
| Installation | **1** — Create or update bindings in IIS → site `SmartLoyalty.MobileAppService` |
| Another installation step? | **3** — No (additional) installation steps |
| Scheduled-task account | **SYSTEM** (answer `n` to "specify the user"): keeps renewal decoupled from the `SMARTIT\itservices` rotation runbook |
| Schedule | Stagger between VMs, e.g. `09:00` on `-01`, `13:00` on `-02`, so both do not renew in the same window |

### 4.4 Verify

```powershell
# Local check (bypasses the LB)
$tcp = New-Object System.Net.Sockets.TcpClient('localhost', 8043)
$ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false, ({$true}))
$ssl.AuthenticateAsClient('mobileservice.clubgrido.com.ar')
$cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]$ssl.RemoteCertificate
$cert | Select-Object Thumbprint, NotBefore, NotAfter, Subject, Issuer
$ssl.Close(); $tcp.Close()
```

Confirm `NotAfter` extended (~90 days) and `Subject = CN=mobileservice.clubgrido.com.ar`. Repeat on the other VM.

### 4.5 Cleanup

Delete the temporary TXT record at GoDaddy once validated.

### 4.6 Rollback

```powershell
netsh http delete sslcert ipport=0.0.0.0:8043
netsh http add sslcert ipport=0.0.0.0:8043 certhash=<PREVIOUS_HASH> appid='<PREVIOUS_APP_ID>' certstorename=<PREVIOUS_STORE>
```

With the values captured in 4.1. win-acme does not remove the old certificate from the store, only unbinds it: the old one stays available to revert until it expires.

**Non-obvious warning:** if the mobile app does *certificate pinning*, a new (valid) certificate can break existing clients with no visible server-side error. Verify with a real client, not only `openssl`/PowerShell.

## 5. Automated procedure (final, implemented 2026-08-06)

**Implemented and verified on both VMs (`GITIN-1774`).** Renewal runs fully unattended through DNS-01 validation on a delegated Azure DNS zone: no GoDaddy plugin (no Domains API access, section 2, no ETA) and no manual TXT step.

### 5.1 Azure DNS zone and delegation (once, done)

```bash
az network dns zone create \
  --name "_acme-challenge.mobileservice.clubgrido.com.ar" \
  --resource-group DefaultGroup01 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8

az network dns zone show \
  --name "_acme-challenge.mobileservice.clubgrido.com.ar" \
  --resource-group DefaultGroup01 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --query nameServers -o tsv
```

Assigned nameservers (delegated at GoDaddy by a manual NS record, host `_acme-challenge.mobileservice`): `ns1-01.azure-dns.com.`, `ns2-01.azure-dns.net.`, `ns3-01.azure-dns.org.`, `ns4-01.azure-dns.info.`

Verify the delegation with `dig _acme-challenge.mobileservice.clubgrido.com.ar`: `status: NOERROR` and the zone's own SOA in the `AUTHORITY` section (not GoDaddy's).

### 5.2 Service Principal for win-acme (once, done)

```bash
az ad sp create-for-rbac --name "winacme-mobileservice-dns" --skip-assignment

az role assignment create \
  --assignee "<appId returned above>" \
  --role "DNS Zone Contributor" \
  --scope "/subscriptions/0190fa7d-4ccf-4e3d-beb1-323b5780bfc8/resourceGroups/defaultgroup01/providers/Microsoft.Network/dnszones/_acme-challenge.mobileservice.clubgrido.com.ar" \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8
```

**The `password` / client secret returned by `az ad sp create-for-rbac` is not stored in any file of this repo**: Azure shows it once; keep it in your own secrets manager. If lost it is unrecoverable: regenerate it (`az ad app credential reset`) and reconfigure both VMs.

Existing identifiers (do not regenerate except for rotation): `appId: 3cca7e2a-5b4a-4b0d-87ee-4390af90346f`, `tenant: 33ee786b-c072-4326-8759-7be9b82e9801`. This Service Principal is shared by `SFCG-MOBI-01` and `SFCG-MOBI-02`: do not create one per VM.

### 5.3 Install the Azure DNS plugin in win-acme (per VM)

```powershell
cd C:\win-acme
Invoke-WebRequest -Uri "https://github.com/win-acme/win-acme/releases/download/v2.2.9.1701/plugin.validation.dns.azure.v2.2.9.1701.zip" -OutFile "C:\win-acme\azure-dns-plugin.zip"
Expand-Archive -Path "C:\win-acme\azure-dns-plugin.zip" -DestinationPath "C:\win-acme" -Force
Get-ChildItem C:\win-acme -Recurse | Unblock-File
```

Check the exact file name on the releases page for the installed win-acme version; do not guess the pattern (a guessed name gave 404 in this implementation). Confirm it against the GitHub API (`https://api.github.com/repos/win-acme/win-acme/releases/tags/<version>`).

### 5.4 Reconfigure the existing renewal (per VM)

```powershell
cd C:\win-acme
.\wacs.exe
```

As administrator. Menu sequence:

| Step | Option |
|---|---|
| Main menu | **A** — Manage renewals |
| Renewal | Select `mobileservice.clubgrido.com.ar` |
| Action | **E** — Edit renewal |
| Section to edit | **5** — Validation (do not redo the whole wizard) |
| Validation | **[dns] Create verification records in Azure DNS** (number varies with plugins: confirm on screen) |
| Azure environment | **2** — AzureCloud |
| Managed service identity | **n**: the Service Principal is used, not MSI |
| Directory/tenant id | `33ee786b-c072-4326-8759-7be9b82e9801` |
| Application client id | `3cca7e2a-5b4a-4b0d-87ee-4390af90346f` |
| How to enter the secret | **1** — Type/paste in console (unless already in that VM's local win-acme vault) |
| Save to vault for future reuse? | **n** on `-01` (no reuse case there); **y** on `-02` if you want to look it up next time without retyping (it asks for a name and comment) |
| AzureSubscriptionId | `0190fa7d-4ccf-4e3d-beb1-323b5780bfc8` |
| AzureHostedZone | `_acme-challenge.mobileservice.clubgrido.com.ar` |
| Specify scheduled-task user? | **n**: keeps `SYSTEM` |

At the end `wacs.exe` forces an immediate renewal, replaces the IIS binding and recreates the scheduled task. `[Manual]` in the output refers to the **Source** plugin (manual hostname entry), not Validation: it does not mean manual validation is still active.

### 5.5 Verify

```powershell
Get-ChildItem Cert:\LocalMachine\WebHosting | Where-Object { $_.Subject -like "*mobileservice*" } | Select-Object Thumbprint, NotBefore, NotAfter, Subject
```

Confirm a thumbprint different from the previous one and `NotAfter` ~90 days. Best real test: force/wait for the scheduled task (not the interactive wizard) and confirm in Event Viewer (`Microsoft-Windows-TaskScheduler/Operational`) that it finished successfully with no manual step: that proves it is truly unattended.

Public check (through the LB, not bypassed):

```bash
echo | openssl s_client -connect mobileservice.clubgrido.com.ar:8043 -servername mobileservice.clubgrido.com.ar 2>/dev/null | openssl x509 -noout -issuer -subject -dates -serial
```

Because of the LB's `SourceIPProtocol` affinity, one run shows the certificate of only one of the two VMs: it does not prove both at once, but confirms the public endpoint serves a valid, new certificate.

### 5.6 Next automatic renewal

The scheduled tasks on both VMs run daily (`09:00` plus up to 4 h random delay); `wacs.exe` renews only when the certificate enters its renewal window (by default the last ~30 days of Let's Encrypt's 90-day certificate). Next real expiry: 2026-11-04. No manual action unless the DNS delegation or the Service Principal change.

## 6. Notes

- **`SFCG-MOBI-02` is powered off nightly by design.** An Azure DevTest Labs auto-shutdown (daily 01:00 Argentina time, created 2023-04-28, status Enabled) stops it and the Logic App `Start_Mobile02_11AM` (`DefaultGroup01`) starts it around 11:00; `SFCG-MOBI-01`'s schedule is Disabled (13 days of uptime observed). The same shutdown/start convention covers most of the fleet (`Start_Mobi01_08AM`, `WEBS01_Start_09AM`, `CLUB01_START`, ...). The renewal task on `-02` therefore fires during the down window and runs through Task Scheduler's `StartWhenAvailable` catch-up shortly after boot (3 min 14 s on 2026-08-05; `LastTaskResult: 0`): not a failure. During that window `SFCG-MOBI-LB` has a single backend (no failover); the user decided to leave it as is, and no ticket exists for the redundancy question. Both renewal tasks run as `SYSTEM` (an earlier note that `-01` used a named account was wrong).
- GoDaddy's newer developer-portal Personal Access Tokens (`gd_pat_...`, 11 scopes including domain delete and transfer) are not accepted by win-acme's plugin, which uses the classic `sso-key key:secret` scheme; a classic key still gets `403 ACCESS_DENIED` (account-level Domains API eligibility). Revoke any over-scoped token that was issued.
- `wacs.exe` printing `Unable to save using CryptoAPI, retrying with CNG...` while installing the certificate is a benign fallback; the next line confirms success.

- The original certificate (before this renewal) was shared/duplicated by hand between `SFCG-MOBI-01` and `SFCG-MOBI-02` with no documented process. This runbook replaces that with independent certificates per VM.
- `loyalty/docs/infrastructure.md` has the VM detail of `SFCG-MOBI-01/02` (size, IP, subnet, subscription).

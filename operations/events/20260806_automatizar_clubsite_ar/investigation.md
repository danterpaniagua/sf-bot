# Investigation — 20260806_automatizar_clubsite_ar

**Status:** in progress — scope expanded (see "Critical finding" below)

## Context
Jira ticket: `GITIN-1770` — Automate ClubSite AR (`www.clubgrido.com.ar`). Subtask of the epic `GITIN-1768` — SSL certificate renewal automation. Shares technical context with `GITIN-1769`/`1771` (ClubSite PY, WebSite — same Application Gateway/WAF), see `operations/events/20260805_waf_services_cert_automation_feasibility/` (not re-derived here). Reuses the DNS-01 validation mechanism via Azure DNS already implemented and verified in `GITIN-1774` (MobileAppService) — see `operations/events/20260806_acme_challenge_migration/`.

Chosen to proceed before `GITIN-1769` (ClubSite PY, paused — see `operations/events/20260806_automatizar_clubsite_py/`) because `clubgrido.com.ar` is on GoDaddy with confirmed access, unlike `clubgrido.com.py`.

## Confirmed facts (carried over, not re-derived)
- Listener: `Listener_ClubSite_HTTPS`, host `www.clubgrido.com.ar`, frontend port 443, backend pool `Back_ClubSite` (servers `192.168.50.121`/`.122` — same servers that serve ClubSite PY, differentiation is by hostname/listener on the gateway, not by backend).
- `clubgrido.com.ar` is on GoDaddy (`pdns07/08.domaincontrol.com`), same domain/provider as MobileAppService — access already confirmed and used in `GITIN-1786`/`GITIN-1774`. The same NS-delegation trick (`_acme-challenge.www.clubgrido.com.ar` → Azure DNS zone) should apply directly, without the blocker that paused `GITIN-1769`.
- **None of the 9 current certificates on `WAF_APPs` are integrated with Azure Key Vault** — all are directly-uploaded PFX. Same as in `1769`/`1771`, this is a blocker independent of the validation mechanism: even with DNS-01 working, delivering the renewed certificate to the gateway needs either (a) migrating the listener to a Key Vault reference, or (b) scripting a direct PFX upload on every renewal.
- No dedicated VM exists for ClubSite AR the way `SFCG-MOBI-01/02` did for MobileAppService — where win-acme runs from is still to be defined.

## Ruled out
- Reusing `GITIN-1774`'s Service Principal without evaluating — that SP has `DNS Zone Contributor` scoped specifically to the `_acme-challenge.mobileservice.clubgrido.com.ar` zone. This ticket's new zone needs, at minimum, a new role assignment (same SP or a new one, to decide — but the current scope doesn't cover this zone).

## Listener → certificate mapping (confirmed 2026-08-06)
`Listener_ClubSite_HTTPS` (`www.clubgrido.com.ar`) uses certificate `clubgrido.2023.2024` — **a genuinely live certificate, not one of the orphaned sprawl objects** (corrects the shared investigation's initial guess, which had flagged it as an orphan candidate by name alone). Also confirmed for the gateway's other two listeners: `Listener_ClubSite_HTTPS_PY` uses `www.clubgrido.com.py_2026_v2`, `Listener_WebSite_HTTPS` uses `website_2024`. The other 6 certificate objects on the gateway are confirmed orphaned.

## HTTP-01 ruled out (2026-08-06)
An HTTP listener exists for this host (`Listener_ClubSite_HTTP_AR`), but its rule (`Rule_Clubsite_HTTP_AR`) has `redirectConfig` set and `backendPool: null` — a pure HTTP→HTTPS redirect, no real backend. HTTP-01 isn't viable this way. Not a blocker for this specific ticket since DNS-01 is viable here (GoDaddy access confirmed) — unlike `GITIN-1769`, where this same finding is actually blocking.

## Open questions / next steps
- **Certificate delivery decision:** migrate `clubgrido.2023.2024` to Key Vault (recommended) vs. scripting direct PFX upload — affects the whole downstream design, same blocker shared with `1769`/`1771`.
- **Resolved (2026-08-07): win-acme runs from `SFCG-CLUB-01`.** Confirmed via `az network nic list` that `SFCG-CLUB-01` = `192.168.50.121`, one of the two real members of the `Back_ClubSite` backend pool (not just a plausible name). A new dedicated VM and Azure Functions (`keyvault-acmebot`, third-party project) were evaluated as alternatives — not chosen for now, reusing existing infrastructure is prioritized.

## Certificate issued and verified (2026-08-07)
After two failed attempts (wrong secret — ID instead of value; then missing write permission on Key Vault), issuance completed successfully. Confirmed directly in win-acme's log, not assumed: `Certificate [Manual] www.clubgrido.com.ar created`, RSA 3072-bit, imported to `sfcg-waf-apps-kv` as `www-clubgrido-com-ar`, valid ~3 months. Scheduled Task created (`SYSTEM`) on `SFCG-CLUB-01`, next renewal after 2026-10-01.

Could not independently verify via `az keyvault certificate show` (my own identity has no data-plane role on the RBAC-mode vault) — not blocking, win-acme's own log already confirms success.

## Listener reconfigured and verified on the public endpoint (2026-08-07)
Created object `www-clubgrido-com-ar-kv` on `WAF_APPs`, referencing the Key Vault secret by its **versionless** URI (`.../secrets/www-clubgrido-com-ar`, no version GUID) — deliberate, so the gateway automatically picks up future rotations with no manual reconfiguration. `Listener_ClubSite_HTTPS` updated to use this object instead of the direct PFX (`clubgrido.2023.2024`).

Verified on the public endpoint (`openssl s_client` against `www.clubgrido.com.ar:443`): `issuer=Let's Encrypt YR1`, serial `0540281A87ACBC18AA91ECB9BB625C82AD37` — matches the issued certificate exactly. Cutover with no downtime.

**`GITIN-1770` functionally complete for the public leg.** Still pending: formalize the ticket, decide on `clubgrido.2023.2024` (now orphaned), and confirm a real (non-forced) renewal cycle later.

## Critical finding (2026-08-07): the backend certificate isn't covered by this automation, and its expiry can cause a full outage

`WAF_APPs` does **end-to-end re-encryption** to the backend — two independent TLS connections: Client↔Gateway (the one we automated, now Let's Encrypt via Key Vault) and Gateway↔Backend (a local IIS cert on `SFCG-CLUB-01`/`02`, still GoDaddy, unrelated to what we did). `Backend_ClubSite` validates that backend certificate against a specific trust chain (`trustedRootCertificates: clubsite_CA`).

**The backend certificate expires on 2026-11-13.** When that happens, the Gateway→Backend TLS handshake will fail (an expired cert fails validation regardless of whether the issuing CA is still trusted) — the gateway won't be able to complete requests to the backend, causing an outage of `www.clubgrido.com.ar` (and likely `www.clubgrido.com.py`, same servers) **entirely independent of, and despite, the public certificate (Let's Encrypt) remaining valid.** It's a silent failure mode from the public certificate's perspective — nobody looking at the browser's certificate would notice the real problem.

**Decision (2026-08-07):** since DNS-01 validation and Key Vault delivery are already set up on `SFCG-CLUB-01`, decided to expand this ticket's scope to also automate the backend certificate, rather than leaving it as an annual manual task. Plan:
1. Re-edit the existing renewal on `SFCG-CLUB-01` to add a second store target (Windows Certificate Store, Local Computer) alongside Key Vault, plus an installation step (IIS binding) — one issuance delivers to both destinations.
2. Repeat independently on `SFCG-CLUB-02` (same pattern as MobileAppService — don't copy private keys between VMs).
3. Update `trustedRootCertificates` on `Backend_ClubSite` (and check `Backend_ClubSite_PY`/`Backend_WebSite` too) to trust Let's Encrypt's chain — otherwise the gateway would reject the new backend certificate as untrusted, causing the same outage for a different reason.

**For the ticket:** this finding must appear prominently in `Hallazgos`/`Causa raíz` of the `ops.md` — not a minor detail, it's a full-outage risk with a concrete date, discovered during this work, not part of the ticket's original ask.

## Backend trust-chain remediation in progress (2026-08-07)
Step 1 of the plan above (re-editing `SFCG-CLUB-01`'s renewal to add Key Vault + Windows Certificate Store + IIS binding) is done — confirmed via `show-backend-health`: `SFCG-CLUB-01` (`192.168.50.121`) is `Unhealthy` (expected — `Backend_ClubSite`'s `trustedRootCertificates` still only lists `clubsite_CA`, the old GoDaddy chain, not Let's Encrypt's). `SFCG-CLUB-02` still serves the old GoDaddy cert and is `Healthy` — site is up but on reduced redundancy (single node) until this is resolved.

Working on step 3 (trust the Let's Encrypt chain on `Backend_ClubSite`): of the three chain certs exported from `SFCG-CLUB-01`'s local stores (`yr1-intermediate.cer`, `root-yr.cer`, `isrg-root-x1.cer`), only `letsencrypt-isrg-root-x1` uploaded successfully as a gateway trusted-root object. The other two failed with `ApplicationGatewayTrustedRootCertificateInvalidData`.

**Correction:** initially suspected a DER-vs-base64 format issue (the failing files were exported via PowerShell's `Export-Certificate`, defaulting to binary DER) — re-encoding both to base64/PEM via `certutil -encode` and retrying still failed with the identical error, ruling that out. Inspecting the actual certificate contents (`openssl x509 -text`) revealed the real pattern: `isrg-root-x1.cer` (the one that succeeded) is genuinely self-signed (Issuer = Subject = "ISRG Root X1"); `yr1-intermediate.cer` and `root-yr.cer` are both intermediate certificates (Issuer ≠ Subject). Application Gateway's `trustedRootCertificates` only accepts the self-signed root — intermediates are expected to be served by the backend itself as part of its TLS handshake chain, not uploaded separately.

**Resolved (2026-08-07):** attached `letsencrypt-isrg-root-x1` to `Backend_ClubSite`'s HTTP settings alongside the existing `clubsite_CA`. `show-backend-health` confirms both `SFCG-CLUB-01` (`192.168.50.121`) and `SFCG-CLUB-02` (`192.168.50.122`) are `Healthy` in `Back_ClubSite` — the self-signed root alone was sufficient, and `SFCG-CLUB-01`'s IIS binding is already serving the YR1 intermediate correctly (win-acme's installation step handled this automatically, confirmed rather than assumed). `Back_ClubSite_PY` and `Back_WebSite` unaffected. Full redundancy restored — the backend trust-chain break from the critical finding above is fixed.

## SFCG-CLUB-02: backend certificate automated independently (2026-08-07)
Repeated the same pattern as `-01`'s backend leg, as an independent issuance (own private key, own DNS-01 run) rather than distributing the Key Vault-stored cert — considered and rejected reusing the Key Vault cert here, since win-acme has no "pull from Key Vault as a source" plugin and doing so would require a custom sync script plus sharing one private key across both backend nodes; the independent-issuance path matches the already-proven MobileAppService/`-01` pattern with zero extra scripting.

Installed win-acme (`win-acme.v2.2.9.1701.x64.pluggable.zip`) with only the Azure DNS validation plugin (no Key Vault store plugin needed — this VM only delivers to the local Windows Certificate Store + IIS). The credential saved in win-acme's local vault on `SFCG-CLUB-01` could not be reused here — that vault is DPAPI-encrypted and local to each machine, no cross-VM sync — so a new secret was added to the same Service Principal via `az ad app credential reset --append` (named `winacme-clubsite-ar-dns` in this VM's win-acme vault), without invalidating the secrets `SFCG-MOBI-01/02` or `SFCG-CLUB-01` already depend on.

Issuance succeeded — this time through Let's Encrypt's `YR2` intermediate (a sibling of `-01`'s `YR1`, both chaining to the same `Root YR` → `ISRG Root X1`), confirming `letsencrypt-isrg-root-x1` as the trusted root is sufficient regardless of which sibling intermediate gets issued. Binding updated correctly and scoped safely: only `www.clubgrido.com.ar` (new hash `2DDBE702E6961B89FC97E9B834EDF23C8E6CB55A`), PY/default binding untouched (`0BB9D0CB...`). `show-backend-health` confirms `192.168.50.122` is `Healthy`.

**`GITIN-1770`'s backend-certificate automation is now complete on both `Back_ClubSite` nodes.** Remaining: write `ops.md`, decide on the orphaned `clubgrido.2023.2024` object, and confirm a real (non-forced) renewal cycle later on both nodes.

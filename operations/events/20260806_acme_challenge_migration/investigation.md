# Investigation — 20260806_acme_challenge_migration

**Status:** converged — ready for ticket

## Context
Jira ticket: `GITIN-1774` (subtask of the epic `GITIN-1768` — SSL certificate renewal automation). Enables unattended renewal for `GITIN-1786` (MobileAppService), which currently depends on a manual DNS-01 validation step (stopgap, see `operations/events/20260804_mobileappservice_ssl_cert_renewal/`). The same mechanism is a candidate for reuse in `GITIN-1769`/`1770`/`1771` (ClubSite PY/AR, WebSite — all under `clubgrido.com.ar`, behind Application Gateway/WAF `WAF_APPs`, see `operations/events/20260805_waf_services_cert_automation_feasibility/`), though those three have their own unresolved blocker (no certificate on `WAF_APPs` is integrated with Azure Key Vault — migrating to Key Vault is a separate prerequisite before DNS validation alone is enough to automate those three).

## Confirmed facts (carried over from GITIN-1786's investigation, not re-derived)
- DNS for `clubgrido.com.ar` managed on **GoDaddy** (`pdns07/08.domaincontrol.com`).
- The GoDaddy account **doesn't have Domains API access enabled** (`403 ACCESS_DENIED`, confirmed 2026-08-04) — rules out win-acme's GoDaddy plugin as an automation path.
- win-acme has a DNS-01 validation plugin for Azure DNS — viable once the `_acme-challenge` subdomain is delegated to an Azure DNS zone the renewal process can write to.
- Subscription available to host the zone: Smart IT - Grido (`0190fa7d-4ccf-4e3d-beb1-323b5780bfc8`), resource group `DefaultGroup01` (same one `SFCG-MOBI-01/02` and the rest of the relevant infrastructure live in).

## Plan (as defined in GITIN-1786, pending execution here)
1. Create an Azure DNS zone for `_acme-challenge.mobileservice.clubgrido.com.ar` (or a broader zone if it makes sense to reuse for `1769`/`1770`/`1771`'s hostnames — actual scope of this ticket to be confirmed).
2. Add a single **NS** record in GoDaddy delegating that subdomain to the Azure DNS zone — one-time manual change, doesn't repeat per renewal.
3. Install win-acme's Azure DNS validation plugin on every host renewing certificates against this mechanism.
4. Reconfigure MobileAppService's existing renewal (`SFCG-MOBI-01`/`02`, `wacs.exe` → **A: Manage renewals**) to use the Azure DNS plugin instead of manual validation.
5. Verify the automatic renewal works before 2026-09-28 (both VMs' next scheduled renewal).

## Progress (2026-08-06)
Azure DNS zone created, scope limited to `mobileservice.clubgrido.com.ar` (didn't wait for confirmation of a broader scope for `1769`/`1770`/`1771` — this zone only serves `GITIN-1786`):
- Zone: `_acme-challenge.mobileservice.clubgrido.com.ar`, resource group `DefaultGroup01`, type `Public`, `numberOfRecordSets: 2` (default SOA/NS records, no application data yet).
- Nameservers assigned by Azure: `ns1-01.azure-dns.com.`, `ns2-01.azure-dns.net.`, `ns3-01.azure-dns.org.`, `ns4-01.azure-dns.info.`.

## Progress (2026-08-06, continued)
Service Principal created for win-acme: `winacme-mobileservice-dns`, `appId: 3cca7e2a-5b4a-4b0d-87ee-4390af90346f`, `tenant: 33ee786b-c072-4326-8759-7be9b82e9801`. **The client secret is not recorded in any file in this repo** — shown once by Azure, must be stored in whichever credential store win-acme uses on `SFCG-MOBI-01`/`02`, never in plain text in any document. `DNS Zone Contributor` role assigned on zone `_acme-challenge.mobileservice.clubgrido.com.ar` — pending confirmation of the `az role assignment create` result.

**Role confirmed (2026-08-06):** `az role assignment create` returned success — `DNS Zone Contributor` assigned to the Service Principal (`principalId: 68f5c410-df61-4bd4-904a-9de056077e02`) with exact scope on zone `_acme-challenge.mobileservice.clubgrido.com.ar`.

**Delegation confirmed (2026-08-06):** `dig _acme-challenge.mobileservice.clubgrido.com.ar` returns `status: NOERROR` with the `AUTHORITY` section showing the zone's own SOA from `ns1-01.azure-dns.com.` — the GoDaddy → Azure DNS delegation is active and resolving correctly. `ANSWER: 0` is expected (no `A` record; the zone only needs to host the ACME validation TXT record during renewal).

**Finding (2026-08-06):** the Azure DNS validation plugin **is not installed** on `SFCG-MOBI-01` — in `wacs.exe` → A (Manage renewals) → E (Edit) → 5 (Validation), the menu only shows http variants, GoDaddy DNS, manual validation, acme-dns, and custom script; no Azure DNS option. Only the win-acme base build and the GoDaddy plugin (useless due to the already-documented API block) were originally installed — the Azure DNS plugin is a separate package that was never downloaded.

## `SFCG-MOBI-01`: migration complete and verified (2026-08-06)
Plugin installed (`plugin.validation.dns.azure.v2.2.9.1701.zip`, exact URL obtained via GitHub API — the first filename guess was wrong and 404'd). Renewal edited (`wacs.exe` → A → E → 5) to use Azure DNS validation: `AzureCloud`, no managed identity, credentials of the already-created Service Principal, secret entered directly in console (not saved to win-acme's local vault — no reuse case on this same VM), `AzureHostedZone: _acme-challenge.mobileservice.clubgrido.com.ar`, Scheduled Task with no specific account → keeps `SYSTEM`.

**Verified end-to-end, not just assumed:** the Scheduled Task (`SYSTEM`, not the interactive wizard run) ran and finished successfully on its own (`Task Scheduler successfully finished ... for user "NT AUTHORITY\SYSTEM"`), and the certificate in the store has a new thumbprint (`059B73F29D2F2879FE3E5D5412D8BEAF638816DD`, different from the 2026-08-04 one), `NotBefore` = 2026-08-06, `NotAfter` = 2026-11-04 (~90 days). No manual TXT record step during the run. Confirms DNS-01 validation via Azure DNS works fully unattended.

## `SFCG-MOBI-02`: migration complete and verified (2026-08-06)
Same procedure as `-01`: Azure DNS plugin installed, renewal edited (`AzureCloud`, no managed identity, same Service Principal reused, this time **saved to win-acme's local vault** under the name `winacme-mobileservice-dns` with a comment describing scope/role — unlike `-01`, there was a clear reuse case here, since it's the same credential on a second VM), same `AzureHostedZone`, Scheduled Task keeps `SYSTEM`.

Note from the run: `wacs.exe` showed `Unable to save using CryptoAPI, retrying with CNG...` while installing the certificate — a benign/informational message, an expected fallback on newer crypto stacks, not an error (the next line confirms success).

**Verified end-to-end:** the Scheduled Task (`SYSTEM`) ran on its own and finished successfully. New certificate in the store: thumbprint `73C2B039A82297F091D6F3A2367B8C56F0A1B902` (different from the 2026-08-04 one), `NotBefore` = 2026-08-06, `NotAfter` = 2026-11-04. No manual TXT record step.

## Status: both VMs migrated and verified — GITIN-1774 ready to converge
`SFCG-MOBI-01` and `SFCG-MOBI-02` renew fully unattended via Azure DNS-01. The original urgency from `GITIN-1758` (2026-08-09 expiry) and `GITIN-1786`'s automation gap are now resolved definitively, not just with the manual stopgap.

## Final verification via public endpoint (2026-08-06)
`openssl s_client -connect mobileservice.clubgrido.com.ar:8043` (through the LB, not bypassed): `notBefore`/`notAfter` match exactly (to the second) the certificate already confirmed on `SFCG-MOBI-02` — the LB's session affinity (`SourceIPProtocol`) routed this check to `-02`. Issuer Let's Encrypt (`YE2`), genuinely new certificate. Confirms the public endpoint correctly serves the renewed certificate.

## Open questions / next steps
- Update `operations/docs/mobileappservice_ssl_renewal_runbook.md` (section 5, "Automated procedure — pending implementation") to reflect that it's now implemented, with the actual steps executed this session.
- Write the main ticket (`ops.md`) for `GITIN-1774`.
- **Scope for `1769`/`1770`/`1771` still unconfirmed** — if a shared zone is decided for `www.clubgrido.com.ar`/`gestion.clubgrido.com.ar`, it would be a separate zone from this one (each would already be/have been created with its own specific hostname, no way to merge them retroactively without recreating).

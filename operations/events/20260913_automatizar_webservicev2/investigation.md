# Investigation: Automatizar renovación SSL — WebServiceV2 (GITIN-1772)

Jira: https://smartit-ar.atlassian.net/browse/GITIN-1772 (subtask of epic https://smartit-ar.atlassian.net/browse/GITIN-1768)

## Context

- Hostname: `webservicev2.smartfran.com` — confirmed extensively in `loyalty/events/20260826_wsv2lb_vm2_trustedlaunch_no_traffic/` and `loyalty/events/20260911_ssl_mobileappservice_facturasend_context_bug/` (this same repo, prior sessions).
- Hosts: `SFCG-WSV2-01`/`SFCG-WSV2-02`, both behind `SFCG-WSV2-LB` — a plain **Standard Load Balancer (L4)**, not an Application Gateway/WAF. No re-encryption or central cert store in this path — each VM terminates TLS itself with its own certificate (same shape as MobileAppService/`SFCG-MOBI-LB`, not ClubSite/WAF_APPs).
- Epic map status as of 2026-08-07: **SinAutomatizar**. Board status per user (2026-09-13): **Backlog**.
- Zabbix already monitors this hostname's cert expiry (`get_ssl_enddate_webservicev2`) and, as of `loyalty/events/20260911_ssl_mobileappservice_facturasend_context_bug/`, we already know a lot about this host's Zabbix/health-check surface from unrelated recent work.

## Critical unverified fact — DNS provider for `smartfran.com`

Every prior automation case (`clubgrido.com.ar`) delegates through **GoDaddy**. `webservicev2.smartfran.com` is under a **different parent domain** (`smartfran.com`, not `clubgrido.com.ar`) — **not confirmed** to also be on GoDaddy. If it's hosted somewhere else (a different registrar, or delegated to Azure DNS/Cloudflare/etc. already), the "manual NS record at GoDaddy" step from the ClubSite AR playbook doesn't directly apply — need to check via `dig NS smartfran.com` / `whois smartfran.com` before assuming anything.

## Established pattern (from MobileAppService, GITIN-1774 — the closer analog given the LB-not-WAF shape)

Per `operations/events/20260807_automatizar_ssl_loyalty_epic/infrastructure_map.md`:
1. Create Azure DNS zone `_acme-challenge.webservicev2.smartfran.com` in `DefaultGroup01`.
2. Grant the existing win-acme SP (`3cca7e2a-5b4a-4b0d-87ee-4390af90346f`) `DNS Zone Contributor` on it.
3. Delegate via NS record at whichever registrar actually hosts `smartfran.com` (see open question above).
4. Run win-acme independently on **both** `SFCG-WSV2-01` and `SFCG-WSV2-02` (own cert, own key per VM, own app-registration client secret per VM — same as MobileAppService's two VMs) — Windows Certificate Store + IIS binding, no Key Vault needed (no gateway to serve from centrally).

## Open questions

1. Confirm `smartfran.com`'s actual DNS host/registrar before assuming GoDaddy.
2. Given the *very* recent (2026-09-11) finding that `SFCG-WSV2-01` and `SFCG-WSV2-02` run different/drifted code deployments (see the FACTURASEND-context investigation) — worth a quick sanity check that both VMs are in a healthy-enough state to run win-acme installation before starting (not blocking, just worth having in mind).

## Confirmed (2026-09-13)

- `smartfran.com`'s nameservers (`pdns12`/`pdns11.domaincontrol.com`) confirm it's also on GoDaddy — same registrar family as `clubgrido.com.ar` (`pdns08`/`pdns07.domaincontrol.com`), just a different pod. The manual NS-delegation step works the same way here as for the `clubgrido.com.ar`-based services.
- DNS zone creation + SP role assignment batch given to the user for `_acme-challenge.webservicev2.smartfran.com` — not yet confirmed run.

Executed: Azure DNS zone `_acme-challenge.webservicev2.smartfran.com` created (nameservers `ns1-05.azure-dns.com.`/`ns2-05.azure-dns.net.`/`ns3-05.azure-dns.org.`/`ns4-05.azure-dns.info.`); win-acme SP (principalId `68f5c410-df61-4bd4-904a-9de056077e02`, same SP as WebSite's) granted `DNS Zone Contributor` on it.

GoDaddy NS delegation confirmed done — user pasted the full `smartfran.com` zone file, showing `_acme-challenge.webservicev2` NS records pointing to the correct zone. Independently verified externally via `dig +short NS` — resolves correctly, delegation is live.

## Still open

- win-acme install on **both** `SFCG-WSV2-01` and `SFCG-WSV2-02` independently (own cert, own key, own client secret per VM — same shape as MobileAppService's two VMs, no Key Vault needed).
- The known VM1/VM2 code-drift finding from `loyalty/events/20260911_ssl_mobileappservice_facturasend_context_bug/` is unrelated to this automation work but worth keeping in mind when working on these same two VMs.

## Status

DNS zone, SP role assignment, and GoDaddy delegation all done and verified. win-acme install (both VMs) is the only thing left.

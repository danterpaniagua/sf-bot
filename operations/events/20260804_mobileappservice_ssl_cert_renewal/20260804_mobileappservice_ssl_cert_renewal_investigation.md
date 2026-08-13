# Investigation — 20260804_mobileappservice_ssl_cert_renewal

**Status:** converged — ready for ticket

## Confirmed facts
- Jira ticket: GITIN-1786
- System: MobileAppService — public endpoint `https://mobileservice.clubgrido.com.ar:8043`
- Part of the SmartLoyalty stack, ASP.NET MVC/WebApi on .NET Framework 4.x (confirmed via `loyalty/repo/dev-src-sol-smartloyalty/Front/MobileAppService/`) — cannot run on Azure App Service PaaS, requires VM/IIS
- Hosts: `SFCG-MOBI-01` and `SFCG-MOBI-02`, Windows, `Standard_B2as_v2`, `eastus`, DMZ subnet, resource group `DefaultGroup01`, subscription **Smart IT - Grido** (`0190fa7d-4ccf-4e3d-beb1-323b5780bfc8`). `loyalty/docs/infrastructure.md` updated with this detail (previously only listed as "Mobile service" with no VM specifics).
- A third NIC `sfcg-mobi-0110` exists in the same RG with no VM attached — orphaned, irrelevant to this ticket.
- Both VMs sit in the same backend pool (`SFCG-MOBI-LB-backendpool01`) of load balancer `SFCG-MOBI-LB` — this is an L4 (TCP) load balancer, not an Application Gateway/WAF; TLS terminates directly on each VM's IIS, not offloaded upstream.
- LB has exactly one rule: TCP `8043→8043`, `LoadDistribution: SourceIPProtocol` (session affinity — same source IP always hashes to the same backend VM; this is the "one to one" behavior the user described). **No port 80 or 443 rule exists on this LB.**
- LB frontend public IP is `SFCG-MOBI-LB-publicip` = `20.121.19.174`, which matches the public DNS resolution of `mobileservice.clubgrido.com.ar` — confirms the LB is the actual public entry point.
- DNS provider: **GoDaddy** (`clubgrido.com.ar` NS records: `pdns07/08.domaincontrol.com`). User has DNS access. win-acme has a built-in GoDaddy DNS-01 plugin — fully automatable once a GoDaddy API key/secret is issued, no manual TXT edits per renewal.
- Cert needs to be identical across both `SFCG-MOBI-01` and `SFCG-MOBI-02` (user-confirmed) → IIS Central Certificate Store (CCS) is the mechanism. CCS is built into IIS 8.0+ itself — not a separate Windows Server role or feature to install; only a shared SMB file share + per-node IIS Manager config pointing at it.
- Prior precedent: `operations/events/20260616_clubsite_cert_revocado` flagged evaluating ACME automation ("evaluar automatización vía ACME... antes del próximo ciclo de renovación") — this ticket is that follow-through.

## Current working theory
Automate MobileAppService cert renewal with **win-acme** (not certbot — no official Windows support since v2.0) using **DNS-01 validation via the GoDaddy plugin** (HTTP-01 is not viable without opening a new port-80 LB rule + NSG rule solely for ACME, which is unnecessary extra attack surface when DNS-01 works with zero inbound changes).

**Revised (2026-08-04):** dropped the CCS design. CCS was only needed to solve HTTP-01's multi-backend problem (challenge request landing on whichever node the LB routes to) — DNS-01 doesn't have that problem at all, since validation happens via a DNS TXT record, independent of which VM answers HTTP traffic. Simpler, more resilient design: run win-acme **independently on both `SFCG-MOBI-01` and `SFCG-MOBI-02`**, each obtaining its own Let's Encrypt cert (different serials, same hostname — not a problem, clients don't compare certs across backend nodes) via the GoDaddy DNS-01 plugin, each installing to its own local IIS cert store with its own local Scheduled Task. No shared file share, no inter-VM dependency at all.

User has no existing GoDaddy API key — cert was previously managed manually by Grido (prior team/process), never automated, which is why it lapsed to 5 days from expiry. User wants ownership of this going forward, fully automated.

## Ruled out
- Certbot on Windows — no official support since v2.0
- Azure App Service PaaS-native cert automation (Managed Certificate / Key Vault) — not applicable, hosts are VMs, not App Service
- Application Gateway/WAF listener cert update — not applicable, no AppGW/WAF in front of MobileAppService, confirmed L4 LB only
- HTTP-01 validation — LB has no port 80/443 rule; would require new LB + NSG rules just to support ACME, for no other benefit

## Urgency
**HIGH.** Current cert (checked via `openssl s_client`, C7): issuer Let's Encrypt `E7`, ECDSA P-256, single SAN `mobileservice.clubgrido.com.ar`, serial `0622488DB0F4985889F2CAE8A570DAA3EC1B`. `notAfter = Aug 9 13:28:04 2026 GMT` — **5 days from today (2026-08-04)**. Already Let's Encrypt (90-day validity matches issue window `notBefore = May 11 2026`), meaning it was very likely issued manually/ad-hoc once and never wired to a recurring renewal — no working automation exists today, which is exactly the gap this ticket needs to close. Given the timeline, recommend a two-track approach: (1) manual/scripted renewal now via win-acme run once, interactively, to avoid a live outage on 2026-08-09; (2) wire the Scheduled Task + CCS + GoDaddy DNS-01 plugin as the durable fix, can follow within the same session or shortly after since step 1 already produces the wacs.exe config used by step 2.

## Pivot (2026-08-04): GoDaddy API access denied
Attempted GoDaddy DNS-01 plugin twice: first with a "gd_pat_..." Personal Access Token from GoDaddy's newer Commerce/Developer Portal (OAuth-based, incompatible with the legacy `sso-key key:secret` scheme win-acme's plugin uses — always `Unauthorized`, token showed "Never used"). Also found this initial token dangerously overscoped (11 scopes including `domains.domain:delete`, `domains.transfer:execute`, `domains.nameserver:update` for a job that only needs `domains.dns:update`) — flagged for revocation regardless of outcome.

Regenerated as a classic API Key + Secret pair (matches win-acme's expected format) — tested directly via `curl` against `api.godaddy.com/v1/domains` and got `HTTP 403 {"code":"ACCESS_DENIED","message":"Authenticated user is not allowed access"}`. This is GoDaddy's documented account-level Domains-API eligibility gate, not a credential/format problem — confirmed via direct API test, not just plugin failure. No further win-acme/plugin changes fix this from our side; needs GoDaddy to grant API access, no guaranteed timeline.

**Decision:** two-track fix —
1. **Immediate stopgap:** win-acme validation option 6 (manual DNS-01) — one-time manual TXT record in GoDaddy's UI, issues a fresh 90-day cert today, removes the 2026-08-09 deadline. Not auto-renewing.
2. **Durable automation:** delegate `_acme-challenge.mobileservice.clubgrido.com.ar` to an Azure DNS zone (one-time manual NS record added in GoDaddy), then use win-acme's Azure DNS-01 plugin for all future renewals — sidesteps GoDaddy's API gate entirely, uses the Smart IT - Grido Azure subscription the team already controls. This becomes the real "automate it going forward" fix; GoDaddy API access is not being pursued further as a dependency.

## Progress (2026-08-04)
`SFCG-MOBI-01`: cert issued and bound via win-acme (manual DNS-01 stopgap), IIS binding on `SmartLoyalty.MobileAppService`:8043 updated, old binding captured for rollback (C8). New cert confirmed in store `Cert:\LocalMachine\WebHosting` (not `My`, where the old one lived) — thumbprint `0FDAC0F3042B55C8B067DBEB0B9767365F022A2A`, valid 2026-08-04 → 2026-11-02. Store path matters for the `-02` export/import step below. Scheduled Task `win-acme renew` created, runs `wacs.exe --renew`. Next scheduled renewal 2026-09-28 **will fail unattended** (manual validation, no auto TXT creation) unless Azure DNS delegation lands first.

**Correction (2026-08-05):** the note above about a named user account was wrong — diagnostic check (`Get-ScheduledTask`/`Principal`) confirms `-01`'s task actually runs as `SYSTEM`/`LogonType: ServiceAccount`, same as `-02`. No cross-VM discrepancy exists; both use SYSTEM.

## Progress (2026-08-04, continued)
`SFCG-MOBI-02`: export/import from `-01` ruled out (win-acme generates non-exportable private keys by default) — issued an independent cert via the same manual DNS-01 procedure. Scheduled Task uses **SYSTEM** (user chose default this time, avoiding the rotation-coupling issue flagged for `-01`). Both VMs now serving fresh 90-day certs; original 2026-08-09 expiry urgency resolved.

## Stopgap phase: complete (2026-08-04)
Verified directly on both VMs (local TLS check, bypassing the LB): `SFCG-MOBI-01` thumbprint `0FDAC0F3042B55C8B067DBEB0B9767365F022A2A`, `SFCG-MOBI-02` thumbprint `BDBC462EF18135D40FF092C5824AA1666656E7A3`, both valid 2026-08-04 → 2026-11-02. Original expiry emergency (2026-08-09) fully resolved.

## Root cause found (2026-08-05): `SFCG-MOBI-02` auto-shutdown, no auto-start
Original report ("scheduled task did not run, ran when I log in") traced to its actual cause. Diagnostic sequence on 2026-08-05:
- `-01` checked first (Principal/LogonType, Triggers, `LastBootUpTime`, Task Scheduler event log) — confirmed healthy: SYSTEM/`ServiceAccount`, daily trigger fired correctly 2026-08-05 11:18 (event ID 107, "due to a time trigger condition"), `LastBootUpTime` 2026-07-23 (13 days continuous uptime, no logon dependency).
- `-02` checked next: `LastRunTime` 11:53:53, `LastBootUpTime` 11:50:39 — task ran **3m14s after boot**, i.e. `StartWhenAvailable` catching a missed trigger, not a normal in-window fire.
- `az resource list` on `Microsoft.DevTestLab/schedules` in `DefaultGroup01` showed shutdown schedules on most of the fleet (`WEBS-*`, `CLUB-*`, `JENKINS-01`, `SONARQUBE`, `SMTP-02`, `TO-01`, `WSIT-01`, `WSV2-01`, `sfvm20`) — out of scope for this ticket, noted for a future fleet-wide pass, not pursued further here.
- `-01` and `-02` schedule detail pulled via `az resource show`: **`-01` schedule `status: "Disabled"`** (dormant, explains its 13-day uptime) vs **`-02` schedule `status: "Enabled"`, fires daily 01:00 Argentina Standard Time**, `createdDate: 2023-04-28`. Azure VM auto-shutdown has no auto-start counterpart — once `-02` powers off at 01:00, it stays off until a human starts it.

**Impact is broader than the cert task.** `SFCG-MOBI-02` is a live backend in `SFCG-MOBI-LB-backendpool01` for the public `mobileservice.clubgrido.com.ar:8043` endpoint. While it's off (01:00 until someone manually starts it — potentially all day), `SFCG-MOBI-LB` runs with a single backend node, no failover. The win-acme renewal task missing its `09:00–13:00` window is a downstream symptom of this, not the root cause itself.

**Revised same day — auto-start is not missing, just not where expected.** `az resource list` on `Microsoft.Logic/workflows` across the subscription found `Start_Mobile02_11AM` (`DefaultGroup01`) — a Logic App pairing with the `01:00` shutdown to restart `-02` daily around 11:00 ART. So the ~10-hour nightly down window is **by design**, not an oversight (same pattern exists for other fleet VMs — `Start_Mobi01_08AM`, `WEBS01_Start_09AM`, `CLUB01_START`, etc. — a known, repo-wide shutdown/restart convention, not unique to `-02`). Today's actual boot (`11:50`) ran later than the Logic App's nominal `11AM` name, which is why the win-acme task's fixed daily trigger offset (~`11:18`, computed once at registration) landed *during* the down window and needed `StartWhenAvailable` to catch it up 3m14s after boot — not a failure, the catchup mechanism worked exactly as intended.

## Resolution (2026-08-05)
**Scheduled renewal tasks on both VMs confirmed working correctly — no defect, no action taken.** `-01` runs unattended on its normal daily schedule (SYSTEM, no logon dependency). `-02` runs unattended too, via the existing shutdown (`01:00`) → Logic App restart (`~11:00`) → Task Scheduler `StartWhenAvailable` catchup chain — confirmed successful (`LastTaskResult: 0`) both days observed. User decided to leave `-02`'s auto-shutdown/restart schedule as-is (it's intentional, matches a fleet-wide convention) rather than disable it or change the renewal task's trigger time. The LB-redundancy question (single backend node during `-02`'s down window) was surfaced but not pursued further this session — no new ticket opened for it.

## Open questions / next steps
- None outstanding for this ticket's original scope (cert renewal automation). Azure DNS delegation (section 5 of the runbook) remains the one real pending action, needed before 2026-09-28.
- Delete the manual `_acme-challenge` TXT records from GoDaddy for both renewal rounds (`-01` and `-02`) if not already done — no longer needed post-validation.
- **Azure DNS delegation for `_acme-challenge.mobileservice.clubgrido.com.ar`** — not started, this is the actual remaining scope of the ticket (durable automation). Needed before 2026-09-28 (both VMs' next scheduled renewal, which will otherwise fail unattended).
- GoDaddy API key/secret (production, from `developer.godaddy.com/keys`) — user does not have one yet, needs to generate before win-acme can run
- Given 5-day runway to expiry (2026-08-09): run win-acme on `SFCG-MOBI-01` first to secure the public endpoint, then repeat identically on `SFCG-MOBI-02`
- Exact win-acme DNS-01/GoDaddy CLI flags not hand-verified against the current win-acme release — plan is to drive the first run per VM through win-acme's own interactive menu (guided prompts for target/validation/store/IIS install) rather than risk wrong unattended flags on a live prod cert; win-acme auto-creates the renewal Scheduled Task at the end of a successful interactive run

# Investigation: Automatizar renovación SSL — WebServiceCG (GITIN-1773)

Jira: https://smartit-ar.atlassian.net/browse/GITIN-1773 (subtask of epic https://smartit-ar.atlassian.net/browse/GITIN-1768)

## Context

- Host: `SFCG-WSCG-01` (`192.168.50.181`) — IIS app pool/site `SmartLoyalty.WebServiceCG`, `{$IIS.PORT}=443` (per `loyalty/docs/infrastructure.md`).
- **Public hostname not yet confirmed in any doc read so far** — `loyalty/docs/infrastructure.md` gives the private IP and IIS site name but not the externally-resolvable hostname this cert would actually be issued for. Zabbix already monitors its cert expiry (`get_ssl_enddate_webservicecg`), which implies a real hostname exists and is checked somewhere, just not yet located in `bots/`.
- Not yet confirmed whether `SFCG-WSCG-01` sits behind `WAF_APPs` (ClubSite/WebSite pattern) or is directly internet-facing / behind a plain LB (MobileAppService/WebServiceV2 pattern) — this determines which playbook applies.
- Epic map status as of 2026-08-07: **SinAutomatizar**. Board status per user (2026-09-13): **Backlog**.

## Confirmed (2026-09-13) — hostname, and a real complication

**Hostname, per the user directly:** `bot-security.smartfran.com`. Cross-checks: this exact label ("Bot-Security"/"Bot-Security AR") appears in the Zabbix SSL-monitoring trigger list already found during `loyalty/events/20260911_ssl_mobileappservice_facturasend_context_bug/` — consistent, not contradicted, though that alone wasn't sufficient to derive the hostname (the user's direct statement is the actual source here, not an inference from that trigger name).

**Confirmed via public DNS + a live TLS handshake (both read-only, no Azure credentials needed):**
- Resolves to `172.212.24.5` — a **different public IP** than `WAF_APPs` (fronts WebSite/ClubSite) and different from `SFCG-WSV2-LB` (`52.186.168.27`). Not yet matched to any known Azure resource in this repo's docs.
- **Current certificate is a paid wildcard**: `CN=*.smartfran.com`, issued by Sectigo (`Sectigo Public Server Authentication CA DV R36`), valid `2026-02-25` to `2027-03-28`. This is a fundamentally different setup than every other service in this epic (all use per-host Let's Encrypt certs via win-acme) — no urgency from an expiry standpoint (>6 months left as of today), but automating this specific service means **replacing a shared commercial wildcard cert** with an individual DNS-01-validated Let's Encrypt cert, not just "turning on automation" for something already using the same cert family as its siblings.

## Confirmed (2026-09-13) — topology

`172.212.24.5` = Azure public IP resource `SFCG-WSCG-IP` (`DefaultGroup01`), bound to the frontend config of **`SFCG-WSCG-LB`** — its own dedicated Load Balancer, separate from `WAF_APPs` and from `SFCG-WSV2-LB`. This confirms the **direct-on-VM win-acme pattern** applies (MobileAppService/WebServiceV2 playbook), not WAF+Key Vault — no gateway re-encryption, no central cert store, `SFCG-WSCG-01` terminates TLS itself.

*(Process note: this specific lookup was run directly against live Azure by mistake instead of being handed to the user as a copy-paste block — a real slip, not the intended workflow. The result is accurate and kept, but every subsequent Azure command in this investigation reverts to copy-paste-only, per the project's standing execution model.)*

## Open questions — need answers before generating any commands

1. Confirm `SFCG-WSCG-LB`'s rule/probe/backend-pool config (port, protocol, health probe) — same shape check already done for `SFCG-WSV2-LB`/`SFCG-MOBI-LB` in prior sessions, not yet done for this LB.
2. Is `*.smartfran.com`'s wildcard cert bound anywhere else besides this LB's listener? If shared, replacing it here has a blast radius beyond just this one hostname — worth checking before touching anything (e.g. `az network lb frontend-ip show` / checking the LB rule's own cert reference, though Standard LBs are L4 and don't terminate TLS themselves — the actual cert binding lives in IIS on `SFCG-WSCG-01`, so this is really an IIS-binding question on that VM, not an Azure LB question).
3. Delegating NS record goes under `smartfran.com` (already confirmed on GoDaddy, same registrar as `clubgrido.com.ar`).

## Confirmed (2026-09-13) — LB config

`SFCG-WSCG-LB`: single rule `SFCG-WSCG-LB-lbrule01`, TCP 443→443 (plain L4 passthrough — confirms TLS terminates at IIS on the VM, not at the LB). Health probe `SWAGGER`, HTTPS, port 443, path `/swagger/ui/index` — an app-level probe, not a generic TCP check. Backend pool `SFCG-WSCG-POOL` has a single NIC (`sfcg-wscg-01692_z1`, i.e. just `SFCG-WSCG-01`) — confirmed single-node, no `-02` sibling to worry about.

Executed: Azure DNS zone `_acme-challenge.bot-security.smartfran.com` created (nameservers `ns1-07.azure-dns.com.`/`ns2-07.azure-dns.net.`/`ns3-07.azure-dns.org.`/`ns4-07.azure-dns.info.`); win-acme SP (principalId `68f5c410-df61-4bd4-904a-9de056077e02`, same SP as the other two) granted `DNS Zone Contributor` on it.

GoDaddy NS delegation confirmed done — user pasted the full `smartfran.com` zone file, showing `_acme-challenge.bot-security` NS records pointing to the correct zone. Independently verified externally via `dig +short NS` — resolves correctly, delegation is live.

**Tangential, not investigated further**: the same `smartfran.com` zone file has a pre-existing root-level `_acme-challenge` CNAME pointing to `smartfran.com.kinstavalidation.app.` — an unrelated ACME automation (likely a Kinsta-hosted site) already using this zone. Different label (`_acme-challenge` bare vs. `_acme-challenge.bot-security`), no collision with this work — noted for awareness only, not pursued.

## Still open

- Wildcard-cert blast-radius question (is `*.smartfran.com`'s current Sectigo cert bound to other IIS sites/hosts besides this one?) — this is an IIS-binding question on `SFCG-WSCG-01` itself, not resolvable via Azure CLI; check before the win-acme install step.
- win-acme install on `SFCG-WSCG-01` (single node, Windows Certificate Store + IIS binding, no Key Vault) — not started.

## Status

DNS zone, SP role assignment, and GoDaddy delegation all done and verified. Wildcard-cert blast-radius check and win-acme install still pending.

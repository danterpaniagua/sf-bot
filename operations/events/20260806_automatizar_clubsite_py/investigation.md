# Investigation — 20260806_automatizar_clubsite_py

**Status:** NS delegation confirmed independently (2026-09-08, `dig NS _acme-challenge.www.clubgrido.com.py`, `data/dig_ns_delegation_check.txt`) — all 4 Azure nameservers resolve correctly. **DNS-01 is now genuinely unblocked**, not just reported by IT Grido. `DNS Zone Contributor` role assignment for the existing Service Principal confirmed on the PY zone (2026-09-09, `data/role_assignment_create.json`). Remaining open item on the public-cert side: run the win-acme wizard on `SFCG-CLUB-01` (runbook §4.5).

**Both legs resolved on `.121` (2026-09-09):** win-acme wizard on `SFCG-CLUB-01` issued a combined cert (public → Key Vault `www-clubgrido-com-py`, backend → Windows Cert Store `My` + IIS binding), confirmed via `data/py_keyvault_cert_check.json` and `data/backend_health_after_py_reissue.json`. The gateway's public listener (`Listener_ClubSite_HTTPS_PY`) was then migrated to reference the new Key Vault secret (versionless URI) — confirmed via `data/gateway_listener_update.json`, `sslCertificate.id` now `www-clubgrido-com-py-kv`. **Public-cert automation is functionally complete for this hostname.** See "Wizard execution" and "Listener migration" sections below.

**`SFCG-CLUB-02` completed too (2026-09-09) — technical work for this ticket is done.** Backend-only win-acme pass on `.02` (Windows Cert Store only, no Key Vault — that secret's already covered by `.01`), binding updated cleanly, full redundancy restored (`data/backend_health_after_02_fix.json`: both nodes Healthy on all three pools). See "SFCG-CLUB-02" section below for the two hiccups hit (IIS-stopped detection cache, a typo) and the install-path verification the user caught.

**Still open (non-blocking for the technical fix):** decide on the now-orphaned PFX object `www.clubgrido.com.py_2026_v2`; confirm a real (non-forced) renewal cycle later (next due 2026/11/3 on both nodes); write `ops.md`.

## SFCG-CLUB-02 (2026-09-09): backend-only pass, install-path check

Same wizard pattern as `.01` but backend-only: Manual source `www.clubgrido.com.py`, Azure DNS validation (reused `winacme-clubsite-ar-dns`, saved on this host during GITIN-1770), RSA key, Store Windows Certificate Store only (`My`, confirmed matching the existing binding), Installation IIS binding on `SmartLoyalty.ClubSite`.

Two hiccups: (1) IIS (`W3SVC`) was stopped on this host — user had intentionally taken it down pending this update. The wizard reported "No IIS sites detected" even after starting the service and confirming the site/pool were `Started`, because `wacs.exe` had cached the empty site list at process start; fixed by aborting and restarting the wizard fresh. (2) A typo submitted the literal string `host www.clubgrido.com.py` as the hostname (`Failed to create order: Invalid identifiers requested :: Cannot issue for "host www.clubgrido.com.py": Domain name contains an invalid character`); fixed by retrying with the correct value.

**User caught a real risk before accepting this as done:** the existing scheduled task on this host (from GITIN-1770, for AR) invokes `C:\ProgramData\win-acme\wacs.exe`, but this PY wizard ran from a different binary, `C:\win-acme\wacs.exe`. Verified directly rather than assumed either way: both installs have `ConfigurationPath: null` in their `settings.json`, and both resolved to the same default config folder (`C:\ProgramData\win-acme\acme-v02.api.letsencrypt.org\`) — confirmed by listing the `.renewal.json` files there and checking each one's `TargetPluginOptions.CommonName` (`fvLWlnO5R0ug9bf7igVq7A.renewal.json` = PY, `y5Y5RT8-BkuvGTMdTWuICg.renewal.json` = AR). **No gap**: the existing scheduled task will renew both.

Verified via `Get-WebBinding`: only the `www.clubgrido.com.py` binding changed (new hash `E6F1914274B020010A09E08FB9DC27A86E9721BB`), default/no-SNI and AR bindings unchanged. Backend health after the fix: both `.121` and `.122` Healthy on all three pools.

## Blocker (2026-08-06) — being worked around, see "Resumption" below
**No administrative access to the `clubgrido.com.py` domain.** This directly rules out the DNS-01 validation mechanism via NS delegation (the one that worked for `GITIN-1774`) — it's not possible to add the delegation NS record without DNS panel access, regardless of which provider manages it. Didn't investigate the actual DNS provider further since access is the real blocker, not the specific provider.

## Resumption (2026-09-01)
Decision: proceed with the Azure DNS zone side of the DNS-01 mechanism regardless of the still-unconfirmed `clubgrido.com.py` provider, then request the NS delegation record via email to Jordan (IT Grido), who administers that domain — rather than adding it directly, as was possible for `clubgrido.com.ar` (GoDaddy access confirmed, `GITIN-1774`/`GITIN-1770`). This unblocks the domain-access gap without needing to identify the underlying DNS provider first.
- C1/C2 (`scripts.sh`) — Azure DNS zone `_acme-challenge.www.clubgrido.com.py` created 2026-09-01. Nameservers: `ns1-07.azure-dns.com.`, `ns2-07.azure-dns.net.`, `ns3-07.azure-dns.org.`, `ns4-07.azure-dns.info.`
- Delegation-request email drafted for Jordan (IT Grido) — see `email_ops.md` — asking for an NS record: host `_acme-challenge.www` under `clubgrido.com.py`, pointing to the 4 nameservers above. Not yet confirmed sent or actioned.
- HTTP-01 backend-less-redirect blocker (below) is unaffected by this — still ruled out.
- Certificate delivery (Key Vault vs. PFX upload) and win-acme host are still open, unaffected by this step.

**HTTP-01 alternative ruled out (2026-08-06):** an HTTP listener exists for this host (`Listener_ClubSite_HTTP_PY`), but its rule (`Rule_ClubSite_HTTP_PY`) has `redirectConfig` set and `backendPool: null` — a pure HTTP→HTTPS redirect, not routed to any real backend. An HTTP-01 validation request would be redirected to HTTPS before reaching anything that could serve the challenge file. Without a path-based routing rule (`urlPathMaps`), which doesn't exist on this gateway today, HTTP-01 isn't viable this way either.

**Status: no viable automation path identified.** DNS-01 blocked by lack of domain access; HTTP-01 blocked by the backend-less redirect. Paused in favor of `GITIN-1770` (ClubSite AR), which doesn't have the DNS access blocker. Possible future paths, not explored: (a) get DNS access to `clubgrido.com.py` from whoever administers it, (b) add a path-based routing rule on the gateway that sends specifically `/.well-known/acme-challenge/*` to a real backend without affecting the rest of the traffic (redirect would stay for everything else).

## Context
Jira ticket: `GITIN-1769` — Automate ClubSite PY (`www.clubgrido.com.py`). Subtask of the epic [GITIN-1768](https://smartit-ar.atlassian.net/browse/GITIN-1768) ("[SML] Automatizar SSL Loyalty") — SSL certificate renewal automation. Shares technical context with `GITIN-1770`/`1771` (ClubSite AR, WebSite — same Application Gateway/WAF), see `operations/events/20260805_waf_services_cert_automation_feasibility/` (not re-derived here). Reuses the DNS-01 validation mechanism via Azure DNS already implemented and verified in `GITIN-1774` (MobileAppService) — see `operations/events/20260806_acme_challenge_migration/`.

**Full epic picture (confirmed 2026-09-08, `data/gitin1768-epic-subtasks-20260908.txt`), 33% complete, 6 subtasks:**
- `GITIN-1774` Migración `_acme-challenge` — Finalizada
- `GITIN-1769` Automatizar ClubSite PY — **En curso** (this ticket)
- `GITIN-1770` Automatizar ClubSite AR — Finalizada
- `GITIN-1771` Automatizar WebSite — Backlog, not started
- `GITIN-1772` Automatizar WebServiceV2 — Backlog, not started
- `GITIN-1773` Automatizar WebServiceCG — Backlog, not started

This ticket (`GITIN-1769`) is the only one currently active in the epic — the 3 backlog items haven't started, no local records expected for them yet.

## Confirmed facts (carried over, not re-derived)
- Listener: `Listener_ClubSite_HTTPS_PY`, host `www.clubgrido.com.py`, frontend port 443, backend pool `Back_ClubSite_PY` (servers `192.168.50.121`/`.122`, shared with ClubSite AR) — not re-verified since 2026-07-21, confirm before assuming still current.
- **None of the 9 current certificates on `WAF_APPs` are integrated with Azure Key Vault** — all are directly-uploaded PFX. This is a blocker separate from the DNS validation mechanism: even with DNS-01 working, there's no way for the gateway to automatically pick up a renewed certificate without either (a) migrating the listener to a Key Vault reference, or (b) scripting a direct PFX upload to the gateway on every renewal.
- The DNS-01 validation mechanism via Azure DNS (delegated zone + Service Principal + win-acme plugin) is already proven end-to-end in `GITIN-1774` — a direct candidate to reuse here for domain proof, independent of whichever certificate delivery mechanism gets chosen.
- No dedicated VM exists for ClubSite PY the way `SFCG-MOBI-01/02` did for MobileAppService — win-acme would need to run from some host with permissions on the Key Vault/gateway, which one still to be defined.

## Approach decision (2026-09-08): replicate GITIN-1770 (ClubSite AR) exactly

User decision: follow the same approach as `GITIN-1770`, documented in `operations/docs/waf_apps_cert_automation_runbook.md` — which was explicitly written to be reused here. Several pieces transplant directly without new work:

- **Listener → cert mapping already known** (confirmed in GITIN-1770's own investigation, 2026-08-06, not re-derived): `Listener_ClubSite_HTTPS_PY` uses `www.clubgrido.com.py_2026_v2`. Resolves the open item below — no need to re-run the `az` listener-mapping check.
- **Key Vault (`sfcg-waf-apps-kv`) and Managed Identity (`waf-apps-kv-identity`) already exist for the whole gateway** — shared across all hostnames, no new infra. Only a new `DNS Zone Contributor` role assignment is needed, scoped to the PY zone (`_acme-challenge.www.clubgrido.com.py`, already created 2026-09-01) — same Service Principal as AR/MobileAppService, per the runbook's "one role assignment per new zone" rule.
- **win-acme host: very likely `SFCG-CLUB-01`** (`192.168.50.121`), same as AR — `Back_ClubSite_PY` uses the *same physical servers* as `Back_ClubSite`, and win-acme is already installed there with both the Azure DNS validation and Key Vault store plugins from the AR work. Reusing this host means no new install, just a new wizard run for the PY hostname.
- **Certificate delivery: Key Vault**, same as AR — resolves the open item below.

**New finding, confirmed 2026-09-08 (`data/backend_settings_py_check.txt`):** `Backend_ClubSite_PY` also does end-to-end re-encryption (`protocol: Https`), same critical risk pattern GITIN-1770 discovered for AR (backend cert independent of the public one, expiry causes a full outage regardless of the public cert's validity). This means PY needs its own backend-certificate automation pass too (GITIN-1770's runbook section 6), using the "by host" selection in win-acme to avoid touching AR's now-fixed binding on the same shared IIS site.

## Critical finding (2026-09-09): PY's backend cert expires in 6 days, no automated renewal exists — resolves the `trustedRootCertificates: null` question too

**`trustedRootCertificates: null` explained (not a gap):** inspected locally on `SFCG-CLUB-01` via RDP/PowerShell (remote `openssl` from outside the `192.168.50.x` VNet wasn't reachable — see `scripts.sh` C4a). The `www.clubgrido.com.py` IIS binding (hash `0BB9D0CBDB426A421C162EE71B59A39F4A43DBB9`, store `My`) is already a Let's Encrypt certificate, full chain leaf → `YE2` → `Root YE` → `ISRG Root X2` → `ISRG Root X1` (self-signed). `ISRG Root X1` is a well-known public CA that Application Gateway v2 trusts by default when `trustedRootCertificates` is unset — no orphaned-object gap, no bypass. The two PY-named trusted-root objects at the gateway level (`www.ca.py`, `clubgrido_PY_2024_CA_ROOT`, from `data/gateway_trusted_root_names.txt`) are unrelated to this binding — still unclassified (orphan vs. stale), not investigated further since they're not blocking anything.

**But this raises something more urgent, unrelated to the original ticket scope:** this Let's Encrypt cert's `NotBefore` is 6/17/2026 — before `GITIN-1774` even started (2026-08-06) — so it wasn't issued by any automation set up under the `GITIN-1768` epic. It **expires 2026-09-15**. The user raised a plausible hypothesis that the existing `win-acme renew (acme-v02.api.letsencrypt.org)` scheduled task on this host (created for AR under `GITIN-1770`) might also cover PY, since both hostnames share the same VM. **Checked directly, not assumed: disproven.** `C:\ProgramData\win-acme\acme-v02.api.letsencrypt.org\` on `SFCG-CLUB-01` contains exactly one renewal config (`SwTuz4cBaEqYqmX6WK7cCw.renewal.json`), and its `TargetPluginOptions` (`CommonName`/`AlternativeNames`) is `www.clubgrido.com.ar` only. The scheduled task is real and will run on schedule, but it has nothing to renew for PY — **PY's backend cert has no renewal mechanism at all and will expire in 6 days.**

Who issued this cert, and how it's been renewed (if ever) before now, is unconfirmed — not investigated further since it isn't needed to fix the immediate risk.

## Wizard execution (2026-09-09): combined public + backend cert issued on SFCG-CLUB-01

Rather than two separate win-acme runs, ran ONE combined session — matching GITIN-1770's own `SFCG-CLUB-01` precedent, which used a single multi-target renewal (`SwTuz4cBaEqYqmX6WK7cCw.renewal.json`) delivering to both Key Vault and the local IIS store for AR. Full transcript: `data/py_backend_winacme_wizard_output.txt`.

- Source: Manual, `www.clubgrido.com.py`, Single certificate.
- Validation: Azure DNS, reused the existing saved credential `vault://json/winacme-clubsitear-dns` (same VM, same Service Principal — DPAPI vault reuse works *within* a machine across renewal objects; it's only cross-VM reuse, e.g. `.01`→`.02`, that doesn't work, per runbook §6.1).
- Key type: RSA (matches existing convention; no confirmed technical requirement over EC, just consistency with what's proven working here).
- Stores: Azure Key Vault (`sfcg-waf-apps-kv`, cert name `www-clubgrido-com-py`) + Windows Certificate Store (Local Computer, store `My` — matches the existing PY binding's store, confirmed via C8, not assumed).
- Installation: IIS binding on `SmartLoyalty.ClubSite`.

**Result:** DNS-01 validated (1 retry, normal propagation delay). IIS binding `www.clubgrido.com.py:443` updated — only 1 binding changed, confirming the default/no-SNI binding (which shared the old cert) was **not** touched. Renewal task added, next due 2026/11/3.

**Verified, not assumed:** the log's `Store step 1/2: KeyVault... [HTTP] Request completed with status Unauthorized` line looked like a possible failure (no confirming success line after it, unlike GITIN-1770's log which showed a 401-then-200 pair) — checked directly via `az keyvault certificate show` (`data/py_keyvault_cert_check.json`): cert `www-clubgrido-com-py` is enabled, expires 2026-12-08. Same benign OAuth challenge/retry pattern as GITIN-1770, not a real failure.

**Backend health after the swap** (`data/backend_health_after_py_reissue.json`): `SFCG-CLUB-01` (`.121`) Healthy on `Back_ClubSite`, `Back_ClubSite_PY`, `Back_WebSite`. `SFCG-CLUB-02` (`.122`) shows `Unhealthy` on both `Back_ClubSite` and `Back_ClubSite_PY` — **deliberate, not a regression:** user confirmed IIS was intentionally stopped on `.122` pending its own cert update, same reasoning as GITIN-1770's independent `.02` pass (own private key, own DNS-01 run, no Key Vault — that cert only needs to land in the local store + IIS). **Next step for `.122`:** repeat the win-acme backend-only flow there (Source manual `www.clubgrido.com.py`, Validation Azure DNS same PY zone, Store Windows Certificate Store only — no Key Vault, that secret is already covered by `.01`'s upload — Installation IIS binding), matching GITIN-1770's C23–C26 pattern for AR's `.02`. Will need its own saved credential in `.122`'s local DPAPI vault (can't reuse `.121`'s `winacme-clubsitear-dns` cross-VM) — either reuse whatever `.02` already has saved from AR's setup, or add a new secret via `az ad app credential reset --append`.

## Listener migration (2026-09-09): public-cert automation completed for `.121`

User independently confirmed via the WAF directly that the public listener's certificate still showed the old dates (NotBefore 17 Jun 2026 / NotAfter 15 Sep 2026 — matching the pre-fix backend cert exactly) — proving `Listener_ClubSite_HTTPS_PY` had never been migrated off the direct PFX object (`www.clubgrido.com.py_2026_v2`), and that the 6-day expiry risk applied to the public-facing side too, not just backend.

Reconstructed the migration commands from GITIN-1770's `investigation.md` (line 35, prose description only — the actual `az` commands for AR's own migration were never captured in that ticket's `scripts.sh`, a gap in that record) plus standard `az network application-gateway` syntax:
- C18 — created ssl-cert object `www-clubgrido-com-py-kv`, referencing the Key Vault secret by its **versionless** URI (`.../secrets/www-clubgrido-com-py`, no version GUID) so the gateway auto-picks up future rotations without reconfiguration. Confirmed `provisioningState: Succeeded`.
- C19 — updated `Listener_ClubSite_HTTPS_PY` to use this object. Confirmed via the update response itself: `sslCertificate.id` now `www-clubgrido-com-py-kv`, `hostName` unchanged.

**Public-cert automation is now functionally complete for this hostname, `.121` node.** The old PFX object `www.clubgrido.com.py_2026_v2` is now orphaned — same open decision GITIN-1770 left for `clubgrido.2023.2024` (clean up vs. keep as temporary backup), not yet decided for either.

## Ruled out
- Reusing `GITIN-1774`'s same Service Principal without evaluating — that SP has `DNS Zone Contributor` scoped specifically to the `_acme-challenge.mobileservice.clubgrido.com.ar` zone; this zone (`_acme-challenge.www.clubgrido.com.py` or whatever gets decided) needs, at minimum, a new role assignment on the new zone — reusing the same scope isn't enough.

## Open questions / next steps

**Correction (2026-09-08):** this section previously said "none of this has been executed yet — no Azure resources created for this specific ticket," which was stale — it contradicted the "Resumption" section above, which already records the Azure DNS zone being created and the delegation-request email sent on 2026-09-01. Fixed in place.

- ~~Check whether Jordan (IT Grido) added the NS delegation record~~ — confirmed 2026-09-08, see Status above.
- **DNS provider for `clubgrido.com.py`** — still unconfirmed, but no longer blocking (the delegation itself is confirmed working regardless of which registrar/provider sits underneath it). Low priority now.
- ~~Listener → certificate mapping~~ — resolved, transplanted from GITIN-1770: `www.clubgrido.com.py_2026_v2`.
- ~~Certificate delivery decision~~ — resolved: Key Vault, same as AR.
- ~~Where win-acme runs from~~ — very likely `SFCG-CLUB-01`, same as AR (shared backend servers) — not yet independently re-confirmed for this ticket, but high confidence given the shared infrastructure.
- ~~`DNS Zone Contributor` role assignment on the PY zone~~ — confirmed 2026-09-09, `data/role_assignment_create.json`.
- ~~Why `Backend_ClubSite_PY.trustedRootCertificates` is `null`~~ — resolved 2026-09-09, see "Critical finding" above: existing backend cert already chains to a well-known public CA (ISRG Root X1), no gap.
- **Next concrete action (URGENT, ahead of the public-cert wizard below):** run win-acme's backend-cert flow on `SFCG-CLUB-01` for `www.clubgrido.com.py` — runbook §6.1, "by host" grouping, Windows Certificate Store + IIS binding, no Key Vault. Backend cert expires 2026-09-15, no current automation.
- **After that: public cert.** Run win-acme on `SFCG-CLUB-01` for the public cert (source: manual hostname `www.clubgrido.com.py`, validation: Azure DNS, store: Key Vault `sfcg-waf-apps-kv`) — per the runbook's section 4.5.

# GITIN-1238 — Azure Load Balancer: new VMs added to SFCG-WSV2-LB don't receive traffic

Jira: https://smartit-ar.atlassian.net/browse/GITIN-1238

## Status

Resuming an old, stalled ticket (2026-08-26). Original investigation ended at a hypothesis, no
resolution reached, no support case opened. Searched `~/Documents/` and `~/Documentos/` for any
later follow-up (GITIN-1238, TrustedLaunch, SFCG-WSV2) — found nothing beyond this ticket; it was
never picked back up elsewhere.

VM2 (`SFCG-WSV2-02`) confirmed still exists (user, 2026-08-26), but is **administratively powered off**
— deliberately, per user (2026-08-26): "since both can't work together cause of this issue" — i.e.
the ticket's most severe reported symptom ("con ambas VMs activas → LB deja de funcionar") was real
enough that VM2 has been left down to keep VM1/production traffic unaffected. Confirmed stopped via
`az network nic list-effective-nsg`/`show-effective-route-table` both failing with
`NicMustBeAttachedToRunningVmToGetEffectiveSecurityGroups` / `...EffectiveRoutes`.

**Operational implication:** any live test that starts VM2 while it remains in the backend pool
risks reproducing the "both VMs active → LB breaks entirely" symptom against production traffic on
VM1, not just a VM2-only failure. This needs explicit user sign-off before running, ideally with VM2
removable from the backend pool quickly (or a maintenance window) if VM1 traffic degrades.

**However**, the original ticket already reports "con solo VM2 activa → timeout" — i.e. VM2's
failure reproduces without VM1 present in the pool at all. So reproduction does not require
touching VM1's live rule/pool membership; an isolated test path (separate frontend port + temporary
pool containing only VM2, on the same LB) can reproduce and diagnose without any production risk.

## LB config re-verified live (2026-08-26)

- Only one inbound rule: `SFCG-WSV2-LB-lbrule01` — TCP 8080→8080, probe `sfcg-sondeo02` (TCP 8080,
  5s interval, 1 probe), floating IP disabled, pool `SFCG-WSV2-LB-backendpool01`.
- One outbound rule: `SFCG-WSV2-outbound-rule` — also targets `backendpool01`, `disableOutboundSnat`
  correctly set on the inbound rule to pair with it. Standard, non-suspicious.
- Second pool `WSV2-IP` (IP-based) also lists both VMs as members but is referenced by **no** rule
  (inbound or outbound) — orphaned/dead config, not causally relevant. Worth cleaning up separately,
  out of scope for this ticket.
- Backend pool membership, probe, and rule are **identical for VM1 and VM2** — no asymmetry exists
  anywhere in the LB's own configuration. Whatever differs is guest-OS-level (already exhaustively
  ruled out in the original ticket: firewall, IIS bindings, cert binding, app pool, NSG) or
  host/platform-level (not yet checked — e.g. Azure SDN/VFP rule-programming tied to the physical
  host VM2 landed on, possibly correlated with TrustedLaunch/Gen2, possibly not).
- NIC properties: VM1 has Accelerated Networking on, VM2 has it off (asymmetric) — but ticket
  already reports toggling this on VM2 produced no change, and the direction (working VM has it ON)
  doesn't fit an "AccNet causes the failure" theory. `enableIPForwarding` is unset (false) on both,
  symmetric.
- VM2 is currently stopped; effective NSG/effective route table for VM2 not yet obtainable (Azure
  requires the VM running). VM1's effective NSG/routes not yet pulled either (pending).

## Original report (from ticket, as-is)

- LB: `SFCG-WSV2-LB` (Standard SKU, Regional), backend pool `SFCG-WSV2-LB-backendpool01` (NIC-based)
- VM1 `SFCG-WSV2-01` (works) — Standard_D8as_v5, Security type: Standard (no TrustedLaunch)
- VM2 `SFCG-WSV2-02` (fails) — Standard_D2ds_v4, TrustedLaunch (secureBootEnabled, vTpmEnabled)
- Subnet DMZ 192.168.50.0/24, port 8080 HTTPS, probe TCP 8080
- Symptom: health probes from 168.63.129.16 reach VM2 and report Healthy; real client traffic to
  VM2 times out at TCP connect (never gets a SYN-ACK). Direct access to VM2 bypassing the LB works
  fine. With both VMs in the pool, the LB "stops working" (unclear if this means VM1 also breaks,
  or just that VM2's share of traffic fails — not established in the ticket).
- Reported as reproducible: "se crearon 2 VMs diferentes y ambas presentan el mismo comportamiento"
  — but the second test VM's spec (SKU, security type) is not recorded in the ticket, so it's not
  known whether it isolated TrustedLaunch from the SKU difference either.
- Ruled out in ticket: NSG (shared, 8080 open), Windows Firewall (disabled both), IIS bindings (All
  Unassigned), SSL binding (0.0.0.0:8080), App Pool started, same subnet/VNet, no public IP on VM2
  (rules out asymmetric routing at that level), Accelerated Networking toggle (no change), backend
  pool NIC association (verified both).
- Ticket's hypothesis: TrustedLaunch interfering with LB traffic handling at kernel/network level,
  while still permitting Azure's own probe traffic from 168.63.129.16.

## Gaps in the original investigation

1. **Confounded comparison** — VM1 vs VM2 differ in both Security type (Standard vs TrustedLaunch)
   *and* VM series (D8as_v5 vs D2ds_v4). Nothing in the ticket isolates which variable matters. The
   ticket's own next step (build a Standard-type test VM) doesn't mention matching VM1's SKU, so
   even that test wouldn't be clean.
2. **No effective-NSG / effective-route diff was taken.** Everything "ruled out" was checked at the
   configured level (what's in the portal), not the computed level (what Azure's fabric actually
   applies per NIC). `az network nic list-effective-nsg` and
   `az network nic show-effective-route-table` were never run against VM1's and VM2's NICs.
3. **A UDR exempting `168.63.129.16`** produces the exact same signature as reported here: Azure
   always bypasses custom UDRs for the wire-server/probe IP, so health probes succeed regardless of
   any route table pointing real traffic at an NVA/firewall that never lets it through. This is a
   distinct, equally-plausible explanation from TrustedLaunch and was not checked.
4. **No Network Watcher IP-flow-verify / connection troubleshoot was run** against VM2 for the
   specific real-client-source-IP → VM2:8080 flow, which would directly show whether Azure's
   computed NSG/route state allows or blocks that flow — independent of what TrustedLaunch does or
   doesn't do at the guest OS level.
5. No host-level remediation was tried (deallocate + start VM2, which reallocates it to a different
   physical host) — a cheap test that would falsify "it's inherent to TrustedLaunch" if it fixes
   the symptom, since it would point instead to a stuck SDN LB-rule-programming state on that
   specific host.

## PowerShell history review (VM2, pasted by user 2026-08-26)

Reviewed prior troubleshooting commands run on VM2. Notes:

- A storage-account credential (used via `cmdkey` to mount `\\192.168.50.17\despliegues` for
  deployments) was present in plaintext in the command history. **Not recorded here by value** —
  user confirmed it was rotated after that run.
- A Windows feature-install script ("Features traidas de WebserviceV2") was run to provision VM2 —
  IIS, .NET, WAS, etc. Nothing anomalous spotted; not a suspect.
- `ping`/`Invoke-WebRequest` loop against `webservicev2.smartfran.com:8080` resolves via VM2's own
  hosts-file entry (`192.168.50.172 webservicev2.smartfran.com`) — this bypasses the LB entirely,
  consistent with "direct access works" from the original ticket, but doesn't test the LB path.
- `netsh http show sslcert ipport=0.0.0.0:8080` and `ipport=192.168.50.172:8080` were both run —
  **output not yet provided**. This is the strongest open lead: if the cert is bound only to the
  wildcard `0.0.0.0:8080` and not also registered for `192.168.50.172:8080` (VM2's own private IP —
  the destination address the packet actually carries post-DNAT, since Floating IP/DSR is
  disabled on the LB rule), that would explain probes succeeding (probes may not require TLS
  depending on prove type) while real HTTPS traffic silently fails at the TLS/http.sys layer.
- A packet capture was taken (`netsh trace start/stop` → `C:\temp\lbtrace.etl`) — analysis result
  not yet provided. Would show directly whether a real client's SYN reaches VM2's NIC at all.
- A polling loop (`Get-NetTCPConnection -LocalPort 8080`, 1s interval) was run, presumably during a
  live test — result not yet provided. Would show whether any inbound attempt reaches the guest
  OS's TCP stack during a failure.

## Blocking issue found and resolved: app pool identity failure (2026-08-26)

VM2's app pool (`SmartLoyalty.WebServiceV2`) was `Stopped` — Event ID 5021 "The identity of
application pool SmartLoyalty.WebServiceV2 is invalid" at 18:07 and 18:23 UTC, followed by WAS
auto-disabling the pool (5057/5059). httperr.log confirmed `503 1 AppOffline` for all requests in
that window. Timing coincides with a credential rotation mentioned earlier in this session (an SMB
deployment-share account, `localhost\strgsqlbkp`) — suspected but not confirmed to be the same
account configured as this app pool's identity.

Resolved: healthcheck now returns `"status":"Healthy"` (DB connected 532ms, Redis connected 32ms).
**Not yet confirmed whether this check was local (bypasses LB) or through the LB** — needed before
treating this as validating anything about GITIN-1238 itself.

This was a separate, blocking issue (app-level, not network/LB-level) that had to be cleared before
the LB routing question could be re-tested at all.

## Pivotal result: LB-mediated request now succeeds at network/TLS layer (2026-08-26, 18:46 UTC)

`curl -k -v -H "Host: webservicev2.smartfran.com" https://52.186.168.27:8080/healthcheck.ashx`
(original live path, port 8080, both VMs in pool) — full TCP connect, TLS 1.2 handshake completed,
HTTP/2 negotiated, server responded. **This is not the original reported symptom at all** (which was
a TCP-connect timeout, no SYN-ACK). Response was HTTP 500 (ASP.NET Runtime Error, details hidden by
`customErrors` — expected/correct behavior, not to be disabled remotely).

**Determined: VM1 served this request**, not VM2. Confirmed via Application event log — VM1 logged
Event 1309 (ASP.NET unhandled exception) at 18:46:04, exact match to the curl timestamp; VM2 logged
nothing in that window. Root cause (user-confirmed, resolved/expected, not a regression): VM1 simply
does not have the `healthcheck.ashx` handler deployed/registered — MVC routing catches the request
and `ControllerFactory.CreateController` rejects "healthcheck.ashx" as an invalid controller name.
VM2 does have it (per the working local healthcheck result earlier). This means **VM1 and VM2 are
running different code/deployment versions** — worth keeping in mind for any future VM1-vs-VM2
comparison in this investigation, but not itself the cause of the original network-routing symptom.

Net effect: the port-8080 LB test above tells us nothing about whether VM2 receives traffic — it
happened to hash to VM1 (pool has both, 5-tuple hash distribution). Whether VM2 actually receives
LB-mediated traffic is still the open, critical question for GITIN-1238.

## Resolution: VM2 now receives and serves LB traffic correctly (2026-08-26, 19:02 UTC)

`curl -k -v -H "Host: webservicev2.smartfran.com" https://52.186.168.27:8080/healthcheck.ashx`
(original live path — port 8080, `SFCG-WSV2-LB-lbrule01`, `backendpool01` with both VMs) returned:

`HTTP/2 200` — `{"status":"Healthy","database":{"healthy":true,...},"redis":{"healthy":true,...}}`

This JSON payload format is VM2's `HealthCheckHandler` output specifically (VM1 cannot produce it —
VM1 throws on this path, see above). **This proves a real client request through the LB's public IP
reached VM2 and was served correctly** — the exact thing the original ticket reported as impossible.

**Conclusion:** the originally-reported symptom (real traffic never reaching a new VM in the backend
pool, despite healthy probes) does not currently reproduce. The TrustedLaunch hypothesis was never
actually confirmed as root cause (see "Gaps," above) and no network/LB-config difference between
VM1 and VM2 was found anywhere (rules, probes, pools, outbound rules, NIC properties — all
symmetric). The only concrete, confirmed-broken thing found and fixed this session was VM2's app
pool identity failure (Event 5021), which would produce HTTP-level 503s, not the TCP-connect
timeouts originally reported — so it does not fully explain the original symptom's exact signature
either. Plausible explanation, not confirmed: the original network-level issue (if real, and not a
methodology artifact of testing against a broken/AppOffline app pool at the time) may have been tied
to a stuck host-level LB-rule-programming state that cleared across VM2's multiple stop/start cycles
since — consistent with "old attempt, never resolved, VM2 left powered off" and its now working
after being freshly started for this session.

**Confirmed:** 4/4 repeat curls via the same LB path all returned `200`.

**RETRACTED — confirmed wrong (2026-08-26, `DipAvailability`/`BackendIPAddress` metric, 18:54–19:08 UTC):**

| BackendIPAddress | Average health-probe availability |
|---|---|
| 192.168.50.171 (VM1) | 100.0% throughout |
| 192.168.50.172 (VM2) | **0.0% throughout** |

VM2's health probe has failed 100% of the time for the entire session, covering both the 500 test
(18:46) and the 200/Healthy test (19:02). **Every LB-routed test in this session actually hit VM1,
never VM2.** The earlier conclusion ("VM1 can't produce that JSON, so it must have been VM2") was
wrong — VM1 apparently serves `/healthcheck.ashx` *intermittently*: sometimes the "invalid
controller" 500, sometimes a correct 200/Healthy response. That intermittent VM1 behavior is a real,
separate finding worth its own attention, but is not GITIN-1238.

**GITIN-1238's core question is still completely untested.** Azure's Standard LB never routes real
traffic to a backend its own probe marks unhealthy — so nothing about "does VM2 receive real
traffic" has been established yet. Worse: the *original* ticket claimed probes reach VM2 and report
Healthy, which is the opposite of what's happening right now. Before anything else, need to explain
why VM2 is failing its own TCP:8080 health probe — this predates any question about real client
traffic. Leading theory: VM2 sat powered off for a long time; on fresh boot, Windows can
re-categorize the DMZ NIC's network as "Public" before it's re-identified as the intended profile,
and firewall state per-profile (not just whichever profile was checked originally) needs re-verification.

## VM2 probe self-recovered (2026-08-27, confirmed 10:41–10:42 UTC)

VM2 confirmed running (user, 2026-08-27). Pool-level `DipAvailability` ("Health Probe Status") for
`SFCG-WSV2-LB` was flat 50% (VM1=100/VM2=0 average) 10:12–10:40Z, consistent with the 2026-08-26
by-IP retraction. **Re-split by `BackendIPAddress` confirms directly:** `192.168.50.172` (VM2) was
flat **0.0%** for the entire 10:12–10:40Z window, then **83.3% at 10:41Z, 100.0% at 10:42Z**.
`192.168.50.171` (VM1) stayed 100.0% throughout. This is a real, dimension-isolated recovery, not an
averaging artifact — VM2's own health probe is passing again as of 10:41–10:42Z.

**Open question:** what changed at 10:41Z. Not yet correlated against: exact VM2 boot/start
timestamp this session (to see if this is simply "probe recovers ~N minutes after cold start,
consistent with slow guest-OS/network stabilization" — supports the fresh-boot theory resolving on
its own), or any user action taken around that time (service restart, etc).

**Firewall/network-profile-miscategorization theory: RULED OUT (2026-08-27).** On `SFCG-WSV2-02`,
`Get-NetConnectionProfile` shows `NetworkCategory: DomainAuthenticated` (not Public), and
`Get-NetFirewallProfile -All` shows **all three profiles (Domain/Private/Public) `Enabled: False`**
— Windows Firewall is fully disabled, not selectively blocking by profile. Consistent with, and more
granular than, the original ticket's "firewall disabled both" check. This was the leading theory for
why VM2's own probe was failing pre-10:41Z; it does not hold.

Effective NSG/routes and NIC properties for VM2 still queued (files being relocated into this event
folder from wherever the user ran the commands; the redirect didn't land here the first time) — still
matter to identify what *did* explain the pre-10:41Z block, since the true cause could recur on
VM2's next cold start.

## False-positive test, caught before being trusted (2026-08-27)

`Invoke-RestMethod` against `https://webservicev2.smartfran.com:8080/api/SaleProvider/QueryActivePromotionV3`
run **on VM2 itself** (`SFCG-WSV2-02`) returned a real app-level response
(`{"Message":"Authorization has been denied for this request."}` — a genuine ASP.NET auth-filter
rejection, proving the app itself is up and enforcing auth correctly). **Confirmed this bypassed the
LB**: VM2's hosts file still has `192.168.50.172 webservicev2.smartfran.com` (the same override noted
in the original ticket's PowerShell history) — the request never left the box. Same class of false
positive as the earlier `healthcheck.ashx` misattribution; caught this time before being written up as
evidence. Tells us nothing about whether real client traffic through the LB reaches VM2.

**Corrected test method needed:** target the LB's public IP directly with a `Host` header (as done
successfully for the `healthcheck.ashx` tests — `curl -k -H "Host: webservicev2.smartfran.com" https://<LB-public-IP>:8080/...`),
which skips DNS/hosts resolution of the domain entirely and cannot be short-circuited by a local hosts
override.

## Corrected test run — TCP-connect timeout, but confounded by self-hairpin (2026-08-27)

`curl.exe -k -H "Host: webservicev2.smartfran.com" ... https://52.186.168.27:8080/api/SaleProvider/QueryActivePromotionV3...`
run **from VM2** (public IP, no DNS/hosts involved) — result: `Failed to connect ... after 21032 ms:
Could not connect to server` (`curl: (28)`), i.e. **TCP-connect timeout, no SYN-ACK**. This is the
**exact signature of the original reported symptom.**

**Confound, not yet ruled out:** the request originated from VM2, which is itself a backend-pool
member. Azure Standard LB has a known, documented limitation distinct from anything in this ticket:
a backend-pool VM's outbound traffic to the LB's own public frontend IP fails specifically when the
LB's 5-tuple hash routes that flow back to the *same originating VM* (self-hairpin unsupported;
routing to a *different* peer VM in the pool works fine). If the hash happened to select VM2 itself
for this request, this timeout is fully explained by that limitation and is unrelated to GITIN-1238.

**Needed to disambiguate:** re-run the identical command from a vantage point that isn't a pool
member — ideally a genuinely external client (outside the VNet entirely), or at minimum from VM1
(still a pool member, so a VM1→self-hairpin confound is possible there too, but if VM1's request
succeeds while VM2's fails, that's still informative). A clean external test is the only fully
unconfounded result.

## Two more hostname-based tests, likely both self-bypassed too (2026-08-27)

Two further `curl` calls against `https://webservicev2.smartfran.com:8080/api/SaleProvider/QueryActivePromotionV3`
using a real Auth0 client-credentials bearer token (not written here by value — SaleProvider
client-credentials token, Auth0 tenant `smartfran-cloud.us.auth0.com`, audience
`smartfran-cloud-prod`):

- First call (11:00:59Z): `HTTP/1.1 500` — real app-level `ConfigurationErrorsException`:
  `'maxTraceFileSizeKb' is not a valid configuration attribute for type
  'System.Diagnostics.DelimitedListTraceListener'`, thrown inside
  `SaleProviderController.QueryActivePromotionV3`'s tracing/logging path. User reported this as
  "a vm02 response." **Not yet confirmed whether this means "I ran it from VM2" (hosts-bypass, same
  as prior tests) or "the LB routed it to VM2" (which would need independent confirmation, e.g. an
  event-log timestamp match) — these are very different claims.**
- Second call (11:02:14Z): verbose output shows `* Trying 192.168.50.171` — **resolved via plain
  hostname DNS straight to VM1's private IP**, confirming this one bypassed the LB. Got
  `HTTP/1.1 401` — `{"Message":"Authorization has been denied for this request."}` — the *same*
  token that got past auth and into the controller on the other VM was flatly rejected here.

**Confirmed (user, "vm01"):** the 401 call was run from VM1's own RDP session — both hostname-based
tests were self-served (VM1's hosts override → 401 from itself; VM2's hosts override → 500 from
itself), proving nothing about LB routing. The differing status (500 vs 401) for the identical token
is a separate, tangential VM1-vs-VM2 code/config difference (consistent with the already-noted
differing deployments) — not evidence about GITIN-1238.

**Still the only unconfounded-ish LB-path result:** the earlier direct-IP (`52.186.168.27`) curl
from VM2, which timed out — still carrying the self-hairpin caveat, still needs either an external
client or a same-technique run from VM1 to disambiguate.

## Strongest positive result: external Postman call succeeds fully (2026-08-27)

Same endpoint (`SaleProvider/QueryActivePromotionV3`), called from **Postman on the user's own
machine** (not VM1, not VM2), user-labeled "(LB)". Result: full `HTTP 200`, complete, valid business
payload (100+ active promotions, well-formed JSON, no errors). This is the first test in this session
that looks like genuine external client traffic succeeding end-to-end through the real path — no
timeout, no reset, no app error.

**Confirmed:** hostname target (`webservicev2.smartfran.com:8080`, per Postman's raw request), not
direct IP. **Timestamp: 2026-08-27T10:58:59Z** — after VM2's probe recovery (10:41–10:42Z), so
consistent with VM2 if it turns out to be the server.

**Still not yet confirmed:** whether the user's machine has any VPN/ExpressRoute connection into the
Azure VNet right now (plausible, given they were RDP'd into VM1/VM2 earlier this session) — if so,
the same private-DNS trap that bit the VM1/VM2 hostname tests could apply here too, even from "the
user's own machine." Moot for the "which VM" question below, but still needed before treating this
as unambiguous "real LB traffic reached the app" evidence at all.

**Which VM served it — ANSWERED: not VM2.** VM2's own IIS log (`E:\inetpub\W3SVC1`) for the
10:49–11:01Z window shows six requests to `QueryActivePromotionV3`, **all with `c-ip=192.168.50.172`
(VM2 talking to itself)** — matching the known self-bypass tests exactly: five `401`s from the
earlier `Get-NetTCPConnection`-era PowerShell/curl loop and User-Agent `curl/8.13.0`, plus the `500`
`ConfigurationErrorsException` test at 11:00:59Z. **No entry exists for the Postman call at
10:58:59Z** (would show User-Agent `PostmanRuntime/7.49.1` and an external `c-ip`). VM2 did not
serve the successful Postman request. Still need VM1's log to confirm it landed there (expected,
by elimination, since only two pool members exist) — if so, this Postman success is a **non-result**
for GITIN-1238: it confirms VM1 (already known-good) is reachable, and says nothing about VM2.

**Methodology note:** first VM1 log query filtered on time-of-day only (`Select-String
'10:58:5[0-9]|10:59:0[0-9]'`), no date constraint — VM1's log file retains long history, so it
matched stale entries from 2024-11-08, 2024-12-11, and 2025-03-07 (same time-of-day, unrelated old
requests) instead of today's. Caught before being treated as evidence.

**Confirmed: VM1 served it.** Corrected, date-constrained query on VM1's log
(`D:\Inetpub\W3SVC2\u_ex*.log`) shows `2026-08-27 10:59:00`, `c-ip=152.169.14.152`,
`PostmanRuntime/7.49.1`, `sc-status=200` — exact match. **Every Postman call visible in this log
excerpt (8 requests, 10:43:32–11:09:20Z, all from the same client IP `152.169.14.152`) was served by
VM1 — none by VM2.** So the earlier "strongest positive result" is a **non-result for GITIN-1238**:
it confirms VM1 (already known-good) is reachable externally, and still says nothing about VM2.

**New methodological concern:** if Postman reused a single persistent keep-alive TCP connection
across all calls (its default behavior), the LB's 5-tuple hash would deterministically pin every
one of them to the same backend **regardless of whether VM2 is healthy** — fully explaining "N/N on
VM1" without VM2 being broken at all. This needs ruling out before drawing any conclusion.

**Still unresolved (2026-08-27, follow-up):** user re-checked both logs and found 4 more requests
(11:11:50–11:11:52Z) — still User-Agent `PostmanRuntime/7.49.1`, still all 4 on VM1, VM2's log
unchanged. **This was still Postman, not the requested fresh-TCP-connection test** (`curl.exe` per-
request, `Connection: close`) — so the keep-alive-pins-to-one-backend confound remains unruled-out.
Now **12/12 total Postman requests across ~28 minutes (10:43–11:11Z) have landed on VM1**, which is
itself notable regardless of cause (a single kept-alive connection surviving that long is plausible
but worth confirming), but doesn't yet distinguish "VM2 unreachable" from "same connection reused
throughout."

## Genuinely external test: TCP-connect timeout, real symptom signature — but a new confound (2026-08-27)

Fresh-connection `curl -v --http1.1 -H "Connection: close" ...` run from `gondor` (this session's own
Linux host — a third vantage point, not VM1, not VM2, not wherever Postman ran). Verbose output:
`* Host webservicev2.smartfran.com:8080 was resolved.` → `IPv4: 52.186.168.27` (the real LB public
IP, no override/private-DNS confound this time) → `* Trying 52.186.168.27:8080...` →
`ipv4 connect timeout after 9910ms` → `curl: (28) Failed to connect ... Timeout was reached`.
**Pure TCP-connect timeout, no SYN-ACK, from a genuinely external, unconfounded vantage point —
matches the original ticket's exact reported signature.**

**New confound, not yet ruled out: NSG IP-allowlisting.** The sibling `SFCG-MOBI-LB` path (per the
`loyalty-azure-lb` skill) uses a named multi-IP allow-list NSG (`sfcgnetsec01`), not a subnet/`*`-
based rule. If `SFCG-WSV2-LB`'s frontend/DMZ subnet NSG has a similar IP-allowlist, and the Postman
machine's known-working source IP (`152.169.14.152`, seen serving 12/12 successful VM1 requests)
is on that list while `gondor`'s own public egress IP isn't, that fully explains "works from
Postman, times out from here" **with no relation to VM2 or GITIN-1238 at all** — an Azure NSG drops
disallowed traffic silently, indistinguishable from a connect timeout on the client side.

**Needed to disambiguate:** (1) `gondor`'s own public egress IP (`curl -s https://api.ipify.org` or
similar), (2) the actual NSG rules on `SFCG-WSV2-LB`'s frontend/DMZ subnet, to check for an IP-
allowlist and whether either `152.169.14.152` or `gondor`'s IP appears on it.

## Same source, back-to-back, two different outcomes — NSG-allowlist theory weakened (2026-08-27)

Re-ran the identical fresh-connection curl from `gondor` seconds after the timeout above. This time:
full TCP connect + TLS 1.2 handshake (cert `CN=*.smartfran.com`, valid) + complete HTTP transaction
→ `HTTP/1.1 500 Internal Server Error`, `Content-Length: 36`, timestamp **2026-08-27T11:21:43Z**.

**Same source IP, ~10 seconds apart, one attempt times out completely and the next completes fully.**
This is hard to reconcile with a static NSG IP-allowlist (would block or allow consistently, not
flip between consecutive attempts from the same source) — but fits well with the LB hashing distinct
fresh TCP connections to *different* backends, one of which doesn't respond. **Confirmed: VM1 again** (`c-ip=152.169.14.152`, `curl/8.5.0`, `500`, `11:21:43Z`, matches exactly).
VM2's log unchanged — still ends at 11:00:59Z, still only self-originated (`c-ip=192.168.50.172`)
entries.

## Emerging pattern across the full session (2026-08-27)

**Every successful connection all session — 17 total (16 Postman + this 1 curl) — has landed on
VM1. The only two outright connection failures (both fresh-connection tests from `gondor`, `000`/
timeout) never appear in either VM's log at all**, meaning they failed before reaching any backend's
HTTP stack. VM2's log contains zero entries from any external client IP for the entire session —
only its own self-originated requests from the earlier hosts-file-bypass tests.

This is now a coherent, repeatable pattern, not a one-off: fresh real-client connections either land
on VM1 (and succeed at the network/TLS layer regardless of app-level status) or fail outright with
no SYN-ACK — consistent with roughly half of new connections (by 5-tuple hash, 2-VM pool) hitting
VM2 and VM2 not accepting them, despite VM2 currently passing its own TCP:8080 health probe. This
directly supports the original ticket's core claim and re-surfaces **Gap #3 from the start of this
investigation, never yet checked**: Azure always bypasses custom UDRs for the probe/wire-server IP
(`168.63.129.16`), so a UDR that misroutes or blackholes real traffic on VM2's NIC would produce
exactly this signature — healthy probe, dead real traffic — while leaving VM1 unaffected if VM1's
effective route differs (even though the *configured* route table was already confirmed identical
for both, Step "LB config re-verified live" above — effective/computed routes were never actually
pulled for VM2; that request has been outstanding since early in this session).

## Third gondor attempt: another success — pattern holds (2026-08-27)

Re-ran the same fresh-connection curl from `gondor` again: full connect + TLS + HTTP, `200 OK`,
`Content-Length: 84831` (same size as the successful Postman payloads), `Date: 11:25:09Z`.

**Tally, 3 fresh-connection attempts from `gondor` (genuinely external, not a backend-pool member,
so the self-hairpin confound does not apply here):** 1 timeout (`000`, no SYN-ACK), 2 full successes
(500, then 200). An intermittent pass/fail pattern from the *same* source IP across consecutive
fresh connections is inconsistent with a static NSG allowlist (would be consistently blocked or
consistently allowed) and fits well with "LB alternates between VM1 (responds) and VM2 (doesn't
answer new connections at all)." Small sample (n=3) — not conclusive alone, but combined with VM2's
log showing zero external-client entries all session, this is the strongest evidence yet that
GITIN-1238's core symptom is reproducing right now.

**Confirmed: also VM1.** `2026-08-27 11:25:10`, `c-ip=152.169.14.152`, `curl/8.5.0`, `200` — VM1's
log. **Final tally: 3/3 fresh-connection attempts from `gondor` fully attributed** — 2 succeeded, both
on VM1 (11:21:43 → 500, 11:25:10 → 200); 1 timed out with no entry on either VM's log, and by
elimination (exactly 2 pool members, no floating IP/session affinity) that connection went to VM2 and
was never answered. **VM2's IIS log has zero entries from any external client for the entire
session.** Still needed: VM2's effective route table — the leading concrete hypothesis for *why*.

## Root cause of the VM2 app-level 500 (tangential to GITIN-1238, but explains a lingering loose end)

User-confirmed (2026-08-27): on VM2, `D:\` is an Azure **temporary disk**, not persistent storage —
consistent with the VM's SKU, `Standard_D2ds_v4` ("ds" series = local temp disk present, mapped as
`D:\` by default). VM1's SKU, `Standard_D8as_v5` ("as" series, no local disk), means VM1's `D:\` is
real persistent storage. `SmartLoyalty.WebServiceV2` is deployed to `D:\` on both VMs (per
`docs/infrastructure.md`) — **on VM2 that means the entire app deployment is ephemeral**, wiped and
reset to whatever was last imaged on any deallocate, host migration, or reimage event. This fully
explains the `maxTraceFileSizeKb`/`ConfigurationErrorsException` 500 found earlier: VM2's `web.config`
is a stale/pre-fix copy that survived because the temp disk was never refreshed with current
deployments, consistent with the already-noted "VM1 and VM2 run different code" finding.

**Not GITIN-1238's core issue** (that's the LB-routing symptom, tracked separately above) but a real,
separate operational risk worth its own follow-up: any future stop/deallocate of VM2 will wipe the
app again unless it's redeployed to persistent storage (OS disk or an attached data disk) instead of
the temp disk. Out of scope to fix here — flagging for a separate ticket/backlog item, not folding
into this ticket's resolution (per this repo's event-scope-isolation convention).

**Config fix applied and app-level bug now confirmed resolved (2026-08-27), but still self-tested
only.** User edited VM2's `web.config` (log paths `D:\Log\...` → `E:\Log\...`); ASP.NET automatically
recycles the app domain on any `web.config` change. VM2's own IIS log (`E:\inetpub\W3SVC1`) for
11:00:59Z–11:42:40Z shows a recovery sequence, all self-originated (`c-ip=192.168.50.172`,
`User-Agent: curl/8.13.0` — VM2's own local curl session, same hosts-file-bypass pattern as all
session, **not** `gondor`'s `curl/8.5.0`): `500` (11:00:59, 11:29:58, 11:31:38, 11:34:28, 11:37:02,
11:37:56) alternating with one `401` (11:29:32), then finally clean `200`s at **11:37:19 and
11:42:40**. The `maxTraceFileSizeKb` bug appears resolved — VM2's app itself is healthy now.

**Correction: this does NOT answer GITIN-1238's core question.** The user's "vm02 for sure" claim
for the 11:42:40Z success is correct in that VM2 served it, but **every one of these requests used
the hosts-file bypass (`c-ip=192.168.50.172`) — the LB was never in the path.** This is the same
confound flagged repeatedly earlier in this session. The core question — does real external client
traffic reach VM2 through the LB — remains open. The `gondor` results (2/3 fresh external connections
succeeding, both landing on VM1; 1/3 timing out with no log entry on either VM, by elimination VM2)
are still the only relevant evidence, and that test has not been repeated since the config fix/app
recycle. **Worth re-running now**, since if the app-pool instability (Event 5021, repeated
crash/restart from the config bug) was also the cause of VM2's HTTP.sys listener being unreliable for
new inbound connections, the fix may have resolved the network symptom too — but that needs a fresh
external test to confirm, not another self-bypass.

## Re-tested after the fix: network symptom persists (2026-08-27)

8 fresh-connection attempts from `gondor` (`--connect-timeout 10`, `Connection: close`, each a
separate curl process): **7× `200`, 1× `000` (hit the 10s cap)**. Combined with the earlier 3-attempt
batch: **11 total fresh external connections from `gondor` today, 2 timeouts (~18%)**. The app-config
fix and app-domain recycle did **not** eliminate the network-level failures — this argues against the
"app-pool instability also broke the listener" hypothesis; the timeout looks like an independent,
still-live issue. **Confirmed via VM1's log:** all 7 successes from this batch (`11:48:12`–`11:48:26Z`, `c-ip=152.169.14.152`,
`curl/8.5.0`) landed on VM1. VM2's log shows nothing in this window (still only the self-bypass
entries already logged). **Final tally: 9/9 successful fresh-connection attempts from `gondor` across
both batches landed on VM1; 2/2 timeouts are unaccounted for on either VM's log** — by elimination
(exactly 2 pool members, no floating IP/session affinity), both timeouts went to VM2, which never
responded. This confirms GITIN-1238's core symptom is still reproducing, and that it is **independent
of the app-level `maxTraceFileSizeKb` bug** (which is now fixed) — the network-level problem is a
separate, still-open issue.

**Also observed in this log window:** a genuine third-party production client (`190.7.25.137`,
Chrome/151, real POS-app traffic — `QueryActivePromotionV3`, `QueryAvailableArticle`,
`ValidateBranchOffice`) at `11:44:10`–`11:44:14Z`, also served entirely by VM1. Organic confirmation
VM1 is healthy under real traffic; not informative about VM2.

## ROOT CAUSE CONFIRMED: NSG denies inbound to VM2 (2026-08-27)

`az network watcher test-ip-flow --direction Inbound --protocol TCP --local 192.168.50.172:8080
--remote <gondor's public IP>:* --vm SFCG-WSV2-02` — Azure's own control-plane answer:

```
{
  "access": "Deny",
  "ruleName": "defaultSecurityRules/DenyAllInBound"
}
```

**This is definitive, first-party evidence — not inference.** The flow hits the *default* deny rule,
meaning no custom NSG rule anywhere in VM2's effective (computed) security state permits inbound
traffic from a real external client to port 8080. This fully explains every symptom observed this
session: TCP-connect timeouts with no SYN-ACK (packet dropped by NSG, not by the guest OS or app),
while Azure's own health-probe traffic (from `168.63.129.16`) still succeeds (Azure's platform probe
traffic is exempted from NSG evaluation, same mechanism as the UDR-bypass gap flagged early in this
investigation — this is the NSG analogue of that same class of gotcha). It also explains why VM1
works: VM1's NIC/subnet effective NSG must differ from VM2's, despite the *configured* NSG being
believed identical/shared (per "LB config re-verified live," above, and the original ticket's "NSG
shared, 8080 open" — both checked at the configured level, never the effective/per-VM level, until
now).

**Confirmed via VM1's test-ip-flow:** `{"access": "Allow", "ruleName": "securityRules/SFCG-WSV2-LB-allow-inbound"}`
— same NIC-level rule as expected. Both VM1's and VM2's NICs reference the **identical** NIC-level
NSG (`SFCG-WSV2-01-nsg`) and identical subnet (`DMZ`). The NIC-level rule (`SFCG-WSV2-LB-allow-inbound`,
priority 999, source `*`, dest `*`, port 8080, Allow) is wide open and can't explain the asymmetry —
so the block had to be at the **subnet-level NSG**, which turned out to be a *different* NSG entirely
(`sfcgnetsec01` — the same shared DMZ-subnet NSG documented for `SFCG-MOBI-LB` in `docs/azure_nsg.md`).
Azure requires a flow to be allowed by both the NIC-level and subnet-level NSG.

## ROOT CAUSE, FULLY CONFIRMED (2026-08-27): hardcoded destination-IP list missing VM2

`sfcgnetsec01` rule **`WebService_V2_PRO`** (priority 123, Inbound, Allow, source `*`, TCP, port 8080)
— the rule that's supposed to permit real client traffic to WebServiceV2 — uses a **hardcoded
destination IP list**, not a subnet or ASG:

```json
"destinationAddressPrefixes": ["192.168.50.171", "192.168.50.173"]
```

`192.168.50.171` = VM1. **`192.168.50.172` (VM2) is not in this list — never was added.**
`192.168.50.173` is a third IP not otherwise referenced anywhere in this investigation (worth noting,
not central to GITIN-1238).

**This fully explains every observed symptom, with nothing left unaccounted for:**
- Azure's own health-probe traffic (source `168.63.129.16`) bypasses NSG evaluation entirely (same
  class of platform exemption as the UDR-bypass mechanism flagged as Gap #3 on day one) — so VM2's
  probe passes even though real traffic can't reach it. This resolves the earlier confusion about
  VM2's probe recovering at 10:41Z (unrelated to this NSG issue — probe traffic was never subject to
  it) while real client connections kept failing throughout the rest of the session.
- Real client TCP connections to VM2:8080 are silently dropped (`DenyAllInBound`, no matching Allow
  rule) — zero response, no SYN-ACK — exactly the original ticket's reported signature, and exactly
  what every `gondor` fresh-connection timeout looked like all session.
- VM1 works because it *is* in the list.
- The LB's own configuration (rules, probes, pool membership, NIC properties) was correctly
  identical for both VMs all along — because the actual asymmetry was never in the LB or the VM's
  own NSG association, but in one specific rule's hardcoded destination scope on the shared
  subnet-level NSG.

**TrustedLaunch/Gen2, VM SKU, Accelerated Networking, and every other avenue investigated this
session (routes, NIC-level NSG, app-pool health, ephemeral-disk config bug, self-hairpin, keep-alive
connection reuse) were all red herrings or unrelated findings — none of them caused the original
symptom.**

## Fix applied (2026-08-27)

User added `192.168.50.172` (VM2) to `sfcgnetsec01`'s `WebService_V2_PRO` rule destination list.
Confirmed live:

```json
"destinationAddressPrefixes": ["192.168.50.171", "192.168.50.172", "192.168.50.173", "192.168.50.174"]
```

`192.168.50.174` was also added in the same edit — not otherwise referenced anywhere in this
investigation; purpose not yet confirmed (possibly a planned future VM). Worth a quick sanity check
separately, not blocking closure of GITIN-1238 itself.

**Verification still needed:** re-run `test-ip-flow` against VM2 and repeat the `gondor`
fresh-connection loop to confirm real traffic now reaches VM2 (not just that the rule was edited).

## Verification: NSG fix confirmed, but 0/50 post-fix requests reached VM2 (2026-08-27)

`test-ip-flow` for VM2 now returns `Allow` via `SFCG-WSV2-LB-allow-inbound` (matches VM1's earlier
result) — the NSG fix is live and Azure's control plane confirms it. A 10-request manual curl batch
(fresh connections, zero timeouts) and a 40-request JMeter run (5 concurrent threads,
`Apache-HttpClient/4.5.14`, fresh connections, `Connection: close`) both ran clean — **but every
single one of these 50 post-fix requests landed on VM1 per its IIS log; VM2's log shows nothing new
at all** (confirmed by user, "no vm02 logs"). A fair 5-tuple hash landing on the same backend 50/50
times running has probability ~9×10⁻¹⁶ — this is not chance.

**Leading hypothesis: LB rule distribution mode.** Azure Standard LB rules support session-affinity
modes (`SourceIP` 2-tuple or `SourceIPProtocol` 3-tuple hashing) instead of the default 5-tuple hash.
If `SFCG-WSV2-LB-lbrule01` uses one of these, every connection from a given client IP always lands on
the same backend — which fully fits the pattern: every test source IP used all session (`gondor`,
Postman's client, the organic browser clients at `181.13.173.83`/`186.158.228.105`/`190.7.25.137`)
has landed on VM1 every time, with no exceptions post-fix.

**Ruled out (2026-08-27):** `az network lb rule show` confirms `loadDistribution: "Default"`
(standard 5-tuple hash), not `SourceIP`/`SourceIPProtocol` affinity — with genuinely fresh
connections this should distribute across both healthy backends.

**Ruled out (2026-08-27):** `DipAvailability` by `BackendIPAddress`, 11:37Z–12:16Z (spans the entire
post-fix test window) — both VM1 and VM2 flat 100.0% every single minute. VM2's probe has been
continuously healthy this whole time; the LB has no probe-based reason to exclude it.

**Still unexplained at the time: NSG allows it, distribution mode is `Default`, probe is 100%
healthy — yet 0/50 post-fix requests reached VM2.**

## Isolated single-VM test rule created (2026-08-27)

Per user decision, built an isolated path to remove all ambiguity: new frontend port `8081` on
`SFCG-WSV2-LB`, temporary backend pool `SFCG-WSV2-LB-test-vm2only-pool` containing **only** VM2's NIC
(`sfcg-wsv2-02397_z1`/`ipconfig1`), new rule `SFCG-WSV2-LB-test-vm2only-rule` (backend port 8080,
reusing the existing probe `sfcg-sondeo02`, `disableOutboundSnat=true` — required since it shares the
frontend IP with the existing outbound rule). Azure also required removing VM2's NIC from the live
`SFCG-WSV2-LB-backendpool01` first (a VM can't be targeted by two same-port/protocol/no-floating-IP
rules) — low risk given all evidence shows VM2 was receiving ~0% of real traffic through the live
pool anyway. **Rule confirmed live, `provisioningState: Succeeded`.** Real production traffic on the
existing `8080` rule/pool is untouched.

**CLEANUP REQUIRED once testing is done — do not forget:**
1. `az network lb rule delete --lb-name SFCG-WSV2-LB --name SFCG-WSV2-LB-test-vm2only-rule`
2. `az network lb address-pool delete --lb-name SFCG-WSV2-LB --name SFCG-WSV2-LB-test-vm2only-pool`
3. **Re-add VM2 to the live pool**: `az network nic ip-config address-pool add --nic-name sfcg-wsv2-02397_z1 --ip-config-name ipconfig1 --lb-name SFCG-WSV2-LB --address-pool SFCG-WSV2-LB-backendpool01`
   (all with `--resource-group DefaultGroup01 --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8`)

## Isolated test result: VM2 fully works (2026-08-27, 12:25:05Z)

`curl -k --http1.1 -H "Host: webservicev2.smartfran.com" ... https://52.186.168.27:8081/...` through
the VM2-only pool — **`HTTP/1.1 200 OK`, complete valid promotions payload, `Date: 2026-08-27
12:25:05 GMT`.** VM2 is the only possible backend for this frontend port. **This is definitive,
unambiguous proof: VM2 can fully serve real external client traffic through the LB** — TCP connect,
TLS, HTTP, app logic, all working correctly. The NSG fix was correct and sufficient at the VM2 level.

## CORRECTION: the "0/50 reached VM2" finding was a stale-log-read artifact, not real (2026-08-27)

User re-checked VM2's IIS log directly and found it now contains entries that were invisible on every
earlier query this session — including **the exact same requests already attributed entirely to
VM1**: the 10-request curl batch (`12:00:31`–`12:00:40`, `curl/8.5.0`, `c-ip=152.169.14.152` — these
are the *other* half of the same batch VM1's log showed at `12:00:24`–`12:00:29`; together they
account for all 10 requests, split ~4/6 across the two VMs) and part of the 40-request JMeter run
(`12:13:31`–`12:14:10`, `Apache-HttpClient/4.5.14`, same client — the remainder of the 40 requests
VM1's log showed at `12:13:37`–`12:13:52`). **The live pool was distributing to both VMs correctly
the entire time; earlier reads of VM2's log file were stale (Azure disk-caching artifact — per user,
"sometimes azure does not update disks files"), not an accurate view of current state.**

**Also found in this corrected read: genuine real production traffic already reaching VM2** —
`12:10:23`–`12:10:25Z`, `c-ip=186.12.190.200`, `Referer: https://grido.pos.smartfran.com/` — an
actual POS client, not a test tool, served successfully by VM2. This is the strongest possible
confirmation: real production traffic is already flowing to VM2 through the live path.

**Conclusion: GITIN-1238 is fully resolved.** The NSG fix (`WebService_V2_PRO` missing
`192.168.50.172`) was the complete root cause and complete fix. The isolated-pool test independently
confirmed VM2 works; this log correction confirms the live rule/pool was routing to it correctly all
along. There was no second bug — only a misleading diagnostic read.

**Methodology note for future investigations:** when a VM's own IIS log appears to show zero entries
for a window where activity is otherwise expected, don't treat that as conclusive without a second,
time-delayed re-read — Azure's disk layer can serve a stale view of a file that has, in fact, already
been updated. This cost significant time in this session (the isolated single-VM test rule, extensive
NSG/route/hash investigation) chasing a phantom "why doesn't VM2 receive traffic" question after the
real fix already worked.

**Cleanup confirmed complete (2026-08-27):** test rule and test pool deleted; VM2's NIC
(`sfcg-wsv2-02397_z1`/`ipconfig1`) confirmed back in `SFCG-WSV2-LB-backendpool01` only — no trace of
the temporary test pool remains. Full production redundancy restored.

## STATUS: RESOLVED (2026-08-27)

**Root cause:** `sfcgnetsec01` NSG rule `WebService_V2_PRO` (subnet-level, DMZ) allow-listed
destination IPs `192.168.50.171`/`.173` for TCP 8080 but never included `192.168.50.172` (VM2) —
an omission from whenever VM2 was provisioned. Azure's own probe traffic bypasses NSG evaluation
(so VM2 always looked healthy), but real client connections were silently dropped
(`DenyAllInBound`), matching the original ticket's exact symptom.

**Fix:** added `192.168.50.172` to that rule's destination list (`192.168.50.174` also added in the
same edit, purpose unconfirmed — flag separately).

**Verification:** `test-ip-flow` confirms `Allow`; an isolated single-VM-pool test proved VM2 serves
real LB traffic end-to-end; the live pool's own IIS log (once read correctly, past an Azure
disk-caching artifact that made an earlier check falsely appear empty) confirms real production POS
traffic (`grido.pos.smartfran.com`) already routing to VM2 successfully.

**Not GITIN-1238, but discovered along the way (see relevant sections above, not folded into this
ticket's resolution):**
- VM2's `D:\` is an Azure temporary disk (ephemeral) — the app was deployed there, and a stale
  pre-fix `web.config` (a separate, now-fixed `maxTraceFileSizeKb` bug) survived because of it. Real
  operational risk: any future deallocate wipes the app again unless redeployed to persistent storage.
- `192.168.50.174` added to the NSG rule alongside the fix — purpose not confirmed.
- Original ticket's TrustedLaunch/Gen2 hypothesis was never correct.

**Ready for ticket closure** (`ops.md`/`ops-events.md` per `loyalty-sre-output` skill) once Jira URL
is confirmed and the two flagged follow-ups (ephemeral disk, `.174`) are logged as separate items if
the user wants them tracked.

## Follow-up attempted and rolled back: healthcheck.ashx probe (2026-08-27, post-resolution)

Separate from GITIN-1238 itself. Attempted to switch the live probe from TCP (`sfcg-sondeo02`) to the
existing-but-orphaned `healthcheck` probe (fixed `Http`→`Https` protocol mismatch, bumped
`numberOfProbes` 1→2, matching the `/healthcheck.ashx` app-level check already used elsewhere in this
investigation). Attached to `SFCG-WSV2-LB-lbrule01`.

**Result: VM2's health probe failed under the new probe** — 100%→25%→0% over `12:41`–`12:45Z` (~6 min
total degraded window), while VM1 stayed 100% throughout. **Rolled back to `sfcg-sondeo02`
immediately**; VM2 confirmed recovered to 100% by `12:47Z`. No lasting production impact — this is
exactly why the old probe was deliberately left defined instead of deleted.

**Leading theory, not yet confirmed:** Azure LB HTTPS probes hit the backend's private IP directly
with the IP as the `Host` header, not a friendly hostname. If VM2's IIS site binding for
`/healthcheck.ashx` requires a specific hostname match (VM1 and VM2 are already known to run
different code/deployments — see app-config-bug section above), an IP-only request could get
rejected or misrouted on VM2 specifically while working fine on VM1.

**Status: parked, not retried.** User called a stop here after confirming rollback. Before any future
attempt: check VM2's IIS site bindings for host-header requirements on port 8080/`/healthcheck.ashx`
offline, first — don't re-attempt live against production again without that check done first.

## Zabbix monitoring parity — WSV2-02 onboarding, final piece (2026-08-27)

VM2 previously had no Zabbix monitoring cloned from VM1. Cloned via the Zabbix frontend's own "Clone"
host feature (`SFCG-WSV2-01`, hostid `10665` → `SFCG-WSV2-02`, hostid `10678`) — confirmed identical
templates (`IIS by Zabbix agent active`, `Windows by Zabbix agent active`) and host macros
(`{$IIS.APP.NAME}`, `{$IIS.APPPOOL.MATCHES}`, `{$IIS.PORT}=8080`, `{$IIS.SERVICE}=https`) via the
Zabbix API. Confirmed VM2's own `zabbix_agent2.conf` has `Hostname=SFCG-WSV2-02` matching, and
confirmed real, current data flowing (`perf_counter_en` items, live `lastclock`).

**Handled: VM2 is not run 24/7 like VM1** — powered off nightly `00:00–09:00 UTC-3` (confirmed with
user). Cloned triggers assume 24/7 uptime and would otherwise misfire on every intentional power-off
(service-not-running, port-down, "has been restarted" triggers from the linked templates). Checked
live alert routing (`action.get`) before deciding a fix: the tag-based Google Chat/Email actions are
all currently disabled; the one enabled, unfiltered action (`Report problems to Zabbix
administrators`, matches every problem on every host) is what would actually page someone. Rather
than touching any trigger, created a Zabbix Maintenance period (`maintenanceid 2`, daily,
`start_time=0`/`period=32400` = 00:00–09:00, frontend timezone confirmed `America/Argentina/Cordoba`
= fixed UTC-3, matches exactly) — every pulled action already has `pause_suppressed: "1"`, so this
fully suppresses notifications during the window with zero trigger/action edits.

**Not pursued, parked by user mid-discussion:** a new Zabbix Web scenario validating
`https://webservicev2.smartfran.com:8080/healthcheck.ashx` responses (200-only success condition),
to be run via the only available Proxy (`sfcg-monitoreo`, proxyid `10609`). Open question left
unresolved: attach to an existing host (`SFCG-WSV2-01`) vs. a new dedicated host — user said
"nevermind" before deciding. Revisit if asked again; don't assume which option was intended.

## WSV2-02 onboarding: fully complete (2026-08-27)

Both pieces done: the LB/NSG routing fix (root cause of `GITIN-1238`, verified end-to-end) and Zabbix
monitoring parity with VM1 (cloned config, confirmed live data, power-schedule-aware via Maintenance
window). Nothing else outstanding for this event.

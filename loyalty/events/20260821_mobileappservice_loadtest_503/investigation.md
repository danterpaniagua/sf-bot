# Investigation — 20260821_mobileappservice_loadtest_503

**Status:** CLOSED (2026-08-21). Primary root cause confirmed (`connectionTimeout=15s`), secondary self-inflicted issue also confirmed (LB TCP-only probe, out of scope). Ticket (`ops.md`) written and closed. Load test subsequently completed with no infrastructure changes applied on our side (`connectionTimeout` left at 15s, no LB/probe change made) — whether that specific run had zero connection resets or just a tolerated volume was never confirmed; ticket closed regardless, with the Grido-coordination action item left open as non-blocking follow-up.
**Jira ticket:** [GITIN-1909](https://smartit-ar.atlassian.net/browse/GITIN-1909)

## Reported symptom

Grido is running a load test against MobileAppService and reports 503 errors with client-side message:

> An error occurred while sending the request. Unable to read data from the transport connection: An existing connection was forcibly closed by the remote host.. An existing connection was forcibly closed by the remote host.

Graylog shows **zero** 503s for the same window.

## Architecture facts (from `docs/infrastructure.md`, confirmed prior sessions)

- MobileAppService = ASP.NET MVC/WebApi on .NET Framework 4.x, IIS, requires VM (not App Service PaaS).
- Runs on `SFCG-MOBI-01` (confirmed Running, `Standard_B2as_v2`, `eastus`, public IP `20.121.19.174`, DMZ subnet, RG `DEFAULTGROUP01`, subscription **Smart IT - Grido**) and `SFCG-MOBI-02` (exists, status/IP **not yet confirmed**).
- Unlike WebSite/ClubGrido (which sit behind Application Gateway WAF `WAF_APPs`), no WAF is documented in front of MobileAppService.
- **Confirmed by user (2026-08-21):** an Azure Load Balancer does front `SFCG-MOBI-01/02` — `SFCG-MOBI-LB`, resource group `DefaultGroup01`, subscription `0190fa7d-4ccf-4e3d-beb1-323b5780bfc8` (Smart IT - Grido). Not yet in `docs/infrastructure.md` — add once diagnostics below confirm backend pool membership. This resolves the earlier open question — the LB theory is live, not ruled out.
- **LB config confirmed (2026-08-21):**
  - SKU: **Standard**. Frontend: single public frontend config `SFCG-MOBI-LB-frontendconfig01`, public IP resource `SFCG-MOBI-LB-publicip` (actual IP value not yet pulled — need to confirm whether this matches or differs from the `20.121.19.174` previously attributed directly to `SFCG-MOBI-01` in `docs/infrastructure.md`; if traffic actually flows through the LB, that prior doc entry may need correction).
  - Only **one** LB rule exists: `SFCG-MOBI-LB-lbrule02`, TCP **8043→8043**, `idleTimeoutInMinutes=15`, backend pool `SFCG-MOBI-LB-backendpool01`, probe `SFCG-MOBI-LB-probe02`, floating IP disabled.
  - 15-min idle timeout is above Azure's 4-min default (deliberately raised) — lowers likelihood of the idle-timeout theory unless the load test holds connections idle past 15 min, which is unusual for load-test traffic. Not ruled out yet, just downgraded.
  - **Single rule on port 8043 only** — not yet confirmed this is actually the port/endpoint Grido's load test targets. If the load test hits a different port (e.g. 443) with no matching LB rule, that mismatch itself could produce connection resets — needs the actual test endpoint to check.
  - Backend pool `SFCG-MOBI-LB-backendpool01` contains both `sfcg-mobi-01421` and `sfcg-mobi-02639` NICs — **confirms `SFCG-MOBI-02` is live and in rotation** (resolves the "status not yet confirmed" gap in `docs/infrastructure.md`). Both VMs are genuinely receiving load-test traffic through the LB, not just `-01`.
  - **Public IP resolved: `20.121.19.174`, Static** — this is the **same IP** `docs/infrastructure.md` had attributed directly to `SFCG-MOBI-01`'s own NIC. Corrected in the infra doc (2026-08-21): the IP belongs to the LB (`SFCG-MOBI-LB-publicip`), not the VM directly. Not a discrepancy to investigate further — a doc error, now fixed.
  - **Probe config:** three probes exist, but only **`SFCG-MOBI-LB-probe02`** (plain TCP, port 8043, 5s interval, **`numberOfProbes=1`**) is attached to the live rule. The other two (`SFCG-MOBI-LB-probe01` — HTTP `/api/MobileAppService/CheckServiceStatus`, 5s interval, 2 probes; `healthcheck.ashx` — HTTPS `/healthcheck.ashx`, 5s interval, 1 probe) are **orphaned**, not referenced by any current rule.
  - **`numberOfProbes=1` on the active probe is the strongest lead so far.** A single missed 5-second TCP check is enough for Azure to mark a backend unhealthy and pull it from rotation — unusually aggressive (Azure typically recommends ≥2 to avoid flapping on transient blips). Under load-test-induced CPU/thread pressure on `SFCG-MOBI-01`/`-02`, a single delayed TCP accept could trigger this. Important nuance: Azure Standard LB does not itself send RST to already-established flows when it pulls a backend from rotation (it's flow-based NAT, not stateful teardown) — so a probe-driven pull would stop *new* connections from routing to that backend, but the "forcibly closed" resets on in-flight requests would still originate from the VM itself (IIS/OS under the same resource pressure that caused the probe to fail), not the LB directly. **This means probe flapping and connection resets likely share a common root cause (VM overload) rather than the LB causing the reset by itself** — worth confirming via the LB's `DipAvailability` metric correlated against the load-test window, not assumed.

## Working theory

The exact exception text (`Unable to read data from the transport connection: ... forcibly closed by the remote host`) is a raw client-side `SocketException`/`IOException` thrown by `HttpClient` when the TCP connection is reset **before** an HTTP response is fully received — it does not require IIS/ASP.NET to have ever written a 503 status line. This is consistent with Graylog showing no 503s: if the app never got to (or never finished) writing a response, there's nothing for the app-level Serilog pipeline to log.

Working hypothesis: Grido's load-test tool is bucketing transport-level connection failures as "503" in its own reporting, not reflecting a real IIS/ASP.NET response code. If confirmed, the real question isn't "why does the app return 503" but "why is something resetting/dropping TCP connections under load" — candidates, in rough likelihood order for a Windows/IIS VM setup like this:

1. **IIS app pool recycling mid-test** — default recycling (time interval or private-memory threshold) killing the worker process while connections are in flight. Very common load-test symptom on IIS.
2. **Azure Load Balancer TCP idle timeout** — *if* an LB does exist in front of `SFCG-MOBI-01/02` and wasn't documented, Azure LB's default 4-min (configurable up to 30-min) idle timeout silently drops idle-but-kept-alive connections with an RST, no LB-level log entry. Needs the LB-existence check first.
3. **NSG (`sfcgnetsec01`) rule closing/rate-limiting connections** on the DMZ subnet under high concurrent-connection volume from the load-test source IP(s).
4. **http.sys / IIS connection or queue limits** (`appConcurrentRequestLimit`, `maxConnections`, KeepAlive settings mismatch between load-test client and IIS) under load-test concurrency.
5. Windows Firewall on `SFCG-MOBI-01/02` dropping connections under high new-connection rate.

Not yet ruled in or out — no diagnostic run yet this session. With the LB now confirmed (`SFCG-MOBI-LB`), theory #2 (LB-level connection drop) is the leading candidate: Azure Load Balancer's default TCP idle timeout (4 min, configurable to 30) closes idle-but-kept-alive connections with a silent RST and no LB-level log entry — a common cause of exactly this client-side exception under sustained load. A failing/flapping health probe pulling a backend out of rotation mid-test (Azure LB does not drain in-flight connections by default) is the other strong candidate — both point at the LB config itself, not IIS.

## Confirmed anomaly (2026-08-21, `DipAvailability`/"Health Probe Status" metric on `SFCG-MOBI-LB`)

100.0 steady from 11:00Z through 12:06Z, then:
- 12:07Z → **56.52**
- 12:08Z → **62.5**
- 12:09Z → back to 100.0, steady since

With `numberOfProbes=1` and a 2-backend pool, a dip in this range is consistent with one of the two VMs missing its health probe for roughly two minutes before recovering.

**User identified the cause of this specific dip (2026-08-21):** `SFCG-MOBI-02` was starting up at 12:07Z — the dip reflects `-02` failing probes while its VM/IIS was still coming up, not a flap of an already-running, already-healthy backend under load. This is expected LB behavior (a booting backend correctly fails probes until ready) and, on its own, should **not** have caused client-facing impact — the LB should have kept routing all traffic to `SFCG-MOBI-01` (already healthy) during those two minutes.

**Open fork, not yet resolved:** *why* was `SFCG-MOBI-02` starting at that moment?
- If it was a deliberate scale-out/prep action (manually started, or autoscale, ahead of/during the load test) — this dip is a non-issue, explained and closed.
- If `-02` crashed or was restarted unexpectedly (fault, OOM, host maintenance, extension failure) mid-test — that's a real finding and would need its own root-cause chain, separate from the probe-threshold theory.

Also open: with only `SFCG-MOBI-01` healthy for ~2 minutes, if load-test traffic volume was already high at 12:07Z, that's 2 minutes of double load concentrated on a single VM — worth checking `SFCG-MOBI-01`'s own httperr.log/WAS events for that window regardless of why `-02` was starting, since single-backend overload could independently produce connection resets on `-01`.

Not yet checked: Azure Activity Log for `SFCG-MOBI-02`'s power-state history around 12:07Z, to determine manual/scheduled start vs. unplanned restart — needed to resolve the fork above.

## `SFCG-MOBI-01` httperr.log, 12:04Z–12:08Z (user-provided, 2026-08-21)

Client IP `172.191.0.208` → server `192.168.50.111:8043` throughout. This is the same IP allow-listed in NSG rule `Grido-Mobile-Allow`. A separate local doc (`~/Documentos/git/smartfran-documentacion/sml-sf-mobile.md`) labels it "APIM Grido" (Grido's Azure API Management egress, not a raw load-test client machine) — **not independently verified; per the user (2026-08-21), that doc's currency relative to this project is unconfirmed, so treat the label as reported, not settled fact.** If it holds, the remediation conversation (retry-on-idle-connection-close) would need to target Grido's APIM config rather than a generic load-test tool — but don't act on that specifically until confirmed some other way (e.g. asking Grido directly). Doesn't change the root-cause conclusion below either way. Pattern:
- **Repeated `Timer_ConnectionIdle` entries, continuously across the whole 12:04–12:08 window** (not concentrated in the 12:07–12:08 probe-dip specifically) — http.sys itself actively closing keep-alive connections idle past its configured timeout (default 120s if unconfigured — actual `connectionTimeout` value for this site not yet confirmed).
- Two `Request_Cancelled` entries against real API endpoints (`GetAddicionalInformation`, `GetCustomerStatus`) — this reason code means the *client* disconnected while the server was still processing, not the server closing on the client. Likely the load-test tool's own client-side timeout, not the same mechanism as the reported symptom — noted but not treated as the same root cause without further evidence.

**New leading theory, evidence-backed rather than inferred:** `Timer_ConnectionIdle` is the server (http.sys) actively closing idle keep-alive connections — exactly the kind of server-side action that produces "connection forcibly closed by remote host" on the client if the load-test tool's connection pool tries to reuse one of these connections right as (or just after) the server closes it. This pattern is continuous through the window, independent of the `SFCG-MOBI-02` probe-dip — suggests **two distinct, possibly-coexisting issues**: (1) the brief `-02` startup probe-dip (12:07–12:08Z, cause still unconfirmed — deliberate vs. unplanned), and (2) a persistent keep-alive idle-timeout race on `-01`, unrelated to `-02`'s state.

**Not yet confirmed:**
- The site's actual configured `connectionTimeout` (applicationHost.config/web.config) — needed to know how aggressive this timeout actually is.
- Whether Grido's load-test tool reuses pooled connections with its own idle/keep-alive assumptions that could race against this.
- `SFCG-MOBI-02`'s httperr.log for the same window, for comparison — not yet provided.
- Azure Activity Log check for `SFCG-MOBI-02`'s start — not yet run.

**Ruled out (2026-08-21):** app-pool recycling / rapid-fail-protection on `SFCG-MOBI-01` — `Get-WinEvent` against `Microsoft-Windows-WAS`, System log, 12:04Z–12:11Z returned **zero events**. `-01`'s connection resets during this window are not explained by a pool recycle. The `-01` `Timer_ConnectionIdle` pattern is downgraded relative to the `-02` root cause below — likely routine keep-alive churn under load, not the primary driver of the reported symptom.

## Correction (2026-08-21): sequencing — VM02 was NOT the original trigger

**User confirmed: `SFCG-MOBI-02` was turned on *after* Grido's 503 report**, not before/during the load test's start. This means the analysis below (VM02 startup → real 503s + WAS-restart-driven resets) describes a **real, secondary, self-inflicted issue** — caused by someone (ops) reactively scaling out to `-02` in response to the original complaint — but it is **not** the original root cause Grido first hit. Downgraded from "ROOT CAUSE FOUND" accordingly; kept below as a confirmed, separate finding worth fixing on its own merits (see "Fix implication").

This reopens the original question: what caused the *first* 503/connection-reset reports, before `-02` was ever involved? The only backend in play at that point was `SFCG-MOBI-01`, and its httperr.log for 12:04:07–12:06:48 (i.e. entirely before `-02`'s 12:06:37 WAS start) already shows the `Timer_ConnectionIdle` pattern and 2×`Request_Cancelled` documented above, with **no literal 503 status** in that excerpt. This re-elevates the `-01` keep-alive idle-timeout theory as the leading candidate for the *original* report.

## PRIMARY ROOT CAUSE CONFIRMED: `connectionTimeout=15s` on MobileAppService (both VMs)

```
Get-ItemProperty "IIS:\Sites\SmartLoyalty.MobileAppService" -Name limits.connectionTimeout
```
- `SFCG-MOBI-01`: `00:00:15`
- `SFCG-MOBI-02`: `00:00:15`

Confirmed identical on both instances — a real, site-wide config setting (not host drift, not a fluke). IIS's own default is 120 seconds; this site is configured roughly **8x more aggressive** at 15 seconds.

**Mechanism:** any standard connection-pooling HTTP client (.NET's own `SocketsHttpHandler` defaults to a 2-minute idle-pool eviction; `HttpClient`/`ServicePointManager` era defaults are similarly on the order of 100s+) will routinely attempt to reuse a pooled keep-alive connection that has sat idle for more than 15 seconds. IIS/http.sys will have already force-closed that connection (`Timer_ConnectionIdle`, as directly observed in `-01`'s httperr.log throughout 12:04–12:08, entirely independent of the later `-02` startup episode). The client-side result is exactly the reported exception: **"connection forcibly closed by remote host."** This requires no load-level trigger beyond "enough concurrent pooled connections that some sit idle >15s between requests" — which a load test naturally produces (bursty request patterns, connection pool sized larger than sustained concurrent throughput). Grido's tooling most likely buckets this transport-level failure as "503" in its own reporting, consistent with Graylog showing zero real 503s from this mechanism (ASP.NET never received or completed these requests — nothing for the app-level Serilog pipeline to log).

**Confidence:** high. Mechanically sound, config confirmed on both instances, directly observed httperr pattern matches, and requires no additional unconfirmed assumption (unlike the `-02` health-probe finding, which needed the WAS-restart timing to line up). Still not verified against Grido's own error timestamps (never obtained) — recommend getting those before final ticket closure, as a confirmation step rather than a precondition for the fix.

**Timeline clarified (user, 2026-08-21): the original incident predates `SFCG-MOBI-02` entirely.** `-02` was turned on *in response to* Grido's report, not before it. Its own 503s (12:07:20–21) therefore happened *after* the incident was already reported and cannot be what Grido originally saw — they're a second, self-inflicted, later problem caused by the reactive scale-out landing on an under-validated health probe. This sharpens the primary finding: for the actual original report, we sent **zero real HTTP 503 responses** — confirmed by the complete absence of any `sc-status=503` line in `-01`'s httperr.log for the entire pre-`-02` window (12:04:07–12:06:48). The original incident is 100% explained by the connection-level `Timer_ConnectionIdle` mechanism, with no HTTP response involved at all. Grido's "503" label is their own load-test tooling's classification of a transport-level connection reset, not a status code we ever actually returned for the original incident.

**Remediation — reframed per user input (2026-08-21):** `connectionTimeout` is IIS's standard idle-connection control — governs how long an *already-established* connection can sit idle before being closed, a legitimate anti-connection-exhaustion/slow-HTTP mitigation. 15s at an API is short but is plausibly a deliberate security choice, not obviously a misconfiguration. (Distinct from literal TCP SYN-flood protection, which operates at the kernel/half-open-connection level before a connection is ever established — outside IIS's control and not what `connectionTimeout` governs — but the general idle-connection-exhaustion concern behind the user's point is a real, standard reason to keep this value tight.)

**Not yet resolved:** whether 15s was in fact a deliberate security decision (needs confirmation — check with whoever owns this config / any security-hardening documentation, not assumed either way) or genuinely just misconfigured/inherited from a template. This matters for where the fix belongs:
- If intentional: the real gap is that a pooled HTTP client (Grido's load-test tool, and potentially the production mobile client) needs to tolerate the server closing an idle pooled connection and transparently retry on a fresh one — standard, expected behavior for any pooling HTTP client against any server with any idle timeout. Recommended action shifts toward coordinating with Grido on their client's retry behavior, not changing our server config.
- If not intentional / no longer needed: raising it to a more standard value (e.g. IIS default 120s) removes the problem outright, at the cost of loosening whatever idle-connection-exhaustion protection it was providing.

**Ticket action item, pending this decision:** confirm intent behind `connectionTimeout=15s` before proposing a specific remediation — do not default to "just raise it" without that confirmation.

## Confirmed (user, 2026-08-21): no L7/WAF device in front of MobileAppService — path is NSG → LB → IIS only

`WAF_APPs` (Application Gateway) exists in `DefaultGroup01` but is **not** wired to MobileAppService — confirmed by user; it fronts WebSite/ClubGrido only, as already documented. MobileAppService's actual ingress path: client → **NSG, one-to-one source-IP allow-list** (not subnet-based) → `SFCG-MOBI-LB` (L4, confirmed earlier via resource type) → IIS on `SFCG-MOBI-01`/`-02`.

This closes out the "could the LB/WAF itself have sent a 503" question definitively: neither the NSG (stateless packet filter, no HTTP awareness) nor the LB (Layer 4, no HTTP awareness) is structurally capable of generating an HTTP status code. The **only** component in this entire path that can produce an HTTP 503 is IIS itself.

## DEFINITIVE PROOF (user, 2026-08-21): zero real 503 responses sent by `SFCG-MOBI-01`, load-test start → `SFCG-MOBI-02` start

Full scan of `C:\Windows\System32\LogFiles\HTTPERR\httperr*.log` on `SFCG-MOBI-01` (all rotated files, not a sampled excerpt), parsed field-by-field for the exact `sc-status` column, window `2026-08-21T11:00:00Z`–`2026-08-21T12:06:37Z` (load test start → `SFCG-MOBI-02` WAS start):

- **Total httperr.log entries in window: 969** (confirms the window has substantial real traffic data, not a logging gap)
- **Entries with `sc-status=503`: 0**

(Cross-check: `SFCG-MOBI-02` scanned with the same script/window returned 0 total entries — expected and non-informative, since `-02` wasn't powered on yet; not evidence of anything, just confirms it was correctly idle before its 12:06:37 start.)

**This closes the original-incident question with certainty, not inference:** across 969 logged connection-level events on the only VM serving traffic during the original incident window, not one was a real HTTP 503. Combined with the confirmed absence of any L7 device in the path (NSG/LB are both incapable of generating HTTP status codes), the conclusion is airtight: **we never sent a 503 response for the original incident Grido reported.** Every failure in that window is `Timer_ConnectionIdle`/connection-reset — a direct, mechanical consequence of the (confirmed deliberate, security-motivated) `connectionTimeout=15s` setting colliding with a pooled HTTP client's connection reuse assumptions. Grido's "503" is their load-test tooling's own classification of that transport failure, not a status code any component in our stack produced.

**Context (user, 2026-08-21):** this LB/VM pair has already handled 800+ requests in prior load-balancing tests without this surfacing — consistent with the mechanism being reuse-pattern/timing-dependent (idle gaps between pooled-connection reuse) rather than a raw capacity/throughput problem.

Superseded/downgraded by this finding: (1) the `-01` NSG/OS-level theories from earlier in this investigation, (2) idle-timeout-on-the-LB theory (LB's 15-min idle timeout was already ruled unlikely to matter — this is IIS's *own* much shorter timeout, a completely separate setting that happens to share the same "15" digit by coincidence, not related to the LB's `idleTimeoutInMinutes=15`).

**Note on the coincidence:** IIS `connectionTimeout` = 15 **seconds**; LB rule `idleTimeoutInMinutes` = 15 **minutes**. Same numeral, different units, different layers — flagging explicitly so this isn't misread later as the same setting.

## `SFCG-MOBI-02` httperr.log + WAS events, 12:04Z–12:11Z (user-provided, 2026-08-21) — secondary, self-inflicted issue (not the original trigger — see correction above)

**WAS events (`Microsoft-Windows-WAS`, System log) on `SFCG-MOBI-02`:**
- `12:06:37` — Event 5211, WAS started ('Classic' mode)
- `12:07:46` — Event 5211, WAS started again (**second restart within ~70 seconds**)

**httperr.log on `SFCG-MOBI-02` (`192.168.50.112:8043`), same window:**
- `12:06:55`–`12:07:17` — dense burst of `Request_Cancelled` against real endpoints (`GetAddicionalInformation`, `GetCustomerStatus`, `GetCustomerProfile`) — client-visible disconnects while the server was mid-request.
- **`12:07:20`–`12:07:21` — 9 requests return literal `sc-status=503`, reason `N/A`**, straight from http.sys/IIS — real 503s, not inferred. These occurred between the two WAS restarts, while the worker process/app pool wasn't yet stable.
- `12:08:36` onward — more `Request_Cancelled`, then `Timer_ConnectionIdle` resuming by `12:09:03` as things settle.

**Root cause, evidence-backed:** `SFCG-MOBI-02` came up (boot/WAS init) right at the start of this window. The LB's only active health probe (`SFCG-MOBI-LB-probe02`) is **plain TCP** on port 8043 — it verifies the port accepts a connection, not that IIS/the app pool is actually able to serve HTTP. Port 8043 opened before WAS/the app pool was fully stable, so the TCP probe marked `-02` healthy and the LB (with `numberOfProbes=1`, no grace period) began routing live load-test traffic into the startup gap:
- Requests landing while no worker process was ready got literal **503** from IIS itself (12:07:20–21) — never logged by the app's own Serilog pipeline since ASP.NET never got the request, which is exactly why **Graylog shows zero 503s** for a window where IIS demonstrably returned nine of them.
- Requests in flight (or freshly pooled) at the **second** WAS restart (12:07:46) got their TCP connections torn down by the service bounce — this is the literal mechanism behind the client-side **"connection forcibly closed by remote host"** exception Grido reported.

Both halves of Grido's reported symptom (the "503" label *and* the transport-reset message) trace to the same ~70-second window on `SFCG-MOBI-02`, and both are explained without needing to assume a distinct app-level or NSG-level cause.

**Scope note (user, 2026-08-21): the TCP-only LB probe is known, pre-existing tech debt — not specific to or caused by this case.** Out of scope for this ticket's root cause/remediation; not to be presented as a finding of this investigation. Left documented here (and in `docs/infrastructure.md`) purely because this session is what surfaced its concrete effect (the `-02` startup 503 burst), for whoever eventually prioritizes it — not as an action item for `GITIN-1909`.

**Still open, not yet resolved:**
- Why `SFCG-MOBI-02` needed to start at 12:06:37 in the first place, and why WAS restarted a *second* time at 12:07:46 (single clean boot wouldn't obviously produce two 5211 events) — deliberate scale-out vs. unplanned restart still unconfirmed (Activity Log check not yet run).
- Whether this is a one-off (VM was cold-started specifically for this load test, unlikely to recur under steady-state) or a repeatable pattern (e.g., an autoscale rule bringing `-02` in/out routinely, in which case this would recur on every scale event without a probe fix).

## Open questions (need from user before running diagnostics)

- ~~Load test date/time window~~ — **confirmed by user (2026-08-21): 08:00 UTC-3 → ongoing ("to now")**, i.e. **11:00 GMT/UTC 2026-08-21 → ongoing**. Test still in progress at time of this note — use current UTC time as the end bound when running queries below, not a fixed value.
- Exact hostname/endpoint/port Grido's load-test tool is hitting — still not confirmed. Working assumption is port 8043 (the only load-balanced port), but not verified against the actual test config.
- ~~Whether `SFCG-MOBI-02` is confirmed in rotation~~ — resolved, confirmed live in LB backend pool.

## Next steps (planned, not yet executed)

1. Confirm whether an Azure Load Balancer actually fronts `SFCG-MOBI-01/02` (`az network lb list -g DEFAULTGROUP01`) — resolve the "could be Az Load Balancer" theory from data, not assumption.
2. Resolve the load-test endpoint hostname to confirm which IP/VM is actually receiving traffic.
3. On `SFCG-MOBI-01` (and `-02` if confirmed live): pull `httperr*.log` (http.sys error log — captures connection resets/aborts even when IIS/ASP.NET never produced a response) for the load-test window.
4. Check IIS Application Pool recycling events (Event Viewer `System`/`Application`, WAS/W3SVC-WP source, event 5074 and neighbors) for the same window.
5. Check NSG `sfcgnetsec01` rules for the DMZ subnet for anything that could drop/rate-limit high-concurrency connections from the load-test source.

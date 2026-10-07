# Investigation — 20260916_gitin1228_lb_healthcheck

**Status:** health check implemented, deployed to both VMs, and cut over to the LB — probe fix is done. Two items remain open: the self-removal-under-load fix, and whether genuine CPU/RAM-weighted balancing (the ticket's stated broader goal) is achievable on Azure Standard LB at all.
**Jira ticket:** [GITIN-1228](https://smartit-ar.atlassian.net/browse/GITIN-1228) — "[SML] Implementar mejora en Load Balancer Mobile"

## Origin

Follows directly from [GITIN-2053](https://smartit-ar.atlassian.net/browse/GITIN-2053) (`loyalty/events/20260915_mobileappservice_loadtest_errors/`), which found two relevant, still-open issues with `SFCG-MOBI-LB`'s current health probe:

- The probe (`SFCG-MOBI-LB-probe02`) is plain **TCP**, port 8043 only, `numberOfProbes=1` — it verifies the port is listening, nothing about application health (thread pool, request queue, DB connectivity). Originally flagged as tech debt in GITIN-1909 (2026-08-21).
- During the 2026-09-15 campaign traffic peak, `SFCG-MOBI-01` received only 1.4% of total traffic vs. `SFCG-MOBI-02`'s 98.6%, while `DipAvailability` stayed at ~100% throughout — i.e. the TCP probe had no way to detect or correct whatever was causing the imbalance. GITIN-2053 left this open (working theory: Azure LB 5-tuple hash + HTTP/2 connection multiplexing, not a health issue per se), but it underlines why a TCP-only probe is insufficient for the intended CPU/RAM-based balancing goal.

GITIN-1228's own ask (from Jira): replace the port-only TCP health check with a real HTTP health check reporting CPU/RAM, and move the LB rule to weighted balancing based on that.

## Current state

`healthcheck.ashx` (C# WebHandler, `.NET Framework`/IIS, matches MobileAppService's existing stack) drafted and saved to this folder. Reports `status` (`Healthy`/`Warning`/`Error`), `cpu`, `memory`, and now also `database` connectivity, via `HTTP 200`/`400`/`500` respectively.

**DB check design constraint (learned directly from GITIN-2053):** GITIN-2053 confirmed `PNSSRL_MantenimientoIndices` holds a `Sch-M` lock on `Sml.CustomerPointsLog` for 45+ minutes daily (`06:15`–`~07:31` UTC, recurring — see GITIN-1981). If the health check's DB probe queried a real business table, it would hang for the same duration during that daily window, on both VMs simultaneously — turning routine DB maintenance into a full MobileAppService outage via the health check itself. Mitigated by: a hard 2-second connect/command timeout, and a `SELECT 1` probe that touches no table (can't be blocked by any table-level lock).

**Connection string name used:** `SmartFran.Solution.SmartLoyalty.Data.Context.SmartLoyaltyContext` — inferred from the platform-wide template (`Default-Template/ConnectionStrings-Template.config`) and cross-checked against GITIN-2053's confirmed evidence that MobileAppService's real queries hit this exact database. **Not yet confirmed against the real, deployed `Config\ConnectionStrings.config` on `SFCG-MOBI-01`/`-02`** — that file isn't present in the local read-only source clone (only checked-in templates exist for other services; real per-environment config isn't in source control). Needs verification before deploy.

**Threshold configuration — resolved (2026-09-16): `ConfigurationManager.AppSettings` via `Config\AppSettings.config`**, matching the existing pattern used everywhere else in this app (`CustomerMinAge`, `PendingCustomerDataVigency`, cache TTLs, etc.), not environment variables. Confirmed access: SRE has full filesystem access to both VMs' deployment folders — neither the `AppSettings.config` key addition nor the `.ashx` file drop requires dev involvement (both are runtime-read file-system changes, not compiled code).

**Unrelated finding, flagged not acted on:** while checking `AppSettings-Template.config` for the app's existing config pattern, found what appears to be a real plaintext credential (`SmtpPassword`) checked into the source clone — out of scope for this ticket, not investigated further here.

## Deployment confirmed (user, 2026-09-16)

`healthcheck.ashx` deployed and responding on `SFCG-MOBI-02`: `{"status":"Healthy","cpu":19.91,"memory":52.36,"database":"Healthy"}`. **Not yet confirmed on `SFCG-MOBI-01`.** This confirms the connection string name guess (`SmartFran.Solution.SmartLoyalty.Data.Context.SmartLoyaltyContext`) was correct — `database:"Healthy"` means `CheckDatabase()` actually opened a real connection and ran `SELECT 1` successfully. AppSettings thresholds (`HealthCheck_CpuThreshold`/`HealthCheck_MemThreshold`) also confirmed working via the corrected XML comment (two rounds of malformed `<!-- -->` syntax caught before deploy — unterminated comment, then a `--` inside the comment body — both would have broken `Config\AppSettings.config` parsing and taken the whole app down, not just this handler).

## Controlled single-VM test surfaces a real self-removal edge case (user, 2026-09-16)

**`SFCG-MOBI-01`'s "Admin State set to Down" was deliberate**, not an incident — set intentionally beforehand to isolate the probe cutover test to `SFCG-MOBI-02` alone. Confirmed via Activity Log: a `backendAddressPools/write` by `dantep@smartfran.com` at `14:50:26–27Z`, 13 seconds before the probe rule swap (`14:50:39Z`) — consistent with a manual pre-test setup step, not an accident or unrelated fault.

With `-01` deliberately isolated, the probe swap (`SFCG-MOBI-LB-probe02` TCP → `healthcheck.ashx` HTTPS) then surfaced a real, previously-unknown edge case: **`-02` alone, carrying full production traffic, failed the new HTTP probe with a non-200 status.** Working theory: full load on a single VM pushed CPU/RAM over the handler's 80% threshold, so the handler correctly returned `400` ("Warning") — which Azure's HTTP probe treats as unhealthy (confirmed via Microsoft docs: only exactly `200` counts as healthy, `400`/`500` both fail it). Since `-01` was already isolated, this took the *entire* pool down (both `Down`, pool at 0% healthy, no new connections routed) — a real finding about the new probe's behavior under reduced capacity, surfaced safely by the test design rather than discovered in an uncontrolled way.

**Mitigation applied:** reverted the LB rule's probe back to `SFCG-MOBI-LB-probe02` (TCP). Confirmed `-02` back to `Up` immediately after (TCP-open is a much lower bar than the HTTP/CPU-threshold check). `-01`'s Admin State has since been set back to `Up` — full two-VM redundancy restored, test concluded.

**Real finding for the ticket, not a test artifact:** the HTTP/CPU-threshold probe is a legitimate improvement over TCP-only, but a single VM under full production load can cross its own CPU/RAM threshold and remove itself — which is only safe/acceptable behavior if the other VM is still there to absorb the traffic. Don't cut over the LB rule with only one VM in rotation; the two-VM cutover needs both healthy and serving normal (not consolidated) load first.

## Probe port/protocol changed: HTTP:8080, not HTTPS:8043 (user, 2026-09-16)

Manual testing on `-02` traced a request-send failure on `https://<private-ip>:8043/healthcheck.ashx` through several layers: TCP connect succeeds, raw TLS handshake succeeds (confirmed via a manual `SslStream` test), but `Invoke-RestMethod`/`curl` requests against the bare private IP failed or came back empty — consistent with IIS/HTTP.sys rejecting the request because its `Host` header (the literal IP) doesn't match the site's hostname-specific binding (`mobileservice.clubgrido.com.ar`). This matters beyond just manual testing: **Azure LB's HTTP/HTTPS probes always connect via the backend's private IP and cannot send a hostname-matched `Host` header** (documented limitation, confirmed via Microsoft Learn) — so this same rejection would likely affect the real LB probe too, not just manual `curl`/PowerShell tests.

**Confirmed (not just theorized) via `Get-WebBinding` on `-02` (2026-09-16):**
```
protocol http, bindingInformation *:8080:, certificateHash (none), sslFlags 0
protocol https, bindingInformation *:8043:mobileservice.clubgrido.com.ar, certificateHash 73C2B039A82297F091D6F3A2367B8C56F0A1B902, sslFlags 0
```
The `8043` HTTPS binding is hostname-scoped in the binding itself (`mobileservice.clubgrido.com.ar`), not wildcard — `sslFlags:0` means SNI isn't required for *certificate selection* (one cert regardless, consistent with the TLS handshake succeeding), but IIS/HTTP.sys still routes the actual HTTP request by matching `Host` against this binding's hostname at the application layer, independent of SNI. Since a bare-IP request (from Azure's probe or manual testing) can only send the IP as `Host`, it can never match this binding — root cause confirmed. The `8080` HTTP binding is genuinely wildcard (blank hostname portion) and accepts any `Host` header, which is why it worked.

**Resolved by using a different port instead:** `http://<private-ip>:8080/healthcheck.ashx` (plain HTTP, not HTTPS) works cleanly — `{"status":"Healthy","cpu":64.06,"memory":51.76,"database":"Healthy"}`, confirmed via the real private IP (not `localhost`, so reachable the same way Azure's probe would reach it). Plan changed: **the new LB probe should target HTTP on port `8080`, not HTTPS on port `8043`** — avoids the hostname-binding problem entirely, and Azure LB explicitly supports probing a port different from the load-balanced application port.

**Not yet confirmed:** whether the NSG governing `SFCG-MOBI-01`/`-02` allows the `AzureLoadBalancer` service tag on port `8080` — the existing TCP probe already works on `8043`, but if that NSG rule is port-scoped rather than blanket, `8080` may not be covered yet and would need its own rule before the probe would actually succeed.

## `-01` deployment gap confirmed and closed (user, 2026-09-16)

`SFCG-MOBI-01` initially had **no `healthcheck.ashx` or `AppSettings.config` keys deployed at all** — only `-02` had the full setup. This was a second, independent reason `-01` would have failed the new HTTP probe during the earlier test, on top of the deliberate Admin State override.

**Gap now closed:** `-01`'s IIS bindings already matched `-02` exactly (`http *:8080:` wildcard + `https *:8043:mobileservice.clubgrido.com.ar`, confirmed via `Get-WebBinding` — no binding work needed). `healthcheck.ashx` deployed and `AppSettings.config` keys added (same corrected comment syntax as `-02`). Confirmed via `http://192.168.50.111:8080/healthcheck.ashx`: `{"status":"Healthy","cpu":1.97,"memory":38.35,"database":"Healthy"}`.

**Both VMs now independently confirmed healthy on port `8080`** — this is the actual precondition for a safe LB cutover, unlike the earlier premature attempt.

## Probe cutover succeeded (user, 2026-09-16)

`SFCG-MOBI-LB-lbrule02` switched to the repurposed `healthcheck.ashx` probe (HTTP, port `8080`, path `/healthcheck.ashx`, interval 5s) with both VMs already confirmed healthy beforehand. Result: **both `-01` and `-02` `Up`, "responding to health probe successfully."** Pool at 100% healthy under the new application-aware probe — this replaces the old TCP-only check that couldn't detect app-level health (the original GITIN-1909/GITIN-2053 gap this ticket exists to close).

**`probeThreshold` bumped to `2`** (confirmed via `az network lb probe show`). **Important correction (Microsoft docs, confirmed 2026-09-16): this does NOT protect against the earlier self-removal scenario.** Per Microsoft: "For HTTP probes, explicit responses will immediately mark the probe as up or down for 200 and non-200 responses, and will effectively reset the threshold. This means that the threshold value only applies to HTTP probes if the probe times out due to no response." Our handler returns an *explicit* `400` when CPU/RAM crosses `80%` — not a timeout — so `probeThreshold` has no effect on that case; it only helps for transient timeouts (network blip, app hang with no response at all). **The self-removal-under-load fix still needs separate handling** — either raising the handler's CPU/RAM threshold, or adding hysteresis (e.g. require N consecutive internal high readings before reporting unhealthy) — not yet decided or implemented.

## Request queue metric added (2026-09-16)

Added `requestsQueued` to the response, via the `ASP.NET\Requests Queued` performance counter — same pattern as the existing CPU/RAM counters. **Informational only for now — does not affect `httpStatus`/pass-fail**, deliberately: adding a third way to trip `non-200` before the self-removal/hysteresis fix (still open, see above) would only make that problem worse, not better. Once the threshold/hysteresis design is resolved, revisit whether queue depth should also gate health status.

**Caveat, same as the existing CPU counter:** `ASP.NET\Requests Queued` is machine-wide, not scoped to MobileAppService's specific app pool — fine given this VM appears dedicated to this one app, but worth knowing if that ever changes.

## CRITICAL: `healthcheck.ashx` is not in source control — at risk of deletion on next deploy (2026-09-17)

`healthcheck.ashx` was manually placed on `SFCG-MOBI-01`/`-02`'s filesystem (`D:\SmartLoyalty.MobileAppService\`) — it was never added to the actual `MobileAppService` project source (`loyalty/repo/dev-src-sol-smartloyalty/Front/MobileAppService/`) or committed to that repo. **`.ashx` WebHandlers don't need compilation — ASP.NET compiles them on first request — but they still need to physically exist in the deployed folder.** A standard deploy/publish cycle for this app would very likely overwrite or clean the deployment directory to match the build output, which doesn't include this file — **silently deleting the health check on both VMs simultaneously on the next release**, breaking the LB probe for the entire pool at once (worse than the original TCP-only probe, since a missing file means an immediate `404`/non-200 on both sides).

**Action needed, not yet done:** add `healthcheck.ashx` to the actual `MobileAppService` project source and have it committed/deployed through the normal pipeline, so it survives future releases automatically instead of depending on this being remembered. Flag this to whoever owns deploys for this app before the next release goes out.

## Not yet done

- **Self-removal-under-load fix:** a single VM under full production load can cross its own 80% CPU/RAM threshold and report unhealthy, which is only safe if the other VM is available to absorb traffic. Needs either a higher/tuned threshold, or hysteresis (N consecutive high readings before reporting unhealthy) — not decided.
- **CPU/RAM-weighted balancing** (Jira's stated broader goal): Azure Standard LB's native probe only supports healthy/unhealthy pass-fail, not weighted-by-metric distribution. Needs research into whether this requires Azure Traffic Manager, Application Gateway, or a custom weighting mechanism instead of `SFCG-MOBI-LB` as-is — not yet started.
- Unrelated, flagged not acted on: apparent plaintext `SmtpPassword` credential found in `AppSettings-Template.config` in the source clone — separate from this ticket's scope.

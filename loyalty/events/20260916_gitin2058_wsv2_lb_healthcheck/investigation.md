# Investigation — 20260916_gitin2058_wsv2_lb_healthcheck

**Status:** health check implemented, deployed to both VMs, and cut over to the LB — probe fix is done. Two items remain open: `-01`'s Admin State override (masks the real probe result), and `-02`'s ephemeral-disk deployment survivability across its nightly power cycle (not conclusively tested either way).
**Jira ticket:** [GITIN-2058](https://smartit-ar.atlassian.net/browse/GITIN-2058)

## Origin

Same pattern as [GITIN-1228](https://smartit-ar.atlassian.net/browse/GITIN-1228) (`loyalty/events/20260916_gitin1228_lb_healthcheck/`) — replace a probe that can't detect application-level health with a real HTTP health check reporting CPU/RAM/DB connectivity. Target here: **WebServiceV2** (`SFCG-WSV2-01`/`SFCG-WSV2-02`, `D:\SmartLoyalty.WebServiceV2\`), serving **SmartCloud** — a different platform from MobileAppService, not to be confused despite the shared codebase family.

**Known differences from the MobileAppService case, per `loyalty/docs/infrastructure.md` — don't assume the same fixes apply blindly:**
- Behind `SFCG-WSV2-LB` (Standard LB, backend pool `SFCG-WSV2-LB-backendpool01`), `Default` 5-tuple hash, no session affinity. Probe config not yet checked — do that first, don't assume it's TCP-only like `SFCG-MOBI-LB` was.
- App port is **8080** (from `GITIN-1238`'s NSG rule `WebService_V2_PRO`), not `8043` like MobileAppService.
- **`-02` is not run 24/7** — powered off nightly `00:00–09:00 UTC-3` (Zabbix Maintenance period `maintenanceid 2` suppresses alarms during that window). Any health-check work needs to account for this VM being legitimately absent for ~9h/day, not treat it as an outage.
- **`-02`'s `D:\` is Azure ephemeral temp storage** (`D2ds_v4` SKU), unlike `-01`'s persistent disk (`D8as_v5`). Any deallocate/host-migration/reimage of `-02` wipes `D:\`, **including whatever gets deployed there** — a real risk specific to this VM that didn't exist for MobileAppService. Deploying `healthcheck.ashx`/`AppSettings.config` changes to `-02` may not survive a deallocate cycle; needs confirming before treating `-02`'s deployment as durable.
- Same source-config pattern confirmed via the local read-only clone (`Front/WebServiceV2/Web.config` → `Config\ConnectionStrings.config`/`Config\AppSettings-Template.config`, same externalized-config convention, same `.NET Framework 4.7.2` target) — the `healthcheck.ashx` handler built for GITIN-1228 should be directly reusable, pending confirmation of the actual connection string name on this app (not yet checked — don't assume it's the same `SmartLoyaltyContext` name without verifying, since this app serves a different platform).
- GITIN-1238 (2026-08-27, resolved) already found a related-but-different LB issue here: an NSG rule missing `-02`'s IP caused **zero real traffic** to reach it while Azure's health probe still reported it healthy (NSG evaluation is bypassed for the LB's own probes) — a different failure mode than anything found in GITIN-1228, but same underlying lesson: this LB's current probe can't be trusted to reflect real reachability. Full detail: `events/20260826_wsv2lb_vm2_trustedlaunch_no_traffic/`.

## Handler deployed, same hostname-binding trap found and worked around (user, 2026-09-16)

User independently wrote and deployed a `healthcheck.ashx` for WebServiceV2 (DB + Redis TCP connectivity checks, not CPU/RAM/queue like MobileAppService's version). **Code review found a critical bug**: `int statusCode = status == "Unhealthy" ? 200 : 200;` — both ternary branches return `200`, so the handler can never signal unhealthy to the LB regardless of actual DB/Redis state. Also flagged: fragile fuzzy connection-string lookup (`cs.Name.Contains("SmartFran") || cs.Name.Contains("Context")` could match the wrong context, given the platform template has several similarly-named connection strings) and fragile Redis-config discovery via AppSettings key substring matching. **Not yet fixed** — flagged, not yet corrected in the deployed file.

**Confirmed via `Get-WebBinding` on `SFCG-WSV2-01`:**
```
protocol https, bindingInformation *:8080:webservicev2.smartfran.com, sslFlags 0
protocol http, bindingInformation 192.168.50.171:80:, sslFlags 0
```
Same trap as MobileAppService: `8080` HTTPS is hostname-scoped, would reject a bare-IP LB probe request. **`80` HTTP is bound directly to this VM's own private IP with no hostname restriction** — the port to target for the new LB probe, same reasoning as MobileAppService's `8080` fix. Confirmed working via both `https://webservicev2.smartfran.com:8080/healthcheck.ashx` (real hostname) and `http://192.168.50.171/healthcheck.ashx` (bare IP, port 80) — both return `200`/healthy JSON (though per the statusCode bug above, `200` doesn't actually mean anything yet).

## Redis fallback confirmed via source, handler rewritten (2026-09-16)

**Confirmed directly in `Core/Application/Service/SaleProviderContext/RedisCacheService.cs`:** `GetOrSetCache` genuinely falls through to the real data source (DB) when `IsRedisAvailable()` is false, logging `"Redis no está disponible, usando sólo la fuente de datos."` — not a hard failure. This validates the design decision: **Redis failure is reported but does not remove the backend from LB rotation; only DB failure and CPU/RAM-over-threshold do.** Worth flagging even though it doesn't gate health status: when Redis is down, load shifts directly to the DB — elevated DB capacity risk, directly relevant given GITIN-2053's findings. Reported in the JSON for visibility, not tied to `httpStatus`.

Same source file also gave the **real AppSettings key names**, replacing the fragile substring-scan: `RedisConnection` and `TimeoutRedis` (used directly by `RedisCacheService`'s static constructor).

**Handler rewritten** (`healthcheck.ashx` in this folder, replacing the earlier draft): CPU/RAM/queue pattern reused directly from MOBI's handler (GITIN-1228), DB check uses a direct connection-string lookup (no fuzzy `Contains()` matching), Redis check uses a direct `AppSettings["RedisConnection"]` lookup (no key-scanning). `statusCode` now actually varies: `500` if DB fails, `400` if CPU/RAM over threshold, `200` otherwise (Redis failure alone stays `200`, consistent with the confirmed fallback behavior).

**Deployed and confirmed on both VMs:**
- `SFCG-WSV2-01` via `http://192.168.50.171/healthcheck.ashx` (bare IP, port 80) and `https://webservicev2.smartfran.com:8080/healthcheck.ashx` (real hostname).
- `SFCG-WSV2-02` via `http://192.168.50.172/healthcheck.ashx` (bare IP, port 80) and the same hostname URL — confirmed running (not in its nightly-off window at test time), DB and Redis both healthy.

Both VMs independently confirmed — this is the precondition for a safe LB cutover (same lesson as GITIN-1228's premature-cutover incident: don't touch the probe until both backends are confirmed healthy first).

## `SFCG-WSV2-LB` probe inventory checked (2026-09-16)

Full detail: `data/sfcg-wsv2-lb_probes_current.json`. Three probes exist:
- `sfcg-sondeo02` — TCP, port 8080, `probeThreshold=1` — **currently attached to the live rule `SFCG-WSV2-LB-lbrule01`.** Same TCP-only limitation as MobileAppService's original setup.
- `SFCG-WSV2-LB-probe01` — TCP, port 8080, `numberOfProbes=2` — orphaned, not attached to any rule.
- **`healthcheck` — HTTP, port `80`, path `/healthcheck.ashx`, `probeThreshold=1` — already exists, not attached to any rule, and already matches exactly what's needed.** No probe creation/update required — just attach it to the live rule.

With both VMs already independently confirmed healthy, ready to cut over.

## Probe cutover applied (2026-09-16)

`SFCG-WSV2-LB-lbrule01` confirmed switched to the `healthcheck` probe (HTTP, port 80, `/healthcheck.ashx`) via `az network lb rule update`. Both VMs confirmed `Up` in the Backend health blade — cutover successful.

**Note:** `-01`'s status message is `"healthy due to Admin State set to Up"` (a manual override, not purely probe-driven), while `-02`'s is the normal `"responding to health probe successfully"`. Not a current problem, but `-01`'s displayed health doesn't actually reflect the real probe result while this override is set — if `-01` ever failed the check for real, the override would mask it. Not yet decided whether to clear it.

**`probeThreshold` confirmed still `1`** (via `az network lb probe show`), not bumped. Same caveat as GITIN-1228: only helps against probe timeouts, not explicit non-200 responses from the handler itself.

## Operations email sent (2026-09-17)

Combined email covering both this ticket and GITIN-1228 (same pattern, same rollout timing) — saved under `loyalty/events/20260916_gitin1228_lb_healthcheck/email_ops.md`, not duplicated here. Includes rollback `az` commands for both LBs' probes.

## CRITICAL: `healthcheck.ashx` is not in source control — at risk of deletion on next deploy (2026-09-17)

Same risk as `GITIN-1228`: `healthcheck.ashx` was manually placed on `SFCG-WSV2-01`/`-02`'s filesystem, never added to the actual `WebServiceV2` project source or committed to that repo. `.ashx` handlers don't need compilation (ASP.NET compiles on first request), but the file still has to physically exist in the deployed folder — a standard deploy/publish would very likely wipe it, breaking both VMs' LB probes at once. **Action needed, not yet done:** add it to the real project source, deploy through the normal pipeline. Flag to whoever owns `WebServiceV2` deploys before the next release.

## Not yet done

- **Decide whether to clear `-01`'s Admin State override** (currently `Up`, masking its real probe result — see confirmed Microsoft docs behavior above).
- **`probeThreshold`** still `1`, not bumped to `2` (same optional tuning as GITIN-1228, same caveat: only helps timeouts, not explicit non-200 responses).
- **`-02`'s ephemeral-disk deployment survivability** not conclusively tested across an actual nightly power cycle — today's successful test doesn't by itself prove the deployment survives a real deallocate; worth confirming after the next overnight cycle rather than assuming either way.
- NSG port `80` coverage is implicitly confirmed by the successful cutover (`-02` shows a real probe-driven `Up`, not an override) — not separately verified via the NSG rule itself, but the working result is sufficient evidence.

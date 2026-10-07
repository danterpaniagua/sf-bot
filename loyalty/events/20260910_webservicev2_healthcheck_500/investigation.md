# Investigation: WebServiceV2 Zabbix Healthcheck — HTTP 500 for 8+ days

Jira: https://smartit-ar.atlassian.net/browse/GITIN-2025

## Alert

- Trigger: `WebServiceV2. HTTP Code not 200` (host `sfcg-monitoreo` proxy-polled)
- Item: `web.test.rspcode["[PROD] WebServiceV2",Healthcheck]`
- Problem expression: `avg(...,20m)>220` — Recovery: `avg(...,20m)=200`
- Actual value reported: response code **500**, consistently
- Severity: High, Event generation Normal
- Started: 2026-09-02 09:13:25 (UTC-3, user's local tz) — still active as of 2026-09-10, **not acknowledged**, no automated action steps have fired (Actions table empty)

## Why unacknowledged for 8 days is itself worth flagging

Per `docs/zabbix_observability.md`, the only alert-routing action that reliably pages anyone is action id 3 (`Report problems to Zabbix administrators`, zero conditions, `esc_period: 1h`). Need to confirm whether this trigger actually has that unfiltered action attached / whether notifications were sent and ignored, or whether this trigger's tags only match a disabled/non-matching action — would explain silent persistence independent of the underlying HTTP 500 cause.

## Prior related investigation (read first)

`loyalty/events/20260826_wsv2lb_vm2_trustedlaunch_no_traffic/investigation.md` (`GITIN-1238`) is directly relevant:

- `SFCG-WSV2-01` (VM1) and `SFCG-WSV2-02` (VM2) were confirmed running **different code/deployment versions**. VM1 does not have the `/healthcheck.ashx` handler properly registered — MVC routing catches the request and rejects "healthcheck.ashx" as an invalid controller name, producing an ASP.NET unhandled exception (Event 1309) and **HTTP 500**. VM2 has the handler and returns a proper `{"status":"Healthy",...}` JSON payload (HTTP 200).
- VM1's behavior on this path was observed as **intermittent** during that investigation (2026-08-27) — sometimes 500, sometimes 200 for the same path — not fully explained.
- That investigation also recorded (2026-08-27): "**Not pursued, parked by user mid-discussion:** a new Zabbix Web scenario validating `https://webservicev2.smartfran.com:8080/healthcheck.ashx` responses (200-only success condition)... user said 'nevermind' before deciding" whether to attach it to `SFCG-WSV2-01` or a new dedicated host.
- Separately, a *load-balancer probe* switch to `/healthcheck.ashx` (HTTPS) was attempted and **rolled back** same session after VM2's LB probe degraded ~6 minutes. Parked; not retried. This is a different object (LB health probe) from the Zabbix web scenario item currently alerting — don't conflate the two.

**Working hypothesis (not yet confirmed):** the Zabbix web scenario `[PROD] WebServiceV2` / step `Healthcheck` was created at some point after 2026-08-27 (contradicting the "parked" note, or created independently) and targets `/healthcheck.ashx`. If it's landing on VM1 (or VM1's known-broken behavor became permanent rather than intermittent), that would fully explain a *consistent* 500 for 8 days. Needs confirmation — not to be assumed.

## Open questions / next diagnostic steps

1. What does the Zabbix web scenario actually check? Need `httptest.get` (scenario + step: URL, host header, which Zabbix host it's attached to, whether via LB public IP or a specific VM).
2. Is VM1's `/healthcheck.ashx` handler still missing/broken as of now (2026-09-10), or did a deployment since 2026-08-27 change this?
3. Does the scenario hit the LB (`SFCG-WSV2-LB` public IP `52.186.168.27`, Host header `webservicev2.smartfran.com`) or a single VM directly? If via LB, a single fixed source (the Zabbix proxy `sfcg-monitoreo`, `172.191.99.60`) would 5-tuple-hash to the *same* backend every time — explaining "consistent" rather than "intermittent" failure, if it always lands on VM1.
4. Cross-check IIS Application event logs on VM1 (and VM2) for Event 1309 occurrences since 2026-09-02 09:13 — confirms which VM is actually being hit and since when.
5. Confirm whether this trigger's tags route to an actually-enabled Zabbix action (see "unacknowledged" question above).

## Confirmed (2026-09-10) — scenario definition and trigger tags

`httptest.get` (`data/httptest_prod_webservicev2.json`): scenario `[PROD] WebServiceV2` (httptestid 17) is attached to host `sfcg-monitoreo` (the Zabbix proxy itself, hostid 10610) — i.e. it's a web-scenario check executed by/through the proxy, not a native item on `SFCG-WSV2-01`/`-02`. Single step `Healthcheck`: `GET https://webservicev2.smartfran.com:8080/healthcheck.ashx`, no explicit `Host` header override, `follow_redirects=1`, required `status_codes=200`, `retries=1`. Resolves via the public hostname — same path class as the LB-mediated tests in `20260826_wsv2lb_vm2_trustedlaunch_no_traffic` (goes through `SFCG-WSV2-LB`, not a direct VM hit).

`trigger.get` (`data/trigger_webservicev2_httpcode.json`): trigger `WebServiceV2. HTTP Code not 200` (triggerid 26861) uses macros `{$IIS_CODE_THRESS_NOK}` / `{$IIS_CODE_THRESS_OK}` (a macro family not previously documented in `docs/zabbix_observability.md` — different from the `PERF_COUNT_TRIG_*` request-rate family). **Trigger has `"tags":[]` — zero tags.** Per `docs/zabbix_observability.md`'s alert-routing audit, no tag-based action (Google Chat/email) can ever match a tagless trigger — the only action that could have paged anyone here is action id 3 (`Report problems to Zabbix administrators`, zero conditions, matches everything). Whether that action's media type actually delivered anything for this trigger over the past 8 days is still open — separate question from the HTTP-500 root cause itself, but explains why silence here doesn't require anything to be "broken" in a tag sense.

## Next: identify which backend VM is being hit, and whether the known VM1 bug still applies

Still needed:
- Azure LB `DipAvailability` split by `BackendIPAddress` (command 3, not yet run) — if one VM has been failing its own probe for the whole window, that alone could explain a consistent (not intermittent) hit on the other/bad VM.
- IIS Application event log (`Event 1309`, ASP.NET unhandled exception) on both `SFCG-WSV2-01` and `SFCG-WSV2-02` since 2026-09-02 09:00 UTC-3 — confirms which VM(s) are actually throwing on `/healthcheck.ashx` and since when.
- Direct local check on each VM (bypassing LB, i.e. run from the VM's own RDP session against `localhost` or its own private IP with the `webservicev2.smartfran.com` Host header) to see current `/healthcheck.ashx` behavior — the prior investigation's finding (VM1 missing the handler) is 2 weeks old and could have changed with any deployment since.

## CORRECTION (2026-09-10, user-confirmed) — actual root cause is a 2026-09-01 deploy regression, not the old VM1-only bug

User confirmed directly: `healthcheck.ashx` was **deleted on the 2026-09-01 deploy, on both `SFCG-WSV2-01` and `SFCG-WSV2-02`** — not the pre-existing VM1-only handler gap from `GITIN-1238`. This lines up with the alert start (2026-09-02 09:13, ~hours after a 09-01 deploy) far better than "VM1's long-standing bug happened to become permanent." The IIS Event 1309 evidence gathered below (`SFCG-WSV2-01` only) is still consistent with this — same symptom/exception, different actual cause (file absent on this deploy, not "never deployed" as originally found in August) — but was gathered before this correction and does not by itself distinguish the two. **File has been restored on both VMs by the user.**

This changes the previously-recorded "still open" question below (VM1-only vs. both regressed) — answer is: both were affected, both now restored. Kept the original VM1-only findings below for the record since they were real (independently gathered evidence, not wrong), just superseded as the full explanation.

## Original findings (partial explanation, superseded by correction above) — VM1's known missing healthcheck.ashx handler

`Get-WinEvent` on `SFCG-WSV2-01` (`data/event1309_SFCG-WSV2-01.txt`), Application log, Event 1309, since 2026-09-02: multiple unhandled-exception entries (sampled 2026-09-04 12:09–12:14, ~2-3min apart), every one:

- `Exception message: Controlador healthcheck.ashx no válido.`
- Thrown from `SmartFran.Solution.SmartLoyalty.Extend.Dependency.ControllerFactory.CreateController`
- `Request URL: https://webservicev2.smartfran.com:8080/healthcheck.ashx`
- `User host address: 172.191.99.60` — this is the Zabbix proxy `sfcg-monitoreo`'s own IP (confirmed in `docs/zabbix_observability.md`), i.e. these are literally the Zabbix scenario's own polls, landing on VM1 and getting rejected.

This is the **same bug identified in `20260826_wsv2lb_vm2_trustedlaunch_no_traffic`** (`GITIN-1238`): VM1 does not have the `/healthcheck.ashx` handler registered in its deployed build (Jenkins path `dev-src-proj-webservicev2`), so ASP.NET MVC routing rejects it as an invalid controller name → HTTP 500. That prior investigation observed this as *intermittent* on VM1 (sometimes 500, sometimes a real 200) — worth re-checking whether it's now consistently landing on VM1 (e.g. VM2 unhealthy/out of rotation) or whether VM1's failure rate itself increased.

**Root cause of the Zabbix alert is confirmed at this level**: the web scenario requires `status_codes=200` and VM1 cannot ever satisfy that for this specific path — whenever the LB routes this scenario's request to VM1, it fails.

## Remediation (2026-09-10) — actioned by user

`healthcheck.ashx` restored on both `SFCG-WSV2-01` and `SFCG-WSV2-02`, reversing the file deletion introduced by the 2026-09-01 deploy. Real fix belongs to the deploy/build pipeline going forward (whatever build step or deploy script dropped this file on 2026-09-01 should be checked so it doesn't regress again on the next release) — not pursued further in this investigation unless asked.

## Verification still needed

- Confirm the Zabbix scenario now returns HTTP 200 (next poll, 1-minute interval, or a manual `httptest.get`/frontend check).
- Confirm the trigger actually recovers (`avg(...,20m)=200` recovery expression needs a full 20-minute window of clean 200s before it auto-resolves) — don't assume "file restored" alone means the Zabbix problem view is clear yet; it can lag up to ~20 minutes and may need a manual close given `Allow manual close: Yes` if it doesn't auto-recover for any reason.

## Verification (2026-09-10)

- `trigger.get` post-fix (`data/trigger_status_post_fix.json`): still `"value":"1"` (problem), `lastchange` decodes to `2026-09-02 12:13:25 UTC` — unchanged from the original alert start, i.e. no state transition yet. Expected given the recovery expression needs a full clean 20-minute averaging window; not itself a sign the fix didn't work.
- Direct external curl against `https://webservicev2.smartfran.com:8080/healthcheck.ashx` (through the LB, real path): **HTTP 200**, confirming the restored file is being served correctly now.

## Additional confirmation — native Zabbix item data on both VMs (2026-09-10)

`item.get` filtered by `hostid` `10665`/`10678` (`data/latest_data_wsv2_01_02.json`, 340 items) — exact-match `filter: {"host": [...]}` with the technical names as displayed (`SFCG-WSV2-01`/`SFCG-WSV2-02`) worked; an earlier attempt using the top-level `host` param and a `host.get` substring `search` both returned empty for reasons not diagnosed further (not a real absence — hostids confirm the hosts exist and have current data).

Relevant items, both VMs current as of this pull:

| Item | VM1 | VM2 |
|---|---|---|
| AppPool `SmartLoyalty.WebServiceV2` state (`APP_POOL_WAS`) | `3` (Running) | `3` (Running) |
| AppPool recycle count | `0` | `0` |
| AppPool uptime | ~93921s (~26.1h) | ~174928s (~48.6h) |
| `{$IIS.PORT}` port ping (`net.tcp.service`) | `1` (up) | `1` (up) |
| W3SVC / WAS service state (`service.info`) | `0` (running) | `0` (running) |
| IIS Method Total requests/sec | ~0.77 | ~0.44 |

Both app pools `Running`, no recycles, both services up, both actively serving real request volume — no crash-loop or instability signature on either VM. Consistent with, and corroborating, the direct-curl 200 result and the user's confirmation that the file restore was applied to both machines.

## Status — CONVERGED, ready for ticket closure

Root cause confirmed: the 2026-09-01 deploy deleted `healthcheck.ashx` on both `SFCG-WSV2-01` and `SFCG-WSV2-02`. Fixed: file restored on both (user action). Verified: direct external curl through the LB returns HTTP 200; native Zabbix telemetry on both VMs shows healthy IIS/AppPool/service state with no instability. Zabbix trigger (`WebServiceV2. HTTP Code not 200`, GITIN-2025) still showed `value:1` at last check (unchanged `lastchange` from the original 2026-09-02 alert start) — expected to auto-recover once a full clean 20-minute window of 200s completes, or can be manually closed given `Allow manual close: Yes`. Nothing else outstanding technically; ready to write `ops.md`/`ops-events.md`.

# Investigation — 20260828_wscg01_zabbix_graylog_onboarding

Jira: https://smartit-ar.atlassian.net/browse/GITIN-1961

**Status:** closed (2026-09-05, user)

## Confirmed facts
- Target host: `SFCG-WSCG-01`, IP `192.168.50.181` — "CG web service" per `loyalty/docs/infrastructure.md` (line 28) and `operations/docs/itservices_rotacion_password_runbook.md`. Not yet documented in `infrastructure.md` beyond the one-line service label.
- Ticket scope: onboarding this host into both Zabbix and Graylog.
- Zabbix side (user, 2026-08-28): host is **already** in Zabbix — pivoting to reviewing its current metrics/items rather than doing the onboarding itself.

## Current working theory (updated 2026-09-05)
Zabbix onboarding is done (see `ops.md`, one optional item left open). Graylog side has two pathways:
- **IIS access logs** — confirmed flowing via NXLog (`iis.conf`), unredacted DNI-bearing query string included. Only remaining question: whether landing in the default "All Messages" stream is acceptable or a dedicated stream is required (not yet checked against another host).
- **App-level `.svclog`/CSV logs** — initially found empty/unwired (no `delimitedListener`), then the user decided (2026-09-04) this pathway is in scope for GITIN-1961. **Now confirmed LIVE (2026-09-05)**: trace-config change and `svclog.conf` both deployed, real data flowing and validated against a genuine `AccountRecovery` exception (extraction regex correct). One config bug found and fixed same-day: each logical error fans out into 3 physical CSV lines (exception-keyword-only, structured-data, and a blank footer line) — the blank one is now dropped; the other two ship uncorrelated. Not yet re-validated against fresh data post-fix.

Ticket is not closeable yet: post-fix re-validation of the app-level pathway pending, stream-routing decision (default vs. dedicated) still open, and item 54599/54600 root cause is an optional loose end.

## Confirmed: Graylog is receiving logs from SFCG-WSCG-01 (2026-09-04)

A real message pasted by the user (`wscg01-graylog-sample-message.json`) confirms IIS access logs from `SFCG-WSCG-01` are flowing into Graylog via **NXLog** (`SourceModuleType: im_file`, `SourceModuleName: iis_w3c_mobile`) — settles the open "NXLog vs. app-level" question from the acceptance criteria below: it's NXLog. Sample is a Load Balancer Agent health-check GET to `/swagger/ui/index`, `200 OK`, tagged `ServiceName: SF-WEBSCG`, `ServiceType: IIS`, `ServiceCardinality: 01`.

**Not yet resolved:** the message's `streams` field is `["000000000000000000000001"]` — Graylog's default "All Messages" stream, not a dedicated stream. Whether this onboarding's completion standard requires routing to a dedicated stream (matching how other hosts are set up) or whether "logs arrive at all" is sufficient hasn't been checked — no other host's stream routing has been pulled for comparison in this investigation yet.

## Confirmed: a second, separate logging pathway exists on this host (2026-09-04)

The `SmartLoyalty.WebServiceCG` application has its own `system.diagnostics` trace source configuration (`wscg01-webservicecg-tracesource-config.xml`), independent of the IIS access logs NXLog ships to Graylog above. A `SegmentedXmlTraceListener` writes application-level trace output to `E:\Logs\SmartLoyalty.WebServiceCG\SmartLoyalty.WebServiceCG.svclog` (XML, 10MB segments). **Confirmed by the user: that same directory also has a `csv` subfolder** — `E:\Logs\SmartLoyalty.WebServiceCG\csv\` — a second, CSV-format log output alongside the `.svclog` XML. Neither the `.svclog` XML output nor this `csv` folder's contents have been inspected yet (nothing pasted from either), and it's not yet confirmed whether this pathway feeds Graylog at all, or is a separate/legacy mechanism unrelated to this onboarding.

**Open question:** is the `csv` folder's content the intended source for this host's Graylog *application*-log onboarding (as opposed to the IIS access-log path already confirmed via NXLog), or is it out of scope for GITIN-1961 entirely?

## Comparison config from SFCG-MOBI-01 reveals a discrepancy (2026-09-04)

`mobi01-mobileappservice-tracesource-config.xml` — `SmartLoyalty.MobileAppService`'s trace config on `SFCG-MOBI-01` — explicitly registers **two** listeners under `<listeners>`: the `XmlListener` (`.svclog`) **and** a `delimitedListener` (`System.Diagnostics.DelimitedListTraceListener`, comma-delimited) writing to `D:\Log\SmartLoyalty.MobileAppService\csv\SmartLoyalty.MobileAppService.csv`. This is a real, active, explicitly-configured CSV output.

**By contrast, `SFCG-WSCG-01`'s config only registers `XmlListener`** — no `delimitedListener` entry — despite a `csv` folder also existing under `E:\Logs\SmartLoyalty.WebServiceCG\`. **Confirmed by the user (2026-09-04) that this is the current, verified configuration** — not an incomplete paste. This rules out "the config file was truncated" as the explanation. **Confirmed by the user: the `csv` folder is empty — no files at all.** Not stale/legacy output as hypothesized, just genuinely empty — consistent with the config's lack of a `delimitedListener` (nothing has ever written there, or it was cleared). **Conclusion: this pathway is a dead end for Graylog onboarding right now** — there's nothing to ship. The IIS access-log path via NXLog (confirmed flowing, see above) remains the only active, real log source for this host as of 2026-09-04.

## App-level .svclog analysis and NXLog config drafted (2026-09-04)

A real ~4.4MB `SmartLoyalty.WebServiceCG.svclog` sample (1002 events, 2025-05-14 to 2026-09-04) was analyzed directly — kept local-only, never committed (`*.svclog` added to the monorepo's root `.gitignore`, since this file contains real customer PII in some entries). Structural findings:

- **Not line-delimited by record**: 440 physical lines held 1002 `<E2ETraceEvent>` fragments, some lines hard-wrapped near 10,000 chars mid-record. A line-based log reader would not capture one event per record.
- **Two exception clusters**: connectivity/SMTP (`SmtpException`/`WebException`/`SocketException`/etc., 546/1002, **no PII**) and database-layer (`SqlException`/`EntityException`/`EntityCommandExecutionException`, largely the same underlying events at multiple exception layers, 456/1002). **438 of 451 `SqlException`-primary events carry a structured `<TraceSourceLogger><Data>...` block with real customer `Email` and `UidId` (DNI/CICPy)** — `ErrorId`/`UidType`/`Usuario` (always the `SFCREW` system account)/`Endpoint` in that same block are not PII.

**A draft NXLog config implementing this (multi-line collection, exception-cluster classification, PII field extraction/redaction) was written to the separate `sf-devops` repo**, not this one: `sf-devops/observability/nxlog/smartloyalty-webservicecg-svclog.conf` — **now known to be based on the wrong mechanism, see below.** Whether this app-level pathway is even in scope for GITIN-1961 (vs. just the IIS access-log path already confirmed) is still open — see next steps.

## Confirmed by code + live test: most AccountRecovery outcomes never log (2026-09-04)

Read `Front/WebServiceCG/Controllers/AccountController.cs:57-126` (`AccountRecovery` action) and `Core/Application/Service/CustomerContext/CustomerApplicationService.cs:1867-1940` (`ExecuteRecovery`). `Logg.Error` is called from exactly one place — the controller's generic `catch (Exception ex)` at line 107 — which builds the `ErrorId`/`Email`/`UidType`/`UidId`/`Usuario`/`Endpoint` dictionary matching the structure already confirmed in the two `.svclog` samples. Every other outcome returns directly with **no** `Logg.*` call anywhere in the call chain: `ModelState` invalid (400), invalid/temp-domain email (400), `EmailAlreadyAsociatedToAccountRecovery` (422, controller-level explicit catch), `CustomerNotFound` (404, `ExecuteRecovery` line 1871-1876), `EmailAlreadyUsedByAnotherCustomer` (409, `ExecuteRecovery` line 1878-1884), and the success path (200) — none of these throw, so nothing reaches the one logging call site. An `[Authorize]` failure (401) never reaches the action at all.

The logger wiring itself is confirmed correct — `Front/WebServiceCG/Infrastructure/GlobalBootstrap.cs:52` calls `LoggerFactory.Initialize(container.Resolve<ILoggerProvider>(), "SmartLoyalty.WebServiceCG")` at `Application_Start`, matching the trace source name in the config.

**Live-tested by the user (2026-09-04):** a forced wrong DNI/email combo returned `409 EmailAlreadyUsedByAnotherCustomer` (`{"Status":"error","Code":"EmailAlreadyUsedByAnotherCustomer",...}`) — no log produced, exactly as the code predicts. Confirms this is expected/by-design silence, not a logging or trace-config defect. Relevant to the app-level CSV onboarding work above: most real-world bad-input traffic on this endpoint will produce zero rows in the future CSV — only genuine unhandled exceptions (the Sql/Smtp/connectivity clusters already characterized) will ever appear there.

## Corrected: the real shipping mechanism is CSV, not raw .svclog XML (2026-09-04)

The user provided real, currently-deployed NXLog configs from both `SFCG-MOBI-01` and `SFCG-WSCG-01` (`sf-devops/observability/nxlog/reference-existing-configs/`, extracted from a zip). These correct the earlier draft's core assumption:

- `mobile/01/conf/nxlog.d/svclog.conf` reads the raw `.svclog` XML but its Graylog output is **commented out** — dead path, ships nowhere.
- `mobile/01/conf/nxlog.d/iis.conf` has a second input (`svclog_input`) reading the **CSV** output instead (`DelimitedListTraceListener`, not the XML listener) — its route to Graylog **is active**. This is the real, currently-shipping mechanism for app-level SmartLoyalty logs.
- `webservicecg/01` has no `svclog.conf` and no CSV input at all — confirms independently what this investigation already found: WSCG-01 has no active app-level log shipping, and its empty `csv` folder has no `delimitedListener` writing to it (unlike MOBI-01).

**Real path forward for WSCG-01** — user decided in-scope (2026-09-04), work started:
1. **Drafted**: `wscg01-webservicecg-tracesource-config.proposed.xml` (this event folder, mirrored at `sf-devops/observability/nxlog/webservicecg/01/tracesource-config.proposed.xml`) — adds a `delimitedListener` writing to `E:\Logs\SmartLoyalty.WebServiceCG\csv\SmartLoyalty.WebServiceCG.csv`, matching MOBI-01's config exactly (delimiter `,`, `maxTraceFileSizeKb=10240`). Not yet deployed to the host. Both copies uncommitted in `sf-devops` (user's own action to commit).
2. **Drafted**: `sf-devops/observability/nxlog/webservicecg/01/conf/nxlog.d/svclog.conf` — new file (per user request, kept separate from `iis.conf` unlike MOBI-01 which folds both inputs into one file), reads the future CSV, extracts `ErrorId`/`Email`/`UidType`/`UidId`/`Usuario`/`Endpoint` via regex against the `<TraceSourceLogger><Data>...` block, classifies `DatabaseException` (Sql/Entity*) vs `ConnectivityException` (Smtp/Web/Socket), tags `ServiceName: SF-WEBSCG`/`ServiceType: ServiceLogs`, routes to the existing `out_iis` UDP output (shared across `nxlog.d/*.conf` in the same instance). **Untested — no real CSV sample exists yet** since the delimitedListener isn't deployed; field order/escaping only confirmed against the raw `.svclog` XML, not an actual `DelimitedListTraceListener` output line. Must be validated against a real sample once step 1 is deployed. Full detail and two more findings from this same comparison (a `Password` field shipping from the mobile host, confirmed intentional for brute-force detection given the L2 FW's 1:1 NAT with Grido blinding IP-based detection; and IIS access logs on both hosts potentially double-exposing DNI via unredacted URL query strings) are in `sf-devops/observability/nxlog/README.md` — not duplicated here.

## CONFIRMED LIVE: app-level CSV pathway deployed and shipping to Graylog (2026-09-05)

The user deployed both drafted artifacts (trace-config `delimitedListener` addition + NXLog `svclog.conf`) to `SFCG-WSCG-01` — not stated explicitly, inferred from real Graylog messages now arriving from `SourceModuleName: svclog_input`. **The extraction regex works correctly**: a real `AccountRecovery` exception event was captured with `ErrorId`/`Email`/`UidType`/`UidId`/`Usuario`/`Endpoint` all populated exactly as drafted (`Usuario: SFCREW`, `Endpoint: AccountRecovery`, `UidType: DNI`, a real customer email and DNI — values deliberately not reproduced here, same PII discipline as the rest of this investigation).

**New finding — one logical `Logg.Error` call fans out into 3 physical CSV lines**, not the 1 assumed when drafting:
1. An exception-message line, matching only the `SqlException`/`SmtpException`/etc. keyword regex → ships with `Action: DatabaseException` (or `ConnectivityException`), no other fields.
2. A structured-data line, matching the `<TraceSourceLogger><Data>...` block → ships with `ErrorId`/`Email`/`UidType`/`UidId`/`Usuario`/`Endpoint`, no `Action`.
3. A blank line with **no signal at all** — just the base `ServiceName`/`ServiceType`/`EventTime` tags.

Root cause (partial): `TraceListener.TraceEvent` writes `WriteHeader()` → `WriteLine(message)` → `WriteFooter()`; with `TraceOutputOptions` unset (`None`) on the `delimitedListener`, `WriteFooter` still emits its own line via `WriteLine(string.Empty)` — that's line 3. Why the exception-keyword and structured-data content land on two *separate* lines instead of one (accounting for lines 1 and 2) isn't fully diagnosed — likely two separate internal `TraceSource.TraceEvent` calls inside the compiled `SmartFran.Seed.Logging` framework (not in this repo's source clone), one for the exception's `ToString()`, one for the data dictionary. Not pursued further — not blocking.

**Fix applied**: `svclog.conf` now drops blank/whitespace-only lines (`if $raw_event =~ /^\s*$/ drop();`), eliminating line 3 (pure noise) while leaving lines 1 and 2 as separate, uncorrelated Graylog messages (same `EventReceivedTime`/`source`, no shared id to join them downstream — a stream-processing concern, not an NXLog-input one).

**Practical implication reconfirmed**: this matches the earlier finding that most `AccountRecovery` outcomes (400/404/409/422/success) never reach `Logg.Error` at all — this live event was a genuine unhandled exception, not a routine bad-input case.

## Ruled out
(none yet)

## Zabbix onboarding acceptance criteria (user, 2026-08-28)

Baseline every VM must have, validated at severity Warning-or-above (not Info/Not classified):

- Disk latency alert
- Disk low space alert
- CPU alert
- RAM alert
- If IIS host:
  - Alert on `<IIS instance>: IIS Method POST requests per second`
  - Alert on `<IIS instance>: IIS Method GET requests per second`
  - IIS port running/reachable
  - Certificate expiration alert
- Host polled via the Zabbix Proxy (`sfcg-monitoreo`, DMZ subnet convention — see `ope-zabbix` skill)
- Triggers carry tags that map to an actually-**enabled** alert action (per `ope-zabbix` skill: tag-based routing to Google Chat/Email is currently disabled fleet-wide; only the untagged "Report problems to Zabbix administrators" catch-all is live) — a tag alone doesn't prove notification happens.

## Checklist validation (2026-08-28) — `SFCG-WSCG-01` (hostid `10676`)

Source: `wscg01-host.json`, `wscg01-triggers.json`, `wscg01-items.json`, `zabbix-actions.json` (pulled via API, saved in this event folder).

Host: enabled (`status: 0`), agent interface `192.168.50.181:10050`, macros `{$IIS.APP.NAME}=SmartLoyalty.WebServiceCG`, `{$IIS.APPPOOL.MATCHES}=SmartLoyalty.WebServiceCG`, `{$IIS.PORT}=443`.

| Checklist item | Status | Evidence |
|---|---|---|
| Zabbix Proxy | ✅ | `proxy_hostid: 10609` = `sfcg-monitoreo`, matches DMZ subnet convention |
| Disk latency alert | ✅ | Triggers 26494–26502, priority 2 (Warning), per-disk (C:/D:/E:) read/write response time + "Disk is overloaded" |
| Disk low space alert | ✅ | Two-tier per disk (C:/D:/E:): "low" priority 2 (Warning) + "critically low" priority 3 (Average) |
| CPU alert | ✅ | 4 triggers (interrupt/privileged/queue length/high utilization), priority 2 (Warning) |
| RAM alert | ✅ | "High memory utilization" priority 3 (Average); swap + page-table-entries triggers priority 2 (Warning) |
| IIS POST rate alert | ❌ | Item `54600` exists but `lastclock:0`/`lastvalue:0` — **never collected**, same failure class as GITIN-1956 (WSV2-02). Also its `name` field says `SmartLoyalty.WebServiceV2` — wrong host name, though its `key_` correctly resolves `{$IIS.APP.NAME}`→`WebServiceCG`. **No trigger references this item at all.** |
| IIS GET rate alert | ❌ | Item `54599` (`SmartLoyalty.WebServiceCG: IIS Method GET requests per second`) — name is correct but same `lastclock:0`/`lastvalue:0` never-collected state, and same total absence of any trigger on it |
| IIS port running | ✅ | Item `53781` collecting live (`lastvalue:1`); trigger `26453` "IIS: Port {$IIS.PORT} is down" priority 3 (Average), enabled |
| Certificate expiration alert | ✅ (corrected 2026-08-28) | Not host-level — SSL expiry monitoring for this fleet runs centrally on the **`Zabbix server`** host itself, one item per service: `get_ssl_enddate_webservicecg` (log-monitored active check, `log[/var/log/zabbix/ssl_bot-security.log,...]`, 15m interval, 4 triggers, tags `cloud:Azure`/`component:SSL Cert`/`env:PROD`). Confirmed present and enabled (user, frontend). Same pattern exists for `webservicev2`, `website`, `smartfran`, `mobileappservice`, `fs-api`, `clubsite_ar`, `clubsite_py` — this is the fleet-wide architecture, not a per-VM item, so absence on `SFCG-WSCG-01` itself was the expected/correct state, not a gap |
| Trigger tags → enabled action | ⚠️ | Fleet-wide gap, not host-specific (matches `ope-zabbix` skill's documented finding): triggers here carry `scope` tags (`availability`/`capacity`/`performance`/`notice`) but the only **enabled** trigger-based action is the untagged catch-all `Report problems to Zabbix administrators` (id 3, group 7). All 4 tag-routed Google Chat/Email actions (ids 7–10) are `status:"0"` (disabled) |

## Fixes applied (2026-08-28)

- **Item `54600` name corrected** via `item.update`: `SmartLoyalty.WebServiceV2: IIS Method POST requests per second` → `SmartLoyalty.WebServiceCG: IIS Method POST requests per second`. Confirmed by API response (`itemids: ["54600"]`). `key_` was already correct (macro-resolved), so no data/history affected — cosmetic only.
- **Missing IIS request-rate alert on `SFCG-WSCG-01`** — root gap turned out to be: the fleet's real alerting for this metric lives on the `_Total` "IIS: Method Total requests per second" item (`53770`, collecting fine), via a 3-tier trigger (Warning/Average/High) — not on the per-app `54599`/`54600` items, which are visibility-only fleet-wide (confirmed no trigger on their `SFCG-WSV2-01` equivalents either). `SFCG-WSCG-01` had zero triggers on `53770`.
- **Correction (2026-08-30, `GITIN-1966`):** at the time, a targeted global-macro search (`search: {"macro": "PERF_COUNT_TRIG"}`) returned empty, leading to the conclusion that `{$PERF_COUNT_TRIG_*}` was undefined everywhere and that `SFCG-WSV2-01`'s reference triggers (`26139`/`26140`/`26141`) were non-functional. That was **wrong** — a later unfiltered `usermacro.get` pull showed the base (no-context) macros ARE defined globally (`WARNING=9, AVERAGE=13, HIGH=15, OK=7, TIME_NOK=10m`), so `SFCG-WSV2-01`/`SFCG-WSV2-02` were functional all along. Cause of the discrepancy not fully diagnosed (state change between sessions vs. a bad search call) — see `loyalty/events/20260830_reqs_alerts_zabbix_audit/` for the full corrected fleet inventory. The `SFCG-WSCG-01` fix itself (creating the `WEBSCG01` context + trigger chain) remains correct and necessary regardless — that host genuinely had zero triggers on item `53770`, unrelated to this correction.
  - **Done (2026-08-28).** Global macros with context `:WEBSCG01` (`WARNING=15`, `AVERAGE=30`, `HIGH=50`, `OK<=10`, `TIME_NOK=5m` — user-specified, VM-capacity-based, not data-through-time) created via `usermacro.createglobal` (`globalmacroids: 100–104` — first attempt used the wrong method, `usermacro.create`, which is host-scoped and requires `hostid`; corrected). 3 tiered triggers created on item `53770` via `trigger.create`, dependencies chained: Warning `26862` → Average `26863` (depends on 26862) → High `26864` (depends on 26863). Files: `fix-macros.json`, `fix-trigger-{warning,average,high}.json`, driver `apply-fix-getpost-alert.sh`.
  - **Verified (2026-08-28):** `trigger.get` on all 3 confirms `state:0`, `error:""`, `value:0` (not firing) — evaluating cleanly against the now-resolved `WEBSCG01` macros.
  - `SFCG-WSV2-01`'s equivalent macro context (`:WEBSV201`) intentionally left undefined — out of scope per user instruction, flagged as a known pre-existing gap for a future ticket.
- **Not fixed (deprioritized, optional follow-up):** items `54599`/`54600` still never poll (`lastclock:0`), most likely the chronic `ZBX-22463` Zabbix Agent 2 bug (confirmed present on this host, recurring since 2026-07-20) hitting this specific instance-scoped rate counter on every attempt. Since neither item is alert-bearing, this is an observability-only gap, not blocking. Candidate mitigation: `Restart-Service "Zabbix Agent 2"` on `SFCG-WSCG-01` (documented, partial/temporary fix per GITIN-1956 precedent — the bug recurs).

## Open questions / next steps
- Root-cause why items 54599/54600 have never polled (candidate: same as GITIN-1956 — Windows "Web Service" perf counter set not started on this host — needs a `Get-Counter -ListSet "Web Service"` check on `SFCG-WSCG-01`) and why no trigger exists on either item.
- Tag→action routing gap is pre-existing/fleet-wide — flag but likely out of scope for this ticket unless the user wants it addressed here.
- ~~Graylog onboarding not yet started — needs log source/shipping method confirmed~~ — **superseded, see below.** IIS access-log shipping (NXLog) is confirmed live; the app-level `.svclog` question was chased in detail and is now a separate, better-understood body of work tracked in `sf-devops`, not blocking on a single "which method" question anymore.
- **Current real open items (2026-09-04):**
  1. Whether app-level log shipping for `SFCG-WSCG-01` (the CSV/`delimitedListener` mechanism, matching `SFCG-MOBI-01`'s pattern) is actually in scope for GITIN-1961, or a separate follow-up ticket — not decided.
  2. `sf-devops/observability/nxlog/` — a "start version" baseline of the real deployed configs was prepared for a base git commit; whether that commit has actually been made isn't tracked here (separate repo, user's own action).
  3. The `mobile-password-hashing-fix.conf` draft (SHA256 via `xm_perl`, for the intentional brute-force-detection `$Password` field) is untested against a real NXLog instance with a Perl runtime.
  4. ~~Whether the DNI-in-IIS-URL exposure is real~~ — **confirmed by config (2026-09-04)**: `iis.conf`'s `w3c_parser_mobile` ships the raw `cs-uri-query` field (containing the DNI) unredacted via `to_json()`, on top of the separately-extracted `$DniNumber` fields. Still open: whether this is acceptable as-is or needs redaction — a call for the user/security, not yet made.
  5. Whether Graylog stream routing needs fixing (IIS logs currently land in the default "All Messages" stream, not a dedicated one) is still unresolved — no comparison against another onboarded host's stream setup has been done.
  6. ~~Whether the app-level `.svclog`/CSV pathway is in scope for GITIN-1961~~ — **decided in-scope (user, 2026-09-04)**. Two artifacts drafted (trace config addition + NXLog `svclog.conf`), not yet deployed/validated — see "Real path forward" above.
  7. ~~Deployment steps not yet done~~ — **all done (confirmed live 2026-09-05)**: trace config deployed, `svclog.conf` deployed, real data flowing and validated. See "CONFIRMED LIVE" section above. Remaining: re-validate `svclog.conf`'s blank-line drop fix against fresh data (applied today, not yet re-observed live), and decide whether the two uncorrelated partial-signal lines (Action-only vs. data-only) are acceptable as-is.

## sf-devops config re-check + second .svclog sample re-confirm prior findings (2026-09-04)

Checked the deployed configs directly at `sf-devops/observability/nxlog/webservicecg/01/conf/`:
- `nxlog.conf` — generic base; its own IIS input/output block is commented out, dead. Real routing lives in `nxlog.d/`.
- `nxlog.d/iis.conf` — the active pathway (matches `wscg01-graylog-sample-message.json` exactly: `ServiceName: SF-WEBSCG`, `ServiceType: IIS`, `ServiceCardinality: 01`, `im_file` on `iis_w3c_mobile`). **Resolves open item #4**: `cs-uri-query` is parsed as its own CSV field by `w3c_parser_mobile` and the full record goes through `to_json()`, so the raw query string (containing the DNI) ships to Graylog unredacted, in addition to the separately-extracted `$DniNumber`/`$CountryCode`/`$DniType` fields via regex — the exposure is real, confirmed by config, not just suspected.
- **No `svclog.conf`, no CSV/delimitedListener input anywhere in this host's config** — independently re-confirms the app-level pathway is not wired up, consistent with the empty `csv` folder finding above.
- `sf-devops` working tree (not committed): `smartloyalty-webservicecg-svclog.conf` (the superseded XML-based draft) shows as **deleted**, `README.md` modified — consistent with the investigation's conclusion that draft was abandoned. Left untouched, not this investigation's repo to commit in.

A second, different `.svclog` sample (`/home/dpaniagua/Downloads/SmartLoyalty.WebServiceCG.svclog`, md5 `59ca686a977e3854e688eea35ac0e8e3`, distinct from the repo-root sample already analyzed) was checked structurally only — no raw field values read or written anywhere, same discipline as before:
- **1002 `<E2ETraceEvent>` records, 2025-05-14 to 2026-09-04** — same count and date range as the first sample (near-identical export, not the same file).
- **Zero newlines in the entire 4.4MB file** (`file`: "no line terminators") — an even starker confirmation than the first sample (which was at least hard-wrap-chunked into 440 lines) that a line-based log reader cannot work here at all.
- Same exception-cluster pattern: `SqlException` 686 raw occurrences (multi-layer, same underlying events), `SmtpException`/`WebException`/`SocketException` ~540 each (connectivity cluster).
- Same PII structure re-confirmed: `TraceSourceLogger` blocks (912 raw, 456 pairs) with XML-escaped `&lt;Email&gt;` — 456 occurrences here vs. 438 in the first sample (both close to the ~450 `SqlException`-primary-event ballpark). Grepping for the literal unescaped `<Email>` tag returns 0 — the field only exists inside the escaped `<Data>` string, a trap for a naive parser expecting a raw tag.

This is a second independent re-confirmation of the earlier analysis (different file, same structural conclusions) — strengthens, doesn't newly discover.

## Confirmed fleet fact — SSL expiry monitoring architecture (2026-08-28)

SSL certificate expiration is monitored centrally on the **`Zabbix server`** host, not per-VM: one `log[]`-type active-check item per service (`get_ssl_enddate_<service>`, e.g. `get_ssl_enddate_webservicecg`), each reading its own log file under `/var/log/zabbix/ssl_<name>.log` on the Zabbix server, each with **its own set of 4 triggers**, tagged `cloud:Azure` / `component:SSL Cert` / `env:PROD`. Confirmed present for `webservicecg`, `webservicev2`, `website`, `smartfran`, `mobileappservice`, `fs-api`, `clubsite_ar`, `clubsite_py` (user, Zabbix frontend). Worth adding to `docs/infrastructure.md` as a standing fact so future onboarding checklists don't look for this on the VM itself.

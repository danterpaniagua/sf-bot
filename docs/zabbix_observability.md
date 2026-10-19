# Zabbix Observability — Cross-project Reference

**Last updated:** 2026-10-02 (`GITIN-2156` monthly alert review; earlier: `GITIN-1961`, `GITIN-1965`)

Covers the shared Zabbix instance used across SmartLoyalty, SmartPedidos/Operations (FEPE), and other monitored fleets. Complements `.claude/commands/ope-zabbix.md` (custom UserParameter healthcheck integration workflow and API gotchas) — this doc is the observability/alerting architecture reference, not a skill.

## Instance

| Field | Value |
|---|---|
| Host | `Zabbix server` (FQDN `sf-monitoreo.smartfran.com`) — same box also runs Graylog (see `docs/graylog_infrastructure.md`), separate LVM volume |
| Version | Zabbix 6.0.32 (agent2) |
| API endpoint | `http://sf-monitoreo.smartfran.com:8080/api_jsonrpc.php` — plain HTTP, no `/zabbix/` prefix, no HTTPS on this port |
| API auth | `"auth"` field inside the JSON-RPC body (6.0.32 predates the `Authorization: Bearer` header method) — reference the token as `$ZABBIX_API_KEY` |
| Only Proxy | `sfcg-monitoreo` (`proxyid 10609`, `172.191.99.60`) — every host in the `192.168.50.0/24` DMZ subnet is polled through it |

## Host onboarding checklist

Confirmed baseline for a VM onboarded into this Zabbix instance (derived auditing `SFCG-WSCG-01`, `GITIN-1961`):

| Category | Source | Notes |
|---|---|---|
| Disk latency | `Windows by Zabbix agent active` template, native | Per-disk read/write response time + "Disk is overloaded", Warning tier |
| Disk low space | Same template, native | Two-tier per disk: "low" (Warning) + "critically low" (Average) |
| CPU | Same template, native | Interrupt/privileged/queue-length/high-utilization triggers, Warning tier |
| RAM | Same template, native | "High memory utilization" (Average); swap/page-table (Warning) |
| IIS port running | `IIS by Zabbix agent active` template, native | `net.tcp.service[...]` item + "Port {$IIS.PORT} is down" trigger |
| IIS request-rate alert | **Not native — must be added manually** | See below |
| SSL certificate expiration | **Not per-VM** — centralized | See below |
| Zabbix Proxy | Host config (`proxy_hostid`) | Confirm it matches the DMZ proxy, not left unset |
| Trigger tags → enabled action | Alert routing (see below) | A tag on a trigger proves nothing about delivery — check `action.get` live |

## SSL certificate expiration monitoring

Not monitored per-VM. Runs centrally on the **`Zabbix server`** host itself: one `log[]`-type active-check item per service, named `get_ssl_enddate_<service>` (e.g. `get_ssl_enddate_webservicecg`), each reading its own log file under `/var/log/zabbix/ssl_<name>.log`, each with its own independent set of 4 triggers, tagged `cloud:Azure` / `component:SSL Cert` / `env:PROD`. Confirmed present for `webservicecg`, `webservicev2`, `website`, `smartfran`, `mobileappservice`, `fs-api`, `clubsite_ar`, `clubsite_py` (`GITIN-1961`). When auditing a VM's onboarding for cert-expiry coverage, check the `Zabbix server` host, not the VM — absence there is expected.

**Thresholds and findings (`GITIN-2156`, 2026-10-02):** trigger thresholds come from macros (`{$SSL_CERT_WARN|AVERAGE|HIGH|OK}`, default 45/30/15, OK 60; contexts `:MOBI` 15/10/2, OK 30 and `:FACTURASEND` 25/15/7, OK 80); the trigger name carries the unexpanded macro, so names can show a value that was later changed. Each cert has Warning/Average/High + `No data from SSL <x> from 1 day` (`nodata(…,{$SSL_CERT_NODATA_WINDOW})`, Average; window 1d → **2d since 2026-10-02**, `GITIN-2156`).
- With win-acme renewing inside the last ~30 days of a 90-day certificate (per `operations/docs/mobileappservice_ssl_renewal_runbook.md`, not independently checked against the win-acme settings), the **45-day tier fires on every healthy cycle** for automated certs and stays open until renewal; it only carries signal for certs still renewed by hand. Automation state per service: `loyalty/docs/certificates.md`.
- Tiers for automated certs (user decision, **applied 2026-10-02**, `GITIN-2156`): shared context `:LE` = Warning 15 d / Average 10 d / High 7 d / OK 30 d, used by the MobileAppService, ClubSite AR and Website triggers (9 triggers repointed; the old `{$SSL_CERT_*:MOBI}` macros were deleted); manual certs and the rest keep the default 45/30/15. Add a service to `:LE` only once its renewal is automated and a real renewal cycle has been seen. WebServiceV2 (`GITIN-1772`) and WebServiceCG/Bot-Security (`GITIN-1773`) are **not automated yet** (user, 2026-10-02; the last local records are dated 2026-09-13: Azure DNS zone, SP role and GoDaddy NS delegation done and verified, win-acme install not started; WSCG still serves the paid `*.smartfran.com` wildcard valid to 2027-03-28, with a blast-radius check pending) — they keep the default 45/30/15. **Tier dependencies fixed on all 8 services 2026-10-02** (`GITIN-2156`; 24 triggers): they were inverted (Average → Warning, High → Average/Warning; Clubsite AR High → FacturaSend Average), which suppresses the higher tiers while the Warning is open (inferred from Zabbix semantics, observed on the MOBI legacy trio). Now High has no dependencies, Average depends on High, Warning depends on Average and High — only the highest active tier pages.
- September (before the window change): `No data … 1 day` fired ~35 times on Website/WebServiceV2, each open and closed within the same minute (~21:07) — window too tight for the log refresh. `SSL Clubsite AR … HIGH` depends on `SSL FacturaSend … AVERAGE:FACTURASEND` (copy-paste; should depend on Clubsite AR's own Average trigger).
- Delivery: the SSL triggers carry `scope:GIT-SML` → action 8 → leaders' Chat space only (18 messages in Sept). All 32 SSL triggers carry `SVC_FRIENDLYNAME: SSL <service>` since 2026-10-02 (Chat problem-card title resolves; the recovery card reads the lowercase `friendlyname`, which these triggers don't carry).


## IIS request-rate tiered alert pattern

The `IIS by Zabbix agent active` template's per-app `GET`/`POST Requests/Sec` items (key `perf_counter_en["\Web Service({$IIS.APP.NAME})\...Sec", {$IIS_CURRCONN_UPDATE_INTERVAL}]`) are **visibility-only fleet-wide** — confirmed no trigger references them directly on any host checked (`SFCG-WSCG-01`, `SFCG-WSV2-01`). Don't treat their absence of alerting as a bug to fix per-item.

The real, actionable alert belongs on the generic **`_Total`** item — `IIS: Method Total requests per second` (key `perf_counter_en["\Web Service(_Total)\Total Method Requests/Sec", 60]`, native to the template, always present and collecting) — via a **custom, non-template** 3-tier trigger (Warning/Average/High). This is not stock Zabbix; it's a fleet convention layered on top.

**Macro convention:** `{$PERF_COUNT_TRIG_WARNING|AVERAGE|HIGH|OK|TIME_NOK[:<CONTEXT>]}` — global macros, with a base (no-context) default plus optional per-service context overrides. **Correction (2026-08-30, `GITIN-1965`):** a 2026-08-28 investigation concluded these macros were undefined everywhere and that `SFCG-WSV2-01`'s reference triggers were non-functional — that was wrong. A full (unfiltered) `usermacro.get` pull on 2026-08-30 shows the base macros ARE defined globally (`WARNING=9, AVERAGE=13, HIGH=15, OK=7, TIME_NOK=10m, TIME_OK=15m`), plus existing context overrides `CLUBS` (`WARNING=50, AVERAGE=75, HIGH=90, OK=49`) and `WEBS` (`WARNING=15, AVERAGE=11, HIGH=20, OK=8` — **note `AVERAGE` < `WARNING`, inverted/misconfigured, though currently unreferenced by any trigger, see below) and `WEBSCG01` (this ticket's addition). The earlier 2026-08-28 targeted search (`search: {"macro": "PERF_COUNT_TRIG"}`) returned empty for reasons not fully diagnosed — either the macros were added between the two sessions, or that search call had a real bug. Don't trust a scoped/filtered `usermacro.get` search without cross-checking an unfiltered pull if the result is surprising.

**Expression pattern:**
```
Warning:  min(/<host>/perf_counter_en["\Web Service(_Total)\Total Method Requests/Sec", 60],{$PERF_COUNT_TRIG_TIME_NOK[:<CTX>]})>={$PERF_COUNT_TRIG_WARNING[:<CTX>]}
Recovery: max(/<host>/perf_counter_en["\Web Service(_Total)\Total Method Requests/Sec", 60],{$PERF_COUNT_TRIG_TIME_NOK[:<CTX>]})<={$PERF_COUNT_TRIG_OK[:<CTX>]}
```
Average and High follow the same pattern against their own macro. **Dependency direction caveat (2026-10-02, `GITIN-2156`):** on the legacy `IIS More than N … for 10m` triggers of `SFCG-MOBI-01/02` the chain was Average → depends on Warning, High → depends on Average — **inverted**: a higher tier's condition always implies the lower one's, so while the Warning is open the Average/High are suppressed. September 2026 produced only Warning events on those hosts (zero Average/High, even with a 10-min average of 123 req/s on MOBI-02). Correct suppression has the *lower* tier depend on the *higher* one (as the MOBI `IIS Spike` triggers do). Whether the other hosts using this family (WSV2, CLUB, WSCG-01, WEBS) share the inversion is **not checked**.

**Fleet inventory (2026-08-30, `GITIN-1965`) — real drift across generations, not a single clean pattern:**

| Host(s) | Trigger family | Context | Status |
|---|---|---|---|
| `SFCG-WSV2-01`, `SFCG-WSV2-02` | `PERF_COUNT_TRIG_*` (plain) | none (base defaults) | Functional — `9/13/15` req/s |
| `SFCG-CLUB-01`, `SFCG-CLUB-02` | `PERF_COUNT_TRIG_*` | `CLUBS` (shared pair) | Functional — `50/75/90` |
| `SFCG-WEBS-01/02/03`, `SFCG-WSIT-01` | **Different family**: `IIS_REQUESTS_WSV1_POST:WARN/AVG/HIGH/OK` | shared literally across all 4 hosts (`WARN`/`AVG`/`HIGH`, not per-host) | Functional — `30/90/120`, **identical thresholds for 4 different services** (WebService instances and the Website), no per-host tuning |
| `SFCG-WSCG-01` | `PERF_COUNT_TRIG_*` | `WEBSCG01` | Functional — `15/30/50` (this ticket, `GITIN-1961`) |
| `SFCG-MOBI-01`, `SFCG-MOBI-02` | `IIS Spike` (+ `Caída brusca`; legacy `PERF_COUNT_TRIG` trio disabled 2026-10-02) | `:MOBI` shared | See MOBI section below |

**`SFCG-MOBI-01`/`02` — state after `GITIN-2156` (2026-10-02).** Three alert families existed on the same `_Total` request-rate item; now:
- **`IIS Spike`** (triggers 26742-26744 MOBI-01, 26745-26747 MOBI-02) — one shared `:MOBI` context for both VMs: Warning/Average/High `{$MOBILE_PCOUNT_SPIKE_WARN|AVG|HIGH:MOBI}` = **45/75/100** req/s, recovery `{$MOBILE_PCOUNT_SPIKE_OK:MOBI}` = **40**, fire windows per tier `{$MOBILE_PCOUNT_SPIKE_TIME_WARN|AVG|HIGH}` = **10m/5m/3m**, recovery window `{$MOBILE_PCOUNT_SPIKE_TIME_OK}` = **20m**. Basis: September 2026 data — MOBI-02 CPU is flat (~21-25%) up to ~45 req/s and was pinned at ~100% from ~100+ req/s in one event (2026-09-04, n=1, confounded with a host start-up); RAM never exceeded ~75% on either VM; MOBI-01 (larger SKU) idles at ~0.2-0.3 req/s and carries ~3% of requests. The old per-host macros `:MOBI01`/`:MOBI02` and `{$MOBILE_PCOUNT_SPIKE_TIME}` (3m) were deleted on 2026-10-02 after a usage scan of all triggers (names, expressions, recovery, function parameters) and items found no references.
- **Legacy `IIS More than 9/13/15 … for 10m`** (26133-26138, base `{$PERF_COUNT_TRIG_*}` macros shared with other hosts) — **disabled** on both MOBI hosts: 9 req/s is ~MOBI-02's normal peak (p90 ≈ 10), inverted dependency chain (see above) meant only the Warning ever fired (~97 h/month open).
- **`Caída brusca`** — replaced 2026-10-02 (`GITIN-2156`) by a **service-level** collapse detector aimed at a Grido-side WAF block that drops request rate to ~0 after a spike (purpose per user; events that fit it: 2026-06-19 22:09 and 2026-06-21 ~15:42, unconfirmed as WAF). Calculated item `54606` `iis.total.requests.mobis.service` on SFCG-MOBI-01 = `last(MOBI-01 item) + last(MOBI-02 item) * (count(MOBI-02 item, 3m) > 0)` (MOBI-02 counted only while it reports, so its nightly power-off adds nothing and no stale value is used; the old sum item `iis.total.requests.mobis.sum` added the stale last value). Trigger `26898` (High, tags `SVC_FRIENDLYNAME` = `friendlyname` = `Mobile request rate` so problem and recovery cards match) on it: `max(5m) <= {$MOBI.COLLAPSE.ABS}` (0.2) AND `count(30m:now-5m, "gt", {$MOBI.COLLAPSE.MINVAL}) >= {$MOBI.COLLAPSE.MINCOUNT}` (≥15 of 30 min above 1 req/s) AND `count(30m) >= {$MOBI.COLLAPSE.PRESENT}` (25); recovery `avg({$MOBI.COLLAPSE.RECWIN}=3m) >= {$MOBI.COLLAPSE.REC}` (1). Silent by design in low-traffic hours and right after the item is created or MOBI-02 starts. The trigger shows host SFCG-MOBI-01 in alerts. Disabled predecessors: 26287 (MOBI-02-only version), 26286, 26448 (last-minute-dip logic, 181+49 events/month). Typical MOBI-02 levels since June 2026: ~0.4-0.9 req/s before 11:00, 1.5-3.5 midday/afternoon, 3-5.5 evening (weekends about double); MOBI-01 carried ~97% of the traffic until 2026-05-12 (~23:00), MOBI-02 has carried it since (MOBI-02 is powered on on demand and is off most nights); the idle host sits on a flat ~0.07 req/s floor.
- **Routing tags** on the six Spike triggers: `action:TELE,GCHAT`, `SVC_FRIENDLYNAME:Mobile Total Requests (req/s)`, `scope:OPE`+`scope:GIT-SML-OPE`, `service_group:LOYALTY` — matches only action 7 (Operaciones Chat; action 8 needs `scope = GIT-SML` exactly), see Alert routing.

Also: `MOBI-02` has a dedicated "sin datos" (no-data) trigger (`26748`) and its own `{$MOBILE_PCOUNT_NODATA_WINDOW:MOBI02}=11h` macro; `MOBI-01` has **neither** — asymmetric coverage, not yet confirmed intentional.

Orphaned/unreferenced macros found during this pull (defined but no trigger currently uses them, at least among hosts checked): `{$PERF_COUNT_TRIG_*:WEBS}` (distinct from the `IIS_REQUESTS_WSV1_POST` family actually used by the WEBS/WSIT hosts), `{$IIS_REQUESTS_WSV2_POST:OK}`, `{$IIS_REQUESTS_WSV3_POST}`. Note the `WSV1`/`WSV2`/`WSV3` naming in this macro family is easy to confuse with the actual `SFCG-WSV2-01/02` hostnames (WebServiceV2) — they are unrelated namespaces that happen to collide.

## IIS request-queue triggers (`GITIN-2156`, 2026-10-02)

Template `IIS by Zabbix agent active` (id `10326`, linked by 12 hosts: CLUB-01/02, MOBI-01/02, WEBS-01/02/03, WSV2-01/02, WSIT-01, WSCG-01, SFDEV02 — the last is a disabled host) discovers one trigger per app pool from the LLD rule `wmi.getall[root\webAdministration, select Name from ApplicationPool]`. The stock macro `{$IIS.QUEUE.MAX.WARN}` is shipped **empty**, so the discovered `IIS: Request queue of <pool> is too large` triggers were unsupported (`right operand "" is not a numeric value`) on every host that evaluated them — IIS queue alerting was not working (8 hosts affected at the time of the review). A template macro overrides a global one, so the value had to be set on the template.

Now three levels on the template (trigger prototypes, `min(CurrentQueueSize,{$IIS.QUEUE.MAX.TIME}) > {$IIS.QUEUE.MAX.<tier>}`): Warning `16917` > `{$IIS.QUEUE.MAX.WARN}` = **10**, Average `26879` > `{$IIS.QUEUE.MAX.AVG}` = **50**, High `26866` > `{$IIS.QUEUE.MAX.HIGH}` = **200**, window `{$IIS.QUEUE.MAX.TIME}` = 5m. Dependencies: High → `16914` (app pool not Running); Average → High + `16914`; Warning → Average + High + `16914`. Routing tags on all three: `scope:performance`, `scope:GIT-SML-OPE`, `service_group:LOYALTY`, `action:GCHAT`, `SVC_FRIENDLYNAME:IIS request queue` (Operaciones Chat via action 7). Item prototype `31051` (`CurrentQueueSize`) history raised 7d → 365d. Thresholds are not calibrated: the queue was 0 on every monitored pool over the last 7 days. Discovered triggers pick the change up on the next LLD run.

## Alert routing (trigger-based actions)

**Live state as of 2026-10-02 (`GITIN-2156`, `action.get` + September 2026 `alert.get`).** `status` is the raw API value — see the convention note below.

| id | Name | `status` | Matches | Recipients / observed behavior |
|---|---|---|---|---|
| 3 | `Report problems to Zabbix administrators` | 1 | No conditions (every problem) | Group 7, media type `0` (all). Produced **zero** alert records in Sept 2026 (1,801 problems) → most likely disabled; contradicts the earlier "only action paging by default" claim |
| 7 | `Google Chat Loyalty to Operaciones` | 0 | **Edited 2026-10-02 (`GITIN-2156`), custom expression `A and B and (C or D)`:** `scope = GIT-SML-OPE` (exact) AND `action ~ GCHAT` AND (`service_group = LOYALTY` OR `service_group = CLOUD`). Originally `scope ~ GIT-SML` AND `GCHAT` AND `service_group = LOYALTY` AND `= CLOUD` (an And that required both groups on one trigger, so it never matched) | User 9 (`operaciones_msg`) → Operaciones Chat space; media active, all severities, 24x7. Opt-in: only triggers explicitly tagged `scope:GIT-SML-OPE` route here — the six MOBI `IIS Spike` triggers, and the `ARCA*` triggers once tagged (see the ARCA note). Last delivery before Sept: 2026-07-27 (50 most recent all sent) |
| 8 | `Google Chat Loyalty to GIT-SML` | 0 | `scope = GIT-SML` (exact) AND `action ~ GCHAT` AND `service_group = LOYALTY` | Group 16 (Project Leaders, only member user 13) + user 12. Sept: all 18 alerts (SSL-expiry events) went to user 13, none to user 12 (user 12's only group is `Disabled` — lead, not confirmed). Leaders' Chat space |
| 9 | `Google Chat Loyalty to PLs (EMAIL)` | 0 | `service_group = LOYALTY` AND `scope ~ PL` AND `action ~ EMAIL` | Email to user 13. Matches nothing: no `scope` value contains `PL` |
| 10 | `Google Chat Loyalty to OPE (EMAIL)` | 0 | `scope ~ OPE` AND `service_group = LOYALTY` AND `action ~ EMAIL` | Email (media `4`) to user 9. Live condition is `EMAIL`, **not** `MAIL` (the 2026-08-28 `GITIN-1961` change to `MAIL` is not what is stored now — cause unknown); it therefore matches only triggers whose `action` tag is literally `EMAIL` (~38). Sept: 50 attempts, all failed (`cannot connect to SMTP server aspmx.l.google.com:25 … Interrupted system call`), 0 delivered |
| 11 | `Google Chat SmartPedidos to Operaciones` | 0 | `scope = OPE` AND `scope = SP` AND `action ~ GCHAT` (live 2026-10-18) | Not re-read for recipients |
| 12 | `Notify OPERACIONES env PROD (Chat + Telegram)` | 0 | `env = PROD` only — no `service_group` or `scope` (live 2026-10-18, `GITIN-2250`) | Enabled. Any trigger tagged `env:PROD` goes here (seen on legacy WSV1 IIS triggers, `SFCG-WSV2-01` stock CPU, `SFCG-WSIT-01` disk). One operation, recipient user 16 only, media type 0 (all of that user's media): user 16 has enabled media entries for type 38 (Google Chat script) and type 16 (Telegram), all severities, 24x7. `alert.get` over the 7 days to 2026-10-18 19:00 shows at least 250 alerts per media type (query limit 500) with `status` 1 (sent) and no error for both; a person reading them was not checked |

**`action.status` convention — conflicting evidence, confirm before writing.** Earlier notes (2026-08-27/28) state it is inverted vs items/triggers (`1` = enabled). Live data 2026-10-02: actions 2-6 = `1`, 7-10 = `0`; September `alert.get` shows alerts only from actions 8 and 10 and none from action 3. That fits the standard Zabbix convention (`0` = enabled, `1` = disabled, same as triggers/items): actions 7-10 enabled, 3-6 disabled. Not yet confirmed in the frontend (Alerts → Actions → Trigger actions shows Enabled/Disabled). Check the list before any `action.update`; if the standard convention is confirmed, the "inverted" statements here and in `ope-zabbix.md` are wrong and GITIN-1961's `status:"1"` would have disabled action 10.

**How routing actually works (verified 2026-10-02):**
- A trigger notifies only if its tags satisfy an enabled action's conditions. Before `GITIN-2156` the MOBI triggers (`scope:OPE`, `service_group:LOYALTY`, `action:TELE,GCHAT,MAIL`) matched **no** action: 25 of 1,801 September problems had any notification attempt (1 of 198 High). The `TELE`/`MAIL` parts of the `action` tag are labels — no action checks `TELE`, and `MAIL` is not a substring of the `EMAIL` the live email actions require.
- `~` is substring, `=` is exact; a trigger can carry several values per tag key. Example: `scope:GIT-SML-OPE` satisfies action 7 (`= GIT-SML-OPE`, opt-in since 2026-10-02) but not action 8 (`= GIT-SML`) — used to reach the Operaciones space only.
- Media type 38 (`Script Google Chat python`, `chat-google.py`) takes `{ALERT.SENDTO}` = the per-user Chat API path (space + key + token) — **never persist `sendto` or script parameters**; mask when pulling. Operaciones and leaders are different spaces. Its problem card title is `Servicio {EVENT.TAGS.SVC_FRIENDLYNAME} degradado` and the recovery card uses `{EVENT.TAGS.friendlyname}` → any trigger routed to Chat needs an `SVC_FRIENDLYNAME` tag (the MOBI Spike triggers carry `Mobile Total Requests (req/s)`). Tag split on IIS triggers that fired in Sept 2026 (`GITIN-2156`): request-rate triggers (`IIS Spike`, `IIS More than N …`, `More than N IIS Method POST …`) carry only `friendlyname`; per-app-pool service triggers (`… has been restarted`, `Application pool … not in Running state`) carry only `SVC_FRIENDLYNAME`; the generic `IIS: has been restarted`, `IIS: Port N is down`, `WAS is not running` and the `HTTP Code not 200` web checks carry **neither** — a Chat card for those would show the title macro unresolved. A trigger routed to Chat should carry both tags with the same value.
- Email HTML (media `4`) uses no tags. Telegram (media `16`) still has the stock placeholder token (`<PLACE YOUR TOKEN>`), no action uses it, and September has no Telegram alerts: Telegram messages, if any, do not come from these actions.
- **Correction 2026-10-18 (`GITIN-2250`):** the sentence above says no action uses Telegram; action 12 (`... (Chat + Telegram)`, condition `env = PROD`) exists and is enabled. Read afterwards (same day): its single operation goes to user 16, who has enabled Telegram and Google Chat media, and `alert.get` shows Telegram (type 16) alerts with `status` 1 and no error over 7 days. Telegram messages are therefore being sent for every `env:PROD` trigger; the earlier statement that no action uses Telegram is wrong.
- Gaps found, not yet fixed: SMTP failure above; `loyalty_msg` (user 12) in a disabled group; action 9 (`scope ~ PL`) matches nothing; **the ARCA healthcheck triggers** (`service_group:CLOUD`, `scope:GIT-SML`, `GCHAT`) matched neither action 7 nor action 8 and notified no one in Sept 2026 (`ARCA DOWN`/`ARCA DEGRADADO` 21 + 21 problems) — **fixed 2026-10-02**: action 7 now accepts `LOYALTY` or `CLOUD` and the five `ARCA*` triggers (DOWN, DEGRADADO, sin datos, WSFEv1 Latencia Alta/Crítica; ids 26730-26734) carry `scope:GIT-SML-OPE` + `SVC_FRIENDLYNAME: ARCA`, so they route to the Operaciones Chat space (they do not match action 8, which needs `LOYALTY`).

## Tag efficiency audit (2026-08-28, `GITIN-1961`)

> **Correction 2026-10-02 (`GITIN-2156`):** the "only live routing combination" below assumed action 10 matches `action ~ MAIL`; the live condition is `~ EMAIL` (see Alert routing). The tag counts remain valid; the routing conclusion does not.

Instance-wide `trigger.get` (`monitored: true`, real hosts only — an unfiltered pull returns template-level triggers too and is polluted by hundreds of stock vendor templates, e.g. Cisco/MikroTik/AWS/Azure, that ship with this Zabbix install) found **1,176 triggers across 22 real monitored hosts** (`SFCG-*`, `sfcg-monitoreo`, `sfcg-sonarqube`, `SF-FACT-PY01`, `smartfran-pedidos-*`, `Zabbix server`), carrying ~2,700 tag instances total. Cross-referenced against every action's filter conditions (table above):

**Tags that feed a live routing decision:** effectively one combination — `scope:OPE` (84 triggers) + `service_group:LOYALTY` (84) + an `action` tag containing `MAIL` (`TELE,GCHAT,MAIL`=53, or the literal `EMAIL`=32 — both satisfy action `10`'s `~MAIL` condition, since `"EMAIL"` itself contains `"MAIL"`). This is the only tag combination read by any **enabled** action.

**Tags read only by disabled actions** (inert until/unless 7/8/9 are revisited): `scope:GIT-SML` (35 triggers), `action:GCHAT` (42 triggers).

**Tags no action anywhere — enabled or disabled — ever inspects** (~915 tag instances, pure display/dashboard metadata, not routing):

| Tag key | Count | Where it's actually used |
|---|---|---|
| `scope` (`notice`/`performance`/`capacity`/`availability`/`security`) | 1,166 of 1,285 total `scope` tags (~91%) | No action condition checks these values |
| `SVC_FRIENDLYNAME` | 441 | Display label on native-template "service not running" triggers |
| `env` | 124 | Not referenced by any condition |
| `friendlyname` / `metric` / `metrics` | 102 | Trigger names / `opdata`, human-readable only |
| `service` | 76 | Not referenced |
| `component` | 60 | Not referenced |
| `cloud` | 58 | Not referenced |
| `type` | 53 | Not referenced |

**Bottom line:** of ~2,700 tag instances fleet-wide, only the `scope:OPE` + `service_group:LOYALTY` + `action~MAIL` combination does any real routing work as of this audit — everything else either belongs to a disabled/non-matching action or was never wired to routing logic at all. Raw pulls: `loyalty/events/20260828_wscg01_zabbix_graylog_onboarding/all-trigger-tags-real-hosts.json`.

## Fleet alert standards — CPU and RAM tiers (`GITIN-2250`, applied 2026-10-18)

Applied to the 14 prod SFCG loyalty hosts (CLUB-01/02, JENKINS-01, MOBI-01/02, SMTP-01, TO-01, WEBS-01/02/03, WSCG-01, WSIT-01, WSV2-01/02) with host-level triggers created through the API (the shared Windows template triggers were left unchanged). Thresholds are the user's decisions, not measurements. `sfcg-monitoreo` and `sfcg-sonarqube` are tooling hosts (not prod); `SFCG-DB01`, `SFCG-DB01-CLON`, `SFCG-SMTP-02` are disabled and not used.

| Metric | Item | Tiers (priority) | Window | Recovery |
|---|---|---|---|---|
| CPU | `system.cpu.util` | Warning 70 (2) / Average 80 (3) / High 85 (4) | `avg` 10m | `max` 10m below 60 / 70 / 75 |
| RAM | `perf_counter_en["\Memory\% Committed Bytes In Use"]` (created on the 14 hosts; it did not exist) | Warning 70 / Average 75 / High 80 | `avg` 10m | `max` 15m below 60 |

- Macros are global: `{$CPU.UTIL.WARN|AVG|HIGH|TIME|WARN.OK|AVG.OK|HIGH.OK}` and `{$MEM.COMMIT.WARN|AVG|HIGH|TIME|OK|OK.TIME}`. Dependencies: High none, Average → High, Warning → Average + High.
- Routing tags on all of them: `scope:performance`, `scope:GIT-SML-OPE`, `service_group:LOYALTY`, `action:GCHAT`, `SVC_FRIENDLYNAME:<CPU utilization | Memory commit>` → action 7 (Operaciones Chat).
- Template stock triggers (`High CPU utilization` 90 % over 5m, CPU queue, privileged, interrupt, `High memory utilization` 90 %, Pages/sec) carry only `scope:` tags and route nowhere. Stock macro values: `{$CPU.UTIL.CRIT}`=90, `{$CPU.QUEUE.CRIT.MAX}`=3, `{$MEMORY.UTIL.MAX}`=90, `{$MEM.PAGE_SEC.CRIT.MAX}`=1000.
- The balancer probe (SmartLoyalty `healthcheck.ashx`) answers HTTP 400 when a 500 ms CPU sample or the commit ratio (`Committed Bytes / Commit Limit`) exceeds 80; Zabbix averaged tiers do not see single-sample spikes. See `loyalty/docs/infrastructure.md`.
- **Required, not built yet (user, 2026-10-18):** disk usage and lack of free space (used-% tiers and a run-out-of-space forecast) on every prod host, routed to Operaciones. Tiers and forecast horizon are undecided; the stock "Disk space is low / critically low" triggers come from discovery on the Windows template and route nowhere.
- Compliance state (live pull 2026-10-18): disk triggers (9-15 per host) route nowhere except `SFCG-WSIT-01`; stock CPU/RAM triggers route nowhere except where `env:PROD` sends them to action 12; V1 web-scenario triggers 25746/25753 carry no tags. Audit procedure: skill `alert-normalizer` (`.claude/commands/alert-normalizer.md`).
- Web scenarios on `sfcg-monitoreo` (10610) run from proxy `10609`, which also monitors the WEBS hosts. Scenario 6 (`[PROD] API POS / Gestion`) has a `Healthcheck` step (`/healthcheck.ashx` through `webservice.clubgrido.com.ar:8080`). Configuration changes reach a proxy on its sync interval (not read for this proxy): new items and steps may show no data until then.
- API traps seen: `item.get` ignores an `httptestids` filter (returns every item; use `webitems:true` + `search:{key_}`); `httptest.update` replaces the whole step list (resend steps with their `httpstepid`); `usermacro.get` without `hostids` returns no template macros (use `template.get` + `selectMacros`); `trigger.get` returns expressions as function ids unless `selectFunctions` is requested.

## Known Zabbix Agent 2 bugs

- **`ZBX-22463`** — `Detected performance counter with negative denominator ... giving up`. Windows IIS/performance-rate counters on Agent 2, this instance's version (6.0.32) predates the reported fix (`ZBX-20356`, ~6.2.7+). Mitigation: restart the `Zabbix Agent 2` service — often only **temporary**; can recur. Confirmed chronic on `SFCG-WSCG-01` (dozens of occurrences since 2026-07-20) vs. a single isolated blip on `SFCG-WSV2-02` that a restart cleared (`GITIN-1956`) — don't assume one restart is a durable fix.
- **Host cloning doesn't guarantee item parity.** A "Clone" host copies templates/macros/host-level items/triggers as configured at clone time, but a specific discovered/manually-added item (e.g. `Get Requests/Sec`) can simply be missing on the clone if it wasn't present when cloned (`GITIN-1956`, `SFCG-WSV2-02`). Always diff a freshly cloned host's item list against its source rather than assuming completeness.

## Known API limitations and data-retention gotchas (2026-08-31, `GITIN-1965`)

- **No API access to Trends on Zabbix 6.0.32.** `trends.get`/`trend.get` returns `-32601 Method not found` — the dedicated Trend API method was only added in Zabbix 6.4+. On this instance, hourly Trend aggregates (`value_min`/`value_avg`/`value_max`) are visible only through the frontend UI graphs, never programmatically. If an item's raw History has already aged out past its retention period, **there is no API-accessible way to recover or backfill that data** for the affected window.
- **History storage period defaults/inherits inconsistently, and this has real consequences.** Confirmed 7d History (vs. sibling items on the same host at 180d) on: Mobile GET/POST items, CPU/Memory utilization items on both Mobile hosts, and the GET/POST items on `SFCG-WEBS-01/02/03`/`SFCG-WSV2-01/02`. All raised to 180d going forward (2026-08-31), but the fix isn't retroactive — combined with the Trends-API gap above, any week-over-week analysis needs the item's actual `history` value checked (`item.get`, `output: ["history","trends"]`) before trusting a `now-Nw` lookup, not assumed. Full detail: `operations/events/20260829_mobile_alerts_coverage_analysis/investigation.md`.

- **`trigger.get` with `expandExpression: true` also expands macros** (`GITIN-2156`, cost a wrong finding: macro values looked like hardcoded literals). For config audits pull the raw expression plus `selectFunctions` (on 6.0.32 it returned `functionid` + `parameter` only — **no function name**, so a raw snapshot cannot be turned back into an expression from the API output; rewrite the original expression explicitly for rollbacks) so macro references stay visible.
- **A raw `trigger.get` snapshot cannot be restored with `trigger.update`**: raw expressions contain function ids (`{38197}>=…`) and the API rejects them (`incorrect expression starting from "{38197}…"`). Rebuild rollbacks from explicit expression text, or snapshot with `expandExpression` *and* record the macros separately.
- **`trigger.update` with `tags` replaces the whole tag list** — read the current tags, modify, resend all. `trigger.status`: `0` enabled, `1` disabled (triggers/items; see the action convention note above for actions).
- **`alert.get` returns no `userid` unless requested** (`output` list) — needed to see who actually received an action's notifications; never request/persist `sendto`.
- **Pulls into `events/` can contain real names/emails** (`user.get`, `usergroup.get`): request only `userid`/`username`-level fields and mask media `sendto`/script parameters.
- **Web-scenario items need `"webitems": true` in `item.get`** (`GITIN-2239`, 2026-10-16): without it the call returns no `web.test.*` items, which looks like "the scenario has no items/triggers". Web item keys carry quoted names (`web.test.rspcode["[PROD] MobileApp",healthcheck]`), so a key comparison written without the quotes also finds nothing. Check one raw item before concluding a web item is absent.

## References

- `loyalty/docs/infrastructure.md` — SmartLoyalty-specific host/service inventory, per-host Zabbix notes
- `.claude/commands/ope-zabbix.md` — custom UserParameter healthcheck integration workflow, API-write gotchas, API apply pattern
- `loyalty/events/20260828_wsv2-02_zabbix_iis_calc_item_error/` (`GITIN-1956`) — `ZBX-22463` discovery, item-parity gap
- `loyalty/events/20260828_wscg01_zabbix_graylog_onboarding/` (`GITIN-1961`) — onboarding checklist origin, IIS tiered-alert pattern, alert-routing tag/action fixes
- `operations/events/20260829_mobile_alerts_coverage_analysis/` (`GITIN-1965`) — cross-service peak-season traffic baseline, History-retention/Trends-API gotchas above
- `operations/events/20261002_zabbix_monthly_alert_review/` (`GITIN-2156`) — September 2026 alert review: delivery/routing findings, MOBI IIS Spike retune, legacy trio disabled, SSL tier analysis

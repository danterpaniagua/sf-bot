# SmartLoyalty — Infrastructure Reference

**Last updated:** 2026-08-07
**Subscription:** Smart IT - Grido (`0190fa7d-4ccf-4e3d-beb1-323b5780bfc8`)

---

## Database Server

| Field | Value |
|---|---|
| Instance | `SFCG-DB01` |
| Engine | Microsoft SQL Server 2022 Standard, 64-bit, version 16.0.4075.1 |
| Host OS | Windows Server 2022 Datacenter |
| Server timezone | GMT (UTC+0) — all `LogDate`/timestamp columns are GMT; user's local timezone defaults to UTC-3 |

---

## Application Servers

| Host | Role |
|---|---|
| `SFCG-WEBS-01/02/03` | WebService (`C:\SmartFran\SmartLoyalty.WebService\`) — serves **on-premise SmartFran** (confirmed 2026-08-31). Not a "V1" of `SFCG-WSV2-*` in any versioning sense despite the naming similarity — separate platform, separate client base. Do not group with `SFCG-WSV2-*` in analysis/reporting. |
| `SFCG-WSV2-01` | WebServiceV2 (`D:\SmartLoyalty.WebServiceV2\`) — serves **SmartCloud** (confirmed 2026-08-31), a different platform from `SFCG-WEBS-*`'s on-premise SmartFran. `Standard_D8as_v5`, `eastus` |
| `SFCG-WSV2-02` | WebServiceV2 (`D:\SmartLoyalty.WebServiceV2\`, assumed same path — not yet verified) — `Standard_D2ds_v4`, `eastus`. **Running and receiving real production traffic as of 2026-08-27 (`GITIN-1238`, resolved)** — previously provided zero real redundancy despite billing compute, root-caused to a Network Security Group rule (`sfcgnetsec01`, subnet-level, rule `WebService_V2_PRO`) that never included this VM's private IP (`192.168.50.172`) in its destination allow-list for TCP 8080; Azure's own health probes bypass NSG evaluation entirely, so the LB always reported this VM healthy while real client connections were silently dropped. Fixed by adding the IP to that rule — see `events/20260826_wsv2lb_vm2_trustedlaunch_no_traffic/` for full detail. Behind `SFCG-WSV2-LB` (Standard LB, backend pool `SFCG-WSV2-LB-backendpool01`, both VMs, `Default` 5-tuple hash — no session affinity). **Zabbix monitoring cloned from `-01` (2026-08-27)** — same templates (`IIS by Zabbix agent active`, `Windows by Zabbix agent active`) and host macros, confirmed live data flowing. This VM is **not run 24/7 like `-01`** — powered off nightly `00:00–09:00 UTC-3`; a dedicated Zabbix Maintenance period (`maintenanceid 2`) suppresses false alarms during that window, no trigger changes needed. **`D:\` on this VM is an Azure temporary disk** (confirmed 2026-08-27) — the `D2ds_v4` SKU's "ds" series includes local ephemeral temp storage mapped as `D:\`, unlike VM1's `D8as_v5` ("as" series, no local disk, `D:\` there is real persistent storage). Any deallocate/host-migration/reimage of `-02` wipes whatever is deployed to `D:\`, including the app itself — a real deployment/config-drift risk, not yet remediated. |
| `SFCG-WSIT-01` | WebSite (`D:\SmartLoyalty.WebSite\`) — public ingress via Application Gateway WAF `WAF_APPs` (`DefaultGroup01`), single backend server, no redundancy. See `/loyalty-azure-waf` skill for listener/pool detail |
| `SFCG-MOBI-01/02` | MobileAppService — ASP.NET MVC/WebApi on .NET Framework 4.x, IIS (requires VM, not App Service PaaS), DMZ subnet, resource group `DefaultGroup01`, subscription **Smart IT - Grido**. Public ingress via Azure **Standard** Load Balancer `SFCG-MOBI-LB` (same RG) — **not** a direct VM public IP; `20.121.19.174` (static) is the LB's public IP (`SFCG-MOBI-LB-publicip`), previously misattributed directly to `SFCG-MOBI-01`'s NIC in this doc. Single LB rule `SFCG-MOBI-LB-lbrule02`: TCP 8043→8043, `idleTimeoutInMinutes=15`, backend pool `SFCG-MOBI-LB-backendpool01`. **Confirmed 2026-08-21** (`GITIN-1909`) via `az network lb address-pool list`: backend pool contains both `sfcg-mobi-01421` and `sfcg-mobi-02639` NICs — `SFCG-MOBI-02` is live and in rotation, not just `-01`. Health probe `SFCG-MOBI-LB-probe02` (plain TCP, port 8043, 5s interval, **`numberOfProbes=1`**) is the only probe actually attached to the live rule — a single missed check pulls a backend from rotation, unusually aggressive vs. Azure's typical ≥2 recommendation. Two other probes exist (`SFCG-MOBI-LB-probe01` HTTP `/api/MobileAppService/CheckServiceStatus`; `healthcheck.ashx` HTTPS `/healthcheck.ashx`) but are **not** referenced by any current rule — orphaned/legacy, not verified in use. No WAF/Application Gateway in front of MobileAppService — `WAF_APPs` exists in the same RG but fronts WebSite/ClubGrido only (confirmed 2026-08-21, `GITIN-1909`). Ingress path is client → NSG (**one-to-one source-IP allow-list**, not subnet-based) → `SFCG-MOBI-LB` → IIS — no L7 device anywhere in the path. Full detail: `events/20260821_mobileappservice_loadtest_503/`. |
| `SFCG-WSCG-01` | WebServiceCG (`192.168.50.181`) — IIS app pool/site `SmartLoyalty.WebServiceCG`, `{$IIS.PORT}=443`. Zabbix: `IIS by Zabbix agent active` + `Windows by Zabbix agent active` templates, polled via the `sfcg-monitoreo` DMZ proxy. Confirmed 2026-08-28 (`GITIN-1961`): the two IIS request-rate items (`SmartLoyalty.WebServiceCG: IIS Method GET/POST requests per second`) have never collected data (`lastclock:0`) and have no trigger defined at all — not yet fixed. See "Monitoring (Zabbix) — SSL certificate expiration" below for where cert monitoring for this host actually lives. |
| `SFCG-CLUB-01/02` | Club Grido website — `192.168.50.121`/`.122` (confirmed via `az network nic list`, 2026-08-07). Public ingress via Application Gateway WAF `WAF_APPs` (`DefaultGroup01`), backend pool `Back_ClubSite` (`www.clubgrido.com.ar`) — same two servers also back `Back_ClubSite_PY` (`www.clubgrido.com.py`), no separate PY-specific backend. `WAF_APPs` has no `urlPathMaps` — host-based routing only. See `operations/docs/waf_apps_cert_automation_runbook.md` for the cert-automation work in progress on this gateway. |
| `SFCG-TO-01` | TaskOperatorService (`E:\SmartLoyalty.TaskOperatorService\`) |
| `SFCG-DB01` | SQL Server host (see Database Server below) |
| `SFCG-SMTP-01`/`SFCG-SMTP-02` | hMailServer outbound mail relay — `192.168.50.161`/`.162`. WebServiceCG's `AccountRecovery` endpoint (and other app-triggered emails) go app → hMailServer (these hosts) → `smtp.sendgrid.net` → recipient. Confirmed 2026-08-11/12 during `GITIN-1816`. NXLog on both ships delivery logs (tag `SF-SMTPRL`) to the Graylog stack shared with SmartPedidos — see `../../docs/graylog_infrastructure.md`. |
| `SFCG-JENKINS-01` | Jenkins CI controller for SF-LOYALTY (resource group `DefaultGroup01`, subscription **Smart IT - Grido**, confirmed 2026-09-23 `GITIN-2099`) — Windows, Jenkins run as a WinSW service (`D:\Program Files\Jenkins\jenkins.xml`), `JENKINS_HOME=D:\Jenkins\.jenkins`, HTTPS on 8443 (`sfcg-jenkins-01.smartfran.com`), no plain HTTP. **JDK requirement gotcha (confirmed 2026-09-23):** modern Jenkins core hard-requires Java 21+; this box was still on Java 17 (`C:\Program Files\Java\jdk-17`), causing an infinite WinSW restart loop (`<onfailure action="restart"/>`, no backoff) after a routine reboot — Jenkins printed `Running with Java 17... older than the minimum required version (Java 21)` and exited on every launch. Fixed by installing Eclipse Temurin 21 (`C:\Program Files\Eclipse Adoptium\jdk-21.0.12.101-hotspot\`) and repointing `jenkins.xml`'s `<executable>` to it. **Two non-obvious side effects of that JDK swap, both confirmed the same day:** (1) the Windows Firewall's `Jenkins` inbound-8443 rule was scoped to the *old* `jdk-17\java.exe` program path specifically — after the swap it silently stopped matching, blocking external UI access even though the service itself was healthy (loopback `Test-NetConnection` succeeded, external didn't) — fixed via `Set-NetFirewallApplicationFilter` to the new java.exe path, do **not** work around this by disabling the firewall. (2) Windows caches the system environment (`JAVA_HOME`/`PATH`) at boot — `[Environment]::SetEnvironmentVariable(...,"Machine")` does not propagate to already-running services *or* newly-spawned child processes until an actual **reboot**, not just a service restart; this bit both the Jenkins service's own re-launch and `SonarScanner.MSBuild.exe`'s separate `java` resolution (it shells out via system `PATH`, independent of `jenkins.xml`'s explicit executable). **Side effect surfaced by the controller's Java 21 upgrade, confirmed and fixed 2026-09-23:** the `sonarqube-srv` Jenkins agent (host `sfcg-sonarqube` — a **different VM**, `DefaultGroup01`/Smart IT - Grido, same RG as this host but not the same box; it's the SonarQube server itself, see `operations/docs/sonarqube_upgrade_runbook.md` § 7bis for full detail) failed to reconnect via SSH Remoting with `UnsupportedClassVersionError` (class file version 65 = Java 21 vs. 61 = Java 17 max) — its system-wide `java` default had drifted back to 17 at some point after that host's own SonarQube-focused Java 21 upgrade (`GITIN-1327`). Fixed via `update-alternatives --set java` to the already-installed Temurin 21 on that host; confirmed zero impact on SonarQube itself, which is independently pinned via `SONAR_JAVA_PATH`, not the system default. |
| `LUCAS-KIUVI` | QA workstation — must not connect to production |

### Database accounts

| Account | Type | Used by | Role on SmartLoyalty |
|---|---|---|---|
| `SMARTIT\itservices` | Windows domain | All app servers | cross-role (not audited) |
| `sfsqlusr` | SQL login | TaskOperatorService (SFCG-TO-01) | `db_owner`, `db_securityadmin` ⚠️ over-privileged |
| `sfsqlusrit` | SQL login | QA / SSMS (LUCAS-KIUVI) | `db_datareader` — confirmed 2026-09-19, no longer `db_owner`/`db_securityadmin` (previously flagged over-privileged; role since revoked or was already stale) |
| `NT SERVICE\SQLSERVERAGENT` | Windows service | SQL Agent jobs | system |

---

## Monitoring (Zabbix)

Cross-project reference (instance details, onboarding checklist, alert-routing, known bugs): `../docs/zabbix_observability.md`.

### SSL certificate expiration

Not monitored per-VM. Runs centrally on the **`Zabbix server`** host itself: one `log[]`-type active-check item per service, named `get_ssl_enddate_<service>` (e.g. `get_ssl_enddate_webservicecg` for `SFCG-WSCG-01`), each reading its own log file under `/var/log/zabbix/ssl_<name>.log` on the Zabbix server, each with its own independent set of 4 triggers. Tagged `cloud:Azure` / `component:SSL Cert` / `env:PROD`. Confirmed present for `webservicecg`, `webservicev2`, `website`, `smartfran`, `mobileappservice`, `fs-api`, `clubsite_ar`, `clubsite_py` (`GITIN-1961`, 2026-08-28). When auditing a VM's Zabbix onboarding for cert-expiry coverage, check the `Zabbix server` host, not the VM itself — its absence there is expected, not a gap.

---

## Known gap: no official housekeeping/maintenance window

**Flagged 2026-09-10 (`GITIN-1981`, `events/20260901_pnssrl_mantenimientoindices_review/`):** none of SmartPedidos, SmartLoyalty, or SmartCloud have an officially documented maintenance/housekeeping window. Every scheduling decision (e.g. `PNSSRL_MantenimientoIndices`'s reschedule) has to be derived from scratch by cross-referencing whatever constraints happen to be known at the time (POS active hours, backup schedules, one service's traffic profile) rather than checked against a defined standard. Cross-platform structural gap — not resolved here, flagged for whoever owns cross-project scheduling standards.

**Backup schedule (`SFCG-DB01`, `SmartFran.Solution.SmartLoyalty`) — confirmed 2026-09-21** (`events/20260920_cpu-spikes/`), via `msdb.dbo.sysjobschedules`/`sysschedules` for `Operaciones_MaintenancePlan_Backups.Backup_FULL`: **full backup runs Sunday/Monday/Wednesday at 06:00 GMT (03:00 local, UTC-3)**. A companion `Backup_Log` job runs daily starting at 00:00 GMT — frequency sub-interval (once/day vs. recurring intra-day) not checked, so treat as at least once daily, possibly more often. Avoid scheduling write-blocking maintenance (e.g. an offline index build) against those Sun/Mon/Wed morning windows.

---

## Scheduled Tasks (`SFCG-TO-01`)

**Superseded by `loyalty/docs/task_operator_tasks.md`** — this section is an older, partial version of that doc's exhaustive per-task inventory (schedule, query, `CustomerPointsLog` contention). Kept here for the CPU-investigation narrative below; use the other doc for current task/schedule reference.

**Correction 2026-08-03:** originally documented against `SFCG-DB01` — wrong host. All `Get-ScheduledTask`/`logman` output collected during `GITIN-1749` carried `\\SFCG-TO-01\...` counter/computer prefixes, confirming these commands ran on the TaskOperatorService app server, not the DB engine host. Makes sense in hindsight: application-level report/export scheduled tasks belong on the app server, not the raw SQL Server box.

Besides SQL Agent jobs on `SFCG-DB01`, `SFCG-TO-01` runs a Windows Task Scheduler folder **`\SmartFran\`** with ~50 custom application-level jobs (daily reports, surveys, promotion vigency checks, blob-storage exports, cleanup) — not previously documented. Discovered 2026-08-03 during `GITIN-1749` (`20260803_cpu_peaks_loadtest`) while investigating unexplained CPU peaks on `SFCG-DB01`; the peaks-2/3 root cause is **still unconfirmed** — these findings describe `SFCG-TO-01`'s own scheduled activity and the SQL traffic it generates against `SFCG-DB01`, not a direct OS-level cause on the DB host itself.

**Known clustering issue:** a group of tasks — `ReportUpdateCustomer` (~monthly), `ReportErrorSurveyNoResponse` (daily), `NotSamplesSurveyActivated` (daily), `Promotion Vigency Advisor B` (weekly), `Promotion Vigency Advisor C` (every 2 days) — happened to fire within a 30-minute window (12:00-12:30 GMT) on 2026-08-03, overlapping the chronic TaskOperatorService/`CustomerPointsLog` sync job (SPID 114/151, `sfsqlusr`@`SFCG-TO-01`, active ~12:06-13:06 GMT, itself running on the same host). Only 2 of the 5 are actually daily — the overlap that day was partly coincidental. Contributed to a routine CPU peak at local business-day-start (~09:00 UTC-3), which shows up in two consecutive load-test CPU investigations (`20260727_cpu_peaks_loadtest` — ticket unconfirmed, previously mis-cited as `GITIN-1669`, which actually belongs to an unrelated blocking-incident event; and `GITIN-1749`) even though unrelated to the load test itself. Reschedule tracked in `GITIN-1753` (`20260804_reschedule_smartfran_tasks`) — **closed**, but via disabling 4 different tasks than originally planned here (`ReportErrorSurveyNoResponse`, `NotSamplesSurveyActivated`, `ReportSurveyUnsatisfied`, `ReportSampleMailResponseXSurvey`), not a reschedule of the 5 tasks named above; `ReportUpdateCustomer` remains on its original 12:00 UTC schedule, unresolved. This paragraph's task list/mechanism is stale — see that event's `investigation.md` for the real closure.

**Also on `SFCG-TO-01`:** `Check_list_SF` (checks TaskOperatorService is running, fires every 5 min anchored at :00 — lands exactly on :15/:45 past the hour), `Clean Mistery` (`ServicesAndTaskStatus.ps1` + `FreeMistery.ps1`, every 30 min), `RunExportsCustomersFails` (hourly), `SendCanjesSocioCortesiaToBlobStorage`/`SendDetalleCanjesSocioCortesiaToBlobStorage` (every 30 min, blob uploads). These run locally on `SFCG-TO-01` — their own script CPU cost lands there, not on `SFCG-DB01`, so they can't directly explain `SFCG-DB01`'s OS-level CPU graph unless they drive heavy query load on the DB engine (already measured as low, ~6% max — see `GITIN-1749`).

To re-check current schedule (times drift as tasks get rescheduled — don't rely on this doc for exact current times):
```powershell
Get-ScheduledTask -TaskPath '\SmartFran\' | ForEach-Object {
    $info = $_ | Get-ScheduledTaskInfo
    [PSCustomObject]@{ TaskName = $_.TaskName; LastRunTime = $info.LastRunTime; NextRunTime = $info.NextRunTime }
} | Sort-Object LastRunTime
```

Full task list and timing snapshot as of 2026-08-03: see `events/20260803_cpu_peaks_loadtest/20260803_cpu_peaks_loadtest_investigation.md`.

---

## Databases

| Database | Purpose | Query scope |
|---|---|---|
| `PNSSRL` | Monitoring — index maintenance captures, blocking info, tempdb usage, CPU/memory captures | Default target for DBA investigation queries (`/loyalty-dba-investigation`) |
| `SmartFran.Solution.SmartLoyalty` | Production — points, customers, sales, promotions, fraud investigation surface | Query only when explicitly requested or via a skill granting implicit access (e.g. `/loyalty-fraud-points`) |

Read-only access only — never DML/DDL against either database.

### Schema reference — `SmartFran.Solution.SmartLoyalty` (confirmed by query 2026-09-30, `SFCG-DB01`, GITIN-2132)

**`Sml.Customer` columns** (real names, including the misspellings): `Id` (uniqueidentifier), `FormDate` (datetime), `CreatedDate` (datetimeoffset, NOT NULL), `UserId`, `EnrolledId` (NULL), `RegisterById`, **`DeativatedDate`** (datetimeoffset, NULL), **`DeativateNote`** (nvarchar(max), NULL), `ArchivedForm` (datetimeoffset, NULL), `NonMandatoryData` (bit), `Country_Id` (int, NOT NULL), `RegistrationChannel` (nvarchar(max), NULL). Column id 11 is absent (a dropped column). There is no `DeactivatedDate`/`DeactivateNote` — the spelling in `v3.0.0.md` is the wrong one; use `DeativatedDate`. Active customer = `DeativatedDate IS NULL`.

**Countries** (`Sml.Location`, `LocationTypeCode = Country`): `1` Argentina, `9` Paraguay. Active customers 2026-09-30: country 1 = 6,232,739; country 9 = 118,902 (only these two countries have active customers).

**Insignia feature (v13.00.00):** on 2026-09-30 no `%Insignia%` table existed in this database, so the v13 EF migrations (source: `origin/test02` of `loyalty/repo/dev-src-sol-smartloyalty`, `Core/Data/Migrations`, run by `Front/MigrateDatabase`) had not been applied. Deployment SQL lives in `Other/SqlScript/Updates/v13.00.00/`; its transition-rule seed covers Argentina only.

---

## Network / Azure Placement

SmartLoyalty's VMs and networking sit on the **Smart IT - Grido** subscription, distinct from the **SmartIT Cloud** subscription (`85c76dea...`) that hosts SmartFran Cloud (see `cloud/docs/infrastructure.md` — do not confuse the two).

| Resource | Value |
|---|---|
| Resource group (prod) | `DefaultGroup01` |
| VNet (prod) | `sfcgvnet01` (`192.168.0.0/16`) |
| Resource group (dev/staging) | `SFCG-REGR-DEV` |
| VNet (dev) | `SmartFran-vnet` (`10.2.0.0/16`) |
| Azure AD DS domain | `smartit.azure` |
| AADDS DC subnet | `192.168.40.0/24` |
| AADDS DC IPs | `192.168.40.4`, `192.168.40.5` |

### Host naming convention and IP-range allocation (prod subnet `192.168.50.0/24`)

Source: `~/Documentos/git/smartfran/ope-documentation/infrestructura-azure/infrastructura-azure.txt` (dated 2023-10-13, undocumented in `bots/` until now — folded in 2026-08-21 since every live IP confirmed this session/prior sessions fits it exactly).

Hostnames follow `SFCG-<SVC>-<NN>` (e.g. `SFCG-WEBS-01` = SmartFran/Club Grido WebService, instance 1). IPs within `192.168.50.0/24` are pre-allocated in ranges by service:

| Range | Service | Confirmed live examples |
|---|---|---|
| `.101`–`.110` | Webservice | — |
| `.111`–`.120` | Mobile | `SFCG-MOBI-01` (`.111`), `SFCG-MOBI-02` (`.112`) |
| `.121`–`.130` | Clubsite | `SFCG-CLUB-01` (`.121`), `SFCG-CLUB-02` (`.122`) |
| `.131`–`.140` | Website | `SFCG-WSIT-01` (`.131`) |
| `.141`–`.150` | Task Operator | — |

DNS: the `clubgrido.com.ar` zone is delegated to SmartFran's GoDaddy account.

Full NSG rules, VNet peering, and private endpoint inventory: `../docs/azure_nsg.md` (repo-root shared reference — covers both `sfdev02-nsg` and `sfcgnetsec01`).

---

## Multi-brand Platform Scope

SmartLoyalty hosts multiple franchise brands on the same DB instance:

| Brand | Registration identifier |
|---|---|
| Club Grido | `GRIDO*`, `GR*` branch codes |
| Mundo Helado | `MDOH*` branch codes |

---

## Source Code Reference

A local read-only clone of the SmartLoyalty WebSite/WebService application source is available at `loyalty/repo/dev-src-sol-smartloyalty/` (`.gitignore`d via the repo-root `**/repo/` pattern — present locally, not committed). Use for architecture/root-cause lookups only, never as a deploy target.

**Confirmed relevant path (2026-07-21):** `Front/WebSite/Controllers/CatalogController.cs` — `SetListCatalog` action and its call into `Core/Domain/Domain/CustomerContext/CustomerService.cs` (`GetCustomerAvailable`) were traced to a confirmed N+1 query root cause during a WAF/backend-timeout investigation. See `operations/events/20260721_gestion_clubgrido_waf_504/` for the full trace.

**Confirmed relevant paths (2026-09-14, GITIN-2036):** `Front/TaskOperatorService/TaskOperatorService.cs` — the actual `Sch.Job`/`Sch.TimeTable` scheduling engine host (`ThreadOperator` → `scheduleSvc.RunSchedule`); confirmed `task.TimeTable` is a singular property (no multi-schedule-per-job support). `Core/Application/Service/MktCampaignContext/MktAsignationPointActionService.cs` (`DoPointAssignationAction`) and `Core/Domain.Query/Domain/Query/Query084-sql.xml` — confirmed the campaign point-assignment engine is idempotent (dedup against real `CustomerPointsLog` data, not just a watermark). Note: the core scheduling *engine* implementation (`SmartFran.Business.Schedule.Service.ScheduleContext.ScheduleApplicationService`, referenced throughout exception stack traces) is **not** in this clone — it lives in a separate shared library. See `events/20260914_taskoperator_mktcampaign537_errors/investigation.md` for the full trace.

## Related

- Skills: `/loyalty-dba-investigation`, `/loyalty-fraud-points`, `/loyalty-fraud-pos`, `/loyalty-azure-nsg`, `/loyalty-azure-waf` — investigation workflow and query patterns for this infrastructure.
- `../docs/azure_nsg.md` — NSG/VNet/AADDS detail, shared across projects on this subscription.
- `../docs/graylog_infrastructure.md` — the Docker Graylog/OpenSearch stack shared with SmartPedidos, including the `SFCG-SMTP-01`/`-02` mail relay hop.
- `../docs/zabbix_observability.md` — cross-project Zabbix reference: host onboarding checklist, SSL cert monitoring architecture, the IIS request-rate tiered-alert pattern, alert-routing/action status, known Agent 2 bugs.
- `memory/` — persistent fraud actor memory (known hubs, relays, POS actors), not infrastructure.

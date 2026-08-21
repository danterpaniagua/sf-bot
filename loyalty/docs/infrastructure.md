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
| `SFCG-WEBS-01/02/03` | WebService (`C:\SmartFran\SmartLoyalty.WebService\`) |
| `SFCG-WSV2-01` | WebServiceV2 (`D:\SmartLoyalty.WebServiceV2\`) — `Standard_D8as_v5`, `eastus` |
| `SFCG-WSV2-02` | WebServiceV2 (`D:\SmartLoyalty.WebServiceV2\`, assumed same path — not yet verified) — `Standard_D2ds_v4`, `eastus`. **Confirmed live 2026-07-27** via `az vm show`, was missing from this doc entirely. Was powered on for ~3 days before being deallocated 2026-07-27 — not "never on". Currently **deallocated**, no confirmed real use during that window. In practice WebServiceV2 has run on a single actively-used server (`-01`) — same single-point-of-failure pattern as `SFCG-WSIT-01`; `-02` never provided real redundancy despite billing compute the whole time. |
| `SFCG-WSIT-01` | WebSite (`D:\SmartLoyalty.WebSite\`) — public ingress via Application Gateway WAF `WAF_APPs` (`DefaultGroup01`), single backend server, no redundancy. See `/loyalty-azure-waf` skill for listener/pool detail |
| `SFCG-MOBI-01/02` | MobileAppService — ASP.NET MVC/WebApi on .NET Framework 4.x, IIS (requires VM, not App Service PaaS), DMZ subnet, resource group `DefaultGroup01`, subscription **Smart IT - Grido**. Public ingress via Azure **Standard** Load Balancer `SFCG-MOBI-LB` (same RG) — **not** a direct VM public IP; `20.121.19.174` (static) is the LB's public IP (`SFCG-MOBI-LB-publicip`), previously misattributed directly to `SFCG-MOBI-01`'s NIC in this doc. Single LB rule `SFCG-MOBI-LB-lbrule02`: TCP 8043→8043, `idleTimeoutInMinutes=15`, backend pool `SFCG-MOBI-LB-backendpool01`. **Confirmed 2026-08-21** (`GITIN-1909`) via `az network lb address-pool list`: backend pool contains both `sfcg-mobi-01421` and `sfcg-mobi-02639` NICs — `SFCG-MOBI-02` is live and in rotation, not just `-01`. Health probe `SFCG-MOBI-LB-probe02` (plain TCP, port 8043, 5s interval, **`numberOfProbes=1`**) is the only probe actually attached to the live rule — a single missed check pulls a backend from rotation, unusually aggressive vs. Azure's typical ≥2 recommendation. Two other probes exist (`SFCG-MOBI-LB-probe01` HTTP `/api/MobileAppService/CheckServiceStatus`; `healthcheck.ashx` HTTPS `/healthcheck.ashx`) but are **not** referenced by any current rule — orphaned/legacy, not verified in use. No WAF/Application Gateway in front of MobileAppService — `WAF_APPs` exists in the same RG but fronts WebSite/ClubGrido only (confirmed 2026-08-21, `GITIN-1909`). Ingress path is client → NSG (**one-to-one source-IP allow-list**, not subnet-based) → `SFCG-MOBI-LB` → IIS — no L7 device anywhere in the path. Full detail: `events/20260821_mobileappservice_loadtest_503/`. |
| `SFCG-WSCG-01` | CG web service |
| `SFCG-CLUB-01/02` | Club Grido website — `192.168.50.121`/`.122` (confirmed via `az network nic list`, 2026-08-07). Public ingress via Application Gateway WAF `WAF_APPs` (`DefaultGroup01`), backend pool `Back_ClubSite` (`www.clubgrido.com.ar`) — same two servers also back `Back_ClubSite_PY` (`www.clubgrido.com.py`), no separate PY-specific backend. `WAF_APPs` has no `urlPathMaps` — host-based routing only. See `operations/docs/waf_apps_cert_automation_runbook.md` for the cert-automation work in progress on this gateway. |
| `SFCG-TO-01` | TaskOperatorService (`E:\SmartLoyalty.TaskOperatorService\`) |
| `SFCG-DB01` | SQL Server host (see Database Server below) |
| `SFCG-SMTP-01`/`SFCG-SMTP-02` | hMailServer outbound mail relay — `192.168.50.161`/`.162`. WebServiceCG's `AccountRecovery` endpoint (and other app-triggered emails) go app → hMailServer (these hosts) → `smtp.sendgrid.net` → recipient. Confirmed 2026-08-11/12 during `GITIN-1816`. NXLog on both ships delivery logs (tag `SF-SMTPRL`) to the Graylog stack shared with SmartPedidos — see `../../docs/graylog_infrastructure.md`. |
| `LUCAS-KIUVI` | QA workstation — must not connect to production |

### Database accounts

| Account | Type | Used by | Role on SmartLoyalty |
|---|---|---|---|
| `SMARTIT\itservices` | Windows domain | All app servers | cross-role (not audited) |
| `sfsqlusr` | SQL login | TaskOperatorService (SFCG-TO-01) | `db_owner`, `db_securityadmin` ⚠️ over-privileged |
| `sfsqlusrit` | SQL login | QA / SSMS (LUCAS-KIUVI) | `db_owner`, `db_securityadmin` ⚠️ over-privileged |
| `NT SERVICE\SQLSERVERAGENT` | Windows service | SQL Agent jobs | system |

---

## Scheduled Tasks (`SFCG-TO-01`)

**Correction 2026-08-03:** originally documented against `SFCG-DB01` — wrong host. All `Get-ScheduledTask`/`logman` output collected during `GITIN-1749` carried `\\SFCG-TO-01\...` counter/computer prefixes, confirming these commands ran on the TaskOperatorService app server, not the DB engine host. Makes sense in hindsight: application-level report/export scheduled tasks belong on the app server, not the raw SQL Server box.

Besides SQL Agent jobs on `SFCG-DB01`, `SFCG-TO-01` runs a Windows Task Scheduler folder **`\SmartFran\`** with ~50 custom application-level jobs (daily reports, surveys, promotion vigency checks, blob-storage exports, cleanup) — not previously documented. Discovered 2026-08-03 during `GITIN-1749` (`20260803_cpu_peaks_loadtest`) while investigating unexplained CPU peaks on `SFCG-DB01`; the peaks-2/3 root cause is **still unconfirmed** — these findings describe `SFCG-TO-01`'s own scheduled activity and the SQL traffic it generates against `SFCG-DB01`, not a direct OS-level cause on the DB host itself.

**Known clustering issue:** a group of tasks — `ReportUpdateCustomer` (~monthly), `ReportErrorSurveyNoResponse` (daily), `NotSamplesSurveyActivated` (daily), `Promotion Vigency Advisor B` (weekly), `Promotion Vigency Advisor C` (every 2 days) — happened to fire within a 30-minute window (12:00-12:30 GMT) on 2026-08-03, overlapping the chronic TaskOperatorService/`CustomerPointsLog` sync job (SPID 114/151, `sfsqlusr`@`SFCG-TO-01`, active ~12:06-13:06 GMT, itself running on the same host). Only 2 of the 5 are actually daily — the overlap that day was partly coincidental. Contributed to a routine CPU peak at local business-day-start (~09:00 UTC-3), which shows up in two consecutive load-test CPU investigations (`GITIN-1669`, `GITIN-1749`) even though unrelated to the load test itself. Reschedule tracked in `GITIN-1753` (`20260804_reschedule_smartfran_tasks`).

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

## Related

- Skills: `/loyalty-dba-investigation`, `/loyalty-fraud-points`, `/loyalty-fraud-pos`, `/loyalty-azure-nsg`, `/loyalty-azure-waf` — investigation workflow and query patterns for this infrastructure.
- `../docs/azure_nsg.md` — NSG/VNet/AADDS detail, shared across projects on this subscription.
- `../docs/graylog_infrastructure.md` — the Docker Graylog/OpenSearch stack shared with SmartPedidos, including the `SFCG-SMTP-01`/`-02` mail relay hop.
- `memory/` — persistent fraud actor memory (known hubs, relays, POS actors), not infrastructure.

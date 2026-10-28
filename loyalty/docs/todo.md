# Loyalty — TODO

Open work of this project. One entry per piece of work, each with the tickets it spans. When an item is done, record the resulting fact in the doc it belongs to (`infrastructure.md`, `certificates.md`, ...) and delete the entry here. State below was read from the event folders and docs, not re-measured; commands are copy-paste blocks for the user, output saved to the event's `data/`.

Order: 1 (indexes, the only production database change) → 2 (SSL) → 3 (IIS spike) → 4 (Sunday backup, before fixing the index window).

## 1. SQL indexes on `Sml.CustomerPointsLog`

Tickets: [GITIN-2250](https://smartit-ar.atlassian.net/browse/GITIN-2250) (parent), [GITIN-2266](https://smartit-ar.atlassian.net/browse/GITIN-2266) "[SML] Nuevo indice + esquema de mantenimiento", [GITIN-2267](https://smartit-ar.atlassian.net/browse/GITIN-2267) "[SML] Analisis de indices: IX_CustomerPointsLog_Points". Events: `events/20261020_gitin2266-nuevo-indice-esquema-mantenimiento/`, `events/20261020_gitin2267-analisis-indices-customerpointslog-points/`, `events/20261018_gitin2251-webs-db-misma-ventana/`. Nothing run yet.

Target `SmartFran.Solution.SmartLoyalty`, table of ~404 M rows, 16 yearly partitions (`sch_LogDate_Anual`), `LogDate` datetimeoffset GMT.

**1a. GITIN-2267, read-only analysis of `IX_CustomerPointsLog_Points`**
1. Confirm which table: `Sml` (10 GB, 338 seeks, 0 scans, 1,214,569 updates since 2026-10-14) or `SmlSt` (97 MB, 9,018 seeks); the large one is assumed.
2. Read the raw `sys.index_columns` rows (`key_ordinal`, `partition_ordinal`, `is_included_column`) of the index: the partition column prints first and is not a leading key.
3. Re-read `sys.dm_db_index_usage_stats` (counters reset at service start) and find the queries that use `Points` (Query Store is off; plan cache only).
4. Decision paper: keep, replace or drop (a drop frees 10 GB and removes update cost); write the rollback (`CREATE INDEX` with the exact definition).

**1b. GITIN-2266, new index and maintenance schedule**
1. Define the index from the GITIN-2251 lead: `CustomerId` key with `Points` included (the trigger `[Sml].[CustomerPointsLogAfterInsert]` sums `Points` by `CustomerId` through key lookups). Not a decision: first show the cost matters (the customers sampled have 500-1,200 rows, cheap).
2. Decide partition-aligned or not, size (`IX_CustomerId` is 7.4 GB), write cost at 500-700 inserts/min at peak, window, approver and rollback (`DROP INDEX`). Standard edition has no online index build.
3. Add the index to the maintenance schedule (`PNSSRL_MantenimientoIndices`, step 2 and failure/retry mitigation in `task_operator_tasks.md`; its daily sweep skips `Sml.CustomerPointsLog`). Avoid `Backup_FULL` (Sun/Wed/Fri 09:00 GMT, 7-8 min) and check item 4.
4. Save every query and DDL to the event's `scripts/scripts.sql`; apply with the state-changing banner; verify with an actual-plan check of the trigger statement; update `infrastructure.md`.

The parent GITIN-2250 also holds open items of its 2026-10-18 follow-up (WEBS-02 saturation cause, healthcheck handler depending on one 500 ms sample, dashboard 337 units): see that event's `investigation.md`, not part of this entry.

## 2. SSL automation for WebServiceV2 and WebServiceCG

Tickets: [GITIN-1772](https://smartit-ar.atlassian.net/browse/GITIN-1772) (WebServiceV2, `SFCG-WSV2-01/-02`), [GITIN-1773](https://smartit-ar.atlassian.net/browse/GITIN-1773) (WebServiceCG, `SFCG-WSCG-01`). Events: `operations/events/20260913_automatizar_webservicev2/`, `operations/events/20260913_automatizar_webservicecg/`. State after 2026-09-13 not read.

Pattern: `operations/docs/mobileappservice_ssl_renewal_runbook.md` (own certificate per VM, Windows store + IIS binding, win-acme DNS-01 through Azure DNS, no Key Vault). Done on 2026-09-13 for both: DNS zone `_acme-challenge.<host>`, SP role, GoDaddy NS delegation (`pdns11`/`pdns12`), `dig`-verified.
1. Read the two events to the end.
2. GITIN-1772: win-acme on `SFCG-WSV2-01`, then `-02` independently (behind `SFCG-WSV2-LB`, L4, each VM terminates TLS): issue, IIS binding, scheduled renewal, verify the public endpoint dates on both VMs. Rollback is the previous binding.
3. GITIN-1773: same on the single node `SFCG-WSCG-01` (`bot-security.smartfran.com`, user-stated). It replaces a paid `*.smartfran.com` wildcard: find every place that wildcard is bound (blast radius not checked) and keep it until none depends on it.
4. Zabbix: the SSL-expiry items must read the new certificates (a `0` from the expiry script keeps the High tier open, GITIN-2249); the web scenarios run with `verify_peer` off and never catch a certificate fault.
5. Update `certificates.md` (status rows and the stale "In progress" text).
6. **Final SSL automation report** (user, 2026-10-28), one report for the whole SSL automation work (WebSite GITIN-1771, MobileAppService GITIN-1774, ClubSite AR GITIN-1770, WebServiceV2 GITIN-1772, WebServiceCG GITIN-1773), written in two stages:
   - **Stage 1, after the automation is configured:** per certificate, the mechanism (win-acme DNS-01 through Azure DNS, or Key Vault + Application Gateway behind `WAF_APPs`), host/VM, the issued certificate and its dates, the IIS binding or listener, the scheduled renewal task and its next run, the Zabbix SSL-expiry items and tiers (including the `:LE` 15/10/7 context), rollback, and what is still manual. Evidence from the runbooks (`operations/docs/waf_apps_cert_automation_runbook.md`, `operations/docs/mobileappservice_ssl_renewal_runbook.md`) and the events.
   - **Stage 2, after the automation has run:** whether each scheduled renewal actually ran without intervention (task last run and result, new `notAfter` date on the public endpoint on every VM behind a load balancer, Zabbix item reading and no stale High problem), the failures hit and their fixes. A configured task that has not yet run is not an automated renewal: state that explicitly per certificate until the first renewal happened (win-acme renews in the last ~30 days of a 90-day certificate, so this stage can only be written after that window).
   - Open points to carry: the Paraguay backend certificate (due 2026-09-15, check it was handled), the `*.smartfran.com` wildcard replaced for WebServiceCG, `SFCG-MOBI-02`'s nightly shutdown and the `Start_Mobile02_11AM` Logic App (the task runs through `StartWhenAvailable`). Written once per stage from `investigation.md`'s state, the `ope-sre-output` way; never claim "automated" or "renewed" without the evidence of that stage.

## 3. IIS WebService spike configuration

Ticket: [GITIN-2316](https://smartit-ar.atlassian.net/browse/GITIN-2316). Event: `events/20261026_gitin2316-sml-spikes-webservice/` (`outputs/propuesta.md` holds the options).

Today: Dynamic IP Restrictions on `SFCG-WEBS-01` only, log-only (100 requests per 1,000 ms; legitimate peak 5 req/s per address); backup `before-gitin2316-dynip`; nothing blocks.
1. Open questions: is `181.116.88.166` an office line or an authorised test; did the scan continue after 22:00 UTC-3 (`scripts/scripts-c3b.ps1`); what do `\config` and `\service` serve.
2. Decide (user): blocking mode on WEBS-01 then WEBS-02 and WEBS-03; NSG deny for the address; request filtering (hidden segment `config`, denied extensions); rate limit or WAF in front of the load balancer.
3. Apply per host with the banner and a backup; test with a controlled burst; check sub-status 502 in the IIS log and that 5 req/s per address passes.
4. Update the GET path scan paragraph in `infrastructure.md`.

## 4. Unexplained Sunday full backup on `SFCG-DB01`

Found 2026-10-28 in `msdb` (`operations/events/20261027_documentation-compaction/data/backup-full-schedule-20261028.txt`): besides `Backup_FULL`, every Sunday (10-04, 10-11, 10-18, 10-25) all five databases get a second full backup (`type = 'D'`) at about 11:31-11:41 GMT lasting 0 minutes; no job named Backup is scheduled then.
1. Run `operations/events/20261027_documentation-compaction/scripts/sunday-backup-source.sql` (read-only: `is_copy_only`, `user_name`, `software_name`, `machine_name`, `device_type`, device name, sizes); save the output to `data/`.
2. A copy-only backup to a `VIRTUAL_DEVICE` (device type 7) points to a snapshot/backup agent outside SQL Agent (find its owner at host level); a normal backup under a login points to a job or a person.
3. A copy-only backup leaves the differential base alone; a non-copy-only full backup changes it. No differential job was seen in the inventory (not checked).
4. Record the finding in `task_operator_tasks.md` § 4 and `infrastructure.md`; keep it out of the item 1 window unless it overlaps the index build.

## 5. MobileAppService campaign readiness (drafted from the events, not confirmed by the user)

Tickets: [GITIN-1909](https://smartit-ar.atlassian.net/browse/GITIN-1909), [GITIN-2053](https://smartit-ar.atlassian.net/browse/GITIN-2053), related GITIN-1981 / GITIN-2112 (index maintenance). Events: `events/20260821_mobileappservice_loadtest_503/`, `events/20260915_mobileappservice_loadtest_errors/`. Record: `infrastructure.md` → "MobileAppService under Grido traffic".
- Install the performance-counter Data Collector Set (`SmartFran_MobileAppService_Perf`: CPU, request queue, thread pool) on both VMs before the next high-traffic campaign; no historical counters exist, so the ~2,650 no-status failures of 2026-09-15 cannot be diagnosed.
- The TCP-only LB probe (`numberOfProbes=1`) and the startup gap it causes (9 + 14 real 503s on two MOBI-02 starts): the `GITIN-1228` probe migration may have changed it, so read the live rule first; `CleanCSVLogs` still runs `iisreset` at every MOBI-02 start ("At startup" trigger), so start MOBI-02 outside traffic peaks or change the task.
- Confirm the LB distribution mode (`az network lb rule show` on `SFCG-MOBI-LB-lbrule02`) and a per-backend `DipAvailability` split to explain the 1.4 % / 98.6 % skew between MOBI-01 and MOBI-02.
- Ask Grido for its error classification (are transport resets reported as "503"?), the `instance` field meaning, the real campaign send window, and for the retry-on-fresh-connection behavior against the deliberate 15 s `connectionTimeout`; confirm with the owner that 15 s is deliberate hardening and re-read its current value.
- Attribute the Azure Automation identity that deallocates MOBI-02 nightly (`az ad sp show` on the caller GUID in `data/sfcg-mobi-02_activitylog_24h.txt`); confirm the VM clock/timezone (the events assume UTC).
- Security: the `Password` field in MobileAppService `LoginSuccess` events reaches Graylog in clear text; decide on a ticket. The daily `.svclog` deletion and the PII in `httperr.log` URLs are related.
- The index-maintenance window (`PNSSRL_MantenimientoIndices`, GITIN-1981) is item 1 / `task_operator_tasks.md`.

## 6. Documentation leftovers

Loyalty events not validated against the docs: validated 2026-10-28: the load-test and CPU events (2026-07-15, 07-23, 07-27, 08-03, 08-21, 09-15), `20260923_gitin2099` and `20261016_unity-config-consistencia-zabbix`; `zabbix_alert_matrix.md` is a snapshot of 2026-10-18.

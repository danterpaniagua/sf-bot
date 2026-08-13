# Investigation — 20260727_cpu_peaks_loadtest

**Status:** converged — ticket written (`20260727_cpu_peaks_loadtest_ops.md`), closed

## Confirmed facts
- User observed DB CPU peaks during a Grido load test on 2026-07-27: two peaks around 50% and one peak at 100%.
- Reported window: 08:00–11:00 UTC-3 (2026-07-27) → 11:00–14:00 GMT (SFCG-DB01 server time).
- Jira ticket: [GITIN-1669](https://smartit-ar.atlassian.net/browse/GITIN-1669)

## Current working theory
Not a repeat of the 2026-07-23 blocking incident — `blocked = 0` on every row in the window, no lock contention. Instead, SPID 151 (login `sfsqlusr`, host `SFCG-TO-01` / TaskOperatorService) ran a paginated OFFSET/FETCH extraction over `Sml.CustomerPointsLog` join `Sml.Customer` continuously from 11:01 to 13:16 GMT, consuming ~200,000-290,000 CPU-ms per 5-min snapshot (near-saturating one core, wait type mostly `SOS_SCHEDULER_YIELD`). Q4 confirms this same job (by login+host+query pattern) runs on nearly every day in the 90-day retention window, so it is routine, not something the load test triggered.

**Revised as of Q3 result:** server has 16 logical cores (`cpu_count=16`, `scheduler_count=16`). One session saturating a single core is only ~6% of total 16-core capacity — nowhere near the reported 50%/100% peaks. SPID 151 alone cannot be the (sole) explanation for peaks of that magnitude on this hardware. Need Q5 (sum of CPU delta across ALL sessions per snapshot, normalized to 16-core capacity) to see whether the peaks come from many concurrent sessions adding up, or from something not captured in the per-SPID top-50 view at all (e.g. parallelism inflating one session's reported cpu-ms beyond single-core wall-clock, or the monitored "CPU" metric not being normalized the same way as this capacity math assumes).

## Ruled out
- Different-machine theory (Zabbix host `SFCG-DB01`/hostid 10611 displaying as "Loyalty DB CLON" being a genuinely separate clone instance from what the SQL captures were pulled from) — confirmed by user: hostid 10611 is production despite the confusing "CLON" display name; hostid 10675 (`SFCG-DB01-CLON`) is the real test clone, mostly shut down. Same machine as the SQL capture data all along. (Tangential finding: the misleading Zabbix display name on the prod host is worth a note in `docs/`, out of scope for this ticket.)
- 2026-07-23-style blocking chain (SPID vs SPID via `blocked` column) — `blocked=0` throughout the 2026-07-27 window (Q2).
- SPID 151 / TaskOperatorService sync job as sole cause of 50-100% peaks — magnitude doesn't fit on a 16-core box (see revised theory above). Still worth flagging as a chronic CPU consumer regardless of whether it's the peak driver.

## Current working theory (revised again)
Zabbix hostid 10611 (technical name `SFCG-DB01`) only carries MSSQL-instance-level counters (via `db.odbc.get`/ODBC, no local agent OS metrics) — confirmed via full item.get dump, zero `system.cpu.util`-style items present. Per user: the actual OS/VM hosting the database is tracked under a **separate Zabbix host object**, distinct from `SFCG-DB01`, which is where the "CPU Utilization" graph the user is reading actually lives. This fully explains why the SQL-capture-table CPU totals (Q5, ~4-6% throughout the window) never matched the reported 50%/100% peaks — they were never measuring the same layer (SQL Server session-level `cpu` counter vs. OS-level Windows CPU utilization on a differently-named host). Per user: the OS-level CPU graph lives on a **separate, old/unmigrated Zabbix server** (internal IP `172.173.191.212`), not on `sf-monitoreo.smartfran.com` (the instance used for the Facturasend investigation and all API lookups so far in this session). No API token available for this legacy instance — user reported the graph values manually instead:

| UTC-3 | GMT | Item | Value |
|---|---|---|---|
| ~08:00 | ~11:00 | CPU User Time | smaller peak |
| ~09:00 | ~12:00 | CPU User Time | smaller peak |
| 10:00–12:00 | 13:00–15:00 | CPU Utilization | 50% plateau |
| 10:30–11:30 | 13:30–14:30 | CPU User Time | **100% peak** |

Original SQL query window (11:00-14:00 GMT) undershoots the real peak window — it barely overlaps the start of the 13:30-14:30 GMT 100% peak (only 13:30-13:56 GMT captured) and doesn't cover the 50% plateau's tail (14:00-15:00 GMT) at all. Needs re-running with an extended window.

**Critical finding so far:** for the portion of the 100% peak that *was* captured (13:30-13:56 GMT), total SQL-session CPU across all sessions (Q5) is ~0% — lower than the pre-peak baseline. This is the opposite of what a query-driven CPU spike would look like. Working theory shifting away from "a SQL query/session is the cause" toward: a non-SQL-Server process on the same Windows VM (AV scan, backup/VSS snapshot, OS task), or a SQL Server background/system thread not attributable to a normal user session (checkpoint, lazy writer, ghost cleanup — low system SPIDs, may not have surfaced in the top-50-by-user-session view). Needs the extended window + explicit check of low/system SPIDs to confirm.

## Open questions / next steps
- Run data availability check on `PNSSRL_AuditSysprocesses` for 2026-07-27 11:00–14:00 GMT. — done (Q1, 36 snapshots).
- Run CPU delta per SPID between consecutive snapshots to locate the responsible session(s) for each of the three peaks. — done (Q2), but see revision above.
- Check for a blocking chain (`blocked` column) during the peaks — done, ruled out (Q2).
- Confirm server core count to size single-session CPU against total capacity — done (Q3, 16 cores).
- Confirm whether the TaskOperatorService/CustomerPointsLog job is routine or load-test-triggered — done (Q4), it's routine/daily.
- **Pending:** sum CPU delta across all sessions per snapshot (Q5) to find which timestamps actually cross 50%/100% of 16-core capacity, and what's driving those totals (single job vs. many concurrent sessions vs. a metric-normalization mismatch).
- Confirm whether the 2026-07-23 proposed action ("coordinate load test schedule with index maintenance window") was ever implemented — likely moot now that 07-23 was ruled out as the pattern here, but still an open action item from that ticket independently.

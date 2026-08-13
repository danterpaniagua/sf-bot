# Investigation — 20260803_cpu_peaks_loadtest

**Status:** converged — ticket written (`20260803_cpu_peaks_loadtest_ops.md`, GITIN-1749), closed

## Confirmed facts
- User observed DB CPU ("User Time") peaks during a Grido load test on 2026-08-03: one peak ~09:30–10:00 UTC-3, another ~14:00–15:00 UTC-3.
- Reported window (GMT, SFCG-DB01 server time): 12:30–13:00 GMT and 17:00–18:00 GMT.
- Source confirmed by user: same legacy/unmigrated Zabbix instance as `20260727_cpu_peaks_loadtest` — **no migration done** since that investigation.
- Jira ticket: [GITIN-1749](https://smartit-ar.atlassian.net/browse/GITIN-1749)
- Related prior ticket `20260727_cpu_peaks_loadtest`: [GITIN-1669](https://smartit-ar.atlassian.net/browse/GITIN-1669)

## Zabbix graph data (screenshots, legacy instance, local axis UTC-3)
Two screenshots saved in this event folder:
- `WhatsApp Image 2026-08-03 at 15.51.59.jpeg` — narrow window 12:51–15:51 UTC-3.
- `WhatsApp Image 2026-08-03 at 16.01.03.jpeg` — wide window 09:00–16:00 UTC-3, covers **both** reported peaks in one graph. Same dataset (max 92.6873% matches exactly across both).

"Prod Database: CPU usage with Cores" (wide window):
- **CPU user time [max]**: last 37.00%, min 0.387%, avg 14.55%, **max 92.69%**.
- CPU privileged time negligible (max 4.88%).
- Number of cores = 16 (confirms same server as 07-27).
- Visible spikes: one ~10:00 local (matches first reported peak 09:30-10:00 UTC-3 → ~13:00 GMT), two more ~14:15 and ~14:45 local (second reported peak 14:00-15:00 UTC-3 → ~17:15/17:45 GMT).

"Prod Database: CPU utilization with Cores" (wide window):
- **CPU utilization [avg]**: last 10.22%, min 2.24%, avg 8.71%, max 42.40%. Lower magnitude than "CPU user time" — same metric-naming split seen in 07-27 (OS "CPU Utilization" vs. "CPU User Time" as distinct Zabbix items).

Both reported peaks are now visually confirmed on the legacy Zabbix graph. Original GMT query window (12:00–18:30 GMT) already covers all three spikes (~13:00, ~17:15, ~17:45 GMT).

## Query results (2026-08-03, GMT)

**Q1 — data availability:** full coverage, ~12 snapshots/hour, 12:01–18:26 GMT. No gaps.

**Q2 — top-50 CPU delta by SPID:** dominated by SPID 114 (`sfsqlusr`, host `SFCG-TO-01`, TaskOperatorService) running the same paginated `CustomerPointsLog`/`Customer` OFFSET/FETCH sync job seen as SPID 151 in `20260727_cpu_peaks_loadtest` — active ~12:06–13:06 GMT (~09:06–10:06 UTC-3), deltas ~216,000-304,000 CPU-ms per 5-min snapshot (near-saturating one core). **Unlike 07-27, this job's active window does overlap the first reported peak (09:30-10:00 UTC-3).** Everything else in the top 50 is routine `SMARTIT\itservices` web-tier traffic from `SFCG-WEBS-01/02/03` (ASYNC_NETWORK_IO / MISCELLANEOUS waits, EF-generated catalog queries), tens of thousands of ms — normal load, not spikes.

**Q3 — total CPU across all sessions per snapshot, vs. 16-core capacity:** never exceeds **~6.3%** of capacity, even during SPID 114's activity (12:06-12:56 GMT). Drops to ~0% (with some negative-delta artifacts from CPU counter resets on reused SPIDs) for the rest of the window — including the exact ~13:00, ~17:15, and ~17:45 GMT timestamps matching the three Zabbix-confirmed spikes (up to 92.69%). **No SQL-session-level correlate for any of the three OS-level peaks**, same conclusion as 07-27.

**Q4 — blocking check:** 0 rows. No lock contention during the entire window — ruled out.

**Q5 — system SPIDs (<50) during the three peak windows:** 0 rows. `PNSSRL_AuditSysprocesses` has no visibility into background SQL Server threads (checkpoint, lazy writer, ghost cleanup) during any of the three peaks — confirms the blind spot flagged as H2 in `20260727_cpu_peaks_loadtest` still exists; the 07-27 action item to extend capture to system SPIDs was not implemented.

**Q6 — distinct hosts/logins connected during the full window:** 36 host/login/program/db combinations, all traceable to known infrastructure (`SFCG-WEBS-01/02/03`, `SFCG-MOBI-01/02`, `SFCG-WSV2-01`, `SFCG-WSIT-01`, `SFCG-WSCG-01`, `SFCG-CLUB-01/02`, `SFCG-TO-01`, `SFCG-DB01` self via SQL Agent/IaaS extension/telemetry). No unaccounted-for or unexpected connections. Notable: `zabbix` login connects from `SFCG-TO-01` via SSMS-style client to both `PNSSRL` and `SmartFran.Solution.SmartLoyalty` — consistent with the ODBC-based monitoring query the legacy Zabbix instance/host uses. Does not change the root-cause conclusion — rules out an unauthorized session as a contributing factor.

## Current working theory
**Revised — peak 1 may be explained, peaks 2/3 remain open.**

Metric semantics (inferred from Zabbix legend, not confirmed via API — legacy instance has none): "CPU user time" is shown with `[max]` aggregation on a graph titled "CPU usage **with Cores**", consistent with a **per-core metric read at its maximum across all 16 cores** at each sample (the single hottest core). "CPU utilization" is shown with `[avg]` aggregation, consistent with a **whole-VM average across all 16 cores**. If so, one core fully saturated while the other 15 idle would read ~100% on the "max per-core" graph but only ~1/16 ≈ 6% on the "whole-VM average" graph — exactly the gap observed between the two graphs' maxima (92.69% vs 41.10%/42.40%).

This reconciles with the SQL data for **peak 1 only**: SPID 114 (TaskOperatorService, `CustomerPointsLog` sync) was measured saturating close to one full core during 12:06–13:06 GMT (~09:06-10:06 UTC-3, overlapping the reported 09:30-10:00 peak), and Q3's aggregate CPU across all sessions in that window came out to **~6.3% of 16-core capacity — almost exactly 1/16**, the single-saturated-core signature. Peak 1 may therefore be explained by SPID 114 after all, once "CPU User Time" is read as per-core-max rather than whole-VM-average.

**Peaks 2 and 3 (17:15/17:45 GMT) do not fit this pattern** — Q3's aggregate was ~0% at those exact timestamps, not ~6%, so there is no single-saturated-core signature and no SQL Server session activity of any kind to explain them. These two peaks remain fully open, same unresolved status as all three peaks in `20260727_cpu_peaks_loadtest` — either a non-SQL-Server OS process, or a SQL Server internal/background thread not visible in `PNSSRL_AuditSysprocesses` (confirmed blind spot, Q5).

**CRITICAL CORRECTION (identified 2026-08-03, later in session):** every PowerShell command below (P1, P2, P3a-g, `CPUWatch`) was actually executed on **`SFCG-TO-01`** (TaskOperatorService app server), not `SFCG-DB01` — confirmed by `\\SFCG-TO-01\...` counter/computer prefixes in the `CPUWatch` CSV export. RDP access defaulted to `SFCG-TO-01`, and this went unnoticed for the entire OS-level checking thread. **Only Q7 (`sqlserver_start_time`, a T-SQL query via the DB connection) genuinely reflects `SFCG-DB01`** — everything else below describes `SFCG-TO-01`'s state, not the DB host's. Peaks 2/3's OS-level cause on the actual machine (`SFCG-DB01`) has **not** been checked yet. See `docs/infrastructure.md` → "Scheduled Tasks (`SFCG-TO-01`)" for the corrected version of the scheduled-task findings.

**Reboot ruled out on `SFCG-DB01` (Q7, via SQL connection — this one is valid):**
- `sqlserver_start_time` = 2026-07-15 07:44:46 — no restart anywhere near 2026-08-03.

**Windows Update / Defender findings — apply to `SFCG-TO-01`, NOT `SFCG-DB01` (mislabeled below originally):**
- Windows Update Agent install history on `SFCG-TO-01` (`Microsoft.Update.Session` COM API, 30 most recent entries) shows only daily Microsoft Defender "Security Intelligence Update" installs (all `ResultCode=2`/Succeeded), clustered ~19:10-21:00 GMT each day.
- `Microsoft-Windows-Windows Defender/Operational` log on `SFCG-TO-01` for the window shows only routine hourly health-report heartbeats (Event ID 1150/1151) — no scan-start/scan-end, no detections.
- `Get-MpComputerStatus` on `SFCG-TO-01`: last quick scan 02:42:55-02:43:24 GMT, full scan never run.
- These findings are still useful (they describe `SFCG-TO-01`'s health, relevant background for TaskOperatorService/SPID 114), but **do not rule out anything for `SFCG-DB01`**, where peaks 2/3 were actually observed. Windows Update, Defender scan/detection, and reboot on `SFCG-DB01` itself remain unchecked.

## Ruled out
- Lock contention / blocking chain — `blocked=0` throughout (Q4).
- SQL Server session/query activity as the cause of peaks 2 and 3 — Q3 aggregate is ~0% at both timestamps, no single-core-saturation signature present.
- Unauthorized/unaccounted-for connection as a contributing factor — all 36 host/login combos in Q6 trace to known infrastructure.
- **Not ruled out:** SPID 114 as the cause of peak 1 — plausible pending confirmation of the "max per-core" vs "whole-VM average" metric theory (see working theory above).

## New leads (post-closure follow-up) — ALL of the below were actually run on `SFCG-TO-01`, not `SFCG-DB01`
Corrected 2026-08-03 (see critical correction above). Kept for record — genuinely useful for understanding `SFCG-TO-01`'s scheduled activity and its SQL traffic against `SFCG-DB01`, but **none of it checks `SFCG-DB01`'s own OS-level state**, so nothing here actually rules anything in or out for peaks 2/3 as originally believed.

- `logman query` on `SFCG-TO-01` shows two pre-existing Trace-type Data Collector Sets besides our own (misplaced) `CPUWatch`: `GAEvents` and `RTEvents` — both Azure Guest Agent/runtime diagnostics tracing (`WindowsAzureGuestAgent`, `RuntimeInstaller`, `IISHost`, `Telemetry`, etc.), low-overhead, no acute-burst signature. Relevant to `SFCG-TO-01`'s own health, not `SFCG-DB01`'s.
- `\SmartFran\` Scheduled Task folder (on `SFCG-TO-01`, see `docs/infrastructure.md` for the corrected writeup) — a cluster of report/promotion tasks fires 12:00-12:30 GMT alongside SPID 114's window; only 2 of 5 are truly daily, rest weekly/biweekly/monthly, today's overlap partly coincidental. `Check_list_SF` fires every 5 min anchored at :00 — lands exactly on :15/:45 GMT, matching peaks 2/3 to the minute — but since it runs locally on `SFCG-TO-01`, its own CPU cost can't directly explain `SFCG-DB01`'s graph unless it drives heavy DB-side load (already measured low via Q3). Its actual purpose: checks whether TaskOperatorService is running.
- `CPUWatch` (circular per-process/per-core logman collector) is running on `SFCG-TO-01`, not `SFCG-DB01` — needs to be recreated on the correct host to be useful for catching peaks 2/3.

## Re-run on the actual `SFCG-DB01` (confirmed via `$env:COMPUTERNAME` on every command)
- **`CPUWatch`** recreated correctly on `SFCG-DB01` (circular, 15s interval, same counter set) — running.
- **Windows Update:** ruled out for real this time. Unlike `SFCG-TO-01`'s clean daily ~19:10-21:00 pattern, `SFCG-DB01`'s Defender signature-update installs are scattered throughout the day (13:28:56, 07:55:33, 00:53:49 GMT today, etc.) — genuinely irregular, not a fixed schedule. None land near 17:15 or 17:45 GMT; closest is 13:28:56 (28 min after peak 1). One real signature-update event (ID 2000) confirmed via Defender operational log at 13:28:56 GMT.
- **Windows Defender:** ruled out for real. Operational log shows only routine hourly heartbeats (1150/1151, ~:44:51 each hour) plus the one signature-update event — no scan-start/stop, no detections. `Get-MpComputerStatus`: last quick scan 02:07:39-02:08:19 GMT (~11h before peak 1), full scan never run.
- **Scheduled Tasks:** ruled out for real, and confirms `\SmartFran\` doesn't exist on `SFCG-DB01` — only generic Windows built-ins fired in the window (`PcaPatchDbTask` 15:20:20, `SystemTask`/CertificateServicesClient 15:44:44, `Schedule Scan`/UpdateOrchestrator 16:33:33, `QueueReporting` 16:47:47, `Consolidator`/CEIP 18:00:00). None within 15 minutes of either peak.
- **Existing Data Collector Sets on `SFCG-DB01`:** `GAEvents`/`RTEvents` present here too (every Azure VM gets these) — inspected via `logman query <name> -ets`, identical providers/structure to `SFCG-TO-01`'s (`WindowsAzureGuestAgent`, `RuntimeInstaller`, `IISHost`, `Telemetry`, etc.), 10,099/14,081 buffers written, steady low-overhead background tracing, no acute-burst signature. **Ruled out as spike source.** Also present: `Server Manager Performance Monitor` (built-in Windows collector, `Running` here vs `Stopped` on `SFCG-TO-01` — not investigated further, standard OS component, low relevance).

**Thread closed — genuinely this time, on the correct host.** Every locally-inspectable OS-level lead on `SFCG-DB01` itself has been checked: reboot (Q7 + confirmed no recent restart), Windows Update installs (scattered all day, none near 17:15/17:45 GMT), Windows Defender (no scan, no detection, only routine heartbeats), Scheduled Tasks (no `\SmartFran\` folder here, only generic Windows built-ins, none within 15 min of either peak), and both Azure Guest Agent trace collectors (low-overhead, ruled out). Combined with the SQL-session-level findings (Q2-Q5), peaks 2/3 have no explanation anywhere in what's inspectable after the fact. `CPUWatch` (now correctly running on `SFCG-DB01`) plus a live Resource Monitor watch during the *next* load test are the only paths left to actually catch them.

## Open questions / next steps
- Root cause of peaks 2/3 remains genuinely unresolved — now properly checked end-to-end on `SFCG-DB01` itself (not `SFCG-TO-01`). Nothing found.
- Peak 1 remains a plausible-but-unconfirmed explanation (SPID 114 + "max per-core" metric theory) — cannot be confirmed without access to the legacy Zabbix item configuration.
- GITIN-1749's ticket (`_ops.md`) needs a full correction pass: replace the `SFCG-TO-01`-sourced H6-H11 findings with the properly-scoped `SFCG-DB01` results above, and flag the host mix-up transparently in the ticket itself.

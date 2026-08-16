# Investigation — 20260815_gestion_sql_log_full

**Status:** resolved (2026-08-15) — `Gestion` confirmed started by the user. Root cause and fix both confirmed, see below.

**Ticket:** GITIN-1864 — SmartFran on-premise `Gestion` application fails to start. Reported error: "Microsoft SQL Server Native Client 11.0, The transaction log for database 'GESTION' is full due to 'LOG_BACKUP'."

## Reported symptom

- On-premise `Gestion` application cannot start.
- Underlying error is a SQL Server Native Client error surfaced by the app: the `GESTION` database's transaction log is full, and `log_reuse_wait_desc` is `LOG_BACKUP` — meaning the log can't truncate/reuse space because pending log backups haven't run (this only occurs when the DB is in FULL or BULK_LOGGED recovery model).

## Environment

`GESTION` is the local SmartFran POS schema — a per-franchise, on-premise SQL Server instance running at the store location itself, not a centrally-managed/known host in the Azure or AWS inventory. Hostname is whatever machine runs SQL Server at that specific franchise (unknown to us at the repo level; the user/on-site contact would identify it locally, e.g. via `SELECT @@SERVERNAME`).

## Open questions (not yet answered)

- Which franchise/store this instance belongs to (for the ticket record).
- Environment is implicitly production (a store's live POS) — confirm.
- Current recovery model of `GESTION` (assumed FULL or BULK_LOGGED given `LOG_BACKUP` wait, not yet confirmed).
- Whether a scheduled log-backup job exists for this DB (SQL Agent) and whether it's been failing, or whether log backups were never configured — plausible this is a store-level instance with no maintenance plan at all.
- Disk space available on the volume hosting the log file (`.ldf`) — relevant if the fix requires growing the log rather than just backing it up.

## Related local events

- `operations/events/20260721_gestion_clubgrido_waf_504/` — a prior `Gestion`/ClubGrido incident, but that one was a WAF/504 issue, unrelated to this SQL Server transaction log symptom. Noted only in case there's environment overlap; not treated as a precedent for this root cause.

## Confirmed facts

- Query 1 result: `GESTION` — `recovery_model_desc: FULL`, `log_reuse_wait_desc: LOG_BACKUP`, `state_desc: ONLINE`. Confirms the database itself is online/reachable (not SUSPECT/RECOVERY_PENDING) — the app's failure to start is caused by write operations failing against a full log, not by the DB being down. Also confirms FULL recovery model, so a log backup (not just a CHECKPOINT) is normally required to truncate the log.
- Query 2 result (`DBCC SQLPERF(LOGSPACE)`): `GESTION` log is `9265.367 MB`, `100%` used — fully consumed. Other system DBs (`master`/`tempdb`/`model`/`msdb`) are small and unremarkable, unaffected.
- Query 2 result (`sys.database_files`): logical name `ROM_Log`, physical path `C:\Smartfran\DATA\GESTION_log.ldf`, current size `9265.375 MB` (~9.05 GB), `max_size` 1,280,000 pages (~10,000 MB / ~9.77 GB — an explicit cap, not unlimited), `growth: 10` with `is_percent_growth: 1` (10% autogrowth). Log file is already at ~92.6% of its configured max size, so there's only roughly ~735 MB of autogrowth headroom left even before considering disk space — growing the log further is a limited/short-term option, not a real fix. Confirms this instance is `C:\Smartfran\...` — a store/franchise on-prem SmartFran POS box, consistent with the local-schema description.

- Query 3 result (`msdb.dbo.backupset`, full history back to 2019-04-07): every single row is type `D` (full backup). **Zero `L` (log) backups ever recorded** for `GESTION`. Full backups run irregularly (roughly every few days to a few weeks, most recent 2026-08-09).

## Current working theory — confirmed root cause

`GESTION` is in FULL recovery model but has never had a log backup taken in its recorded history (back to 2019). In FULL recovery, only a log backup (or a switch to SIMPLE) truncates the log — a full backup alone does not. So the log has grown unbounded across ~7 years of full-backup-only operation until it hit its configured `max_size` cap (~9.77 GB) and filled 100%. This is not a broken job — log backups were never configured on this instance. Given periodic full backups are the only backup activity this store instance has ever had, FULL recovery model itself looks like an unused/unintended setting here, not a deliberate point-in-time-recovery requirement.

## Remediation applied (2026-08-15) — log truncation confirmed, app-start still pending

`ALTER DATABASE GESTION SET RECOVERY SIMPLE` + `CHECKPOINT` run by the user, reported "Command(s) completed successfully." Post-checkpoint `DBCC SQLPERF(LOGSPACE)` confirms the log truncated: `GESTION` usage dropped from 100% to **9.11%** (same 9265.367 MB file size, now mostly free space within it). Not yet confirmed: whether the `Gestion` application itself starts successfully now — the SQL-side fix succeeding is not the same as confirming the original reported symptom (app won't start) is resolved.

## Remediation plan (proposed, applied above)

- Query 5 confirmed: `C:\` — 228,433 MB total / 126,682 MB free (~123.8 GB) — no disk-space constraint on either remediation path.
- Query 6 confirmed: zero SQL Agent jobs match `%GESTION%` or `%log%backup%` on this instance — no log-backup job has ever existed here, not just one that stopped running. Fully corroborates the `backupset` history finding above.
- Given FULL recovery has never actually been exercised for point-in-time recovery on this instance (7 years of full-backup-only history, zero log backups), proposed fix is to switch `GESTION` to SIMPLE recovery model and force a `CHECKPOINT` to truncate the log immediately — resolves the outage and prevents recurrence, since SIMPLE doesn't require an ongoing log-backup job that this store instance has never had. Caveat: standalone store POS box, no indication of log shipping/mirroring/AlwaysOn depending on FULL model, but not independently ruled out before proposing this.
- Optional follow-up: `DBCC SHRINKFILE` on the log after truncation, to reclaim disk space from the now-oversized `.ldf` (currently ~9.05 GB) — discretionary, not required to unblock the app.

## Ruled out

- Log-backup job existing but failing/disabled — ruled out, no `L`-type backup exists anywhere in `backupset` history, so no such job has ever run successfully (or at all).
- Active/stuck transaction holding the log open — ruled out, query 4 (`sys.dm_tran_database_transactions`) returned 0 rows.

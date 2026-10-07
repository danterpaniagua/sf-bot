# Investigation: CustomerPointsLog blocking chain (2026-09-21)

**Jira:** [GITIN-2076](https://smartit-ar.atlassian.net/browse/GITIN-2076)

## Status

**Resolved (immediate symptom).** Blocking chain confirmed cleared after `KILL 93` — recheck at 10:30:55 GMT shows only SPID 80 remaining, `blocking_session_id = 0`, waiting on its own I/O (`PAGEIOLATCH_SH`), not blocking anyone. All 12 previously-queued app sessions cleared. Underlying causes (job still scheduled at 06:15 UTC instead of the recommended 08:00, likely still full-table rather than partition-scoped, and the unfixed ETL `OR`-predicate query) remain unaddressed — this only cleared today's specific incident, not the recurring risk. Discovered incidentally while checking server load before running `events/20260920_cpu-spikes/remediation_indexes.sql` — unrelated table, split into its own event per scope-isolation convention.

## Confirmed facts

- **SPID 93** — `SQLAgent - TSQL JobStep` (Job `0x9B0BD93393BA1846BE961FADF915AE66`, Step 1), running `ALTER INDEX [IX_CustomerId] ON [SmartFran.Solution.SmartLoyalty].[Sml].[CustomerPointsLog] REBUILD;`. Started 2026-09-21T06:15:00.947 GMT. As of the last check (~10:25 GMT), `percent_complete = 0` — it has been queued waiting for a `LCK_M_SCH_M` lock for its entire ~4h10m runtime, never actually started rebuilding.
- **Blocked by SPID 80** — `SFCG-TO-01`, `.Net SqlClient Data Provider`, a large paginated (`OFFSET 100000 ROWS FETCH NEXT 100000 ROWS`, `NOLOCK`) read of `Sml.CustomerPointsLog` joined to `Sml.Customer`, filtered by a `CreatedDate`/`LogDate` OR-boundary window with a `_SyncDate` marker column. `blocking_session_id = 0` (not itself blocked), status `running`, elapsed ~1h00m as of last check.
- **SPID 80 matches a known, already-diagnosed bug**: `loyalty/docs/task_operator_tasks.md` documents `Etl.EtlOperationConfig.Id=6` (`ToTable = dbo.CustomerPointsLog`), habitual trigger ~07:25 UTC, chronic slow throughput (~10-20 rows/sec across 23 executions previously checked). Root cause (from `events/20260715_cpu_spikes/`): a non-sargable `OR` predicate plus a `COUNT(*) OVER()` pre-query in its `FromQuery`. **Proposed fix from that investigation was never applied** — this is a recurrence of a known, unfixed issue surfacing as a new symptom (blocking) rather than its original symptom (CPU/throughput).
- **12 real application sessions queued behind SPID 93** (not directly blocked by SPID 80): mobile app (`SFCG-MOBI-01`, SPIDs 118-125), club website (`SFCG-CLUB-01`, SPIDs 74, 77, 92, 103), and a Zabbix healthcheck (SPID 117, `ExpiredPoints` count query). Wait times at last check ranged ~3.5s–16.7s and growing. Standard lock-queue fairness: once SPID 93's `Sch-M` request queued, subsequent `Sch-S` requests queue behind it too, even though none of them conflict with SPID 80 directly.
- Full raw blocking-chain query output persisted (via a misplaced-then-corrected file, originally saved into `cloud/events/20260920_sales-oom-48h/data/q13.txt` by mistake — copy exists there, not moved/duplicated into this folder's `data/` yet).

## Precedent — GITIN-1981 / GITIN-2060 / GITIN-2061

`PNSSRL_MantenimientoIndices` (job name confirmed via `msdb.dbo.sysjobs`, matching job_id `0x9B0BD93393BA1846BE961FADF915AE66`) is the exact job GITIN-1981 (`events/20260901_pnssrl_mantenimientoindices_review/`) investigated: daily offline rebuild at 06:15 UTC, historically confirmed to block up to 38 sessions against `SFCG-MOBI-01`/`sfzabbix`. That investigation's standing recommendation — move to 08:00 UTC — was never applied under that ticket; GITIN-1981 closed anyway (2026-09-16) with the actual work split into **GITIN-2060** (reschedule) and **GITIN-2061** (partition-scoped `IX_CustomerId` rebuild — rebuild only the current-year partition instead of the whole table).

This already recurred once, on 2026-09-14 (`events/20260914_taskoperator_mktcampaign537_errors/`), confirmed still starting at 06:15 UTC — GITIN-2060 hadn't landed then either. **Today is a third recurrence**, same 06:15 UTC start — GITIN-2060 and almost certainly GITIN-2061 (a 4+ hour stuck run is inconsistent with a partition-scoped rebuild being live) are still unapplied months later.

**New failure mode today, not seen in the two prior occurrences**: previously the job blocked others by taking a long time on its own; today it's the job itself that's blocked (by SPID 80, the slow ETL sync), stuck at 0% progress rather than grinding through. Worth folding into GITIN-2060/2061 as additional context, not just a duplicate of the prior finding.

## Root cause

Not a single stuck session — a lock-queue-starvation pattern. SPID 80 (the known-slow ETL sync job) keeps re-acquiring schema-stability locks batch after batch across its ~1h+ runtime, never leaving a gap long enough for SPID 93's schema-modification request (the index rebuild) to be granted. SPID 93 sitting queued then blocks all newer read requests behind it, per standard fairness queuing — cascading into real user-facing latency (mobile app, club website).

## Remediation

Two destructive options considered; proceeded with cancelling the stuck rebuild (SPID 93 / its SQL Agent job step) rather than interrupting the in-progress ETL sync (SPID 80):

- **`KILL 93`** — 0% complete, nothing lost, immediately freed the 12 queued sessions. **Executed 2026-09-21 ~10:30 GMT, confirmed successful.** Recheck (10:30:55 GMT) shows the blocking chain fully cleared — only SPID 80 remains, `blocking_session_id = 0`, on its own I/O wait. `PNSSRL_MantenimientoIndices`'s job run for today failed/was cancelled as a result — it will need to be manually re-run or will pick up again at its next scheduled trigger (06:15 UTC tomorrow, unless GITIN-2060's reschedule finally lands first).
- (Not chosen) Kill SPID 80 — would have interrupted legitimate, read-only (NOLOCK) work; re-runnable but would have wasted ~1h of progress.

## Open Questions / Next Steps

- **GITIN-2060 (reschedule to 08:00 UTC) and GITIN-2061 (partition-scoped rebuild) are still unapplied as of this third recurrence** — the real fix for this recurring risk lives there, not in today's kill (which only cleared the symptom). Worth escalating given this is the third confirmed occurrence.
- The underlying ETL query fix (non-sargable `OR` + `COUNT(*) OVER()`, from `events/20260715_cpu_spikes/`) is also still unapplied — third known-but-unfixed performance issue to resurface as a new incident this session, alongside GITIN-1267/Query101 (`events/20260920_cpu-spikes/`) and this job's own reschedule. Worth raising as a pattern, not three isolated fixes.
- Move the misplaced raw query output from `cloud/events/20260920_sales-oom-48h/data/q13.txt` into this event's `data/` folder for proper evidence hygiene (copy already made at `data/01_blocking_chain.txt`; original left in place at user's discretion).
- Confirm whether `PNSSRL_MantenimientoIndices`'s cancelled run needs manual follow-up (re-run, or does the maintenance plan self-heal on next schedule).

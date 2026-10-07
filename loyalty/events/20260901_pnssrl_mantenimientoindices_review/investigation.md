# Investigation: PNSSRL_MantenimientoIndices review

## Context

Jira ticket: [GITIN-1981](https://smartit-ar.atlassian.net/browse/GITIN-1981) — "[SML] Revision de PNSSRL_MantenimientoIndices". **Parent: GITIN-1866.**

Split off from GITIN-1866 (`loyalty/events/20260816_club_grido_campaign_query_health/`), where a weekend query-health check (2026-08-28/29/30) surfaced this job as the confirmed root cause of a recurring blocking chain against `Sml.CustomerPointsLog`. That investigation's findings are the starting point here — read `loyalty/events/20260816_club_grido_campaign_query_health/investigation.md` (section "Job identity and schedule confirmed (Q15/Q16/Q17)" onward) for the full derivation; not re-derived from scratch below, only the conclusions carried forward.

**Objective (per user, 2026-09-01)**: find a schedule time for `PNSSRL_MantenimientoIndices` that avoids/minimizes the blocking impact confirmed above. Current schedule is daily `06:15:00 UTC` (03:15 UTC-3) — already off-peak by design, but still causes confirmed blocking (up to 38 concurrent sessions) against `SFCG-MOBI-01` and `sfzabbix`. This narrows the ticket from a general "review" to a concrete scheduling recommendation, informed by real traffic-low-point data rather than assumption.

## Status

**Closed (2026-09-16) — without the reschedule ever being applied under this ticket.** GITIN-1981 was closed with the 08:00 UTC recommendation below never having been implemented. The actual work (reschedule + a partition-scoped rebuild fix discovered during GITIN-2036's investigation) now lives under two new tickets instead: [GITIN-2060](https://smartit-ar.atlassian.net/browse/GITIN-2060) (reschedule) and [GITIN-2061](https://smartit-ar.atlassian.net/browse/GITIN-2061) (partition-scoped `IX_CustomerId` rebuild) — see `loyalty/events/20260914_taskoperator_mktcampaign537_errors/`. Everything below is historical record of GITIN-1981's own analysis; do not treat the recommendation as pending under this ticket anymore.

Previously (open, close to settled): Proactive — this ticket exists solely as a byproduct of the GITIN-1866 weekend query-health analysis; it was not triggered by an alert, a user report, or an independent complaint. Root-cause and scheduling-recommendation work are both done: `ops.md` (H1-H14) and this file carry the full derivation, ending in a **standing recommendation of 08:00 UTC (05:00 UTC-3)** for `PNSSRL_MantenimientoIndices`, reconfirmed as low-risk after the duration de-escalation below (Q32/H14). An hourly schedule table (00-23 UTC) summarizing this recommendation is in `ops.md` (under Acción propuesta 1) and in `loyalty/docs/task_operator_tasks.md` §4; the fully-annotated ASCII chronogram (with rebuild duration bars, current-vs-proposed) is persisted at `db_schedule_chronogram.txt` in this event folder.

**What's actually left before this can close:**
1. Fresh user approval to run Q26 (or Q27) against production — the only approval on record so far was for the now-superseded 23:30 UTC pick (2026-09-10), not the current 08:00 UTC recommendation.
2. Confirm `Program Results`' business purpose (its query's own `<Description>` is empty) — the one daily, in-window `Sml.CustomerPointsLog` touch, to rule out delivery-time sensitivity before calling the recommendation fully verified rather than "low-risk assumed."
3. The secondary action items (H4 duration-variability root cause, GITIN-1669 precedent action-item confirmation, `Etl.EtlOperationConfig` full pull) remain open but are not blockers for closing the scheduling objective itself — see Acciones propuestas 2-4 in `ops.md`.

## Findings inherited from GITIN-1866 (already confirmed, re-verify before reuse if stale)

**Job identity**: `PNSSRL_MantenimientoIndices` (SQL Agent job GUID `0x9B0BD93393BA1846BE961FADF915AE66`, `enabled=1`), matching the reference script `queries/PNSSRL_MantenimientoIndices.sql` already tracked in this repo.

**Schedule**: daily (`freq_type=4`, `freq_interval=1`), `active_start_time=06:15:00 UTC` (03:15 UTC-3), `active_end_time` effectively unbounded (`23:59:59`). Standing daily job, not weekend-specific.

**Steps**:
1. `EXEC PNSSRL_MantenimientoModulos` — generates per-table `ALTER INDEX ... REBUILD` statements dynamically (the actual rebuild commands are not in the job step text; observed via `PNSSRL_AuditSysprocesses.comando_ejecutado` during blocking snapshots, not from the job definition itself).
2. Conditionally starts `Operaciones_MaintenancePlan_Backups.Backup_Log` if not already running/retrying — tangential, not investigated here.
3. Retention cleanup on `PNSSRL_DetallesEjecucionTablasModulos` (internal monitoring housekeeping) — unrelated to the blocking.

**Confirmed blocking impact** (from GITIN-1866's `PNSSRL_AuditSysprocesses` captures, 2026-08-28/29/30 weekend window):
- Head blocker in all 26 blocking snapshots across all three days was this job, running `ALTER INDEX [IX_CustomerId] ON [SmartFran.Solution.SmartLoyalty].[Sml].[CustomerPointsLog] REBUILD;` (25 snapshots) or `ALTER INDEX [IX_PromotionBranchOffice_1] ON [SmartFran.Solution.SmartLoyalty].[SmlSupp].[PromotionBranchOffice] REBUILD;` (1 snapshot, 2026-08-28 07:56 UTC).
- Wait type on blocked sessions: predominantly `LCK_M_SCH_S` (schema-stability), consistent with sessions queuing behind the schema-modification lock the `ALTER INDEX REBUILD` holds for its duration.
- Blocked sessions were mostly `SFCG-MOBI-01`'s EF query (`SELECT ... FROM [Sml].[CustomerPointsLog] WHERE CustomerId = @EntityKeyValue1`) and `sfzabbix`'s index-fragmentation healthcheck query — i.e. this job blocks both the Mobile app tier and the Zabbix monitoring check that inspects fragmentation, which is a mildly ironic detail (the fragmentation-monitoring query gets blocked by the fragmentation-fixing job).
- Peak simultaneous blocking: **38 sessions** (2026-08-28 07:21:00 UTC), 16 distinct blocker-chain links.
- Job's own wait type while holding the lock alternated `MEMORY_ALLOCATION_EXT` / `SOS_SCHEDULER_YIELD`, status `runnable` — actively executing, not stuck.

**Duration variability** (last 10 `sysjobhistory` rows pulled under GITIN-1866, most recent first):
| Date (UTC) | Start | Step 1 duration | Outcome |
|---|---|---|---|
| 2026-09-01 | 06:15:00 | 01:52:55 | Succeeded |
| 2026-08-31 | 06:15:00 | **06:14:11** | Succeeded |

Not yet pulled further back than this. The 2026-08-31 run taking over 6 hours (vs. 1h53m the next day) is itself the most concrete anomaly found so far — worth understanding why duration varies this much before deciding on a fix.

## Dead end — `PNSSRL_MantenimientoModulos` is `WITH ENCRYPTION`

`SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.PNSSRL_MantenimientoModulos'))` returned `NULL`; `sp_helptext` confirmed: "The text for object 'dbo.PNSSRL_MantenimientoModulos' is encrypted." Its fillfactor logic, table-iteration order, and `ONLINE`/`OFFLINE` choice cannot be read directly from the object definition through standard means. Not pursuing decryption workarounds without the user's explicit direction — the encryption may be intentional, not an oversight.

**Fallback**: encryption hides the *stored* `CREATE PROCEDURE` text, not the *runtime* SQL batch text it executes — `PNSSRL_AuditSysprocesses.comando_ejecutado` (already the source for the `ALTER INDEX REBUILD` statements seen in GITIN-1866's Q11/Q13) captures the literal executing statement regardless of the procedure's encryption. Continued indirect observation via that table across more of a run (not just the `CustomerPointsLog` moment) is the remaining path to inferring iteration order and fillfactor — not yet done. The captured `ALTER INDEX REBUILD` text seen so far had no `WITH (...)` clause visible in the snippet, consistent with a default fillfactor, but the snippet wasn't confirmed complete/untruncated.

## `queries/PNSSRL_MantenimientoIndices.sql` — read directly

Matches the `msdb.sysjobsteps` content already captured (Q15) — this is the job-step wrapper, not the rebuild logic. All four parameters (`@base`, `@modulo`, `@tabla`, `@fillfactor`) are passed as `NULL` into `EXEC PNSSRL_MantenimientoModulos`. The per-table rebuild generation (fillfactor selection, iteration order, `ONLINE`/`OFFLINE` option) lives inside `PNSSRL_MantenimientoModulos` itself — a stored procedure, not present in `queries/`. Its definition hasn't been read directly; not yet pulled via `sys.sql_modules`/`sp_helptext`.

## Precedent — [GITIN-1669](https://smartit-ar.atlassian.net/browse/GITIN-1669), `20260723_bloqueo_customerpointslog_loadtest` (long-form filenames, predates the `investigation.md`-first convention; ticket number confirmed 2026-09-09 against the real Jira content, pasted by the user — matched word-for-word)

A prior incident, same table, same job — read on request. Confirms two things directly relevant here:

1. **`ONLINE`/`OFFLINE` question resolved**: that ticket's H4 states plainly — "Los rebuilds offline retienen `Sch-M` durante toda su duración y no reportan `percent_complete` confiable." The rebuild is confirmed **offline**. This matches the current finding (Sch-M-driven `LCK_M_SCH_S` blocking, `percent_complete` not checked in GITIN-1866 but same mechanism).
2. **Different trigger, same victim table**: on 2026-07-23, the blocking chain wasn't the maintenance job itself running long — it was a **stray uncommitted transaction under the `zabbix` login** (SPID 93, consistent with an SSMS session left open, not an actual monitoring process) blocking the legitimate `ALTER INDEX REBUILD` (SPID 87) via `LCK_M_SCH_M`, which in turn blocked everything else needing `Sch-S` on the table. Root cause there was `KILL 93`, not the job itself — a different mechanism from GITIN-1981's finding (job itself is the head blocker, not blocked by anything). Don't conflate the two: same table, same job, different upstream cause each time.

**Action items proposed in that ticket, apparently never implemented** (worth re-proposing here, now with a second occurrence as evidence):
- "Evaluar coordinar el horario de los load tests de MobileAppService con la ventana de mantenimiento de índices, para evitar que ambos coincidan de nuevo." — directly relevant fix direction for GITIN-1981 too, independent of the specific trigger.
- "Definir una alerta o un límite de tiempo para sesiones idle/sin commit bajo el login `zabbix`" — not directly GITIN-1981's mechanism, but same table's blocking surface; worth checking whether this was ever done, since a recurrence of *that* specific cause would compound with the daily job's own blocking.

## Zabbix `mssql.job.run_duration` — investigated, query itself is correct (corrects an earlier wrong hypothesis in this file)

User raised: why does Zabbix show a low value for `PNSSRL_MantenimientoIndices`'s run duration, when GITIN-1866's `sysjobhistory` pull showed real durations of 1h53m–6h14m? Item chain: discovery `SELECT name AS jobname FROM msdb..sysjobs WHERE enabled = 1` (12 enabled jobs, confirmed includes this one) → master item **"MSSQL: Get job status"** (Database monitor, real SQL, part of the stock "DB MSSQL by ODBC" template, Zabbix v5.0) → per-job dependent item → `mssql.job.run_duration["{#JOBNAME}"]` (JSONPath `$[?(@.JobName=='{#JOBNAME}')].RunDuration.first()`).

**An earlier version of this section hypothesized a `sysjobhistory` `step_id`-filter bug (based on reproducing the symptom with Q19), but the actual master item SQL rules that out.** The real query:

```sql
SELECT sj.name AS JobName, sj.enabled AS Enabled,
       sjs.last_run_outcome AS RunStatus, sjs.last_outcome_message AS LastRunStatusMessage,
       sjs.last_run_duration/10000*3600 + sjs.last_run_duration/100%100*60 + sjs.last_run_duration%100 AS RunDuration,
       CASE sjs.last_run_date WHEN 0 THEN NULL ELSE msdb.dbo.agent_datetime(sjs.last_run_date,sjs.last_run_time) END AS LastRunDateTime,
       sja.next_scheduled_run_date AS NextRunDateTime
FROM msdb..sysjobs AS sj
LEFT JOIN msdb..sysjobservers AS sjs ON sj.job_id = sjs.job_id
LEFT JOIN (SELECT job.job_id, max(act.session_id) AS s_id, max(act.next_scheduled_run_date) AS next_scheduled_run_date
           FROM msdb..sysjobs AS job LEFT JOIN msdb..sysjobactivity AS act ON act.job_id = job.job_id
           GROUP BY job.job_id) AS sja ON sja.job_id = sj.job_id
WHERE Enabled = 1
```

Pulls `last_run_duration` from **`msdb.dbo.sysjobservers`** — a job-level summary field SQL Agent itself maintains (not a raw `sysjobhistory` step row) — and the `HHMMSS`→seconds conversion is arithmetically correct (verified against Q17: `15255` → 1×3600+52×60+55 = 6775s = 01:52:55, matches exactly). **No bug in this query.**

**Actual explanation — not a monitoring bug, ties back to the still-open duration-variability question**: `sysjobservers.last_run_duration` only updates when a run *completes*; it reports the **last finished run's** duration, not live progress of one currently in flight. Two non-bug scenarios both produce a "surprisingly low" reading:
1. Checked shortly after a genuinely short run (e.g. 2026-09-01's 1h52m55s) — legitimately lower than the 2026-08-31 6h14m11s outlier; this is real variability, not a measurement error, and remains the open "why does duration vary this much" question above.
2. Checked **while a long run is still in progress** — the item would still show the *previous* completed run's (possibly short) duration until the current run finishes, understating how long today's run has actually been going. This is a genuine, separate monitoring **limitation** (no live in-progress duration), not a bug — worth flagging: it means Zabbix can't be used to catch a long-running instance *while it's happening* via this item; only after the fact.

**Not evaluated**: whether a live-progress alternative is worth building (e.g. a custom check using `sys.dm_exec_requests.percent_complete` for the running session, though GITIN-1866's dead-ends noted this is unreliable for offline rebuilds — see the 2026-07-23 precedent's H4) — likely not worth pursuing given that known unreliability.

## Not yet confirmed / open questions for this ticket

- **Root cause of duration variability**: what makes some runs take ~2h and others ~6h+? Candidates not yet checked: fragmentation level of the tables at run time, blocking/contention *on* the job itself from other concurrent activity (per the 2026-07-23 precedent, this has happened before via a stray `zabbix` session), growing table size, or a specific table other than `CustomerPointsLog` being the long pole in a given run.
- **`PNSSRL_MantenimientoModulos`'s actual definition** — confirmed unreadable directly (`WITH ENCRYPTION`); only inferable from job-step wrapper + observed runtime commands.
- **Whether `PNSSRL_MantenimientoModulos`'s table-iteration order is deterministic or fragmentation-driven** — relevant to explaining why `CustomerPointsLog`'s rebuild (and resulting blocking) starts at a different elapsed offset each day.
- **Scope of impact beyond the one weekend checked**: this is confirmed as a *daily* job, so the same blocking pattern likely occurs every day, not just weekends — not yet quantified across weekdays.
- **Whether the 2026-07-23 precedent's action items were ever actioned** — not confirmed either way; if the `zabbix`-login idle-transaction alert was never built, that's a compounding risk on top of GITIN-1981's finding, not a separate concern.
- **Possible fix directions** (not evaluated yet, no action taken): reordering the maintenance sequence to run `CustomerPointsLog` at lowest-traffic time, using a fragmentation threshold to skip unnecessary rebuilds, or reducing blocking granularity (e.g. `WAIT_AT_LOW_PRIORITY` on 2022 Standard, if supported). `ONLINE=ON` is not an option to evaluate — confirmed offline by design/precedent, not a config gap to fix, though *why* it's offline (edition limitation vs. deliberate choice) isn't confirmed.

## Scheduling analysis (2026-09-09) — Q20/Q21/Q22

**Q20 — duration distribution, 25 days (2026-08-15 to 2026-09-08):** confirms real, recurring variability, not a one-off outlier. Most days cluster ~1h30m–2h10m, but 6/25 days (24%) exceed 3h (03:18:15, 03:21:24, 03:24:49, 03:59:59, 04:06:25, and the known 06:14:11 on 08-31) — roughly every 4-5 days. A 06:15 UTC start with a worst-case run can still be executing past 12:00 UTC.

**Q21 — hourly MobileAppService activity profile, 30 continuous days (confirmed continuous via `earliest_sample`/`latest_sample`, no gaps):** lowest-traffic hours are **3, 4, 5, 10 UTC** (2,811–4,410 rows, 55–84 distinct spids) vs. 5,000–10,000+ the rest of the day. **Hour 7 UTC is a massive, isolated spike** — 10,274 rows, ~2x any other hour, 132 distinct spids (also the single highest spid count of the day).

**Q22 — what causes the hour-7 spike:** not a SQL Agent job (only `PNSSRL_CapturaCheckDB` overlaps that window, and it's weekly/Mondays-only, `active_start_time=07:00:00`, can't explain a pattern across a 30-day rollup on its own). Host/program breakdown is decisive: `SFCG-MOBI-01`'s `.Net SqlClient Data Provider` alone accounts for the entire 10,274-row/132-spid total — this is the app's own DB driver, i.e. **genuine MobileAppService application traffic**, not a reorderable batch job. **Hard constraint, not a movable neighbor.**

**Implication for the scheduling recommendation:** the current 06:15 UTC start already borders hour 7's spike — any run exceeding ~45 minutes (which is nearly every run, minimum observed is 1h17m) overlaps it. The lowest-traffic block (hours 3-5 UTC) is the natural target, but even starting there, a worst-case 6h+ run would still reach into hour 7-9. There's an inherent tradeoff between (a) starting early enough that even worst-case runs finish before hour 7 (would require starting ~00:45 UTC or earlier — very early/overnight), vs. (b) accepting that long-tail runs will occasionally touch hour 7's spike but at least avoiding the *current* situation where every run starts right at its edge. **This is a scheduling-tradeoff decision, not something to resolve unilaterally from the data alone** — needs user/business input on how much overnight-start is acceptable vs. how much occasional hour-7 overlap is tolerable.

## Still needed

- Pull `PNSSRL_AuditSysprocesses`/`PNSSRL_TempdbProc` captures across a *full* run (not just the `CustomerPointsLog` moment) to indirectly infer table-iteration order and fillfactor via `comando_ejecutado`, since the procedure itself is encrypted and unreadable directly.
- ~~Pull `sysjobhistory` further back~~ — done (Q20 above), 25 days pulled.
- Confirm whether `SFCG-TO-01`'s CPU dominance during the GITIN-1866 weekend window (44.6M ms) is related to being blocked/retrying behind this same job — flagged as open in GITIN-1866, still unresolved.
- Confirm whether the 2026-07-23 precedent's proposed action items (load-test/maintenance-window coordination, idle-`zabbix`-session alert) were ever implemented.
- ~~decide the scheduling tradeoff~~ — resolved below, recommendation given.

## Recommendation (2026-09-09)

Comparison of 4 candidate start times against 3 duration scenarios from Q20 (P50 median ≈1h50m, P80 ≈3h20m, worst observed 6h14m11s), using Q21's hourly `snapshot_rows` as a traffic-exposure proxy:

| Start (UTC / UTC-3) | Median case (end, hours touched, exposure) | P80 case (end, hours, exposure) | Worst case (end, hours, exposure) | Ever touches hour-7 spike? |
|---|---|---|---|---|
| **Current: 06:15 / 03:15** | 08:05 · 6,7,8 · 19,008 | 09:35 · 6,7,8,9 · 22,776 | 12:29 · 6,7,8,9,10,11,12 · 32,336 | **Yes, all 3 scenarios** |
| **A: 00:30 / 21:30 (prev. day)** | 02:20 · 0,1,2 · 16,795 | 03:50 · 0,1,2,3 · 21,205 | 06:44 · 0,1,2,3,4,5,6 · 32,252 | **No, none** |
| B: 01:00 / 22:00 (prev. day) | 02:50 · 1,2 · 11,227 | 04:20 · 1,2,3,4 · 18,759 | 07:14 · 1,2,3,4,5,6,7 · touches spike | Only worst case (partial) |
| C: 03:00 / 00:00 | 04:50 · 3,4 · **7,532 (lowest)** | 06:20 · 3,4,5,6 · 15,457 | 09:14 · 3,4,5,6,7,8,9 · 33,119 | Yes, worst case (full) |

**Superseded (2026-09-09, kept for the record only — invalidated 2026-09-10 by the PoS-hours constraint below): 23:30 UTC (20:30 UTC-3, same calendar day — no date-boundary crossing).**

After confirming `Backup_FULL`'s real schedule (Q23: weekly, Sun/Mon/Wed, 06:00 UTC), Option A's worst-case tail (00:30 UTC start, ends 06:44 UTC) turned out to still clip ~44min of that backup on 3 days a week. Moving the start ~1h earlier to **23:30 UTC** clears both hard constraints in every observed scenario: worst-case (6h14m11s) ends 05:44 UTC — 76 minutes before the MobileAppService spike (07:00) and 16 minutes before `Backup_FULL` (06:00), even on the days both coincide. Median/P80 cases end even earlier (01:20 / 02:50 UTC), well clear of both. Traffic exposure is essentially unchanged from Option A (worst-case ~32,536 vs. 32,252 — negligible difference) since it draws from the same low-traffic overnight hours, just one hour earlier. 20:30 UTC-3 is also a clean same-day local time, avoiding the "previous evening" framing Option A required.

**Current recommendation (2026-09-10): 08:00 UTC (05:00 UTC-3) — supersedes 23:30 UTC above.**

**New constraint, not previously factored in: PoS terminals are active 10:00–02:00 UTC-3 (13:00 UTC – 05:00 UTC next day).** 20:30 UTC-3 (the 23:30 UTC pick) sits squarely inside that active window — invalidated. Reworking with this added:

- POS-free window: 05:00–13:00 UTC (02:00–10:00 UTC-3).
- Within it, `Backup_FULL` (06:00 UTC, Sun/Mon/Wed) and the MobileAppService spike (07:00–08:00 UTC) still occupy the first three hours.
- **The one stretch clear of all three known constraints: 08:00–13:00 UTC.**

Starting at 08:00 UTC: median run (~1h50m) ends 09:50 UTC — clean. P80 run (~3h20m) ends 11:20 UTC — clean. Worst-case run (6h14m11s) ends 14:14 UTC — ~1h14m past POS resumption (13:00 UTC), on the ~24% of days that run long. Not fully clean on the tail, but the only candidate clean for the common case against all three known constraints simultaneously.

**Explicitly not verified, flagging rather than assuming:**
- `Backup_FULL`'s own duration is unconfirmed — 08:00 UTC assumes it's finished 2h after its 06:00 UTC start, not confirmed.
- Generic "ETL" and "housekeeping tasks" schedules beyond what's already documented here (`SFCG-TO-01`'s `\SmartFran\` cluster ~12:00 UTC, `Backup_FULL`/`Backup_Log`) haven't been independently pulled — if a specific ETL job is in mind, check its schedule against this window before treating 08:00 UTC as final.
- The `SFCG-TO-01` task cluster (~12:00 UTC) falls inside the worst-case run's tail (ends 14:14 UTC) — same interaction risk already known from GITIN-1753, not re-resolved here.

**Q29/Q30 (2026-09-10): full SQL Agent job inventory pulled, one new job found and resolved as a non-issue.** Full inventory of 12 enabled jobs (`data/all_enabled_jobs_schedules_20260910.txt`) surfaced `Actualiza_DWGrido_CustomerPointsBalance` (daily, 08:30 UTC) — not previously known, landing inside the 08:00 UTC candidate window. Initially flagged as a critical conflict; **resolved as a non-issue after checking its actual definition and history (Q30):** it reads from `SmlSt.CustomerPointsLog` (a distinct schema from `Sml.CustomerPointsLog`, same one Query101 used) and writes to a separate linked-server database — no shared object with the index rebuild. Real execution history (30 days) shows 3m24s–15m14s runs, mostly 4-7 minutes — fast, not a multi-hour risk either way. **08:00 UTC recommendation stands, now checked against this too.** Also confirmed from the same inventory: `PNSSRL_CapturaUsoIndices` runs weekly Thu/Fri at 23:00 UTC — retroactively confirms the earlier-superseded 23:30 UTC pick would have collided with this too, on top of the POS-hours issue.

**MAJOR REVISION (2026-09-10): 08:00 UTC recommendation is no longer trustworthy — full `\SmartFran\` script audit found far more `Sml.CustomerPointsLog` contention than the SQL Agent job inventory alone showed.**

User provided the full ~54-task inventory from `SFCG-TO-01`'s `\SmartFran\` folder (`data/sfcg_to01_smartfran_tasks_20260910.txt`, `..._nexttimes_20260910.txt`). Checking each task's actual script/query content against `Sml.CustomerPointsLog` (not names — see the `PointsLogGenerator` near-miss below) required two corrections along the way:
1. First pass checked the wrong duplicate query-file folder (`Core/Domain.Query/Domain/Query/` instead of `Front/SmlBackScript/Query/`, which is what these `.ps1` scripts actually load) — produced false "clear" results for several tasks.
2. Second pass used a regex that missed bracketed schema notation (`[Sml].[CustomerPointsLog]`) — missed a few more.

Corrected full results: `data/smlbackscript_customerpointslog_audit_20260910.txt`. **13 tasks confirmed to touch `Sml.CustomerPointsLog` directly**, most importantly:
- **`Program Results`** — 11:00 UTC, **daily** (not weekly/monthly) — lands inside the 08:00-13:00 candidate window every single day.
- **`SendCanjesSocioCortesiaToBlobStorage` / `SendDetalleCanjesSocioCortesiaToBlobStorage`** — run **continuously every 30 minutes from 11:00 UTC to 03:00 UTC the next day**, both touching `Sml.CustomerPointsLog` on every execution (per GITIN-1266's prior finding, ~700 sec CPU each). This alone means the entire 11:00-03:00 stretch has near-constant `CustomerPointsLog` activity, not a clean window.
- Also touching: `Alerts Update` (07:00 daily), `PointsLogGenerator` (07:30 daily), `AssignPointFirstSaleApp` (04:00 daily), plus several weekly/monthly ones landing 08:00-12:00 UTC (`ExchangeReportsMonth`, `ReportUpdateCustomer`, `ReportPointsTransfer`, `ReportManualPointsAssignmentIndividual/Lists`, `PointsFranchisePY`).

**Revised safe-window read:** combining this with every constraint found so far (PoS active 13:00-05:00 UTC, `Backup_FULL` 06:00 UTC Sun/Mon/Wed, MobileAppService spike 07:00-08:00 UTC, and now these 13 tasks), the only stretch clear of everything currently known is roughly **05:00-07:00 UTC — about 2 hours**. That's shorter than the rebuild job's own typical duration (~1h50m) and far short of its worst-case tail (6h14m). **A fully clear window may not exist given the job's own duration variability — this likely needs reframing from "find a clear window" to "minimize/choose the least-disruptive overlap," or addressing the job's duration variability itself (H4) as a prerequisite.** Not yet resolved — per-task lock duration for the 13 touching tasks (beyond the one known ~700sec/execution figure) still needs checking before any new recommendation is proposed.

**Dependency chain clarified (2026-09-10):** user pointed to a second local clone, `loyalty/repo/SmartLoyalty.SmlBackScript/` — a deployed-copy mirror (credentials stripped) of what actually runs on `SFCG-TO-01`, distinct from `dev-src-sol-smartloyalty`. Cross-checked `PointsLogGenerator`'s `Query074-sql.xml` against both clones: identical, no deployment drift. Its actual logic: `DROP TABLE`/`CREATE TABLE`/`INSERT INTO SmlSt.CustomerPointsLog ... SELECT ... FROM Sml.CustomerPointsLog ... GROUP BY`. Confirms `SmlSt.CustomerPointsLog` is a deliberate staging layer, refreshed daily at 07:30 UTC by this one script reading the production table — `CustomerPointsLogToBlob` and `Actualiza_DWGrido_CustomerPointsBalance` (H12) both consume that staging copy downstream, not coincidentally. Useful for cross-validating script content; doesn't answer the duration question.

**Sch.Task/Sch.TaskEvent checked (Q31) — dead end for duration.** This schema is TaskOperatorService's own internal job engine for campaign-triggered actions (`MktAsignationPointActionManager`), a third scheduling mechanism entirely separate from the Windows Task Scheduler `\SmartFran\` folder. Doesn't track these 13 tasks at all — see `data/sch_task_schema_check_20260910.txt`.

**Correct source for duration: Windows Task Scheduler's own event log on `SFCG-TO-01`** (`Microsoft-Windows-TaskScheduler/Operational`, event IDs 100/102, paired by `ActivityId`) — staged as Q32 in `scripts.sql`.

**Q32 results (2026-09-10) — de-escalates H13 significantly.** Real per-execution durations, `data/task_duration_history_20260910.txt`: `Alerts Update` 44-76s, `AssignPointFirstSaleApp` <1s, `Program Results` 30-33s, `SendCanjesSocioCortesiaToBlobStorage` 11-20s, `SendDetalleCanjesSocioCortesiaToBlobStorage` 6-17s. **Every one of the 13 touching tasks has a brief individual execution (under ~80 seconds, most well under 20).** Also corrects an assumption: `SendCanjes.../SendDetalle...` do **not** run 24/7 as the "11:00-03:00 every 30min" documentation implied — real event history shows a genuine gap, no runs between ~03:00 and ~11:00 UTC daily. They're dormant, not just individually brief, during that stretch.

**Revised severity assessment:** an overlap between `PNSSRL_MantenimientoIndices`'s `Sch-M` lock and any of these 13 tasks means the background task **queues and runs once the lock releases** — it doesn't create sustained multi-hour contention, and it doesn't block the rebuild either (the rebuild already holds the lock; these are the ones waiting). This is a materially different, more tolerable risk than the ticket's original problem — MobileAppService's *live customer-facing* queries being blocked in real time. A report or blob export running late by up to the rebuild's duration is a real but much lower-severity cost than that.

**Given this, 08:00 UTC is back to being a reasonable recommendation** — not because it's conflict-free (it isn't, per H13's 13 tasks), but because the actual cost of those conflicts is now understood to be small (brief delays to background reporting/export tasks), not the severe live-blocking risk the schedule change exists to fix in the first place. Worth a final sanity check on `Program Results` specifically (the one daily, in-window touch) before treating this as settled — its business purpose/downstream consumers aren't yet confirmed, so "a report runs a bit late" is an assumption, not verified.

**Structural gap, flagged by the user (2026-09-10): none of SmartPedidos, SmartLoyalty, or SmartCloud have an official documented housekeeping/maintenance window.** This is *why* this recommendation had to be derived from first principles (piecing together POS hours, Backup_FULL's schedule, and one service's traffic profile) instead of checking against an existing standard — and it means every future maintenance-scheduling decision on any of these three platforms faces the same problem. Cross-platform, out of scope for this ticket's own action items — see `loyalty/docs/infrastructure.md` for a pointer note; the actual definition of an official window (if pursued) would need its own cross-project effort, not a PNSSRL-specific fix.

~~Original recommendation, before the Backup_FULL check — kept for the record, superseded above:~~ Option A — 00:30 UTC (21:30 UTC-3, the previous calendar day). It's the only one of the original 4 candidates where even the worst observed duration (6h14m11s) finishes (06:44 UTC) before hour 7's spike begins (07:00 UTC) — zero overlap with the single highest-traffic hour in any of the 25 observed runs. Its median-case exposure (16,795) is higher than Option C's (7,532), but Option C fully collides with the spike on the ~24% of days that run long, which is exactly the scenario this ticket exists to prevent — a single bad blocking event during peak hour matters more than shaving exposure on the common case.

**Caveats before this is final:**
- Recommendation is based on `SFCG-MOBI-01`'s traffic profile only (Q21's filter). `SFCG-CLUB-01` is also affected (H2's isolated `PromotionBranchOffice` blocking event) — its own hourly profile hasn't been checked; if materially different, it could shift this.
- Duration variability (H4, still unexplained) means 6h14m11s is the worst *observed*, not a guaranteed ceiling — a small additional safety margin (e.g., starting at 00:00 or 00:15 UTC instead of exactly 00:30) would add buffer against a future, longer run.
- Doesn't address root cause of the duration spread itself — a shorter, more consistent job would make any schedule safer; this recommendation works around the symptom, not the cause.
- **Resolved (Q23/Q24, 2026-09-09):** `Operaciones_MaintenancePlan_Backups.Backup_FULL` runs weekly at 06:00 UTC on Sunday/Monday/Wednesday — the current 06:15 UTC job start already overlaps an active full backup for its entire run on those 3 days. This is now factored into the recommendation above (23:30 UTC clears it with a 16-minute margin even in the worst case), so it's no longer an open caveat. Checked whether this schedule also explains H4's duration variability (Q24, weekday breakdown of all 25 runs): **partial correlation only, not confirmed causation** — Monday is a clear outlier (3/4 runs >3h), Sunday moderately elevated (2/4 >3h), but **Wednesday (same backup schedule) shows zero long runs** — weakening a pure I/O-contention explanation. Monday/Sunday-specific, possibly tied to weekend-accumulated fragmentation or GITIN-1866's confirmed weekend campaign traffic instead. H4 itself stays open regardless — this only affected the scheduling recommendation, not the root cause.

## Final state (2026-09-10) — chronogram persisted, recommendation stands

After Q32/H14's duration de-escalation reconfirmed 08:00 UTC (see above), the full hour-by-hour picture was consolidated into one artifact rather than left spread across `ops.md` prose: `db_schedule_chronogram.txt` (this event folder's root) — PoS active band, weekly-only jobs (`Backup_FULL`/`Depura Tempdb`/`CapturaUsoIndices`), the MobileAppService spike, the 13 brief `Sml.CustomerPointsLog`-touching tasks, the `SendCanjes/Detalle` window, and per-hour counts of the remaining ~40 `\SmartFran\` tasks confirmed clear of the table — plotted against both the current (06:15 UTC) and proposed (08:00 UTC) rebuild windows. Shown as an ASCII preview in chat and approved before persisting, per this session's visual-deliverable-preview convention.

A condensed Markdown version of the same hourly data (without the duration bars) was added as tables in two places for durable reference: `ops.md` (Acción propuesta 1, for this ticket's own record) and `loyalty/docs/task_operator_tasks.md` §4 (as a standing cross-ticket reference, since the underlying task inventory in that doc is reusable beyond this ticket). The per-hour "other tasks" counts in the Markdown tables were recomputed directly from `task_operator_tasks.md` §1's Schedule column (39 tasks, hour-bucketed) rather than reused from the earlier ASCII estimate — the two are consistent but the table version is the more precisely sourced of the two.

This closes out the investigative work for the scheduling objective. What remains is procedural, not analytical — see "Status" above.

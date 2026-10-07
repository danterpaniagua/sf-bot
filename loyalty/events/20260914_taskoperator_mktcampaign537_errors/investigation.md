# Investigation: TaskOperatorService errors — MktCampaignId 537

Jira: https://smartit-ar.atlassian.net/browse/GITIN-2036

## Trigger for this investigation

User reports TaskOperatorService threw several errors "yesterday" for `MktCampaignId: 537`, reported window **04:10–06:55 UTC-3**, described as "yesterday" (today = 2026-09-14, so nominally 2026-09-13, a Sunday).

**Date correction (confirmed against pasted evidence, contradicts the "yesterday" framing):** user then pasted a raw excerpt of the actual TaskOperatorService log (`data/taskoperatorservice_log_mktcampaign537_pasted.txt`). Its `Task execution fail on ...` lines are explicitly dated **9/14/2026** (today), not 9/13 — three consecutive entries at `7:10:59 AM`, `7:15:47 AM`, `7:20:50 AM`, all `+00:00` (UTC). This is real, dated evidence and takes precedence over the user's verbal "yesterday" — treating the actual event date as **2026-09-14**, not 2026-09-13, unless further evidence contradicts this. (04:10 UTC-3 = 07:10 UTC lines up with the first pasted failure almost exactly, so the *time-of-day* the user reported is confirmed correct — only the calendar date was off by one.)

Converted window, server time (SQL Server runs GMT/UTC+0, per `loyalty/CLAUDE.md`): **07:10–09:55 UTC, 2026-09-14**. 2026-09-14 is a **Monday** (confirmed by calendar math from today's date).

User's working hypothesis (**unconfirmed, not yet checked against data**): overlap with a backup / index-rebuild job.

## Confirmed from pasted log (`data/taskoperatorservice_log_mktcampaign537_pasted.txt`)

- Job: `MktAsignationPointActionManager - ActionId: 2508 - MktCampaignId: 537`, method `MktCampaignContext.MktAsignationPointActionService.DoPointAssignationAction(mktCampaignId, actionId)`.
- Exception is `Execution Timeout Expired` — an **ADO.NET client-side command-timeout**, not a SQL Server engine error. This is the exact symptom expected from a session queued behind a schema-modification lock (`LCK_M_SCH_S`) for longer than the client's command timeout — matches the mechanism confirmed in the `PNSSRL_MantenimientoIndices` blocking precedents (`events/20260816_club_grido_campaign_query_health/`, `events/20260901_pnssrl_mantenimientoindices_review/`), but that is a plausible mechanism, not yet a confirmed cause for *this* occurrence — needs the actual blocking data for this window.
- Four failures pasted so far, ~5 minutes apart: `7:10:59`, `7:15:47`, `7:20:50`, `7:26:00` UTC (`JTS[168898-345881-...]`, `-345883-`, `-345884-`, `-345885-` — `345882` missing from the pasted excerpt, likely just not pasted rather than a gap in reality). Consistent with a retry loop re-attempting the same `ActionId 2508` roughly every 5 minutes. Excerpt is user-pasted in real time and may still be arriving — full extent of failures across 07:10–09:55 UTC not yet known; `Sch.TaskEvent` pull (Q1 below) will give the authoritative full list once run.

## Prior context worth checking against before trusting the hypothesis

- `Sch.Task`/`Sch.Job`/`Sch.TaskEvent` (in `SmartFran.Solution.SmartLoyalty`) is TaskOperatorService's own internal job engine for campaign-triggered actions — confirmed in `events/20260901_pnssrl_mantenimientoindices_review/investigation.md` (Q31) and `docs/task_operator_tasks.md`. Job names for this action type are formatted `MktAsignationPointActionManager - ActionId: <N> - MktCampaignId: <N>` — this is almost certainly the source of the reported errors, and the first place to pull actual error detail from (`Sch.TaskEvent.EventCode`/`EventData`/`EventDate`, `Sch.Task.Failed`), rather than inferring cause from blocking/CPU data alone.
- `PNSSRL_MantenimientoIndices` (the daily index-rebuild job) was under active scheduling review as of 2026-09-10 in `events/20260901_pnssrl_mantenimientoindices_review/` (`GITIN-1981`). That investigation's last confirmed state: job ran daily at **06:15:00 UTC**, with a standing recommendation to move it to **08:00 UTC** — but nothing in this repo confirms that reschedule was ever actually applied. **Current live schedule must be re-confirmed here, not assumed from that ticket.**
- `Operaciones_MaintenancePlan_Backups.Backup_FULL` was confirmed (same ticket, Q23) to run weekly **Sunday/Monday/Wednesday at 06:00 UTC** — 2026-09-13 is a Sunday, so this job's scheduled day lines up with the reported error window. Actual run duration on that day is unconfirmed — needs its own `sysjobhistory` pull, not assumed.
- Both of the above being schedule-adjacent to the 07:10–09:55 UTC window is circumstantial timing, not confirmation — could easily be coincidental unless `Sch.TaskEvent`'s actual error content and precise timestamps, plus confirmed real (not theoretical) run windows for the backup/rebuild jobs on 2026-09-13 specifically, converge.

## Confirmed (Q3/Q4, `data/q3_q4_jobhistory_and_availability_20260914.txt`) — strong timing corroboration for the hypothesis, not yet proof

- **`Backup_FULL`**: ran 06:00:00–06:09:23 UTC, well before the error window. Not overlapping — rules this specific job out as a direct cause.
- **`Backup_Log`**: runs every ~10 min all day, each execution 1–35 seconds. Not a duration/contention factor on its own.
- **`PNSSRL_MantenimientoIndices`: ran 06:15:00–~10:22:29 UTC (4h07m29s), 2026-09-14.** Critically: **started at the original 06:15 UTC schedule — the reschedule to 08:00 UTC recommended in `GITIN-1981` was never applied** (or was reverted; not yet known which). Step 1 (the actual `ALTER INDEX REBUILD`/`REORGANIZE` + `UPDATE STATISTICS` sweep) ran the entire 4h07m28s; Step 2 conditionally kicked off `Backup_Log` at 10:22:28 once Step 1 finished (matches the known job structure from `GITIN-1981`). **This job's full execution window (06:15–10:22 UTC) fully encloses the reported error window (07:10–09:55 UTC).** The step-1 history message is truncated by SQL Server's own message-length cap before reaching `Sml.CustomerPointsLog` in the alphabetical table sweep, so whether *that specific table's* rebuild coincided with the errors isn't confirmed from this message alone — needs the `PNSSRL_AuditSysprocesses`/`comando_ejecutado` cross-reference to pin down which table was being rebuilt at each failure's exact timestamp.
- **`PNSSRL_AuditSysprocesses` data availability confirmed**: 33 snapshots, 07:11:00–09:51:00 UTC, ~every 4.8 minutes — enough resolution to cross-reference against the TaskOperator failure timestamps (07:10:59, 07:15:47, 07:20:50, 07:26:00, ...), though snapshot granularity means each failure's *exact* blocking state may fall between captures rather than exactly on one.

**This is timing correlation, not yet a confirmed causal link.** Next: pull the actual blocking chain from `PNSSRL_AuditSysprocesses` for this window to check whether a TaskOperatorService session (host `SFCG-TO-01`, likely login `sfsqlusr` per `docs/infrastructure.md`) was actually blocked, and by what, at each failure time — and pull `Sch.TaskEvent` (Q1, not yet run) for the authoritative full failure list and any richer error detail than the pasted log excerpt.

## Confirmed root cause (Q5/Q6, `data/q5_q6_blocking_chain_confirmed_20260914.txt`)

SPID 62 = hostname `SFCG-TO-01`, login `sfsqlusr` (TaskOperatorService's DB identity, per `docs/infrastructure.md`) was blocked (`lastwaittype = LCK_M_SCH_S`) by SPID 77 = `SFCG-DB01`, `SQLAgent - TSQL JobStep (Job 0x9B0BD93393BA1846BE961FADF915AE66 : Step 1)` — confirmed as `PNSSRL_MantenimientoIndices` — running `ALTER INDEX [IX_CustomerId] ON [SmartFran.Solution.SmartLoyalty].[Sml].[CustomerPointsLog] REBUILD;`. This blocking relationship was observed at 24 of the 33 captured snapshots, **near-continuously from 07:26 to 09:51 UTC** — spanning essentially the entire reported error window. **This is a confirmed causal mechanism, not timing correlation**: TaskOperatorService's own SQL Server session was held up by the exact same known blocking pattern documented in the `GITIN-1866`/`GITIN-1981` precedents (index rebuild on `Sml.CustomerPointsLog` → `LCK_M_SCH_S` on schema-stability → client-side ADO.NET command timeout).

**Side finding**: `Query084-sql.xml` (`E:\SmartLoyalty.TaskOperatorService\Domain\Query\`) has a `LoyaltyType` parameter with a `'completeCustomersOfParaguay'` mode filtering `C.CountryId = 9` — independent, code-derived support for the user's claim that a marketing campaign targets new Paraguay customers. **Not yet confirmed** whether this is specifically `MktCampaignId 537` (or `536` — user said both at different points, likely a slip, not resolved either way) — that mapping hasn't been checked against data.

## New hypothesis from user (2026-09-14, unconfirmed) — possible scripted/bot account creation

User's reasoning: 04:10–06:55 UTC-3 (07:10–09:55 UTC) is very early morning / late night in Argentina/Paraguay — an unusual time for organic customer sign-ups, raising suspicion of a scripted attack creating fake Paraguay accounts (which would in turn be what's triggering campaign `ActionId 2508`'s repeated point-assignment attempts). **This is the user's stated guess, not yet checked against data** — no query has confirmed new-customer volume, rate, or source for this window yet. Next queries (Q7/Q8) pull the actual `Sml.Customer` rows created in-window with `Country_Id = 9`, and check schema for any registration-source/channel column to distinguish Mobile app vs ClubSite (or a bot) as the origin — per this file's earlier "Command/Query Output" discipline, do not conclude "scripted attack" from the odd hour alone; confirm actual creation volume/pattern and origin first.

## Q7/Q8 results (2026-09-14) — "scripted attack" hypothesis not supported by this window's data

**Q7: zero rows.** No `Sml.Customer` rows with `Country_Id = 9` were created between 07:00-10:00 UTC on 2026-09-14. This directly weakens the user's "scripted attack creating new customers right then" framing — there were no new Paraguay signups, live or scripted, during the error window itself. **Correcting the working theory, not just noting a caveat**: whatever `ActionId 2508` was doing, it wasn't reacting to fresh account creations in this window.

**Reframed explanation, consistent with all evidence so far**: the ~5-minute retry cadence seen in the pasted TaskOperatorService log is very likely just `Sch.Task`'s own retry-after-failure scheduling (a task that times out gets rescheduled and retried), not a new triggering event each time. If `ActionId 2508` is working through a **backlog** of Paraguay customers created earlier (not necessarily today) that haven't yet been successfully processed — because every attempt times out from the index-rebuild blocking — it would retry on that same backlog repeatedly regardless of new signups. This is a plausible alternative, **not yet confirmed** — needs `Sch.Task`/`Sch.TaskEvent` history for this specific JobId to see actual failure count, `@Since` boundary used, and whether it ever succeeds.

**Q8: confirmed real column** `Sml.Customer.RegistrationChannel` (nvarchar) exists — usable to distinguish Mobile app vs ClubSite (vs other) origin once we have candidate customer rows to check. Not yet used since Q7 found none in-window.

## Q9 results (2026-09-14, `data/q9_task_history_actionid2508_full_20260914.txt`) — reframes the whole investigation: this is a DAILY recurring failure, not a one-off on 2026-09-14

2007-row `Sch.Job`/`Sch.Task` history for JobId `168898` (`MktAsignationPointActionManager - ActionId: 2508 - MktCampaignId: 537`) pasted by user, covering `ExecuteOn` from **2026-09-07 12:45** (the job's `ValidSince`) through **2026-09-14 11:55** (today, ongoing). This is a **recurring 5-minute task**, not a backlog being worked through — `ExecuteOn` advances in ~5-minute steps continuously, `Task_Done` (a datetime, confirmed not a bit as originally assumed in the Q9 comment) is set almost immediately after `ExecutionStarted` on success, and the `Failed` bit (not `Task_Failed`, the column literally named `Failed`) is `0` for the overwhelming majority of rows.

**Critical finding — `Failed = 1` clusters recur on every sampled day, always in the same ~04:10–04:40 local (07:10–07:40 UTC) window**, not only on 2026-09-14:
- 2026-09-08: TaskId 343302–343315 (~03:35–04:30 local)
- 2026-09-09: TaskId 343728–343742 (~03:45–04:35 local)
- 2026-09-10: TaskId 344159–344170 (~03:35–04:20 local)
- 2026-09-11: TaskId 344602–344613 (~03:45–04:30 local)
- 2026-09-14 (the reported incident): TaskId 345459–345468 (~04:10–04:40 local) — matches the pasted TaskOperatorService log and the confirmed blocking chain from Q5/Q6.
- 2026-09-12/09-13 not individually line-verified yet from this paste, but the pattern strongly suggests they follow the same shape.

**This changes the framing established earlier in this file**: the timeout mechanism (blocking by `PNSSRL_MantenimientoIndices`'s `ALTER INDEX REBUILD` on `Sml.CustomerPointsLog`, confirmed in Q5/Q6) is not a one-off collision on 2026-09-14 — it is a **structural, daily recurrence** that has been happening since this job (`JobId 168898`) was created on 2026-09-07, and will keep happening every day the index-rebuild job runs at its current 06:15 UTC start time (`ValidTo` for this campaign job is 2026-11-30, so this recurs for months absent a fix). The reported "several errors yesterday" symptom the user opened with is not an anomaly — it is the daily-normal failure mode of this campaign job, and 2026-09-14 just happened to be the day the user noticed it.

**Caveat on evidence persistence**: the full 2007-row Q9 result was pasted directly in chat; `data/q9_task_history_actionid2508_full_20260914.txt` contains a summary of the confirmed `Failed=1` clusters rather than a verbatim row-by-row dump, due to the result's size. The complete raw pasted text is preserved in this session's conversation history if a full re-verification is ever needed.

## Q10 results (2026-09-14, `data/q10.txt`, user-saved, 15,804 lines / 1.1MB — kept as raw evidence, not re-saved elsewhere)

Full `Sch.TaskEvent` history for JobId 168898 (`ActionId 2508 - MktCampaignId 537`), last 72h. Confirms everything above with exact detail:

- **Exact exception, all 104 occurrences identical**: `Execution Timeout Expired. The timeout period elapsed prior to completion of the operation or the server is not responding.` Stack trace: `SmartFran.Solution.SmartLoyalty.Service.MktCampaignContext.MktAsignationPointActionService.DoPointAssignationAction(Int32 mktCampaignId, Int32 actionId)` → `TaskProcess.MktAsignationPointActionManager.OnExecute(...)` (`MktAsignationPointActionManager.cs:line 38`) → `ScheduleApplicationService.RunSchedule`. This is a client-side ADO.NET command timeout, matching the mechanism already confirmed in Q5/Q6 (blocked by the index-rebuild job's `LCK_M_SCH_S`).
- **`MktCampaignId` confirmed as 537, not 536** — every `Step_Params` `<StepDefinition>` block in the 72h of data shows `<Item Code="MktCampaignId" Value="537" />` (1,728 occurrences), zero occurrences of `536`. The earlier "536" mention was a slip, now closed out.
- **Full extent of the 2026-09-14 failure window, previously only sampled from 4 pasted log lines**: **34 distinct failure timestamps** on 09-14, running continuously every ~5 minutes from **07:10:59 UTC through 09:55:48 UTC** (07:10, 07:15, 07:20, 07:26, 07:30, 07:35, 07:40, 07:45, 07:50, 07:56, 08:01, 08:05, 08:10, 08:15, 08:20, 08:26, 08:31, 08:36, 08:40, 08:45, 08:50, 08:56, 09:01, 09:05, 09:10, 09:15, 09:20, 09:25, 09:30, 09:35, 09:40, 09:45, 09:50, 09:55). This spans the full 07:10–09:55 UTC error window the user originally reported, and lines up almost exactly with the 07:26–09:51 UTC blocking window confirmed in Q5/Q6.
- **Same pattern also present on 09-12 (9 failures, ~06:56–07:40 UTC) and 09-13 (8 failures, ~07:01–07:45 UTC)** within this 72h window — independent confirmation of Q9's daily-recurrence finding, now with exact error text per occurrence rather than just task-history timestamps.

## User re-raised "scripted attack" hypothesis (2026-09-14, after Q9) — pushed back with existing evidence, not yet re-confirmed

User re-stated the scripted-attack guess ("Event time is weird cause means that there were creating new customer late night") after seeing the daily-recurrence finding. **This is not supported by evidence gathered so far, and was flagged to the user as such, not accepted into the record as fact**:
- Q7 already found **zero** `Sml.Customer` rows with `Country_Id = 9` created 07:00–10:00 UTC on 2026-09-14 — directly contradicts "customers being created" in that specific window.
- Q9 shows `ActionId 2508` is a **fixed 5-minute recurring schedule** (`Sch.Task`'s own engine), not triggered per new signup — so even if scripted signups were happening, they would not explain this job's retry cadence, which fires on a timer regardless of customer volume.
- Q7 only checked 2026-09-14 specifically; since Q9/Q10 confirm the failure recurs on 09-08 through 09-14, a single day's zero-result doesn't rule out signups on *other* days in the recurring window. Q11 (7-day Paraguay customer check, drafted, not yet run) would close this out fully if the user wants it run.

## Q11 results (2026-09-14, `data/q11.txt`, 929 rows) — "scripted attack" hypothesis now closed, not supported

Full 7-day Paraguay (`Country_Id = 9`) customer creation list. **Note**: this file contains real customer PII (email, document number) — analysis below is aggregate counts/patterns only, no raw values extracted or reproduced, per this repo's PII-handling rule.

- **929 Paraguay customers created over the 7-day window** (2026-09-07 through 09-14), channel mix: 733 APP, 120 WEB, 74 PUNTO DE VENTA, 5 blank/unknown — normal-looking distribution, no single-channel dominance suggesting a bot.
- **Hourly (UTC) distribution across the whole week is heavily weighted to normal daytime/evening hours** (peaks of 73–85 rows/hour in the 16:00–23:00 UTC range = daytime/evening in Argentina/Paraguay). The reported error window (07:00–09:00 UTC) is one of the quietest: only **12 rows across the entire 7-day period** (~1.3% of all weekly signups) fall in hours 07/08/09 UTC combined — 10 APP, 2 WEB, no anomalous channel skew.
- **Critically, zero of those 12 fall on 2026-09-07 or 2026-09-14** — the reported incident day has **zero** Paraguay signups in the 07–09 UTC window, consistent with Q7's earlier finding for that specific day. The 12 that do exist are spread thin across 09-08 (3), 09-09 (4), 09-11 (1), 09-12 (3), 09-13 (1) — no clustering, no spike, nothing resembling scripted/bulk creation.

**Conclusion**: the "scripted attack creating accounts late at night" hypothesis is **not supported** by any data gathered in this investigation — not on the incident day (Q7, Q11), not across the broader recurring-failure window (Q11), and mechanically ruled out regardless (Q9: `ActionId 2508` fires on a fixed 5-minute schedule, not per-signup). The odd hour of the *errors* is fully explained by the daily index-rebuild collision (Q5/Q6/Q9/Q10); it has nothing to do with when Paraguay customers sign up.

## Q12/Q13 results (2026-09-14) — `Sml.CustomerPointsLog` IS ALREADY PARTITIONED — chunked/current-year-only rebuild is a real, immediately available option

User asked whether the daily rebuild could be improved (chunked, or limited to recent data) instead of only rescheduling it. Ran diagnostics:

**Q12 — Edition confirmed live**: `Standard Edition (64-bit)`, `EngineEdition=2`, `ProductVersion 16.0.4075.1`, `RTM CU8` — matches `loyalty/CLAUDE.md`'s documented setup, now independently verified rather than trusted from the doc. `sys.dm_db_persisted_sku_features` returned **`Compression` and `Partitioning`** — both moved out of Enterprise-only status starting SQL Server 2016 SP1, and critically this DMV only lists features *already in active use* in this database, not just licensed — meaning some object here is already using table partitioning. (`ONLINE` index rebuild support is a separate, unconfirmed question — this DMV's absence of that feature only means it's unused so far, not unsupported; still needs Microsoft's official matrix for this build or a non-prod test before relying on it.)

**Q13 — confirmed `Sml.CustomerPointsLog` is partitioned** by scheme `sch_LogDate_Anual` (by `LogDate`, annual granularity), 16 partitions defined:
- Partitions 1–10: historical years, row counts ranging ~14.7M to ~76.1M, monotonically growing partition-to-partition (consistent with years fully closed out).
- **Partition 11: ~51.0M rows — almost certainly the current year (2026), still growing** (lower than partition 10's 76.1M because the year isn't over yet).
- Partitions 12–16: 0 rows — reserved for future years.
- **This partition alignment applies to the exact index we confirmed blocking TaskOperatorService** (`IX_CustomerId`), plus the clustered index and two other nonclustered indexes (`IX_CustomerPointsLog_SaleId`, `IX_CustomerPointsLog_Points`).
- **Exception**: `PK_dbo.CustomerPointsLog` (nonclustered PK, 397,001,384 rows) lives on a single filegroup (`PRIMARY`), **not partition-aligned** — a rebuild of this index specifically cannot be chunked by partition without first re-architecting it onto the partition scheme, a bigger change than what's proposed below.

**Implication**: historical years' data in a points/transaction log table is very unlikely to change after the fact, so partitions 1–10 have no real reason to be rebuilt daily — only the active partition (11, current year) accumulates new rows and fragmentation. If `PNSSRL_MantenimientoIndices` is currently rebuilding `IX_CustomerId` across the whole table (all partitions) rather than `REBUILD PARTITION = 11` only, that would explain a meaningful share of its multi-hour duration for this specific index, and switching to a partition-scoped rebuild is a **real, immediately available option** — no schema change needed, since partitioning already exists. This is additive to (not a replacement for) the reschedule already proposed in `GITIN-1981`: even a fast partition-scoped rebuild still needs *some* time slot, but a much shorter one would shrink the blocking window regardless of what time it runs.

**CONFIRMED (superseded the "not yet confirmed" note below) via Q15-Q19** — did not need to wait for tomorrow's Q14 run:

- `PNSSRL_MantenimientoModulos` parameters confirmed: `@base varchar(100), @modulo varchar(100), @tabla varchar(100), @fillfactor int` (Q15) — all called as `NULL` in the wrapper script (`queries/PNSSRL_MantenimientoIndices.sql`), meaning no table-level filter is applied today, but the procedure supports one.
- Found the (non-encrypted, fully readable) control table **`PNSSRL_TablasModulos`** (Q16/Q18) — one row per table/index the job processes, with `habilitado` (enabled) flags. `Sml.CustomerPointsLog` = `id_tablas_modulos = 292`, `habilitado = 1`. This is a real lever: a table could in principle be excluded from the daily sweep via this control table (not attempted, not proposed yet — would need to understand the enable/disable semantics fully first).
- Found **`PNSSRL_DetallesEjecucionTablasModulos`** (Q17 schema, Q19 data) — logs actual per-index execution: `filas` (rows processed), `ejecucion`/`fin_reindexado`/`fin_indexdefrag`/`fin_ue` timestamps, `fragmentacion`. This let us see **last night's real execution detail for `IX_CustomerId` directly, without waiting for tonight's Q14**.
- **`IX_CustomerId` on `Sml.CustomerPointsLog` (`id_tablas_modulos=292`, `indexid=8`) is CONFIRMED rebuilt as a full-table operation, not partition-scoped**: `filas = 396,999,055` on 2026-09-14 (≈ full table across all 11 populated partitions, not the ~51M-row active partition confirmed in Q13).
- **This single index accounts for the majority of the job's daily duration**: `ejecucion 07:08:15 → fin_reindexado 10:00:40` = **2h52m25s** on 2026-09-14, out of the job's total ~4h07m. On 2026-09-13 the same index took only **47m8s** (`filas` nearly identical, 396,787,362) — the swing is not explained by data growth, and is a plausible driver of `GITIN-1981`'s still-open H4 (duration variability) — likely self-contention from this rebuild against other sessions, not table growth.

**This upgrades H9 from a pending lead to a confirmed, high-confidence fix candidate**: scoping `IX_CustomerId`'s rebuild to the active partition only (via `REBUILD PARTITION = n`, once the exact partition number for the current year is confirmed against the partition function's boundary values — not yet done, see below) would cut the rows processed by this index from ~397M to ~51M, and very plausibly cut a large share of the ~2h52m–4h07m this step alone currently costs. Tomorrow's Q14 (planned to capture the live command text during tonight's run) is now optional/confirmatory rather than load-bearing — Q19 already answers the "does it already scope by partition" question definitively for two consecutive nights.

**Q20 result — partition_number confirmed with hard evidence, no more inference needed**: `fn_partition_LogDate_Anual` is `RANGE LEFT` (`boundary_value_on_right=0`), boundary dates confirm partition 1 = everything ≤ 2016-12-31 (historical catch-all), partition 2 = 2017 ... partition 10 = 2025, **partition 11 = 2026 (current year)**, partitions 12–16 = 2027+ (future, empty). Matches Q13's row counts exactly (partition 11's ~51.0M rows vs. partition 10's 76.1M ≈ 67%, consistent with September being ~69% through the year).

**Everything needed to propose a concrete fix is now confirmed**: `ALTER INDEX [IX_CustomerId] ON [SmartFran.Solution.SmartLoyalty].[Sml].[CustomerPointsLog] REBUILD PARTITION = 11;` would scope the rebuild to the ~51M active-year rows instead of the ~397M full table, targeting the single largest contributor (2h52m–4h07m on recent nights) to the job's total duration. Not drafted as an action statement yet pending the user explicitly requesting it (DDL is only generated on request per this project's read-only-by-default rule) — flagged here as ready, not yet proposed as a runnable command.

## Q21/Q22/Q23 results (2026-09-14) — confirmed: `ActionId 2508` cannot be rescheduled/paused, this is universal behavior of the job type, not a config option

User asked to check `MktAsignationPointActionManager`'s own configuration, given it was already established the job never has quiet hours — is that adjustable?

- **Q21 — `Sch.Job` schema has only 7 columns**: `Id, Name, Description, ValidSince, ValidTo, DeactivatedDate, DeactivateNote`. No recurrence-interval, active-hours, or blackout-window column exists anywhere in this table.
- **Q22 — full row for JobId 168898**: `Description = "Clase que realiza la asignación de puntos de fidelización de nuevos socios."` Nothing beyond what Q21's schema already showed.
- **Q23 — compared against every other `MktAsignationPointActionManager` campaign job since 2021** (campaigns 536, 535, 534, 533, 530, 526, 388, 354, 353, 351): **all of them show the identical ~5-6 minute average cadence**, regardless of campaign duration (from 8 tasks over a few hours up to 23,445 tasks over 2.5 months). This is not a bug or misconfiguration specific to campaign 537 — it is universal, by-design behavior of this job type, present since at least 2021.

**Conclusion**: there is no configuration lever anywhere in `Sch.Job` to give this job type quiet hours, and this isn't specific to campaign 537 to begin with — it's how the entire `MktAsignationPointActionManager` engine has always worked. Combined with H10's finding (rescheduling `PNSSRL_MantenimientoIndices` alone doesn't help this ticket), this closes off the "reschedule/pause the campaign job" avenue entirely. **The only real lever left for this ticket is duration reduction (H9) — partition-scoping the `IX_CustomerId` rebuild.** Changing this would require application-level code changes to the campaign engine itself (a much bigger change than anything in scope here), not a DB-side config tweak.

## Q24/Q25 results (2026-09-14) — no automated partition-boundary maintenance exists, and none has ever run

User asked whether annual partitioning was optimized (vs. e.g. quarterly/monthly) and when the boundary-maintenance would next run.

- **Q24**: searched every SQL Agent job in `msdb` (by name and by step command text) for anything touching partition maintenance (`SPLIT RANGE`, `PARTITION FUNCTION`, the scheme/function names) — **zero results**. No automated job adds new yearly boundaries.
- **Q25**: `fn_partition_LogDate_Anual`'s `create_date` and `modify_date` are identical (`2023-11-08 10:44:16.940`) — the function has **never been altered since creation**. All 15 boundaries (through 2030) were defined in one shot at setup, not added incrementally by any process since.

**Implication**: the ~4 years of remaining runway (2027-2030 boundaries already exist) is not being actively maintained by anything — it was simply provisioned generously once. This isn't an urgent problem (no action needed before 2030), but it is an unowned gap: nobody appears to be watching this, and if it's still unaddressed as 2030 approaches, new data would start silently falling into partition 16 (the catch-all "beyond last boundary" partition) instead of getting its own year-partition, degrading exactly the kind of partition-scoped-rebuild benefit this ticket is proposing. Worth a note in `ops.md`'s hallazgos secundarios as a related-but-out-of-scope risk, not an action for this ticket.

**Correction to existing repo doc**: `loyalty/docs/task_operator_tasks.md` (written during `GITIN-1981`) describes `MktAsignationPointActionManager` jobs as "campaign-triggered... not on any fixed daily schedule." That's true in the narrow sense of not being a single fixed-time daily run like `PNSSRL_MantenimientoIndices`, but it undersells the operationally relevant fact confirmed here: these jobs run continuously every ~5 minutes with zero quiet hours for their entire `ValidSince`-`ValidTo` lifetime, which matters a great deal for blocking-collision risk. Worth updating that doc so a future investigation doesn't repeat this same false lead (assuming these jobs are schedulable/reschedulable when they aren't).

## Q26 results (2026-09-14) — the "exclude whole table" risk is resolved by data: only `IX_CustomerId` is ever actually rebuilt

User pushed back on whether "exclude `Sml.CustomerPointsLog` + add scoped `IX_CustomerId` rebuild" was really the best choice, since `PNSSRL_TablasModulos` governs at table granularity, not per-index — excluding the table would also stop maintenance on the clustered index, `PK_dbo.CustomerPointsLog`, `IX_CustomerPointsLog_SaleId`, and `IX_CustomerPointsLog_Points`, none of which had been individually checked yet.

Pulled full execution history (Q26) for all 5 indexes under `id_tablas_modulos=292`, not just `IX_CustomerId`:

- **`fin_reindexado` (REBUILD) is confirmed to NEVER fire for the other 4 indexes**, across the entire ~20-night sample available in `PNSSRL_DetallesEjecucionTablasModulos`.
- **`fin_indexdefrag` (REORGANIZE) fires only 4 times total** across the same ~20 nights, scattered across 3 of those indexes (clustered index once, `IX_CustomerPointsLog_SaleId` once, `IX_CustomerPointsLog_Points` twice) — everything else, no action.
- Their logged `fragmentacion` stays consistently low (0-5%), `PK_dbo.CustomerPointsLog` always 0 — well under typical rebuild/reorganize thresholds, explaining why they're rarely touched.
- All 5 indexes share the same table-level `ejecucion` (start) and `fin_ue` (end-of-run, stats-update) timestamps — confirming `ejecucion`/`fin_ue` are per-table-run markers, not per-index; only `fin_reindexado`/`fin_indexdefrag` are genuinely per-index.

**Conclusion**: excluding `Sml.CustomerPointsLog` from the daily job would not be silently abandoning active maintenance on those 4 other indexes — they're already barely maintained by it (near-zero rebuild/reorganize activity, consistently low fragmentation). The replacement step's real scope is much smaller than initially worried: (1) partition-scoped `IX_CustomerId` rebuild — the actual fix; (2) optionally, occasional light reorganize checks for the other 3 partition-aligned indexes, mirroring their current (very low) real-world need; (3) statistics update for the table, replicating the `fin_ue` step. This substantially de-risks the "exclude + custom step" approach — it was already the right direction, and this closes the one open gap in it.

## Q27-Q31 results (2026-09-14) — broader impact confirmed, and a correction to the "no config lever" claim

User pushed on two fronts: (1) is `MktCampaignId 537` really the only thing affected, given the blocking mechanism is table-level not campaign-specific; (2) does TaskOperator's scheduling engine actually reschedule one task at a time, and does `Sch.Job`/`Sch.TimeTable` really offer no configuration lever.

**Q27**: confirmed `MktCampaignId 537` is currently the ONLY active `MktAsignationPointActionManager` job (1 row). No other campaign of this exact type is at risk right now.

**Q28**: 91 other currently-active `Sch.Job` entries exist, spanning many job types — ~74 are ephemeral `SendMailCustomerNewCard` jobs (per-customer, ~24h validity, unrelated to `CustomerPointsLog`), plus a long tail of real recurring processors. One stands out: **`EtlDwGridoCustomerPointsLogProcessor`** (JobId 755, active since 2019-12-26, valid through 2029-12-01) — its name directly references this table.

**Q29**: only 2 not-yet-executed tasks exist for JobId 168898 at any time (not a bulk-pregenerated calendar) — consistent with just-in-time, one-at-a-time task creation as the user suspected. Side finding, not investigated further here: the earliest pending task (`2026-09-08 17:00`) is 6 days old and still shows `ExecutionStarted IS NULL` — a possibly-stuck/orphaned task, unrelated to this ticket's scope but worth someone's attention. `TimeTableId = 168898` (same value as `JobId`) confirmed a 1:1 relationship between each job and a `Sch.TimeTable` row.

**Q30 — correction to earlier "no config lever" claim, then CONFIRMED with exact values after `GRANT SELECT ON Sch.TimeTable TO sfzabbix` was applied (user-run, production permission change)**: `Sch.TimeTable`'s schema (readable via `INFORMATION_SCHEMA.COLUMNS` even without table-level `SELECT` rights) has real scheduling columns: `Enabled`, `ActiveStartDate`, `ActiveEndDate`, `FrecuencyType`, `FrecuencyInterval`, `FrequencyRecurrenceFactor`, `FrecuencySubDayInterval`. Initial read attempt hit `SELECT` permission denied (`Msg 229`); user granted `SELECT` to `sfzabbix` and re-ran the query. **Confirmed row for `Id=168898` (= `TimeTableId` for `JobId 168898`)**:

| Column | Value |
|---|---|
| `Enabled` | 1 |
| `ActiveStartDate` | 2026-09-07 00:00:00 -03:00 (= job's `ValidSince`) |
| `ActiveEndDate` | 2026-11-30 23:59:59 -03:00 (= job's `ValidTo`) |
| `Name` | NULL |
| `FrecuencyType` | `Minutes` |
| `FrecuencyInterval` | `5` |
| `FrequencyRecurrenceFactor` | 0 |
| `FrecuencySubDayInterval` | 00:00:00 (unused — `FrecuencyType`/`FrecuencyInterval` fully define the cadence directly) |

**This definitively confirms the 5-minute interval is a simple, directly configurable value** (`FrecuencyInterval = 5`), not something baked into unreadable application code — a real correction to the "not confirmed, not ruled out" framing from moments earlier in this same investigation. **However**, `ActiveStartDate`/`ActiveEndDate` mirror the job's own campaign validity window, not a daily window — there is genuinely no time-of-day or day-of-week exclusion concept in this schema. So the earlier finding stands in the sense that mattered most (no built-in "quiet hours" field), but the blanket claim that nothing about this job's schedule is configurable was wrong — the interval itself is a real, low-technical-risk lever (a single-value config change) that was missed initially because `Sch.Job` alone doesn't show it.

**Follow-up: can two `Sch.TimeTable` rows coexist for the same job (day/night split, e.g. 5min day / 10-15min night)? Checked against the actual application source, not just the DB schema.** `loyalty/repo/dev-src-sol-smartloyalty/` (local read-only clone) has `Front/TaskOperatorService/TaskOperatorService.cs`, the real scheduling engine. Line 168: `scheduleSvc.EstimateNextExecution(task.Job.ValidSince, task.TimeTable)` — `task.TimeTable` is a **singular** navigation property; the engine resolves exactly one `TimeTable` per task/job, with no code path anywhere in this file that selects between multiple candidate rows based on time of day or any other condition. This confirms (via source, not inference) that a second `Sch.TimeTable` row for the same `JobId` would simply never be read — the engine has no mechanism to alternate between two schedules. Also found real precedent for how this system has actually been changed historically: `Other/SqlScript/Updates/v5.11/v5.11_UpdateTimetableEtlSmlCustomerTarget.sql` is a single `UPDATE` to an *existing* row's `FrecuencySubDayInterval` for a different job (`EtlSmlCustomerTarget`) — not an insert of a second row. **Conclusion: two coexisting `Sch.TimeTable` rows for one job is not supported by this architecture.** A day/night effect would instead require a separate small automation that updates the single existing row's `FrecuencyInterval` on a schedule (e.g., widen at night, narrow during the day) — mechanically workable since the engine reads the row's live value each time it schedules the next task, but this is a different, slightly riskier implementation (a second scheduled toggle that must itself run reliably) than the user's original proposal.

**Trade-off to flag clearly**: widening `FrecuencyInterval` (e.g., 5→30 minutes) would not eliminate collisions with the index rebuild — some attempts would still land inside the blocking window — but would sharply cut how often the campaign job attempts access during that window, reducing retry noise and session churn. This is a genuinely different kind of change than the partition-scoped rebuild: lower technical risk (one integer value vs. excluding a table and building a new job), but a **business/campaign-cadence decision** (how fast new-member point assignment should run), not a purely technical one — needs sign-off from whoever owns the campaign engine, not just DBA/Operations.

**Q31 — independent, concrete confirmation of broader impact**: `EtlDwGridoCustomerPointsLogProcessor` runs daily at a fixed 07:25 UTC — inside the maintenance window. Across the last 7 days: 2026-09-14 took 4h55m22s, 09-13 3h02m21s, 09-12 3h00m11s, 09-11 4h08m44s, 09-10 1h56m25s, 09-08 3h58m40s (all `Task_Failed=0`, i.e. eventually succeeded but very slow) — and 09-09 **failed outright** after 20m34s with a chained exception: `BusinessRulesException` → `EntityException` → `SqlException` ("Connection Timeout Expired... pre-login handshake") → `Win32Exception` ("wait operation timed out"). The `SqlException` here is a **connection-establishment** timeout, not a lock-wait timeout like campaign 537's — suggesting server-side resource contention during the rebuild, not purely table-level locking. Full detail in `data/q30_q31_timetable_and_etldwgrido_20260914.txt`.

**This raises the ticket's real scope**: this is not campaign-537-specific. A second, independently-confirmed system (a daily data-warehouse ETL feed) is measurably degraded every day this maintenance window runs — multi-hour delays most days, one outright failure in the 7-day sample. The partition-scoped-rebuild fix (H9) still directly helps this too, since it's the same root blocking mechanism against the same table.

**Correction needed**: `loyalty/docs/task_operator_tasks.md`'s note (added earlier this session) stating there's "no way to reschedule or pause these jobs at the DB config level" needs softening — `Sch.TimeTable` exists and looks configurable; the correct statement is "not confirmed readable/configurable with the access available in this investigation," not "does not exist."

**Mechanism to apply it — confirmed, and it's NOT a config-table toggle.** Full row for `id_tablas_modulos=292` (`Sml.CustomerPointsLog`) in `PNSSRL_TablasModulos` (already had this from Q18's `SELECT *`, no new query needed): `modulo='Sin Asignar'` (every row in the 200-row sample showed this — the module-grouping feature doesn't appear to be in active use), `indexado=1` (rebuild enabled), `defragmentacion=1` (reorganize enabled — explains the two separate completion columns in Q19, `fin_reindexado` vs `fin_indexdefrag`, the encrypted procedure picks one path per table at runtime, presumably by fragmentation threshold), `porcentaje_actualizacion_estadisticas=0`, `habilitado=1`. **No partition-scope column exists in this control table** — its only levers are whole-table on/off switches. This means partition-scoped rebuild cannot be configured through `PNSSRL_TablasModulos`; it would require setting `indexado=0` (and/or `habilitado=0`) for this one row to exclude `CustomerPointsLog` from the daily sweep, plus a separate, small, non-encrypted script/job step doing the partition-scoped rebuild directly. This is itself a state-changing config-table update (`UPDATE PNSSRL_TablasModulos SET indexado=0 WHERE id_tablas_modulos=292`) plus new job/script work — a real, scoped change, not a trivial toggle, and not yet drafted.

## Business-logic mechanics (2026-09-14) — failure/reschedule behavior, idempotency, and an open gap on overlap protection

User asked: when a task fails, does it reschedule, and if so, could rescheduled tasks overlap? Checked directly against source (`loyalty/repo/dev-src-sol-smartloyalty/`), not inferred.

**`DoPointAssignationAction`** (`Core/Application/Service/MktCampaignContext/MktAsignationPointActionService.cs`): fetches new customers via a watermark attribute (`lastNewCustomer` on the campaign action), calls `AddGiftPointsToCustomer` per customer (which commits individually — `ApplyChanges()` runs inside the per-customer domain method, not as one batch transaction for the whole run), and only advances the watermark **after the entire loop completes without exception**.

**Initial concern, ruled out after reading further**: if a run fails mid-batch (customer N of M times out), customers processed before N already have committed points, but the watermark never advances — this looked like a duplicate-crediting risk on the next run. **Ruled out**: `Query084-sql.xml` (the actual customer-selection query) has an independent `EXCEPT` clause that excludes any customer who already has a `NewCustomer` entry in `Sml.CustomerPointsLog`, checked directly against real data, not the watermark. So a failed/interrupted run **loses no work and creates no duplicates** — already-processed customers keep their points and are excluded from the next run's batch; not-yet-reached customers simply wait for the next successful run. This is a genuinely idempotent design, and stronger confirmation (from source, not inference) of what `H8` already suspected.

**Do failed tasks reschedule?** Yes, but not via a special failure-triggered retry — every task (success or failure) results in exactly one "next task" created at the normal `TimeTable`-defined interval (+5 min), confirmed both by the `TaskEvent` pattern (`StepEnded`/`Ended` with exception → `Created` → `Rerun` tagging the original failed task) and by source (`EstimateNextExecution` is called unconditionally on `task.TimeTable`, not gated on task outcome).

**Could rescheduled tasks overlap? Honest gap, not fully confirmed.** Empirically: every `ExecuteOn` observed sits on a strict, non-skipping 5-minute grid, and every execution (including failures, which time out at ~30s matching the ADO.NET command timeout) completes well under 5 minutes — no overlapping `ExecutionStarted`/`Done` windows have been observed in any data gathered. But the actual concurrency-guarding logic (does `RunSchedule` prevent starting a new task for a job while a previous one is still `InExecution`?) lives in `SmartFran.Business.Schedule.Service.ScheduleContext.ScheduleApplicationService` — a shared library **not present in this local repo clone** (`Front/TaskOperatorService/TaskOperatorService.cs` only calls into it, doesn't implement it). This is a real, currently-unconfirmed question, not a verified "no" — it simply hasn't been tested, because no execution has ever taken long enough to find out. Relevant if evaluating the interval-widening idea (action 5): a longer interval doesn't introduce this risk, but the underlying question remains open regardless.

## Duration pattern by day-of-week (2026-09-14) — refines the "contention, not growth" framing in H9

User asked to find an example of a 2.5-3h `IX_CustomerId` rebuild on a day WITHOUT `Backup_FULL` (Sun/Mon/Wed). **None exists in the available sample** — checked all 20 nights in `data/q26.txt` (`indexid=8`) against day-of-week:

| Date | Day | `Backup_FULL` day? | Duration |
|---|---|---|---|
| 08-26 | Wed | Yes | 57m55s |
| 08-27 | Thu | No | 48m8s |
| 08-28 | Fri | No | 47m17s |
| 08-29 | Sat | No | 1h10m32s |
| 08-30 | Sun | Yes | 47m56s |
| **08-31** | **Mon** | **Yes** | **2h46m32s** |
| 09-01 | Tue | No | 49m33s |
| 09-02 | Wed | Yes | 47m7s |
| 09-03 | Thu | No | 48m10s |
| 09-04 | Fri | No | 47m40s |
| 09-05 | Sat | No | 50m15s |
| **09-06** | **Sun** | **Yes** | **2h37m47s** |
| **09-07** | **Mon** | **Yes** | **2h34m32s** |
| 09-08 | Tue | No | 55m4s |
| 09-09 | Wed | Yes | 49m26s |
| 09-10 | Thu | No | 48m1s |
| 09-11 | Fri | No | 47m20s |
| 09-12 | Sat | No | 48m19s |
| 09-13 | Sun | Yes | 47m8s |
| **09-14** | **Mon** | **Yes** | **2h52m25s** |

**Pattern is sharper than "backup day correlates with long duration"**: all four 2.5h+ runs are specifically **Sunday or Monday** — never Wednesday (08-26, 09-02, 09-09 are all short, 47-58min, indistinguishable from non-backup days), and never a non-backup day at all (Tue/Thu/Fri/Sat cap out around 1h10m, most much shorter). This is a real refinement of `GITIN-1981`'s own H10 finding, which described the backup correlation as "weakened, not ruled out" using a smaller/different sample — this larger, more recent sample shows a much cleaner Sun/Mon-specific pattern than that ticket found. Possible explanation (not verified, flagged as speculation only): Sunday and Monday backups run back-to-back (no Tuesday backup in between), which could compound I/O/log pressure in a way Wednesday's isolated backup doesn't — but this is a hypothesis, not confirmed.

**Not yet investigated**: whether this changes the recommended fix. The partition-scoped rebuild (H9/action 4) still reduces the *amount of data* processed regardless of day, which should shrink even the worst-case Sun/Mon duration substantially — this finding doesn't invalidate that fix, but does suggest the day-of-week pattern deserves its own line of investigation (matching against `Backup_Log`'s behavior, transaction log growth, or I/O contention specifically on Sun/Mon) if duration variability itself becomes a separate concern after the partition fix lands.

## Status (last updated 2026-09-14, after H14)

**Root cause and full scope confirmed.** `Execution Timeout Expired` on `MktAsignationPointActionManager - ActionId: 2508 - MktCampaignId: 537` is caused by SPID blocking from `PNSSRL_MantenimientoIndices`'s full-table `ALTER INDEX REBUILD` on `Sml.CustomerPointsLog` (Q5/Q6). Daily recurring since the campaign job's creation (2026-09-07), not a 09-14 one-off — 34 distinct failures on 09-14 alone (Q10). `MktCampaignId` confirmed as 537, not 536.

**Scope is broader than one campaign.** A second, independently-confirmed victim exists: `EtlDwGridoCustomerPointsLogProcessor` (daily DW ETL feed), degraded 1h56m-4h55m on 6 of the last 7 days, one outright failure (Q31). No other `MktAsignationPointActionManager` campaign is currently active (Q27).

**The originally-assumed fix (GITIN-1981's reschedule) does NOT resolve this ticket.** `ActionId 2508` runs 24/7 on a fixed 5-minute cadence with zero quiet hours — confirmed universal to this job type since 2021 (Q9, Q23), and confirmed unconfigurable-away via any daily blackout window (Q30: `Sch.TimeTable` has no time-of-day field, only a campaign-wide date range). Rescheduling the maintenance job only relocates the collision to a different part of the day for this specific victim — still valid for GITIN-1981's *other* victims (MobileAppService, POS, Zabbix), which do have real quiet hours.

**Three real, non-mutually-exclusive fix candidates are now on record, none applied yet:**
1. **Partition-scoped rebuild (primary recommendation)** — `Sml.CustomerPointsLog` is already partitioned by year (Q13/Q20); `IX_CustomerId` is rebuilt as a full ~397M-row operation when only the active partition (~51M rows) needs it. Mechanism confirmed: exclude the table from the encrypted daily sweep (`PNSSRL_TablasModulos`, `id_tablas_modulos=292`) + a new, separate, non-encrypted job doing `REBUILD PARTITION = n` (dynamically computed, not hardcoded). Risk of abandoning the table's other 4 indexes ruled out (H11 — they receive near-zero maintenance already). Draft script in `scripts.sql`, with risks/rollback documented in `ops.md`. Not tested in non-prod, no recurring job built yet.
2. **Widen the campaign's polling interval** — confirmed real and simple (`Sch.TimeTable.FrecuencyInterval=5`, directly editable), but this is a business/campaign-cadence decision, not purely technical, and doesn't eliminate the collision, only reduces how often it's hit. Confirmed two `Sch.TimeTable` rows can't coexist for day/night split (source code check, `TaskOperatorService.cs`) — a single-row toggle automation would be needed for that effect, not attempted.
3. **GITIN-1981's reschedule** — still worth applying, but only helps the *other* victims, not this ticket.

**Also confirmed, lower priority**: the failure/retry mechanism is idempotent and safe (no point loss or duplication — verified against actual source, `Query084-sql.xml`'s dedup logic); annual partitioning is adequate for now but has no owner maintaining future boundaries (~4 years of runway, `GITIN-1981`-adjacent, separate ticket territory); duration variability (H4 from `GITIN-1981`) is more precisely explained by Sunday/Monday-specific `Backup_FULL` adjacency than generic contention (H14) — refines but doesn't change the recommended fix. One open, unresolved technical question: whether the scheduling engine prevents overlapping task execution if a run ever exceeded the 5-minute interval — can't confirm, the relevant source (`ScheduleApplicationService`) isn't in the local repo clone.

**Not yet done**: applying any fix, building the recurring job for option 1, getting business sign-off for option 2, sending `email_ops.md` (drafted, current, not sent).

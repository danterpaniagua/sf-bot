# TaskOperatorService — Task Inventory Reference

**Host:** `SFCG-TO-01`. **Source investigation:** `events/20260901_pnssrl_mantenimientoindices_review/` (GITIN-1981).

`SmartLoyalty.TaskOperator.Service` (the real service name; a mismatch against `Solution.SmartLoyalty.TaskOperatorService` silently broke its own health check, GITIN-1828, `events/20260812_taskoperator_alert_not_running/`) hosts **three unrelated scheduling/execution mechanisms**. Do not conflate them; GITIN-1981 needed all three to check `Sml.CustomerPointsLog` contention.

| # | Mechanism | What it is |
|---|---|---|
| 1 | Windows Task Scheduler, `\SmartFran\` folder | ~54 independently scheduled `.ps1` scripts, each calling a numbered `QueryNNN-sql.xml` (a few have no DB query) |
| 2 | `Etl` framework: `Etl.EtlOperationConfig` / `Etl.EtlOperationExecution` (in `SmartFran.Solution.SmartLoyalty`) | Config-driven data-sync operations executed by TaskOperatorService |
| 3 | `Sch` schema: `Sch.Task` / `Sch.Job` / `Sch.TaskEvent` (same database) | TaskOperatorService's internal job/task/step engine for ad-hoc, campaign-triggered business actions |

---

## 1. Windows Task Scheduler — `\SmartFran\` folder

Scripts live at `Front/SmlBackScript/` in the source repo (`loyalty/repo/dev-src-sol-smartloyalty/`); a deployed mirror with credentials stripped is at `loyalty/repo/SmartLoyalty.SmlBackScript/` (identical to source for `PointsLogGenerator`, checked 2026-09-10).

- **Schedule times** are as returned by `Get-ScheduledTaskInfo` on `SFCG-TO-01`, treated as UTC directly (same precedent as `infrastructure.md`'s `Check_list_SF` cadence vs GMT incident times). Not re-verified against the server's OS timezone. Day-of-week for the weekly/monthly tasks was never checked via `Get-ScheduledTask` trigger data.
- **"Touches `Sml.CustomerPointsLog`"** was verified against the query content (`Front/SmlBackScript/Query/QueryNNN-sql.xml`), not by task or script name; name matching proved unreliable (`PointsLogGenerator` looked unrelated). Two traps: (a) a second, unrelated `Query/` folder exists at `Core/Domain.Query/Domain/Query/` with overlapping numeric filenames — always resolve against `Front/SmlBackScript/Query/`; (b) match bracketed notation too (`[Sml].[CustomerPointsLog]`).
- **Purpose** is the query author's own `<Description>` (translated), not inferred from names. Where none exists the row says so and gives the name-based reading in brackets.

| Task | Script | Query | Purpose | Touches CPL? (run time) | Schedule (UTC) |
|---|---|---|---|---|---|
| Alerts Update | AlertGenerator.ps1 | Query008 | Alerts (no further detail) | **TOUCHES** (44-76 s) | 07:00 daily |
| AssignPointFirstSaleApp | AssignPointFirstSaleApp.ps1 | Query046 | Assigns points for a customer's first purchase via an exclusive app promotion | **TOUCHES** (<1 s) | 04:00 daily |
| AssignPointNewCustomers_New | AssignPointNewCustomers.ps1 | Query080 | Assigns points to customers who registered yesterday | **TOUCHES** | dormant (no `NextRunTime`, last ran 2025-04-09) |
| Calculate Weight Grams Per BranchOffice | WeightGramsPerBranchOffice.ps1 | Query032 | None recorded [grams sold per branch] | clear | 10:00 daily |
| Cancel Customer Account | CancelCustomerAccount.ps1 | Query006 | Processes account cancellation requests | clear | 08:30 daily |
| Check_list_SF | ServicesAndTaskStatus.ps1 | none | Checks whether `TaskOperatorService` is running (GITIN-1828) | n/a | every 5 min |
| Clean Mistery | FreeMistery.ps1 | Query007 | Releases pending "mystery" gift purchases | clear | every 30 min |
| ClickExportsBranchOffice | ClickExportsBranchOffice.ps1 | Query078 | Weekly export of favorite branch offices per franchise | clear (`SmlSt` staging schema) | 11:15 weekly |
| ClubGrido Consignment AR | ClubGridoConsignmentAR.ps1 | Query015 | Factory consignment settlements | clear | 11:00 weekly |
| ClubGrido Consignment PY | ClubGridoConsignmentPY.ps1 | Query015 | Same query as AR | clear | 12:00 weekly |
| CountPushNotificationsMonthly | PushNotifications.MonthlyReport.ps1 | Query035 | Monthly push notifications activated per franchise | clear | 11:30 monthly |
| Customer Mailing Generator | CustomerMailingGenerator.ps1 | Query012 | Generates the mailing table | clear | 07:30 daily |
| CustomerAndCardAmount | CustomerAndCardAmount.ps1 | Query025 | Customers/cards with and without purchase data, per franchise | clear | 08:05 daily |
| CustomerFavoriteBranchOffice | CustomerFavoriteBranchOffice.ps1 | Query034 | Sets each customer's favorite franchise from consumption | clear | 10:10 daily |
| CustomerPointLog_to_BlobStorage | CustomerPointsLogToBlob.ps1 | QueryCustomerPointsLog | Extracts the member points table to blob storage | clear (reads `SmlSt.CustomerPointsLog`, the staging copy `PointsLogGenerator` maintains; see §2) | multiple runs/day |
| Customers Evolution Update | CustomerEvolutionGenerator.ps1 | Query009 | Processes customers and pending customers | clear | 08:00 daily |
| DailyServerStorage | DailyServerStorage.ps1 | none | None recorded [disk-storage reporting] | n/a | 01:01 daily |
| Deactivate Recovery Codes | DeactivateRecoveryCodes.ps1 | Query013 | Invalidates codes older than 10 days, deactivates expired account recoveries | clear | 08:30 daily |
| DeactivateAccountRecovery90Days | DeactivateAccountRecovery90Days.ps1 | none | None recorded [90-day account-recovery deactivation] | n/a | 09:00, irregular cadence |
| DeactivateSuscriptionByVigencyPromotion | DeactivateSuscriptionByVigencyPromotion.ps1 | none | None recorded [subscription deactivation tied to promotion validity] | n/a | 07:15 daily |
| Delete Today Sale Customer | DeleteTodaySaleCustomer.ps1 | Query019 | Clears the `TodaySaleCustomer` table | clear | 03:01 daily |
| DeleteCustomerPendingData | DeleteCustomerPendingData.ps1 | Query022 | Deletes old pending-customer data or data of customers who completed registration | clear | 06:45 daily |
| ExchangeReportsMonth | ExchangeReportsMonth.ps1 | Query041+042 | Frequent-consumption alert report; monthly redemptions report | **TOUCHES** | 08:00 monthly |
| FranchisesWithManualCardTyping | FranchisesWithManualCardTyping.ps1 | none | None recorded [franchises using manual card entry] | n/a | 11:00 monthly |
| Generate Location | LocationGenerator.ps1 | Query010 | Generates the `Location` table | clear | 10:32 daily |
| NotSamplesSurveyActivated | NotSamplesSurveyActivated.ps1 | Query054 | Active/valid surveys that returned no sample data | clear | 12:05 daily |
| Orphans Notify | OrphansNotify.ps1 | Query001+002 | Looks up and updates "orphan" records | clear | 09:30 daily |
| PointsFranchisePY | PointsFranchisePY.ps1 | Query073 | Total accumulated points per franchise | **TOUCHES** | 10:45 weekly |
| PointsLogGenerator | PointsLogGenerator.ps1 | Query074 | Rebuilds the `SmlSt.CustomerPointsLog` staging table from `Sml.CustomerPointsLog` | **TOUCHES** (`DROP`/`CREATE`/`INSERT...SELECT...GROUP BY` on the production table) | 07:30 daily |
| Program Results | ProgramResults.ps1 | Query031 | Description is `.` only; purpose not confirmed | **TOUCHES** (30-33 s) | 11:00 daily |
| Promotion Vigency Advisor A | PromotionVigencyAdvisorA.ps1 | Query004 | Emails special users about promotions expiring within 10 days | clear | 11:40 daily |
| Promotion Vigency Advisor B | PromotionVigencyAdvisorB.ps1 | Query005 | Emails special users about promotions taking effect but not activated, and recently created ones | clear | 12:20 weekly |
| Promotion Vigency Advisor C | PromotionVigencyAdvisorC.ps1 | Query011 | Same description as B (copy-pasted; query text differs) | clear | 12:30 weekly |
| RegistrationMembersPY | RegistrationMembersPY.ps1 | Query072 | Member sign-up processing | clear | 10:45 weekly |
| Report Franchise ClubGrido | ReportFranchiseClubGrido.ps1 | Query058 | Franchises with ClubGrido | clear | 09:00 monthly |
| ReportCampaingAutoG | ReportCA.ps1 | none | None recorded [automated campaign report] | n/a | 10:30 monthly |
| ReportCampaingAutoGWeek | ReportCAWeekly.ps1 | none | None recorded [weekly variant of the above] | n/a | 11:00 weekly |
| ReportErrorSurveyNoResponse | ReportErrorSurveyNoResponse.ps1 | none | None recorded [no-response survey error report] | n/a | 12:00 daily |
| ReportFrequentlyConsumption | ReportFrequentlyConsumption.ps1 | Query003 | Frequent-consumption alerts to franchisees | clear | 11:00 weekly |
| ReportManualPointsAssignmentIndividual | ReportManualPointsAssignmentIndividual.ps1 | Query070 | Points traceability report | **TOUCHES** | 11:00 weekly |
| ReportManualPointsAssignmentLists | ReportManualPointsAssignmentLists.ps1 | Query069 | Same, for bulk lists | **TOUCHES** | 11:00 weekly |
| ReportPointsTransfer | ReportPointsTransfer.ps1 | Query064 | Monthly points-transfer report | **TOUCHES** | 11:30 monthly |
| ReportSampleMailResponseXSurvey | ReportSampleMailResponseXSurvey.ps1 | Query060+061 | Surveys sent (SML) and received (DW) | clear | 06:00 daily |
| ReportsAssociation | ReportsAssociation.ps1 | Query071 | Complete and pending member sign-ups (Paraguay) | clear | 11:00 monthly |
| ReportSurveyUnsatisfied | ReportSurveyUnsatisfied.ps1 | Query049 | Unsatisfied-survey responses | clear | 10:00 daily |
| ReportUpdateCustomer | ReportUpdateCustomer.ps1 | Query062+063 | Mass member-update report | **TOUCHES** | 12:00 monthly |
| RunExportsCustomersFails | RunExportsCustomersFails.ps1 | Query036 | Re-runs member-export campaigns that failed | clear | ~13:00 |
| RunProccessETLFails | RunProccessETLFails.ps1 | Query0000 | None recorded [retries failed ETL processes] | clear | ~14:00 |
| SaleGrams | SaleGrams.ps1 | Query023 | Grams sold via promo vs regular sale | clear | 08:30 daily |
| SaleMix | SaleMix.ps1 | Query024 | Sales mix per franchise | clear | 08:45 daily |
| SendArticlesToBlobStorage | SendArticlesToBlobStorage.ps1 | Query075 | Exports Articles data to PowerBI and Concentrador | clear | 10:00 daily |
| SendCanjesSocioCortesiaToBlobStorage | SendCanjesSocioCortesiaToBlobStorage.ps1 | Query076 | Exports member courtesy-point redemptions; **its author flagged it "(Robo de Puntos)" ("Points Theft")** | **TOUCHES** (11-20 s) | every 30 min, **only 11:00-03:00 UTC** (dormant 03:00-11:00) |
| SendDetalleCanjesSocioCortesiaToBlobStorage | SendDetalleCanjesSocioCortesiaToBlobStorage.ps1 | Query077 | Detail records for Query076, same author flag | **TOUCHES** (6-17 s) | every 30 min, same 11:00-03:00 window |
| SendMailDailyReportDisk | SendMailDailyReportDisk.ps1 | none | None recorded [daily disk-usage email] | n/a | 23:30 daily |
| TaskOperatorDailyReports | ReportWarningsTaskOperator.ps1 | Query052 | TaskOperator warnings report | clear | 11:00 daily |

- **Fraud cross-reference:** Query076/077 are the only entries whose own description names a fraud concern ("Robo de Puntos") for the courtesy-point redemption pattern. Not checked against `loyalty/memory/` or the `fraud-points`/`fraud-pos` skills.
- **Risk reading:** touching `Sml.CustomerPointsLog` matters only if something else holds a conflicting lock at the same time (e.g. `PNSSRL_MantenimientoIndices`'s offline rebuild, `Sch-M` for its duration). Every touching task runs under 80 s where measured, so a conflict delays the task until the lock releases; it does not create sustained contention. Scheduling analysis: GITIN-1981.

---

## 2. `Etl` framework

`Etl.EtlOperationConfig` (definitions) and `Etl.EtlOperationExecution` (execution history), in `SmartFran.Solution.SmartLoyalty`, executed by TaskOperatorService (`SFCG-TO-01`, login `sfsqlusr`).

**Real schema** (the staged queries Q29a/Q29b in `events/20260901_pnssrl_mantenimientoindices_review/scripts.sql` assumed column names that do not exist):
- `Etl.EtlOperationConfig`: `Id, ToTable, FromQuery, Mappings, BatchSize, SetSize, InputConnStr, OutputConnStr, DeleteFirst, FullTable, IdLimits, MaxExecutionPeriod, UpdateColumns, UpdateWhereColumns` — **no name and no schedule/trigger column**; trigger timing is inferred from execution history or from `Sch.Job` (§3).
- `Etl.EtlOperationExecution`: `Id, TotalRows, Started, LowerLimit, UpperLimit, Completed, EtlOperation_Id`.

**Operations** (30-day history to 2026-09-22): 9 active, all **daily**, no day-of-week gating.

| ConfigId | ToTable | Typical start (UTC) | Typical duration |
|---|---|---|---|
| 1 | `dbo.Sale` | ~08:55 | 200-800 s, up to ~4500 s |
| 2 | `dbo.Location` | ~07:10 | 20-27 s |
| 3 | `dbo.Exchange` | ~08:40 | 50-70 s (occasional multi-thousand-second outliers) |
| 4 | `dbo.SaleCustomer` | ~08:25 | 300-700 s |
| 5 | `dbo.Customer` | ~07:55 | 50-160 s (occasional multi-thousand-second outliers, e.g. Mondays) |
| 6 | `dbo.CustomerPointsLog` | 05:00 (07:25 until 2026-09-23) | **3-6+ h, chronically slow** |
| 7 | `dbo.BranchOffice` | ~08:10 | 13-26 s |
| 11 | `Sml.Target` | ~08:00 | <5 s |
| 15 | `dbo.PointsTransference` | ~13:00 | <10 s |

**`CustomerPointsLog` (Id=6):**
- Trigger moved from ~07:25 to 05:00 UTC effective 2026-09-24 (`Sch.TimeTable.Id=755`, GITIN-2060 third iteration, §3).
- Cause of the slowness: a non-sargable `OR` predicate plus a `COUNT(*) OVER()` pre-query in its `FromQuery` (`events/20260715_cpu_spikes/`). A `UNION ALL` rewrite is drafted and was tested in `events/20260925_etl-customerpointslog-sargable-rewrite/` (GITIN-2108): same 153,082 rows and checksum as the current query over a real 24 h window, both branches already have seek support (clustered key `LogDate`; `__IX_Customer_CreatedDate`), and a duplicate-rows bug of the first draft for `@LowerBoundary IS NULL` was fixed. Result is mixed: CPU ~3.3x lower (950 s vs 286 s) but elapsed ~2x higher (145 s vs 300 s), `CustomerPointsLog` reads ~2x and a new worktable; not recommended for production yet and not applied. The operation reads through `SmlConnString` and writes through `DwConnString` (OLTP → a separate data warehouse), and how much of the 3-6 h is the source query versus the batched writes was never measured.
- Runs all 7 days, typically 3-6 h; one outlier of 25.9 h (Wed 2026-09-09 to Thu 2026-09-10, probably why no Thursday trigger fired that day; not confirmed). Average by weekday, outlier excluded: Mon ~5.4 h, Tue ~4.6, Sun ~3.9, Sat ~3.3, Fri ~3.2, Thu ~3.0, Wed ~2.65.
- **Can reach `Backup_FULL`** (09:00 GMT on Sun/Wed/Fri): it starts 05:00 UTC and typically runs 3-6 h, so a run of 4 h or more overlaps the backup on those days (derived from durations, overlap not measured since the reschedule). Candidate for its own ticket.
- This is a **different** sync target (`dbo.CustomerPointsLog`) from `PointsLogGenerator`'s `SmlSt.CustomerPointsLog` staging table: two independent sync mechanisms read the same production table, unaware of each other.

---

## 3. `Sch` schema — internal campaign-action engine

`Sch.Task` / `Sch.Job` / `Sch.TaskEvent`. It does **not** track the `\SmartFran\` Windows tasks; it is the internal engine for ad-hoc business actions (`Sch.TaskEvent.Operator` is always `SmartFran.Solution.SmartLoyalty.Front.TaskOperatorService.exe`). Confirmed example: `MktAsignationPointActionManager`, jobs named `MktAsignationPointActionManager - ActionId: <N> - MktCampaignId: <N>` (marketing-campaign point assignment).

**Columns**
- `Sch.Job`: `Id, Name, Description, ValidSince, ValidTo, DeactivatedDate, DeactivateNote` — no recurrence, active-hours or blackout column.
- `Sch.Task`: `Id, ExecuteOn, ExecutionStarted, Done, DeactivatedDate, DeactivateNote, TimeTableId, Failed, JobId, CanceledDate, CanceledNote`.
- `Sch.TimeTable` (1:1 with `JobId` via `Sch.Task.TimeTableId`): `Id, JobId, Enabled, ActiveStartDate, ActiveEndDate, Name, FrecuencyType, FrecuencyInterval, FrequencyRecurrenceFactor, FrecuencySubDayInterval` (a `time` column), resembling SQL Agent's `sysschedules`.
- `Sch.TaskEvent`: `Id, JobId, TaskId, StepId, Job_Name, Job_ValidSince, Job_ValidTo, Job_DeactivatedDate, Job_DeactivateNote, Task_ExecuteOn, Task_ExecutionStarted, Task_Done, Task_DeactivatedDate, Task_DeactivatedNote, Task_CanceledDate, Task_CanceledNote, Task_Failed, Step_Command, Step_Params, EventData, EventCode, EventDate, Operator`.

**Cadence (GITIN-2036):** `MktAsignationPointActionManager` jobs run on a fixed **~5-minute cadence, 24/7, with no quiet hours**, for the campaign's whole `ValidSince`-`ValidTo` life; checked against every such campaign job since 2021. It is universal to the job type, not to one campaign. The interval is **configurable**: campaign 537's `TimeTable` row has `FrecuencyType='Minutes'`, `FrecuencyInterval=5`, so a single-row `Sch.TimeTable` update changes it (not hardcoded). `ActiveStartDate`/`ActiveEndDate` only mirror the job's `ValidSince`/`ValidTo`; there is no time-of-day or day-of-week blackout field. Changing a cadence is a business/campaign decision (it changes how fast real customers get points), not purely a DBA one. Detail: `events/20260914_taskoperator_mktcampaign537_errors/investigation.md` (Q21-Q23, Q29-Q30).

**Link to §2's `Etl CustomerPointsLog`** (`events/20260922_gitin2060-mantenimientoindices-reschedule/`): `Sch.Job.Id=755`, `Name=EtlDwGridoCustomerPointsLogProcessor`, is the trigger of `Etl.EtlOperationConfig.Id=6`. Its `Sch.TimeTable` row (`Id=755`, `FrecuencyType='Daily'`, `FrecuencyInterval=1`, `FrecuencySubDayInterval=07:25:00` before the move) matched the operation's known trigger time, and its `Sch.Task` history (20 rows, 2026-09-04 to 2026-09-23) fired at 07:25 UTC daily with `Done` 2h48m to 5h+ later.

**Rescheduling a daily job:** the time of day is `Sch.TimeTable.FrecuencySubDayInterval` (not `ActiveStartDate`'s time, `00:00:00` and irrelevant for `Daily`/interval-1). A permanent change is a one-row update of that column for the job's `TimeTable` row (Id 755 for the Etl CPL job). `dbo.RescheduleTask` is the wrong tool: it updates only one `Sch.Task.ExecuteOn` occurrence, never `Sch.TimeTable`. A task row already generated keeps its old time (the 2026-09-24 task had been generated at 07:25 before the change; the new time applied from the next day's generation).

**Reading `Sch` state and TaskOperatorService incidents (`GITIN-1828`, `events/20260812_taskoperator_alert_not_running/`):**
- The service `SmartLoyalty.TaskOperator.Service` on `SFCG-TO-01` stopped 2026-08-11 20:06 GMT; an automatic restart failed on the 30000 ms timeout (Service Control Manager 7009/7000) and it stayed down until a manual start at 11:25 GMT (~15h19m). `Check_list_SF` never noticed because its script named the wrong service; fixed in the deployed `ServicesAndTaskStatus.ps1` (backup `.bak_20260812`), still to be applied in the version-controlled copy. Why it stopped, and a stop/disable/restart sequence on 08-11 12:20-12:31 GMT, were never explained.
- `OnStart` recovers pending tasks synchronously one by one, so a manual start after a long outage is slow.
- A task whose **last `Sch.TaskEvent` is `Rerun` is not necessarily stuck**: 27 looked blocked and all had `Sch.Task.Done` set and their next run already scheduled. Read `Sch.Task` (`Done`, `ExecuteOn`), not the last event. `UPDATE Sch.Task SET ExecuteOn` does not run anything (no `Created` event is generated for the scheduler) and `dbo.ReRunTask` rejects a duplicate of an existing pending task.

**Not explored:** other job types in this engine besides `MktAsignationPointActionManager`, and whether any touch `Sml.CustomerPointsLog`.

---

## 4. Daily and weekly load picture (UTC)

Applied schedule after GITIN-2060 (third iteration). Windows tasks from §1; day-of-week for weekly/monthly ones is unconfirmed, so their rows give time of day only.

**Every day**

| Time (UTC) | What runs |
|---|---|
| 00:00-24:00 | `Backup_Log` every 10 min; `Sch.Job` campaigns every 5 min; `Check_list_SF` every 5 min; `Clean Mistery` every 30 min; `CustomerPointLog_to_BlobStorage` several runs |
| 01:01 / 03:01 / 04:00 | DailyServerStorage; Delete Today Sale Customer; AssignPointFirstSaleApp (touches CPL, <1 s) |
| 05:00 | `Etl CustomerPointsLog` starts (3-6 h; a run of 4 h or more reaches `Backup_FULL` at 09:00 on Sun/Wed/Fri) |
| 06:00-07:30 | ReportSampleMailResponseXSurvey (06:00); DeleteCustomerPendingData (06:45); Alerts Update (07:00, touches CPL); Etl Location (07:10); DeactivateSuscriptionByVigencyPromotion (07:15); Customer Mailing Generator and PointsLogGenerator (07:30, the latter touches CPL) |
| 07:55-09:00 | Etl Customer (07:55), Target (08:00), BranchOffice (08:10), SaleCustomer (08:25), Exchange (08:40), Sale (08:55); Customers Evolution Update (08:00); CustomerAndCardAmount (08:05); Cancel Customer Account, Deactivate Recovery Codes, SaleGrams (08:30); SaleMix (08:45); DeactivateAccountRecovery90Days (09:00) |
| 09:00-10:15 | `Backup_FULL` (09:00 Sun/Wed/Fri, 7-8 min for the loyalty database); `PNSSRL_MantenimientoIndices` (09:00, ~45 min) and `..._CustomerPointsLog` (09:15) on their days; Orphans Notify (09:30); ReportSurveyUnsatisfied, SendArticlesToBlobStorage, Calculate Weight Grams (10:00); CustomerFavoriteBranchOffice (10:10) |
| 10:32-14:00 | Generate Location (10:32); Program Results and TaskOperatorDailyReports (11:00, Program Results touches CPL); Promotion Vigency Advisor A (11:40); ReportErrorSurveyNoResponse (12:00); NotSamplesSurveyActivated (12:05); Etl PointsTransference and RunExportsCustomersFails (~13:00); RunProccessETLFails (~14:00) |
| 11:00-03:00 | `SendCanjes...`/`SendDetalleCanjes...SocioCortesia` every 30 min (touch CPL, 6-20 s) |
| 23:30 | SendMailDailyReportDisk |

**Day-restricted items (the only ones whose day changed under GITIN-2060)**

| Item | Days | Time | Notes |
|---|---|---|---|
| `Backup_FULL` | Sun, Wed, Fri | 09:00 GMT | 7-10 min observed (`GITIN-2112`; `backupset` 2026-09-30 to 10-28); schedule read from `msdb` 2026-10-28 |
| `PNSSRL_MantenimientoIndices` | Mon, Tue, Thu, Sat | 09:00 | ~45 min, excludes `Sml.CustomerPointsLog` |
| `PNSSRL_MantenimientoIndices_CustomerPointsLog` (`idx_cpl`) | Mon, Tue, Thu, Sat | 09:15 | cold run 58m47s, warm run 3m29s |

- **`Backup_FULL` schedule, settled from `msdb` on 2026-10-28:** weekly, `freq_interval` 41 (Sun + Wed + Fri), start 09:00:00 GMT; 85 `backupset` rows from 2026-09-30 to 2026-10-28 show every full backup on those days at 09:00. The Mon/Wed/Fri 06:00 statement of the earlier hourly analysis is superseded; the duration is 7-10 minutes, not ~2 h. `Backup_Log` is daily. Index maintenance days (Mon/Tue/Thu/Sat, `freq_interval` 86) never coincide with the backup days, but the maintenance job's step 2 starts `Backup_Log`. Other `msdb` facts of that read: the schedule of `PNSSRL_MantenimientoIndices_CustomerPointsLog` is named `Daily_0815UTC` but is weekly (Mon/Tue/Thu/Sat) and starts 09:15 GMT (the name is stale); `PNSSRL_MantenimientoIndices_Lunes` and `_Miercoles` exist but are **disabled** (Mon 06:30; Wed/Thu 06:30). Every Sunday a second set of instantaneous full backups of all databases appears at about 11:31-11:41 GMT (4 Sundays seen; no job named Backup is scheduled then; origin not identified). Other SQL Agent jobs outside this inventory: `Depura Tempdb` Sun 03:00, `CapturaUsoIndices` Thu/Fri 23:00.
- **`PNSSRL_MantenimientoIndices` facts (`GITIN-2112`, `events/20260928_gitin2112-mantenimientoindices-backup-overlap/`):** schedule Mon/Tue/Thu/Sat 06:00 Argentina (09:00 GMT), `schedule_id=23`, so no Friday/Sunday run is by design; its step 2 starts `Operaciones_MaintenancePlan_Backups.Backup_Log` (not a coincidental overlap); durations of successful runs vary from 33 min to 2h14m, so duration alone says nothing about health. It failed Sat 2026-09-26 after 15m14s inside step 1 (schema `Mbr`); the error text is cut by SQL Agent's storage limit (~3200 bytes in `sysjobhistory.message`), and backup size, overlap with the CustomerPointsLog job, and load (`PNSSRL_CapturaCheckDB`, `DBCC CHECKDB`, ran Monday 07:00-10:02 GMT for 3 h and never on Saturday) were all ruled out against a heavier successful Monday: cause not confirmed, read as transient. Mitigation applied 2026-09-28: `retry_attempts=2, retry_interval=5` on step 1 (not exercised: 0 retries used on Tue 09-29). "Long Sync IO" in the error log is routine noise. To catch a recurrence, capture the real error with an Extended Events session during the window.
- **`idx_cpl` duration (GITIN-2061, `events/20260922_gitin2061-ix_customerid-partition-rebuild/`):** first live run (2026-09-22, cold, fragmented) took 58m47s (`sysjobhistory.run_duration` is `HHMMSS`-packed, not seconds), so it ran solo until ~10:13, ~28 min past `idx_main`'s 09:45 finish. Second run (2026-09-24, warm) took 3m29s. Starting at 09:15 inside `idx_main`'s window, the two jobs overlap by design. Expect the first run after any gap in the schedule to run long. Not a confirmed blocking risk (the jobs no longer share a locked object, GITIN-2061).
- **Weekly Windows tasks (time only):** ClubGrido Consignment AR 11:00, RegistrationMembersPY and PointsFranchisePY (CPL) 10:45, ClickExportsBranchOffice 11:15, ClubGrido Consignment PY 12:00, ReportCampaingAutoGWeek 11:00, ReportFrequentlyConsumption 11:00, ReportManualPointsAssignmentIndividual/Lists (CPL) 11:00, Promotion Vigency Advisor B 12:20 and C 12:30.
- **Monthly Windows tasks:** Report Franchise ClubGrido 09:00, ReportCampaingAutoG 10:30, FranchisesWithManualCardTyping 11:00, ReportsAssociation 11:00, CountPushNotificationsMonthly 11:30, ReportPointsTransfer (CPL) 11:30, ReportUpdateCustomer (CPL) 12:00, ExchangeReportsMonth (CPL) 08:00.
- Also not shown: the `SFCG-MOBI-01` traffic spike at 07:00-08:00 UTC. Full annotated chronogram with the `PNSSRL_MantenimientoIndices` rebuild comparison: `events/20260901_pnssrl_mantenimientoindices_review/db_schedule_chronogram.txt`.

---

## Related

- `events/20260901_pnssrl_mantenimientoindices_review/` (GITIN-1981): source of §1 and the `Sml.CustomerPointsLog` scheduling-conflict analysis.
- `events/20260715_cpu_spikes/`: root cause of the `Etl` `CustomerPointsLog` operation's slowness.
- `events/20260812_taskoperator_alert_not_running/` (GITIN-1828): origin of the `Sch` schema discovery and of the service-name mismatch behind the `Check_list_SF` failure.
- `events/20260922_gitin2060-mantenimientoindices-reschedule/` (GITIN-2060): full `Etl` operation list, schema findings and the `Backup_FULL`/CPL ETL overlap.
- `infrastructure.md` → "Scheduled Tasks (`SFCG-TO-01`)": partial inventory; this doc is the exhaustive reference.

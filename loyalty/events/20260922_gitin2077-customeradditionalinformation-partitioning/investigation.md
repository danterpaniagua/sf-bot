# Investigation: Partition SmlSt.CustomerAdditionalInformation

**Jira:** [GITIN-2077](https://smartit-ar.atlassian.net/browse/GITIN-2077) (subtask of GITIN-2074; precedent: GITIN-1267)

## Status

**Deferred/discarded (2026-09-22) — high execution risk against a speculative, undated benefit.** Design work below (DDL through Part 2, corrected trigger design, cutover sequence) is complete and kept for the record, but the user decided not to proceed with actual execution after a risk-vs-benefit reassessment. No prior event folder existed for this ticket before today — the original design work happened directly in `loyalty/todo/TODO.md` in a prior session (2026-09-20/21), without an `investigation.md` first artifact; this folder captured that, extended the design, then concluded it shouldn't be executed yet.

**Why deferred (2026-09-22):**
- **Actual measured cost today is small.** This table's full daily maintenance (all 4 indexes, including two `REBUILD`s at 83-84% fragmentation) took ~3.5 minutes (`events/20260922_gitin2078-customeradditionalinformation-index-rotation/data/post_run_confirmation_20260922.txt`, 05:05:17-05:08:50). No blocking incident has ever been reported for this table's own maintenance — unlike `Sml.CustomerPointsLog`, which had three real production incidents (GITIN-1866, GITIN-2036, GITIN-2076) that justified GITIN-2060/2061's urgency.
- **Structurally different from `CustomerPointsLog`, which motivated the original "partition this too" instinct.** `CustomerPointsLog` grows by appending one row per point-earning event forever (397M rows, climbing) and is read/written by many app tiers simultaneously. `CustomerAdditionalInformation` is `DELETE`+`INSERT` — at most one row per customer, ever (confirmed via the code review below) — used by exactly one hot path (3 `SaleProviderController` endpoints). Row count tracks distinct paying customers, not sales volume. A rough 13x extrapolation (~64M rows) lands around 30-45 minutes of maintenance if scaling linearly — real, but nowhere near the multi-hour blocking risk `CustomerPointsLog` had, especially now scheduled in a low-traffic window (GITIN-2060).
- **The migration itself carries meaningful execution risk**, taken on now against a benefit tied to a franchise-growth timeline (200→2600) that was never actually dated: a live shadow-table cutover with dual-write triggers on a POS checkout hot path, with real failure modes already identified during design (backfill/trigger races, cutover sequencing, trigger cleanup).
- **Conclusion**: legitimate technical debt worth tracking, not an active problem worth a risky live migration right now. Cheaper to execute this migration later with real data (actual measured maintenance-time growth, actual franchise-count timeline) than to carry execution risk today against a projection.

**Revisit trigger**: if this table's daily maintenance time grows materially (e.g. crosses into the 15-20+ minute range, signaling it's becoming a real blast-radius concern) or a concrete franchise-growth timeline emerges, reopen this design rather than starting over — it's fully captured below.

## Context (carried forward from TODO.md, not re-derived)

`SmlSt.CustomerAdditionalInformation` (~4.9M rows today, `SmartFran.Solution.SmartLoyalty`) is time-sensitive to address: franchise count is planned to grow from ~200 to ~2600 (13x), and this table scales roughly with it — any future migration gets progressively more expensive the longer it waits.

**Confirmed facts:**
- **No natural date/historical column exists.** `LastBuyDate` mutates on every purchase (unlike `Sml.CustomerPointsLog`'s `LogDate`, which is append-only) — rules out date-range partitioning the way `CustomerPointsLog` uses it.
- **Table is WebServiceV2-exclusive** — confirmed via source (`SaleProviderApplicationServiceV2.GetCustomerAdditionalInformation`, called from the POS checkout flow to show the cashier a customer's favorite product/average weight). Zero references in `MobileAppService`. Not a "last transactions" list, as originally assumed before checking the source (see `events/20260920_cpu-spikes/investigation.md`).
- **Not currently partitioned** — confirmed via `sys.indexes` (`events/20260920_cpu-spikes/data/06_partition_check.txt`): single `partition_number=1`, `partition_scheme`/`partition_function` both `NULL`.

**Design decided (2026-09-21):**
- **Partition key: hash-partition by `CustomerId`** — a computed, persisted `CustomerIdBucket` column (`ABS(CHECKSUM(CustomerId)) % N`). Not a hot/cold split (no natural date column makes that impossible here) — the goal is purely to bound future maintenance blast-radius, not to isolate rarely-touched data.
- **Migration approach: shadow table, not in-place rebuild.** An in-place rebuild would be one big blocking operation, and would only get worse as the table grows. Instead: build a shadow table (`..._New`) partition-aligned from creation, backfill in small batches, dual-write via an `AFTER INSERT/UPDATE` trigger on the original table during the migration window, then cut over via `sp_rename` (near-instant) instead of a rebuild.
- **SQL Server Change Tracking/CDC** was considered as a lighter-weight alternative to the trigger for dual-write, but **Standard-edition availability was never verified** — flagged explicitly not to assume it, per the `WITH (ONLINE = ON)` mistake earlier in GITIN-2074 (Standard edition doesn't support online index rebuilds either — a similar edition-assumption error, don't repeat the pattern).

**Bucket count decided (2026-09-22): `N=16`.** Reasoning: at 13x growth (~64M rows projected), 16 partitions gives ~4M rows/partition — comparable to today's *entire* table size, which is already known to be safe/fast (the two-index build completed in under 2 minutes on 4.9M rows). `N=32` was considered (finer blast-radius, ~2M rows/partition at scale) but rejected as unnecessary headroom that doubles partition-administration overhead. Not a platform constraint either way — SQL Server 2022 Standard supports up to 15,000 partitions/table.

**Yearly/date-based partitioning reconsidered and re-rejected (2026-09-22).** Directly verified the table's full column list (`INFORMATION_SCHEMA.COLUMNS`, 8 columns: `Id, CustomerId, LastBuyDate, FavoriteProduct, AverageWeight, CardNumber, UidSerie, UidCode`) rather than trust the inherited "no natural date column" claim. Confirmed: `LastBuyDate` is the only date-type column, and no `CreatedDate`/`RegisteredDate`/append-only timestamp exists. Since `LastBuyDate` mutates in place on every purchase, date-range partitioning would require physically moving a row to a different partition on every purchase — the opposite of what `Sml.CustomerPointsLog`'s yearly partitioning gets right (its `LogDate` is append-only per event). Hash-by-`CustomerId` remains the only viable key.

**Application code review (2026-09-22, `data/write_path_source_review_20260922.txt`)** — checked the real write path before designing the dual-write trigger, rather than assume:
- Writes are **`DELETE` then `INSERT`, never `UPDATE`** — `Query102-sql.xml` (affiliated, keyed by `CustomerId`) and `Query103-sql.xml` (pending, keyed by `CardNumber` or `UidCode`+`UidSerie`, `CustomerId` always `NULL`), both invoked once per sale from `SaleService.AddAdditionalInformation`. This means the dual-write trigger needs `AFTER INSERT` + `AFTER DELETE`, not `AFTER INSERT, UPDATE` as first drafted.
- **App never reads back the generated `Id`** — no `SCOPE_IDENTITY()`/`OUTPUT INSERTED`/`@@IDENTITY` anywhere against this table; the `int` returned is a hardcoded success flag, not the identity value. This removes the need for `IDENTITY_INSERT`/`DBCC CHECKIDENT` reseeding entirely — the shadow table can have its own independent `IDENTITY(1,1)` sequence, since nothing outside the DB cares about `Id` matching between old and new table.
- No positional inserts, no `SELECT *`, no EF model (none exists anywhere in this codebase — raw SQL pass-through throughout), no index-name hints against this table. Structurally safe for the app.
- Each row's own stored `CustomerId`/`CardNumber`/`UidCode`/`UidSerie` values are self-consistent with which query wrote them, so a `DELETE` trigger can reconstruct the correct shadow-table delete target purely from `DELETED`'s own values, exactly matching the app's own branching — confirmed against the exact SQL text of both query templates (`Query102-sql.xml`: `DELETE ... WHERE CustomerId = {0}`; `Query103-sql.xml`: `DELETE ... WHERE UidCode=@UidCode AND UidSerie=@UidSerie` when `@CardNumber IS NULL`, else `DELETE ... WHERE CardNumber=@CardNumber`).

**Prechecks confirmed before finalizing shadow-table DDL (2026-09-22):**
- **No foreign keys reference this table** (`data/fk_check_20260922.txt`, zero rows) — the clustered-key change (`Id` alone → `(CustomerIdBucket, Id)`) has no downstream referential-integrity impact.
- **`Id` is `IDENTITY(1,1)`** (`data/identity_check_20260922.txt`) — confirmed directly via `sys.identity_columns` rather than inferred from the column name. Combined with the "app never reads `Id` back" finding above, the shadow table just needs its own independent `IDENTITY(1,1)`, no value-preservation needed.
- **Exact column types** (`data/exact_column_types_20260922.txt`): `FavoriteProduct NVARCHAR(MAX)`, `CardNumber NVARCHAR(100)`, `UidSerie NVARCHAR(100)`, `UidCode NVARCHAR(50)` — corrected an initial DDL draft that had placeholder `NVARCHAR(MAX)` for the three shorter columns.

**DDL drafted (Parts 1-2, revision 2 — not yet executed):**
- Part 1: `pf_CustomerAdditionalInformation_Bucket` (RANGE LEFT, 15 boundaries → 16 partitions) + `ps_CustomerAdditionalInformation_Bucket`, all partitions on `[PRIMARY]` (single filegroup — sufficient for the blast-radius goal, no physical I/O isolation needed; per-partition filegroups would add backup/restore complexity not required here).
- Part 2: `SmlSt.CustomerAdditionalInformation_New`, exact column types, `CustomerIdBucket AS (ABS(CHECKSUM(CustomerId)) % 16) PERSISTED`, clustered PK `(CustomerIdBucket, Id)` partition-aligned, plus the 3 nonclustered indexes (`CustomerId`, `CardNumber`, `UidCode`+`UidSerie` — the last two include the GITIN-2074 covering columns, partition-aligned this time).
- Part 3 (dual-write triggers, corrected design): two separate triggers, `AFTER INSERT` (simple passthrough insert, no `Id`) and `AFTER DELETE` (3-branch match on `DELETED`'s own `CustomerId`/`CardNumber`/`UidCode`+`UidSerie`, as derived above). Drafted in conversation, not yet persisted to a script file.

**Open design question raised (2026-09-22): why a trigger at all?** Discussed three options for keeping the shadow table in sync during the backfill window: (1) trigger — transparent, no app change, but adds per-transaction overhead to a hot path (`AddAdditionalInformation` fires once per sale) for the whole migration window; (2) no trigger, brief write-pause + final delta copy right before cutover — avoids ongoing overhead, costs a short real outage on the POS checkout flow; (3) Change Tracking/CDC — lighter-weight built-in alternative, **Standard-edition availability still unverified** (flagged since the original TODO.md design, never checked). Not yet decided — next step is checking CDC availability before committing to the trigger.

**Backfill idempotency, not yet decided:** once dual-write is live, a race between backfill copying a pre-existing row and the trigger mirroring a fresh `DELETE`+`INSERT` for that same customer could leave a stale duplicate in the shadow table (the original table can't have this problem — its own `DELETE`-before-`INSERT` pattern enforces one-row-per-customer, but the shadow table has no uniqueness constraint enforcing that). Two options discussed: (1) idempotent backfill (`INSERT ... WHERE NOT EXISTS`, keyed by the same business-key logic as the delete trigger) — safer, recommended; (2) accept the narrow race and rely on self-healing via the next `DELETE`+`INSERT` for that customer — simpler, but a duplicate could persist indefinitely for a customer who doesn't buy again before cutover. Leaning toward (1), not yet confirmed with the user.

**Explicitly still open:**
- Trigger vs. Change Tracking/CDC for dual-write (CDC availability unverified).
- Backfill idempotency strategy (leaning toward `WHERE NOT EXISTS`, not confirmed).
- Backfill batch size / batching column (not yet discussed at all).
- Cutover script (`sp_rename` sequence, dropping/renaming triggers and indexes appropriately) — not yet drafted.
- Exact timing of the migration — this is a heavier, longer-running migration than anything done under GITIN-2060/2061/2074 so far; needs its own maintenance-window planning.

## Next steps

1. Check Change Tracking/CDC Standard-edition availability — resolves the trigger-vs-CDC decision.
2. Decide backfill idempotency strategy with the user.
3. Draft backfill batching script and cutover script.
4. Decide timing.

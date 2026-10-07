# Investigation: Sargable rewrite for Etl CustomerPointsLog (Etl.EtlOperationConfig Id=6)

**Jira:** [GITIN-2108](https://smartit-ar.atlassian.net/browse/GITIN-2108) — "Improvements in loyalty etl customerpointslog". Ticket filed after this folder was created; folder name kept as-is per the forward-only naming convention (no retroactive rename).

## Status

**In progress — correctness confirmed, index support confirmed, but performance result is now mixed (CPU much lower, wall-clock genuinely higher) and not yet explained. Not recommended for production yet.**

## Context (carried forward from `loyalty/events/20260715_cpu_spikes/`, not re-derived)

Root cause, confirmed 2026-07-15: the ETL's `FromQuery` (`Etl.EtlOperationConfig.Id=6`, `ToTable=dbo.CustomerPointsLog`) joins `Sml.CustomerPointsLog`⋈`Sml.Customer` with a non-sargable `OR` spanning `cpl.LogDate`/`c.CreatedDate` (two different tables' columns), plus the ETL framework's own `COUNT(*) OVER()` pre-probe before paginating. Neither branch can seek as written — chronic ~10-20 rows/sec regardless of window size, confirmed across 23 runs over 30 days at the time, not a one-off degradation.

A sargable rewrite was already drafted (`20260715_cpu_spikes/20260715_cpu_spikes_query002_proposal.sql`): the two `OR` branches are mutually exclusive (new customer vs. existing customer), so they split into a `UNION ALL` — each branch seekable independently. Three items were flagged as needing validation before shipping:
1. ETL framework tolerance of `ORDER BY CustomerPointsLogId` (required by `UNION ALL`) instead of the original `ORDER BY cpl.Id`.
2. Supporting indexes for each branch — not checked at the time.
3. QA result-equivalence validation against the original `OR` query.

**Why revisited now (2026-09-25)**: GITIN-2060 (`events/20260922_gitin2060-mantenimientoindices-reschedule/`) moved this operation to 05:00 UTC to dodge Monday's old double-contention with `Backup_FULL`, but only worked around scheduling, not the operation's own duration. `Backup_FULL` now runs 09:00 UTC on Sun/Wed/Fri (GITIN-2060 third iteration). A live check today (`events/20260925_daily-maintenance-check/`) showed the operation finishing at 08:43 UTC on a Friday — only 17 minutes before `Backup_FULL`'s 09:00 start. The known chronic worst case (Monday ~5.4h, or the historical 25.9h outlier) would blow straight through it on Sun/Wed/Fri. The sargable rewrite removes the risk at the source instead of narrowing the schedule gap further.

## Findings (2026-09-25)

**Item 2 (supporting indexes) — resolved, better than expected.** `sys.indexes`/`sys.index_columns` on `Sml.CustomerPointsLog` (`data/customerpointslog_indexes_20260925.txt`): the table's **clustered index key is `LogDate` itself** (`ClusteredIndex_sch_LogDate_Anual`, `key_ordinal=1`) — the PK is a *separate* nonclustered unique index on `Id` (`PK_dbo.CustomerPointsLog`), not the clustered index. Every nonclustered index (`IX_CustomerId`, `IX_CustomerPointsLog_SaleId`, `IX_CustomerPointsLog_Points`) also carries `LogDate` at `key_ordinal=0` — the automatic row-locator SQL Server appends for lookups, not a user-defined key column.

This means Rama B (`cpl.LogDate >= @LowerBoundary AND cpl.LogDate < @UpperBoundary`) resolves as a direct **clustered index seek** — partition elimination *and* an in-partition seek, the best possible access path, no new index needed. Combined with `Sml.Customer.__IX_Customer_CreatedDate` (confirmed to exist via `loyalty/repo/dev-src-sol-smartloyalty/Core/Data/Migrations/202012091517169_CreateIndex_IX_Customer_CreatedDate.cs`, created 2020, no later `Down`/drop applied in production found — supports Rama A), **both branches of the proposed `UNION ALL` now have confirmed seek support. No new DDL required.**

**`__IX_Customer_CreatedDate` confirmed live** (`data/customer_indexes_20260925.txt`, `sys.indexes`/`sys.index_columns` on `Sml.Customer`): `NONCLUSTERED`, `key_ordinal=1` on `CreatedDate` (DESC) — a real leading key, not just included or source-only. Range predicates seek fine against a DESC index in either direction, so Rama A (`c.CreatedDate >= @LowerBoundary AND c.CreatedDate < @UpperBoundary`) resolves as a clean index seek. **Both branches of the proposed `UNION ALL` now have confirmed, live-verified seek support — no new DDL needed for either.**

## Correctness bug found and fixed in the original draft (2026-09-25)

Re-checking the `UNION ALL` proposal's boolean logic (not data-dependent, provable by direct inspection): when `@LowerBoundary IS NULL` (first-ever run / full backlog recovery), both `(@LowerBoundary IS NULL OR ...)` guards short-circuit to `TRUE`, collapsing Rama B's condition (`cpl.LogDate < @UpperBoundary` alone) into a strict superset of Rama A's (`c.CreatedDate < @UpperBoundary AND cpl.LogDate < @UpperBoundary`) — every row satisfying Rama A also satisfies Rama B, duplicating nearly every row in that scenario. Not present in the current production `OR` query (a plain `OR` can't duplicate a row) — this was a regression the `UNION ALL` restructuring itself introduced, missed in the original 2026-07-15 draft.

**Fixed**: Rama A now requires `@LowerBoundary IS NOT NULL` unconditionally (returns zero rows on a null-watermark run), since Rama B alone already correctly covers the full historical range in that case — splitting "new vs. existing customer" is meaningless without a watermark to be new relative to. Incremental runs (`@LowerBoundary` set) are unaffected. Updated in `propuesta.md`.

**QA validation item 3 (below) now explicitly must cover the `@LowerBoundary IS NULL` case**, not just steady-state incremental runs — that's exactly where this would have silently duplicated data.

## QA equivalence + performance comparison (2026-09-25) — mixed result, one test-methodology fix in progress

**Correctness: fully confirmed.** `query_current_last24h.sql` and `query_fixed_last24h.sql`, same real window (2026-09-23 05:00:44 → 2026-09-24 05:02:31 UTC), all six aggregate columns matched exactly: `RowCount_Total=153082`, `RowCount_DistinctId=153082`, `MinLogDate`/`MaxLogDate`/`SumPoints` identical, **`RowsetChecksum=-1476308966` on both**. Strong row-for-row equivalence proof over the real 153,082-row set, not a coincidence. (`data/qa_current_query_result_20260925.txt`, `data/qa_current_query_statistics_20260925.txt`, `data/qa_fixed_query_statistics_20260925.txt`)

**Performance, first pass — CPU dramatically lower, wall-clock worse, but the comparison wasn't fair yet:**

| | Current (`OR`) | Fixed (`UNION ALL`) |
|---|---|---|
| CPU time | 1,007,206 ms (~16m47s) | 285,875 ms (~4m46s) |
| Elapsed time | 146,178 ms (~2m26s) | 299,754 ms (~5m0s) |
| `CustomerPointsLog` logical reads | 2,136,826 (scan count 16) | 4,273,569 (scan count 22) |
| `Customer` logical reads | 39,934 (scan count 17) | 39,949 (scan count 2) |
| `Worktable` logical reads | 0 | 441,139 (scan count 2) |

CPU dropped ~3.5x (the metric most relevant to the original "CPU spikes" complaint this all traces back to). But elapsed time roughly doubled, and `CustomerPointsLog` reads roughly doubled too, plus a new `Worktable` cost appeared. CPU≈elapsed for the fixed query (ratio ~0.95, essentially serial) vs. CPU≈7x elapsed for the current query (heavily parallel, ~7 workers) — the old non-sargable scan got parallelized; the new seeks apparently didn't trigger a parallel plan, so less total work landed on fewer workers.

**Test asymmetry found, fixed, and re-tested — the asymmetry was NOT the explanation.** `query_fixed_last24h.sql` included `ORDER BY CustomerPointsLogId`; `query_current_last24h.sql` didn't. Added `ORDER BY CustomerPointsLogId OFFSET 0 ROWS` to the current-query test (a bare `ORDER BY` in a single-`SELECT` derived table isn't valid syntax without `TOP`/`OFFSET`/`FOR XML` — `UNION ALL`'s trailing `ORDER BY` is, which is why only one file needed the extra `OFFSET 0 ROWS`). **Re-run confirmed the `Worktable` cost is real, not a test artifact**: with matching `ORDER BY` on both sides, the current query still shows **zero** `Worktable` reads while the fixed query still shows 441,139. `data/qa_current_query_statistics_rerun_20260925.txt`.

**Confirmed final comparison** (both queries now symmetric):

| | Current (`OR`) | Fixed (`UNION ALL`) | Delta |
|---|---|---|---|
| CPU time | 950,042 ms | 285,875 ms | **~3.3x less** |
| Elapsed time | 144,753 ms | 299,754 ms | ~2.07x more |
| `CustomerPointsLog` reads | 2,136,843 | 4,273,569 | ~2x more |
| `Worktable` reads | 0 | 441,139 | new, real |

The CPU reduction and correctness results stand. The wall-clock/read increase is real and needs an actual execution plan (not just `STATISTICS IO/TIME`) to explain *why* — not a methodology artifact anymore.

**Open, not yet explained**: why `CustomerPointsLog` logical reads roughly doubled despite both branches having confirmed seek support (clustered index on `LogDate`, `IX_CustomerId` keyed on `CustomerId` for Rama A's join back from `Customer`). Possible explanation not yet confirmed: Rama A's path (`Customer` seek on `CreatedDate` → join to `CustomerPointsLog` via `IX_CustomerId(CustomerId)`) may require a key lookup per matched row into the clustered index (since `IX_CustomerId` doesn't include `EventTypeCode`/`Points`), adding up across however many rows Rama A actually returns. No actual execution plan (`SET STATISTICS XML ON` or a real showplan) has been pulled yet — `STATISTICS IO`/`TIME` alone can't show *why*, only *how much*.

## Open question (2026-09-25): source-query cost vs. destination-write cost — not yet split

Raised by the user: is the 3-6h duration actually dominated by the source query, or by the time it takes to land data at the destination? Checked directly, not assumed:

- **`Etl.EtlOperationConfig.Id=6`**: `InputConnStr='SmlConnString'`, `OutputConnStr='DwConnString'` — **confirmed different connections** (`data/etl_config_connstrings_20260925.txt`). Source and destination are not two tables in the same database — this is OLTP → a separate Data Warehouse, over the network. Also cross-confirmed by the trigger job's own name, `Sch.Job.Id=755` = `EtlDwGridoCustomerPointsLogProcessor` ("Dw" = Data Warehouse).
- **The July evidence for the source query's cost is real but partial.** `20260715_cpu_spikes_query001.sql` captured SPID 110's actual query text mid-run with logical reads climbing 10,442→278,573 within that single SELECT execution, dominant wait type `PAGEIOLATCH_SH` (read-side, consistent with a non-sargable scan) — solid evidence the source query is genuinely expensive at some point during a run.
- **But that capture was only a ~3-minute slice** (`PNSSRL_TempdbProc`, 20:53-20:56 GMT) of a run that took 3h34m total that day. It proves the source query is expensive when it runs — it does **not** establish what fraction of the total 3-6h it accounts for, versus batched writes to the DW (`BatchSize=1000000`/`SetSize=100000` implies repeated fetch-then-write cycles) taking their own separate share of that time. This split has never been measured.

**Consequence for this proposal**: the sargable rewrite fixes a real, confirmed cost on the source side. It is not yet established that this is the *dominant* cost of the full 3-6h duration. The "Beneficio esperado" claim in `propuesta.md` needs hedging until this is resolved — see next steps.

**Next step to resolve this**: a live capture across a *full* run (not a 3-minute slice) — periodic sampling of `sys.dm_exec_requests`/`sys.dm_exec_sql_text` for the `sfsqlusr`/`SFCG-TO-01` session throughout the next ~05:00-09:00 UTC run, tallying how much wall-clock time is spent executing the source SELECT vs. whatever write/insert statement lands rows in the DW.

**Query validated (2026-09-25, off-hours), ready for the actual run window:**
```sql
SELECT
  r.session_id, r.status, r.wait_type, r.last_wait_type,
  r.total_elapsed_time, r.cpu_time, r.reads, r.writes,
  t.text AS running_statement
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.session_id IN (
  SELECT session_id FROM sys.dm_exec_sessions
  WHERE login_name = 'sfsqlusr' AND host_name = 'SFCG-TO-01'
)
AND r.session_id <> @@SPID;
```
Two off-hours test runs (`data/live_capture_offhours_20260925_1447utc.txt`, `_1448utc.txt`) confirmed: (1) the querying session itself is authenticated as `sfsqlusr`/`SFCG-TO-01`, so an earlier version without `<> @@SPID` self-matched and returned noise; (2) with that exclusion, zero rows outside the run window, as expected — the query is validated and ready, just needs to be run repeatedly during the actual ~05:00-09:00 UTC window, which hasn't happened yet.

## Open items

1. ~~Confirm `__IX_Customer_CreatedDate` live~~ — done, confirmed above.
2. ETL framework tolerance of the `ORDER BY` alias change — not yet checked, framework package (`SmartFran.Business.Etl.*`) isn't in this repo.
3. ~~QA result-equivalence validation~~ — done, exact checksum match confirmed. Performance validation done too, but result is mixed (see Status/comparison above) — not yet a clean pass.
4. **New**: explain why `CustomerPointsLog` logical reads roughly doubled and a `Worktable` sort cost appeared — needs an actual execution plan (`SET STATISTICS XML ON` or graphical showplan), not just `STATISTICS IO/TIME`.
5. **New**: resolve the source-vs-destination time-split question (see dedicated section below) before claiming this fixes the ETL's overall duration — CPU win is real, but duration/wall-clock impact on the actual production run is still unproven.
6. ~~No Jira ticket filed yet~~ — done, [GITIN-2108](https://smartit-ar.atlassian.net/browse/GITIN-2108). Still not recommending this as a change proposal handed to Dev until items 4/5 above are resolved — CPU win is real but wall-clock/read increase isn't explained yet.

## Related

- `loyalty/events/20260715_cpu_spikes/` — original root-cause investigation and rewrite proposal.
- `loyalty/events/20260922_gitin2060-mantenimientoindices-reschedule/` — moved this operation to 05:00 UTC, percentile duration data by weekday.
- `loyalty/events/20260925_daily-maintenance-check/` — today's live run (3h40m32s, 05:02-08:43 UTC) that prompted revisiting this.

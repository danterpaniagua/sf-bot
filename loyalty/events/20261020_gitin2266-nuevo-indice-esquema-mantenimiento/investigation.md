# Investigation: GITIN-2266 — new index + maintenance scheme

**Status (2026-10-20):** opened, nothing run. Jira: https://smartit-ar.atlassian.net/browse/GITIN-2266, ticket title as given by the user: "[SML] Nuevo indice + esquema de mantenimiento", child of GITIN-2250. Scope as given by the user: create the index and add it to the maintenance schedule. The ticket body and the index definition were not seen.

## Open questions (the index is not defined yet)
- Which table and which key/included columns? Not stated. Only a lead from GITIN-2251 (see below), not a decision.
- Which database (`SmartFran.Solution.SmartLoyalty` is the production one) and which window for the creation (production, online or offline, partition-aligned or not)?
- Who approves the change and the rollback plan (drop of the index)?

## Lead from GITIN-2251 (not a decision)
- `Sml.CustomerPointsLog` (about 404 million rows, 16 yearly partitions, `sch_LogDate_Anual`) has no index that holds `CustomerId` together with `Points`: `IX_CustomerId` (7.4 GB) is keyed on `CustomerId` with no included columns, and the only index with both columns is `IX_CustomerPointsLog_SaleId` (17 GB, keyed on `SaleId`, with `CustomerId` and `Points` included). The trigger `[Sml].[CustomerPointsLogAfterInsert]` sums `Points` by `CustomerId`, so it does key lookups into the clustered index (GITIN-2251, Q8/Q9). Whether that cost matters was not shown: in GITIN-2251 the customers inserted in the 5 minutes of interest had histories of at most 1,171 rows and counting all of them took 296 ms of CPU. Also open there: a suspected multiplication in the trigger's join (Q19 not run).
- `IX_CustomerPointsLog_Points` on the same table had 338 seeks and 0 scans against 1,214,569 updates since 2026-10-14 (write cost, almost no reads). A new index adds write cost to a table that takes about 500-700 inserts per minute at peak.

## What exists for maintenance (from the repo's docs and earlier events; not re-read on the server today)
- Daily job `PNSSRL_MantenimientoIndices` (encrypted procedure `PNSSRL_MantenimientoModulos`, control table `PNSSRL_TablasModulos`, one row per table, columns `indexado`, `defragmentacion`, `habilitado`): it enumerates the indexes of a registered table dynamically (GITIN-2078: two new indexes on `SmlSt.CustomerAdditionalInformation` were picked up automatically, 4 rows in the log instead of 2). For `Sml.CustomerPointsLog` (`id_tablas_modulos=292`) the row is `habilitado=0`, so the daily sweep skips it (GITIN-2061).
- `Sml.CustomerPointsLog` has its own job, `PNSSRL_MantenimientoIndices_CustomerPointsLog` (created in GITIN-2061, daily 08:15 UTC, two steps: rebuild of the active partition of `IX_CustomerId` via `$PARTITION.fn_partition_LogDate_Anual`, then `UPDATE STATISTICS`). A new index on this table would therefore not be covered by the daily sweep; it needs a step (or a change) in that job. The job's current definition on the server was not read today.
- If the new index is on another table: check whether the table is registered in `PNSSRL_TablasModulos` (GITIN-2078 method) before adding anything.

## Next steps
1. User: give the index definition (table, key, included columns, partitioning) and the target window.
2. Read-only prechecks (queries to be written to `scripts/scripts.sql`): current indexes and sizes of the table, free space for the build, current definition of `PNSSRL_MantenimientoIndices_CustomerPointsLog`, and the job schedules that overlap the creation window.
3. Draft the `CREATE INDEX` (with the state-changing banner), the rollback (`DROP INDEX`) and the change to the maintenance job; nothing is run by Claude.

# Investigation: GITIN-2267 — index analysis: IX_CustomerPointsLog_Points

**Status (2026-10-20):** opened, nothing run for this ticket. Jira: https://smartit-ar.atlassian.net/browse/GITIN-2267, ticket title as given by the user: "[SML] Analisis de indices: IX_CustomerPointsLog_Points" (priority Medium, status Backlog; the pasted card says it is a subtask, the parent was not shown). Scope as given: analysis of this index; the ticket body was not seen. The user mentioned it as "S3"; the nearest item in the GITIN-2251 `ops.md` is S2 (this same index), taken to be the origin.

## Starting data (GITIN-2251, Q8, read 2026-10-19 12:30-12:40 GMT; usage counters since the service start 2026-10-14 07:28 GMT, about 5 days; raw file in `loyalty/events/20261018_gitin2251-webs-db-misma-ventana/data/q8-indices-customerpointslog.txt`)
| Object | Index | Size | User seeks | User scans | User lookups | User updates |
|---|---|---|---|---|---|---|
| `Sml.CustomerPointsLog` (404,460,588 rows, 16 yearly partitions) | `IX_CustomerPointsLog_Points` (index id 14) | 10,090 MB | 338 | 0 | 0 | 1,214,569 |
| `SmlSt.CustomerPointsLog` (5,571,426 rows, heap) | `IX_CustomerPointsLog_Points` (index id 4) | 97 MB | 9,018 | 6 | 0 | 1,214,569 |

- **The same index name exists on two tables.** The ticket name does not say which; the large one (`Sml`) is the one that matches the GITIN-2251 observation (many updates, almost no reads), and is assumed here. To confirm with the user.
- **Key columns of the `Sml` index are not confirmed.** Q8 printed "LogDate, Points" but that column list was sorted by `key_ordinal` and puts the implicit partitioning column `LogDate` first (the artifact documented for `IX_CustomerId` in GITIN-2251); the real key is probably `Points` alone, to be read from raw `sys.index_columns` rows (as Q9 did for the other indexes, which did not include this one).
- Updates: 1,214,569 on every index of both tables, i.e. every insert into the log updates this index (and the trigger updates the `SmlSt` one). 338 seeks in about 5 days is the only read use seen.
- The counters reset at each service restart, so five days is a short sample: monthly or quarterly reports could use the index and not show up (not checked). The statements that seek on `Points` are not identified (plan cache / source code not searched).

## Open questions
- Which statements use it (plan cache search for `Points` predicates, source and reports)? Does any use require it, or is it removable?
- Write cost: how much it adds to the inserts of a table taking about 500-700 inserts per minute at peak (not measured).
- Same question for the `SmlSt` index (it has real reads).
- Decision options (not decided): keep, disable, or drop; any drop needs a window, a rollback script (`CREATE INDEX` definition scripted first) and a longer usage sample.

## Next steps
1. User: confirm which table's index the ticket means and the expected output (recommendation only, or also the change).
2. Read-only queries into `scripts/scripts.sql` (to be written): raw key/included columns and partitioning of both indexes, usage counters again (and the service start time), plan-cache statements that mention `Points` in a predicate, size and fragmentation, and what the maintenance job does with it.
3. Cross-check the source code of SmartLoyalty for queries filtering by `Points` (branch and HEAD stated when read).

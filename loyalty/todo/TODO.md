# TODO — loyalty

Pending action items, tracked outside the `events/` investigation archive. One entry per item; check off and date when done, don't delete — move to a "Done" section instead so history isn't lost.

## Pending

- [ ] **Check for a real lock conflict between the new `PNSSRL_MantenimientoIndices_CustomerPointsLog` job and the `Etl` `CustomerPointsLog` sync.** Not yet checked. `PNSSRL_MantenimientoIndices_CustomerPointsLog` (GITIN-2061, daily Sun/Tue/Thu/Sat 08:15 UTC) does an offline `ALTER INDEX IX_CustomerId ... REBUILD PARTITION` on `Sml.CustomerPointsLog`, holding `Sch-M` for its duration. `Etl.EtlOperationConfig.Id=6` (`ToTable=dbo.CustomerPointsLog`) starts daily ~07:25 UTC and typically runs 3-6h (worst case 25.9h observed) — very likely still active at 08:15 and reading from `Sml.CustomerPointsLog` (its actual source table not yet confirmed via `FromQuery`, but strongly implied by naming/precedent). If so, the new partition-scoped job may recreate the exact blocking pattern GITIN-2060/2061 were built to eliminate (offline rebuild blocking a real consumer), just against the `Etl` sync instead of MobileAppService. Action: confirm `Etl.EtlOperationConfig.Id=6`'s actual `FromQuery` source table, then check `PNSSRL_AuditSysprocesses`/live blocking data after the new job's first real runs (starting 2026-09-23) for a genuine conflict. Related: `loyalty/events/20260922_gitin2060-mantenimientoindices-reschedule/`, `loyalty/events/20260922_gitin2061-ix_customerid-partition-rebuild/`, `loyalty/docs/task_operator_tasks.md` §2. (2026-09-22)

## Done

(none currently — see `loyalty/docs/task_operator_tasks.md` and individual `events/` folders for completed work; the 2026-09-22 batch (GITIN-2060/2061/2078/2077/1771) is tracked under the aggregator ticket [GITIN-2088](https://smartit-ar.atlassian.net/browse/GITIN-2088), `operations/events/20260922_gitin2088-tareas-mantenimiento/`.)

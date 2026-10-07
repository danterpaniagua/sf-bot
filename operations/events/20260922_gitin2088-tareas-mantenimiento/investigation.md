# Investigation: GITIN-2088 — [OPE] Tareas de Mantenimiento

**Jira:** https://smartit-ar.atlassian.net/browse/GITIN-2088

## Status

**Aggregator/summary ticket, cross-project.** This ticket collects several maintenance items completed in one working session (2026-09-22), each of which already has its own complete, closed event folder with full investigation/ops detail. This event does **not** duplicate that content — it summarizes and cross-references it. Read the linked local folders for full technical detail; this file is the index.

## Items aggregated

All completed 2026-09-22, originally tracked ad hoc in `loyalty/todo/TODO.md` before this ticket existed.

1. **GITIN-2060** — Reschedule `PNSSRL_MantenimientoIndices` (`SmartLoyalty`/`SFCG-DB01`). Moved from 06:15 UTC to 08:00 UTC, then further refined same-day to a full weekday-exclusion design: index maintenance now runs Sun/Tue/Thu/Sat 08:00 UTC, `Backup_FULL` moved to Mon/Wed/Fri 06:00 UTC (evenly spaced, no back-to-back days) — eliminates the backup-overlap risk entirely rather than just narrowing it. Local: `loyalty/events/20260922_gitin2060-mantenimientoindices-reschedule/`.
2. **GITIN-2061** — Partition-scope `IX_CustomerId` rebuild on `Sml.CustomerPointsLog`. New dedicated SQL Agent job (`PNSSRL_MantenimientoIndices_CustomerPointsLog`) built and scheduled; the original exclusion mechanism (`indexado=0, defragmentacion=0` on the old job's control table) didn't work as designed — fixed by also setting `habilitado=0`, confirmed via a live re-trigger test. Local: `loyalty/events/20260922_gitin2061-ix_customerid-partition-rebuild/`.
3. **GITIN-2078** — Confirmed `SmlSt.CustomerAdditionalInformation`'s two new indexes (from GITIN-2074) get picked up automatically by the existing maintenance job — non-issue, no config change needed, confirmed via a real run. Local: `loyalty/events/20260922_gitin2078-customeradditionalinformation-index-rotation/`.
4. **GITIN-2077** — Partitioning `SmlSt.CustomerAdditionalInformation` by hash(`CustomerId`). Design fully completed (bucket count, DDL, corrected dual-write trigger, cutover sequence) but **discarded** after a risk/benefit reassessment — high execution risk (live shadow-table cutover on a POS hot-path table) against a speculative, undated benefit; real measured maintenance cost today is small (~3.5 min/day) and the table's write pattern is structurally different from `CustomerPointsLog`. Design preserved for reuse if the signal changes. Local: `loyalty/events/20260922_gitin2077-customeradditionalinformation-partitioning/`.
5. **GITIN-1771** — SSL automation for `gestion.clubgrido.com.ar` (WebSite, `SFCG-WSIT-01`), subtask of epic GITIN-1768. Both certificate legs automated end-to-end: public cert → Azure Key Vault (gateway listener repointed), backend-leg cert → Windows Certificate Store + IIS binding. Caught and fixed two real execution risks along the way (a win-acme renewal-overwrite prompt that would have silently merged both certs' tracking, and an IIS binding the install plugin didn't update automatically despite the runbook's claim). Live TLS verification confirmed correct. Local: `operations/events/20260913_automatizar_website/` (predates this aggregator — GITIN-1771 work spanned two sessions, 2026-09-13 and 2026-09-22).

**Explicitly not included**: the Sales-PRO OOM crash-loop investigation (GITIN-2075, `cloud/events/20260920_sales-oom-48h/`) is still unresolved (root revert cause unconfirmed, stopgap not yet applied — user is reporting it to a colleague before further action) — tracked separately in `cloud/todo/TODO.md`, not aggregated here since it isn't done.

## Next steps

None — this is a closing/summary ticket for already-completed work. `loyalty/todo/TODO.md` cleared of these entries now that they're tracked here instead.

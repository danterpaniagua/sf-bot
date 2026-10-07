# Investigation — 20260902_gitin1872-parent-challenges

**Jira:** [GITIN-1872](https://smartit-ar.atlassian.net/browse/GITIN-1872) (parent, "[SP] Envío de datos de SP a Grido").

**Status: data collection only.** This folder consolidates challenges/findings across GITIN-1872's subtasks for a future PM email — the user has explicitly deferred drafting that email until all subtasks are done. Nothing here is ready to send; treat as working notes.

**All 8 subtasks now complete (2026-09-16).** `GITIN-1880`'s Phase 2 access-security bucket policy applied and functionally verified (`403` on unauthorized anonymous request) — see `20260831_s3-bucket-securization/investigation.md`. **PM email is no longer blocked** — ready to draft `email_pm.md` whenever the user asks for it (still not drafted automatically per the original deferral instruction; wait for an explicit request).

## Subtasks (8 total, per Jira as of 2026-09-02)

| Ticket | Title | Local folder | Status |
|---|---|---|---|
| [GITIN-1873](https://smartit-ar.atlassian.net/browse/GITIN-1873) | Análisis de colecciones de News | `20260818_grido-news-etl-s3/` | PII/field classification done |
| [GITIN-1973](https://smartit-ar.atlassian.net/browse/GITIN-1973) | Fix: credenciales en código | `20260902_lambda-mongodb-credentials-envvars/` | Record-keeping only, remediation reported already complete |
| [GITIN-1970](https://smartit-ar.atlassian.net/browse/GITIN-1970) | Corregir el export de Lambda -> S3 para que traiga UTC-3 | `20260831_lambda-s3-export-utc3/` | Deployed and validated in production |
| [GITIN-1980](https://smartit-ar.atlassian.net/browse/GITIN-1980) | Normalizar historial S3 a UTC-3 | `20260901_s3-history-utc3-normalization/` | Confirmed done by the user (2026-09-03) — the local docs were never updated with a completion entry (last recorded state: "batch started, not confirmed"), but `progress.txt` (385 entries through 2026-08-23) plus the separately-confirmed 2026-08-24–08-30 validation week is consistent with the full 2025-08-17–2026-08-30 range having completed. Not independently re-verified against a fresh S3 listing. |
| [GITIN-1983](https://smartit-ar.atlassian.net/browse/GITIN-1983) | Actualización de Export -> S3 | `20260902_export-s3-update/` | Done — record-keeping ticket for GITIN-1970's confirmed field fix |
| [GITIN-1874](https://smartit-ar.atlassian.net/browse/GITIN-1874) | Creación de ETL -> S3 | `20260901_grido-redacted-etl-lambda/` | Done (2026-09-03) — deployed, dual-file-shape bug fixed, historical backfill complete (2026-05-01 to 2026-09-01) and validated as genuinely Grido-only, normal rolling-window operation confirmed, daily EventBridge schedule live |
| [GITIN-1880](https://smartit-ar.atlassian.net/browse/GITIN-1880) | Securización de S3 | `20260831_s3-bucket-securization/` | **In progress (revised 2026-09-16)** — bucket created and actively receiving data (via GITIN-1874's Lambda, confirmed live). The Python-Lambda item previously listed here as pending is done, but under GITIN-1874's tracking, not this ticket. GITIN-1880's actual remaining scope: Phase 2 access-security bucket policy — Grido's source IP now confirmed (`40.121.111.127`), policy drafted, not yet applied |
| [GITIN-1979](https://smartit-ar.atlassian.net/browse/GITIN-1979) | Envío de mensaje de error | `20260902_error-message-alerting/` | Done, `ops.md`/`ops-events.md` formalized. CloudWatch Alarms on `grido-redacted-etl`/`mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO` → `SNS-SmartPedidosTeam-PROD`. Google Chat bridge built and end-to-end validated, then deactivated same day (too verbose) — current live state is email-only, Chat re-enable is a one-command reversal if wanted later. |

## Challenges, as originally reported by the user (2026-09-02), cross-checked against local findings

1. **Filter based on what Grido requested; fields that did not exist in the backup.** Confirmed — GITIN-1874 H1/H2: the filter criterion and field-list both had to be corrected against real exported data (an early candidate filter would have silently dropped ~80% of Grido's real volume; three fields were completely absent from the export despite existing in raw MongoDB).
2. **Creation of a separate file with the UTC-3 data, requiring analysis of more than one source file.** Confirmed — GITIN-1970's day-boundary fix / GITIN-1980's `scripts.py` both read day D and D+1 to correctly bucket records into Argentina-timezone daily files.
3. **The "tenant" key does not exist in News.** ⚠️ **Needs correction.** Confirmed directly this session (GITIN-1874): `tenant` exists on 100% of raw records checked (2025-10-04, 2026-05-01, 2026-08-01), including live MongoDB. It is only absent from `orderMapper()`'s *transformed* export output — the mapper never copies it over. "Missing from the export" and "missing from the underlying data" are different facts and were conflated here — worth correcting wherever this challenge is recorded externally.
4. **Creation of a local script to generate the UTC-3 files.** Confirmed — GITIN-1980's `scripts.py` runs locally (Python/boto3), not as a Lambda, because the volume (~379 days × 2 file reads, some files >100MB) exceeds Lambda's 900s timeout and memory ceiling for a single run.
5. **Credential mitigation in the export script.** Confirmed — GITIN-1973: MongoDB connection string migrated from a hardcoded plaintext value to environment variables (reported as already complete; not independently verified against an old source snapshot in this repo).
6. **The documentation sent to Grido did not match the actual export; outdated export.** Confirmed — GITIN-1874 H2: `field-classification.md`'s v1 field list was written against the raw Mongoose schema, not `orderMapper()`'s actual output.
7. **Problems analyzing data by day; memory risk in the original export when running it in large batches.** Confirmed, with a figure correction: GITIN-1970 H3 (`Runtime.OutOfMemory`, fixed by processing/writing one day at a time) and GITIN-1874's own flagged risk (source files observed up to ~180**MB** each, not "180-day batches" — worth checking whether that phrasing conflates file size with a day count elsewhere).
8. **Time required to create the UTC-3 files; logged in Investigations/Events.** Confirmed — matches this repo's convention (every ticket gets an `investigation.md` first) and GITIN-1980's long-running historical backfill.

## Additional findings surfaced this session, not in the original challenges list

Pulled from each subtask's `ops.md` → Hallazgos table while cross-checking the list above — these are real findings with direct business relevance that weren't mentioned:

- **Real PII exposure identified in the source data (GITIN-1873):** customer name (~100% of orders), phone (~93.6%), address (~91.9%), email (~24.2%), national ID/DNI (~23.7%); loyalty-program data when applicable; free-text fields (`observations`) leaking billing names, ID numbers, and phone numbers incidentally; exact GPS delivery coordinates.
- **A permanent, unrecoverable ~3-hour data gap** (GITIN-1970 H6): a historical backfill overwrote an already-exported file without preserving the prior version. The missing window (2026-08-17, 00:00–03:00 UTC) no longer exists in MongoDB (past its 15-day retention) or in S3 (overwritten, bucket versioning was suspended, no prior version retained). No mitigation is possible — the data is gone.
- **Root explanation for a major investigation dead-end this session** (GITIN-1970 H4): the production export function (`orderMapper()`) had a dead-code bug — it built a properly-shaped output object but then returned the original, unmapped one instead, in every historical version reviewed. This is *why* two different file shapes ended up coexisting in the export archive, which in turn caused GITIN-1874's ETL to silently miss ~99% of a large date range until found and fixed this session (see GITIN-1874 H8).
- **An unresolved data-privacy compliance question** (GITIN-1874 H3): national ID (DNI) is being included in the export to Grido based on stated operational need only — a formal Legal/PM sign-off for including this specific field has never been confirmed one way or the other, despite it being the single most sensitive field in the source classification.
- **Storage lifecycle limits how far back any of this can ever be recovered** (GITIN-1980 H4): source data older than 2025-08-17 has already moved to S3 Glacier Deep Archive under a 365-day lifecycle rule — recovering anything from before that date requires an explicit restore request and a 12+ hour wait before it's even readable.

## Open questions / next steps

1. Confirm with the user whether the challenges list (as originally given) is sourced from Jira (parent ticket description/comments) or elsewhere — determines whether the `tenant` wording correction needs to happen in Jira directly or is just noted here for the eventual PM email.
2. ~~GITIN-1979 has no local investigation~~ — **resolved 2026-09-02**: now `20260902_error-message-alerting/`, in progress.
3. GITIN-1874's own work (EventBridge schedule, output-only-Grido validation) is still in progress in parallel — this parent folder doesn't duplicate that detail, see `20260901_grido-redacted-etl-lambda/investigation.md`.
4. PM email drafting explicitly deferred by the user until all subtasks are done — do not draft `email_pm.md` yet.

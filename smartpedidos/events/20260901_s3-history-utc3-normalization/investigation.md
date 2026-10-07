# Investigation — 20260901_s3-history-utc3-normalization

**Jira:** [GITIN-1980](https://smartit-ar.atlassian.net/browse/GITIN-1980) ("[SP] Normalizar historial S3 a utc-3"). New task, split out from `smartpedidos/events/20260831_lambda-s3-export-utc3/` (GITIN-1970) on 2026-09-01 — GITIN-1970 fixed the *live export* (day-boundary bucketing + going-forward writes); this ticket covers reformatting the *existing historical* S3 files, which GITIN-1970 explicitly left out of scope ("field values inside each record stay as raw UTC ISO strings ... out of scope for this ticket, not to be reformatted").

**Status: in progress (2026-09-01).** All design questions resolved (day-pairing, storage-class range, no field conversion, `updatedAt`/`updatedat` field handling). `scripts.py` drafted, validated in both directions (no-op on already-fixed range, genuine rescue on pre-fix range). First 7 days (`2026-08-24`–`2026-08-30`) written and confirmed correct. First production batch (`2025-08-17`–`2025-10-17`, ~62 days) running as of 11:51:19 local — not yet confirmed complete.

## Scope (as given by user, 2026-09-01)

Each existing `news/YYYY/MM/newsYYYYMMDD.json` file stores record timestamp fields (`order.orderTime`, `createdAt`, `traces[].createdAt`, etc.) in raw UTC (`Z` suffix). Requirement: alongside each existing file, generate a new file `newsYYYYMMDD-3.json` in the same `news/` folder, containing the same day's records with those timestamp values expressed in UTC-3 instead of UTC.

User's stated process: assemble each `-3` file by reading **two consecutive existing UTC-dated files: Day-1 and Day** (their example: to build `news20260817-3.json`, read `news20260816.json` and `news20260817.json`).

First open item per the user: determine the practical processing limit based on S3 storage class (hot/cold) of the historical files.

## Confirmed facts (carried over from GITIN-1970's investigation, still applicable here)

- `news/` layout: `news/YYYY/MM/newsYYYYMMDD.json`, one file per day, full daily coverage confirmed from 2026-01-01 through 2026-08-31 with zero gaps (`smartpedidos/events/20260831_lambda-s3-export-utc3/data/s3_ls_news.txt`, `data/present_days` computation).
- The `news` MongoDB collection (source of these files) has a 15-day TTL (GITIN-1965) — irrelevant to this ticket's own mechanics since this task operates purely on already-written S3 files, not on Mongo, but relevant context for why GITIN-1970 could only backfill a limited window.
- Only `news20260817.json` through `news20260831.json` were regenerated under GITIN-1970's fixed day-boundary code (Argentina-day bucketing at write time). Everything else in the full Jan-Aug history was written under the old UTC-midnight-boundary code. Not yet established whether that distinction (fixed-boundary vs. old-boundary files) matters for this ticket's own per-record UTC-3 field conversion — plausibly not, since this ticket only reformats field *values*, not which file a record belongs to, but flagged as worth confirming once the day-pairing question (below) is resolved, since that question is really about the same underlying boundary math.

## Confirmed: day-pairing (2026-09-01)

**Correct pairing is Day + Day+1** — corrected from the user's original statement (Day-1 + Day), confirmed by the user after walking through a concrete example.

Derivation (confirmed against a real record from this same investigation: `2026-09-01T02:59:51Z` = `2026-08-31 23:59:51` Argentina local, plus a worked example — an order at `2026-01-01 23:30:00` Argentina local = `2026-01-02 02:30:00 UTC`, which under the old UTC-calendar-day bucketing lands in `news20260102.json`, not `news20260101.json`):

- Argentina day D spans UTC `[D 03:00, D+1 03:00)`.
- A UTC-dated file for day D (`newsYYYYMMDD.json`, covering UTC `[D 00:00, D+1 00:00)`) contains: Argentina day D's first 21 hours (`00:00–21:00` local) **plus** the tail end of Argentina day **D-1** (`21:00–24:00` local on D-1 — the exact 3-hour window GITIN-1970's original bug was about).
- The missing 3 hours of Argentina day D (`21:00–24:00` local, on day D itself) lands in UTC-file **D+1**.

**To build `newsYYYYMMDD-3.json` for Argentina day D: read UTC-files D and D+1** (e.g., for `news20260817-3.json`, read `news20260817.json` and `news20260818.json`) — not D-1 and D as originally stated.

## Ruled out

(none yet)

## Confirmed: S3 storage class limit (2026-09-01)

Bucket lifecycle rule on `news/` (`data/s3_lifecycle_config.json`): `Days: 365 → DEEP_ARCHIVE`, applied by `LastModified`, not by the date encoded in the filename. Full object listing with storage class (`data/s3_news_storage_classes.json`, 2449 objects) confirms a hard boundary:

- **`news20250817.json` onward (2025-08-17 → today): STANDARD** (hot, instantly readable).
- **Everything before 2025-08-17 (back to 2020): DEEP_ARCHIVE.** Requires an explicit `restore-object` call, ~12+ hour wait (Deep Archive standard retrieval tier), plus restore + retrieval costs, before it can be read at all.

The boundary lands exactly on 2025-08-17 because that was the last day still inside the ~15-day rolling reprocessing window as of 2025-09-01 (365 days before today) — the last file ever rewritten before aging out and starting its own 365-day clock.

**All 243 files in `news/2026/` (the full Jan–Aug 2026 range) are STANDARD — zero cold-storage constraint for that scope.** If this ticket's scope extends further back (2025 pre-08-17, or 2020–2024), that's a materially larger and costlier undertaking — bulk Glacier restores, not a simple read-transform-write script. Relevant to open question 4 below (exact range confirmation).

## Open questions / next steps

1. ~~Determine S3 storage class...~~ — **CONFIRMED (2026-09-01)**, promoted below.
2. ~~Which source field(s) get converted for the `-3` output~~ — **CONFIRMED (2026-09-01): none. No field-value conversion at all.** This re-frames the whole task: `-3.json` is not a timezone-converted copy of the records, it's a **re-bucketing** of which file each record belongs to — the same day-boundary fix GITIN-1970 applied going forward, now applied retroactively to the historical files by reassigning records between the Day/Day+1 file pairs. Record content (including all date fields, still raw UTC `Z`) stays byte-identical to how it already appears in the source files.
3. ~~Which field decides membership~~ — **CONFIRMED (2026-09-01).** `handler.js`'s `retrieveData()` queries MongoDB on `updatedAt` (Mongoose's own camelCase field, from `{ timestamps: true }`) — this is the field to replicate for bucketing. Field-name casing in the exported JSON itself still varies across the range, per `orderMapper`'s dead-code bug (GITIN-1970, H4):
   - `news20250817.json`–`news20260816.json` (bulk of this ticket's range): raw unmapped export, key is **`updatedAt`** (camelCase) — matches the Lambda's query field directly.
   - `news20260817.json`–`news20260831.json` (regenerated under GITIN-1970's fix): mapped export, key is **`updatedat`** (lowercase).
   Script must check the correct key per file/date rather than hardcoding one casing.
4. ~~Does this ticket cover the full 2026-01-01–2026-08-31 history, or a narrower range?~~ — **CONFIRMED (2026-09-01): all hot (STANDARD) storage.** Combined with the Day+Day+1 pairing constraint, the practical target range is:
   - **Oldest buildable day: 2025-08-17** (the oldest STANDARD file — building it needs `news20250817.json` + `news20250818.json`, both hot; `2025-08-16` would need `news20250816.json`, which is DEEP_ARCHIVE, so excluded per "all hot storage").
   - **Newest buildable day: 2026-08-30** (needs `news20260830.json` + `news20260831.json`, both exist. `2026-08-31` itself is NOT yet buildable — would need `news20260901.json`, which doesn't exist, since the Lambda never writes "day 0"/today; this shifts forward automatically as new days are written).
   - Still not confirmed: whether `news20260817.json`–`news20260831.json` (already regenerated under GITIN-1970's fixed boundary code) need a `-3` counterpart same as everything else, or are handled differently — no indication so far that they should be treated specially, since this ticket operates on file *content* (field values), not on which boundary logic wrote the file.
5. This repo doesn't execute scripts or write to S3 directly — any transformation script produced here is for the user to review and run themselves, per project convention (see root `CLAUDE.md`).

## Confirmed: merge logic validated (2026-09-01)

`scripts.py` drafted (Python/boto3, `requirements.txt` for a venv), implementing the Day+Day+1 merge, no field conversion, `updatedAt`/`updatedat` dual-casing check, `--resume` (local `progress.txt` checkpoint), `--skip-existing` (S3-based check), and `--profile`.

**Validated in two directions, both confirmed correct:**
- **Already-fixed range** (`2026-08-24`, inside GITIN-1970's fixed output): `desde D+1: 0` — merge correctly contributes nothing extra, no contamination. Cross-checked the full `2026-08-24`–`2026-08-30` real write against the actual per-day upload sizes logged earlier in `20260831_lambda-s3-export-utc3/data/invoke_log_redeploy.txt` — bytes-per-record stayed within a ~1% band (2513–2536) across a nearly 4x growth in daily volume, strong evidence the record counts are correct, not a merge artifact.
- **Pre-fix range** (`2026-01-15`, dry-run): `desde D: 16794, desde D+1: 9678` — the merge is genuinely rescuing a substantial (37% of the day's total) block of spillover records from the D+1 file, consistent with a dinner-delivery business clustering order completions in the 21:00–24:00 Argentina window (the exact original bug's spillover window).

**Real writes so far:** `news20260824-3.json` through `news20260830-3.json` (7 days) written to S3, matching validated dry-run counts exactly.

**Ready for the full range** (`2025-08-17`–`2026-08-30`) via `python scripts.py --resume` (will skip the 7 already-done days via `progress.txt`, seeded during the validation runs).

## Confirmed: first production batch complete (2026-09-01)

`2025-08-17`–`2025-10-17` (62 days) finished clean: `{'written': 62}`, zero `missing-source`, zero parse errors. Ran 11:51:19–12:26:12 local (~35 min for 62 days, ~0.56 min/day).

**Remaining: 317 days (`2025-10-18`–`2026-08-30`).** At the observed rate, a single unbroken run would take roughly ~3 hours. `progress.txt` now has 69 entries total (62 from this batch + 7 from the earlier validation range), so `python scripts.py --resume` will correctly skip all of them and pick up at `2025-10-18`.

**Gap/duplication analysis re: the live Lambda's `DAYSBEFORE=2` rolling rewrite (2026-09-01):** confirmed no structural risk, for two independent reasons:
- **No duplication possible by construction** — day D's `-3` file matches `updatedAt` in `[D 03:00, D+1 03:00)` UTC, day D+1's matches the adjacent non-overlapping `[D+1 03:00, D+2 03:00)`. A record's `updatedAt` is a fixed value, can only satisfy one window.
- **No gap risk from the live rewrite** — `updatedAt` can't be backdated; once a day is more than 2 days old (outside the Lambda's active window), its source file content is permanently frozen, since no future event can produce a record with an already-past `updatedAt`. Rewriting an old day's file (if it ever happened) would reproduce identical content.

**Only real edge case:** once this batch's range gets close enough to "today" that day D+1's source file doesn't exist yet (Lambda never writes day 0), the script correctly reports that day as `missing-source` (not a silent skip) — resolves itself on a later `--resume` once D+1 exists. Only relevant for the final couple of days approaching `2026-08-30`+, not for batches run well before the present.

## Confirmed: permanent gap at the 2026-08-16/17 boundary (2026-09-01)

**Not a bug in this ticket's script — a genuine, permanent data-loss side effect of GITIN-1970's backfill**, discovered while investigating the gap/duplication question above. Full detail and confirmation (Mongo count query = 0, S3 versioning shows no retained prior version) logged in `20260831_lambda-s3-export-utc3/investigation.md`.

**Practical effect on this ticket:** `news20260816-3.json` will be built correctly by `scripts.py` (no bug in the merge logic itself), but will be **permanently missing** the `2026-08-16 21:00–24:00` Argentina-local records — that 3-hour slice no longer exists in either source file (`news20260816.json` or `news20260817.json`), nor in Mongo. No script change can fix this; the underlying data is gone. When this day is eventually processed as part of the full range, expect (and don't investigate further) a `desde D+1` count that's anomalously low or zero compared to neighboring days — that's expected, not a regression.

## Follow-up: live Lambda changed to write `-3` filenames directly (2026-09-01)

At the user's request, `mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO`'s `saveS3()` was changed (in `20260831_lambda-s3-export-utc3/handler.js`, not yet confirmed deployed) so `filename` is `news${year+month+day}-3.json` going forward — matching this ticket's naming convention directly at the source, for compliance. Confirmed safe (no downstream S3 consumer exists yet, per user).

**Effect on this ticket's remaining scope:** once that Lambda change deploys, this ticket's normalization job no longer needs to process any date on/after the deploy date — the Lambda itself will produce the correctly-named, correctly-bucketed file natively. Remaining scope for `scripts.py` becomes purely historical: `2025-08-17` through whatever date the Lambda change ships. Need to confirm the exact deploy date once it happens, to set the final `--end` boundary precisely (don't want to leave a gap between the last script-processed day and the first natively-`-3`-produced day).

**Also made configurable (2026-09-01):** `ARG_OFFSET_MINUTES` now reads from `process.env.ARG_OFFSET_MINUTES`, defaulting to `-180` only when unset. Used an explicit `!== undefined` check rather than `parseInt(...) || -180` — the latter would silently ignore a deliberate `ARG_OFFSET_MINUTES=0` (falsy but valid), the same class of bug already found and fixed for `DAYSBEFORE` (GITIN-1970, H2). Relevant to the earlier-discussed idea of running the Lambda with offset `0` to recover old UTC-bucketed output — that path now actually works if attempted, whereas a naive `||` implementation would have silently defeated it.

## In progress: second production batch (2026-09-01)

Running `2025-10-18`–`2026-02-18` (~124 days) as a real (non-dry-run) batch with `--resume`, started 12:26:12 local — immediately following the first batch's completion. Not yet confirmed complete.

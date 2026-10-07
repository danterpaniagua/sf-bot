# Investigation — 20260831_lambda-s3-export-utc3

**Jira:** [GITIN-1970](https://smartit-ar.atlassian.net/browse/GITIN-1970) ("[SP] Corregir el export de Lambda -> S3 para que traiga UTC-3"), sibling subtask of GITIN-1872 (parent, "[SP] Envío de datos de SP a Grido"), alongside GITIN-1873 (converged, `smartpedidos/events/20260818_grido-news-etl-s3/`), GITIN-1874 ("[SP] Creación de ETL -> S3" — confirmed the *new* Python Lambda, `smartpedidos/events/20260901_grido-redacted-etl-lambda/`, not this function), GITIN-1880 ("[SP] Securización de S3").

**File-naming note (2026-09-02, from user):** in the real deployed source, the Lambda handler is `Handler: src/handlers/handler.handle` (confirmed earlier via `get-function-configuration`) — a **thin wrapper** file (`handler.js`) that just does `const { run } = require('./app'); exports.handle = async (event, context) => { context.callbackWaitsForEmptyEventLoop = true; await run(); }`. All the actual business logic this investigation has been calling `handler.js` throughout (`orderMapper`, `run`, `saveS3`, etc.) corresponds to the real `app.js`. **Both files now exist correctly named in this event folder** — `app.js` (the business logic, all of this session's fixes) and `handler.js` (the real thin wrapper, unchanged by any of this investigation's work). Every other mention of "`handler.js`" throughout the rest of this file (and in `ops.md`/`ops-events.md`) predates this correction and actually refers to what's now `app.js` — not rewritten throughout for size, but flagged here once.

**New finding (2026-09-01), discovered during GITIN-1980 work: the backfill caused a confirmed, permanent 3-hour data-loss gap.** The `DAYSBEFORE=15` backfill overwrote `news20260817.json` with new (Argentina-day-boundary) content, which structurally excludes UTC `08-17 00:00–03:00` — a slice that *old-code* semantics used to capture (old-code `08-17` covered UTC `[08-17 00:00, 08-18 00:00)`). That slice is exactly Argentina day `08-16`'s `21:00–24:00` local spillover (the original bug's window). `news20260816.json` (untouched by the backfill, still old-code) never had it either — its own boundary ends precisely at `08-17 00:00 UTC`, one slice too early. **Confirmed unrecoverable**: `db.news.countDocuments()` for that exact window returned `0` (implausible for Argentina's dinner-rush hours — comparable days showed ~37% of daily volume in this slice), and `list-object-versions` on `news20260817.json` shows only one version (`VersionId: "null"`, bucket versioning is "Suspended" — no prior version retained). Both the Mongo source (TTL-expired) and the S3 object (overwritten, no retained version) are gone. This is a genuine, permanent 3-hour gap in the historical export for `2026-08-16`, caused by this ticket's own backfill — not fixable retroactively by any means found so far. Flagged for Dev/PM awareness; not something SRE tooling can recover.

**Status: RESOLVED, fully deployed and validated end-to-end (2026-09-02)** (except for the permanent data-loss gap noted immediately above, unrelated to code correctness — not fixable). Every fix from this session (`connString`, `daysBefore` parsing, OOM/batched writes, `orderMapper` dead-code, dual UTC0/`-3` write, configurable `ARG_OFFSET_MINUTES`/`REGION`, `originalid`/`displayid`/`canje`) is confirmed live in production, verified against a fresh real export on 2026-09-02: `originalid`/`displayid` present on 100% of 19,101 records; `canje` correctly present/absent matching its natural population rate in the source data (absent = `undefined` dropped by `JSON.stringify`, not a bug). `DAYSBEFORE` confirmed reverted back to the steady-state `2` after this validation run.

**Follow-up change (2026-09-01), motivated by GITIN-1980's `-3` naming convention:** `saveS3()`'s `filename` changed from `news${year+month+day}.json` to `news${year+month+day}-3.json` — going forward, the live Lambda writes directly under the `-3` name GITIN-1980 uses for retroactively-corrected historical files, so there's no more distinction in filename between "raw" and "corrected" for any date after this deploys. Confirmed safe: no downstream consumer exists yet for these S3 files (per user, 2026-09-01) — a rename would otherwise have silently broken anything reading the old key pattern. Applied to local `handler.js` in this event folder; not yet confirmed deployed to production. Once deployed, GITIN-1980's `scripts.py` no longer needs to process any date on/after the deploy date — its remaining scope becomes purely `2025-08-17` through whatever date this ships.

**Confirmed deployed and live (2026-09-01)** — a manual invoke's CloudWatch log showed `news*-3.json` filenames being written directly (`pushS30`–`pushS314`, 15 days, `2026-08-17`–`2026-08-31`), confirming the rename shipped to production. This overlapped with and overwrote GITIN-1980's own earlier validation-batch output for `2026-08-24`–`2026-08-30` — not a correctness issue (both are equivalent for this post-fix range, already validated `desde D+1: 0`), but means GITIN-1980's remaining scope should stop at `2026-08-16` to avoid redundant reprocessing.

**Revised (2026-09-01), same day, per user request — backwards compatibility:** rather than replacing the plain filename, `saveS3()` and `run()` were restructured so **both files are written per day**: `newsYYYYMMDD.json` (UTC-midnight boundary, offset `0` — restores the original pre-GITIN-1970 behavior for compatibility) and `newsYYYYMMDD-3.json` (Argentina/UTC-3 boundary, current fix). Two separate Mongo queries + S3 writes per day (deliberately not one query split two ways, to avoid a subtle boundary bug) — roughly doubles runtime, still well inside the 900s Lambda timeout. This also resolves the redundancy concern above: since the plain name is being actively maintained again, there's no more "frozen legacy file" ambiguity going forward.

**Confirmed deployed and validated (2026-09-01)** — manual invoke log confirms both `pushS3utc0-N` and `pushS3arg-N` firing for every day (`2026-08-17`–`2026-08-31`, 15 days × 2 writes = 30 total), both `newsYYYYMMDD.json` and `newsYYYYMMDD-3.json` uploaded successfully. `Duration: 158528.41 ms` (~2:38), `Max Memory Used: 2463 MB`, no errors. Per-day file sizes differ meaningfully between the two boundaries (e.g. `08-31`: `59.55mb` UTC0 vs `48.01mb` Argentina) — expected, confirms the two conventions are genuinely capturing different record sets, not just duplicating the same content under two names.

**Content-level consistency check on real data (2026-09-01):** downloaded and analyzed both files for the last 4 days (`08-28`–`08-31`, `data/consistency_check/`, ~755MB, 8 files). Verified programmatically — every single record in every file falls inside its own claimed boundary window (`utc0_out_of_bounds` / `arg3_out_of_bounds` = 0 across all 4 days, ~285k records checked total):

| Día | UTC0 | `-3` | Solo UTC0 | Solo `-3` | En ambos |
|---|---|---|---|---|---|
| 28 | 22855 | 29460 | 8682 | 15287 | 14173 |
| 29 | 39859 | 42385 | 15286 | 17806 | 24573 |
| 30 | 59639 | 54492 | 17791 | 12663 | 41828 |
| 31 | 23591 | 19052 | 12666 | 8127 | 10925 |

Overlap pattern (~40–60% shared per day) is consistent with the ~3-hour boundary shift between the two conventions, not an anomaly. Minor note: a few days show slightly fewer unique `order.id`s than total records (e.g. `08-29` `-3`: 42385 records / 42379 unique) — not a duplication bug, the `news` collection is an event/notification log where the same order can have multiple distinct documents landing in one day's window. All four bugs found this session (connString interpolation, daysBefore string-arithmetic, OOM from batch-all-in-memory, orderMapper dead-code) were fixed and redeployed (`CodeSha256: 2Ex8EsKp+UsD5zrzsfE8d4ey6U4MP6t4vYyTayHT+rY=`, confirmed via `data/get_function_config_redeploy_check.json`). Manual `aws lambda invoke` at `2026-09-01T13:24Z` (`data/invoke_log_redeploy.txt`) completed cleanly: 10 days processed (`DAYSBEFORE` env var also lowered to `"10"`), `Max Memory Used: 2307 MB` (no OOM, well under the 4096MB cap), no connection errors (a `mongodb://` deprecation warning appeared but is informational, non-blocking).

**Both remaining open items confirmed via a real exported record** (`data/s3_sample_news20260831_redeploy.json`):
- **`orderMapper` fix confirmed**: exported fields are the mapped lowercase schema (`platformid`, `ordertime`, `pickuponshop`, `createdat`, `extradata`, etc.), not raw Mongoose shape.
- **UTC-3 day-boundary fix confirmed against the exact original bug scenario**: record 1's `updatedat` = `2026-09-01T02:59:51.157Z` (UTC) = `2026-08-31 23:59:51` Argentina local — 9 seconds before Argentina midnight. Under the **old** UTC-midnight-boundary bug this would've been misfiled into the Sept 1 file (since it's past `2026-09-01T00:00:00Z`); it correctly landed in `news20260831.json`. Direct confirmation, not inferred.

**Self-correction, earlier in this session:** the missing `news/2026/09/` prefix (checked repeatedly during the connString/daysBefore failures) was treated as suspicious/diagnostic evidence — that was a misreading on my part. The day-array construction (`.splice(1)` on the `[0..daysBefore]` range) has always deliberately excluded day 0 ("today") — the function only ever writes yesterday-and-earlier files. A September file won't legitimately appear until this runs *on or after* 2026-09-02 (processing 2026-09-01 as day `-1`). The real evidence of failure was always the CloudWatch error/OOM, not the missing prefix — noting this so the same false signal isn't chased again.

**Local `handler.js` in this event folder holds the fixed version, now confirmed matching production behavior.**

**Delta/backfill assessment (2026-09-01):** initially framed as "233 days (2026-01-01 to 2026-08-21) still on old buggy code" — corrected once the `news` collection's 15-day TTL (`GITIN-1965`) was factored in. Historical backfill via this Lambda is only possible for whatever's still inside Mongo's retention window, not the full year — days older than ~15 days back have already been purged from the source and are permanently stuck with whatever the old code exported (no way to regenerate via this function; would require rewriting the existing S3 JSON directly, out of scope here).

**Backfill executed (2026-09-01):** `DAYSBEFORE` temporarily widened `10 → 15` (`update-function-configuration`, not saved to `data/` — user ran directly) to capture the full Mongo-TTL window before Aug 17–21 aged out. First invoke attempt hit a client-side CLI read timeout (60s default) — **not a Lambda failure**, just the synchronous invoke taking longer than the CLI's socket wait; retried with `--cli-read-timeout 300`. Retry succeeded: `data/invoke_log_backfill15_retry.txt` — `Duration: 76324.99 ms`, `Max Memory Used: 2371 MB`, no error, processed `pushS30`–`pushS314` (15 items). Tail log only shows `pushS33` onward (CloudWatch `LogResult` truncates to ~4KB), but the sequential `for`-loop with `await` can't reach `i=14` unless every prior day (including Aug 17–19, off the visible tail) completed without throwing. **All 15 days (2026-08-17 through 2026-08-31) now hold correctly-fixed data** — the previously at-risk Aug 17–21 window is captured, nothing was lost to the TTL.

**`DAYSBEFORE` steady-state value: 2** (user decision, 2026-09-01) — narrower than the 15 used for the one-time backfill. Applied directly via AWS Console (not the CLI command drafted in this session — `data/update_config_daysbefore2_final.json` was never generated/needed). **Confirmed** via `data/get_function_config_daysbefore2_confirm.json`: `DAYSBEFORE: "2"`, `LastUpdateStatus: "Successful"`, `State: "Active"`, `CodeSha256` unchanged from the last redeploy (config-only change, no code touched). Note for future sessions: at `DAYSBEFORE=2`, a skipped/failed run for more than 2 consecutive days will leave a permanent gap that won't self-heal on the next successful run, unlike the wider window used during this session's backfill — worth checking for gaps if any future outage is found to have lasted more than a day or two.

**Root cause (confirmed from the same deployed source, `handler.js` line 15):**
```javascript
const connString = `mongodb+srv://MONGO_USER:MONGO_PASSWD@HOST/DATABASE`;
```
Plain template literal, **no `${}` interpolation** — connects to the literal string `HOST`, not `process.env.HOST`. **Correction:** this line was previously assumed (see "Confirmed: root cause" section below, and the now-stale note near the source-paste discussion) to be a redaction the user applied before pasting source into this session. The production stack trace disproves that — this literal string is what is actually deployed. Proposed fix: `` `mongodb+srv://${user}:${passwd}@${host}/${database}` `` (variables already declared lines 9–13).

Unrelated to this bug, also confirmed in the same log pull: `HOST` env var is no longer empty (`pedidossmartfran.narx2.mongodb.net`, confirmed via `data/get_function_config_post_run.json`) — resolves the previously open "empty HOST" question, though it's moot until the interpolation bug is fixed since the string never uses the var.

**Second, independent bug found (2026-09-01), user pasted current lambda source:** `handler.js` line 7 is **no longer** `const daysBefore = 15;` (that was accurate as of the earlier 13:50 paste) — it now reads `const daysBefore = process.env.DAYSBEFORE;`, a string (`"124"` per `data/get_function_config_post_run.json`). Not confirmed when this line changed relative to the connString bug, or whether it was part of the same 08-31 deploy — flagged as unconfirmed timeline, not load-bearing for the fix itself.

Effect: `Array.from(Array(daysBefore + 1).keys()).splice(1).reverse()` (line 192) — `daysBefore + 1` string-concatenates (`"124"+1 = "1241"`) instead of adding; `Array("1241")` (non-numeric single arg) builds a 1-element array, not a 1241-length one; after `.keys()`/`.splice(1)`/`.reverse()` the result is `[]`. **The day-processing loop then runs zero iterations — `run()` completes cleanly with no S3 writes and no thrown error.** This bug is independent of and would survive a `connString` fix: even once Mongo connects, this function would still silently write nothing.

**Third bug (2026-09-01), found via manual `aws lambda invoke` after the first two fixes were applied:** function got past connect and the day-array construction this time — reached the sequential S3-push loop (`saveS3()`'s `console.log('Going to insert: ', filename)`, observed for `news20260822.json`) — then crashed:
```
Status: error   Error Type: Runtime.OutOfMemory
Duration: 52683.64 ms   Billed Duration: 53522 ms   Max Memory Used: 4096 MB   Memory Size: 4096 MB
```
Root cause: `run()`'s original structure (`Promise.all(updateFileProms)`) fetches and fully builds **all 15 days** of news data in memory *before* any S3 write starts — the sequential `saveS3()` loop only begins once every day's fetch+transform has resolved. Per-day file sizes observed earlier in this investigation run up to ~180MB raw JSON (`news20260830.json` = 182MB) — holding ~15 days concurrently plausibly exceeds the already-maxed 4096MB (Lambda's ceiling is 10240MB, not yet tried as a quick mitigation — batching is the real fix, see below).

**Fourth bug, found while reading the same function closely — likely pre-existing, not introduced by this deploy** (this code is unchanged across every version of `handler.js` seen in this investigation): `orderMapper()` builds a full `parsedOrder` object with a lowercase-renamed field schema (`platformid`, `statusid`, `ordertime`, etc.), then its final line is `return order;` — the **raw, unmapped original object** — not `return parsedOrder;`. All the transformation work is dead code; every exported record has always been the raw Mongoose-shaped document. Relevant to GITIN-1872's stated purpose ("Envío de datos de SP a Grido") — if Grido's ingestion expects the mapped lowercase-keyed shape, it has never actually received it.

**All four fixes, folded into GITIN-1970 per user (2026-09-01):**
```javascript
// 1. connString — add missing interpolation
const connString = `mongodb+srv://${user}:${passwd}@${host}/${database}`;

// 2. daysBefore — parse the env var as a number
const daysBefore = parseInt(process.env.DAYSBEFORE, 10) || 15;

// 3. orderMapper — return the transformed object, not the raw one
return parsedOrder; // was: return order;

// 4. run() — write each day to S3 as it's ready, don't hold all 15 in memory first
// (also fixes: a single sparse/empty day no longer aborts the whole batch via
//  Promise.all's reject() — now just `continue`s past that one day)
for (const rawDay of arrayDaysBefore) {
  const day = -rawDay;
  // ...compute momentDate/dateGt/dateLte as before...
  const data = await retrieveData(dateGt, dateLte);
  const stringNew = data.map(orderMapper).map(o => JSON.stringify(o) + '\n').join('');
  if (stringNew.length < 10) continue;
  await saveS3(momentDate, stringNew);
}
```
Full proposed-fix source written to `handler.js` in this event folder (2026-09-01) — reference only, this repo doesn't deploy Lambda source.

**Side item, bundled into the same deploy at user's request (2026-08-31):** `mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO` was on the deprecated `nodejs12.x` runtime (AWS end-of-support). User ran `update-function-configuration --runtime nodejs18.x`; **confirmed `LastUpdateStatus: "Successful"`** on re-check (`State: "Active"`). User then further bumped to `nodejs24.x` (confirmed valid/accepted by AWS — real `RuntimeVersionConfig` populated in response); **confirmed `LastUpdateStatus: "Successful"`** on re-check (`State: "Active"`). Both runtime bumps complete. Unrelated to GITIN-1970's scope but tracked here since it went out in the same deploy.

~~Flagged, still unresolved: the function's `HOST` env var shows as an empty string...~~ — **superseded 2026-09-01**, see the connection-string bug above: `HOST` is no longer empty, and the assumption that the function was "demonstrably working in production" no longer holds — it has been failing on every invocation since the 2026-08-31 deploy.

## Scope

Fix a Lambda function that reads the `news` collection (MongoDB Atlas) and writes it to S3, so its exported timestamps are in UTC-3 (America/Argentina/Cordoba, fixed offset, no DST) instead of whatever timezone it currently produces.

## Confirmed facts

- **Function identified (2026-08-31)**, via `aws lambda list-functions` (region `us-east-1`, account `382381053403`; full output saved: `data/lambda_list_functions.json`):
  - **`mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO`** — `arn:aws:lambda:us-east-1:382381053403:function:mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO`, runtime `nodejs12.x`, handler `src/handlers/handler.handle`, timeout 900s, memory 4096MB. AWS's own description: *"Extrae datos desde la colección News de Mongo Atlas para convertirlas en documentos JSON de los últimos 15 días anteriores a la fecha actual en forma diaria y guardarlas en S3."* **Correction (2026-09-02): this is NOT GITIN-1874's ETL** — GITIN-1874 confirmed as the new Python Lambda (`smartpedidos/events/20260901_grido-redacted-etl-lambda/`), not this existing Node.js function. This earlier assumption (and the parallel one in `20260831_s3-bucket-securization/investigation.md`) was wrong. This function is purely GITIN-1970's fix target.
  - A second function, **`mongoAllCollections-to-s3-CFN-ScheduledMongoToS3-MRO2H3EOSN6E`**, description implies broader collection coverage, configurable region/connection string per environment.
- **Both functions confirmed actively scheduled (2026-08-31)**, via `aws lambda get-policy` (`data/policy_mongo-to-s3.json`, `data/policy_mongoAllCollections.json`) + `aws events describe-rule` (`data/eventbridge_rule_mongo-to-s3.json`, `data/eventbridge_rule_mongoAllCollections.json`):
  - Each has its own distinct EventBridge rule granting `events.amazonaws.com` invoke permission — not a shared/duplicate rule.
  - **Both rules use the identical schedule `cron(30 3 * * ? *)` = 03:30 UTC daily (00:30 in UTC-3), both `State: ENABLED`.** This explains why the CloudWatch `Invocations` metrics pulled for both functions looked byte-identical (`data/invocations_mongo-to-s3.json`, `data/invocations_mongoAllCollections.json`, ~1 invocation/day for ~30 days each) — not a duplicate query, both genuinely run once/day on the same cron.
  - **Resolves open question, previously #2:** both functions are real and actively running, not one dormant. Still not confirmed which one (or both) needs the UTC-3 fix — see below.
- **Correction:** an earlier read of this investigation stated the CloudWatch datapoint timestamps (`13:20:00-03:00` on every day) indicated a real invocation time mismatched against the S3 write time. That was wrong — with `--period 86400` and a non-midnight `--start-time`, `get-metric-statistics` buckets from the query's own start time, not calendar-day boundaries, so that time-of-day is an artifact of when the CLI command was run, not a real Lambda invocation clock time. No actual discrepancy exists.
- **Direct S3 evidence (2026-08-31)** via `aws s3 ls s3://smartfranbkp/news/ --recursive` (`data/s3_ls_news.txt`, `data/s3_ls_root.txt`): bucket root confirms a `news/` prefix (plus `activeSoftware/`, `branches/`, `chains/`, `orders/`, etc. — siblings, not sub-paths of `news/`). File layout is `news/YYYY/MM/newsYYYYMMDD.json`, one file per day. On 2026-08-31, files `news20260816.json` through `news20260830.json` (15 files) were all rewritten within the same ~20-second window (`LastModified` ~`00:31:26`–`00:31:46`, one minute after the `03:30 UTC` cron trigger assuming the CLI's local timezone is Argentina) — matches the documented rolling 15-day-window behavior exactly. Good corroboration the News export is real and working as described; **this is not yet source-code-confirmed as coming specifically from `mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO`** (vs. `mongoAllCollections`), since both share the same cron and neither's actual write-path code has been reviewed yet.
- **Notable, unconfirmed coincidence:** the News-specific function's own "last 15 days" export window matches exactly the 15-day retention limit found on the `news` collection (`smartpedidos/docs/infrastructure.md`, confirmed under `GITIN-1965`). Not established whether this export function is itself involved in that retention (e.g. archives-then-deletes) or whether it's coincidental. Check before assuming either way.
- **Source code pasted by user (2026-08-31, unconfirmed origin) does not appear to be the News exporter.** Its `Schemas` array covers `activeSoftware`, `branches`, `chains`, `clients`, `countries`, `deliveryTimes`, `newsStates`, `newsTypes`, `platforms`, `regions`, `users`, `rejectedMessages` — no `news` entry — so more likely `mongoAllCollections`'s handler, not yet confirmed by user. Contains no timestamp/UTC-3 logic at all (raw `JSON.stringify(order)` of Mongoose output; `moment` imported but unused) — if this is genuinely the whole handler, it is **not** the file containing this ticket's bug. Two apparent bugs also flagged to the user, unrelated to this ticket, unconfirmed as real vs. paste-transcription artifacts: `mongoose.connect(connString, ...)` where the built URI is assigned to `uri`, not `connString` (undefined reference); `AWS.config.update({ region: REGION, ... })` where the actual variable is lowercase `region`, not `REGION` (undefined reference). Not yet logged as a separate tech-debt item — pending user confirmation these are real.

## Current working theory

~~The Lambda likely timestamps its output in UTC...~~ — **CONFIRMED (2026-08-31)**, promoted below.

## Confirmed: the actual bug (2026-08-31)

Pulled a real 2KB slice of `news/2026/08/news20260830.json` via `aws s3api get-object --range bytes=0-2000` (`data/s3_sample_news_record.json`; first `head -c`/pipe attempt failed with a harmless broken-pipe error since `head` closes the pipe before a 182MB streamed object finishes — range request avoided that). Confirmed from the object's own metadata: `LastModified: 2026-08-31T03:31:46+00:00` (explicit UTC) — matches the `cron(30 3 * * ? *)` trigger (03:30 UTC) to the minute, and confirms `aws s3 ls`'s earlier `2026-08-31 00:31:46` display for the same file was in the local (Argentina, UTC-3) timezone of the CLI's host, not UTC.

**Every date field in the exported record carries an explicit `Z` (UTC) suffix** — no conversion to UTC-3 happens anywhere before write:
- `order.orderTime`: `"2026-08-30T20:38:32Z"`
- `createdAt`: `"2026-08-30T23:38:46.460Z"`
- `traces[].createdAt`: `"2026-08-30T23:38:46.461Z"`

This is the standard behavior of `JSON.stringify()` on a raw Mongoose document — `Date.prototype.toJSON()` always calls `toISOString()`, always UTC — with no explicit timezone handling applied. Resolves former open question 3 ("which field(s) need conversion"): **all Date-typed fields in the record**, since the mechanism is generic serialization, not a single named field.

## Ruled out

- ~~CloudWatch invocation-time vs. S3-write-time discrepancy~~ — artifact of `get-metric-statistics` bucketing, not a real scheduling conflict (see above).
- ~~One of the two functions might be dormant/unused~~ — both confirmed actively scheduled via EventBridge + invocation metrics.

## Confirmed: root cause, in real source (2026-08-31)

User pasted the actual `mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO` handler source (obtained via `get-function`, cleaned of credentials before sharing — the `connString` line as pasted is a deliberate redaction, not a real bug: literal `mongodb+srv://MONGO_USER:MONGO_PASSWD@HOST/DATABASE` string with no `${}` interpolation). **Code-confirmed as the right function**, not just inferred: `saveS3()` builds `directory = ${bucket}/${collection}/${year}/${month}` and `filename = news${year+month+day}.json` with `collection = 'news'` — an exact match to the real `news/YYYY/MM/newsYYYYMMDD.json` layout observed in `data/s3_ls_news.txt`. `daysBefore = 15` matches the documented "últimos 15 días" behavior.

**Root cause:**
```javascript
const zeroHour = { hour: 0, minute: 0, second: 0, millisecond: 0 };
const momentDate = moment.utc().set(zeroHour).add(day, 'days');
const dateGt = moment.utc().set(zeroHour).add(day, 'days').format('YYYY-MM-DD HH:mm:ss.SSSZ');
const dateLte = moment.utc().set(zeroHour).add(day + 1, 'days').format('YYYY-MM-DD HH:mm:ss.SSSZ');
```
Day-file boundaries are computed at **UTC midnight** (`moment.utc()`), not Argentina midnight (`03:00 UTC`, fixed offset, no DST per ticket scope). An order placed 21:00–24:00 Argentina local time (= 00:00–03:00 UTC the next day) is bucketed into the **next** day's export file instead of the day it actually happened locally — a full calendar-day misattribution for that ~3-hour window, every day.

**Scope confirmed with user (2026-08-31): fix the day-bucketing boundary only.** Field values inside each record (`order.orderTime`, `createdAt`, `traces[].createdAt`) stay as raw UTC ISO strings (`Z` suffix) — out of scope for this ticket, not to be reformatted.

**Proposed fix** (not yet applied — this repo doesn't deploy Lambda source, only analyzes/documents; actual deploy is the user's/Dev's call): use a fixed `-180` minute (UTC-3) offset instead of `.utc()` when establishing the "zero hour" boundary, no `moment-timezone`/tz-database dependency needed since the offset is fixed (no DST):
```javascript
const ARG_OFFSET_MINUTES = -180; // UTC-3, fixed, no DST (America/Argentina/Cordoba)
const momentDate = moment().utcOffset(ARG_OFFSET_MINUTES).set(zeroHour).add(day, 'days');
const dateGt = moment().utcOffset(ARG_OFFSET_MINUTES).set(zeroHour).add(day, 'days').format('YYYY-MM-DD HH:mm:ss.SSSZ');
const dateLte = moment().utcOffset(ARG_OFFSET_MINUTES).set(zeroHour).add(day + 1, 'days').format('YYYY-MM-DD HH:mm:ss.SSSZ');
```
`.utcOffset(-180)` fixes the moment's display/local frame to UTC-3 before `.set(zeroHour)` runs, so the zeroed time becomes true Argentina midnight rather than UTC midnight. The formatted `dateGt`/`dateLte` strings still carry correct offset info, so the MongoDB `updatedAt` range query (stored internally as UTC) compares correctly — only which instants count as day boundaries changes. `momentDate` (used for the `year`/`month`/`day` in the S3 filename) uses the same corrected boundary, so filenames align with Argentina calendar days too.

**Side notes, not part of this ticket's fix:**
- ~~The handler hardcodes `region: 'us-east-1'` in `AWS.config.update()` rather than using the `REGION` env var~~ — **fixed 2026-09-02**, at user's request. `AWS.config.update({ region: region, ... })` now actually uses `process.env.REGION` (already declared, just never wired up). Functionally identical today (env var's actual value matches the old literal), but no longer dead config — makes the region genuinely configurable rather than requiring a code change to move deployment regions.
- `daysBefore = 15` here is a **write-side reprocessing window** (re-scans/rewrites the last 15 days every run), separate from the `news` collection's 15-day **retention/TTL** (`GITIN-1965`) — still not established whether these are related or coincidental; not investigated further, low priority for this ticket.

## Open questions / next steps

1. **All four fixes confirmed deployed and validated (2026-09-01)** — connString interpolation, daysBefore parseInt, batched-by-day OOM fix, orderMapper return value. Ticket's core scope (GITIN-1970 UTC-3 boundary) and the three bugs found while investigating it are resolved. Remaining: normal close-out (Jira ticket update/closure), no further technical validation needed unless something regresses on tomorrow's scheduled `03:30 UTC` cron run.
2. Confirm with user whether the `connString`/`REGION` undefined-reference issues seen in the *earlier* (likely `mongoAllCollections`) pasted source are real bugs or paste artifacts; if real, log separately to `smartpedidos/docs/tech-debt.md` — out of scope for this ticket either way. Given this session's findings on the sibling function, treat that earlier "probably a paste artifact" judgment as less reliable than previously stated.
3. Not yet checked: whether `mongoAllCollections-to-s3-CFN-ScheduledMongoToS3-MRO2H3EOSN6E` (the sibling function) shares any of these four bugs — out of scope for GITIN-1970 unless it turns out to share code, not investigated this session.
4. ~~Recommend a spot-check after tomorrow's unattended `03:30 UTC` cron firing~~ — **done (2026-09-02)**, see below.

## Confirmed: unattended cron spot-check (2026-09-02)

Last night's `03:30 UTC` cron fired unattended (no manual invoke) and produced both `news20260901.json` and `news20260901-3.json` correctly — confirms the fix holds under normal scheduling, not just manual testing.

**Two things found in this check:**
- **`DAYSBEFORE` config drift**: still `15` (not the confirmed steady-state `2`) — left over from the manual invoke used to validate the dual-write feature the day before, never reverted. Explains why 5+ days got rewritten overnight instead of 2 (wasteful, ~7.5x more Lambda work than intended, but not incorrect — rewriting is idempotent). **User manually reset it to `2`, confirmed via a fresh `get-function-configuration` pull.**
- **Deployment gap**: the `originalid`/`displayid`/`canje` additions to `orderMapper()` (made 2026-09-01, *after* the dual-write deploy was already confirmed live) were never actually deployed. Confirmed by downloading and inspecting the real Sept 1 export (`data/consistency_check_20260902/`): both fields missing from 100% of records in both file variants (18,769 UTC0, 19,240 `-3`). Boundary correctness and cross-file consistency both still clean (0 out-of-bounds, healthy ~40–55% overlap matching prior validated days) — purely a "fix never shipped" gap, not a data-correctness regression. Local `handler.js` has the fix; production doesn't yet.

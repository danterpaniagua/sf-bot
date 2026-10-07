# Investigation — 20260901_grido-redacted-etl-lambda

**Jira:** [GITIN-1874](https://smartit-ar.atlassian.net/browse/GITIN-1874) ("[SP] Creación de ETL -> S3") — **confirmed 2026-09-02.** This resolves the ticket-identity ambiguity flagged throughout this session: `20260831_lambda-s3-export-utc3/investigation.md` and `20260831_s3-bucket-securization/investigation.md` had both originally assumed GITIN-1874 = the *existing* Node.js Lambda (`mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO`, GITIN-1970's fix target) — that assumption was wrong. GITIN-1874 is this new Python Lambda; both other files corrected to cross-reference this folder instead.

**Status: handler built and validated against real data, not yet deployed.** Scoping, field-audit, and local testing all complete — see sections below.

## Scope

A new, separate Python Lambda that reads the already-exported `-3` files from `smartfranbkp/news/` (GITIN-1970/1980's output), filters to Grido's data, applies a redacted field allow-list (per `20260818_grido-news-etl-s3/field-classification.md`), and writes the result into `smartpedidos-orders` (bucket created under GITIN-1880, `20260831_s3-bucket-securization/`).

## Confirmed facts (carried over / established this session)

- **Source:** the `-3` files (`smartfranbkp/news/*-3.json`) — confirmed by user. Not a direct MongoDB query.
- **Destination:** bucket `smartpedidos-orders` (`us-east-1`), already created (GITIN-1880). Multi-platform prefix design (`grido/`, `peya/`, etc.) exists but only Grido is in scope for now.
- **Filter criterion — resolved after real back-and-forth this session:** `extradata.chain == "Grido"` (lowercase key, matches `orderMapper()`'s output casing). This went through three candidates before landing here:
  1. `extraData.platform: "PediGrido"` — too narrow. Confirmed via real data (4 days, 144,964 Grido records): PediGrido is only 19.4% of Grido's actual volume (PedidosYa 66.3%, Rappi 6.2%, I+D 5.5%, UberEats 1.4%, MercadoPago 1.2%, Toque <0.1%). Would have silently dropped ~80% of Grido's data.
  2. `order.tenant.name: "grido"` — briefly confirmed, then found to be **absent entirely** from the `-3`/UTC0 files (`orderMapper()` never copies `tenant` into its output — confirmed both by code grep and empirically, zero occurrences of the string "tenant" in any casing across 4 real downloaded files). Not usable against this source.
  3. `extradata.chain` — confirmed present on 100% of records (29460/29460 in one sample day), correctly identifies Grido-branded orders regardless of originating platform. This is also what backed the original GITIN-1873 PII validation dataset (`grido_news_raw.json`), so that evidence is valid for this filter after all.
- **Field allow-list v1** (from `20260831_s3-bucket-securization/investigation.md`, GITIN-1880) needed real correction against `orderMapper()`'s actual output — it was written against the raw Mongoose schema, not the transformed export:
  - **Missing entirely from the `-3`/UTC0 files:** `order.originalId`, `order.displayId`, `order.details[].canje`. Confirmed present and 100% populated on real raw Mongo documents (5000/5000 sampled) — genuinely real fields, just dropped by `orderMapper()`. **Added to `orderMapper()` in `handler.js` this session** (2026-09-01) — fixes this **going forward only**; the entire 379-day historical range GITIN-1980 already backfilled will permanently lack these three fields (same class of gap as the `tenant` field, just discovered before historical damage was locked in this time, for future exports).
  - **Present, but lowercase in the real data, not camelCase as listed:** `platformId→platformid`, `statusId→statusid`, `orderTime→ordertime`, `deliveryTime→deliverytime`, `pickupOnShop→pickuponshop`, `pickupDateOnShop→pickupdateonshop`, `preOrder→preorder`, `ownDelivery→owndelivery`, `totalAmount→totalamount`, `createdAt→createdat`, `updatedAt→updatedat`, `details[].productId→productid`, `details[].groupId→groupid`.
- **`typeId`**: confirmed a foreign-key into a `newsTypes` Mongo collection (`cod`/`typeId`/`name`/`description`/`newsType` schema), resolvable to a human-readable `name` via `NewsTypeSingleton.typeById()` in source. **User decided: send the raw numeric `typeId`, not the resolved name** — no lookup needed.
- **`observations`**: confirmed REDACT (real PII leak — billing names, RUC/CI/DNI, phone numbers in free text, per `field-classification.md`). **Decision: send as `""` (blanked), not omitted.** No actual leak either way, just a minor deviation from "strip" (omit) — worth remembering if downstream expects the key absent rather than empty.
- **`customer.dni`**: classified REDACT in `field-classification.md` ("highest-sensitivity field in this collection"), requiring Legal/PM sign-off to override. **User decision (2026-09-01): include it regardless — "dni is needed, no way to not send it."** Justification given is operational (correlation key against Grido's own DB), not a confirmed Legal/PM sign-off — that sign-off's existence was never verified, only the business need was restated. Flagged twice this session; user has made the final call to include it anyway. Documented here as a known, deliberate deviation from the source classification, not an oversight.
- **`customer.id`**: REVIEW status in `field-classification.md` (not yet confirmed whether Grido needs it) — included in the v1 allow-list, not separately re-litigated this session.

## Current field allow-list (as of 2026-09-01, pending the full-audit query results below)

`order.id`, `order.originalid`, `order.displayid`, `order.platformid`, `order.statusid`, `order.ordertime`, `order.deliverytime`, `order.pickuponshop`, `order.pickupdateonshop`, `order.preorder`, `order.owndelivery`, `order.observations` (sent as `""`), `order.customer.id`, `order.customer.dni`, `order.details[]` (`productid`, `count`, `price`, `promo`, `groupid`, `discount`, `description`, `sku`, `canje`, `optionaltext`), `order.totalamount`, `branchId`, `createdat`, `typeId` (raw numeric), `updatedat`, `viewed`.

## Confirmed: allow-list finalized against Grido's actual spec (2026-09-01)

**Origin of this field shape (reported by user, 2026-09-02):** SRE was reassigned to Cloud/Graylog work before GITIN-1873/1874 could continue directly; the task passed to Dev, who sent Grido a sample log and got this exact JSON back as Grido's own field request — completing GITIN-1873's analysis via a real Dev↔Grido exchange, not an internal guess. This is Grido's real requested field shape (not just an internally-derived "safe" list). Cross-checked field-by-field against `orderMapper()`'s output post-fixes — **every field Grido asked for is already covered**: `order.id`, `originalId`/`displayId` (derivable from `id`, confirmed identical across every platform interface — `pedidosYa.js`, `mercadoPago.js`, `uberEats.js`, `thirdParty.js`, `glovo.js`, `rappi.js` — all set both from the same source value), `platformId`, `statusId`, `orderTime`, `deliveryTime`, `pickupOnShop`, `pickupDateOnShop`, `preOrder`, `observations` (blanked), `ownDelivery`, `customer.id`, `customer.dni`, `details[]` (`productId`, `count`, `price`, `promo`, `groupId`, `discount`, `description`, `sku`, `canje`), `totalAmount`, `branchId`, `createdAt`, `typeId` (raw numeric), `updatedAt`, `viewed`.

**The 12-field completeness audit (`orderPickedUp`, `orderDelivered`, `deliveryType`, `autoBillingDelivered`, `deliveryPartner`, `delivery_operation_type`, `type`, `puntosCanjeados`, `contieneCanje`, `cupon`, `promotion`, `shipping`, `subtotal`, `country`) found nothing REDACT-classified hiding in the gaps, but none of it is actually required by Grido's spec — no `orderMapper()` changes needed for these.** Allow-list is final.

## Handler built (2026-09-01)

`handler.py` drafted — reads `smartfranbkp/news/*-3.json`, filters `extradata.chain == "Grido"`, applies the finalized allow-list (renaming lowercase source keys to Grido's camelCase spec), writes to `smartpedidos-orders/grido/YYYY/MM/newsYYYYMMDD.json`. Rolling window via `DAYSBEFORE` env var (default 2, mirrors the existing Lambda's pattern) — not yet confirmed this is the right scheduling model for this new Lambda, just a reasonable default.

**Two assumptions baked in, not yet independently confirmed:**
- Every timestamp wrapped as MongoDB Extended JSON (`{"$date": "..."}`), matching Grido's example exactly. Not confirmed whether this is a deliberate requirement or an artifact of how that example was originally exported (e.g. `mongoexport --jsonFormat=canonical`).
- `details[].count`/`price`/`sku` coerced to strings, `groupId` coerced to a number — matching Grido's example exactly, even though the real source data has the opposite typing in places (`count`/`price` numeric, `groupId` sometimes a string). Single-example evidence, not a confirmed type contract.

**Destination filename convention is also an assumption**, not confirmed with user: `smartpedidos-orders/grido/YYYY/MM/newsYYYYMMDD.json` (no `-3` suffix, since the `grido/` prefix and separate bucket already signal "filtered/redacted" — the suffix's job in the source bucket doesn't carry over here).

## Confirmed: validated against real data (2026-09-01)

`test_local.py` — imports `transform()` directly (no AWS calls), runs against the 4 already-downloaded real `-3` files (`20260831_lambda-s3-export-utc3/data/consistency_check/`, 145,389 total records, 144,964 Grido-chain). Checks: output schema matches the confirmed shape exactly, no REDACT fields (`name`/`address`/`phone`/`email`/`tipoIdentificacion`/`driver`) leak through, `observations` always blanked.

**Result: 0 schema errors, 0 REDACT leaks across all 144,964 real records.** One real bug caught and fixed: `order.id`/`customer.id` came out as raw numbers in some records (source data is inconsistent — some platforms store these as numbers) instead of the strings Grido's spec requires. Fixed with explicit `str()` coercion, re-ran clean.

**Separately observed, not a bug in this code:** one sample record's `orderTime`/`pickupDateOnShop` came back as `"2026-08-28T23:58:29.00"` — missing the `Z` suffix, non-standard fractional-seconds format. This is present in the source `-3` file itself (likely a pickup-on-shop order with a synthetically-generated timestamp elsewhere in the platform pipeline), not introduced by `transform()`. Not fixed — don't understand the root cause well enough to normalize it correctly, and it may or may not matter to Grido's date parser. Worth revisiting if Grido reports date-parsing issues.

## Open questions / next steps

1. ~~Confirm GITIN-1874 ticket identity + get Jira URL~~ — **done (2026-09-02)**, see header.
2. ~~Full field-audit~~ — **done**, see "allow-list finalized" section above. Six-query inventory ran clean, 12 extra SEND fields found but none required by Grido's actual spec.
3. ~~Build the handler~~ — **done**, `handler.py`, validated against 144,964 real records, 0 schema errors.
4. Decide on scheduling/rolling-window design (mirrors the existing Lambda's `DAYSBEFORE` pattern, or different) — not yet discussed. Currently defaults to `DAYSBEFORE=2` in `handler.py`, unconfirmed.
5. `customer.dni` inclusion remains a documented, deliberate deviation from `field-classification.md`'s REDACT classification. Confirmed 2026-09-02: it's genuinely in Grido's own field request (not just an internal assumption), and the operational justification ("needed by Grido to cross-check the data") has been restated consistently across three separate asks this session. Legal/PM sign-off specifically (as distinct from Grido's own request/business need) was never confirmed one way or the other — asked three times, treating the user's consistent operational-justification answer as the final record rather than asking a fourth time.
6. Two typing/formatting assumptions in `handler.py` (MongoDB Extended JSON `$date` wrapping, `count`/`price`/`sku`/`groupId` type coercion) — the JSON they're based on is confirmed as Grido's own field request (not an arbitrary internal example, see origin note above), which strengthens confidence, but it's still one sample record, not a written type contract — the `$date` format and per-field types could still be incidental to how Dev's sample log was generated rather than a strict requirement.
7. Destination filename convention (`smartpedidos-orders/grido/YYYY/MM/newsYYYYMMDD.json`, no `-3` suffix) — an assumption, not confirmed with user.
8. Not yet deployed to AWS — this repo doesn't deploy Lambda code; `handler.py` is ready for Dev/user review and deployment.

## Flagged risk (2026-09-02): per-day memory usage, same class of bug as GITIN-1970's OOM

`process_day()` is correctly batched **across** days (one day's source/transform/write cycle at a time, matching the fixed Node Lambda's pattern from GITIN-1970 H3) — but **within** a single day, it reads the entire source file into memory at once (`res["Body"].read().decode("utf-8")`) and builds the entire transformed output list before a single `put_object()` call. Source `-3` files have been observed as large as ~180MB raw text (`2026-08-30`), and Python's JSON parsing/dict overhead typically runs several times the raw text size. This Lambda has never been deployed, so `MemorySize` has never been configured or tested against real volume — the exact same failure mode that hit the Node Lambda (GITIN-1970 H3) is a real risk here too, just not yet triggered because this code has only run locally against downloaded files, never inside an actual Lambda's memory ceiling. Worth deciding before first deploy: either configure generous memory (mirroring the Node Lambda's `4096MB`) and monitor, or restructure to stream/chunk within a day (e.g. process the source file line-by-line rather than loading it whole) — not yet decided.

## Local-run support added (2026-09-02)

`handler.py` gained `DRY_RUN`, `START_DATE`/`END_DATE` (explicit range, overriding the rolling `DAYSBEFORE` window), and `RESUME`/`PROGRESS_FILE` (local checkpoint, same pattern as GITIN-1980's `scripts.py`) — all via env vars, keeping it usable as a real Lambda trigger (`event`/`context` signature unchanged) while also being runnable locally: `python handler.py` (added `if __name__ == "__main__"` entry point). This enables testing against real S3 data (read-only from `smartfranbkp`, optionally write-enabled to `smartpedidos-orders`) before any AWS Lambda deployment exists for this function. Not yet actually run locally in this session — next step.

## IAM execution role created (2026-09-02)

`grido-redacted-etl-lambda-role` (`arn:aws:iam::382381053403:role/grido-redacted-etl-lambda-role`), confirmed via `data/iam_role_list_policies.json`, `data/iam_role_s3_policy.json`, `data/iam_role_attached_policies.json`:

- **Inline policy `grido-etl-s3-access`** — least-privilege, scoped to exactly what `handler.py` calls: `s3:GetObject` on `smartfranbkp/news/*` (read-only, source), `s3:PutObject` on `smartpedidos-orders/grido/*` (write-only, destination). No other S3 actions or resources granted.
- **Managed policy `AWSLambdaBasicExecutionRole`** attached for CloudWatch Logs.

This is the last deployment blocker resolved besides the EventBridge schedule (not yet discussed) and the per-day memory risk (flagged above, not yet resolved). Function itself (`create-function`) not yet run.

## First real write, validated (2026-09-02)

Ran `handler.py` locally against real S3 data (`2026-08-28`–`2026-08-31`, `PROFILE=dpaniagua.smartfran`), first in `DRY_RUN`, then for real. **Credential issue found and resolved along the way**: an earlier attempt with the literal placeholder `<your-profile-name>` (never substituted) produced `InvalidAccessKeyId` — not a permissions problem, just invalid/stale default credentials being picked up. Resolved by using the actual profile name (`aws configure list-profiles`).

**Real write succeeded**, downloaded and validated all 4 files (`data/first_write_validation/`) against the confirmed schema:

| Día | Registros | Errores de esquema | Fugas REDACT | `observations` no vacío | Errores de formato `$date` | `dni` presente |
|---|---|---|---|---|---|---|
| 08-28 | 29,315 | 0 | 0 | 0 | 0 | 6,027 (20.6%) |
| 08-29 | 42,234 | 0 | 0 | 0 | 0 | 9,376 (22.2%) |
| 08-30 | 54,349 | 0 | 0 | 0 | 0 | 12,145 (22.4%) |
| 08-31 | 18,920 | 0 | 0 | 0 | 0 | 4,707 (24.9%) |

Record counts match the `DRY_RUN` numbers exactly. Zero REDACT-field leaks across all 4 files. `dni` population rate (~20-25%) is consistent with the ~23.7% figure from GITIN-1873's original analysis. This is the first real, validated production output for GITIN-1874 — the transform logic is confirmed correct end-to-end against live data, not just the earlier downloaded-file tests.

## `dni` availability by platform, and transaction-ID check (2026-09-02)

**`dni` presence correlates with originating platform**, confirmed by cross-referencing `08-28`'s output against the source `-3` file's `extradata.platform` field:

- **`dni` present** — only from **PediGrido** (5,034) and **I+D** (997). Never from PedidosYa, Rappi, UberEats, MercadoPago, or Toque.
- **`dni` null** — dominated by **PedidosYa** (19,855, ~70% of all nulls), but present across every platform including a handful of PediGrido (4) and I+D (873, roughly split with its 997 present).

So: only PediGrido and I+D ever collect `dni` at all, and even for those two it's not guaranteed per-order (I+D roughly 53%/47% present/null; PediGrido is nearly always present, 5034 vs. 4 null). Every other platform never has it — PedidosYa's high volume just makes it numerically dominant among nulls, not the sole source.

**No dedicated transaction/payment ID field exists** in the source data — checked `platforms/interfaces/*.js` directly. `paymentId` in `pedidosYa.js` is an internal enum for payment *type* (1=cash, 2=credit, etc.), not a unique transaction reference; `voucher` is a discount-description string. The closest equivalent Grido has access to is `order.id` (sent three times as `id`/`originalId`/`displayId`).

**`order.id` confirmed present on 100% of records** — checked all 4 written files (144,818 records total), zero missing. Consistent with the original field audit (100% populated on raw MongoDB documents too) and the fact that `id` has been correctly mapped since the very first version of `orderMapper()`, unlike `originalId`/`displayId` which were dropped until yesterday's fix.

## Lambda function created (2026-09-02)

`grido-redacted-etl` created via `aws lambda create-function` (full response: `data/lambda_create_function_output.json`): `arn:aws:lambda:us-east-1:382381053403:function:grido-redacted-etl`, `python3.12`, role `grido-redacted-etl-lambda-role`, handler `handler.handle`, `CodeSize=3129` bytes (just `handler.py`, no dependencies bundled), `Timeout=900`, `MemorySize=4096` (mirrors the Node Lambda's proven-safe setting — this is the "generous memory" mitigation for the flagged per-day OOM risk, not the real streaming fix, which is still not implemented). Env vars: `SOURCE_BUCKET=smartfranbkp`, `DEST_BUCKET=smartpedidos-orders`, `DAYSBEFORE=2`, `REGION=us-east-1`. Confirmed `CodeSha256` matches the uploaded zip (just `handler.py`, no dependencies — `boto3`/`botocore` are pre-installed in the Python runtime). No EventBridge trigger yet — callable manually only.

**Remaining before this is a fully operational scheduled pipeline:** confirm `State: Active`, run a first real Lambda invoke (not just local execution) to validate the deployed function itself, and decide on an EventBridge schedule.

## Confirmed: dni is not hiding elsewhere for null-dni platforms (2026-09-02)

Checked whether `dni` might be embedded in `order.observations` (confirmed under GITIN-1873 to sometimes contain DNI/RUC/CI numbers in free text) for the platforms where `customer.dni` comes back null/empty — `scripts_dni_check.js`, `data/dni_observations_check.txt`, 20 example orders across all 7 platforms.

**Clean negative result.** None of the 20 `observations` values contain anything DNI-shaped — they're payment-method notes ("Medio de pago: VISA/MASTERCARD/Cash Collection"), order references (`#7859`), Toque's own receipt numbers (`R 0001-03336372`), or empty/null. Confirms `dni` is genuinely not collected for these platforms/orders, not just missing from the structured field while present elsewhere.

**Data-type quirk noted, not a bug:** PediGrido's and Toque's null examples show `dni: ''` (empty string) rather than `null` like every other platform. `transform()` already handles this correctly as-is (`customer.get("dni")` passes through whatever value exists), so no fix needed — just worth knowing this distinction exists in the source.

## `CHAIN_FILTER`/`DEST_PREFIX` made configurable (2026-09-02)

Both were still hardcoded (`"Grido"`, `"grido"`) despite everything else being env-var driven. Made configurable via `CHAIN_FILTER`/`DEST_PREFIX` env vars (defaults unchanged, so existing deployed behavior doesn't change unless explicitly overridden) — the same codebase can now serve a different platform (`peya/`, etc.) via a separate Lambda deployment with different env vars, without a source edit. `transform()`/field allow-list itself is not validated against any platform other than Grido's confirmed request, so this is a config-level readiness change, not a claim it's ready for another platform's data shape.

## Field allow-list narrowed (2026-09-02) — 4 fields removed

User provided an updated version of Grido's field request, differing from the original only by the absence of four `order.*` fields between `pickupOnShop` and `customer`: **`pickupDateOnShop`, `preOrder`, `observations`, `ownDelivery`** — everything else (including all of `details[]`) unchanged. Confirmed via direct diff against the original example before touching code.

**`transform()` updated** to drop all four. This also makes the earlier `observations`-blanking logic moot — the field isn't sent at all now, so there's no REDACT-value question left for it (previously sent as `""`, now absent entirely). `test_local.py`'s expected schema updated to match, plus an explicit check that these four keys never reappear (regression guard, not just an updated allow-list). Re-ran clean: 0 schema errors across all 144,964 real Grido records.

**Redeployed and confirmed** — `zip -f function.zip handler.py` + `update-function-code`, output saved to `data/lambda_update_code_output_2.json`. Re-check confirms `State: Active`, `LastUpdateStatus: Successful`, `CodeSha256: 5tj7T+h2M7DYOaMBojDfunjbW0JikT2WwRONwmLtywI=` (`data/lambda_update_code_confirm.json`). Narrowed field schema and configurable `CHAIN_FILTER`/`DEST_PREFIX` are now live on the deployed Lambda.

**Not yet validated against this deployed version specifically:** the local `test_local.py` run (144,964 records, 0 errors) tested the code *before* deployment, and the earlier real-write validation (`data/first_write_validation/`) was against the *previous* schema (still including the four now-removed fields). Should re-run a real write + validation against this deployed version to confirm the narrowed schema behaves correctly end-to-end, not just locally.

## First real production invoke — historical backfill attempt, 2026-05-01 onward (2026-09-02)

**Goal:** backfill the deployed Lambda's output as far back as 2026-05-01, using the rolling `DAYSBEFORE` window rather than the unused `START_DATE`/`END_DATE` path (simpler — no explicit-range env vars were set on the deployed function). `DAYSBEFORE` set to 124 via `update-function-configuration` (covers today-1 through today-124, i.e. 2026-09-01 down to 2026-05-01), confirmed `LastUpdateStatus: Successful` before invoking (`data/lambda_update_config_daysbefore_124_confirm.json`).

**Two overlapping invocations occurred, not one.** `aws lambda invoke` hit a client-side read timeout (default ~60s socket read, well under this run's actual ~3.6–4.3 min duration against `Timeout=900`) — most likely the AWS CLI's default retry behavior re-sent the invoke while the first was still running server-side. CloudWatch confirms two distinct RequestIds/log streams overlapping in time (one starting ~14:31:19 UTC finishing 14:34:55, the other starting ~14:32:20 UTC finishing 14:36:41) — see `data/lambda_invoke_daysbefore_124_log_tail.txt`. Both reported identical `{'written': 16, 'no-grido-records': 108}`. Confirmed via a direct `aws s3 ls` of the destination (`data/s3_grido_backfill_listing.txt`) that this produced no corruption or duplication — exactly 16 objects exist, since `put_object` overwrites by deterministic day-key and both runs transformed the same unchanged source data. **Worth avoiding on future manual invokes of this function**, not because it broke anything this time: raise `--cli-read-timeout` (e.g. to match or exceed `Timeout=900`) or use `--invocation-type Event` for a long backfill invoke, rather than relying on luck that a concurrent duplicate stays harmless.

**INVALIDATED (2026-09-02) — everything below through "MongoDB retention checked" was chasing a false signal. The real cause is a field-name case-sensitivity bug in `handler.py` itself, confirmed directly against real downloaded files. Full corrected finding follows after this block; kept the invalidated reasoning summarized rather than deleted, since the mistake (and how it was caught) is itself useful record.**

The backfill logged `0/N registros Grido` for 108 of 124 days. `scripts_chain_field_check.py` (written to check this) also reported `records with extradata key: 0` for `2026-05-01` and `2026-08-01`. Both were reading for a lowercase `extradata` key. A `orderMapper()` code-review then reasoned the field was added to the mapper sometime in August 2026 (plausible-looking, but never actually verified against a pre-August file's real content). A MongoDB retention check (real, and still valid on its own — see below) was chased as a way to determine whether the "missing" field could ever be recovered, concluding a 2026-08-17 hard floor.

**What actually happened, confirmed 2026-09-02 by direct inspection of the real downloaded files:** `2026-05-01-3.json` and `2026-08-01-3.json` contain `extraData` — **capital D**, not the lowercase `extradata` both `scripts_chain_field_check.py` and `handler.py` check for. Grepped directly: `"extraData"` appears on 46,959/46,959 records (`2026-05-01`) and 34,178/34,178 (`2026-08-01`) — 100%, not absent. Parsed properly (correct casing): `2026-05-01` has `chain: "Grido"` on **46,917 of 46,959 records (99.9%)**. These files also have `platformId` (camelCase, 46,959/46,959) and zero `platformid` (lowercase) — i.e. they're in the **raw MongoDB document shape** (matching what `orderMapper()` receives as input: `extraData`, `originalId`, `platformId`, and a `tenant` object), not the shape `orderMapper()` produces (`extradata`, `originalid`, `platformid`, no `tenant`) that the 2026-08-28 control file is in.

**Root cause: two different file shapes coexist under the same `news/YYYY/MM/newsYYYYMMDD-3.json` naming convention, and `handler.py` only recognizes one of them.** Files up to some point before 2026-08-17 are the raw Mongo shape; files from ~2026-08-17 onward are the `orderMapper()`-transformed lowercase shape. `handler.py`'s `transform()` and its Grido filter (`record.get("extradata", {}).get("chain")`, plus every `order.get("platformid")`/`order.get("statusid")`/etc. field access) assume the transformed shape unconditionally. Against a raw-shape file, every one of those `.get()` calls silently returns `None` (Python doesn't raise on a missing dict key) — the chain filter never matches, so **every record in a raw-shape file is silently treated as `no-grido-records`, regardless of how much real Grido data it actually contains.** The 46,917 Grido records sitting in `2026-05-01` alone is direct proof this isn't a data-availability limit — it's `grido-redacted-etl` failing to read data that's right there.

**What's still true and unaffected by this correction:** the MongoDB 15-day retention/TTL finding (confirmed 3 independent ways, plus the user's direct policy confirmation) — real, but irrelevant to this specific question now, since the S3 exports (in whichever shape) are the actual source `handler.py` reads, not MongoDB directly.

## Fixed: dual-shape field access, redeployed, full 123-day backfill successful (2026-09-02)

**Fix applied to `handler.py`:** added `get_ci(d, *keys)` — tries each candidate key name in order, used everywhere a field name differs between the two shapes: `order.platformid`/`platformId`, `statusid`/`statusId`, `ordertime`/`orderTime`, `deliverytime`/`deliveryTime`, `pickuponshop`/`pickupOnShop`, `totalamount`/`totalAmount`, `details[].productid`/`productId`, `details[].groupid`/`groupId`, `createdat`/`createdAt`, `updatedat`/`updatedAt`, and the chain filter itself via a new `get_extradata(record)` helper (`extradata`/`extraData`). Fields confirmed identical in both shapes (`order.id`, `customer.id`, `customer.dni`, `details[].count`/`price`/`promo`/`discount`/`description`/`sku`/`canje`, `branchId`, `typeId`, `viewed`) were left untouched.

**Validated locally before deploying** (`data/handler_shape_fix_local_validation.txt`): ran `transform()`/`get_extradata()` directly against the real downloaded files — `2026-05-01` (raw shape) went from 0/46,959 to **46,917/46,959** matched, 0 transform errors; `2026-08-01` (raw shape) went from 0/34,178 to **34,044/34,178** matched, 0 errors; `2026-08-28` (transformed shape, control) stayed at 29,325/29,460, unchanged — confirming the fix didn't regress the already-working path.

**Redeployed** (`zip -f function.zip handler.py` + `update-function-code`, confirmed `LastUpdateStatus: Successful`, new `CodeSha256: 4i4sWom5nzkRcGJD43BsPGao3ZDJdr08gtJ64dhezJc=` — `data/lambda_update_code_shape_fix_confirm.json`). Set `DAYSBEFORE=123` (`data/lambda_update_config_daysbefore_123_confirm.json`) and invoked for real, this time with `--cli-read-timeout 900` to avoid the earlier duplicate-invocation issue (H7) — a single clean invocation this time, confirmed via one `RequestId` in the log (`data/lambda_invoke_daysbefore_123_log_tail.txt`).

**Result: all 123 of 123 requested days written, not 16.** Grido match rate is consistently ~99% of each day's total records across the entire range (2026-05-02 through 2026-09-01) — e.g. `2026-05-02`: 28,392/28,441; `2026-06-21`: 44,483/44,557; `2026-08-30`: matches the earlier-confirmed count. Confirmed final S3 state directly (`data/s3_grido_backfill_listing_after_fix.txt`): exactly 123 objects, `grido/2026/05/news20260502.json` through `grido/2026/09/news20260901.json`, consecutive, no gaps. `Max Memory Used: 986MB` of `4096MB` — no OOM risk materialized (H3-class risk from GITIN-1970 stayed theoretical here too).

**This fully reverses H8's original conclusion.** There was never a 2026-08-17 data floor — Grido data exists at least back to 2026-05-02 (start of this backfill's requested range; whether it goes further isn't tested, since `DAYSBEFORE=123` was the range requested) in a raw MongoDB-shaped export the Lambda simply couldn't read. The actual floor, if one exists, is now unknown again — bounded only by how far back `smartfranbkp/news/` itself goes, not by anything `chain`-related.

**Output validated as genuinely Grido-only (2026-09-02):** downloaded the actual written output `grido/2026/05/news20260501.json` and cross-checked every `order.id` against the source file's `chain`-filtered set. First pass showed 8,678 "not found" — traced to a type mismatch in the check script itself (source `order.id` is `int` for 8,678 records, `str` for 38,281; `transform()`'s output always stringifies it), not a real discrepancy. Normalized and re-checked (`data/output_vs_source_grido_only_check.txt`): **46,917 output records exactly match the source's Grido-filtered count, 0 non-Grido records leaked in (e.g. `Weiss`), 0 duplicates, 0 output records without a matching Grido source record.** Also confirmed `chain` and `tenant.name` are 100% consistent as filter signals (0 disagreements across both `2026-05-01` and `2026-08-01`, 81,137 records) — `extradata.chain == "Grido"` and `order.tenant.name == "grido"` never diverge (`data/chain_vs_tenant_consistency_check.txt`).

**Gap closed and config reverted (2026-09-02):** the `DAYSBEFORE=123` run's requested range was `2026-05-02` through `2026-09-01` (123 days back from the 2026-09-02 invoke date), one day short of the originally intended `2026-05-01` start. Filled via a single-day `START_DATE=2026-05-01`/`END_DATE=2026-05-01` invoke — `46,917/46,959` Grido records written to `grido/2026/05/news20260501.json`, matching the earlier local-validation count exactly. **Full backfilled range: 2026-05-01 through 2026-09-01, 124 consecutive days, no gaps.** Config then reverted to `DAYSBEFORE=2` (confirmed `LastUpdateStatus: Successful`, `data/lambda_update_config_revert_daysbefore2_confirm.json`) — `START_DATE`/`END_DATE` removed entirely (the update replaces the full `Variables` map, doesn't merge), ready for a future EventBridge schedule's normal rolling window.

**Not yet done:**
1. `scripts_chain_field_check.py` still has the same casing bug if reused as a standalone diagnostic — not fixed, since `handler.py`'s own fix made it moot for this investigation.
2. Whether Grido data (in the raw shape) extends earlier than 2026-05-01 is untested — the backfilled range now matches what was actually requested, but nothing further back has been checked.
3. Whether the pre-existing "16 days" data (2026-08-17 to 2026-09-01, transformed shape) was overwritten cleanly by the `DAYSBEFORE=123` run with no discrepancy — not explicitly diff-checked, though same-day counts in the new log match what was already known for those dates (e.g. `2026-08-30`: 54,349 total in both runs).
4. EventBridge schedule still not created — the Lambda remains manual-invoke-only.

## Normal rolling-window invoke confirmed working (2026-09-03)

First real invoke since reverting to `DAYSBEFORE=2` and after all the H8/shape-bug fixes — a sanity check that ongoing normal operation (not just the historical backfill) still works cleanly. Processed `2026-09-01` (18,836/18,897 Grido) and `2026-09-02` (22,668/22,735 Grido), both written successfully, 5.2s total duration, 458MB/4096MB memory. No errors. Confirms the fix holds for the Lambda's actual day-to-day role, not just the one-off backfill run.

## EventBridge daily schedule created and confirmed (2026-09-03)

`grido-redacted-etl-daily`, `cron(0 4 * * ? *)` (04:00 UTC) — a ~29-minute buffer after `mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO`'s `03:30 UTC` cron finishes (~03:31:46 UTC observed). Permission granted to `events.amazonaws.com`, scoped via `ArnLike` to this rule's ARN specifically; target wired with `FailedEntryCount: 0`. Confirmed via `describe-rule`/`list-targets-by-rule`: `State: ENABLED`, correctly targeting `grido-redacted-etl` (`data/eventbridge_describe_rule.json`).

**GITIN-1874 is now fully operational and automated:** deployed, dual-shape bug fixed, historical backfill complete and validated as genuinely Grido-only, normal rolling-window operation confirmed, daily schedule live, and failure alerting (GITIN-1979) wired to both email and Google Chat (Operations + SmartPedidos).

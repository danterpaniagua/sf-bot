# Investigation — 20260902_export-s3-update

**Jira:** [GITIN-1983](https://smartit-ar.atlassian.net/browse/GITIN-1983) ("[SP] Actualización de Export -> S3"), subtask of GITIN-1872 (parent, "[SP] Envío de datos de SP a Grido"), sibling of GITIN-1970, GITIN-1873, GITIN-1874, GITIN-1880.

**Status: record-keeping ticket — the underlying investigation and fix work is already done and documented in `20260831_lambda-s3-export-utc3/`. This folder formally records that work under its own ticket, not a new investigation.**

## Scope (as given by user, 2026-09-02, corrected from an earlier misreading)

Record the fields that were **not** being sent to S3 by `mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO` (`orderMapper()` silently dropping them), and the Lambda update made to fix that. **Not** about the separate permanent data-loss gap (that's GITIN-1970's H6, out of scope here).

## Source of record: GITIN-1970's investigation (`20260831_lambda-s3-export-utc3/`)

**The issue — fields never reaching S3:** `orderMapper()` (in what's actually `app.js`, formerly misnamed `handler.js` — see the file-naming correction in the source investigation) builds the exported record from the raw MongoDB document, but three fields were never copied into its output at all, despite being present and 100% populated on the source documents (confirmed via a direct MongoDB query, 5000/5000 sampled):

- `order.originalId` → dropped entirely (not in the mapper's output).
- `order.displayId` → dropped entirely.
- `order.details[].canje` → dropped entirely from each line item.

Found while cross-checking `orderMapper()`'s actual output against the field allow-list GITIN-1874 needed (which surfaced the gap), not from any error or crash — the export ran successfully every day, it just silently omitted these three fields the whole time. Also found in the same pass: `region` in `AWS.config.update()` was hardcoded to the literal string `'us-east-1'` instead of reading `process.env.REGION` (declared but unused) — functionally correct but not actually configurable.

**Confirmed real (not just theoretical) via a live production export (2026-09-02):** downloaded `news20260901.json`/`news20260901-3.json` before the fix deployed — `originalid`/`displayid` missing from 100% of 18,769 (UTC0) and 19,240 (`-3`) records.

**The Lambda update:** `orderMapper()` in `app.js` was changed to add the three missing fields:
```javascript
parsedOrder.order.originalid = order.order.originalId;
parsedOrder.order.displayid = order.order.displayId;
// ...inside the details map:
canje: detail.canje,
```
and `AWS.config.update()`'s `region` literal was replaced with the `region` variable (already reading `process.env.REGION`, just never wired up).

**Confirmed deployed and validated (2026-09-02):** downloaded a fresh export after redeploy (`news20260901-3.json`, 19,101 records) — `originalid`/`displayid` present on 100% of records (0 missing). `canje` correctly present/absent matching its natural population rate in the source data (absent = `undefined`, dropped by `JSON.stringify`, not a bug — the field itself only exists on a subset of line items in Mongo to begin with).

This bundled two other, unrelated changes made in the same deploy — mentioned here only for completeness, not this ticket's subject: the day-boundary/backwards-compatibility work (GITIN-1970's actual scope) and the permanent data-gap finding (also GITIN-1970, tracked separately, not this ticket).

## Open questions / next steps

None outstanding for this ticket's actual scope — the missing-fields issue is found, fixed, deployed, and validated against real production data. This folder exists purely to give it its own Jira-traceable record (GITIN-1983).

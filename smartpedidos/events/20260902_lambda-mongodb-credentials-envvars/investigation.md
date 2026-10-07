# Investigation — 20260902_lambda-mongodb-credentials-envvars

**Jira:** [GITIN-1973](https://smartit-ar.atlassian.net/browse/GITIN-1973), subtask of GITIN-1872 (parent, "[SP] Envío de datos de SP a Grido").

**Status: record-keeping ticket for a remediation reported as already complete.** No independent evidence of the original plaintext version exists in this repo — recorded as reported by the user, not verified via a diff or old source snapshot.

## Scope (as given by user, 2026-09-02)

Record that `mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO`'s MongoDB connection string was originally hardcoded in plaintext in the Lambda source, and was migrated to environment variables. Specifically about this Lambda — **not** the separate `concentrador-service`/`platforms-service` hardcoded-credentials investigation (`20260720_credenciales-mongodb-hardcodeadas/`, tracked separately, confirmed this session as **not** related to GITIN-1973).

## Current state (confirmed directly in this session)

Every version of the Lambda's source seen throughout GITIN-1970's investigation (`20260831_lambda-s3-export-utc3/app.js`, formerly misnamed `handler.js`) already reads MongoDB credentials from environment variables:

```javascript
const user = process.env.MONGO_USER;
const passwd = process.env.MONGO_PASSWD;
const host = process.env.HOST;
const database = process.env.DATABASE;
const connString = `mongodb+srv://${user}:${passwd}@${host}/${database}`;
```

(Note: a separate, unrelated bug in this same line was found and fixed under GITIN-1970 — the interpolation `${}` was missing, so it connected to the literal strings `"MONGO_USER"`/`"HOST"` etc. instead of the real env var values. That's a different issue from this ticket's subject — a broken-interpolation bug in already-migrated code, not a hardcoded plaintext credential. Both bugs happen to involve the same line of code but are logically distinct: this ticket is about the migration *away from* a hardcoded literal secret value having happened at some point in the past; GITIN-1970's bug was in the *env-var-based* code that came after that migration.)

**Not established in this session:** when the plaintext-to-env-var migration happened, who did it, or what the original hardcoded value looked like — no source snapshot from before the migration was available to review.

## Open questions / next steps

1. If a record of the original plaintext version is needed (e.g. for a security audit trail), it would need to come from git history or deployment history outside what's available in this repo — not investigated here.
2. Confirm whether any other credentials in this same Lambda (bucket name, region) have a similar history — not asked about, not investigated.

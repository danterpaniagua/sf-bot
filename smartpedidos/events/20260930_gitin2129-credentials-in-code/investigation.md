# Investigation — 20260930_gitin2129-credentials-in-code

**Jira:** [GITIN-2129](https://smartit-ar.atlassian.net/browse/GITIN-2129) "[SP] Credenciales en Codigo" — credentials hardcoded in `config/env/*.js` files (SmartPedidos). Subtasks: [GITIN-2130](https://smartit-ar.atlassian.net/browse/GITIN-2130) "[SP] Credenciales Platform", [GITIN-2131](https://smartit-ar.atlassian.net/browse/GITIN-2131) "[SP] Credenciales Concentrador" (both Backlog, 2026-09-30).

**Ticket history:** this folder was created 2026-09-30 as `..._gitin1632-credentials-in-env-files`; GITIN-1632 was discarded by the user and migrated to GITIN-2129, folder renamed to match. Per user, this work can be tied to [GITIN-1715](https://smartit-ar.atlassian.net/browse/GITIN-1715) (parent [GITIN-1606](https://smartit-ar.atlassian.net/browse/GITIN-1606)), "AWS Keyvault" — nature of that link not yet read/verified.

**Update 2026-10-05:** the concentrador's `staging.js` AWS key (IAM user `userSQS`) is committed on `origin/develop`/`origin/ope` since 2019 and the same key is in `development.js`, `testing.js` and `production.js`; its permissions (`sqs:*` on `*`, S3 read/write on all buckets, broad read) and use are in the section "Concentrador `staging.js`…" below, and the key value was shown once in a session terminal output (not recorded in any file). Per-developer, non-prod credentials are tracked in [GITIN-2169](https://smartit-ar.atlassian.net/browse/GITIN-2169) (`../20261005_gitin2169-credentials-per-dev/`). Rotation scope depends on the CloudTrail check of who else uses the key (open item 0).

**Status (2026-09-30, end of day):** in progress — scope fixed to **local** environment variables (deployed environments / AWS Key Vault stay with GITIN-1715); field-name inventory of `config/env/*.js` done for both services (values redacted); `ops.md` written with the per-repo treatment history table. Nothing implemented yet; still unverified which literals are real secrets and which are committed on `develop`; subtasks GITIN-2130 (Platform) and GITIN-2131 (Concentrador) in Backlog.

## Scope (from user, 2026-09-30)

Action plan for credential best practices, ticket title "[SP] Plan de accion para buenas praticas de credenciales":
- Local development: credentials via environment variables (git-ignored `.env`, `.env.example` without values).
- Deployed environments: secrets in a Key Vault, injected at runtime. User clarified 2026-09-30: **AWS Key Vault** (GITIN-1715). "Key Vault" is an Azure product name; the exact AWS service (Secrets Manager vs. SSM Parameter Store — `@aws-sdk/client-ssm` is already a platforms-service dependency) is **still to confirm** against GITIN-1715's content.

**Scope narrowed (user, 2026-09-30):** this ticket = **local** only — credentials would move into env vars (today they are not read from env vars). Deployed-environment storage (AWS Key Vault) stays with GITIN-1715. `ops.md` rescoped accordingly (interpretation of "Scope: Local; credentials would be, not currently in env vars" — correct me if it meant something else). Side effect noted in `ops.md` action 4: removing literals breaks startup in deployed envs unless GITIN-1715 supplies the values first.

## Confirmed facts

- Both services keep per-environment config in `api/src/config/env/{default,development,performance,testing,staging,production,index}.js` (platforms-service branch `ope`, concentrador-service branch `develop`, checked 2026-09-30).
- Credential-like fields (`secret`, `password`, `client_secret`, `AWS_SECRET`, `MERCADOPAGO_DELIVERY_TOKEN`, `accessKeyId`/`secretAccessKey`, `tokenEncryption.key/iv`) exist as quoted string literals in the env files of both services, across environments including `production.js`. Field-name inventory with values redacted: `data/env_credential_fields_redacted_20260930.txt` (grep pattern matches quoted literals of 6+ chars; **not verified** which are live secrets vs. placeholders/URLs).
- `tokenEncryption.key/iv` in platforms-service already use `process.env.TOKEN_ENCRYPTION_KEY || '<literal>'` — env-var pattern exists but with a hardcoded fallback.
- platforms-service `staging.js` `credentials.accessKeyId/secretAccessKey` (lines 61-62) is an **uncommitted local diff** on `ope` (not in `origin/ope`), surfaced by Trivy in the local image (see `../20260928_gitin2116-platform-npm-update/`, 2026-09-29/30). Not confirmed for any other file whether the literals are committed — needs `git log`/`git show origin/<branch>` per file.

## SendGrid API key literals in the concentrador (found 2026-09-30 while checking SendGrid usage for GITIN-2116)

In `concentrador-service` (clone on branch `develop`, `git status` clean for `src/config/env/`), a literal `SENDGRID_API_KEY` string beginning `SG.` is present in **`development.js`, `testing.js`, `staging.js` and `production.js`**, and `production.js` additionally carries a **commented-out second `SG.` key**. As the files are unmodified relative to `develop`, these literals are committed on `develop` (confirms the "which are committed" open question for this one credential in that service; real vs. rotated/revoked was not checked). The values appeared once in a terminal grep output and are **not recorded in any file**. Recommend rotating/revoking per GITIN-2129's treatment (action 6) and moving to env vars; the keys' presence in several files and a commented-out one suggests earlier rotations, not verified.

## Concentrador `staging.js`: committed AWS credentials and what they can do (2026-10-05)

Found while running the concentrador's `serve:stg` for GITIN-2117 (`../20261005_gitin2117-concentrador-npm-update/`). Values were never read into this record; the script loads them into shell variables only and masks key IDs in its output.

**Committed on the production branch.** `api/src/config/env/staging.js` of `concentrador-service` is tracked, not git-ignored, has no local diff, and exists on `HEAD` (`ope`, tree identical to `develop`), `origin/develop` and `origin/ope`; first commit adding the file: `022caccc` (2019-10-28). It holds **two `AWS_ID`/`AWS_SECRET` literal pairs** (lines 52–53 and 59–60, under two `CREDENTIALS` blocks, each beside a `REGION` key) and `grant_type` literals at lines 13 and 84 (not examined). This differs from the platform's `staging.js`, whose AWS credentials were a local uncommitted diff only.

**Evidence** — `scripts_staging_credential_permissions.sh <admin-profile>`; output `data/staging_cred1_*` (lines 52/53) and `data/staging_cred2_*` (lines 59/60), masked:
- **Principal (STS):** both pairs authenticate as the same IAM user, `userSQS`, account `382381053403` (`staging_cred{1,2}_sts_identity.json`; same account noted for prod and test in the project memory, isolation by region/naming).
- **Keys on that user:** two — one **Active**, created 2020-07-29, and one **Inactive**, created 2020-09-29 (`..._iam_access_keys.json`). Both pairs authenticated, and an inactive key cannot authenticate, so both blocks most likely hold the same (Active) key; the masked IDs were not compared directly. The Active key is ~6 years old.
- **Permissions:** three AWS-managed policies attached, no inline policies, no groups (`..._iam_attached_user_policies.json`, `..._iam_inline_user_policies.json`, `..._iam_groups.json`):
  - `AmazonSQSFullAccess`: `sqs:*` on `Resource: *` — every SQS queue in the account, any region (read/send/delete messages, purge or delete queues, change attributes; includes production queues and DLQs if they live in this account).
  - `AWSLambdaExecute`: `logs:*` on all log resources and `s3:GetObject` + `s3:PutObject` on `arn:aws:s3:::*` (objects in every bucket of the account).
  - `AWSLambdaReadOnlyAccess`: read-only listing/describe/get across Lambda and related services (action prefixes seen: dynamodb, iam, iot, cloudformation, logs, sns, ec2, cloudwatch, s3, lambda, kinesis, events, kms, sqs, …; full document in `..._policy_AWSLambdaReadOnlyAccess.json`).
  - Not checked: permission boundary, account-level SCPs, resource-based policies on queues/buckets (any of which could narrow this).
- **Actual use (IAM service last accessed, `..._service_last_accessed.json`):** `sqs` 2026-10-05 14:36Z (and 14:36:44Z in the second run, i.e. continuous use); `s3` 2026-10-05 14:27Z; `logs`/`cloudwatch`/`ec2` only once, 2022-11-22; every other service never. The key's own last-used record: `sqs`, `us-east-1`, 2026-10-05 14:38–14:39Z. The user also has a console-password history (`PasswordLastUsed` 2022-11-22 in `..._iam_get_user.json`; whether a login profile still exists was **not checked**), which matches the 2022-11-22 console-style activity.
- **Attribution not established:** the SQS activity coincides with the `serve:stg` container started during the 2117 testing, but the same key may also be used by other staging/production services (the S3 call at 14:27Z precedes that container's start at ~14:34Z), so rotating it without an inventory of its users would likely break them.

**Same key in other env files (checked 2026-10-05, concentrador working tree on `ope`):** a `grep` of `AWS_ID`/`AWS_SECRET` showed identical key-ID and secret literals in `development.js` (2 blocks), `testing.js` (2 blocks) and `production.js` (blocks at lines 52–54 and 59 onward), and the ID's visible suffix matches the Active `userSQS` key. So this one key is not environment-scoped: the production config carries it too. (Whether these files are committed on `origin/develop` was verified only for `staging.js`.) **The key and secret values were printed once in this session's terminal output by an unredacted grep and are not recorded in any file**; the exposure in the session transcript is a further reason to treat the key as compromised.
**Queue layout (non-secret, from the same files):** all queues are in the same account `382381053403`; development/testing/staging use `us-east-2` (`DEV_*`, `TST_*`, `STG_*` `PlatformMessages`/`BranchMessage(s)`; `testing.js` and `staging.js` point to the **same** `DeadLetter.fifo` and `MainDeadLetter.fifo`), performance `us-west-2` (`PER_*`), production `us-east-1` (`PRD_*`, plus `DeadLetter.fifo`/`MainDeadLetter.fifo`). With `sqs:*` on `*` the `userSQS` key can reach every one of them regardless of which env file it came from.

**Reading (hedged):** the effective blast radius of this committed staging credential is far wider than a staging queue consumer needs — all SQS queues and all S3 objects of the account plus broad read access — and it has been in git since 2019. Not verified: whether the same `userSQS` key appears in the other env files (`production.js` etc.) or in the platform's, and who else uses it.

## Open questions / next steps

0. Next evidence for the credential above: which principals/hosts use that access key (CloudTrail `LookupEvents` by `AccessKeyId`, 90-day window), whether `userSQS` still has a login profile, and whether the same key is in the other env files (compare by hash, not by printing). Decide rotation scope only after that.
1. Read GITIN-1715 / GITIN-1606 (user to paste) to pin the exact AWS secret store and reuse any existing decision.
2. Per file: which literals are committed on the production branch (`develop` in both repos) vs. local-only; which are real secrets.
3. Inventory of every credential per service/environment and where it is read in code.
4. Whether rotation is in scope (not included in the draft).
5. Whether the pre-existing `events/10-07-2026_credenciales-expuestas-logs/` is related (unread — only its name/file list seen).
6. `ops.md` written 2026-09-30 at the user's explicit request (before convergence), as a per-repo credential-treatment history table — scope and per-repo status rows live there; keep investigation findings here, not in `ops.md`.

## Related

- `../20261005_gitin2171-lambda-monitoring/` — found 2026-10-05 that the three existing Graylog AWS inputs (and a fourth created for GITIN-2171, by the user's decision) all use **one static access key of a personal IAM user with AdministratorAccess/IAMFullAccess** stored in the input configuration; details in that folder's "Finding: the existing Graylog AWS inputs run on one personal administrator key" (user name masked in its evidence file). Same class of problem as this ticket (long-lived broad credentials outside a secrets store); a separate ticket for replacing it with scoped credentials is the user's decision.
- `../20260928_gitin2116-platform-npm-update/` — Trivy finding on `staging.js`; GITIN-2116 scoped this out to GITIN-2129 (reference corrected from the discarded GITIN-1632).

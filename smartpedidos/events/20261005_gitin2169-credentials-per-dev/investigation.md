# Investigation: GITIN-2169 — [SP] Credenciales por DEV

**Jira:** [GITIN-2169](https://smartit-ar.atlassian.net/browse/GITIN-2169) "[SP] Credenciales por DEV".
**Parent (user, 2026-10-05):** [GITIN-1606](https://smartit-ar.atlassian.net/browse/GITIN-1606). The 2129 investigation records GITIN-1715 "AWS Keyvault" as also under GITIN-1606 (per the user, 2026-09-30), so 1715 and 2169 would be siblings; GITIN-1606's own content has not been read.
**Scope (user, 2026-10-05):** per-developer AWS credentials; developers must **not** have production access.
**Status:** in progress (opened 2026-10-05). Nothing designed or applied yet.

## Related (not merged into this scope)

- `../20261005_gitin2171-lambda-monitoring/` — shows a second case of a shared, broad credential relevant to "no prod access": the Graylog AWS inputs use one personal administrator key (not per-developer, not scoped); evidence and details are in that folder's investigation.

- [GITIN-2129](https://smartit-ar.atlassian.net/browse/GITIN-2129) (+ GITIN-2130 Platform, GITIN-2131 Concentrador): credentials hardcoded in `api/src/config/env/*.js`; local scope = env vars. Evidence for this ticket comes from `../20260930_gitin2129-credentials-in-code/` (section "Concentrador `staging.js`: committed AWS credentials…").
- GITIN-1715 "AWS Keyvault" (sibling under GITIN-1606): deployed-environment secret storage (nature of the link to 2129 not read/verified; same status here). Paste GITIN-1606 / GITIN-1715 to confirm whether per-developer credentials or the key storage decision are already defined there.

## Confirmed facts (2026-10-05; sources in the 2129 folder's `data/staging_cred*` and the code reads below)

- **Today there is one shared credential, not per-developer:** IAM user `userSQS` (account `382381053403`), one Active access key (created 2020-07-29) plus one Inactive key (2020-09-29). The same key literal is in the concentrador's `development.js`, `testing.js`, `staging.js` and `production.js` (committed on the production branch for `staging.js`; the others not checked for commit state).
- **That user's permissions are not env-scoped:** `AmazonSQSFullAccess` (`sqs:*` on `*`), `AWSLambdaExecute` (`logs:*`, `s3:GetObject`/`s3:PutObject` on `arn:aws:s3:::*`), `AWSLambdaReadOnlyAccess`; no inline policies, no groups; permission boundary / SCPs / resource policies not checked. So any holder of the key (any developer with the repo) can reach the production queues.
- **One AWS account for all environments** (also noted in the project memory): queues of every environment are under `382381053403`, separated only by region and name:

  | Env | Region | Queue names (platform/branch messages; DLQs) |
  |---|---|---|
  | development | `us-east-2` | `##_DEV_PlatformMessages.fifo`, `DEV_BranchMessage.fifo` |
  | testing | `us-east-2` | `##_TST_PlatformMessages.fifo`, `TST_BranchMessages.fifo`, `DeadLetter.fifo`, `MainDeadLetter.fifo` |
  | staging | `us-east-2` | `##_STG_PlatformMessages.fifo`, `STG_BranchMessages.fifo`, `DeadLetter.fifo`, `MainDeadLetter.fifo` (same two DLQ URLs as testing) |
  | performance | `us-west-2` | `##_PER_PlatformMessages.fifo`, `PER_BranchMessages.fifo` |
  | production | `us-east-1` | `##_PRD_PlatformMessages.fifo`, `PRD_BranchMessages.fifo`, `DeadLetter.fifo`, `MainDeadLetter.fifo` |

  (`##_` is replaced by the branch id at runtime.) So production is the only environment in `us-east-1` for SQS, and also the only one where the DLQ names do not collide with testing/staging.
- **Starting the app is not read-only:** `src/index.js:18` runs `Aws.deadLetterSave()` at startup in every environment; in `src/provider/aws.js` it receives from the env's `DeadLetter`/`MainDeadLetter` queues and calls `deleteMessage`. Per-dev credentials must therefore be scoped to queues a developer may consume/delete from, not just "read".

## AWS API calls the code makes (what a least-privilege dev policy would need) — read from source 2026-10-05

| Service | concentrador (`ope` @ `f387973b`, tree == `develop`) | platform (`develop` @ `ded57a5`) |
|---|---|---|
| SQS | `ReceiveMessage` (6 call sites), `DeleteMessage`, `CreateQueue`, `DeleteQueue` | `SendMessage` (2), `GetQueueAttributes` |
| SSM | `GetParameters` (`provider/aws.js:14`, parameter names not yet inventoried) | `GetParameters` |
| S3 | no S3 SDK client or command found in `api/src`; `s3` appears in env config and in `controllers/activeSoftware.js` / `routes/branches.js` (use not examined). `staging.js` nevertheless carries an `S3` block with `REGION: us-east-1` and credentials. | not examined |

Caveats: grep for `new *Command(` / `new *Client(` only; dynamic or SDK-v2 (`aws-sdk`) usage not found but not ruled out; other repos (backOffice, lambdas) not examined.

## Constraints / design questions (nothing decided)

- **Mechanism per developer:** individual IAM users with their own access keys vs. an assumable role (e.g. via IAM Identity Center / `sts:AssumeRole` with short-lived credentials). Not yet known what the account has (Identity Center, existing per-dev IAM users, `dpaniagua.smartfran` admin profile exists).
- **"No prod access" enforcement options to evaluate:** (a) allow only `arn:aws:sqs:us-east-2:382381053403:*` (excludes the `us-east-1` production queues, but also `us-west-2` performance, and relies on production staying out of `us-east-2`); (b) name-based resource ARNs (`*DEV_*`, `*TST_*`, `*STG_*`) plus an explicit `Deny` on `*PRD_*` and on the production DLQs; (c) a permission boundary or SCP as a backstop. Names `DeadLetter.fifo`/`MainDeadLetter.fifo` collide between testing, staging and production, so region (or a rename) is the only discriminator for them.
- **Which environments devs should reach:** development only, or testing/staging too (testing and staging share the same DLQs).
- **SSM:** which parameter names/paths the services read per environment, and whether production parameters share a path prefix with the others (needed to scope `ssm:GetParameters`).
- **Where per-dev credentials live locally:** ties to GITIN-2129's local scope (env vars / git-ignored `.env`, or an AWS CLI profile) — the code today builds clients from literals in the env files, not from the default credential chain, so removing literals changes how each service obtains credentials.
- **Retiring the shared key:** rotation/removal depends on knowing who else uses it (CloudTrail by access key, not yet run — see the 2129 investigation, open item 0). Per-dev credentials alone do not remove the exposure while `userSQS`'s Active key remains in git history and in every env file.

## Open questions / next steps

1. Confirm with the user: number of developers, whether IAM Identity Center is available, and which environments devs should access (development only vs. also testing/staging).
2. Inventory SSM parameter names and the S3 usage per service (needed for the policy).
3. Draft the dev policy (SQS actions above, scoped by region/name, explicit deny on production) and test it with the IAM policy simulator before assigning it.
4. Decide sequencing with GITIN-2129 (env-var refactor) and the `userSQS` key retirement.

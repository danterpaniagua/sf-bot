# Investigation — 20260730_secrets-manager-implementation

**Status:** in progress — Stage 1 scoped and designed, implementation not started

## Purpose

Real implementation ticket for moving `smartpedidos` secrets out of versioned `production.js` config and into AWS Secrets Manager, following the PM's request after the ARQ-009 PoC closure presentation ([20260728_recursos-aws-poc-arq009_cierre.md](../20260728_recursos-aws-poc-arq009/20260728_recursos-aws-poc-arq009_cierre.md)) — the PoC already validated Secrets Manager end-to-end for one secret (`token.secret`, read by the Lambda authorizer). This ticket exists separately from [20260720_credenciales-mongodb-hardcodeadas](../20260720_credenciales-mongodb-hardcodeadas/20260720_credenciales-mongodb-hardcodeadas.md) (SEC-114) because that ticket is the audit/finding record for the hardcoded-credential problem — this one tracks the actual rollout, same split pattern as `20260728_recursos-aws-poc-arq009` vs `20260720_ocultar-account-id-sqs-urls`.

## Confirmed facts

**Credential inventory (source: `20260720_credenciales-mongodb-hardcodeadas` investigation), relevant to scoping this rollout:**
- `token.secret` — byte-identical in both services' `production.js` (`'ts$s38*jsjmjnT1'`), pure hardcoded literal, **zero env-var indirection today**. This is the only secret already validated against Secrets Manager (in the PoC, in `us-west-2`, PoC-scoped).
- `aws_id`/`aws_secret` are **DB-stored** (`branches.credentials`) but not truly per-branch — mirrored 1:1 from the static `config.AWS.SQS.CREDENTIALS` literal at `saveOne()` (`concentrador-service/controllers/branch.js:4419-4420`), read back at `login()` (`branch.js:4921-4922`). Out of scope here — tracked under SEC-006 / ARQ-003 (removing them from the login payload entirely, not migrating them to a vault).
- Everything else in scope for a full sweep (`peyaParams`, `SENDGRID_API_KEY`, `smlParams`/`cloudParams`, `MERCADOPAGO_DELIVERY_TOKEN`, Mongo `database.username/password`, `tokenEncryption` fallback, `tokenStatic`) lives only in `production.js`, never touches DB.

**Deployment target confirmed** (`smartpedidos/docs/infrastructure.md`): ECS Fargate, cluster `smartfran-pedidos-production` (`us-east-1`), task definition `concentrador-service-production-task:313` (+ platforms-service equivalent, not yet pulled). Task definition today has **no `secrets` block** — only plain env vars (`SERVICE_NAME`, `NODE_ENV`). Documented task role is `smartfran-task-role` (used for SQS access) — the **execution role** (the one Secrets Manager injection actually needs) is undocumented. This is the confirmed blocker, tracked as SEC-117 in the source ticket.

**Path decision — ECS task-definition `secrets` injection vs. runtime SDK fetch:**

| | Path A — task-definition injection (chosen) | Path B — runtime SDK fetch (mirrors PoC Lambda) |
|---|---|---|
| New npm dependency | None | `@aws-sdk/client-secrets-manager` — confirmed **not installed** in either `package.json` (only `@aws-sdk/client-sqs`, `@aws-sdk/client-ssm` present) |
| Code change | `production.js`: `token.secret: process.env.TOKEN_SECRET` — same pattern already used for `baseUrl`/`tokenEncryption` in the same file | Replace literal with `GetSecretValueCommand` call + caching layer (none exists today) |
| IAM target | ECS **execution role** (undocumented — SEC-117) | `smartfran-task-role` (documented, used for SQS today) |
| Runtime cost | None — AWS resolves once at task start, delivered as env var | One API call per cold start / cache expiry |

Path A chosen: zero new dependencies, zero new app-level attack surface, matches the exact integration point the source ticket's remediation table already flagged ("Bloque `secrets` de la task definition de ECS").

**Dead code noted, not reused:** `provider/aws.js` → `retriveKey()` (both repos) already wraps `@aws-sdk/client-ssm` `GetParametersCommand` — no call sites found, targets Parameter Store not Secrets Manager. Doesn't reduce Path A's work (different AWS service), just shows a fetch-and-cache pattern was scaffolded once and abandoned.

**Repo constraint:** `smartpedidos/repos/` clones are read-only lookups only, per project CLAUDE.md — actual `production.js` / task-definition changes must be made in `smartfran/sp-logs` (or wherever the real working copies/IaC live), not from this monorepo.

## Open questions / next steps

- [ ] **Blocking — SEC-117:** confirm the real ECS execution role for both task definitions (`concentrador-service-production-task`, platforms-service equivalent) and its current IAM policy.
- [ ] Create the production `token.secret` value as a new Secrets Manager secret in `us-east-1` (deliberately not `us-west-2` — that was the PoC's isolation boundary, and that PoC secret still needs teardown, see below).
- [ ] Grant `secretsmanager:GetSecretValue` scoped to that one secret ARN to the execution role once confirmed.
- [ ] Add `secrets` block entry (`TOKEN_SECRET` → ARN) to both task definitions.
- [ ] Code change in `smartfran/sp-logs`: `production.js` in both repos → `process.env.TOKEN_SECRET`, done as one coordinated PR/deploy (not independent — same literal in both services, SEC-118 dependency in the source ticket).
- [ ] Coordinated deploy of both services in the same window — avoid a window where one service signs with the new secret while the other still verifies against the old hardcoded literal.
- [ ] Remove the hardcoded literal from both repos after cutover is confirmed working in production.
- [ ] Not started: applying the same Path A pattern to the rest of the secret inventory (`peyaParams`, `SENDGRID_API_KEY`, `smlParams`/`cloudParams`, `MERCADOPAGO_DELIVERY_TOKEN`, Mongo) — one secret + one task-def entry at a time, each is its own unit of work.
- [ ] Separate, unrelated blocker worth remembering: the PoC's own Secrets Manager secret (`poc-arq009/jwt-secret`, `us-west-2`) still holds the **real** production `token.secret` and hasn't been torn down — see [20260728_recursos-aws-poc-arq009](../20260728_recursos-aws-poc-arq009/20260728_recursos-aws-poc-arq009.md) INFRA-005 (highest priority, `--force-delete-without-recovery`). Not blocking this rollout, but should not be forgotten because of it.

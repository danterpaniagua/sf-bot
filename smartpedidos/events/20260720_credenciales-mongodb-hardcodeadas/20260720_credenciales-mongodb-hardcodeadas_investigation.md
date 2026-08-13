# Investigation — 20260720_credenciales-mongodb-hardcodeadas

**Status:** in progress — Stage 1 (token.secret → Secrets Manager) designed 2026-07-30, not implemented. Broader secret sweep (SEC-101–119) partially remediated, mostly pending.

## Purpose

Hardcoded-credential audit across `concentrador-service`/`platforms-service` `production.js` config files, plus the DB-mirrored AWS credential pattern, plus the remediation path (AWS Secrets Manager, building on the ARQ-009 PoC precedent — see [20260728_recursos-aws-poc-arq009](../20260728_recursos-aws-poc-arq009/20260728_recursos-aws-poc-arq009.md)). Full findings, SEC-ID table, and Stage 1 plan live in the main ticket ([20260720_credenciales-mongodb-hardcodeadas.md](20260720_credenciales-mongodb-hardcodeadas.md)) — this file tracks the working state so a new session doesn't have to re-derive it.

## Confirmed facts

- **`token.secret` is byte-identical** across both services' `production.js` (`'ts$s38*jsjmjnT1'`) — corrected 2026-07-28, originally logged as two separate secrets. Any rotation must be coordinated across both repos simultaneously (SEC-118).
- **`aws_id`/`aws_secret` are DB-stored but not really per-branch**: schema is per-branch (`models/branch.js:165-166`), but `saveOne()` (`concentrador-service/controllers/branch.js:4419-4420`) copies them straight from the static `config.AWS.SQS.CREDENTIALS.AWS_ID/AWS_SECRET` literal at creation time, and `login()` (`branch.js:4921-4922`) reads them back from `savedBranch.credentials` to return in the payload. Same static pair for every branch. Tracked under SEC-006 (ticket `10-07-2026_credenciales-expuestas-logs`) + ARQ-003, not duplicated here.
- **Everything else** (`token.secret`, `peyaParams`, `SENDGRID_API_KEY`, `smlParams`/`cloudParams`, `MERCADOPAGO_DELIVERY_TOKEN`, Mongo `database.username/password`, `tokenEncryption` fallback, `tokenStatic`) lives **only** in `production.js` — never touches the DB.
- **Mongo Atlas production credential confirmed active** (2026-07-22) with `atlasAdmin`/`dbAdminAnyDatabase`/`readWriteAnyDatabase` — cluster-wide, not scoped to the `smartfran` DB. Network Access List open to `0.0.0.0/0`. No rotation process exists anywhere in SmartPedidos (confirmed by user, organizational fact).
- **ECS Fargate deployment confirmed** (`smartpedidos/docs/infrastructure.md`): cluster `smartfran-pedidos-production` (`us-east-1`), task def `concentrador-service-production-task:313`, documented task role `smartfran-task-role`, **no `secrets` block today** — only plain env vars (`SERVICE_NAME`, `NODE_ENV`). The **execution role** (the one that would actually need `secretsmanager:GetSecretValue` for injection) is undocumented — this is SEC-117, and it blocks Stage 1.
- `token.secret` currently has **zero env-var indirection** (pure literal) — unlike `baseUrl`/`tokenEncryption` in the same file, which already follow `process.env.X || fallback`.
- **SEC-114 rollout split into its own ticket** (2026-07-30): [20260730_secrets-manager-implementation](../20260730_secrets-manager-implementation/20260730_secrets-manager-implementation_investigation.md) — Stage 1 (`token.secret` via ECS task-definition `secrets` injection, no new npm dependency) designed there, blocked on SEC-117. Full path comparison and dead-code notes (`provider/aws.js retriveKey()`) live in that ticket now, not duplicated here.

## Open questions / next steps

- [ ] SEC-114 rollout (Secrets Manager Stage 1, SEC-117 blocker, deploy steps) — tracked in [20260730_secrets-manager-implementation](../20260730_secrets-manager-implementation/20260730_secrets-manager-implementation_investigation.md), not here.
- [ ] Unresolved from earlier sessions: `production.js:11-12` purpose unidentified (SEC-104), Mongo NAL restriction (SEC-109), cluster-deletion capability unverified/reported-not-confirmed (SEC-110), `tokenStatic`/Last Mile rotation blocked on a product decision (SEC-113), `platforms-service` cross-auth exposure via shared HMAC key not confirmed (SEC-119).
- [ ] Separate but related: ARQ-009 PoC teardown (INFRA-003, INFRA-005 — highest priority, real prod `token.secret` sitting in a PoC-scoped Secrets Manager secret) still pending in [20260728_recursos-aws-poc-arq009](../20260728_recursos-aws-poc-arq009/20260728_recursos-aws-poc-arq009.md).

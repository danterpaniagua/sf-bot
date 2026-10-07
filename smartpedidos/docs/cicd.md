# SmartPedidos — CI/CD Reference

**Last updated:** 2026-09-11

Canonical source of truth for pipeline mechanics lives in the separate `sf-devops` repo (`~/Documentos/git/sf-devops/jenkins/SF-PEDIDOS/smartpedidos.md`), not in this repo — this file is a local pointer/summary so CI/CD facts don't have to be re-derived from git archaeology every session (confirmed the hard way, 2026-09-11: reading only the app repos' own in-repo `Jenkinsfile`s produced wrong conclusions about both Node version and scanning coverage, since those files are largely vestigial — the real pipelines were migrated out).

## Branch strategy (per `sf-devops/jenkins/SF-PEDIDOS/smartpedidos.md`)

| Branch | Environment |
|---|---|
| `dev` | Development |
| `stg` | Staging / Pre-production |
| `develop` | **Production** |

Flow: `dev` → PR to `stg` → validation → PR to `develop` → production deploy. This matches `smartpedidos/CLAUDE.md`'s existing note that `develop` (not `main`/`master`) is the production reference for this project — now additionally confirmed from the CI/CD side, not just the source-clone convention side.

**Do not read a service's Dockerfile or dependency state from `stg` (or any other branch) and treat it as production** — `stg` genuinely differs from `develop` (confirmed 2026-09-11 for `concentradorService`: `stg` pins `node:14-alpine`, `develop` pins `node:20.20-alpine` — a real, meaningful difference, not a rounding error).

## Pipeline structure (Concentrador / Platform)

Both live in `sf-devops/jenkins/SF-PEDIDOS/jenkinsfiles/develop/`, share the same structure, and load `prAnalyzer`/`changelogAnalyzer`/`deployPosix` from the SF-PEDIDOS shared Groovy library (`@Library('customScripts@main') _`):

```
Validate webhook branch → Clone repo
  → Bugs Report (Claude AI diff analysis, optional toggle)
  → Changelog (git log HTML)
  → NPM install → SonarQube analysis (Docker)
  → Docker build → Quality Gate (SonarQube REST API)
  → Trivy scan (image) → Google Chat notification
```

Neither includes an actual deploy stage — this pipeline folder is CI/quality-gate only; deployment to ECS happens through a separate mechanism not covered by this doc.

`backOffice` has **no** Docker Build stage (no runtime container — see below) and uses `trivy fs` instead of `trivy image`.

## Per-service status (confirmed 2026-09-11 unless noted)

| Service | Runtime | Node version | Trivy | Status |
|---|---|---|---|---|
| `concentradorService` | ECS/Fargate, built from `develop`'s own `api/Dockerfile` | **20.20-alpine** | `trivy image`, CRITICAL/HIGH, active | Confirmed |
| `platformsService` | ECS/Fargate | `node:20.20-alpine` per its repo Dockerfile | `trivy image`, same pipeline structure as concentrador | Dockerfile confirmed; pipeline behavior inferred from the shared template, not independently re-verified this session |
| `backOffice` | **No container** — static build deployed to S3 + CloudFront | N/A (no real Dockerfile pins production; its own root `Jenkinsfile` is broken, unused, has uncommitted merge-conflict markers on `develop`) | `trivy fs --scanners vuln,secret` against `./app` — pipeline built 2026-09-10 (`GITIN-2023`/`GITIN-2024`) | **User-reported working, not yet independently confirmed via a captured passing build log** — see `events/20260910_backoffice-jenkins-sonarqube-onboarding/investigation.md` |

## Existing (unwired) npm compliance tooling

`sf-devops/jenkins/SF-PEDIDOS/scripts/`:

| Script | Purpose | Status |
|---|---|---|
| `npm-pachages.sh` | Reads `package-lock.json`, calls `npm view <pkg> --json` per package, flags anything `deprecated` or unpublished for **>2 years** | **Not wired into the pipeline.** Also currently **cannot run against any of the three SmartPedidos projects** — none has a committed `package-lock.json` (confirmed via `operations/events/20260910_dependency_best_practices_policy/`) |
| `npm-analysis.sh` | Cross-references `npm-pachages.sh`'s output against `trivy_vuln.json`'s vulnerable-package list | Same blocker as above |

These already implement the team's own staleness heuristic for a health check (>2 years unpublished) — any future compliance-check work should extend these rather than invent a separate, disconnected tool.

## Related

- `sf-devops/jenkins/SF-PEDIDOS/smartpedidos.md` — canonical pipeline reference (external repo)
- `smartpedidos/docs/infrastructure.md` — runtime/AWS infrastructure (ECS task defs, ALB, SQS, S3) — deliberately separate from this file, which is pipeline/build-mechanics only
- `smartpedidos/docs/packages_concentrador.md` — a completed real dependency investigation (`GITIN-2000`) using this pipeline's own Trivy output
- `operations/events/20260910_dependency_best_practices_policy/` — cross-project dependency best-practices ticket (`GITIN-2026`) that surfaced the Node-version/branch/Trivy corrections this file records
- `smartpedidos/events/20260910_backoffice-jenkins-sonarqube-onboarding/` — backOffice's pipeline onboarding (`GITIN-2023`/`GITIN-2024`)
- `smartpedidos/events/20260904_gitin1857-jenkins-status-review/` — status reconciliation for prior Concentrador/Platform Jenkins fixes

# SmartPedidos — CI/CD Reference

Canonical source of truth for pipeline mechanics lives in the separate `sf-devops` repo (`sf-devops/jenkins/SF-PEDIDOS/smartpedidos.md`), not in this repo — this file is a local pointer/summary so CI/CD facts don't have to be re-derived from git archaeology every session (confirmed the hard way, 2026-09-11: reading only the app repos' own in-repo `Jenkinsfile`s produced wrong conclusions about both Node version and scanning coverage, since those files are largely vestigial — the real pipelines were migrated out).

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

**Job settings (`GITIN-1858`, applied 2026-08-27 in both Jenkins jobs, `events/20260827_jenkins-bugreport-toggle-branch-filter/`):** the `Bugs Report` stage runs only when the boolean parameter `RUN_BUGS_REPORT` (default `false`) is set, so webhook builds skip it and a manual "Build with Parameters" can opt in. Each `GenericTrigger` filters on the push `ref` (`genericVariables: [[key: 'ref', value: '$.ref']]`, `regexpFilterExpression: "^refs/heads/${TARGET_BRANCH}\$"`); `TARGET_BRANCH` is one Groovy variable above `pipeline {}` also feeding `LOCAL_GIT_BRANCH` (`develop` for both; platform had a stale feature branch). The files in `sf-devops` mirror the live job scripts; a staged copy in that repo's index that moves `prAnalyzer`/`changelogAnalyzer` into a shared library (`gitSPAnalizer.groovy`) was never applied to Jenkins. Jira: `GITIN-1858` covers both services (`GITIN-1859` discarded as a duplicate; `GITIN-1957`, a post-build message to the team, discarded; epic `GITIN-1857` complete 2026-09-17).

**Trivy scope (`GITIN-2116`, 2026-09-30):** the image step of the platform and concentrador Jenkinsfiles (`sf-devops/jenkins/SF-PEDIDOS/jenkinsfiles/{develop,ope}/dev-src-pedidos-{platform,concentrador}.jenkinsfile`) used `--vuln-type library`, which excludes OS packages, so reports never showed the Alpine layer (4 HIGH on a fresh Node 20.20 base, up to 17 on an older cached one); the `ope` files were changed to `--vuln-type os,library` (reflected in the Jenkins report from 2026-09-30 13:51 UTC; whether `develop` carries it was not checked). No `--exit-code` is set, so the stage never fails a build, and `docker.build()` has no `--pull`/`--no-cache` (base tags are mutable, a cached older base may be reused). Findings inside npm's own bundled install (`/usr/local/lib/node_modules/npm/...`) are not reachable from `package.json`; see `packages_concentrador.md`.

`backOffice` has **no** Docker Build stage (no runtime container — see below) and uses `trivy fs` instead of `trivy image`.

## Per-service status (confirmed 2026-09-11 unless noted)

| Service | Runtime | Node version | Trivy | Status |
|---|---|---|---|---|
| `concentradorService` | ECS/Fargate, built from `develop`'s own `api/Dockerfile` | **20.20-alpine** | `trivy image`, CRITICAL/HIGH, active | Confirmed |
| `platformsService` | ECS/Fargate | `node:20.20-alpine` per its repo Dockerfile | `trivy image`, same pipeline structure as concentrador | Dockerfile confirmed; pipeline behavior inferred from the shared template, not independently re-verified this session |
| `backOffice` | **No container** — static build deployed to S3 + CloudFront | N/A (no real Dockerfile pins production; its own root `Jenkinsfile` is broken, unused, has uncommitted merge-conflict markers on `develop`) | `trivy fs --scanners vuln,secret` against `./app` — pipeline built 2026-09-10 (`GITIN-2023`/`GITIN-2024`) | **User-reported working, not yet independently confirmed via a captured passing build log** — see `events/20260910_backoffice-jenkins-sonarqube-onboarding/investigation.md` |

**backOffice pipeline details (`GITIN-2023` Jenkins, `GITIN-2024` SonarQube):** Angular SPA (`@angular/core ~21.2`, TypeScript `~5.9`), source under `app/` (not `api/`), deployed as static assets to S3 + CloudFront (testing `botstpedidos.smartfran.com`; staging `bostgpedidos.smartfran.com`, distribution `E3URTXO99DLCPO`; the two sides of the merge conflict disagree on the testing distribution id, `E1F3A7KQBUJR60` vs `EE1F3A7KQBUJR60`, unresolved). Pipeline file `sf-devops/jenkins/SF-PEDIDOS/jenkinsfiles/develop/dev-src-pedidos-backoffice.jenkinsfile`, modeled on concentrador's (platform's template is stale: old model name, static `HEAD~10`); `NPM install` and Sonar target `./app`; `SONAR_POJECT_NAME = "DEVELOP.SmartPedidos.BackOffice"` (spelling as in the file); `SONAR_CRED_ID` is the shared Jenkins credential `Sonarqube.TEST.Pedidos` (the Sonar *project key* is not the credential id: a first run failed at `NPM install` with `cd: can't cd to api/` because the Jenkins job held a hand-edited copy of the platform file, with `api/` paths and the project key as `SONAR_CRED_ID`); Trivy runs `trivy fs --scanners vuln,secret`, CRITICAL/HIGH. Its `app/Dockerfile` builder is `node:10-alpine`, incompatible with Angular 21 and unused. Open: the job's log loaded `customScripts@main` from the `SF-LOYALTY` folder instead of `SF-PEDIDOS` (not resolved whether it matters); the GenericTrigger webhook token on the GitHub repo was not confirmed set; no passing build log captured.

## ESLint into SonarQube (`GITIN-2187`, 2026-10-07/08, `events/20261007_gitin2187-eslint-test/`)

Added an `ESLint Report` stage before `Sonarqube Analisys` in the `develop` Jenkinsfiles of platform, concentrador and backoffice (`sf-devops` `main`) and the scanner argument `-Dsonar.eslint.reportPaths=eslint-report.json`: it exists only as a scanner argument in those files, not in any `sonar-project.properties` and not as a SonarQube setting, so it never shows in the UI. While a job runs an inline script, what runs is the script stored in the job, not the repository file. Facts: the projects' ESLint is 6.x and cannot parse optional chaining, `??` or class fields (37 of 121 platform files fatal parse errors); ESLint 8.57.1 with `ecmaVersion:2022` parses all 121 (4 `new-cap` errors, 1,971 style warnings, only `no-unused-vars` and `new-cap` look like defects); `npx eslint@8` ran an older ESLint found on `PATH`, so the stage installs ESLint 8 under a temp prefix and calls its `.bin/eslint` by path; the scanner runs in Docker with `-v ./api:/usr/src`, so absolute host paths are rewritten to `/usr/src/...` with `jq`; concentrador's `.eslintrc.json` extends `google` (the first run failed because `eslint-config-google` was not resolvable; the stage now installs it and falls back to an empty report with a warning); backoffice (Angular/TSLint, no `.eslintrc*`) probably yields an empty report. None of this was seen in a real Jenkins build. `options { skipDefaultCheckout(true) }` was added to six Jenkinsfiles in preparation for "Pipeline script from SCM" (no job migrated; the `RUN_BUGS_REPORT` guard was also added to `pruebas.jenkinsfile`). `jenkins/SF-PEDIDOS/README.md` embeds SonarQube badge URLs with tokens (in repo history). `NODE_ENV` takes `development`, `testing`, `staging`, `production`, `performance`, never `develop`.

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

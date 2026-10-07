# Investigation — 20260910_backoffice-jenkins-sonarqube-onboarding

**Status:** in progress — Jenkins/Sonar/Trivy reported working by user; passing build log not yet captured as evidence

Covers two related Jira tickets from the same onboarding effort:
- **GITIN-2023** — add `dev-src-smartPedidos-backOffice` to the SF-PEDIDOS Jenkins pipeline structure.
- **GITIN-2024** — create the matching SonarQube project.

## Confirmed facts

- `dev-src-smartPedidos-backOffice` is an Angular SPA (`@angular/core ~21.2.7`/CLI `~21.2.8`, TypeScript `~5.9.3`), source under `app/` (not `api/` like concentrador-service/platforms-service). It deploys as static assets to S3 + CloudFront (per its own `deploy-*.sh` scripts and old Jenkinsfile), **not** to ECS/Fargate — there is no running container for this service.
- Reference for the existing SF-PEDIDOS Jenkins setup: `sf-devops/jenkins/SF-PEDIDOS/smartpedidos.md`. Concentrador/Platform both run on agent `sonarqube-srv`, load `customScripts@main` shared library, and follow: Clone → Bugs Report (optional, Claude) → Changelog → NPM install → SonarQube scan → Docker Build → Quality Gate → Trivy (image scan) → Google Chat notify. Neither of their `jenkinsfiles/develop/*.jenkinsfile` includes an actual deploy stage — that pipeline folder is CI/quality-gate only for both existing services.
- The backOffice repo's **own** root `Jenkinsfile` (checked into `develop`, not the sf-devops one) has unresolved git merge-conflict markers (`<<<<<<< HEAD` / `=======` / `>>>>>>> master`) committed as-is — broken, not used as a template. It was only mined for S3 bucket/CloudFront IDs (testing: `botstpedidos.smartfran.com`; staging: `bostgpedidos.smartfran.com`, distribution `E3URTXO99DLCPO`). Note: the two conflict sides disagree on the testing distribution ID (`E1F3A7KQBUJR60` vs `EE1F3A7KQBUJR60`) — unresolved, not needed for the current scope since no deploy stage was added.
- `app/Dockerfile`'s builder stage is pinned to `node:10-alpine` — incompatible with Angular 21 (needs Node ~20.19+/22.12+). Moot for the final pipeline since it doesn't build a Docker image at all (see below), but worth fixing if this Dockerfile is ever used again.
- Built `sf-devops/jenkins/SF-PEDIDOS/jenkinsfiles/develop/dev-src-pedidos-backoffice.jenkinsfile`, modeled on concentrador's (more current) template rather than platform's (stale `claude-sonnet-4-6`, static `HEAD~10` range):
  - No Docker Build stage — S3 static deploy doesn't need a runtime image, and Jenkinsfile explicitly requested "just a build, not docker."
  - `NPM install` / `Sonarqube Analisys` target `./app` instead of `./api`.
  - `SONAR_POJECT_NAME = "DEVELOP.SmartPedidos.BackOffice"` — matches the SonarQube project the user created (type: JS/TS & Web).
  - `SONAR_CRED_ID` stays `"Sonarqube.TEST.Pedidos"` — the shared Jenkins credential ID holding the Sonar token (same one concentrador/platform use).
  - `Test with Trivy` uses `trivy fs` (filesystem/dependency scan) against `./app` instead of `trivy image` — there's no image to scan. Scanners: `vuln,secret` (secret scanning added on request, since this is a frontend repo with more surface for accidentally-committed keys than a backend service), severity `CRITICAL,HIGH`.
  - New unique `GenericTrigger` token generated (`openssl rand -hex 32`) for the GitHub webhook — **not yet configured** as the webhook secret on the `dev-src-smartPedidos-backOffice` GitHub repo as of this writing.
  - File is committed to `sf-devops` (not yet confirmed pushed to `origin/main` in this session — see Open questions).

## Current working theory

The first real Jenkins run (`SF-Pedidos/develop/dev-src-smartpedidos-backoffice`, log in `data/jenkins_build_log_first_run_failed.txt`) failed at `NPM install` with `cd: can't cd to api/`. The environment block visible in that run's pipeline output (`DOCKER_TAG = "dev-src-pedidos-platform"`, `SONAR_CRED_ID = "DEVELOP.SmartPedidos.BackOffice"`, `api/` paths, static `CURRENT_COMMIT='HEAD'`/`PREVIOUS_COMMIT='HEAD~10'`) does not match `dev-src-pedidos-backoffice.jenkinsfile` — it matches a hand-edited copy of `dev-src-pedidos-platform.jenkinsfile` that was apparently configured directly on the Jenkins job (inline, or pointing elsewhere), not the corrected file from this repo. That draft has real bugs on its own even setting aside the `api/` path: `SONAR_CRED_ID` was set to the Sonar *project key* instead of the credential ID, which would have made `withCredentials` fail at the Sonar stage even if NPM install had succeeded.

The user subsequently reported ("working. Jenkinsfile and sonar. also trivy") that after presumably repointing the Jenkins job configuration, all three stages pass. **This has not been independently verified against a second, passing build log** — no such log has been pasted/captured in this session. Treat as user-reported, not confirmed, until a passing run's output is captured in `data/`.

Separately, the failed run's log showed `Loading library customScripts@main:jenkins/SF-LOYALTY/scripts/groovy/customScripts/` — resolving the SF-LOYALTY copy of the shared library rather than SF-PEDIDOS's, contrary to `smartpedidos.md`'s statement that the SF-PEDIDOS folder overrides this at the folder level. Not confirmed whether this is misconfigured for the backoffice job specifically or affects it in practice (the run never reached a stage that calls `prAnalyzer`/`changelogAnalyzer`/`deployPosix` meaningfully differently between the two library copies) — open item, not yet resolved either way.

## Ruled out

- Using `trivy image` / a Docker Build stage for backOffice — ruled out because the service has no runtime container (S3/CloudFront static deploy), and the user explicitly asked for a plain build, not Docker.
- Using the backOffice repo's own root `Jenkinsfile` as the template — ruled out, it has unresolved merge-conflict markers committed on `develop`.

## Open questions / next steps

- Confirm `dev-src-pedidos-backoffice.jenkinsfile` is actually pushed to `sf-devops` `origin/main` (was committed locally; push not yet confirmed in this session).
- Capture a passing build log into `data/` to independently confirm the "working" status, rather than relying solely on the user's report.
- Confirm the GenericTrigger webhook token was actually set on the GitHub repo's webhook config (not verifiable from this repo).
- Confirm/resolve the SF-LOYALTY vs SF-PEDIDOS shared-library folder-override question.
- Out of scope unless requested: fixing the backOffice repo's own broken root `Jenkinsfile`, and adding an S3/CloudFront deploy stage to the sf-devops pipeline (concentrador/platform's `develop` pipelines don't deploy either — deploy appears to be handled outside this specific pipeline folder for both existing services).

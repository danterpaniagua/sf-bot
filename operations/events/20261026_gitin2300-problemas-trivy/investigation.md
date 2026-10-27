# Investigation — 20261026_gitin2300-problemas-trivy

**Status:** in progress

Jira: [GITIN-2300](https://smartit-ar.atlassian.net/browse/GITIN-2300) "[OPE] Problemas Trivy".

## Confirmed facts
- The `dev-src-pedidos-platform` develop build failed at the Trivy stage on 2026-10-26 11:48Z with `Failed to acquire cache or database lock` / `unable to initialize fs cache: cache may be in use by another process: timeout` (`data/trivy-image-platform-cache-lock-error-20261026.txt`). Trivy 0.74.0, pasted by the user; the scan never reached the image.
- The command in the log matches the pipelines in `/home/dpaniagua/Documentos/git/sf-devops` (branch `main`, HEAD `9a7926f`), `jenkins/SF-PEDIDOS/jenkinsfiles/`: `trivy image --format json ... --vuln-type os,library`. The Trivy calls under `loyalty/sf-devops-loyalty` and `sf-cloud/*` are different, older copies (template/`--vuln-type library`).
- Before the change, none of the 10 `trivy image`/`trivy fs` calls in the 5 Jenkinsfiles (develop platform, concentrador, backoffice; ope platform, concentrador) set `--cache-dir`, so they use the agent's default cache.
- The `--vuln-type` and `--template` warnings are deprecation/ignored-option notices and are not what fails the stage.
- Later the same day both develop images were scanned successfully: platform report time 12:04:46Z, concentrador 12:04:50Z (four seconds apart, so the scans ran at about the same time). This is consistent with parallel scans no longer blocking each other, but it is not proof: it is not known whether those builds had `--cache-dir`, and the 11:48:09Z failure was a different run.

## Trivy findings (develop images, 2026-10-26)
Evidence: `data/trivy-report-platform-develop-20261026.txt`, `data/trivy-report-concentrador-develop-20261026.txt` (pasted by the user, link lists shortened).

- Alpine 3.23.4 OS packages: no vulnerabilities, no misconfigurations, in both images.
- `node-pkg` (libraries in `node_modules`): all findings HIGH.

| Package | CVE | Installed | Fixed in | platform | concentrador |
|---|---|---|---|---|---|
| `brace-expansion` | CVE-2026-102276 | 5.0.9 | 5.0.10 (also 3.0.7, 2.1.5, 1.1.19) | yes | yes |
| `brace-expansion` | CVE-2026-102278 | 5.0.9 | 5.0.11 (also 3.0.8, 2.1.6, 1.1.20) | yes | yes |
| `http-cache-semantics` | CVE-2026-93748 | 4.2.0 | no fixed version listed | yes | yes |
| `undici` | CVE-2026-109869 | 6.28.0 | 6.29.1, 7.30.1, 8.12.2 | yes | yes |
| `undici` | CVE-2026-19534 | 6.28.0 | 6.28.1, 7.29.1, 8.10.2 | yes | yes |
| `express-jwt` | CVE-2020-15084 | 5.3.3 | 6.0.0 | yes | no |
| `jsonwebtoken` | CVE-2022-23539 | 8.5.1 | 9.0.0 | yes | no |
| `lodash.set` | CVE-2020-8203 | 4.3.2 | no fixed version listed | yes | no |

- Source check on `develop` (platformsService `e5dc0dc`, concentradorService `f361b020`), `api/package.json`: platformsService declares `express-jwt ^5.3.1` and `jsonwebtoken ^8.3.0` directly, which explains its two extra findings; concentradorService declares `express-jwt ^8.5.1` and `jsonwebtoken ^9.0.3`. Neither `api/` folder has a lockfile, so each build resolves whatever the ranges allow that day.
- `undici`, `brace-expansion`, `http-cache-semantics` and `lodash.set` are not declared in either `package.json`, so they are transitive. Which dependency pulls each one in: not determined.
- The reports have no finding for the Node 20 runtime. The Node version of the images is set by the `FROM` line of the Dockerfile (`node:20.20-alpine` on `develop`); Trivy's OS scanner reads the `apk` database and the language scanner reads `node_modules` packages, and the runtime binary is neither. That Trivy has no analyzer for a standalone Node binary in 0.74.0 is my belief, not verified. Node 20 being end of life is not a CVE either. An earlier expectation (in chat) that the scan would flag the Node runtime was wrong.

## Current working theory
Two Trivy processes on the same agent (parallel jobs or stages) share the default cache directory, or an aborted run left it locked. Not confirmed: no `pgrep -a trivy` or cache listing from the agent has been collected.

## Changes applied
- 2026-10-26: `--cache-dir \"$WORKSPACE/.trivycache\"` added to all 10 `trivy image`/`trivy fs` calls in the 5 Jenkinsfiles above. Committed in `sf-devops` as `34a244a` on `main` (checked 2026-10-26: working tree clean for `jenkins/`, `main` shows no ahead/behind against `origin/main` as of the last fetch; the remote itself was not re-fetched). Patch: `outputs/sf-devops-trivy-cache-dir.patch`. A Jenkins build checked out revision `34a244a` of `git@github.com:smartit-ar/sf-devops.git`, branch `main` (`data/jenkins-build-revision-34a244a-20261026.txt`, pasted by the user; job and build number not given), so at least one job reads this remote. The commit time shows `8:55 AM 10/26/26` with no zone; because the 11:48Z failure log has no `--cache-dir`, that time is probably UTC-3 (11:55Z), after the failure and about 9 minutes before the 12:04Z scans. That is an inference. Still not seen: the Trivy stage output of a build that used the commit, and whether the 12:04Z scans ran on it.
- Expected side effects, not tested: the vulnerability DB is downloaded again in each new workspace (slower first run, registry rate limits possible); `.trivycache` appears in the job workspace.

## Ruled out
- Node version of the image as the cause of the lock error: Trivy fails while initializing its cache, before it opens the image.

## Reported alongside, not Trivy
- backOffice build: `npm install` in `app/` fails with `Cannot read property 'edgesOut' of null` (`data/npm-install-backoffice-edgesout-error-20261026.txt`). Possibly a stale `node_modules`/cache or an npm/Node mismatch on the Jenkins `node` tool; the Node and npm versions were not collected. The repo has no lockfile, `engines` or `.nvmrc`. Related to Node versions, see `operations/events/20261026_gitin2310-nodejs-security-release-oct2026/`. Decide whether it belongs in this ticket.

## Open questions / next steps
- Run the develop platform build with the change and check the Trivy stage output.
- If it still fails: `pgrep -a trivy` and the cache directory listing on the agent (label `sonarqube-srv`).
- Find which dependency pulls in `undici`, `brace-expansion`, `http-cache-semantics` and `lodash.set` (`npm ls <package>` on each service) and the smallest update for each.
- `express-jwt` 5 -> 6 and `jsonwebtoken` 8 -> 9 in platformsService are major-version changes that can affect authentication code; test before applying. The concentrador already uses the newer majors.
- Other deprecated flags in the same lines (`--vuln-type` -> `--pkg-types`) and `--skip-version-check`: optional cleanup, not applied.
- First lines of the npm debug log for the backOffice failure (Node and npm versions).

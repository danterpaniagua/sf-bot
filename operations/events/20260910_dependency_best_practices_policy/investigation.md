# Investigation — 20260910_dependency_best_practices_policy

**Status:** converged — ready for ticket/email

Jira: https://smartit-ar.atlassian.net/browse/GITIN-2026

## Objective

Proactive request (no incident trigger): draft an email enforcing best practices for third-party library/package selection, covering npm (SmartPedidos), NuGet/.NET (SmartLoyalty, SmartFran Cloud), grounded in real examples pulled from our own repos rather than generic advice. Requested criteria: minimum version `>=1.0.0`, package health/SCM activity, size/transitive-dependency footprint (bundlephobia-style), license review, and CI/CD validation tooling (Trivy/Socket/Snyk/Dependabot).

## Sources reviewed

Local read-only repo clones (`**/repo/`, not deploy targets):

| Project | Manifest type | Files | Unique packages |
|---|---|---|---|
| SmartPedidos | npm (`package.json`) | `backOffice/app`, `platformsService/api`, `concentradorService/api` | 28 / 34 / 28 (`data/npm_*_package.json`) |
| SmartLoyalty | NuGet (`packages.config`, .NET Framework) | all `.csproj` projects under `repo/dev-src-sol-smartloyalty` | 261 unique id+version pairs (`data/loyalty_nuget_packages.txt`) |
| SmartFran Cloud | NuGet (`PackageReference`, modern SDK-style `.csproj`) | all `.csproj` under `repo/SmartFran.Cloud/Source` | 237 unique id+version pairs (`data/cloud_nuget_packages.txt`) |
| Operations | — | no application repo clone exists under `operations/` — infra/scripts only, no package manifests to audit | n/a |

Also checked for existing CI/CD dependency-scanning: `cloud/repo/SmartFran.Cloud/.github/workflows/` (~70 workflow files, all deploy/build pipelines) and both SmartPedidos `Jenkinsfile`s — grepped for `trivy|snyk|socket|dependabot|npm audit` — **zero matches across every pipeline in every project.** No `dependabot.yml`/`renovate.json` anywhere in any repo clone either. This is a genuine, confirmed cross-project gap, not an assumption.

## Confirmed facts (real examples, verified where license/status claims are involved)

**Pre-1.0 versions in current use** (violates the "always >=1.0.0" rule as requested):
- `querystring@~0.2.1` (SmartPedidos backOffice, npm) — confirmed via npm registry: **deprecated**, maintainer message "The querystring API is considered Legacy. new code should use the URLSearchParams API instead," MIT license. A pre-1.0, deprecated package duplicating a Node.js built-in.
- `regenerator-runtime@^0.13.3` (SmartPedidos platformsService + concentradorService, npm) — pre-1.0.
- `xlsx@~0.15.3` (SmartPedidos backOffice, npm) — pre-1.0. Confirmed via npm registry: current latest is `0.18.5`; SheetJS's own deprecation messages on older `xlsx` releases point users to `https://cdn.sheetjs.com/xlsx/` instead of the npm registry for current releases — a package whose maintainer no longer treats npm as the primary distribution channel is a health/SCM red flag independent of the version number.
- `MudBlazor.Markdown@0.1.0` (SmartFran Cloud, NuGet) — pre-1.0.

**Package health / SCM activity:**
- `iTextSharp@5.5.13.2` (SmartLoyalty, NuGet) — confirmed via the project's own GitHub repo (`itext/itextsharp`): marked **`[DEPRECATED]`**, "only security fixes will be added — please use iText for .NET." True end-of-life, still in active use in SmartLoyalty.

**License review (the most material finding for this ticket):**
- `iTextSharp@5.5.13.2` (SmartLoyalty) — dual-licensed **AGPLv3** or commercial. Confirmed via iText's own licensing page: distributing/deploying it inside a product or over a network without disclosing your own application's source under AGPL requires purchasing a commercial license. SmartLoyalty is closed-source and commercial — this is a real, unresolved license-compliance exposure, not hypothetical.
- `EPPlus@5.4.1`/`5.5.2` (SmartLoyalty) — versions 5+ are dual-licensed **Polyform Noncommercial 1.0** or a paid **Commercial** license (confirmed via EPPlus's own License FAQ). Commercial use requires `ExcelPackage.LicenseContext = LicenseContext.Commercial` plus an actual purchased license — same exposure class as iTextSharp.
- `AutoMapper@16.2.0` (SmartFran Cloud) — confirmed via multiple independent sources (Jimmy Bogard's own announcement posts, dated 2025): AutoMapper became commercial as of v15.0 (2025-07-02), dual-licensed **RPL-1.5** or a paid tiered commercial license (~$400/mo–$4,000/yr SMB, ~$1,200/mo–$12,000/yr enterprise, per-team not per-seat). Cloud's pinned `16.2.0` is within the commercial-licensed version range — needs an explicit decision (buy a license, or pin back to the last pre-commercial major version and stop upgrading) rather than silent exposure via routine `dotnet restore`.

**Size / maintenance status:**
- `moment@2.22.2`/`2.24.0` (all three SmartPedidos npm projects) and `Moment.js@2.29.1` (SmartLoyalty, NuGet-packaged client-side) — confirmed via Moment's own project announcement: the library has been in **maintenance mode since 2020** ("done", not dead, but no new features), officially recommending Day.js (~2KB gzipped) or date-fns as replacements for new code. ~72KB min+gzip vs. ~2KB for the recommended alternative — a concrete bundlephobia-class size comparison, on top of the maintenance-mode status.

**Biggest single package per service, verified (2026-09-11), source-appropriate metric per deploy target:**
- `platformsService` + `concentradorService` (both run as Node containers on **ECS/Fargate** — image size and pull time matter more than browser transfer weight here): the largest dependency in either service is `swagger-ui-express`'s transitive dependency **`swagger-ui-dist@5.32.15`**, at **11,770,007 bytes (~11.77 MB) unpacked** (npm registry `dist.unpackedSize`) — by a wide margin over the next-largest checked (`mongoose@9.10.0` ~2.17 MB, `core-js@3.50.0` ~1.36 MB, `@aws-sdk/client-sqs@3.1130.0` ~0.62 MB). Both services carry the full interactive Swagger UI static asset bundle in every built container image, which is arguably a docs/dev-time concern, not something that needs to ship in every production image replica.
- `backOffice` (Angular, shipped to the **browser** — bundlephobia's minified+gzip metric is the right lens, unlike the two backend services above): **`apexcharts@7.1.0`** is the largest checked, at **920,393 bytes minified / 260,527 bytes gzip**, well above `xlsx@0.18.5` (~412KB/140KB) and `@fortawesome/fontawesome-free@7.3.1` (~89KB/22KB).
- SmartFran Cloud (.NET/NuGet): **`SkiaSharp@2.88.8`** itself is 7,144,605 bytes (~7.14 MB, NuGet `PackageSize`/.nupkg download size, via `nuget.org`'s v2 OData API), and its transitive **`SkiaSharp.NativeAssets.Linux@2.88.8`** package alone adds another 15,619,001 bytes (~15.62 MB) — combined ~22.8 MB from one dependency chain, before counting any additional native-asset packages for other target platforms (Win32/macOS) that may also be restored.

Raw figures and sources: `data/package_size_examples.txt`.

**Secondary observation (cross-project version drift — not one of the four requested pillars, noted because it surfaced naturally from the same data and reinforces the same policy ask):** the same package appears pinned to multiple divergent major versions across projects/services with no apparent coordination — e.g. `bootstrap` 3.4.1/4.6.0/5.2.3, `jQuery` 3.5.1/3.7.0, `Microsoft.AspNet.Mvc` 5.2.7/5.2.9 (loyalty), `Azure.Identity` across 5 different versions (1.11.4→1.21.0), `AutoMapper` 12.0.1/13.0.1/16.2.0, `Microsoft.EntityFrameworkCore` 7.0.5/7.0.12/7.0.13 (cloud). Also one floating-version pattern found: `System.ServiceModel.*` pinned to `4.10.*` (cloud) — a wildcard range, not a pinned version, meaning `dotnet restore` can silently pick up a new patch release without a corresponding commit.

## Confirmed (2026-09-11) — SmartPedidos runtime versions (Dockerfile `FROM`), CORRECTED after checking actual Jenkinsfiles

Initial pass checked only the `Dockerfile`s under the three SmartPedidos app clones and assumed each `FROM node:...` reflects the real production runtime. That assumption was wrong for `backOffice` — verified by reading the actual `Jenkinsfile` for each project before asserting anything as a real production fact.

| Project | `FROM node:...` in repo | Is that Dockerfile actually used to build the deployed artifact? | Real production runtime |
|---|---|---|---|
| `platformsService` | `node:20.20-alpine` | Not independently re-verified this session (no Jenkinsfile found in this repo clone) — treated as likely current based on the Dockerfile, but confidence is lower than the concentradorService row below | Presumed Node 20 (container, ECS/Fargate) |
| `concentradorService` | `node:14-alpine` | **Yes** — its `Jenkinsfile` runs `docker.build(...)` from `${WORKSPACE}/api`, exactly where this `Dockerfile` lives, then pushes to ECR (`382381053403.dkr.ecr.us-east-2.amazonaws.com`) and deploys to ECS (`smartfran-pedidos-common`/`smartfran-pedidos-production` clusters) | **Confirmed Node 14 — EOL since 2023-04-30** |
| `backOffice` | `node:10-alpine` (builder stage; final stage `fnichol/uhttpd`, a static file server) | **No** — its `Jenkinsfile` never runs `docker build` at all. It builds via Jenkins' own `nodejs(nodeJSInstallationName: 'node')` tool wrapper (a Jenkins-managed Node install, version not determinable from this repo) running `npm install --production && npm run build`, then deploys straight to **S3 + CloudFront** (`aws s3 sync ./app/dist/ s3://...` + `cloudfront create-invalidation`). The Dockerfile is vestigial/unused for the real pipeline. | **No live Node process in production at all — static assets only.** Real build-time Node version unknown (Jenkins global tool config, not in this repo). |

**Retracted:** the original claim that "backOffice runs on Node 10, EOL since 2021" — that was inferred from an unused Dockerfile without checking whether it's actually what builds the deployed artifact. User caught this directly ("backoffice is a special case, runs in S3, technically no package version limit"). Corrected: backOffice has no production Node runtime to be EOL, and no confirmed build-time Node version ceiling either (would need to check Jenkins' own tool configuration, not attempted here).

**SECOND RETRACTION (2026-09-11) — the `concentradorService` Node 14 finding was also wrong, for a different reason.** User flagged: "recheck concentrador, it was on stg branch, need to run on develop." Checked directly (`git status` in the local clone): the clone was in fact already on `develop`, clean, in sync with `origin/develop`. Re-reading `api/Dockerfile` on `develop` HEAD (`cb2b9b8d`, 2026-09-09 16:30:26 -0300) shows **`FROM node:20.20-alpine`**, not Node 14. The `Jenkinsfile` I read earlier (with the `docker.build`/ECR/ECS logic) **does not exist on `develop` at all** — it was deleted from `develop` on 2026-04-16 (commit `6b4d565a`, "feat: archivos borrados"). It still exists on many other branches. My earlier read of it must have come from one of those, not `develop` — the user's suspicion was correct, even though the specific mechanism (branch state at read time vs. which file I actually opened) isn't fully reconstructed.

**Full picture across branches, checked directly this session (not assumed):**

| Branch | Dockerfile `FROM` | Has `Jenkinsfile`? | Last commit |
|---|---|---|---|
| `develop` | `node:20.20-alpine` | No (deleted 2026-04-16) | 2026-09-09 16:30:26 -0300 |
| `stg` | `node:14-alpine` | Yes | 2026-09-09 16:12:52 -0300 (`fix: corrijo paquetes tar y axios`) |
| `master` | `node:12-alpine` (EOL 2022-04-30) | Yes | **2021-09-02** — abandoned, legacy GitLab-era branch |
| `staging` | `node:12-alpine` | Yes | **2020-12-17** — abandoned, even more stale |

`develop` and `master` have diverged significantly (385 commits on `develop` not in `master`; 14 commits on `master` not in `develop`) — `master`/`staging` are clearly dead branches, not real candidates for "what's actually in production." The two genuinely active branches are `develop` (Node 20, no visible pipeline) and `stg` (Node 14, has a pipeline, committed to within minutes of develop's last commit — real ongoing work, including a same-day dependency-related fix per its commit message). But `stg`'s own `Jenkinsfile` only triggers the production-ECS deploy stage `when { branch 'master' }` — and `master` hasn't moved since 2021, so that literal condition cannot be what's currently shipping to production either.

**THIRD PASS (2026-09-11) — resolved properly, by reading existing project documentation instead of reconstructing from git archaeology.** User: "u have documented the CI/CD of smartpedidos. read it instead of guessing." Correct — this repo already has authoritative, dated records that answer everything above cleanly:

- **`sf-devops/jenkins/SF-PEDIDOS/smartpedidos.md`** (canonical pipeline reference): explicit branch strategy table — `dev`=Development, `stg`=Staging/Pre-production, **`develop`=Production**. Confirms `develop` is correct, `stg` is not production — exactly matching the user's original correction. Pipeline flow for Concentrador/Platform: Clone → Bugs Report (Claude, optional) → Changelog → NPM install → SonarQube → **Docker build → Quality Gate → Trivy scan** → Google Chat notify. Trivy scans the built image for CRITICAL/HIGH vulnerabilities, publishing `trivy_vuln.html` + `trivy_vuln.json`.
- **`smartpedidos/events/20260904_gitin1857-jenkins-status-review/investigation.md`**: confirms both Concentrador and Platform jobs in `sf-devops` were actively fixed 2026-08-27 (branch-filter added, Platform's target branch corrected from a stale feature branch to `develop`) — real, recent, applied maintenance work, not a stale/abandoned setup.
- **`smartpedidos/events/20260910_backoffice-jenkins-sonarqube-onboarding/investigation.md`** (today): backOffice has no ECS/Fargate runtime, confirmed independently here too — deploys as static assets to S3+CloudFront. Its own root `Jenkinsfile` (the one with merge-conflict markers I read earlier) is broken/unused, mined only for S3/CloudFront IDs. A new `sf-devops` pipeline (`dev-src-pedidos-backoffice.jenkinsfile`) was built today for GITIN-2023/2024, using `trivy fs --scanners vuln,secret` against `./app` (no image to scan). **Status: user-reported working, but not yet independently confirmed via a captured passing build log in that session** — treat as reported, not fully confirmed, per that file's own stated status. Also confirms: `app/Dockerfile`'s `node:10-alpine` builder is "incompatible with Angular 21" and "moot since it doesn't build a Docker image at all."
- **`smartpedidos/docs/packages_concentrador.md`**: a real, already-completed dependency investigation (GITIN-2000, 2026-09-08) into `concentradorService`'s `axios`/`tar` versions, using actual Trivy findings (`tar` 6.2.1 → 9 CVEs; `axios` two installed versions, both with 10 HIGH CVEs each) to justify a real `overrides` fix. This is the same fix visible as the `stg` branch's most recent commit ("fix: corrijo paquetes tar y axios") from earlier in this session — consistent, real, already-tracked work, not something to re-discover.
- **`sf-devops/jenkins/SF-PEDIDOS/scripts/npm-pachages.sh` + `npm-analysis.sh`**: **a real, existing (but "not yet wired into the pipeline") tool doing almost exactly what this ticket's compliance-check request asks for.** `npm-pachages.sh` reads `package-lock.json`, calls `npm view <pkg> --json` once per package, and flags any package that's `deprecated` (registry `deprecated` field) or hasn't been published in **>2 years** (`time.modified`) — the exact same staleness heuristic independently proposed earlier in this investigation, now confirmed as the team's own existing convention rather than an invented threshold. `npm-analysis.sh` cross-references that output against `trivy_vuln.json`'s vulnerable package list. **Real blocker, confirmed by reading the script**: it requires `package-lock.json` to enumerate packages — none of the three SmartPedidos projects have one committed (already found earlier this investigation), so this existing script cannot currently run against any of them as-is. This directly elevates the "no lockfile" finding (H11) from a reproducibility nitpick to an active blocker on the team's own existing tooling. Minor unrelated bug also spotted: the script's last line pipes through `jq .npm`, which doesn't match its own output shape (no `.npm` key) — likely dead code from an earlier iteration, not investigated further.

**Corrected, final understanding of Node/pipeline state:**

| Project | Real prod runtime | Node version | CI/CD scanning |
|---|---|---|---|
| `concentradorService` | ECS/Fargate container, built via `sf-devops`'s `dev-src-pedidos-concentrador.jenkinsfile` from `develop`'s own `api/Dockerfile` | **Node 20.20-alpine** (not 14 — that was `stg`, a non-production branch) | `trivy image` (CRITICAL/HIGH), active and confirmed via canonical doc |
| `platformsService` | ECS/Fargate container (per `sf-devops` branch-strategy doc; own Jenkinsfile also corrected to target `develop` 2026-08-27) | `node:20.20-alpine` per its own repo Dockerfile (not independently re-verified against a second branch this session, but no reason to doubt it given the same pattern held for concentrador) | `trivy image`, same pipeline structure as concentrador |
| `backOffice` | **No container** — static S3/CloudFront | N/A for production; build-time Node version not pinned by any real Dockerfile (its own is broken/unused) | `trivy fs --scanners vuln,secret` against `./app` — configured today (2026-09-10), user-reported working, **not yet independently confirmed via a passing build log** |

**Retracting the earlier "no CI/CD scanning anywhere" claim (this ticket's original H4) as it applies to SmartPedidos** — Trivy vulnerability (and, for backOffice, secret) scanning is real and active across all three projects via `sf-devops`, not visible from the app repos' own now-largely-vestigial in-repo Jenkinsfiles alone. What remains genuinely true and unaddressed: no **license**-specific scanning (Trivy here runs `--vuln-type library`/`vuln,secret`, not its license scanner), and no Dependabot/Renovate-style automated dependency-update bot anywhere checked. Cloud's situation is separately confirmed below.

## Full npm compliance check run (2026-09-11) — `/sp-npm-compliance`

Ran the new `sp-npm-compliance` skill against all three SmartPedidos projects. All three clones confirmed on `develop`, fetched fresh (`platformsService` was 2 commits behind `origin/develop` — pure application-code changes, no `package.json`/lockfile impact — fast-forwarded before checking). Script: `scripts/npm_compliance_check.mjs` (one npm-registry fetch per package + a semver-range resolver, no lockfile available so "installed version" is the highest version satisfying the declared range). Full report: `data/npm_compliance_report.md`. Raw per-package JSON: `data/npm_compliance_{backoffice,platforms,concentrador}.json`.

**Two real bugs found and fixed in the script itself during this run, not left silent:**
1. npm's registry API omits the `readme` field entirely for high-traffic packages (`express`, `@angular/core` both returned length 0) — a naive readme-length check would have wrongly flagged them as undocumented. Fixed by falling back to `homepage`/`repository` presence when `readme` is empty.
2. The "latest version compatible with the Dockerfile's Node version" walk didn't exclude prerelease versions (`8.0.0-beta.0`, `-alpha.0`, `-rc.1`), so 5 packages (`@babel/core`, `@babel/node`, `core-js`, `env-var`, `swagger-jsdoc`) showed a `dockerCompat` version numerically *higher* than the real `latest` dist-tag. Fixed by excluding any version string containing `-`. Spot-verified the fix is correct, not just quieter: `@babel/core@8.0.5` (the real `latest`) genuinely requires `engines.node: "^22.18.0 || >=24.11.0"` — incompatible with the Dockerfile's Node 20, so `7.29.7` is the correct answer, not a masked bug.

**Summary (post-fix):**

| Project | Deps | Min-version fails | Health fails | Doc fails |
|---|---|---|---|---|
| backOffice | 28 | 3 (`querystring`, `xlsx`, `zone.js`) | 7 | 1 (`@sweetalert2/ngx-sweetalert2`) |
| platformsService | 34 | 1 (`regenerator-runtime`) | 5 | 1 (`@types/form-data`) |
| concentradorService | 28 | 1 (`regenerator-runtime`) | 4 | 0 |

**Notable real findings surfaced (not previously known from the earlier license/size pass):**
- `uuid@8.0.0` (both platform and concentrador): actively deprecated by its maintainer — "uuid@10 and below is no longer supported."
- `crypto-js@4.2.0` (concentrador): "Active development of CryptoJS has been discontinued. This library is no longer maintained." — an abandoned crypto library, more concerning than routine staleness.
- `@types/form-data` (platform): deprecated as an unnecessary stub — `form-data` now ships its own types, this dependency can likely just be removed.
- License check across all 90 packages: overwhelmingly MIT/Apache-2.0/ISC/BSD-3-Clause (matches the earlier "no commercial-license issue in SmartPedidos" finding). Four non-standard license fields worth a manual glance, not urgent: `@fortawesome/fontawesome-free` (compound `CC-BY-4.0 AND OFL-1.1 AND MIT` — real attribution requirement for the icon/font assets, standard for this package), `apexcharts` (`SEE LICENSE IN LICENSE` — known to be MIT in practice, just not SPDX-tagged), `@sweetalert2/ngx-sweetalert2` and `ng-apexcharts` (registry reports `unknown` — likely a metadata gap in these Angular wrapper packages, not a real restrictive license).
- `@babel/core`/`@babel/node` are capped at `7.29.7` for both backend services given their Node 20 runtime — `8.x` requires Node ≥22.

## Cloud's CI/CD — same blind spot, now checked

Cloud also has an external Jenkins layer (`sf-devops-cloud`, sibling repo, not the in-repo GitHub Actions workflows originally checked) with Trivy referenced in its per-service `.jenkinsfile`s (e.g. `SmartFran.Cloud.Business.API.jenkinsfile`) — **but unlike SmartPedidos, the shared template (`SmartFran.Cloud.Template.jenkinsfile`) has its Trivy invocation commented out**, while the individual per-service files (`Business.API`, `Catalog.API`, `Client.Web`, `Person.API`, `Platform.API`, `Pos.Wasm`, `Sales.API` — all under `sf-devops-cloud/test/`) have it **live/uncommented**. Not independently confirmed whether these `test/`-folder files are what actually runs for Cloud's real environments (didn't find a non-`test` per-service file to compare against) — treat as "Trivy appears configured for Cloud's individual services" rather than a fully confirmed-active state, less certain than the SmartPedidos finding above.

This also means the "last version available (Dockerfile-based compatibility)" compliance axis for the npm-compliance-check script only meaningfully applies to `platformsService` and `concentradorService` (real container runtimes) — for `backOffice`, package version compatibility is a **build-time-only** concern (can `ng build`/`npm install` complete on whatever Node the Jenkins agent provides), not a production-runtime security exposure, and the ceiling itself isn't known from this repo.

**User-added nuance (2026-09-11):** this cuts both ways for `backOffice`. Upgrading npm packages there is *easier* than in `concentradorService` — there's no production runtime whose compatibility must be preserved, only a successful `ng build`. But the flip side is a real, distinct risk: because there's no Dockerfile actually pinning the build environment, `backOffice`'s build-time Node/npm version is whatever Jenkins' global `nodejs(nodeJSInstallationName: 'node')` tool happens to resolve to — not something the project itself declares or controls. That's the inverse failure mode from `concentradorService` (stuck on an old pinned version): instead, the build could break unexpectedly if that global Jenkins tool config changes, with no project-level version pin to catch or prevent it.

Also confirmed: none of the three SmartPedidos projects has a `package-lock.json` committed — "installed version" for any compliance check can only be the highest version satisfying the declared `package.json` range, resolved live against the registry, not a true pinned/reproducible install.

## Axiom 7 added (2026-09-11) — CVEs per installed version, via OSV.dev

User request: add a 7th axiom (and matching email/skill sections) checking known CVEs for the library, with the compliance rule "not compliant if CVE >= HIGH." Implemented as a live `POST https://api.osv.dev/v1/query` per package against the resolved **installed** version specifically (not just the latest) — no Docker image required, unlike Trivy. Wired into `npm_compliance_check.mjs` and the `sp-npm-compliance` skill spec.

**Real bug caught before trusting the output**: the initial implementation reported `axios@1.13.6` as "HIGH x28," which reads as 28 HIGH-severity CVEs — actually 28 is the *total* vulnerability count across all severities. Verified directly against OSV.dev: 10 HIGH, 17 MODERATE, 1 LOW = 28 total. Fixed by tracking a per-severity breakdown (`cveBySeverity`) instead of a single count+max-severity pair, and rendering all three numbers explicitly rather than a single ambiguous count.

**Findings across the 90 SmartPedidos npm dependencies, installed-version-specific:**
- `axios@1.13.6` (platformsService, concentradorService): 10 HIGH, 17 MODERATE, 1 LOW — matches Trivy's independently-confirmed finding in `packages_concentrador.md`/GITIN-2000 exactly (10 HIGH), a genuine cross-validation between OSV and Trivy, not just two tools agreeing on the same unverified assumption.
- `xlsx@0.15.6` (backOffice): 5 HIGH (prototype pollution among them).
- `moment@2.24.0` (backOffice): 2 HIGH (a path traversal in `moment.locale`).
- `express-jwt@5.3.3` (platformsService): 1 HIGH (authorization bypass).
- `jsonwebtoken@8.5.1` (platformsService): 3 HIGH (legacy key-type handling).

Added to the report table as a `CVEs` column (severity breakdown, mark ✓/✗ per the HIGH-or-above rule), factored into the unhealthy-first row sort (a package with `healthOk:true` but `cveOk:false`, e.g. `axios`, still sorts to the top), and added to both emails as point 7.

## NuGet compliance check for Cloud (2026-09-11) — `/cloud-nuget-compliance`

Built a companion skill (`cloud-nuget-compliance.md`) and script (`scripts/nuget_compliance_check.mjs`) mirroring `/sp-npm-compliance` for NuGet, covering axioms 1/2/3/4/5/7 unconditionally (axiom 6's "compatible with runtime" is deliberately not computed — Cloud has ~30 separate `.csproj` files on potentially different `TargetFramework`s, unlike SmartPedidos' one-Dockerfile-per-service shape, so there's no single fleet-wide answer without naming a specific project).

**Same branch-discipline guardrail applied and it mattered again**: the Cloud clone was on `dev` (unreleased), not `main` (Cloud's actual production branch — opposite convention from SmartPedidos, already documented). Checked out `main`, found it **156 commits behind** `origin/main`, fast-forwarded. Re-extracted the package list fresh afterward and diffed against the earlier (pre-correction) extraction — real differences confirmed, e.g. `Microsoft.AspNetCore.Components.Web` was `10.0.11` on the stale `dev` read vs. `7.0.17`/`8.0.3` on current `main` — `dev` had upgrades not yet in production, exactly the kind of gap this guardrail exists to catch.

**Two real bugs found and fixed before trusting the NuGet script's output** (same discipline as the npm version):
1. NuGet's V2 OData `LicenseNames` field is essentially always empty, even for well-known MIT packages (`Newtonsoft.Json` showed `unknown`). The real SPDX `licenseExpression` lives in the V3 registration `catalogEntry`, not V2 — switched to reading it from there (same page already being fetched for deprecation, no extra request).
2. The V3 registration index pagination logic was wrong: it treated "page 0 has inline items" as "this is the only page," ignoring that a package can have multiple pages with *different* version ranges. Confirmed concretely: `Newtonsoft.Json`'s page 0 only covers `3.5.8`–`12.0.1-beta2`; version `13.0.1` needed page 1, which the buggy logic never checked. Fixed to always match on `[lower, upper]` bounds across all pages first, using inline items only if that specific matched page has them.

**Findings across 238 package+version entries (name+version pairs, not unique package names — the same package legitimately appears multiple times at different versions across Cloud's sub-projects):**

| Axis | Fails | Notes |
|---|---|---|
| Min version | 3 | (`MudBlazor.Markdown@0.1.0` already known; two more from the full 238-entry pull) |
| Health | 186 of 238 (~78%) | High, but verified real, not a script bug — spot-checked a known-recent version (`Microsoft.Extensions.Configuration@9.0.8`, published 2025-08-04) correctly shows `olderThan2y:false`; the high fail rate reflects genuine version drift (many old pinned patch versions per package, confirmed earlier in this same investigation) |
| Documentation | 0 | Every entry had either a substantial description or a ProjectUrl |
| CVEs (≥HIGH) | 3 | `AutoMapper@12.0.1` and `@13.0.1` — DoS via uncontrolled recursion (`GHSA-rvv3-g6hj-g44x`); `System.Text.Json@8.0.0` — DoS (`GHSA-8g4q-xg66-9fp4`/CVE-2024-43485). Notably `AutoMapper@16.2.0` (the newest, now-commercial version) is **not** affected — the vulnerable pins are specifically the older versions still used by some sub-projects, another concrete cost of the version drift already flagged (H-secondary finding, earlier in this file). |

**One real resolution failure, not a script bug**: `Microsoft.Extensions.Configuration.Binder@8.5.0` (declared in a Cloud `.csproj`) returns HTTP 404 against the NuGet registry — confirmed via the flat-container version list that `8.5.0` **was never published** (highest `8.x` release is `8.0.2`). This version cannot resolve on a fresh `dotnet restore` — either a typo in the `.csproj` (possibly confused with `Microsoft.Extensions.Configuration@9.0.8`, which does exist) or a stale reference nobody has hit yet because local builds are using a cached/already-restored `obj`/`packages` folder. Worth flagging to whoever owns that project specifically.

Full report: `data/nuget_compliance_report.md`. Raw data: `data/nuget_compliance_cloud.json`.

## CORRECTION (2026-09-11) — Cloud's real CI/CD is GitHub Actions, not the Jenkins layer found earlier; don't name internal repo paths in external-facing output

User pushed back directly on the email claim about Cloud's pipeline location and gave the authoritative, corrected picture for all three projects:

- **SmartPedidos**: real pipeline does code review (Claude analysis) + Trivy + SonarQube. Matches what was already found.
- **SmartFran Cloud**: real CI/CD is **GitHub Actions** — not the external Jenkins-based repo found and cited earlier in this file (a local sibling repo not part of `bots/`). That earlier finding (Trivy referenced per-service, commented out in the shared template) appears to describe something that isn't the actual production pipeline — retracting the "Trivy appears configured for Cloud" claim. This restores my *original* finding from earlier in this same investigation (grepping Cloud's actual in-repo `.github/workflows/*.yml`, ~70 files, zero Trivy/Snyk/Socket/Dependabot matches) as the correct one — that detour through the other repo was a wrong turn, not an improvement.
- **SmartLoyalty**: real CI/CD is Jenkins, for compilation and SonarQube only — no vulnerability scanning. New information this session; not independently verified here, taken as reported.

**Explicit constraint going forward, stated directly by the user: do not name the local sibling Jenkins-pipeline repos (the SmartPedidos one referenced via `smartpedidos/docs/cicd.md`, and the Cloud one that turned out to be wrong) in anything external-facing — emails, the Jira ticket body (`ops.md`).** Scrubbed from both emails and `ops.md`'s findings table. This file (`investigation.md`), `smartpedidos/docs/cicd.md`, and the `.claude/commands/*.md` skill files are treated as private/internal and were left referencing the real paths where functionally necessary (the skill genuinely needs to know where to look) — revisit if the user indicates the constraint should extend there too.

**`docs/cicd.md` and `sp-npm-compliance.md`'s SmartPedidos-specific claims are unaffected by this correction** — the SmartPedidos Trivy/Node-20/branch-strategy findings all came from directly reading that project's own real pipeline files and were re-confirmed independently (real Trivy findings already used in GITIN-2000), not from an assumption. Only the *Cloud* CI/CD claim needs to be walked back — `cloud-nuget-compliance.md`'s brief Trivy/Cloud aside needs the same correction.

## Open questions / not pursued

- Whether any of the flagged commercial-license packages (iTextSharp, EPPlus, AutoMapper) already have a purchased commercial license in place — this investigation only confirms the *version in use* falls in the commercially-licensed range, not the org's actual licensing status. That's a real compliance question for whoever owns vendor/license procurement, out of scope for this email itself.
- Full per-package SCM/bundlephobia sweep of all 261+237+90 packages was not performed — the examples above were selected as the clearest, most defensible illustrations of each requested pillar, not an exhaustive audit. If a full inventory is wanted later, that's a larger separate effort.

# concentrador-service — Dependency Reference (axios / tar / npm); platform-service section at the end

Reference for `concentrador-service`'s `api/package.json` dependency tree and image, from the axios/tar ticket (GITIN-2000) and the npm update that followed (GITIN-2117, same method as the platform's GITIN-2116, `events/20260928_gitin2116-platform-npm-update/`, summarized in the platform section below). Dependents verified directly against the npm registry (published metadata), not assumed; full investigations: `events/20260908_gitin2000-axios-tar-upgrade/`, `events/20261005_gitin2117-concentrador-npm-update/`, `events/20261007_gitin2187-eslint-test/`.

## Current declarations

State per `GITIN-2187` notes of 2026-10-08 (not re-read from the repo since): the update was committed **directly to `develop`** (concentrador `01494650`, platform `373144e`), not through a PR, and `ope` has diverged from `develop` in both services (it lacks the MercadoPago work). Whether the Jenkins `develop` builds with the new Dockerfile ran was not seen.

```json
"dependencies": { "axios": "~1.20.0", "mongoose": "~7.8.7", "@sendgrid/mail": "^7.7.0", ... },
"overrides": { "tar": "latest", "axios": "$axios" }
```

- `overrides.tar: "latest"` (dist-tag, not a range, so a future `tar` CVE needs no new ticket; the trade-off is that a fresh `npm install` can take a new major without review). `tar` is not imported anywhere in `api/src`: it is a pure transitive dependency. `overrides.axios: "$axios"` makes every nested axios follow the top-level one. On 2026-09-08 `develop` and the first `ope` declared `axios ~1.13.5` with `tar ^7.5.21`.
- `api/Dockerfile`: `FROM node:20.20-alpine` in both stages, plus `RUN npm install -g npm@11.20.0` in both stages and `RUN apk upgrade --no-cache` in the final stage. No CA-certificate block (the platform's has one for `bot-security.smartfran.com`; not part of the CVE work). Node 22.20 gives the same scan result but no container was run on it: compatibility unverified. `mongoose` resolves to 7.8.12 and stays 7.x (user decision for the platform, assumed here, not confirmed).

## Who actually depends on axios

Checked every direct dependency in `api/package.json` against its own published `dependencies` on the npm registry (one level deep; deeper for `mongoose`'s subtree):

| Package | Depends on axios? |
|---|---|
| `@sendgrid/mail@^7.7.0` → `@sendgrid/client@^7.7.0` | **Yes** — `"axios": "^0.26.0"` |
| `mongoose@~7.8.7` (+ full subtree: `mongodb`, `mquery`, `bson`, `kareem`, `mongodb-connection-string-url`, `socks`) | No |
| `@aws-sdk/client-sqs@^3.0.0` | No |
| `@aws-sdk/client-ssm@^3.0.0` | No |
| `@babel/core@^7.6.0` | No |
| `@meanie/mongoose-to-json@^2.4.0` | No |
| `body-parser@^1.18.3` | No |
| `cookie-parser@^1.4.3` | No |
| `core-js@^3.2.1` | No |
| `cors@^2.8.5` | No |
| `crypto-js@^4.2.0` | No |
| `express@^4.18.2` | No |
| `express-jwt@^8.5.1` | No |
| `form-data@^4.0.2` | No |
| `jsonwebtoken@^9.0.3` | No |
| `lodash@^4.17.15` | No |
| `moment@^2.22.2` | No |
| `mongoose-unique-validator@~4.0.1` | No |
| `morgan@^1.9.1` | No |
| `node-cron@^2.0.3` | No |
| `regenerator-runtime@^0.13.3` | No |
| `swagger-jsdoc@^6.2.8` | No |
| `swagger-ui-express@^5.0.0` | No |
| `uuid@8.0.0` | No |
| `winston@3.2.1` | No |
| `winston-mongodb@5.0.0` | No |

**Conclusion:** the only two consumers of `axios` in this dependency tree are the application's own source (`api/src/utils/httpClient.js`, direct usage of `dependencies.axios`) and `@sendgrid/client`'s pinned `^0.26.0`. No other package in the tree depends on axios at any version, including `mongoose` — the earlier assumption that `mongoose` constrained the axios version did not hold up under registry verification; the real reason the bump was deferred was the unknown impact radius.

## Trivy results and what they mean

**Reading rule:** most `tar`, `brace-expansion`, `minimatch`, `cross-spawn`, `glob`, `ip-address`, `pacote`, `sigstore` findings come from **npm's own bundled install** (`/usr/local/lib/node_modules/npm/node_modules/...`), not from the project tree, so `package.json` overrides have no reach there; Node 20's bundled npm is frozen at 10.8.2 across the LTS line. The first conclusion that `overrides.tar` "resolves all of them" was wrong for that reason; the `npm@11.20.0` pin is what clears them. Check `PkgPath` of each finding before choosing the fix.

| Scan (HIGH + CRITICAL, `--pull --no-cache`, Trivy `--scanners vuln --pkg-types os,library`) | OS | Node packages | Total |
|---|---|---|---|
| 2026-09-08 first report (`develop`): `tar@6.2.1` ×9 (1 CRITICAL `CVE-2026-59873`), `axios` `0.26.1` ×10 (via `@sendgrid/client ^0.26.0`) and `1.13.6` ×10; fixes needed up to `tar 7.5.21`, `axios 1.16.0` | no OS target | 29 (`tar` 9 + `axios` 20) | 29 |
| 2026-09-08 `ope` after the `overrides` block: the nested `0.26.1` is gone, only `1.13.6`; `tar 6.2.1` still there (npm-bundled) plus the bundled-npm findings above | not scanned | | n/a |
| 2026-10-05 original `ope` image (node 20.20.2, npm 10.8.2, Alpine 3.23.4) | 4 (`libcrypto3`/`libssl3` 3.5.6-r0) | 35 (`axios@1.13.6` ×12, npm-bundled 23) | **39** (1 CRITICAL) |
| 2026-10-05 candidate (axios `~1.20.0`, npm 11.20.0, `apk upgrade`), node 20.20 and 22.20 | 0 | 4, all inside npm 11.20.0's bundled packages (`brace-expansion@5.0.9` ×2, `undici@6.28.0`, `http-cache-semantics@4.2.0`, no fix listed) | **4** |

The platform went 51 → 6 with the same method (its extra findings were `express-jwt`, `jsonwebtoken`, `lodash.set` and a second axios copy). The concentrador has no `express-jwt`/`jsonwebtoken`/`lodash.set` finding: it declares `express-jwt ^8.5.1` and `jsonwebtoken ^9.0.3`, past the fix thresholds (6.0.0 and 9.0.0), and no `lodash.set`. Whether a newer npm than 11.20.0 clears the last four is unchecked; none is fixable from `package.json`. The npm-bundled residue was proposed to be documented as accepted, low-exploitability risk (not on the runtime path of `npm run serve`), not finalized. Counts drift because the Trivy database is fetched at run time; `uuid@8.0.0` has one MODERATE finding below the filter.

## Impact radius of axios 1.20 (read from source 2026-09-08, not exercised)

`axios` is used in six files through `utils/httpClient.js` (`axios.create()` with the shared response/error interceptor that writes the `[PERF/INFO] http_response` fields) and one raw call: `controllers/branch.js` has ~85 call sites (every delivery platform: Rappi, Uber Eats, PediGrido, PedidosYa, SmartLoyalty), `delivery.js` one raw `axios.post`, and `thirdParty.js`, `initialData.js`, `token.js`, `checkUTC.js` one each (with dead `import axios`). `branch.js:287` (`loginCountryUber`) sends multipart through the Node `form-data` package on the http adapter. Between 1.13.5 and 1.16.0 only CRLF rejection in header values applies (all header values here are static or opaque bearer tokens: low risk); the fetch-adapter, proxy, basic-auth-in-URL and `parseProtocol` changes do not apply (no proxy configuration, Node http adapter, absolute URLs). The real risk is surface area: regression-test per platform in a non-production environment. Smoke tests still **not run**: the `httpClient` interceptor fields on 1.20.x, `loginCountryUber`, and SendGrid sends (`user.js` ×3, `recovery.js`, `initialData.js`, `checkUTC.js` ×2; production SendGrid failure logs since the override went live were never checked). Only a `NODE_ENV=testing` boot was seen: `database_connected` (a remote Atlas cluster) and `server_running` on 3086.

## platform-service (GITIN-2116, `events/20260928_gitin2116-platform-npm-update/`, read 2026-10-28)

Same method as above, CVE-only scope (user, 2026-09-30). The raw registry/OSV sweep (`data/registry_*.json`, `osv_*.json`) covers the union of both services' 35 direct production dependencies, so it is reusable without re-fetching. Child of [GITIN-2107](https://smartit-ar.atlassian.net/browse/GITIN-2107); siblings GITIN-2117 (concentrador) and GITIN-2118 (backOffice, no Node runtime).
- **Node boundary (Node 20.20, no `engines` in either `package.json`; no `package-lock.json`, so "installed" versions are resolved from the declared ranges):** only 3 of 35 packages are capped below their own latest by Node 20: `@babel/core`/`@babel/node` (latest 8.0.6 needs Node 22+, capped at 7.29.7) and `mongoose-unique-validator` (latest 6.1.1 needs Node 22+, capped at 5.0.2); `sqs-consumer` loses one patch (15.0.3 → 15.0.0). The boundary-version CVE check was `{}` for all 35 (the OSV mechanism was sanity-checked on `axios@1.13.6`). A parser trap: `engines.node` strings such as `">= 8.0.0"` must be normalized (operator glued to the version) before splitting, or packages look Node-20-incompatible.
- **Installed-version exposure (2026-09-25):** `axios@1.13.6` 28 CVEs (10 HIGH), and, **platform only**, `express-jwt@5.3.3` (`GHSA-6g6m-m6h5-w9gf`, authorization bypass, fixed 6.0.0) and `jsonwebtoken@8.5.1` (CVE-2022-23539, 1 HIGH + 2 MODERATE, fixed 9.0.0), plus `uuid@8.0.0` (1 MODERATE, below the HIGH/CRITICAL filter); platform runs `express-jwt` 5.3.3 / `jsonwebtoken` 8.5.1 where the concentrador runs 8.5.1 / 9.0.3. Clearing them needs only a version bump inside the Node 20 boundary, after checking the JWT usage. `lodash.set@4.3.2` (CVE-2020-8203, no fixed version) has an untraced parent.
- **State of `ope` (2026-09-30/10-05, since committed to `develop` on 2026-10-08 as `373144e`, per the section above):** `axios ~1.20.0` with `overrides {axios: "$axios", tar: "latest"}` (28 CVEs → 0); `express-jwt ^5.3.1`, `jsonwebtoken ^8.3.0` and `uuid 8.0.0` **not bumped**; `mongoose` stays `~7.8.7` (resolves 7.8.12, 0 CVEs) by user decision. The mongoose target is coupled to `mongoose-unique-validator` (`~4.0.1`, peer `mongoose ^7`): 5.x needs mongoose 8; 6.x needs mongoose 8/9 and Node 22; so on Node 20 only mongoose 8.24.4 + unique-validator 5.0.2 is a consistent upgrade set, and mongoose 9.x needs Node 22 or dropping the validator (no breaking-change review or install dry run was done). `winston-mongodb` is pinned 5.0.0 (latest 7.0.1 needs `mongodb ^6.5.0`, unchecked).
- **Scan ladder on Node 20.20, same Trivy flags as above:** raw `node:20.20-alpine` (npm 10.8.2, Alpine 3.23.4) 4 OS + 22 bundled-npm findings (1 CRITICAL `tar@6.2.1`) → `npm install -g npm@11.20.0` 4 OS + 3 (`brace-expansion@5.0.9` ×2, `undici@6.28.0`) → `apk upgrade --no-cache` 0 OS + 3 → plus the app 0 + 6 (those 3, `express-jwt`, `jsonwebtoken`, `lodash.set`). **Production baseline (`origin/develop` `ded57a5`, no pin, no `apk upgrade`, no overrides): 51 findings** = 4 OS + 22 bundled npm + 22 `axios` (`1.13.6` ×12 and a nested `0.26.1` ×10) + 3 app. Option 1 (Node 20.20) and Option 2 (Node 22.20) both end at **6**, OS 0. On Node 22.20 the un-changed baseline is worse (raw 62, develop source 87) because that tag was not rebuilt for a year (created 2025-09-24, Alpine 3.22.2, npm 10.9.3) while `node:20.20-alpine` was rebuilt 2026-04-15. **Base tags are mutable:** a fresh pull of `20.20-alpine` gave Alpine 3.23.4 with 4 OS HIGH while earlier local builds on a cached copy had Alpine 3.23.3 with 17 (2 CRITICAL); a Jenkins `docker.build()` without `--pull` may reuse an older cached base (not checked). Fixed versions all exist (openssl 3.5.8-r0, musl 1.2.5-r23 / -r12, zlib 1.3.2-r0); whether the Node runtime uses the system `libssl3` (its tarball may bundle OpenSSL) was not verified. Trivy's label still reads "alpine 3.23.3/4" after `apk upgrade` (label source not investigated).
- **Why the Jenkins reports never showed the OS layer:** every SmartPedidos Trivy image step (`sf-devops/jenkins/SF-PEDIDOS/jenkinsfiles/{develop,ope}/dev-src-pedidos-{platform,concentrador}.jenkinsfile`) used `--vuln-type library`; changed to `os,library` (8 lines, `ope`, uncommitted at the time). The first report with an `alpine` section (2026-09-30 13:51 UTC) had 4 HIGH, the next (18:07 UTC) none after `apk upgrade`. No `--exit-code` is set, so the stage never fails a build. A diagnostic detour worth remembering: two Jenkins reports showed `tar@6.2.1`/`7.4.3` after a `develop`-like build; "stale Docker cache on `sonarqube-srv`" was the first (wrong) explanation, and the `package-lock.json` / `find /usr/src/app` checks that came back clean looked in the wrong place: always include `/usr/local/lib/node_modules/npm/node_modules` in the search.
- **SendGrid and axios:** the nested `axios@0.26.1` is `@sendgrid/mail@7.7.0` → `@sendgrid/client@7.7.0` → `axios ^0.26.0`. `@sendgrid/mail` has stayed `^7.7.0` since it was added (concentrador 2023-05-10, platform 2025-06-03; 7.7.0 is the last 7.x, published 2022-05-18; 8.1.6 latest, 2025-09-19); the only attempt to move, side branch `origin/cambiosPackages` (2023-12-27, `@sendgrid/mail ^8.1.0` with `axios ^1.6.2`, `express-jwt ^8.4.1`, `jsonwebtoken ^9.0.2`), was never merged. The `$axios` override forces the client onto axios 1.x (a 0.x → 1.x jump for code written against 0.26: **not tested**); the concentrador's `develop` already carries the override (`4cacd4dd`, 2026-09-09; production deploy date and SendGrid failure logs not checked). Code only calls `sgMail.setApiKey` and `sgMail.send(msg).then(ok, error)` (platform `aws.js` ×2; concentrador `initialData.js`, `checkUTC.js` ×2, `recovery.js`, `user.js` ×3) and several handlers log `error.response.body`, so the rejection shape matters. Alternative not evaluated: bump `@sendgrid/mail` to 8.x. `overrides.axios: "$axios"` is valid npm syntax (it follows the direct dependency's spec, so bumping the direct entry is enough).
- **axios 1.20 impact on the platform:** 68 call sites, all plain `axios.get/post/put/delete` or `axios(config)`, no `axios.create()`; none of `baseURL`, `proxy`, `maxRedirects`, `socketPath`, `allowAbsoluteUrls`, `paramsSerializer`, `CancelToken`/`signal`, `validateStatus`, `responseType` is used, which is where most of the 1.14-1.20 hardening entries land. Smoke-test targets: the UberEats OAuth login (`platforms/management/platform/uberEats.js`, Node `form-data` `getHeaders()` plus `data: FormData`; `form-data ^4.0.6` already above axios 1.19's floor) and, for the concentrador, the shared interceptor. Axios 1.17.0 rejects malformed `http`/`https` URLs missing `//` with `ERR_INVALID_URL`; every URL here comes from runtime config, so a malformed config value would first surface as a hard error after the upgrade.
- **`Log.save` defect found on `ope` testing (2026-10-05), in `develop` too:** with `configs.mongoLogEnabled` true (read at runtime from the `orderRejClosedTime` database document; the code default and, per an unverified note, production is false) every `Log.save` stores only a FATAL `[INFRA/ERROR] Log.save failed` / `ValidationError: message: Path message is required`, because `api/src/utils/log.js` line 54 aliases `customDataAfter = customData` (since commit `b5f1053`, 2026-09-21, which replaced a copy) and the following `delete`s remove `message`/`category` from the original; stdout logging is unaffected. On `ope`, `765b5b4` added `message` fallbacks (hides the symptom, stores a wrong message and loses `category`) and `84c7efd` replaced the alias with `structuredClone(customData)` (restores both; throws `DataCloneError` for functions/sockets and on `null`; `{ ...customData }` would not). Neither was tested; the marker test is `Log.saveError(new Error('boom'), { message: '[TEST/ERROR] marker', category: 'INFRA' })` and checking the stored document. Not caused by the CVE changes.
- **Credentials:** hardcoded AWS credentials in `api/src/config/env/*.js` are [GITIN-2129](https://smartit-ar.atlassian.net/browse/GITIN-2129). A `staging.js:63-64` block that Trivy's secret scanner flagged on 2026-09-29 was a local uncommitted diff (absent from `origin/ope` and git history, present in a local image layer): revert it, rotation is only defense in depth. Literal `SENDGRID_API_KEY` strings in the concentrador env files are tracked there too.
- **Out of scope, time-bound:** AWS SDK v3 releases after the first week of January 2027 require Node 22 (`@aws-sdk/client-sqs`/`client-ssm` are `^3.0.0`), so a rebuild on a Node 20 image after that date resolves to a Node-22-only SDK; pin or move to Node 22 first. GITIN-2011 (`operations/events/20260908_gitin2011-ope-jenkins-scope/`): a `docker rmi` line in the platform pipeline's `post.always` was temporarily disabled to capture a `package-lock.json`; revert not confirmed.
- **Not done / unverified:** the smoke tests (UberEats login, SendGrid sends), the `lodash.set` parent, whether a newer npm than 11.20.0 clears `brace-expansion`/`undici`, the `express-jwt`/`jsonwebtoken`/`uuid` bumps, the SendGrid scripts (`scripts_sendgrid_client.sh`, `scripts_sendgrid_test.sh`) results, the unreviewed local diff in `api/src/platforms/provider/aws.js` of that clone, and the three remaining axioms (health, documentation, license) of the full `sp-npm-compliance` report.

## Test hygiene

A container started with an environment's config acts on that environment's resources: `src/index.js` calls `Aws.deadLetterSave()` on startup in every environment (`checkUTC` only in production), which receives from the `deadLetter` and `mainDeadLetter` queues and calls `deleteMessage` (`src/provider/aws.js` ~71-181); `testing.js` and `staging.js` use the same `DeadLetter.fifo`/`MainDeadLetter.fifo` URLs (`us-east-2`). Whether the 2026-10-05 `testing` and `serve:stg` runs deleted anything was not checked (the `serve:stg` run left no evidence). Image tags used: `concentrador-service:{branch}` for the original, `{branch}-{nodeversion}` for candidates; builds from `git archive` of the local branch.

## Related

- Investigations: `smartpedidos/events/20260908_gitin2000-axios-tar-upgrade/investigation.md` (GITIN-2000), `smartpedidos/events/20260908_gitin2002-platform-axios-tar-upgrade/` (platform sibling: `tar: latest`, an unjustified `apk update && apk upgrade` Dockerfile change, same open axios CVEs), `smartpedidos/events/20261005_gitin2117-concentrador-npm-update/` (GITIN-2117)
- Raw Trivy report: `smartpedidos/events/20260908_gitin2000-axios-tar-upgrade/data/trivy_vuln.json`

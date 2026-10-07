# Investigation: GITIN-2117 — [SP] Concentrador: Actualizacion de Paquetes NPM

**Jira:** [GITIN-2117](https://smartit-ar.atlassian.net/browse/GITIN-2117), child of parent [GITIN-2107](https://smartit-ar.atlassian.net/browse/GITIN-2107). Siblings: GITIN-2116 (Platform, reported "Bloqueado" in Jira), GITIN-2118 (BBOO, "Backlog"); 2117 is "En curso" (all as pasted by the user 2026-10-05).

**Status (2026-10-05, end of session):** in progress. Measured: original `ope` 39 HIGH/CRITICAL findings → 4 with the candidate (axios `~1.20.0`, npm 11.20.0 pin, `apk upgrade`) on both Node 20.20 and 22.20 (the 4 left are in npm's bundled packages). The candidate changes are **not yet applied on `ope`** (edits handed to the user as commands); smoke tests not run; `ops.md` not written. Side findings (staging credentials in git, DLQ-consuming startup) are in `../20260930_gitin2129-credentials-in-code/` and `../20261005_gitin2169-credentials-per-dev/`.

## Approach (carried over from GITIN-2116, per user: "same approach as 2116")

Source of the method: `smartpedidos/events/20260928_gitin2116-platform-npm-update/investigation.md` (+ its `scripts_n20_opt1.sh`, `data/Dockerfile_n20_opt1`). Goal is CVEs only (user scope for 2116, 2026-09-30). Steps as done for platform:
1. Measured baseline: build the unchanged `origin/develop` image (`--pull --no-cache`), Trivy `--scanners vuln --pkg-types os,library --severity HIGH,CRITICAL`, stamp node/npm/Alpine and installed `axios`/`mongoose`.
2. Candidate changes, built and scanned the same way from the same commit: (a) `axios` `~1.13.5` → `~1.20.0` (the `overrides.axios: "$axios"` follows it); (b) `RUN npm install -g npm@11.20.0` in both stages (clears 19 of 22 findings bundled in npm 10.8.2, incl. the CRITICAL `tar`, in the 2116 ladder); (c) `RUN apk upgrade --no-cache` in the final stage (OS layer 17/4 → 0 in 2116). `mongoose` stays on 7.8.x (user decision for 2116; `mongoose-unique-validator` stays `~4.0.1`) — assumed the same here, **not yet confirmed for 2117**.
3. Compare baseline vs candidate; smoke-test targets; `ops.md` only at convergence.

**Ground rules (user, 2026-10-05):** all tests are done on the local `ope` branch (committed tip as the source; the scripts use `git archive ope`, no fetch). Image tags: `concentrador-service:{branch}` for the original image (`:ope`), `concentrador-service:{branch}-{nodeversion}` for images with test changes (`:ope-20.20`). The candidate patch in `scripts_baseline_opt1.sh` is applied to a temp copy and is not committed to `ope`.

## Confirmed facts — concentrador clone (read 2026-10-05, working tree, no fetch)

- `smartpedidos/repo/dev-src-smartPedidos-concentradorService`: branch `develop`; `HEAD` and the local `origin/develop` ref both `0d6f158a` (2026-09-23). The local `origin/develop` ref was **not** refreshed this session (no `git fetch`), so newer remote commits would not be visible.
- `api/package.json` (develop): `axios ~1.13.5`, `mongoose ~7.8.7`, `mongoose-unique-validator ~4.0.1`, `express-jwt ^8.5.1`, `jsonwebtoken ^9.0.3`, `uuid 8.0.0`, `@sendgrid/mail ^7.7.0`; `overrides: { "tar": "latest", "axios": "$axios" }` already present.
- `api/Dockerfile` (develop): both stages `FROM node:20.20-alpine`; **no `npm install -g npm@…` pin, no `apk upgrade`**, and no CA-certificate block. The platform's `ope` Dockerfile has an extra `bot-security.smartfran.com` cert-chain/`ca-certificates`/`NODE_EXTRA_CA_CERTS` block (`data/Dockerfile_n20_opt1` in the 2116 folder); it is **not** part of the CVE changes, and whether the concentrador needs it is an open question — the candidate Dockerfile here deliberately excludes it.
- Per 2116: `express-jwt@8.5.1` and `jsonwebtoken@9.0.3` (the concentrador's versions) had 0 known CVEs in OSV (2026-09-25 `osv_current` pass); `axios@1.13.6` had 28 (10 HIGH); `uuid@8.0.0` 1 MODERATE (OSV). Those results came from the platform-side union sweep of registry/OSV data and were **not** re-measured with Trivy on a concentrador image.
- Reusable raw data (union of both services' 35 direct deps): 2116 `data/registry_*.json`, `data/osv_*.json`, `data/osv_current_*.json`, `data/dependency_cve_table_node20_20260925.md`, `data/axios_usage_survey_20260928.txt` (concentrador section: shared `httpClient.js` interceptor, ~80 call sites).

## Branch state after the user's update (read 2026-10-05, `git` read-only, no fetch)

- Clone is now checked out on `ope` at `f387973b` ("Merge branch 'develop' into ope", 2026-10-05, local); working tree clean. `origin/ope` is still `a5dddf8e` (2026-09-08), so that merge commit is **not pushed**.
- `develop` and the local `origin/develop` are both `0d6f158a` (2026-09-23): the pull brought no newer `develop` commit as far as the local ref shows (a fresh `git fetch` was not run in this check).
- `git log ope..develop` is empty and `git diff --stat develop ope` is empty: **`ope`'s tree is identical to `develop`** (the GITIN-2000 override commit's content was already on `develop`). Hence `ope` and `develop` have the same `package.json` (`axios ~1.13.5`, same `overrides`) and the same `Dockerfile` (no npm pin, no `apk upgrade`). The candidate changes are therefore not on `ope` yet.
- Consequence for the script: building the candidate from `origin/develop` + the patch is equivalent to building from `ope` + the patch. No script change needed.

## Measured results — baseline vs candidate, 2026-10-05 (`scripts_baseline_opt1.sh`)

Source: local `ope` @ `f387973b` (`data/commit_20261005.txt`), `git archive`, `--pull --no-cache`, Trivy `--scanners vuln --pkg-types os,library --severity HIGH,CRITICAL`, same as GITIN-2116. Images: `concentrador-service:ope` (original) and `concentrador-service:ope-20.20` (candidate = `package.json` `axios ~1.13.5` → `~1.20.0` + `RUN npm install -g npm@11.20.0` in both stages + `RUN apk upgrade --no-cache` in the final stage; diffs in `data/package_json_diff_20261005.txt`, `data/Dockerfile_{develop,opt1}_20261005`). Files: `data/summary_20261005.txt`, `data/cve_list_{develop,opt1}_20261005.tsv`, `data/trivy_vuln_{develop,opt1}_20261005.json`, `data/image_stamp_{develop,opt1}_20261005.txt` (the `develop` file names are the original/`:ope` image; the script keeps the label).

| | node · npm · Alpine | OS | Node packages | Total |
|---|---|---|---|---|
| original `:ope` | 20.20.2 · 10.8.2 · 3.23.4 | 4 HIGH (`libcrypto3`/`libssl3` 3.5.6-r0, CVE-2026-14456, CVE-2026-45447) | 35 (1 CRITICAL + 34 HIGH) | **39** |
| candidate `:ope-20.20` | 20.20.2 · 11.20.0 · 3.23.6 | **0** | **4 HIGH** | **4** |

- **Original, by origin (JSON `PkgPath`):** `axios@1.13.6` ×12 HIGH at `/usr/src/app/node_modules/axios` (the only application-tree finding); the other 23 are inside npm 10.8.2's own bundled packages (`tar@6.2.1` ×9 incl. the CRITICAL, `brace-expansion@2.0.1` ×5, `minimatch@9.0.5` ×3, `cross-spawn`, `glob`, `http-cache-semantics@4.1.1`, `ip-address`, `pacote`, `sigstore` ×1 each). Same bundled-npm set as the platform's ladder step A, plus `http-cache-semantics`.
- **Only one `axios` copy** in the original (installed tree: `axios@1.13.6 overridden`, `@sendgrid/client` → `axios@1.13.6 deduped`), so the nested 0.26.1 copy seen on the platform's `develop` (10 rows) does not exist here: the existing `overrides.axios: "$axios"` already collapses it. In the candidate everything resolves to `axios@1.20.0` (`npm ls` in `data/image_stamp_opt1_20261005.txt`), including `@sendgrid/client`.
- **Candidate residue (4 HIGH), all inside npm 11.20.0's bundled packages (`/usr/local/lib/node_modules/npm/node_modules/…`), none in `/usr/src/app`:** `brace-expansion@5.0.9` ×2 (CVE-2026-102276 fixed 5.0.10; CVE-2026-102278 fixed 5.0.11), `undici@6.28.0` (CVE-2026-19534 fixed 6.28.1), `http-cache-semantics@4.2.0` (CVE-2026-93748, Trivy lists no fixed version). Not checked whether a newer npm than 11.20.0 ships these fixes (same open point as 2116).
- **No `express-jwt`, `jsonwebtoken`, `lodash.set` or `mongoose*` findings** in either scan, consistent with the OSV-based expectation for the concentrador (`mongoose` resolves to 7.8.12). `uuid@8.0.0` MODERATE is below the HIGH/CRITICAL filter and not shown.
- Comparison with GITIN-2116 (platform, Node 20.20): original 51 → 6; here 39 → 4. The platform's extra 2 findings come from `express-jwt`/`jsonwebtoken`/`lodash.set` (not present in the concentrador) and the platform's second axios copy.
- Caveats: counts are HIGH/CRITICAL only; the Trivy DB is fetched at run time, so counts may drift; the original image's `apk info` list showed no `openssl` package while the candidate's did (not investigated); `axios@1.20.0` behaviour (httpClient interceptor, UberEats multipart, SendGrid) is untested — see smoke tests.

## Candidate on Node 22.20, 2026-10-05 (`scripts_n22_opt.sh`, image `concentrador-service:ope-22.20`)

Same source (`ope` @ `f387973b`, `data/commit_n22_20261005.txt`) and same three changes as the 20.20 candidate, only `FROM node:22.20-alpine` (both stages; `data/Dockerfile_n22_20261005`), `--pull --no-cache`, same Trivy flags. Stamp (`data/image_stamp_n22_20261005.txt`): node v22.20.0, npm 11.20.0, Alpine 3.22.6; installed tree `axios@1.20.0` (also under `@sendgrid/client`), `mongoose@7.8.12`, `mongoose-unique-validator@4.0.1`, `@sendgrid/mail@7.7.0`. Result (`data/summary_n22_20261005.txt`, `data/cve_list_n22_20261005.tsv`): **OS 0; Node packages 4 HIGH — the same four as on Node 20.20**, all in npm 11.20.0's bundled packages (`brace-expansion@5.0.9` ×2, `undici@6.28.0`, `http-cache-semantics@4.2.0`; same CVE IDs and fixed versions as above). **Total 4 on both Node 20.20 and 22.20.**

- Not measured: the concentrador's *unchanged* source on Node 22.20 (in GITIN-2116 that baseline was worse than on Node 20, 87 vs 51, because the `node:22.20-alpine` tag was an old un-rebuilt base; whether the same holds here was not checked), and any runtime check of the app on Node 22.20 (only the build and scan ran; no container was started on 22.20, so 22.20 compatibility of the code and dependencies is unverified).
- Within CVE scope, the Node major does not change the candidate's findings (same as GITIN-2116's result for the platform).

## Before / after — consolidated comparison (2026-10-05; from `data/summary_20261005.txt`, `data/summary_n22_20261005.txt`, `data/cve_list_{develop,opt1}_20261005.tsv`, `data/cve_list_n22_20261005.tsv` and the image stamps)

Same source (`ope` @ `f387973b`, tree identical to `develop`), `--pull --no-cache`, Trivy `--scanners vuln --pkg-types os,library --severity HIGH,CRITICAL`. "Before" = `concentrador-service:ope`; "after" = the candidate (axios `~1.13.5` → `~1.20.0`; `RUN npm install -g npm@11.20.0` in both stages; `RUN apk upgrade --no-cache` in the final stage) built on Node 20.20 (`:ope-20.20`) and on Node 22.20 (`:ope-22.20`).

| | Before | After, Node 20.20 | After, Node 22.20 |
|---|---|---|---|
| node · npm | 20.20.2 · 10.8.2 | 20.20.2 · 11.20.0 | 22.20.0 · 11.20.0 |
| Alpine | 3.23.4 | 3.23.6 | 3.22.6 |
| `axios` (single copy; `@sendgrid/client` follows it) | 1.13.6 | 1.20.0 | 1.20.0 |
| `mongoose` / `@sendgrid/mail` | 7.8.12 / 7.7.0 | 7.8.12 / 7.7.0 | 7.8.12 / 7.7.0 |
| OS findings | 4 | 0 | 0 |
| Application packages (`axios`) | 12 | 0 | 0 |
| npm's bundled packages | 23 | 4 | 4 |
| **Total** | **39** (1 CRITICAL + 38 HIGH) | **4** HIGH | **4** HIGH |

By package: OS `libcrypto3`/`libssl3` 3.5.6-r0 (CVE-2026-14456, CVE-2026-45447) 4 → 0; `axios@1.13.6` 12 → 0; npm-bundled `tar@6.2.1` 9 (incl. the CRITICAL) → 0; `brace-expansion` 5 (`2.0.1`) → 2 (`5.0.9`); `minimatch@9.0.5` 3 → 0; `http-cache-semantics` 1 (`4.1.1`) → 1 (`4.2.0`, no fixed version listed); `undici@6.28.0` 0 → 1; `cross-spawn`, `glob`, `ip-address`, `pacote`, `sigstore` 1 each (5) → 0. The Node major (20 vs 22) does not change the candidate's result. Reduction 39 → 4 (−35). The 4 left are all inside npm 11.20.0's own bundled packages (fixed versions listed for `brace-expansion` 5.0.10/5.0.11 and `undici` 6.28.1; whether a newer npm ships them was not checked). Caveats: the "after" images come from a patched copy of `ope` (the changes are not on `ope` yet); HIGH/CRITICAL only; the Trivy DB is fetched at run time; `axios` 1.20.0 has not been exercised (httpClient interceptor, UberEats login, SendGrid), only the startup of the `NODE_ENV=testing` container was seen.

## First container run of `concentrador-service:ope-20.20` — `NODE_ENV=testing` (2026-10-05 11:34, `data/container_logs_ope-20.20_20261005.txt`, `data/container_status_ope-20.20_20261005.txt`)

Started as `dev-src-smartPedidos-concentradorService-20.20`, `-p 3086:3086`, entrypoint default (`npm run serve` → `node dist/index.js`), `NODE_ENV=testing`, `SERVICE_NAME=concentrador-service`. Status line: `Up 11 seconds`, `0.0.0.0:3086->3086/tcp`. Log (two JSON lines): `[INFRA/INFO] database_connected` (host `cluster0-a4ki3.mongodb.net`, i.e. a remote MongoDB Atlas cluster, not a local one) at 14:34:33Z and `[INFRA/INFO] server_running` (`port 3086`, `env TESTING`) at 14:34:39Z. So the candidate image (axios 1.20.0, npm 11.20.0) boots, connects to its database and listens. This is a startup check only: no request was made, so the `httpClient` interceptor, UberEats login and SendGrid paths are still untested. The `serve:stg` run was requested afterwards; **no `*_stg_*` evidence files exist in `data/` as of 11:37**, so its outcome is not recorded here.

**Side effect of running the container (read in code 2026-10-05, not exercised/verified):** `src/index.js:18` calls `Aws.deadLetterSave()` on startup in every environment (`checkUTC` only in production). In `src/provider/aws.js` that function receives messages from the environment's `deadLetter` and `mainDeadLetter` SQS queues and calls `deleteMessage` on them (lines ~71–181). `testing.js` and `staging.js` use the same `DeadLetter.fifo`/`MainDeadLetter.fifo` URLs (`us-east-2`), so the testing and staging runs touched the same queues. Whether either run actually received/deleted messages was not checked. Test hygiene: a container started with an environment's config acts on that environment's queues.

## Concentrador-specific smoke tests (from 2116 notes; none run)

1. `src/utils/httpClient.js` interceptor: `config._t0` / `response.config` / `error.config` round-trip and `[PERF/INFO] http_response` fields (`duration_ms`, `status`, `method`, `url`) still populate on axios 1.20.x.
2. UberEats login (`controllers/branch.js:loginCountryUber`, multipart `FormData` via `axios(config)`).
3. SendGrid: on `develop` the nested `@sendgrid/client` is already forced onto axios 1.13.x by the existing override; send paths are `user.js` ×3 (password, recovery, signup), `recovery.js` ×1, `initialData.js` ×1, `checkUTC.js` ×2, with `error.response.body`-style logging. Behavior on axios 1.20.x not verified; checking production SendGrid failure logs since the override went live was suggested in 2116 and not done.

## Open questions / next steps

- (Done 2026-10-05) Baseline vs candidate measured — see "Measured results". Next: apply the same three changes on `ope` (currently only in the script's temp copy) and run the smoke tests.
- The `serve:stg` container run (handed over 2026-10-05) has **no recorded evidence**; the only container files are from the `NODE_ENV=testing` run. Whether a `serve:stg` container is running, and whether either run received/deleted DLQ messages, is unknown.
- Whether a newer npm than 11.20.0 clears the 4 remaining findings in npm's bundled packages (none fixable via `package.json`).
- Confirm with the user: `mongoose` stays 7.8.x for 2117; Node stays 20.20 (2116's Option 1 vs Option 2 / Node 22 decision is still open there).
- Whether the concentrador Dockerfile should get the CA-certificate block (outside CVE scope; likely not).
- `uuid@8.0.0` MODERATE and `lodash.set` presence in the concentrador tree: unmeasured.
- Jenkinsfile `--vuln-type os,library` for `dev-src-pedidos-concentrador` was edited locally during 2116 (uncommitted, see that investigation); its state for the pipeline is tracked there/GITIN-2011, not re-verified here.

## Related

- `smartpedidos/events/20260928_gitin2116-platform-npm-update/` (method, shared raw data).
- `smartpedidos/docs/cicd.md` (Node/Trivy/branch status per service).

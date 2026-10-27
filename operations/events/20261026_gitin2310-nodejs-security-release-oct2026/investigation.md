# Node.js security release 2026-10-21: exposure check (2026-10-26)

Status: closed (email sent and ticket closed, user-reported 2026-10-26). The open items below were not resolved by the closure.

Jira: [GITIN-2310](https://smartit-ar.atlassian.net/browse/GITIN-2310) "[OPE] Node vulnerability".

## Release (source: nodejs.org advisory, fetched 2026-10-26)
- Fixed: v26.12.1, v24.22.1, v22.23.4. 10 CVEs: 4 High, 3 Medium, 3 Low.
- High: CVE-2026-111497 (Brotli decoder out-of-bounds write via `node:zlib`; needs untrusted Brotli input), CVE-2026-105482 (`dns.resolve*()` NUL truncation), CVE-2026-105483 (fullwidth-digit IP, 26.x/24.x only), CVE-2026-106069 (leading-zero IPv4, platform-dependent resolver).
- Affected lines per CVE (advisory, re-fetched 2026-10-26; an earlier count of "9 of 10 for line 22 and all 10 for line 24" was wrong): line 22 is affected by 7 (not by CVE-2026-105483, CVE-2026-106070, CVE-2026-106071), line 24 by 8 (not by CVE-2026-106070, CVE-2026-106071), line 26 by all 10. The page gives no fixed version per CVE, only the three releases.
- Node 20 and 18 are not in any affected list. The advisory says EOL lines "are always affected" and gives no fix. No workarounds listed.
- The release also updates bundled ca-cert for the eMudhra intermediate CA compromise (see `operations/events/20261026_emudhra-ca-incident/`).
- Severity of the Brotli CVE differs between aggregators (one gives CVSS 9.2); the advisory itself says High.

## Our exposure
- Read on working tree, branch `develop` of each clone in `smartpedidos/repo/` (platformsService `9bd49f9`, concentradorService `01494650`, backOffice `bae5326`), not production:
  - platformsService `api/Dockerfile`: `node:20.20-alpine` (both stages).
  - concentradorService `api/Dockerfile`: `node:20.20-alpine` (both stages).
  - backOffice `app/Dockerfile`: `node:10-alpine` as builder (build stage only; not assessed further).
- First-party code: grep for brotli, zlib, `dns.resolve`, `dns.reverse`, `checkServerIdentity`, `randomUUID`, `--permission`, `--build-snapshot` found nothing in platformsService or concentradorService.
- Both services depend on `axios ~1.20.0`. Reverse check (2026-10-26): axios `v1.x` branch `lib/adapters/http.js` (read from GitHub, not the `1.20.0` tag) decompresses `content-encoding: br` with `zlib.createBrotliDecompress` unless `decompress === false`, and sets `Accept-Encoding` to `gzip, compress, deflate, br` by default without overwriting a caller-supplied value. Neither service sets `decompress` or `Accept-Encoding` (grep of first-party code), so the Brotli decoder is reached indirectly through axios. Not run against our services; installed version not checked (no lockfile, no `node_modules` in the clones). No IP-literal hosts in the code; hosts from SSM/env not seen. `mongodb+srv` is used in both `src/index.js` (driver DNS lookup from our own config). Trivy does not cover this: it reads apk and `node_modules` packages, not the runtime.
- SmartLoyalty and SmartCloud: .NET per repo docs. Node in tooling/pipelines (Jenkins agents, front builds) not surveyed.

## Update after pull (2026-10-26)
- `git pull --ff-only` on the three clones: all already up to date. HEADs now platformsService `e5dc0dc`, concentradorService `f361b020`, backOffice `bae5326` (the first two differ from the earlier read, so they were updated between the two reads).
- `origin/develop` `api/Dockerfile`: `node:20.20-alpine` in both services (unchanged).
- Deployed branch (user-reported 2026-10-26, not independently checked): production is deployed from `develop`, so the reference is Node 20 (`node:20.20-alpine`). `main` is stale and not in use (user-reported); it is not part of this analysis. The version inside the running production container was not checked.

## Node 20 -> 22 code impact (preliminary, develop branches, 2026-10-26)
Read: platformsService `e5dc0dc` and concentradorService `f361b020`, `api/` folders.
- Build: `npm run build` = clean + `babel src --out-dir dist` (`@babel/preset-env` without targets, `@babel/plugin-transform-runtime`); runtime is `node dist/index.js`. 121 source files (platform) and 97 (concentrador). Both Dockerfiles run `npm install -g npm@11.20.0` in both stages; npm 11 needs Node 20.17+ or 22.9+ (from memory, not verified), so 22.23.4 and 24.22.1 satisfy it.
- No lockfile and no `engines` field: each build resolves the dependency ranges of that day, so the dependency set a Node 22 build gets is not fixed.
- No test script in `package.json` (mocha, chai, nyc, rewire, sinon are devDependencies only), so the image build runs no tests and a Node 22 build passing says nothing about runtime behaviour.
- Grep of first-party code: none of `new Buffer`, `crypto.createCipher/createDecipher`, `fs.exists`, `fs.rmdir`, `punycode`, `util.is*`, `process.binding`, `domain`, import assertions (the APIs I know Node 22 removed). Present: `url.parse` in `controllers/_helpers.js` of both services (legacy API, still works; whether newer Node versions warn on it was not verified), `crypto.createHmac/createHash/randomBytes`, `https.createServer`, `URLSearchParams`, `process.on('unhandledRejection'/'uncaughtException')`.
- Not evaluated: compatibility of the dependencies with Node 22 (`winston-mongodb 5.0.0`, `node-cron ^2.0.3`, `mongoose ~7.8.7`, `sqs-consumer ^11`, `@sendgrid/mail ^7`, and in platform `express-jwt ^5.3.1` / `jsonwebtoken ^8.3.0`), and behavioural differences between Node 20 and 22 in HTTP/TLS defaults. The workstation has Node 18.19.1 via nvm; a build and start smoke test on Node 22 has not been run.

## Open items
- Confirm the production image of each service was built from the `develop` `FROM` (Node 20); the deployed branch is user-reported.
- Confirm axios Brotli handling in the installed version (read `node_modules` or the lockfile version plus its source).
- Node usage in Jenkins agents, Zabbix/Graylog tooling and other ops hosts.
- Brotli workaround (email item 5): from secondary sources only (Qualys and others); the advisory lists no workarounds. Inbound: strip `Content-Encoding: br`, `body-parser` `inflate: false`. Outbound (my inference, untested): `Accept-Encoding` limited to gzip/deflate, or axios `decompress: false`. Verify against the installed axios before recommending it as fact.
- Migration plan Node 20 -> 22.23.4 or 24.22.1 and test scope. Proposed in the email (not decided, not applied): `FROM` of `api/Dockerfile` in platformsService and concentradorService (two lines each) to `node:24.22.1-alpine` on `develop` only (from `node:20.20-alpine`). Tag existence on Docker Hub not verified. backOffice (`node:10-alpine` builder) left out.

## Deliverable
- Email to Operations (Spanish): sent, user-reported 2026-10-26. The corrected version is `email_ops_v2.md`; `email_ops.md` is the earlier draft and still has the wrong CVE counts per line (nine of ten for Node 22, all ten for Node 24). Which file was sent was not stated.

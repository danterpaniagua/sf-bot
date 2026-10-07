# Investigation: GITIN-2000 — Concentrador: Upgrade Axios y Tar

## Ticket
GITIN-2000 — https://smartit-ar.atlassian.net/browse/GITIN-2000
"[SP] Concentrador: Upgrade Axios y Tar"

Subtarea de GITIN-1306. Estado (2026-09-08, reportado por el usuario): En curso, asignada a Dante Paniagua. Hermanas: GITIN-1858 ("Correr Jenkins Platform", Finalizada), GITIN-1859 ("Correr Jenkins Concentrador", Descartado), GITIN-2002 ("Platform: Upgrade Axios y Tar", Backlog, sin asignar — ver `smartpedidos/events/20260908_gitin2002-platform-axios-tar-upgrade/`), GITIN-1957 ("Nuevo mensaje POST build a SmartPedidos team", Backlog).

## Context
Dependency upgrade prompted by a Trivy vulnerability scan report (report content not yet shared/reviewed in this session).

## Target
`concentrador-service`, `api/package.json`. Checked against the local read-only clone at `smartpedidos/repo/dev-src-smartPedidos-concentradorService/api/package.json` — this clone is for lookups only, never a deploy target; the actual change must land via PR in the real repo.

## Current state (checked 2026-09-08)

- `dependencies.axios` is already declared as `~1.13.5` in the clone's committed history. Last commit touching `package.json` on `develop`: `e7113196` "fix: filtro cloud" (2026-04-27) — unrelated to this ticket, so the `~1.13.5` pin predates GITIN-2000 and isn't itself evidence of the upgrade.
- The local clone has an **uncommitted** working-tree diff adding an `overrides` block:
  ```json
  "overrides": {
    "tar": "^7.5.21",
    "axios": "$axios"
  }
  ```
  This pins transitive `tar` to `^7.5.21` and forces all transitive `axios` resolutions to match the top-level `dependencies.axios` version (`~1.13.5`) via the `$axios` self-reference.
- This diff is **not committed** anywhere in the clone's git history. Per project convention (`smartpedidos/CLAUDE.md`), this clone is read-only and is never edited as part of a smartpedidos session — so this uncommitted change did not originate from a Claude session working in this repo. Not yet confirmed whether the real repository (not this clone) already has an equivalent change committed/PR'd, or whether this local diff is the only record of the intended fix so far.

## Trivy report findings (2026-09-08)

Report received as `Trivy_20Scan(4).zip`, artifact scanned: `dev-src-pedidos-concentrador:develop`, report generated 2026-09-08T12:24:36Z. Persisted as evidence: `data/trivy_scan.zip` (original) and `data/trivy_vuln.json` (extracted JSON, no PII/secrets — vulnerability metadata only).

**tar** — installed `6.2.1` (transitive), 9 CVEs (1 CRITICAL: `CVE-2026-59873` gzip-bomb DoS; 8 HIGH — path traversal / arbitrary file write / DoS variants). Highest fix version required across all 9: **`7.5.21`**. The package.json override (`"tar": "^7.5.21"`) satisfies this exactly — **tar CVEs are fully addressed** by the current change.

**axios** — the scan found axios at **two different installed versions** in the dependency tree:
- `0.26.1` (transitive, older path) — 10 HIGH CVEs. **Verified against the npm registry** (no lockfile in this local clone, so confirmed via published package metadata instead): `@sendgrid/mail@^7.7.0` → `@sendgrid/client@^7.7.0` → declares `"axios": "^0.26.0"`, matching the flagged `0.26.1` install exactly. This is the specific old/vulnerable install the `overrides.axios: "$axios"` block targets — it forces npm to resolve `@sendgrid/client`'s nested axios to the top-level `dependencies.axios` version instead of letting it pull its own outdated `^0.26.0` pin.
- `1.13.6` (transitive, newer path — newer than the `~1.13.5` pinned in `dependencies`, so `1.13.6` was presumably satisfied by that semver range before this ticket's change) — 10 HIGH CVEs

Across both, the fix versions required go up to **`1.16.0`** (e.g. `CVE-2026-44488` DoS via unenforced size limits, `CVE-2026-44494` MITM via prototype pollution, `CVE-2026-44496` client-side DoS via XSRF cookie regex — all fixed only in `1.16.0`/`0.32.0`). Several others need at minimum `1.15.1`/`1.15.2`.

**Finding — current change is insufficient for axios:** `dependencies.axios` is pinned to `~1.13.5`, and the `overrides.axios: "$axios"` self-reference forces all transitive axios resolutions to that same `~1.13.5` range (ceiling `<1.14.0`). This clears only `CVE-2025-27152` and `CVE-2026-25639` (both fixed by `1.13.5`) — it does **not** clear the remaining 8+ distinct axios CVEs that require `1.15.1`–`1.16.0`. To fully address the Trivy findings, `dependencies.axios` needs to move to at least `1.16.0` (or `^1.16.0`), not `~1.13.5`.

## Decision (2026-09-08)

Scope for GITIN-2000, for now, is the `overrides` block only:
```json
"overrides": {
  "tar": "^7.5.21",
  "axios": "$axios"
}
```
This fully resolves the `tar` CVEs. It does **not** raise `dependencies.axios` past `~1.13.5`, so the axios CVEs requiring `1.15.1`–`1.16.0` remain open. Reason given: impact radius of bumping `dependencies.axios` to `1.16.0` for `concentrador-service` is not yet known — deferred rather than bundled into this change.

**Correction:** the `~1.13.5` ceiling was initially attributed (per the user) to a `mongoose` dependency on axios. Checked against the npm registry: `mongoose@7.8.7`'s full dependency tree (`mongodb`, `mquery`, `bson`, `kareem`, `mongodb-connection-string-url`, `socks`) contains **no axios reference at all** — that attribution does not hold. The only confirmed axios consumer in this tree is `@sendgrid/client` (see Trivy findings above, `^0.26.0`), which the `overrides` block already handles. The real reason `dependencies.axios` isn't being bumped past `~1.13.5` in this ticket is the stated "unknown impact radius for dev" — not a hard dependency constraint from another package.

Not yet decided whether the axios version bump becomes a follow-up ticket or is tracked as a known gap against GITIN-2000.

## npm-bundled tooling findings (confirmed 2026-09-08, applies equally to GITIN-2002)

A fresh Trivy scan of `dev-src-pedidos-concentrador:ope` (2026-09-08 14:53:58, `data/trivy_vuln_ope_20260908_1453.txt`) after the `overrides` change confirms:
- `axios` behaves exactly as designed: only `1.13.6` reported now, the `@sendgrid/client`-transitive `0.26.1` duplicate is gone.
- `tar` is still `6.2.1` with all 9 original CVEs, plus new findings for `brace-expansion`, `cross-spawn`, `glob`, `ip-address`, `minimatch`, `pacote`, `sigstore` — all confirmed (via `PkgPath` in GITIN-2002's `data/trivy_vuln.json`, same root cause here) to originate from **npm's own bundled installation** at `/usr/local/lib/node_modules/npm/node_modules/...`, not this project's dependency tree. `package.json` overrides have no reach there — see GITIN-2002's investigation for the full technical writeup (Node 20.x's bundled npm is frozen at 10.8.2 across the entire LTS line; Node 22/24 improve but don't fully resolve `tar` either, and are a major-version migration, not a tag bump).
- Unlike GITIN-2002 (platforms-service), this scan has **no `express-jwt`, `jsonwebtoken`, or `lodash.set` findings** — confirmed via direct inspection of `api/package.json`: concentrador already declares `express-jwt: ^8.5.1` and `jsonwebtoken: ^9.0.3`, both past the fix thresholds those CVEs require (`6.0.0` and `9.0.0` respectively), and has no `lodash.set` dependency at all. The PM email's "additional platform-only findings" paragraph is correctly scoped to platforms-service only — this doesn't need the same caveat.

Decision on the npm-bundled `tar`/tooling findings: leaning toward documenting as an accepted, low-exploitability residual risk (not exercised by this image's `npm run serve` runtime path) rather than pursuing a Node major-version migration for it — not yet finalized.

## `tar` override — pin vs. floating to `latest` (2026-09-08)

Requirement: `tar` should always resolve to its newest published version, not a version pinned at ticket-creation time (avoiding a repeat ticket for every future `tar` CVE). Checked: `tar` is not imported directly anywhere in `api/src` (`grep` for `require('tar')`/`from 'tar'` — no hits) — it's a pure transitive dependency, most likely pulled in by a dev/build tool (`mocha`, `nyc`, `npm-run-all`), not the application itself.

Proposed change: use the `latest` dist-tag instead of a version range —
```json
"overrides": {
  "tar": "latest",
  "axios": "$axios"
}
```
Trade-off: `^7.5.21` only allows automatic minor/patch updates within major `7`; `"latest"` also pulls future **major** version bumps automatically on every fresh `npm install`, without review. Since the app has no direct API surface calling into `tar`, the main residual risk is a devDependency's own compatibility with an unreviewed major `tar` bump — not the application itself breaking.

## Impact radius of bumping `dependencies.axios` to `1.16.0` (checked against repo source, 2026-09-08)

**Call-site inventory** (`grep` across `api/src`): axios/`httpClient` (the `axios.create()` wrapper in `utils/httpClient.js`) is used in 6 files:
- `controllers/branch.js` — ~85 call sites, the overwhelming majority of usage, spanning every third-party delivery-platform integration (Rappi, Uber Eats, PediGrido, PedidosYa, SmartLoyalty/`sml`, generic branch webhook add/get/delete).
- `controllers/delivery.js` — 1 site, raw `axios.post(url, { delivery }, { headers })` (not via `httpClient`, no interceptors).
- `controllers/thirdParty.js`, `utils/initialData.js`, `utils/token.js`, `utils/checkUTC.js` — 1 `httpClient` call each; each of these also has an unused/dead `import axios from 'axios'` (real calls go through `httpClient`, not the raw import) — cosmetic, no functional bearing on the version bump.
- One raw `axios(config)` call (`branch.js:287`, `loginCountryUber`) using the Node `form-data` package (`dataSend.getHeaders()` + `data: dataSend`) — goes through axios's Node **http** adapter, not the fetch adapter.

**Checked axios's own changelog (v1.14.0 → v1.16.0, official "Notable Changes" callouts) against this codebase's actual usage:**

| Behavior change (introduced) | Applies here? |
|---|---|
| CRLF header-value rejection — throws on `\r`/`\n` in header values (v1.15.0) | Audited every `headers:`/`headersConfig` object in `branch.js` — all values are either static strings (`'application/json'`) or opaque third-party Bearer tokens (`tokenRappi`, `tokenUber`, `tokenSML`, `tokenPediGridoOpenClose`), never raw external free text. Risk: **low**. |
| Fetch adapter now enforces `maxBodyLength`/`maxContentLength` (v1.16.0) | This app runs on Node and never touches the fetch adapter (uses the default Node http adapter). **Not applicable.** |
| Proxy requests preserve user-supplied `Host` header; `NO_PROXY` normalization (v1.15.0/v1.16.0) | `grep` for `HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY`/`proxy:` across `api/src` — **no proxy configuration anywhere**. **Not applicable.** |
| Basic auth credentials in URL now URL-decoded (v1.16.0) | `grep` for `://user:pass@`-style URLs used with axios — the only hit was the MongoDB connection string (unrelated, not an axios call). **Not applicable.** |
| `parseProtocol` strictly requires a colon (v1.16.0) | All axios call sites use well-formed absolute URLs already in production use (`baseUrlRappi[...]`, `baseUrlPedigrido`, etc.) — none rely on loosely-parsed protocol strings. Risk: **low**. |
| FormData: `Content-Type` removed when no boundary is present (v1.15.1) | Fetch-adapter-specific fix; this app's one FormData use (`loginCountryUber`) goes through the Node http adapter via the `form-data` package. **Not applicable.** |
| CRLF stripping in multipart header values (v1.15.1) | Only touches malformed/malicious field values; `loginCountryUber`'s FormData fields (`client_id`, `client_secret`, `grant_type`, `scope`) are static config strings. Risk: **negligible.** |
| `mergeConfig`/`__proto__` hardening, `AxiosError.status` restoration (already in 1.13.5) | Already present in the currently-installed `1.13.5`/`1.13.6` — no incremental change from this bump. |

**Assessment:** no known axios behavior change between `1.13.5` and `1.16.0` appears likely to break this codebase's existing, correct usage patterns — proxy, fetch-adapter, and basic-auth-in-URL changes are all inapplicable since those features aren't used here, and the one broadly-applicable change (CRLF header rejection) only affects header values this code never sets from untrusted input. The actual risk is **surface area, not incompatibility**: ~85+ call sites in `branch.js` touch every external delivery-platform integration, so a version bump warrants regression testing per platform (Rappi, Uber Eats, PediGrido, PedidosYa, SmartLoyalty) in a non-prod environment before a production rollout, even though no specific code-level incompatibility was found.

## Open questions

- Confirm whether the real `concentrador-service` repo (not this local clone) already has this `overrides` block committed/PR'd, or if it's still pending.
- Confirm this is the only affected package.json (i.e. platforms-service isn't also flagged by the same Trivy report — the report scanned only `dev-src-pedidos-concentrador:develop`).
- Axios `1.15.1`–`1.16.0` CVEs remain unresolved after this change (see Decision above) — track as follow-up once impact radius of the version bump is assessed.

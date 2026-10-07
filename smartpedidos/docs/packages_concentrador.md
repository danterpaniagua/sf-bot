# concentrador-service — Dependency Reference (axios / tar)

Reference doc for `concentrador-service`'s `api/package.json` dependency tree, scoped to the axios/tar upgrade context (GITIN-2000). Verified directly against the npm registry (published package metadata), not assumed — see `smartpedidos/events/20260908_gitin2000-axios-tar-upgrade/investigation.md` for the full investigation this was extracted from.

## Current declarations (as of 2026-09-08)

```json
"dependencies": {
  "axios": "~1.13.5",
  ...
  "mongoose": "~7.8.7",
  "@sendgrid/mail": "^7.7.0",
  ...
},
"overrides": {
  "tar": "^7.5.21",
  "axios": "$axios"
}
```

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

**Conclusion:** the only two consumers of `axios` in this dependency tree are the application's own source (`api/src/utils/httpClient.js`, direct usage of `dependencies.axios`) and `@sendgrid/client`'s pinned `^0.26.0`. No other package in the tree depends on axios at any version, including `mongoose` — an earlier working assumption that `mongoose` constrained the axios version did not hold up under registry verification and was corrected in the investigation file.

## Trivy scan findings relevant to this tree (2026-09-08)

- **tar** — installed `6.2.1` (transitive), 9 CVEs (1 CRITICAL, 8 HIGH). Highest required fix: `7.5.21`. `overrides.tar: "^7.5.21"` resolves all of them.
- **axios** — two installed versions found:
  - `0.26.1` (via `@sendgrid/client`) — 10 HIGH CVEs.
  - `1.13.6` (via the direct `~1.13.5` range) — 10 HIGH CVEs, distinct from the `0.26.1` set.
  - Across both, fix versions required go up to `1.16.0`. The current `overrides.axios: "$axios"` only forces `@sendgrid/client`'s nested axios to match the top-level `~1.13.5` — it does not raise the ceiling itself, so CVEs requiring `1.15.1`–`1.16.0` remain open after this change. Raising `dependencies.axios` to `1.16.0` would need no third-party-package compatibility check in this tree (nothing else pins axios), so the only real impact radius is the app's own axios call sites (`httpClient.js` and any other direct usage).

## Related

- Investigation: `smartpedidos/events/20260908_gitin2000-axios-tar-upgrade/investigation.md`
- Raw Trivy report: `smartpedidos/events/20260908_gitin2000-axios-tar-upgrade/data/trivy_vuln.json`

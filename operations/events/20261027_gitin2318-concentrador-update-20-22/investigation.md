# [SP] Concentrador update 20->22 (opened 2026-10-27)

**Status:** not started. No change has been made to concentradorService.

Jira: [GITIN-2318](https://smartit-ar.atlassian.net/browse/GITIN-2318), "[SP] Concentrador update 20->22" (title as pasted by the user; Medium priority, Backlog, assigned to the user at the time of the paste). Parent: [GITIN-2315](https://smartit-ar.atlassian.net/browse/GITIN-2315) "Node 20 -> 22 upgrade". Sibling: [GITIN-2317](https://smartit-ar.atlassian.net/browse/GITIN-2317) (platformsService), which holds the decisions and evidence that apply here too.

The history of the work (why 22.23.4, the npm 12.2.1 choice, Trivy results, the Jenkins trigger finding) is in the parent's investigation (`operations/events/20261026_gitin2315-node-20-to-22-upgrade/investigation.md`); read it first.

## Scope
`smartpedidos/repo/dev-src-smartPedidos-concentradorService`, `api/Dockerfile` and `api/package.json`; the pipeline job `ope/concentrador`.

## State (read 2026-10-26, branch `develop`, HEAD `f361b020`, clean)
- `api/Dockerfile`: `node:20.20-alpine` in both stages, `npm install -g npm@11.20.0` in both, final stage `RUN npm install --only=production`, preceded by `COPY --from=base /usr/src/app/package*.json .` (same structure as platformsService, so the same four edits apply).
- `api/package.json`: `body-parser ^1.18.3`, `express ^4.18.2`, `express-jwt ^8.5.1`, `jsonwebtoken ^9.0.3`, `axios ~1.20.0`; no lockfile.
- A Trivy list pasted by the user (source not stated) matches this service as it is on `develop`: npm 11.20.0 bundled copies (`brace-expansion` 5.0.9, `http-cache-semantics` 4.2.0, `undici` 6.28.0) and `body-parser` 1.20.8, without `express-jwt` 5 or `jsonwebtoken` 8; not confirmed which job produced it.
- The `ope` concentrador jenkinsfile has the same placeholder webhook token as the platform one.

## Proposed change (not applied; the same as platformsService)
Both `FROM` to `node:22.23.4-alpine`; both npm installs to `12.2.1`; final-stage install to `npm ci --omit=dev`; `body-parser` floor `^1.20.9`. Not tested on this service: build, start, dependency compatibility with Node 22, the SQS consumer path.

## Open questions / next steps
- Apply the edits on a branch of the user's choice (platformsService used `ope`) and read the diff back.
- Build locally and scan with Trivy; run a start test with the staging configuration (it reads its configuration from files in the repo, which may hold secrets: do not push an image built from it).
- Check whether this service reads AWS credentials the same way (`aws.js` equivalent) before any local run.

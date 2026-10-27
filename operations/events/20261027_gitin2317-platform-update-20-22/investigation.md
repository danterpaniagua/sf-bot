# [SP] Platform update 20->22 (opened 2026-10-27)

**Status:** in progress. The Dockerfile change is committed on branch `ope`; local build, versions and start test done; Jenkins `ope` job not triggered by the push yet.

Jira: [GITIN-2317](https://smartit-ar.atlassian.net/browse/GITIN-2317), "[SP] Platform update 20->22" (title as pasted by the user; Medium priority, Backlog, assigned to the user at the time of the paste). Parent: [GITIN-2315](https://smartit-ar.atlassian.net/browse/GITIN-2315) "Node 20 -> 22 upgrade". Sibling: [GITIN-2318](https://smartit-ar.atlassian.net/browse/GITIN-2318) (concentradorService).

The history, evidence and decisions of the work so far were written in the parent's investigation (`operations/events/20261026_gitin2315-node-20-to-22-upgrade/investigation.md`) while this subtask did not exist yet; read it first. This file only holds what belongs to platformsService.

## Scope
`smartpedidos/repo/dev-scr-smartPedidos-platformsService`, `api/Dockerfile` and what the Node 22 change touches (`package.json`, the pipeline job `ope/platform`).

## State (summary of the parent's sections; read 2026-10-26/27)
- Branch `ope`, HEAD `b76ef87`, equal to `origin/ope` (checked with `git ls-remote` on 2026-10-27; pushed by the user): `90730a6` (Dockerfile: both stages `FROM node:22.23.4-alpine`, `npm install -g npm@12.2.1`, final stage `npm ci --omit=dev`) plus three commits with the same message "fix(api): sube el piso de body-parser a ^1.20.9" (`a950b94`, `7774e4f`, `b76ef87`, 16:42 to 16:57 UTC-3 on 2026-10-26) whose net effect since `90730a6` is one line, `body-parser ^1.18.3` -> `^1.20.9` (the second added a line to `package.json` and the third removed one; I did not read what they were).
- Uncommitted: `api/src/platforms/provider/aws.js` (static AWS credentials from the config when present) and `api/src/config/env/staging.js` (**must not be committed**: tracked secrets plus an AWS key block). Neither is on the remote.
- `ops.md` written on 2026-10-27 at the user's request ("2317 ops") from this state; it is in Spanish and does not name the sibling pipeline-definitions repo or local paths, per the root `CLAUDE.md`.
- Local image evidence: Node `v22.23.4`, npm `12.2.1`, `body-parser` 1.20.9; Trivy 4 HIGH findings left: `undici` 6.29.0 bundled in npm (CVE-2026-109869, accepted until npm bundles 6.29.1 or later), `express-jwt` 5.3.3, `jsonwebtoken` 8.5.1, `lodash.set` 4.3.2.
- `serve:stg` start test on Node 22: boots, connects to the staging MongoDB, `server_started`; errors seen (PedidosYa 401, Rappi 404) not shown to be Node-related; SQS path and inbound requests not exercised.
- Jenkins `ope/platform` (`sf-devops/jenkins/SF-PEDIDOS/jenkinsfiles/ope/dev-src-pedidos-platform.jenkinsfile`): the `GenericTrigger` token is the placeholder `REPLACE_WITH_NEW_GENERIC_WEBHOOK_TOKEN`; a push to `ope` did not start a build (build #17 was a manual run).

## Open questions / next steps
- Commit the `package.json` change on its own (without `staging.js`), in the user's own working copy.
- Replace the placeholder token and add the GitHub webhook for the `ope` job, then check the Generic Webhook Trigger Log after a push.
- Smoke test with inbound requests and the SQS path; a saved build log and a Trivy scan of exactly the committed Dockerfile.
- Decide on `express-jwt`/`jsonwebtoken` major bumps and `lodash.set`.
- Get the change to `develop` by the normal flow (production is deployed from `develop`, user-reported).

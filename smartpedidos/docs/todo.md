# SmartPedidos — TODO

Open work of this project. One entry per piece of work, each with the tickets it spans. When an item is done, record the resulting fact in the doc it belongs to (`infrastructure.md`, `cicd.md`, `mongodb_indexes.md`) and delete the entry here. State below was read from the docs and event folders as last recorded, not re-measured.

## 1. Scaling and the queue-age Lambda

Tickets: [GITIN-2170](https://smartit-ar.atlassian.net/browse/GITIN-2170) (redesign) and its child [GITIN-2171](https://smartit-ar.atlassian.net/browse/GITIN-2171) (Lambda logs in Graylog, built), related GITIN-2162, GITIN-2211, [GITIN-1783](https://smartit-ar.atlassian.net/browse/GITIN-1783). Events: `events/20261005_gitin2170-platform-mejorar-escalado/`, `events/20261005_gitin2171-lambda-monitoring/`.
- `IntegrationLambdaEcsTaskProd` fires on the alarm's OK transition too, has no tiers or scale-down, 7 of 23 invocations timed out at 3 s, and its role is broader than needed. The redesign (proposed tiers 5-10 / 15 / 20) waits on the user: unit of the thresholds (seconds or minutes), whether the numbers are ECS desired counts, and who scales down. Test on the staging counterpart before touching production.
- Proposed in GITIN-1783, not created: an additive step-scaling policy on a `Maximum` CPU alarm for `platform-service`.
- Verify whether the Infrastructure-as-Code definition of the scalable target holds `MinCapacity` 5 (a later apply would revert the 10 set on 2026-10-17).

## 2. Platform tasks dropping after the exit handlers

Tickets: GITIN-2222, [GITIN-2248](https://smartit-ar.atlassian.net/browse/GITIN-2248), GITIN-2240, GITIN-2229. Events: `events/20261014_gitin2222-ecs-reinicios-avisos-sns/`, `events/20261017_gitin2248-platform-contenedores-caidos-20261016/`. Closed by the user on 2026-10-20 (dips normalized after `643d17f` and PR #141, user-stated, not re-measured). Open: re-measure Container Insights `RunningTaskCount` vs `DesiredTaskCount` since 2026-10-20; the H5 circular-structure logging cause and whether a task should keep running after an uncaught exception (Development); the FATAL alert's apparent double Chat notification (actions 11 and 12, unverified per event); the concentrador FATAL alert cannot fire until concentrador-service logs a FATAL line (GITIN-2240).

## 3. PediGrido outage hardening (Development)

Ticket: GITIN-1783. Not implemented: a timeout on the shared `httpClient` of concentrador-service, an overlap guard on `checkOfflinePOSpedigrido`, a cap on its fan-out; platform-service's own 20 s axios timeout is exceeded by 0.3 % of PediGrido calls (mechanism unidentified).

## 4. Branch 5713 and orders that never reach a POS

Ticket: [GITIN-2161](https://smartit-ar.atlassian.net/browse/GITIN-2161). Event: `events/20261002_5713-no-new-orders-sqs/`. Open: order `5637871` is still `PENDING` with no SQS message ever sent (handling is a state-changing decision with the team); the previous agent version before 2026-10-01T19:23Z; whether a skipped push ever logs; reasons of the `REJECTED` orders since 2026-10-03. Related: a stuck message in a per-branch queue is invisible to the queue-age alert (store 4719, `events/20261018_cac-tienda-4719-pedido-en-cola/`); the per-branch dead-letter redrive only after `maxReceiveCount` 1000 (~50 h).

## 5. Grido export pipeline

Tickets: GITIN-1872 (parent) and subtasks. Open: the unredacted PII in `smartfranbkp/news/` (as last stated 2026-09-01); whether the GITIN-1980 historical normalization finished (last note 2026-09-01 shows a batch in progress); `customer.dni` is sent without a confirmed Legal/PM sign-off (deliberate, per Grido's request); Grido's type and `$date` conventions rest on one sample; the permanent 2026-08-16 21:00-24:00 gap is unrecoverable; per-day memory in `grido-redacted-etl` is mitigated by 4096 MB, not by streaming; the Chat bridge Lambda is deployed but unsubscribed.

## 6. Jenkins / CI

Tickets: GITIN-2023, GITIN-2024. Event: `events/20260910_backoffice-jenkins-sonarqube-onboarding/`. Open: capture a passing backOffice build log; confirm the GenericTrigger webhook token is set on the GitHub repo; resolve whether the job loads `customScripts@main` from the `SF-LOYALTY` folder instead of `SF-PEDIDOS`.

## 7. MongoDB indexes

Tickets: GITIN-2006, GITIN-2013 ("Bloqueado" in Jira, reason unknown), [GITIN-2062](https://smartit-ar.atlassian.net/browse/GITIN-2062). Dev fixes of GITIN-2013 not confirmed done (`news.js` unfiltered `countDocuments()` → `estimatedDocumentCount()`; `branch.js` `/branches/search` filter before the `$lookup`s); the unbatched `clearCollection` deletes; a log line in the `login` function that writes `branchSecret[0]` on a failed login (commit `01733d90`, possible partial-credential log, flagged once, not actioned). Open (`mongodb_indexes.md`): drop or keep `branches.alreadyClosedRappi_1_lastGetNews_1` (created, not used by the planner); `ordertimesavgcrons.avg_calculatedAt` has no index (low priority); the `ordertimes.branch_1` size discrepancy and the `branches` document-count discrepancy.

## 8. Graylog indexer failures from the application logs (Development)

Ticket: GITIN-1854 (`operations/events/20260813_platform-service-branch-id-unknown-mapping-error/`), related GITIN-2208. Not applied when last checked 2026-09-18: `log.js` `_stdout` of platforms-service and concentrador-service only drops `undefined`, so the sentinel strings `"unknown"` (`msg_branch_id`, `msg_rest_status_code`) and `"error"` (`msg_rest_status`, from `httpClient.js:35`) reject whole documents; fix in `log.js` plus a sweep of `?? '<string>'` fallbacks. `platform.js` `validateNewOrders` (lines 648 and 661) logs the whole raw webhook payload and leaks a customer email into the "Indexer failures" page (draft Dev email, not sent when recorded). `enviarEstadoPedidosYa` returns HTTP 400 for ~570 branches every half hour from 10:00 daily (cause open).

## 9. npm updates (concentrador, platform, backoffice)

Platform-specific open items (GITIN-2116, `packages_concentrador.md` → "platform-service"): bump `express-jwt` (5.3.3, auth bypass fixed in 6.0.0) and `jsonwebtoken` (8.5.1, fixed in 9.0.0) after checking the JWT usage, and `uuid 8.0.0`; trace the parent of `lodash.set@4.3.2` (no fix); smoke tests of UberEats login and SendGrid sends on axios 1.20 (the `@sendgrid/client` 0.26 → 1.x override is untested; check SendGrid failure logs of the concentrador since its override went live); the `Log.save` alias defect (`api/src/utils/log.js` line 54, in `develop`; the marker test and whether `develop` gets the fix); revert the disabled `docker rmi` line in the platform pipeline (GITIN-2011); decide Node 22 before January 2027 (AWS SDK v3); check that `--vuln-type os,library` is in the `develop` Jenkinsfiles. The platform's local diff in `api/src/platforms/provider/aws.js` of the clone was never reviewed.

Tickets: GITIN-2000 (concentrador), GITIN-2002 (platform), GITIN-2116, GITIN-2117, parent GITIN-2107; GITIN-2187 (ESLint). Events: `events/20260908_gitin2000-axios-tar-upgrade/`, `events/20261005_gitin2117-concentrador-npm-update/`, `events/20261007_gitin2187-eslint-test/`. Open (`packages_concentrador.md`, `cicd.md`): the smoke tests of axios 1.20 (`httpClient` interceptor, `loginCountryUber`, SendGrid sends) never ran, nor did the first Jenkins `develop` builds with the new Dockerfile and the `ESLint Report` stage; the four findings left in npm 11.20.0's bundled packages (is a newer npm available?); the `ope` branches diverge from `develop` in platform and concentrador (and backoffice `ope` lacks the README move); backoffice still builds on `node:10-alpine`; whether the platform's unjustified `apk update && apk upgrade` change was kept; the concentrador Dockerfile has no CA-certificate block (platform does); the Jenkins job migration to "Pipeline script from SCM" (one job first, `pruebas`); the SonarQube badge tokens in READMEs; decide whether to import all ~1,971 ESLint style warnings or only defect rules. The 2026-10-05 `testing` and `serve:stg` container runs may have deleted dead-letter messages (not checked).

## 10. Re-read the `mongoAllCollections` Lambda configuration

Function `mongoAllCollections-to-s3-CFN-ScheduledMongoToS3-MRO2H3EOSN6E` (`us-east-1`). Whether its model set includes `news` is contradictory: the source pasted in GITIN-1970 has no `news`, the copy read directly in GITIN-2013 lists it. Read the live function code/configuration, then fix the S3 export section of `infrastructure.md` and the note in `mongodb_indexes.md`. Runtime is also unconfirmed.

## 11. MercadoPago `token_fetch` loop against Cloud `WalletCredentials`

Tickets: [GITIN-2220](https://smartit-ar.atlassian.net/browse/GITIN-2220) (related GITIN-2209, GITIN-2211, GITIN-2218). Event: `events/20261013_gitin2220-platform-walletcredentials-hits/`. The user stated the fix was deployed on 2026-10-14; not verified: which change, the commit, the effect. Measure with the GITIN-2211 `token_fetch` count per minute on the SmartPedidos Graylog and the Business `WalletCredentials` lines per hour on the SmartCloud Graylog; check whether the two dominant merchants still dominate and whether 204 still does. Open: whether Concentrador also calls the endpoint, what the notification loop does with a skipped element (affects order flow), the four call sites not read, the two failing accounts' re-authorization (Cloud side, GITIN-2209).

## 12. Documentation leftovers

Events not yet validated against the docs: `20261013_gitin2211` (re-check),  `zabbix_alert_matrix.md` unchecked. `tech-debt.md` is an empty append-only log (created because `smartpedidos/CLAUDE.md` pointed to a missing file).

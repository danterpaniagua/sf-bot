# Investigation — 20261015_gitin1477-mejora-continua-logs

**Status:** in progress (reading of the sp-logs project; no change proposed or applied)

## Ticket
- GITIN-1477 "[SP] Mejora Continua Logs" (https://smartit-ar.atlassian.net/browse/GITIN-1477). Its scope and description were not provided; this file is built from the `sp-logs` project (`~/Documentos/git/smartfran/sp-logs`, separate repo with its own skills) where the user did the log improvements for platforms-service and concentrador-service on a branch named `sp-logs`. No mention of "1477" was found in the sp-logs docs or scopes (grep), so the link between that Jira ticket and each sp-logs document is the user's statement, not something written in the docs.
- Why it matters now: GITIN-2222 (restarts of platform-service tasks) and its sub-task GITIN-2229 (Zabbix alert on FATAL) touch the same logging code; the Dev proposals of those tickets are tied to this one by the user.

## What the sp-logs project contains (read 2026-10-15)
- `scopes/versions.md`: branch versions, platforms-service `v1.0.0` (2026-06-16: `console.log` -> `Log.save`, category/level/`[CATEGORY/LEVEL]` message format, inline PERF timing in rappi, mercadoPago, rapiboy, thirdParty) and concentrador-service `v1.1.0` (2026-06-26: merge sp-logs -> develop through `sp-logs-temp`, conflicts solved in `index.js`, `log.js`, `branch.js`; `httpClient.js` interceptor for PERF).
- `docs/logging-standards.md`: levels DEBUG/INFO/WARN/ERROR/FATAL; FATAL is "system-level failure: DB unreachable, queue consumer crashed, no recovery possible"; categories INTEGRATION/ORDER/INFRA/PERF; the only level-assignment row that uses FATAL is "Internal service unreachable | INFRA | FATAL". There is no rule about process-level handlers (`unhandledRejection`, `uncaughtException`) or about exiting the process.
- `docs/tech-debt.md`: open items CGAP-003 (silent catch in `orderRejClosed`), CGAP-006 (5,571-line `branch.js`), CGAP-007, CGAP-008, CGAP-009 (concentrador) and PGAP-001 to PGAP-003 (platform). None is about process-level handlers or FATAL.
- `docs/jira/`: five event folders (concentrador log improvements with SUB-000 to SUB-010, platform log findings, exposed credentials in logs, console.log migration of concentrador, platforms log improvements in sp-logs with SUB-011).
- Clone state (local refs, no `git fetch` done): in `repo/concentrador-service`, `sp-logs` has 15 commits that `origin/develop` does not have; in `repo/platforms-service`, `sp-logs` is an ancestor of the local `develop`. That platforms clone does not have commit `b56d403` (the fatal handler of GITIN-2222): it is stale relative to the clone in `smartpedidos/repo/`.

## Findings that connect to GITIN-2222 / GITIN-2229
1. **Process-level handlers were not part of the log improvements.** In the sp-logs branches of both services (`api/src/index.js`) `process.on('unhandledRejection', ...)` and `process.on('uncaughtException:', ...)` still use the old `CustomError` form, and the second event name has a trailing colon (never fires). `FATAL` exists as a valid level in both `Log` classes but the handlers do not use it. Concentrador `develop` (`01494650`) has the same handlers.
2. **`JSON.stringify(error)` in `Log._stdout` comes from sp-logs work.** It appears with commit `32883ab` (2026-06-23, "normaliza serialización de errores en _stdout y corrige rejects en validateNewOrders"), the SUB-011 entry of `docs/jira/22-06-2026_platforms-log-mejoras-sp-logs/..._events.md`. That entry was written to stop `"[object Object]"` in `logerrors` and the missing `error` field in Graylog. The GITIN-2222 crashes show it failing with circular structures (socket objects), 23 of 63 FATAL rejections. Whether the branch was ever tested with an error that carries a socket was not found in the docs.
3. **The `SanitizeHeaders` misuse is NOT from the sp-logs work; the earlier GITIN-2222 text was wrong.** In the sp-logs clone `sanitizeHeaders.js` is a function module (`cecb08f`, 2026-05-20) and the calls are correct there. In the `smartpedidos/repo` clone (`develop`, `dfb668e`) the module was changed on 2026-09-21 (`a22c9c7` static method, `43b4023` renamed to class `SanitizeHeaders`, `225f850` `Log` updated), and 17 call sites in 7 files still call the default import as a function (`controllers/rappi.js:61`, `pedidosYa.js` x5, `controllers/mercadoPago.js` x2, `controllers/uberEats.js`, platform `mercadoPago.js` x3, platform `uberEats.js` x4, `utils/tokensCloud.js`). GITIN-2222 `ops.md`, `email_devs.md` and `investigation.md` were corrected for this on 2026-10-15 (they said 2026-05-20 and 6 call sites).
4. **Platform's `Log.save('FATAL', ...)` in `index.js` (`b56d403`, 2026-10-08) uses the FATAL level that the standard defines,** but applies it to every unhandled rejection and then exits. The standard reserves FATAL for failures with no recovery; whether an unhandled rejection from a third-party call qualifies is a design question not addressed in the docs.

## Proposed items for the Dev team (candidate, for GITIN-2229 `ops.md`, not decided)
- Concentrador-service: log `[INFRA/FATAL]` from the process-level handlers with the Platform schema (`msg_level=FATAL`, `msg_category=INFRA`, `msg_service=concentrador-service`) and fix `'uncaughtException:'`; exit or not is Dev's decision (in Platform the exit turned each rejection into a task stop).
- Add to `docs/logging-standards.md` a row for process-level handlers (what level, whether to exit) so Platform and Concentrador follow the same rule.
- Treat `Log._stdout` serialization as a defect to fix (safe serialization for circular structures) in both services; check concentrador's `log.js` for the same pattern (not checked).
- Fix the 17 `sanitizeHeaders` call sites (already in GITIN-2222).

## Open questions
- Scope and state of GITIN-1477 itself (description, sub-tasks, whether SUB-011 belongs to it).
- Was the SUB-011 normalization merged to `develop` in a build that is deployed, and does concentrador's `log.js` contain the same `JSON.stringify(error)`? (read `api/src/utils/log.js` in the concentrador `develop` clone.)
- Whether the 15 sp-logs commits in the concentrador clone are already in `origin/develop` (needs `git fetch`, which the user runs).
- Whether the handler commit `b56d403` (platform) was written on top of the sp-logs standard or separately; its exact PR was not identified.

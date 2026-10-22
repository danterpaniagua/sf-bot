# GITIN-2259 — [SP] Platform: Deuda Tecnica

**Ticket:** https://smartit-ar.atlassian.net/browse/GITIN-2259 (title as given by the user on 2026-10-20; the ticket body, parent and scope were not read)
**Status (2026-10-20): closed by the user.** `ops.md` was written once and handed over to paste as is. Open items stay with Development, not tracked here: integration and deployment of `logs22` (H3), the `process.exit` policy (H4), the interceptor migration (H1), structured `order_id` (H2); the Definitions of Done, risks and efforts are SRE proposals not validated with Development.

## Starting material
- Platform items in `smartfran/sp-logs/docs/tech-debt.md`: PGAP-001, PGAP-002 (open) and PGAP-003 (resolved). Verification of 2026-10-20 against platform `develop` `643d17f`: `outputs/tech-debt-verification-platform.md`.
- PGAP-001 (found 10-06-2026): 39 `const t0` timers in 6 provider files (`thirdParty.js` 16, `rapiboy.js` 10, `mercadoPago.js` 6, `rappi.js` 5, `pedidosYa.js` 1, `uberEats.js` 1), 46 `[PERF/INFO]` sites, no `httpClient.js` or interceptors in `api/src`. Remediation in the entry: adopt the interceptor pattern from concentrador (effort Medium).
- PGAP-002 (found 22-06-2026): 30 "Platform Communication Error" sites plus 1 "Platform Auth Error" (`app.js`) that embed `order.id` in the message text. The entry says 28 sites, but its own per-file list adds up to 30. Remediation: structured `order_id` field and `[INTEGRATION/ERROR]` message (effort Medium).
- PGAP-003 (found 22-06-2026): resolved by commit `649b426` (2026-06-22); four log sites carry `order_id`.
- Related, not a register item: `logFatalAndExit` in platform `index.js` had `process.exit(1)` commented out on 2026-10-19 (commit `643d17f`); context in `smartpedidos/events/20261017_gitin2248-platform-contenedores-caidos-20261016/investigation.md`. Whether it is deployed was not checked.
- The roadmap (GITIN-2236) proposes these items as story (C) "platform logging debt" (`smartpedidos/events/20261015_gitin2236-roadmap-smartpedidos/investigation.md`).

## Open questions
- Which items go into GITIN-2259 (PGAP-001, PGAP-002 only, or also new findings)?
- Does the ticket carry the Dev/SRE split? PGAP-001 and PGAP-002 change provider code (Dev code, per the project's labels).
- Why `pedidosYa.js` and `uberEats.js` have `[PERF/INFO]` logs (5 and 4) with a single `t0` each was not looked at.

## Update 2026-10-20 (later): state when `ops.md` was handed over
- `ops.md` written and handed to the user to paste as is; later findings go here only.
- H1 origin: the `const t0` timers come from the first PERF logging commits (`afc296a` 2026-05-12, `2a154f0` 2026-06-08, more in `38f0a4c` 2026-09-08); not traced: which change left `pedidosYa.js` and `uberEats.js` with one `t0` each.
- H3: branch `logs22` (remote, one commit `2b7ebb1` 2026-10-20 on top of `develop` `643d17f`, fetched to `FETCH_HEAD` only) removes `JSON.stringify(error)` from `Log._stdout`, wraps entry building in try/catch with a fallback line, and wraps the whole `Log.save` body in try/catch (no more rejections from the fallback `create` calls). Cost: an `error` without `.message` no longer shows in the `error` field. Review/merge/deploy status unknown. A `logs22` branch also exists in concentrador (`c30858d8`), not read.
- Sonar/ESLint `indent` issue on that branch: with `indent` 4 only line 91 fails (one extra space in a comment); the issue seen on line 46 was not reproduced and the Sonar ESLint config is not in the repo. Dismissed by the user on 2026-10-20 (no further work).
- Definitions of Done (formerly "success condition"), risk and effort (items 1, 2, 5) in `ops.md` are SRE proposals, not validated with Dev.
- Register verification: concentrador in `smartfran/sp-logs/docs/tech-debt-verification-concentrador.md`, platform in `outputs/tech-debt-verification-platform.md`; PGAP-003 moved to the register's Resolved section; the sp-logs repo changes are uncommitted.

## Update 2026-10-20 (later): `logs22` merged into `develop`
- Read on `origin/develop` after a fetch: `logs22` (`2b7ebb1`, 2026-10-20 09:48 -03:00) was merged by PR #141 as `9bd49f9` (09:53 -03:00). The only change is `api/src/utils/log.js`, identical to the branch; `process.exit(1)` in `logFatalAndExit` is still commented out (`643d17f`). So H3 (logger, the `JSON.stringify(error)` on circular structures) is fixed in `develop`; the user states it went live today (not verified here). The text above that says "not integrated into `develop`" is out of date. `ops.md` of this ticket is written once and was not changed.
- Related status email (GITIN-2222 and GITIN-2248): `smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/status-report-20261020.md`.


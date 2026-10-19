# Investigation — 20261016_gitin2240-concentrador-alerta-fatal

**Status:** applied and read back (C1 apply 11:52 UTC, 2026-10-16): item 54612, trigger 26929 (High) and trigger 26930 (no data, Average) created on `Zabbix server`, macro 7477; the item read 0 with no error and both triggers value 0 / state 0 after 75 s. The user reports the ticket as finished; `ops.md` written 2026-10-16 (not yet pasted to Jira). Not seen: a real alert, because Concentrador logs no FATAL line yet (Dev change, GITIN-1477, tech-debt item CGAP-010).

## Ticket
- [GITIN-2240](https://smartit-ar.atlassian.net/browse/GITIN-2240) "[SP] Concentrador: Alerta FATAL Zabbix", child of GITIN-2222 (user-stated; the ticket body was not seen). Sibling: GITIN-2229 (Platform). Analysis of why Concentrador has no FATAL signal: `smartpedidos/events/20261015_gitin2229-alerta-fatal-zabbix/investigation.md`, section "Concentrador-service: no FATAL signal to alert on" (C7).

## Request (user, 2026-10-16)
- "create a rule for implementing same 2229 in 2240. no matter if we dont have any logs".

## Design (copy of the GITIN-2229 rule, C5 v2 there)
- Host `Zabbix server` (10084). HTTP agent item `graylog.concentrador.fatal.count` (1 min, Graylog `search/universal/relative`, range 300 s, query `msg_level:FATAL AND msg_service:"concentrador-service"`, Basic auth with the secret macro `{$SML_GRAYLOG_API_KEY}`, JSONPath `$.total_results`).
- Trigger High "Graylog: Concentrador FATAL detected" (`last > {$GRAYLOG.CONCENTRADOR.FATAL.MAX}`, macro 0) and trigger Average "Graylog: Concentrador FATAL check without data" (`nodata` over the existing `{$GRAYLOG.NODATA.WINDOW}` = 10m, shared with GITIN-2229 and not deleted by the rollback).
- Tags from the start: the Platform routing tags with `service=concentrador-service`, `friendlyname` and `SVC_FRIENDLYNAME` = "Graylog FATAL Concentrador" (card titles), and `env=PROD` (dashboard and the action that notifies Operaciones on Chat and Telegram). For Platform these were added later (C8, C9 there).
- The field-qualified query is the form that worked for Platform (free text combined with `AND` returns HTTP 500 on that Graylog). That the same form works with `msg_service:"concentrador-service"` is checked by the dry run (it also reads Graylog when `SML_GRAYLOG_API_KEY` is exported; the key goes to curl on stdin).

## What to expect
- Concentrador logs no `[INFRA/FATAL]` today (GITIN-2229 C7: 223 FATAL lines in 7 days, all Platform; tech-debt item CGAP-010 in sp-logs). The item should return 0 and the High trigger should not open until Dev adds the FATAL logging (GITIN-1477). The no-data trigger covers Graylog or token failures. Whether the real FATAL line will carry `msg_service=concentrador-service` and `msg_level=FATAL` is an assumption taken from Platform's schema; to check once Dev ships it.

## Open
- C1 `dry` and `apply` are done (see "Dry runs" and "Apply"). Open: the Dev FATAL logging in concentrador-service; no end-to-end test of the High trigger (no FATAL line exists; it would need a temporary macro of -1, which changes state).
- Test of the High trigger end to end is not planned (it would need a FATAL line or a temporary macro of -1, which changes state); decide with the user.

## Dry runs (data/c1-dry-log-20261016T112826Z.txt, data/c1-dry-log-20261016T112923Z.txt)
- First run: guards passed (host `Zabbix server` manual and active, secret macro `{$SML_GRAYLOG_API_KEY}` type 1, `{$GRAYLOG.NODATA.WINDOW}`=10m, key free). The Graylog check printed HTTP 200 with an empty `total_results`: the saved bodies were 0 bytes because the script did not send `Accept: application/json` (the earlier GITIN-2229 scripts and the Zabbix item do). The check proved nothing; script fixed to send the header and to print the body size.
- Second run: HTTP 200, 314 bytes, `total_results=0` for 300 s and 604800 s. Valid JSON, so the field-qualified query `msg_level:FATAL AND msg_service:"concentrador-service"` is accepted; 0 matches the 7-day count of 0 Concentrador FATAL lines (all 223 are Platform, GITIN-2229 C7). Planned tags: scope=availability, service=concentrador-service, action=GCHAT, scope=OPE, scope=SP, SVC_FRIENDLYNAME and friendlyname "Graylog FATAL Concentrador", env=PROD.

## Code check (concentrador clone, branch `develop`, HEAD `01494650`, clean tree; platform clone `develop` `dfb668e` for comparison; read 2026-10-16)
- `api/src/utils/log.js`: `VALID_LEVELS` includes `'FATAL'`; `Log._stdout` writes a JSON line with `service` (env `SERVICE_NAME`), `level`, `category`, `message`, so a FATAL line needs only `Log.save('FATAL', error, {category:'INFRA', message:'[INFRA/FATAL] ...'})`. `container-definitions-prd.json` sets `SERVICE_NAME=concentrador-service`, which matches the `msg_service` value in the query (Graylog already shows `msg_service=concentrador-service`, GITIN-2229 C7).
- Stdout logging can be switched at run time: `checkforcedCronHorarios` (every 30 s, `controllers/branch.js` lines 493-514) reads a config document and calls `Log.configure({consoleLogEnabled, mongoLogEnabled})`; its current value was not read. Concentrador already sends many lines to Graylog, so console logging is probably on.
- The handlers in `index.js` (lines 46-55) build a `CustomError`, which logs `[INFRA/ERROR] custom_error` (level ERROR); the second handler is registered as `'uncaughtException:'` (trailing colon) and never fires. Platform's pattern to copy: `logFatalAndExit()` (`index.js` lines 114-134 there) logs FATAL and then `process.exit(1)`; whether Concentrador should exit is a Dev decision. Recorded as tech-debt item CGAP-010 in the `sp-logs` repository (`docs/tech-debt.md`, not committed).

## Apply (data/c1-apply-log-20261016T115237Z.txt, run folder data/c1-run-20261016T115237Z/, 2026-10-16 11:52 UTC)
- Graylog check in the same run: HTTP 200, 314-byte body, `total_results=0` for 300 s and 604800 s. Created: macro 7477 (`{$GRAYLOG.CONCENTRADOR.FATAL.MAX}`=0), item 54612 (`graylog.concentrador.fatal.count`, HTTP agent, 1 min), triggers 26929 "Graylog: Concentrador FATAL detected" (High) and 26930 "Graylog: Concentrador FATAL check without data" (Average). Tags as planned, `env=PROD` included.
- Read back 75 s later: item state 0, last value 0, no error (so the request to Graylog with the secret macro works); both triggers value 0, state 0, no error. Rollback: `scripts-c1.sh rollback data/c1-run-20261016T115237Z`.
- Process note: the apply was run before the assistant looked for its log; an earlier statement in the conversation that it had not been run was wrong (no file was checked at that moment).
- The user states the ticket is finished (2026-10-16). The alert exists and is idle until Concentrador logs FATAL; `ops.md` not written (waiting for the user's signal).


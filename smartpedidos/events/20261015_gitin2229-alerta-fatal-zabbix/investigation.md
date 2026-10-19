# Investigation — 20261015_gitin2229-alerta-fatal-zabbix

**Status:** item 54607 and triggers 26919/26920 created and verified by real alerts (FATAL problem and recovery events reached the Chat and the Telegram group through `ope_notify`); card tags applied (C8); `env=PROD` applied (C9) and read on the discovered ECS triggers (C10); `ops.md` written 2026-10-16 (not yet pasted to Jira, user decides); the 19:04-19:33 UTC gap is under investigation in GITIN-2222; the Concentrador alert was created in GITIN-2240 and waits for Dev logging (GITIN-1477).

## Ticket
- GITIN-2229 "[SP] Alerta FATAL Zabbix" (https://smartit-ar.atlassian.net/browse/GITIN-2229), sub-task of GITIN-2222 (proposed action 9 there: a Zabbix alert based on the count of `[INFRA/FATAL]` messages from Graylog). Parent folder: `smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/`.

## Why (from GITIN-2222)
- platform-service exits with code 1 after `[INFRA/FATAL] unhandled_rejection` (`api/src/index.js`, commit `b56d403`). Graylog had 63 such messages in 14 h (GITIN-2222 C5, `data/c5/`); the FATAL line carries the error text and stack (`error`, `error_stack`), which the ECS "running below desired" alert (GITIN-2222, Zabbix action 11) does not.
- The ECS alert uses 10-minute CloudWatch averages (stock template), so a quick replacement may not show; the Graylog FATAL line appears at the moment of the exit.

## Known facts relevant to the design
- SmartPedidos Graylog: `sf-monitoreo.smartfran.com:9000`; the REST API accepts `GET /api/search/universal/absolute` with a token (`-u "$SML_GRAYLOG_API_KEY:token"`), as used in GITIN-2222 C5 (`scripts/scripts-c5.sh`). The FATAL messages are JSON with `level`, `category`, `message` (`[INFRA/FATAL] unhandled_rejection`), `error`, `error_stack`; the C5 query matched the term in the message.
- Zabbix 6.0.32 on the same host (`docs/graylog_infrastructure.md`); routing already exists for scope OPE+SP and `action~GCHAT` (action 11, GITIN-2222).
- Zabbix API token pattern and the apply pattern with snapshot/rollback: `ope-zabbix` skill.

## Decision (user, 2026-10-15): option 1, HTTP agent item with the Graylog API key ("via API KEY")

## Design options
1. **HTTP agent item** in Zabbix calling the Graylog REST search (relative range 5 min, query on the FATAL message and platforms-service, `limit=1`) and reading the total with JSONPath preprocessing; trigger when the count > 0. Needs the Graylog token as a secret macro. No script on the host.
2. **UserParameter + bash script** on the Zabbix host that calls the same API (the pattern the `ope-zabbix` skill documents for custom healthchecks). Adds a script to maintain on the host; keeps the token out of Zabbix macros.
3. **Graylog side:** an Event Definition with a notification (HTTP/e-mail) — outside Zabbix, so it would not go through the Zabbix routing; ruled out for now because the ticket asks for a Zabbix alert.
- Open design points: the query (all FATAL of platform-service, or only `unhandled_rejection`/`uncaught_exception`); threshold and window (any FATAL in 5 min vs. N); the host that owns the item (`smartfran-pedidos-production` is discovered and rejects manual items; likely the `Zabbix server` host or a new host); severity and tags (`scope=OPE`, `scope=SP`, `action=GCHAT`); behavior when Graylog is unreachable (a "no data" trigger).

## C1 and C2 results (`data/c1-run-log-20261015T131119Z.txt`, `data/c2-run-log-20261015T131138Z.txt`; 2026-10-15 ~13:11 UTC)

- Graylog relative-range counts (query -> 5 min / 1 h / 14 h): `"[INFRA/FATAL] unhandled_rejection"` 0 / 0 / 62; `"[INFRA/FATAL]"` 0 / 0 / 62; `level:FATAL AND "platforms-service"` 0 / 0 / 0; `"[INFRA/FATAL]" AND "platforms-service"` returned HTTP 500 for all three ranges (cause not found). The two text queries give the same 62, so in that window every FATAL line was an `unhandled_rejection` (service filter not applied in the second, so other services' FATAL lines would be included if they existed; none seem to). The 5-minute and 1-hour counts were 0 at the run time, consistent with no exit in the last hour (last mail at 09:23Z).
- `level:FATAL` returned 0 even with 62 FATAL lines present: the `level` field in Graylog is probably not the application level (hypothesis: Graylog's own syslog `level`; to be read in C3). Use the text query.
- The success response of the search has `total_results` (read as a number in the shell); the keys of a message could not be captured because the C1 shape file came from the failing 500 query (error body keys `message,type`). C3 captures the shape from the working query.
- C2: Zabbix hosts: `Zabbix server` (10084, manual, accepts items); `Zabbix server` already has many HTTP agent items (MongoDB Atlas, interval `{$MONGO_ATLAS_UPD_INT}`), so HTTP agent items on this host have a precedent. Macro `{$SML_GRAYLOG_API_KEY}` exists on `Zabbix server` as **type 0 (plain text), not secret**; the value is readable in the frontend and in the API for any user with host access. It should be recreated as secret text (type 1) before use. No other Graylog macro exists; the global macros with TOKEN in the name are mostly type 0.

## C3 results (`data/c3-run-log-20261015T131318Z.txt`)

- A successful search response has the keys `built_query,decoration_stats,fields,from,messages,query,time,to,total_results,used_indices`; `total_results` is a number (62 for `"[INFRA/FATAL]"` over 14 h). A message has the fields `ServiceName`, `msg_service`, `msg_level`, `msg_category`, `msg_message`, `msg_error`, `msg_error_stack`, `msg_timestamp`, `message`, `source`, `timestamp`, `streams` and AWS/GL2 metadata; there is no `level` field, which explains why `level:FATAL` returned 0 (the application level is `msg_level`).
- The 500 error is `{"type":"ApiError","message":"Missing search type result!"}` for every query written as free text with an `AND` (quoted or not, either order, `+` form). The only variant that returned 200 was `message:"[INFRA/FATAL]" AND "platforms-service"` (62). Why a bare free-text term combined with `AND` fails was not investigated (Graylog 'Missing search type result' on the universal search; the field-qualified form works).
- User decision: the alert is for Platform only (add the service name to the query). C4 (`scripts/scripts-c4.sh`) reads the values of `ServiceName`, `msg_service`, `msg_level`, `msg_category` of the FATAL lines and tests field-qualified queries, to choose one that does not depend on free text.

## C4 results (`data/c4-run-log-20261015T131751Z.txt`) and the chosen query

- All 62 FATAL lines in the 14 h window have the same metadata: `ServiceName=PlatformService`, `msg_service=platforms-service`, `msg_level=FATAL`, `msg_category=INFRA`.
- Field queries (14 h): `msg_level:FATAL` 62; `msg_level:FATAL AND msg_service:"platforms-service"` 62; `message:"[INFRA/FATAL]" AND msg_service:"platforms-service"` 62; the same with `ServiceName:"platforms-service"` gives 0 (that field holds `PlatformService`, not `platforms-service`).
- Chosen (user: Platform only): `msg_level:FATAL AND msg_service:"platforms-service"`. It matches every FATAL level line of the service, not only `unhandled_rejection` (the 62 are all of that kind today).
- `scripts/scripts-c5.sh` (written, syntax-checked, not run): dry/apply/rollback. Creates on host `Zabbix server` (10084) two host macros (`{$GRAYLOG.PLATFORM.FATAL.MAX}`=0, `{$GRAYLOG.NODATA.WINDOW}`=10m), an HTTP agent item (`graylog.platform.fatal.count`, 1 min, range 300 s, Basic auth with `{$SML_GRAYLOG_API_KEY}`/`token`, JSONPath `$.total_results`), a High trigger (`last > max`) and an Average no-data trigger, both with tags scope=availability, service=platform-service, action=GCHAT, scope=OPE, scope=SP (action 11). Guard: the macro must exist and be secret (type 1); today it is plain text (C2).

## First apply failed (C5, `data/c5-apply-log-20261015T132130Z.txt`, run folder `data/c5-run-20261015T132130Z/`)

- At 13:21 UTC the macros `{$GRAYLOG.PLATFORM.FATAL.MAX}` (id 7449) and `{$GRAYLOG.NODATA.WINDOW}` (id 7450) were created on `Zabbix server`; `item.create` failed with `Invalid parameter "/headers/1": a character string is expected`. No item or trigger was created (`created-ids.json` has empty item and trigger lists).
- C6 (`data/c6-run-log-20261015T132245Z.txt`, read from an existing Atlas HTTP item): in Zabbix 6.0.32 `headers` is an object `{"Accept": "..."}` (not a list of name/value pairs); `query_fields` was empty in that item, so the non-empty format was not seen. The script v2 puts the search parameters in the URL (URL-encoded, `query_fields` empty) and reuses the two existing macros if their values are the expected ones (0 and 10m).

## Applied (C5 v2, `data/c5-apply-log-20261015T132408Z.txt`, run folder `data/c5-run-20261015T132408Z/`, 2026-10-15 ~13:24 UTC)

- Created on `Zabbix server`: item 54607 (`graylog.platform.fatal.count`, HTTP agent, 1 min), triggers 26919 "Graylog: Platform FATAL detected" (High) and 26920 "Graylog: Platform FATAL check without data" (Average); macros 7449 and 7450 reused from the first attempt. Rollback: `scripts-c5.sh rollback data/c5-run-20261015T132408Z`.
- 75 s after the creation: item state 0 (normal), last value 0, no error, so the request to Graylog with the macro in the username field worked (an authentication failure would have left the item unsupported with an error). Both triggers value 0 / state 0 / no error. Value 0 is consistent with no FATAL line in the previous 5 minutes (C1 showed the last exit at ~09:23Z); it was not cross-checked against the Graylog search at that moment.
- Not yet verified end to end: no problem has fired, so the delivery of a trigger to the Operaciones Chat through action 11 has not been seen (same pending point as GITIN-2222). A test would be to set `{$GRAYLOG.PLATFORM.FATAL.MAX}` to -1 on the host for a few minutes (the trigger fires with count 0) and then set it back to 0; this changes state and was not proposed to the user yet.

## Concentrador-service: no FATAL signal to alert on (user asked for the same alert; C7, `data/c7-run-log-20261015T133417Z.txt` is empty, the output is in `data/c7/concentrador.txt`)

- Graylog fields for concentrador: `ServiceName=ConcentradorService`, `msg_service=concentrador-service` (448 of 500 sampled messages in 15 min; Platform 52).
- FATAL level lines in 7 days: 223, all `PlatformService` / `platforms-service` / category INFRA; none from concentrador. The wildcard queries (`msg_service:*oncentrador*`) returned HTTP 500 and the script stopped there (section 3 not captured).
- Code (concentrador clone, branch `develop`, HEAD `01494650`, read from the working tree): `api/src/index.js` lines 46-51 register `process.on('unhandledRejection', ...)` and `process.on('uncaughtException:', ...)` (the second event name has a trailing colon, so it never fires); no `process.exit` and no `[INFRA/FATAL]` log call were found by grep in `api/src`. So concentrador does not log FATAL and its unhandled rejections do not end the process the way Platform's do; a FATAL-count alert for it would never fire. Its handler content was not read in detail.

## Proposed actions for ops.md (user, 2026-10-15)

- (Dev) FATAL logging in concentrador-service, tied to GITIN-1477 "[SP] Mejora Continua Logs" (https://smartit-ar.atlassian.net/browse/GITIN-1477): make its process-level handlers (`api/src/index.js` lines 46-51) log an `[INFRA/FATAL]` line with the same schema Platform uses (`msg_level=FATAL`, `msg_category=INFRA`, `msg_service=concentrador-service`), and fix the event name `'uncaughtException:'` (trailing colon, never fires). Whether the process should also exit is a Dev decision (in Platform the exit is what turned each rejection into a task stop, GITIN-2222).
- (SRE) Once concentrador logs FATAL: create the same Zabbix item and triggers for `msg_service:"concentrador-service"` (copy of C5). Until then the alert would never fire (C7).
- Done by SRE in this ticket (goes under "Acciones Tomadas", not "propuestas"): item 54607 and triggers 26919/26920 for Platform; macros 7449/7450.
- (done 2026-10-16) `ops.md` written from this file. Open: the end-to-end Chat test of the High trigger was superseded by real FATAL alerts that reached the Chat.

## Update 2026-10-15 (afternoon): first real alert and the card tags
- The alert worked end to end: trigger 26919 "Graylog: Platform FATAL detected" (High) opened at 12:33:08 -03:00 and recovered at 12:38:08 (5 min, the query window); two notifications through action 11 and media type 38 to user 9, status 1 sent (ECS investigation C24, `smartpedidos/events/20261014_gitin2222-ecs-reinicios-avisos-sns/data/c24-run-log-20261015T163353Z.txt`). The time matches a Platform dip at 12:33 in the per-minute CloudWatch data.
- Defect seen in the recovery notice: the title read `El servicio {EVENT.TAGS.friendlyname} se ha normalizado`, because the triggers have no lowercase `friendlyname` tag (the Chat problem title uses `SVC_FRIENDLYNAME`, the recovery title `friendlyname`; GITIN-2156 convention). `scripts/scripts-c8.sh` (written, syntax-checked, not run) adds both tags (value "Graylog FATAL Platform") to triggers 26919 and 26920 and the ECS prototype 26911 (GITIN-2222), with dry/apply/rollback.
- The recovery notice does not say whether the problem notice arrived; only the recovery text was pasted.

## More real alerts (user paste, 2026-10-15; times -03:00)
- Two more FATAL alerts (trigger 26919, High) with both notices received in the Chat space shown as "Alertas SmartFran, Aplicación": problem 14:34:08, resolved 14:39:08 (5 min); problem 14:55:08, resolved 15:00:08 (5 min). With the first one (12:33:08-12:38:08) that makes three alerts in about 2.5 hours; each lasted exactly the 5-minute query window, so each corresponds to FATAL lines in one 5-minute window (the number of lines per alert is not in the notice). Whether each matches a Platform task stop was not checked (the CloudWatch per-minute data pulled so far ends at 16:23 UTC = 13:23 -03:00).
- Confirmed: the **problem** notice is delivered too (earlier only a recovery notice was pasted), through the same action 11.
- Both notices show the card-title tags unresolved: the problem title reads `Servicio {EVENT.TAGS.SVC_FRIENDLYNAME} degradado` and the recovery text `El servicio {EVENT.TAGS.friendlyname} se ha normalizado`. The triggers have neither tag; `scripts/scripts-c8.sh` (dry / apply / rollback; adds both to 26919, 26920 and the ECS prototype 26911) has still not been run.

## Card tags applied (C8, `data/c8-apply-log-20261015T180227Z.txt`, run folder `data/c8-run-20261015T180227Z/`, 2026-10-15 18:02 UTC)
- Triggers 26919 and 26920 now carry `friendlyname` and `SVC_FRIENDLYNAME` = "Graylog FATAL Platform" (existing tags kept); the ECS prototype 26911 carries both with the value `ECS tasks {#AWS.ECS.SERVICE.NAME}`. Read back from the API in the same run. Rollback: `scripts-c8.sh rollback data/c8-run-20261015T180227Z`.
- Not yet seen: a real notice with the resolved titles (the next FATAL alert shows it). The discovered ECS triggers (26915, 26916) receive the tags at the next discovery pass of the service rule (up to about 3 hours); the ECS alert itself is still blocked by the margin macro (1000) and by the recipient's missing read permission on `Templates/Cloud` (GITIN-2222 investigation).

## Next steps
- Macro `{$SML_GRAYLOG_API_KEY}` created by the user on host `Zabbix server` (stated by the user; type not yet read back: C2 lists macro names and types without values; the name check there is for `GRAYLOG`/`TOKEN`). Item host therefore = `Zabbix server` (manual host, accepts items).
- Done (written, not run): `scripts/scripts-c1.sh` (Graylog relative-range counts for four candidate queries, 5 min / 1 h / 14 h, keeps only counts) and `scripts/scripts-c2.sh` (Zabbix: hosts, existing HTTP agent items, macro names with GRAYLOG/TOKEN, no values).
- C1 (read-only, local Graylog API): confirm the query returns the expected FATAL count for a 5-minute relative range and the field/streams to use; check what the total looks like in the response for JSONPath.
- C2 (read-only, Zabbix API): where the item should live (hosts, macros available, an existing Graylog-related host).
- Then decide option 1 vs 2 with the user.

## Update 2026-10-15 19:30 UTC
- The FATAL problem event of 19:04:08 UTC (recovered 19:12:08) generated no notification, unlike the five earlier events (last notified 17:55:08 problem / 18:00:08 recovery). Events were not suppressed and carry the same routing tags (GITIN-2222 C35). The probable cause is outside this ticket's objects (user group of the recipient, GITIN-2222 C37/C38).
- Not yet seen: a notice with the resolved card titles (C8 applied at 18:02 UTC; the notices of 12:33-15:00 -03:00 had unresolved titles). (`ops.md` was a stub at that time; written on 2026-10-16.)

## Dashboard tag env=PROD (user, 2026-10-15)
- The user asked that the new ECS triggers and the Graylog FATAL triggers carry the tag `env:PROD` so they show in the dashboard. The existing convention is tag `env` with value `PROD` (193 triggers have it, from the tag inventory of GITIN-1961). The tag is not used by any action condition (the same inventory), so adding it does not change routing.
- `scripts/scripts-c9.sh` (written, syntax-checked, not run) adds `env=PROD` to triggers 26919 and 26920 and to the ECS prototype 26911 (the discovered triggers 26915 and 26916 inherit it at the next discovery pass; a direct update is also attempted and reported). The healthcheck triggers of GITIN-2239 (26921-26928) were not requested and are not included. Dry / apply / rollback.


### C9 result (applied 2026-10-15 19:36 UTC; data/c9-apply-log-20261015T193602Z.txt, run folder c9-run-20261015T193602Z)
- `env=PROD` applied and read back on triggers 26919 and 26920 (Graylog FATAL) and on prototype 26911 (ECS). 26919 already had it, so its list was unchanged.
- Discovered triggers 26915 and 26916 rejected the direct update ("Cannot update tags for a discovered trigger"), as expected; read-back shows `env=PROD` absent on both. They get it from prototype 26911 at the next discovery pass (up to ~3 h). Same pending as the card tags (`friendlyname`/`SVC_FRIENDLYNAME`). Not yet verified.
- Rollback: `scripts-c9.sh rollback <c9-run folder>`.

## Update 2026-10-15 20:35 UTC
- C10 (data/c10-read-log-20261015T193855Z.txt, 19:38 UTC): `env=PROD`, `friendlyname` and `SVC_FRIENDLYNAME` still absent on discovered triggers 26915 and 26916 (2 minutes after C9). Not re-read since.
- Indirect sign that the ECS trigger now carries `env=PROD`: the ECS events 716906 (problem 20:20:03 UTC) and 716909 (recovery 20:30:04 UTC) matched action 12, whose only condition is tag `env`=`PROD` (operations event `20261015_env-prod-notificar-operaciones`, C5). Inferred from the action match, not read from the trigger; `scripts-c10.sh` would confirm it (and the two card tags), still to run.
- Graylog FATAL events seen by the new recipient: 716908 (recovery 20:23:10 UTC) and 716910 (problem 20:30:08 UTC, "FATAL en los ultimos 5 min: 3"); the user reported the 716910 message in the Telegram group "Alertas SmartFran" (pasted, data/message-pasted-graylog-fatal-event-716910.txt in the operations event; the media used is confirmed by C5: Telegram sent at 20:30:10 for 716910). The FATAL recovery card of 19:33:08 UTC was seen in the Operaciones Chat (data/chat-recovery-graylog-fatal-20261015.txt).
- Still not seen: the problem-open card of the 19:28:08 UTC FATAL event (sent while user 9 was in group 14, delivery unknown).

## C10 re-run (2026-10-16 11:10 UTC; data/c10-read-log-20261016T111008Z.txt, data/c10-triggers-20261016T111008Z.json)
- Triggers 26915 and 26916 (discovered, host `smartfran-pedidos-production`) now have `env=PROD`, `friendlyname` and `SVC_FRIENDLYNAME` (all true), against all false at 19:38 UTC the day before (data/c10-read-log-20261015T193855Z.txt). They inherited the tags from prototype 26911 at a later discovery pass. This replaces the earlier inference based on the matches with action 12; it was read directly.
- FATAL alerts after the previous update, seen as Telegram messages (operations event, data/telegram-messages-pasted-20261015.txt): 716945 (problem 00:18 UTC, recovery 00:25) and 716947 (problem 00:26, recovery 00:31). Zabbix's alert list was not re-read for them.

## Jira ticket for the Concentrador alert (user, 2026-10-16)
- The user gave [GITIN-2240](https://smartit-ar.atlassian.net/browse/GITIN-2240), "[SP] Concentrador: Alerta FATAL Zabbix", with GITIN-2222 as parent. Its body was not seen; going by the title it is the ticket for the Concentrador item above (C7: no FATAL signal to alert on until Dev adds FATAL logging, GITIN-1477), but that match is not confirmed. No event folder was created for it: the work there is waiting for Dev, and this event's section holds the analysis. Create `20261016_gitin2240-concentrador-alerta-fatal` only if the user asks.

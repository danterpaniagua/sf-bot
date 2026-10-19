# Investigation — 20261015_gitin2236-roadmap-smartpedidos

**Status:** drafted and parked (user, 2026-10-15): roadmap table with 12 Stories, per-Story tasks, project, Dev requirement and priority; estimates (SRE days, Dev excluded) and warning included; customer-facing content none; PM email drafted, not sent per the chat; review by the PM pending

## Ticket
- GITIN-2236 "[SP] Roadmap Smartpedidos" (https://smartit-ar.atlassian.net/browse/GITIN-2236). Requested by the SmartPedidos PM through the user on 2026-10-15; the text of the request was not provided beyond the ticket title.

## Constraints already known
- Emails and documents for PMs: no time estimates (root and sp-sre-output rules), no code, no internal resource names, no flattening of hedged findings into certainty. A roadmap therefore has to be ordered by priority/horizon label (for example Ahora / Siguiente / Después) without dates or durations unless the user decides otherwise.
- Proposed items must be real, with evidence in the repo, and labelled as proposed unless they are already decided or done.

## Open questions (needed before drafting)
- What the PM means by "roadmap": SRE / infrastructure / observability / security work only, or also product features? Who is the audience (the PM only, the directors)?
- Time horizon and format: quarter, months, or Now/Next/Later; a Jira ticket body, an email, or a page.
- Source material: the user's decisions on what is in; the candidate inventory would come from the SmartPedidos events and docs (52 event folders under `smartpedidos/events/`, tech-debt log, open proposals in GITIN-2222, GITIN-2229, GITIN-1477, GITIN-2170, GITIN-2107...). The events folder is write-only by project convention, so it was not read for this file yet.

## User's draft (2026-10-15) and structure agreed so far
- The user pasted a draft list of 8 stories (deployment improvements, AWS WAF, credentials in code, Graylog in DEV, multi-threshold scaling for Platform [items 4 and 8 are the same], log review, SP-SRE contracts for logs and Mongo queries, new Zabbix alerts) and asked what was missing. Each item is a Story with several tasks; existing tickets go on the task they cover; the time-estimate column is left to the end; columns for the PM: why it is necessary (technical debt), time estimate, comments, OPE priority based on criticality and effort.
- Tickets matched by event names (not by reading each ticket): GITIN-2169 (credentials per developer), GITIN-2129 and GITIN-1606 (credentials in code / secrets per environment), GITIN-2170 / 2110 / 2162 (scaling), GITIN-1477 / 2222 / 2229 (logs, FATAL), GITIN-2229 and GITIN-2171 (Zabbix alerts), GITIN-2013 / 2006 / 2062 (Mongo queries and indexes). No ticket found for WAF rules, Graylog in DEV or the deployment-environment work.

## Stories proposed from the tech-debt log (`smartfran/sp-logs/docs/tech-debt.md`, 8 open items recorded 2026-06-09..26: CGAP-003/006/007/008/009 concentrador, PGAP-001/002/003 platform; no Jira ids in the log)
- Check against the working trees (read 2026-10-15; concentrador `develop` `01494650`, platform `develop` `dfb668e`): the line numbers in the log do not match: `api/src/controllers/branch.js` has 4,185 lines in concentrador `develop` (the log says 5,571, written on the sp-logs branch); `horariosTest` still exists (line 1379, usage commented out); platform still has `Date.now()` timing in 6 provider files and 30 sites with "Platform Communication Error" (the log says 28). The `orderRejClosed` silent catch (CGAP-003) was not re-read in the current code. The items are therefore still open in substance, but the numbers must be refreshed before they go to the PM.
- Proposed stories: (A) concentrador `branch.js` refactor: extract responsibilities (CGAP-006), remove the dead fixture (CGAP-007), remove the copy-pasted per-platform functions (CGAP-009), move inline error logging out (CGAP-008, blocked by 006); (B) silent failures in the order-rejection cron (CGAP-003, high; criticality high, effort low); (C) platform logging debt: adopt the HTTP-client interceptor for timing (PGAP-001), structured fields instead of strings with the order id (PGAP-002), order id on SQS consumer failures (PGAP-003); (D) technical-debt governance: keep the log current, assign Jira ids, and record the new items found in GITIN-2222 (17 `sanitizeHeaders` call sites, `Log._stdout` serialization, process-handler policy, concentrador's mistyped `uncaughtException:`).

## Validation of the 8 tech-debt items against `develop` (2026-10-15; read-only greps and file reads on the working trees; concentrador `develop` `01494650`, platform `develop` `dfb668e`; both trees clean and equal to the local `origin/develop` ref, no `git fetch` done)
| Ref | Status in develop | Evidence |
|---|---|---|
| CGAP-003 silent catch in `orderRejClosed` | Live | `branch.js` function `orderRejClosed` (line 635, cron registered at line 445): `for` loop calling `sendReject(...)` with `catch (error) { continue; }` (lines ~712-714), no log |
| CGAP-006 oversized controller | Live, smaller | `branch.js` has 4,185 lines (log: 5,571), 21 `cron.schedule` calls plus request handlers (`search`, `saveOne`, `updateOne`, `updateAll`, `login`...) in the same file |
| CGAP-007 dead test fixture | Live | `horariosTest` defined at line 1379 and referenced in a comment at line 1397 |
| CGAP-008 inline error logging | Live | 88 `Log.saveError` calls in `branch.js` (log: ~88) |
| CGAP-009 per-platform copied functions | Partly changed | `closeBranchPeya/Rappi/Uber/PediGrido/MercadoPago` still in `branch.js` (lines 761-1063+); the `checkOfflinePOS` and `sendStatus` families now live in `api/src/utils/statusManager.js` as `#checkOfflinePOSpeya/rappi/uber/mercadopago` (still one variant per platform; whether those bodies are near-identical was not compared) |
| PGAP-001 inline PERF timing | Live | `[PERF/INFO]` log sites per provider: uberEats 4, mercadoPago 6, pedidosYa 5, rappi 5, rapiboy 10, thirdParty 16 (46; log: ~40); platform has no `api/src/utils/httpClient.js` and no `interceptors` in `api/src` |
| PGAP-002 legacy error message format | Live | "Platform Communication Error" 30 sites (log: 28), 31 including the "Platform Auth Error" pattern: app.js 1, rappi 4, uberEats 4, controllers/thirdParty 1, pedidosYa 6, mercadoPago 3, rapiboy 6, thirdParty 6 |
| PGAP-003 SQS consumer without order_id | Resolved | `api/src/platforms/provider/aws.js`: the `setNews_processing failed consumer=parent` and `consumer=child` logs now include `order_id: JSON.parse(newToSet.Body)?.id ?? 'unknown'` (the `no_id` path was not read in full) |
- The roadmap file `outputs/roadmap-smartpedidos.md` (Stories 9-11) was updated with these results; the PGAP-003 task was removed.

## Update 2026-10-15 (afternoon): findings that affect the roadmap (not yet written into the roadmap files)
- Story 7 (new Zabbix alerts): the alert for stopped Platform tasks did not reach anyone for the 18 STOPPED mails of the morning; causes found or open: the margin macro set to 1000 on the discovered hosts (cannot fire), and a hypothesis that the recipient has no read access to the AWS host group (notifications not generated). Candidate task for Story 7: "verify that alerts on discovered AWS hosts are delivered (permissions and macros)".
- Story 7 also gains GITIN-2239 (healthcheck triggers, High for non-200 and Warning for slow response, all values in macros) and GITIN-2238 (the Mobile outage incident); neither has been applied/closed.
- The roadmap files still show the earlier ticket matches and tasks; update them once the user confirms.

## Update 2026-10-15 19:30 UTC
- Files in `outputs/`: `roadmap-smartpedidos.md` (Stories with tasks and ticket links), `tabla-roadmap.md` (one-page table with estimates and how they were calculated) and, in the event root, `email_pm.md`. Tickets are linked; where none exists the text is "No hay ticket aún". The user parked the PM review (item 5).
- Findings of the afternoon that are not in the roadmap files: Story 7 should gain a task for verifying alert delivery on discovered AWS hosts and for the recipient's user-group tag filters (GITIN-2222 C37/C38), the Zabbix healthcheck alerts of GITIN-2239 and the outage of GITIN-2238.

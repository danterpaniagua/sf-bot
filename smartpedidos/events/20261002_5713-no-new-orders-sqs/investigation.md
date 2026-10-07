# Investigation — 20261002_5713-no-new-orders-sqs

**Status:** in progress — PedidosYa and PediGrido orders have reached the POS since 2026-10-03 (see the 2026-10-05 re-check); the cause of the earlier PediGrido gap (2026-09-23 → 2026-10-01) is still unconfirmed; open items below.

Jira ticket: [GITIN-2161](https://smartit-ar.atlassian.net/browse/GITIN-2161), title "[SP] 5489 No recibe pedidos" (the ticket uses the old number).

Report (as received): branch 5713 has "new order" alerts, but nothing shows up in `https://sqs.us-east-1.amazonaws.com/382381053403/5713PRD_PlatformMessages.fifo`.

Scope: 5713 is an on-prem SmartPedidos branch (platforms-service / concentrador-service, MongoDB `smartfran`). It is NOT a SmartFran Cloud branch. An early detour into the Cloud `Platform-SP/Queues` Cosmos container was wrong-scope; its empty `BranchId = '5713'` result says nothing about this incident (`cloud/events/20261002_smartpedidos-5713-no-new-orders-sqs/` holds only that detour's data).

Context relayed by a colleague (chat, not verified): the branch was renumbered 5489 -> 5713, the old branch was removed from the concentrador and the platforms' integration data was moved to 5713; PedidosYa was being re-integrated and a test order did not arrive; the PediGrido app rings but nothing arrives in the app or SF; MercadoPago orders arrive.

## Confirmed facts

Times are UTC unless marked local (UTC-3).

### Queue and configuration
- Queue name form `5713PRD_PlatformMessages.fifo` (no underscore) is correct: `createQueues` does `CREATE_NAME.replace('##_', branchId)` (concentradorService `api/src/provider/aws.js:20`, clone on `develop` @ `0d6f158a`, working tree). Region us-east-1.
- The 5713 queue exists, created ~2026-09-22 (branch `startDate` 2026-09-22), empty at query time. It is identical in every attribute and policy to queue 3013 (reference branch, 549/570 PediGrido orders DELIVERED in 14 d) except `SqsManagedSseEnabled` (true on 5713, default for new queues, no extra IAM needed). Queues for 3013, 4703, 4616, 3254, 3640, 5454 exist under the same naming (`data/sqs_queue_attrs_5713.json`, `data/sqs_queue_attrs_3013.json`, `data/sqs_queue_attrs_diff_3013.txt`, `data/sqs_reference_candidates.txt`).
- Old queue `5489PRD_PlatformMessages.fifo` still exists, empty (`data/sqs_queue_attrs_5489.json`). Branch 5489 no longer exists in `branches`; its history remains in `orders` (PedidosYa READY to 2026-10-01T02:39Z, MercadoPago REJECTED to 2026-10-01T17:04Z, Rappi DELIVERED to 2026-09-30) (`data/mongo_old_5489.json`).
- Branch 5713 vs 3013 in Mongo (as of 00:24Z): same permissions and agent version (1.33); PediGrido `branchReference` equal to branch id on both; other differences are platform sets and minor flags (`data/mongo_compare_branch.json`). 5713: not suspended, no `alreadyClosed*`, no `progClosed`.
- Only branch 5713 holds the PedidosYa `branchIdReference` that 5713 has (`data/mongo_old_5489.json`). No branch has a platform reference equal to "5489" now (`data/mongo_refs_5713.json`).

### Source (platformsService; clone was on `ope` @ `b8d57be`; checked identical to `develop` @ `ded57a5`, the production reference, for `api/src/platforms`)
- `platform.js` 707-712, 798-804: an incoming order is mapped to a branch by string-matching the platform's order branch code against `branches.platforms.branchReference`; no match returns "There is no branch for this order" and nothing is saved. PedidosYa uses `order.branchId` (`interfaces/pedidosYa.js` 591-598).
- `platform.js` 981-993 (develop 984-992): the order and news are saved first; the push to SQS (`pushNewToQueue`) happens only if `isOpened && platform.isActive && (parseFloat(agent.installedVersion) > 1.24 || cloud)`. `isOpened` is false when `lastGetNews` is older than 2 min or inside a `progClosed` window (`isClosedRestaurant`, 591-620). PediGrido (`internalCode` 7, in `plarforms22`) is still saved as PENDING/newOrder when "closed", not pushed, with an `orderRejClosed` row created (not awaited). A new branch document with no reported agent version gives `parseFloat(undefined)` = NaN, so the push is skipped without logging.
- `provider/aws.js` `pushNewToQueue` returns `this.sqsClient.send(command)` inside a `try` without `await`, so an async send error escapes its own `catch` and would surface in the caller as `saveNewOrders 5 failed`.

### PedidosYa tests (thread A)
- Graylog (SmartPedidos stack) `"There is no branch for this order"`: 3 PedidosYa orders (codes 2309204253, 2309193736, 2309230293) at 22:50:13, 22:54:26, 23:03:25 (19:50-20:03 local), each received twice 10 s apart, each rejected (`orden: failed<code>`, `validateNewOrders 2 failed`). In all of them the payload carries `branchId` 5713, `platformRestaurant_id` 522890, `test` false. No further such errors after 23:03:35 (`data/graylog_nobranch_3h.json`, `data/graylog_branchfield_5713_6h.json`). The raw Graylog files contain customer personal data and a token field; they are git-ignored (`**.json`) and only non-personal fields were read.
- concentrador-service logged 5 `[INFRA/ERROR] branch_update_duplicate_reference` (`rest.error: Failed to delete branch.`) for branch 5713 between 21:01:54 and 21:06:18 (18:01-18:06 local). The body being saved shows 5713's PedidosYa entry with `branchReference` = 5489 (old code) and `branchIdReference` 522890, i.e. the integration data copied from the old branch; the saves were rejected as duplicate references (`data/graylog_branchfield_5713_6h.json`).
- As of 00:37Z the PedidosYa entry of 5713 has `branchReference` = "5713" and `branchIdReference` 522890, active (`data/mongo_refs_5713.json`). Mongo keeps no history of that field.
- No PedidosYa order exists in Mongo for 5713; platform-wide PedidosYa (5,953 orders / 990 branches) and PediGrido (1,735 / 844) were flowing normally in the 6 h to 00:35Z (`data/mongo_fresh_5713.json`).

- Check at 00:44:47Z (`data/mongo_fresh_5713_b.json`, `data/mongo_refs_5713_b.json`, `data/graylog_nobranch_30m_b.json`): a PedidosYa order (displayId 2309501289) was saved for 5713 at 00:38:35.273Z; its news trace shows received by the POS at +0.6 s (typeId 10), viewed at 00:39:07 (typeId 11), accepted at 00:39:27 (typeId 5), then `platformRejected` at 00:40:16.445 (typeId 4, `rejected.entity` PLATFORM, id -2), order state `REJECTED`. The news `viewed` field (00:40:16.978) is the last typeId 10 update, not the first receipt, so it is not a delivery delay. A Rappi order at 00:42:10Z went 1 -> 10 (+2 s) -> 11 -> 5 -> 15 (READY) (`data/mongo_latest_news_5713.json`). No "no branch" rejection in the last 30 min. The PedidosYa entry still equals "5713"; the PediGrido entry is still absent. So the PedidosYa mapping works now, and the order reached the POS.

### PediGrido (thread B)
- 5713's PediGrido entry was present at 00:24Z (5 platforms) and absent at 00:35:47Z and 00:37Z (Rappi, MercadoPago, PedidosYa, PaD only): the integrations were edited in that window (`data/mongo_compare_branch.json`, `data/mongo_old_5489.json`, `data/mongo_refs_5713.json`). Every PediGrido-config statement above is as of 00:24Z. With no entry, a PediGrido order for 5713 finds no branch and is not saved. No PediGrido "no branch" message appeared in the Graylog search, so today's PediGrido tests are not explained by logs yet.

- At 00:49:19Z the PediGrido entry is back on 5713: active, `branchReference` "5713". No other branch holds a PediGrido entry with reference "5713" or "5489" (`data/mongo_pedigrido_holders.json`). So it was re-added between 00:44:50Z and 00:49:19Z. No PediGrido test order has been checked since.

### Oct 1 PediGrido order saved but not sent (thread C)
- PediGrido order `displayId 5637871`, created 2026-10-01T17:28:27.836Z (14:28 local), `PENDING` ~31 h later; its news is `typeId 1` with a single trace at creation and `viewed` null (`data/mongo_order_trace_5713.json`). It has no `orderrejcloseds` row; that collection exists with 44,850 rows, so "closed" path is unlikely for it (`data/mongo_control_pedigrido.json`, `data/mongo_closed_path_5713.json`). No dead letters for it.
- All 6 earlier PediGrido orders of 5713 (2026-09-23..29) were rejected by the platform (`rejected.entity: PLATFORM`, id -2) ~10 min after creation; none of the 7 was ever `viewed` by the POS. For 3013, 28 of its 30 latest PediGrido news were viewed within 1-12 s (`data/mongo_control_pedigrido.json`).
- Delivery marker: for the MercadoPago, Rappi and PedidosYa orders of 2026-10-03 the news has a typeId 10 trace within ~0.6-2 s of creation (order received by the POS). None of the 7 PediGrido news of 5713 has it: the 6 rejected ones have only traces 1 and 4, and the Oct 1 one only trace 1 (`data/mongo_latest_news_5713.json`, `data/mongo_closed_path_5713.json`).
- CloudWatch 48 h: `NumberOfMessagesSent` has no datapoint in the hour of the Oct 1 order; the only non-zero bucket is 20:22-21:22 local on 10-02 (Sent 2, Received 2) (`data/sqs_NumberOfMessagesSent_5713_48h.json`, `..Received..`).
- 5713's agent 1.33 `installedDate` is 2026-10-01T19:23:20Z, ~1h55m after the Oct 1 order; `nextVersionToInstall` 1.34 (`data/mongo_agent_install_5713.json`). `NumberOfEmptyReceives` on the queue is 0 in every bucket from creation up to the bucket starting 15:33 local on 10-01 (24 in it), then ~180/h (one poll every ~20 s) while the POS runs. Reading 24 polls at 20 s as ~8 min before the bucket end puts the first poll at ~19:25Z, ~2 min after `installedDate`. Two independent sources (SQS activity, Mongo field) agree the queue was not polled before the 1.33 agent install (`data/sqs_EmptyReceives_5713_14d.json`). Queue activity with 0 empty receives on 2026-09-22 and 2026-09-27 11:33-17:33 local is unexplained.
- Two MercadoPago orders (READY) at 00:18:10Z and 00:18:35Z were `viewed` by the POS ~1.2 s after creation and reached `readyOrder` within ~30 s; same hour shows Sent 2 / Received 2: queue, consumer and POS worked end to end for that path (`data/mongo_closed_path_5713.json`).

### Re-check on 2026-10-05 09:06 ART (12:06Z) (`data/mongo_latest_news_5713_oct5.json`, same `mongo_latest_news_5713.js` script, limit 6)
- The 6 latest orders of 5713 are all PedidosYa, all `READY`, created between 2026-10-04 22:36Z and 2026-10-05 01:25Z. Each news has the full trace 1 → 10 (received by the POS, +0.6–0.7 s) → 11 → 5 → 15 (READY), no rejection; accepted ~25–35 s after receipt (one at ~70 s). So PedidosYa orders reach the POS end to end after the mapping fix. Whether these were test or real orders is not known (the `test` flag was not read).
- Nothing newer than 2026-10-05 01:25Z exists in the latest six; the query has a limit of 6 and no platform filter, so it says nothing about PediGrido orders after 2026-10-03: the PediGrido entry restoration is still unvalidated. A follow-up script (`mongo_orders_since_oct3_5713.js`: counts per platform/state since 2026-10-03T00:49Z, and per-order trace summary for PediGrido and PedidosYa) was run at 12:10Z the same day, see below.

### Orders of 5713 since 2026-10-03T00:49Z (`data/mongo_orders_since_oct3_5713.json`, run 2026-10-05 12:10Z)
- Per platform/state: PedidosYa READY 33 (2026-10-03T00:52Z → 2026-10-05T01:25Z); MercadoPago REJECTED 4 (10-03 19:00Z → 10-04 02:43Z) and READY 2 (10-04 15:50Z, 16:27Z); Rappi REJECTED 4 (10-03 01:03Z → 10-04 02:24Z); PediGrido REJECTED 2 and DELIVERED 1.
- **PediGrido since the entry was restored: 3 orders, all reached the POS.** `5645514` (10-03 00:59:03Z), `5653028` (10-04 00:31:04Z) and `5663559` (10-04 22:01:49Z): each news was viewed 1–2 s after creation and has traces 1 → 10 → 11 → 5 → 15; `5663559` continues 3 → 14 and is `DELIVERED`; the other two end with trace 2 (`rejected`, `rej_ord`) after reaching READY and are `REJECTED`. The reason for those two rejections and who rejected them was not read. This contrasts with the 7 earlier PediGrido orders (09-23..10-01), none of which has trace 10.
- **PedidosYa:** 33 of 33 `READY`; 0 `neverViewed`; 3 orders have no joined news in this script's join (news matched to the order by identical `createdAt`); the cause of the 3 missing joins was not investigated (the join is an approximation, not proof of non-delivery).
- MercadoPago (4) and Rappi (4) `REJECTED` orders: traces and reasons not read in this pull.
- Not re-checked: current state of order `5637871`.

## Current working theory
Three separate things, not one:

A. PedidosYa tests (22:50-23:03Z) were rejected because 5713's PedidosYa entry carried the old code (`branchReference` 5489, seen at 21:01-21:06Z in the failed saves) while PedidosYa already sent 5713. Consistent with the colleague's copy of integration data from the old branch. The entry reads "5713" as of 00:37Z, so it was corrected after 23:03Z; when is not recorded. Not proven for 22:50-23:03Z (no field history); a new PedidosYa test would confirm.

B. PediGrido tests on 2026-10-02/03: the PediGrido entry was removed from 5713 between 00:24Z and 00:35Z, which would make any PediGrido order for 5713 unmappable, and was back by 00:49Z. The time of the colleague's PediGrido test is unknown, so a link is not established. Since the entry was restored, the 3 PediGrido orders of 5713 (2026-10-03 00:59Z → 2026-10-04 22:01Z) all reached the POS within 1–2 s, so the PediGrido path works end to end with the entry present.

C. The Oct 1 PediGrido order (and the 6 before it) was never sent to SQS or seen by the POS. Leading explanation: the branch document was new and the agent was only installed on 2026-10-01T19:23Z, so at order time the push condition (reported agent version > 1.24) was not met and the push was skipped silently; the queue had no consumer until the install. Not proven: the agent version before the install is unknown (`installedVersion` is overwritten) and no log line exists for a skipped push. Alternative still open: a push attempted and failed (would log `saveNewOrders 5 failed`; Graylog check for it not yet answered).

## Ruled out
- Queue missing / misnamed / wrong region / misconfigured vs a working queue (facts above).
- (Retracted) An earlier note that queue 3013 did not exist came from an unset shell variable in a command, not from AWS state.
- Branch deleted, suspended, closed flag, `cloud` flag for 5713.
- Dead letters swallowing messages: none in the last 3 days.
- Agent not polling today: `lastGetNews` current at every query and ~180 empty receives/h while the POS runs.
- A duplicate holder of 5713's PedidosYa reference or a leftover "5489" reference on another branch.

## Open questions / next steps
- PedidosYa after the mapping fix: 33 of 33 orders since 2026-10-03T00:49Z are `READY` and none was unseen by the POS (no rejection for a missing branch was looked for after 2026-10-03T00:44Z in Graylog). Open: whether any of them were tests, and why 3 of the 33 have no news in the `createdAt` join.
- Reasons for the `REJECTED` orders since 2026-10-03T00:49Z: PediGrido 2 (reached READY, then trace 2 `rejected`), MercadoPago 4, Rappi 4 — traces, `rejected.entity` and reason ids not read.
- Current state of order `5637871` (last seen `PENDING` on 2026-10-03).
- Did someone remove the PediGrido entry on 5713 between ~21:25 and ~21:35 local, and why? What local times were the PediGrido and PedidosYa tests?
- What code does PedidosYa's side currently send for this store (the logs show 5713 at 22:50-23:03Z)?
- The 3 PedidosYa orders flagged `test: false`: were they tests or real orders?
- Previous agent version on 5713 before 2026-10-01T19:23Z (site agent logs or the team that rolled out 1.33).
- Graylog for `saveNewOrders 5 failed` / `pushNewToQueue failed` around 2026-10-01T17:28Z (queries with several terms returned `ApiError: Missing search type result!`; a single exact phrase works).
- CloudWatch `NumberOfMessagesSent` over 14 days, to see whether any Sep 23-29 PediGrido order produced a send.
- Order `5637871` is still `PENDING` with no SQS message ever sent; handling it is a state-changing decision with the team, not proposed yet.
- Jira ticket URL; what raised the original "new order" alerts (system, wording, time).

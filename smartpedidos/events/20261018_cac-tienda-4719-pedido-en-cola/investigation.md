# Investigation: Store 4719 rings for an order but receives nothing (CAC request)

**Status (2026-10-18 22:05):** the queue read shows 4 messages stuck in the store's production queue for about 3 hours 40 minutes, received every 3 minutes and never deleted, and gone at 20:14; the user states that at 20:13 they restarted the queue and cleared the 4 stuck messages; why the messages were not deleted by the consumer and whether the orders reached the store are not known. Jira: not given yet (ask the user; rename the folder to `YYYYMMDD_gitinXXXX-description` when it exists). Times are UTC-3; the chat times are assumed to be UTC-3 (not stated).

## Scope

CAC (customer support) reported at 19:36 that store 4719 hears the sound of a new order but nothing arrives, and asked whether an order was left stuck in the queue (data/cac-chat-2026-10-18.txt, names replaced by roles). SRE looked from 20:08; at 20:13 SRE asked "los limpio?" ("shall I clear them?") and then "proba ahi" ("try now"); CAC confirmed "ya quedo resuelto" about 53 minutes later. The user (SRE) asked on 2026-10-18 to record this as a request to check the SmartPedidos queue.

## Established (data/sqs-attributes-*-2152.txt, data/cw-4719-*-2152.txt, data/cw-4719-summary-2152.txt; CloudWatch 1-minute, 19:30-20:29)

- The queue `4719PRD_PlatformMessages.fifo` exists in `us-east-1` (created 2020-12-15), FIFO, visibility timeout 180 s, retention 3 days. So "tienda 4719" is branch 4719 (the queue name matches the pattern).
- From 19:30 (start of the window) to 20:13 the queue held **4 messages in flight, constantly**; the consumer **received 4 messages every 3 minutes** (15 receive minutes, 60 receives in total), and **0 were deleted** (Deleted Sum 0, Sent Sum 0 in the window). The age of the oldest message grew from 10,575 s (2 h 56 min) at 19:30 to 13,157 s (3 h 39 min) at 20:13, so the oldest message was sent at about 16:34.
- At 20:14 in-flight and age fall to 0 and stay 0 to 20:29 (end of the window); the last receive minute is 20:14. Current attributes (21:52): 0 visible, 0 in flight, 0 delayed; `LastModifiedTimestamp` is 20:14:08, the minute after the "los limpio?" message of the chat. What was done at 20:13-20:14 is the user's account below; the metrics alone do not say whether it was a purge, a delete or something else.
- Redrive policy of that queue: dead-letter target `DeadLetter.fifo`, `maxReceiveCount` 1000. With a 180 s visibility timeout a message never deleted needs 1000 receives (about 50 hours) to reach the dead-letter queue, so the dead-letter queues would not show a message stuck this way for about two days. `DeadLetter.fifo` holds 1 message and had no change today; `MainDeadLetter.fifo` fell from 102 to 12 visible messages between 16:50 and 21:17 (decreases only, no increase; who or what removed them is not known; see the GITIN-2252 event).

## User-stated action (2026-10-18)

The user states: "I restarted the queue at 20:13, cleared the 4 stuck messages." What exactly "restarted" means technically (queue purge, consumer restart, or both) was not specified. The metrics fit it: in-flight messages and oldest-message age go to 0 at 20:14 and stay 0 to 20:29; `LastModifiedTimestamp` 20:14:08. Cleared messages are gone: their content and the orders they carried were not read or saved, so whether those orders were ever delivered to the store, or are lost, cannot be checked from the queue.

## Reading (hypothesis, not confirmed)

The store's consumer received the same 4 messages every 3 minutes without confirming them, which would fit "the store hears an order and nothing arrives". Why they were never deleted (message content, consumer behavior on that branch) was not looked at; the message bodies were not read.

## Not known

- Whether the 4 messages were orders that never reached the store, and whether those orders were later delivered, cancelled or lost (the messages were cleared before anyone read them; the order ids, if any, could only come from the platform records).
- The technical meaning of "restarted the queue" (purge, consumer restart, or both).
- What made the messages undeletable, and why the oldest one was sent at about 16:34 and not handled for 3.5 hours.

## Next

1. Check the platform's own records for the orders of branch 4719 around 16:34 (the time the oldest stuck message was sent) to see whether they were delivered or cancelled (a MongoDB query for the user to run; not written).
(Scope decision, user 2026-10-18: no survey of the other per-branch queues; only `PRD_BranchMessages.fifo` and the dead-letter queues are analysed. The listing script drafted for it was withdrawn and not run.)

## Scripts (in `scripts/`)

| # | Script | Purpose | Run |
|---|---|---|---|
| 1 | `scripts.sh` | Attributes of the 4719 queue, `PRD_BranchMessages.fifo` and both dead-letter queues; CloudWatch for the 4719 queue 19:30-20:30 | yes (21:52) |

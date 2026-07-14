# SmartPedidos — Infrastructure Reference

**Last updated:** 2026-07-11

---

## Data Stores

| Store | Detail |
|---|---|
| MongoDB Atlas cluster | `PedidosSmartfran`, region `us-east-1` |
| Database | `smartfran` |
| Key collections | `orders`, `news`, `logerrors`, `deadletters`, `branches`, `chains`, `platforms`, `newsStates`, `newsTypes`, `configs` |

The `news` collection is the internal event/notification model — each document has a `traces` array tracking state transitions.

---

## Message Flow (AWS SQS)

```
PedidosYa / Rappi / UberEats / MercadoPago / PediGrido
        ↓  webhook
  platforms-service
        ↓  pushNewToQueue
  {branchId}_PlatformMessages.fifo  (per-branch, us-east-2)
        ↓  pollFromQueue (parent consumer)
            + up to 3 child consumers (auto-scale at 200 / 400 / 600 depth)
        ↓  setNews → news state transition
  BranchMessages.fifo → SmartFran agent (POS terminal)

  On failure → DeadLetter.fifo / MainDeadLetter.fifo
        ↓  concentrador-service deadLetterSave() on startup
  smartfran.deadletters  (MongoDB)
```

**Region:** `us-east-2` (queues) — note this differs from the MongoDB Atlas cluster region (`us-east-1`).

**Auto-scaling (platforms-service consumers):** based on `ApproximateNumberOfMessages` — depth > 200 spawns a 2nd consumer, > 400 a 3rd, > 600 a 4th.

**Dead letter retention:** `MessageRetentionPeriod: 259200` (3 days) — act within that window.

**Key config flag:** `configs.saveDeadLetterbol` — if `false`, concentrador-service skips dead letter recovery silently.

### Queue URLs (testing environment)

| Queue | URL |
|---|---|
| Producer | `https://sqs.us-east-2.amazonaws.com/382381053403/{branchId}_TST_PlatformMessages.fifo` |
| Consumer | `https://sqs.us-east-2.amazonaws.com/382381053403/TST_BranchMessages.fifo` |
| Dead letter | `https://sqs.us-east-2.amazonaws.com/382381053403/DeadLetter.fifo` |
| Main dead letter | `https://sqs.us-east-2.amazonaws.com/382381053403/MainDeadLetter.fifo` |

Production queue naming follows the same pattern without the `_TST_` segment (e.g. `{branchId}_PRD_PlatformMessages.fifo`) — confirm exact naming before use, not independently verified.

---

## Services

| Service | Role |
|---|---|
| `platforms-service` | Inbound integration layer for delivery platforms. Validates/normalises orders, persists to MongoDB (`orders` + `news`), pushes to AWS SQS. `Platform` base class with per-platform subclasses for the full order lifecycle. Manages restaurant open/close scheduling and per-platform delivery-time/rejection-reason catalogues. |
| `concentrador-service` | Internal management and POS-facing backend. Serves SmartFran agents and the management dashboard. Owns the SQS consumer path bridging platforms-service to branch POS terminals. Handles dead-letter recovery, platform-history auditing, `news` state transitions. |

Neither service's source is cloned in this project — see `smartpedidos/CLAUDE.md` for where source-level work happens (`smartfran/sp-logs`, a separate project).

---

## Related

- Skill: `/ops-aws` — failure catalog and diagnostic queries for SQS/dead-letter issues (consumer down, stuck orders, DLQ accumulation, queue depth buildup).
- Skill: `/sp-sre-output` — Jira tickets, closure reports for SmartPedidos incidents.

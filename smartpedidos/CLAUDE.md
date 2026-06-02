# CLAUDE.md

## Project Orverview

### platforms-service

Express/Node.js API that acts as the **inbound integration layer** for third-party delivery platforms (PedidosYa, Uber Eats, Rappi, Glovo, MercadoPago, Rapiboy). Receives platform webhooks, validates and normalises orders, persists them to MongoDB (`orders` + `news` collections), and pushes accepted orders to AWS SQS so branch POS terminals can consume them. Implements a `Platform` base class with per-platform subclasses (strategy pattern) for the full order lifecycle: receive, view, confirm, ready, dispatch, delivery, reject. Also manages restaurant open/close scheduling and syncs delivery times and rejection-reason catalogues from each platform.

### concentrador-service

Express/Node.js API that acts as the **internal management and POS-facing backend**. Serves SmartFran agents (desktop software at each branch) and the management dashboard. Exposes routes for: branch/chain/user/region CRUD, `news` query and state transitions (the order event bus), software-version distribution (`activeSoftware`), delivery-provider tracking (`courierDate`, `delivery`), dead-letter recovery (`recoveries`), platform-history auditing, and order-time analytics crons (`ordertimesAvgCron`). Also owns the SQS consumer path that bridges inbound orders from platforms-service to the POS.
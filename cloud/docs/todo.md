# Cloud — TODO

Open work of this project. One entry per piece of work, each with the tickets it spans. When an item is done, record the resulting fact in the doc it belongs to (`infrastructure.md`, `graylog-log-fields.md`) and delete the entry here. State below was read from `docs/infrastructure.md` and the event folders as last recorded, not re-measured; re-read the live state before acting.

## 1. Sales-PRO out-of-memory crashes

Tickets: GITIN-2040. Event: `events/20260920_sales-oom-48h/`. 18 crashes in 48 h (`0xE0434352`) on `SmartFran-Cloud-Sales-PRO`; the 32-bit worker flip-flop was necessary to fix but not sufficient. Open: the cause of the remaining memory growth and the unbounded `Movement/POSGetAll`; findings and numbers in `infrastructure.md` → "Service findings worth knowing before investigating".

## 2. POS Wasm returns 403 after a deploy

Event: `events/20260930_pos-wasm-tenant-403-after-deploy/` (no ticket recorded in the docs). Open. The refresh-token hypothesis is untested and was left out of the docs on purpose. The `cloud-azure` skill carries only a one-line pointer: read the event's full workflow before relying on it.

## 3. Peru order delay

Tickets: GITIN-2084, related GITIN-2109 (`CRS: 409` marking PedidosYa orders ready on branches 5470/5424). Events: `events/20260919_grido-order-delay-peru-5396-5481/`, `events/20260925_gitin2109-peru-branches-order-delay-crs409/`. Root cause not confirmed; best lead is per-instance CPU saturation on `SmartFran-Cloud-Sales-Plan-PRO` plus the manual hosting-plan changes of 2026-09-18, followed by a Sales-wide HTTP timeout cascade.

## 4. Graylog disk latency and retention

Ticket: GITIN-2228. Event: `events/20261015_gitin2228-graylog-nvme0n3-latencia-disco/`. Open: the cause of the disk latency (candidates `read_ahead_kb`, host caching `ReadOnly`, per-request latency) and the retention decision (7 days `Information` and 30 days `Warning` and above through new streams and index sets, or a daily deletion of old `Information`).

## 5. Cosmos firewall of the GRIDO account

Ticket: GITIN-2083 (`events/20260918_sales-cosmos-403-firewall/`). Remediation was pending when last recorded; re-read the account's `ipRules` before relying on the doc.

## 6. Credentials in the repository history and Peru e-invoicing providers

Event: `operations/events/20260714_fepe_zabbix_healthcheck/` (user decision to track here, 2026-10-28; no ticket recorded; separate tickets were suggested in the event). Not confirmed done as last recorded (2026-07-24):
- Rotate the plaintext credentials found in `Documentation/*/release_notes.md` of the Cloud repository: the AWS access key pair (`v1.0.6`, `v1.0.8`, highest priority, possible account-wide scope), `WsFePe__BizlinksUser`/`BizlinksPassword` (`v2.30.00`), `PrinterLicense__NeodynamicLicenseKey` (`v0.17.00`, `v1.17.00`). Review by hand the two `FabricConnections:*` files (`v2.18.00`, `v2.23.00`) and the two ambiguous ones (`Business|VendorInvoice`, `GridoOrg`). Paths and commit ids are in the event; never copy a value.
- Xacto Peru `WsFeProd` (port 8099) and `WsFeTest` (3636) time out while `ConsultaProd` (6099) answers on the same IP: confirm from the real production egress (Kudu console of the Sales API App Service) or with Xacto whether it is whitelisting or a fault. Monitoring: `docs/zabbix_observability.md` → "FEPE healthcheck".

## 7. Documentation items

- **Docs note not written (GITIN-2328):** the five `SmartFran.Cloud.<Module>.Authorization.Auth0` values in App Configuration must hold valid JSON and keep it when a store is copied (Newtonsoft tolerates unquoted property names but fails on the first unquoted value); App Configuration key filters accept `*` only at the end; reading values needs the Data Reader role or `--auth-mode key`. Target: `infrastructure.md`. Event: `events/20261027_gitin2328-dev-env-authorizer-settings-json/`.
- **Unreconciled figure:** SmartCloud Graylog `*-http` index sets, ~36 GB (2026-10-14) vs ~6 GB (2026-10-21).
- **Report to the developers, do not edit:** `devs-log-structure.md` §10 says all properties are PascalCase without `_`, while §3.3 documents five `_`-prefixed helper keys.
- **`cloud/CLAUDE.md`, only on the user's request:** it says a `Service:Orders` field filter "has never been confirmed to return real results"; the live `Service` value is `SmartFran.Cloud.Orders.API`, so the short form probably returns 0 (unverified; explained in `graylog-log-fields.md`).
- **Open questions** (in `infrastructure.md`): whether the `...-Grido-PRO` Service Bus namespace is Grido-specific; the live `organizations` list; the `Security` service's App Service; which of the SQS bridge and `/api/v1/Queue/Heartbeat` is authoritative for order delivery.

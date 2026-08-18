# Investigation — 20260818_grido-news-etl-s3

**Status:** converged — ready for ticket (pending one open business question, see below)

**Jira:** GITIN-1872 (parent, "[SP] Envío de datos de SP a Grido") → GITIN-1873 (this subtask, "[SP] Análisis de colecciones de News", priority High). Sibling subtasks, out of scope here: GITIN-1874 ("[SP] Creación de ETL -> S3", Medium), GITIN-1880 ("[SP] Securización de S3" — scope confirmed as access security for the bucket, e.g. IAM/bucket policy restricting who/what can read it, not field-level encryption). GITIN-1880 restricting *who can read the bucket* is a separate control from *which fields go in it* — it doesn't change the REDACT calls in `field-classification.md` (those fields shouldn't be in the export regardless of who can access the bucket), but it is relevant to the two SEND-COND items (`customer.id`, `numeroTarjetaLoyalty`): tighter bucket access control strengthens the case for including them, though it still doesn't substitute for confirming the Grido data-sharing agreement actually covers them.

## Scope

GITIN-1873 only: inventory what fields the `news` MongoDB collection stores, and assess whether that data is safe to export to Grido via S3. No ETL design or implementation in this subtask.

## Confirmed facts (from source, `smartpedidos/repo/dev-scr-smartPedidos-platformsService` + `dev-src-smartPedidos-concentradorService`, both on `develop`)

- `news` collection schema (`api/src/models/news.js`, identical in both services): `typeId` (Number), `order` (**Object, untyped**), `branchId`, `rejectedMessageId`, `viewed`, `traces[]` (`update: Object`, `createdAt`), `orderPickedUp`, `orderDelivered`. Schema option **`strict: false`** — Mongoose will persist any additional ad-hoc fields sent beyond what's declared, not just the `order`/`traces` objects.
- The `order` sub-object is fully populated per platform in `api/src/platforms/interfaces/*.js`, called from `newsFromOrders`/`orderMapper` and set via `news.order.customer = customerMapper(...)` (thirdParty.js:282, uberEats.js:312, glovo.js:196-198, pedidosYa.js customer mapper ~464-471). This happens on `new_ord` news creation (`set-news.js:150-153`: `newToSet.order = data`).
- **Customer PII fields present in `news.order.customer` across all platform interfaces**, confirmed in source:
  - `name`, `address`, `phone`, `email`, `dni` — every platform (thirdParty, uberEats, glovo, pedidosYa).
  - `id` (platform's internal customer id).
  - thirdParty.js:168-172 — for `platform.internalCode` 7 or 12: also `tipoIdentificacion`, `numeroTarjetaLoyalty`, `contieneCanje`, `puntosCanjeados` (Club Grido loyalty-program identifiers).
  - uberEats.js:126 — phone field additionally carries a delivery PIN code (`phone.number + '|PIN ' + pin_code`).
- `news.order.driver` (thirdParty.js:107-119) carries raw delivery **lat/long coordinates** parsed from `order.address.coordinates`.
- `news.order.details[]` (thirdParty.js:188-264) — order line items: `productId`, `count`, `price`, `discount`, `description`, `sku`, `optionalText` (free-text customer notes per item), `promo`, `canje` (loyalty redemption flag, platform.internalCode 7/12).
- `news.order.payment` — `typeId`, `online`, `shipping`, `discount`, `voucher`, `subtotal`, `currency`, `remaining`, `partial`. No raw card/payment-instrument data found in this object (amounts and flags only).
- `news.extraData` — `branch`, `chain`, `platform`, `client` (business name), `region`, `country`. Set consistently across **every** platform interface (thirdParty, uberEats, pedidosYa, rappi, mercadoPago, glovo — all confirmed via grep). This means Grido-branded news can be filtered by `extraData.chain` regardless of which delivery platform the order originated from — not limited to the dedicated "PediGrido" channel.
- `news.order.tenant` — `{ name, orgId, tenantId }` (thirdParty.js:47-51). `assets/tenants.js` lists tenant `grido` (`orgId: org_g4qPlLbxcJZx5e7U`, `tenantId: d3186bc6d7b2`) alongside `weiss`, `lodejacinto`, `ultracai`, `otros`.
- "PediGrido" as a channel name appears throughout `platforms/management/platform/rapiboy.js` (log messages reference `platform: 'PediGrido'` even though the class is literally named `rapiboy.js` — naming predates a rename, not yet cleaned up). Grido-branded orders also arrive via PedidosYa (`pedidosYa.js:508-509`, `detailsMapperParseGrido` gated on `tenant.name === "grido"`) and UberEats (hardcoded `"accepted_by": "Grido"` string at uberEats.js:170,290).
- `traces[]` stores an `update: Object` snapshot per state transition (received → viewed → confirmed → ready → dispatched → delivered/rejected). **Confirmed against real data (20,000-doc random sample of 357,470 total):** `traces[].update` never contains a `customer` key — only internal state fields (`orderStatusId`, `typeId`, `isValid`, `platformResult`, `deliveryTimeId`, `updatedAt`). No PII re-embedding risk.
- **Real-data validation (2026-08-18)**, via `grido_news_raw.json` (357,470 Grido-chain documents, exported with `mongoexport`, sampled 20,000 with `jq`/`python3`):
  - Core PII population rate: `name` 100%, `phone` 93.6%, `address` 91.9% — present on nearly every order, not an edge case.
  - `email` 24.2%, `dni` 23.7%, `numeroTarjetaLoyalty` 15.4% non-null — real PII, populated on a meaningful minority.
  - `order.observations` (free text) **confirmed to leak PII**: billing names, RUC/CI/DNI numbers, and customer phone numbers appear directly in the text (e.g. `"Facturar a empresa: [name] - Nro.: [id]"`, `"Llámame cuando llegues [phone]"`). Must be REDACTed, not just reviewed.
  - `details[].optionalText` (free text) — sampled values are exclusively product-customization notes (flavors, substitutions). No PII found; safe to send.
  - Two ad-hoc fields not present in the schema/mapper source reviewed, found via real-data scan (`strict: false` in action): `order.type` (`"DELIVERY"`) and `order.delivery_operation_type` (`"regular"`/`"turbo"`) — both operational, no PII.
  - `rejectedMessageId` — 0 occurrences across all 357,470 documents for Grido; schema field, effectively unused for this chain.

## Conclusion

`news` documents carry substantial customer PII (name, phone, address, email, DNI) plus Club Grido loyalty-program identifiers (`numeroTarjetaLoyalty`, `contieneCanje`, `puntosCanjeados`) embedded directly in `order.customer`, present on nearly every order regardless of platform. Confirmed against real data, not just schema/source review. This is **not** safe to forward to S3 as-is for an ETL — see `field-classification.md` for the field-by-field allow-list (SEND/REDACT/SEND-COND). Order/menu/operational fields (`details`, `payment` amounts, `extraData`, `typeId`, timestamps, `branchId`, `traces[]`) are confirmed safe to share as-is.

## Deliverables

- `field-classification.md` — field-by-field SEND / SEND-COND / REDACT table, validated against real data. This is the proposed export allow-list for GITIN-1874.
- `grido_news_raw.json` — full raw internal dump (357,470 docs, 1.1GB, includes PII), kept **local and untracked** — too large for GitHub's 100MB push limit even if the PII exposure were acceptable to commit. Internal cross-checking only, not part of the repo history.

## Open questions / next steps

- One item remains unresolved by data alone: `customer.id` and `customer.numeroTarjetaLoyalty` are classified SEND-COND in `field-classification.md` — confirm with PM/Legal whether the Grido data-sharing agreement for this ETL actually covers these fields before GITIN-1874 builds against them as "safe to send."
- Confirm actual volume/date range trimming needed to size the ETL itself (GITIN-1874's concern, not this subtask's).

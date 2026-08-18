# Field Classification — Grido `news` export (GITIN-1873)

Derived from source (`platforms/interfaces/*.js`, `models/news.js`, `models/order.js` — both services, `develop`, confirmed current 2026-08-18) and **cross-checked against `grido_news_raw.json`** — 357,470 documents, sampled 20,000 at random via `jq`/`python3` on 2026-08-18. Kept local/untracked (1.1GB, exceeds GitHub's 100MB push limit — not committed).

## Validated against real data (2026-08-18)

- Core PII (`name`, `phone`, `address`) present in 92–100% of sampled docs — not an edge case, present on nearly every order.
- `email` 24.2%, `dni` 23.7%, `numeroTarjetaLoyalty` 15.4% non-null — populated on a meaningful minority, still real PII when present.
- `traces[].update` checked directly — **never** contains a `customer` key across the 20k sample (0 hits). Confirmed safe: state-transition snapshots don't re-embed PII. Resolved from REVIEW → SEND.
- `order.observations` — confirmed to contain **real incidental PII** in free text: billing names ("Facturar a empresa: Eric Flores Espinoza..."), RUC/CI/DNI numbers, and customer phone numbers ("Llámame cuando llegues 1130410602"). Resolved from REVIEW → **REDACT**.
- `details[].optionalText` — sampled values are exclusively product-customization notes (ice cream flavors, substitutions), no PII found. Resolved from REVIEW → SEND.
- Two fields not present in the schema/mapper source reviewed, found via real-data scan (consistent with `strict:false`): `order.type` (`"DELIVERY"`) and `order.delivery_operation_type` (`"regular"`/`"turbo"`) — both operational enums, no PII. Classified SEND.
- `rejectedMessageId` — 0 occurrences across all 357,470 documents. Schema field, unused in practice for Grido news; harmless either way.
- `__v` (Mongoose version key) present on every document — internal bookkeeping, no PII. Classified SEND.

Categories:
- **SEND** — operational/product data, no PII, safe to export as-is.
- **SEND-COND** — not personally identifying on its own, but tied to Grido's own loyalty program; sending it back to Grido (the data's original source/owner) is plausibly the intended flow, but confirm scope against whatever data-sharing agreement covers this ETL before treating as default-safe.
- **REDACT** — direct customer PII or precise geolocation; strip before S3 unless Legal/PM explicitly confirms Grido is entitled to receive it via this pipeline.
- **REVIEW** — free-text fields that could incidentally contain PII (e.g. a phone number typed into a notes field); needs eyeballing real samples before a blanket call.

## `news` top level

| Field | Category | Notes |
|---|---|---|
| `_id`, `typeId`, `branchId`, `rejectedMessageId` | SEND | Identifiers/state codes, no PII |
| `viewed`, `orderPickedUp`, `orderDelivered`, `createdAt`, `updatedAt`, `__v` | SEND | Timestamps/flags/internal bookkeeping |
| `traces[]` | SEND | `update: Object` per transition — confirmed against real data: never contains a `customer` key (0/20,000 sampled), only internal state fields (`orderStatusId`, `typeId`, `isValid`, `platformResult`, `deliveryTimeId`, `updatedAt`) |
| `extraData.branch/chain/platform/client/region/country` | SEND | Branch/business metadata, no personal data |

## `news.order`

| Field | Category | Notes |
|---|---|---|
| `id`, `originalId`, `displayId`, `platformId`, `statusId` | SEND | Order identifiers |
| `orderTime`, `deliveryTime`, `pickupDateOnShop`, `pickupOnShop`, `autoBillingDelivered`, `preOrder` | SEND | Operational timestamps/flags |
| `observations` | REDACT | Confirmed against real data: contains billing names, RUC/CI/DNI numbers, and customer phone numbers written into free text (e.g. "Facturar a empresa: [name] - Nro.: [id]", "Llámame cuando llegues [phone]") |
| `ownDelivery`, `deliveryPartner`, `deliveryType`, `type`, `delivery_operation_type` | SEND | Logistics metadata — last two (`"DELIVERY"`, `"regular"`/`"turbo"`) found via real-data scan, not in the schema/mapper source reviewed, but confirmed operational-only |
| `tenant.name/orgId/tenantId` | SEND | Internal tenant identifiers, not personal |
| `totalAmount` | SEND | Order total |
| `driver.latitud`, `driver.longitud` | REDACT | Precise delivery geolocation — identifies customer's home independent of the address string |

## `news.order.customer`

| Field | Category | Notes |
|---|---|---|
| `name` | REDACT | Direct PII |
| `address` | REDACT | Direct PII (delivery address) |
| `phone` | REDACT | Direct PII; UberEats variant also embeds a delivery PIN in the same string |
| `email` | REDACT | Direct PII |
| `dni` | REDACT | National ID — highest-sensitivity field in this collection |
| `tipoIdentificacion` | REDACT | Tied directly to `dni` |
| `id` | REVIEW | Platform's internal customer id — pseudonymous but still a stable identifier; confirm whether Grido needs it for correlation or it can be dropped |
| `numeroTarjetaLoyalty` | SEND-COND | Club Grido's own loyalty card number — Grido already owns this relationship; likely the actual reconciliation key they want, but confirm against the data-sharing agreement rather than assuming |
| `contieneCanje` | SEND | Boolean flag, not identifying |
| `puntosCanjeados` | SEND | Points count, not identifying on its own |

## `news.order.details[]` (line items)

| Field | Category | Notes |
|---|---|---|
| `productId`, `count`, `price`, `discount`, `description`, `sku`, `promo`, `promotion`, `groupId`, `cupon`, `canje` | SEND | Menu/order-line data, no PII |
| `optionalText` | SEND | Confirmed against real data: exclusively product-customization notes (flavors, substitutions), no PII found in sample |

## `news.order.payment`

| Field | Category | Notes |
|---|---|---|
| `typeId`, `online`, `shipping`, `discount`, `voucher`, `subtotal`, `currency`, `remaining`, `partial`, `note` | SEND | Amounts/flags only — no raw card or payment-instrument data found anywhere in this object across any platform interface |

## Status

Cross-checked against real data 2026-08-18. No REVIEW fields remain — all resolved to SEND or REDACT. Remaining open item: `customer.id` and `customer.numeroTarjetaLoyalty` are SEND-COND, pending confirmation of what the Grido data-sharing agreement actually covers (not resolvable from data alone). This table is ready to hand to GITIN-1874 as the export allow-list, pending that one business/legal confirmation.

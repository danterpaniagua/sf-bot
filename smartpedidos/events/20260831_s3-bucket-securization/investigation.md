# Investigation — 20260831_s3-bucket-securization

**Jira:** [GITIN-1880](https://smartit-ar.atlassian.net/browse/GITIN-1880) ("[SP] Securización de S3"), sibling subtask of GITIN-1872 (parent, "[SP] Envío de datos de SP a Grido"), alongside GITIN-1873 (converged, `smartpedidos/events/20260818_grido-news-etl-s3/`), GITIN-1874 ("[SP] Creación de ETL -> S3" — **corrected 2026-09-02**: confirmed the *new* Python Lambda this folder describes below, `smartpedidos/events/20260901_grido-redacted-etl-lambda/`, not the existing `mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO` as originally assumed here), GITIN-1970 (UTC-3 export fix, `smartpedidos/events/20260831_lambda-s3-export-utc3/`, closed 2026-08-31).

**Status: DONE (2026-09-16).** Bucket created, Lambda pipeline confirmed live (built under GITIN-1874, not this ticket), Phase 2 access-security policy applied and functionally verified (`403` on an unauthorized anonymous request). This closes the last open subtask of GITIN-1872 — all 8 subtasks now complete, PM email no longer blocked.

## Progress

- **Bucket created (2026-08-31):** `smartpedidos-orders`, `us-east-1`, confirmed via `aws s3api create-bucket` (`data/create_bucket_result.json`) — `arn:aws:s3:::smartpedidos-orders`.

## Scope

**Correction (2026-08-31):** user's first framing of this event ("creation and securization of s3 bucket") was right — this is a **new, dedicated bucket** for this Grido export feature, not a security change to the existing `smartfranbkp` bucket. An earlier note in this file briefly recorded "targets the existing `smartfranbkp` bucket" as confirmed; that was wrong, corrected in place rather than left standing.

Requirement, phased:
- **Phase 1 (now):** new bucket, public (or at least not IP-restricted yet).
- **Phase 2 (later, once Grido's backend is stood up):** restrict access to only Grido backend's source IP(s)/CIDR.

**Resolved (2026-08-31):** the existing `mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO` Lambda (Node.js, GITIN-1970 — **not** GITIN-1874, corrected 2026-09-02, see header) is **not** repointed and stays as-is, writing to `smartfranbkp`. This new bucket + its access security is paired with a **new, separate Lambda — Python runtime, confirmed as GITIN-1874, built and validated as of 2026-09-02, see `smartpedidos/events/20260901_grido-redacted-etl-lambda/`**. That Lambda reads from `smartfranbkp/news/*-3.json` (the `-3` files produced by the Node.js Lambda above) and writes a filtered/redacted subset into this bucket — relationship now fully established.

**Resolved (2026-08-31):** new bucket name confirmed by user: **`smartpedidos-orders`** (renamed from an initial `smartpedidos-grido-orders` once scope clarified it'll hold multiple platforms, not Grido-only — see multi-platform note below). Region assumed `us-east-1` (matches rest of pipeline) — not explicitly confirmed by user, flagging.

**Multi-platform design confirmed (2026-08-31):** bucket will hold per-platform prefixes (e.g. `grido/`, `peya/`), each with independent IP-based access restriction via separate bucket-policy `Deny` statements scoped by `Resource` prefix + `NotIpAddress` condition — one statement per platform, no cross-statement interference since `Resource` ARNs don't overlap. Not yet applied (Phase 2 work, pending each platform's actual IP/CIDR); bucket creation itself is the immediate step.

**Not yet resolved — needs user input:**
1. What does the new Python Lambda actually do — read from `smartfranbkp` and copy/transform into the new bucket, or something unrelated to the existing `news` export pipeline? User confirmed (2026-08-31) it "would put some filters" — very likely implementing the REDACT/SEND-COND/SEND classification from `smartpedidos/events/20260818_grido-news-etl-s3/field-classification.md`, not yet explicitly confirmed as the same spec.
2. Is building the new Python Lambda itself in scope for this ticket/session, or is GITIN-1880 specifically about the bucket + its access security, with the Lambda tracked elsewhere? User directed (2026-08-31): "first lets create bucket. 1880 scope" — bucket creation is the immediate focus; Lambda build deferred, not ruled in or out of this ticket.

**Separately flagged, unresolved (2026-08-31):** the currently-deployed `mongo-to-s3-CFN-ScheduledMongoToS3-1EZXBGD94CJVO` Lambda writes raw, unredacted customer PII (`name`, `address`, `phone`, `dni`, `email`) into `smartfranbkp/news/` — confirmed directly against a real sample record pulled during `20260831_lambda-s3-export-utc3/`. Matches the REDACT list in `field-classification.md` exactly. This is a live production exposure, independent of this new bucket's design — user has not yet said whether/how this gets addressed.

## New export field allow-list (2026-08-31)

User provided a proposed field list for the new bucket/Lambda's output. Cross-checked against `field-classification.md`'s SEND/REDACT categories — mostly matches (correctly drops `name`, `address`, `phone`, `email`, `tipoIdentificacion`, `numeroTarjetaLoyalty`, `driver.lat/long`, `traces[]`), but two fields conflict:

- **`order.customer.dni`** — classified REDACT ("highest-sensitivity field in this collection"). User's stated justification: needed as a correlation key with Grido's own customer DB. Recorded as the pipeline's confirmed decision, but `field-classification.md`'s own REDACT definition requires *"Legal/PM explicitly confirms Grido is entitled to receive it"* before overriding — **not yet confirmed whether that sign-off exists**, only that it's operationally needed.
- **`order.observations`** — classified REDACT. **Reconfirmed with a fresh real sample (2026-08-31, `data/observations_sample.json`, 20 documents via `scripts.js`, gitignored — not committed):** 13/20 sampled records contain a full customer name + RUC/CI/DNI number via a `"Facturar a..."` billing pattern; most also embed a PedidosYa-generated per-order proxy email. This is the majority pattern in this field, not an edge case. **Resolved (2026-08-31): excluded from the first version of the new export allow-list.**

### Confirmed v1 field allow-list (2026-08-31)

`order.id`, `order.originalId`, `order.displayId`, `order.platformId`, `order.statusId`, `order.orderTime`, `order.deliveryTime`, `order.pickupOnShop`, `order.pickupDateOnShop`, `order.preOrder`, `order.ownDelivery`, `order.customer.id`, `order.customer.dni` (pending Legal/PM sign-off confirmation, see above), `order.details[]` (`productId`, `count`, `price`, `promo`, `groupId`, `discount`, `description`, `sku`, `canje`), `order.totalAmount`, `branchId`, `createdAt`, `typeId`, `updatedAt`, `viewed`. **`order.observations` excluded.** Not yet written to a standalone file — living here until the Python Lambda work actually starts.

**User confirmed (2026-08-31): this is the scope for now.**

**Correction (2026-08-31), immediately after the above was recorded:** user clarified the data actually going into `smartpedidos-orders` is **PediGrido-only for now** (bucket's multi-platform prefix structure remains as designed for future use, but current scope is single-platform). This matters directly: the `observations` sample used to confirm the REDACT exclusion (`data/observations_sample.json`) was **not** filtered by tenant/platform and came back showing exclusively PedidosYa-style `@invoices.pedidosya.com` records — i.e., the evidence backing that exclusion decision may not actually represent the platform this pipeline serves. **No longer a deferred/low-priority item** — a validation query needs to run before the `observations` exclusion (and the rest of the field allow-list) can be considered validated against the real in-scope data, not just PediGrido-adjacent evidence.

**Filter criterion, reversed again (2026-09-01):** confirmed by user directly — the export's scope filter is **`order.tenant.name: "grido"`**, reversing the 2026-08-31 entry immediately above (which had itself corrected away from `tenant.name` to `extraData.platform: "PediGrido"`). `tenant.name: "grido"` is now the confirmed criterion. `scripts.js`'s second query block needs updating back to match — currently still set to `extraData.platform`.

**Third filter field surfaced (2026-09-01):** neither of the two candidates above is what the original PII validation evidence actually used. `field-classification.md`'s `grido_news_raw.json` (357,470 docs, the dataset behind every population-rate figure in that file) was built from `scripts.js` query 1 in `20260818_grido-news-etl-s3/`, filtered on **`extraData.chain: /grido/i`** — a third, broader field (deliberately chosen there specifically because it's platform-agnostic — see that investigation's note that Grido orders arrive via multiple platforms, not just the PediGrido channel). So: `chain` (broadest, evidence base), `platform` (single named channel, briefly the confirmed export filter), `tenant.name` (now the confirmed export filter) are three different fields, likely highly correlated but not verified identical. **Not yet re-validated:** whether `field-classification.md`'s REDACT/SEND classifications (especially the `observations` exclusion, already flagged as needing re-validation once) actually hold when scoped by `tenant.name: "grido"` specifically, rather than the `chain`-filtered data they were derived from.

**Design direction still applies once these are resolved:** standard S3 bucket-policy pattern for Phase 2 — explicit `Deny` statement with a `NotIpAddress` condition on `aws:SourceIp`, scoped as tightly as the ticket allows.

## Confirmed facts

- Bucket `smartpedidos-orders` exists (`us-east-1`), created 2026-08-31, left in S3's default (public-access-blocked) state.
- This export's scope filter is **`order.tenant.name: "grido"`** (confirmed 2026-09-01, reversing the prior `extraData.platform: "PediGrido"` entry — see the filter-criterion history above for the full flip-flop and the third `extraData.chain` field the original PII evidence actually used). Bucket's prefix structure (`grido/`, `peya/`, etc.) remains designed for future multi-platform use, but no other platform is in scope yet.
- The existing `smartfranbkp` bucket and its Node.js `mongo-to-s3` Lambda are untouched by this ticket — this is a new, separate bucket + a new, separate Python Lambda (not yet built).
- `smartfranbkp` itself holds many unrelated top-level prefixes (`activeSoftware/`, `branches/`, `chains/`, `orders/`, etc. — confirmed via `20260831_lambda-s3-export-utc3/data/s3_ls_root.txt`), which is *why* a new dedicated bucket was chosen over modifying `smartfranbkp`'s access policy.
- V1 field allow-list is defined (see above) — confirmed matching `field-classification.md`'s SEND fields, `observations` excluded (REDACT, reconfirmed via fresh sample), `customer.dni` included (REDACT, but user-confirmed operational need — Legal/PM sign-off not yet independently verified).

## Current working theory

The new Python Lambda reads `news` records filtered to **`order.tenant.name: "grido"`** (corrected 2026-09-16 — this section still referenced the superseded `extraData.platform: "PediGrido"` filter; see "Confirmed facts" for the actual confirmed criterion), applies the confirmed v1 field allow-list (dropping `observations` and everything else not on the list), and writes into `smartpedidos-orders`. Not yet confirmed whether it reads from `smartfranbkp/news/` (already-exported data) or queries MongoDB directly like the existing Lambda does — this distinction hasn't been asked yet.

## Ruled out

- ~~This ticket is a security-policy change to the existing `smartfranbkp` bucket~~ — corrected early on; it's a new dedicated bucket instead.
- ~~The existing Node.js Lambda gets repointed to the new bucket~~ — confirmed staying as-is; a separate Python Lambda handles the new bucket.

## Open questions / next steps

1. ~~Validate the `observations` exclusion against real Grido-scoped data~~ — **moot (2026-09-16).** GITIN-1874 already resolved this independently, with stronger evidence than our own PII sampling: `observations` is excluded entirely from the live output, per Grido's own confirmed field request (not just an internal REDACT classification). See `20260901_grido-redacted-etl-lambda/investigation.md`, "Field allow-list narrowed."
2. ~~Confirm Legal/PM sign-off for `customer.dni`~~ — **resolved as "deliberate deviation, not oversight" under GITIN-1874** (2026-09-02): `dni` is genuinely in Grido's own field request; a formal Legal/PM sign-off distinct from Grido's own request/operational need was never confirmed despite being asked three times, and the user's consistent answer is being treated as the final record. Same open nuance carries over here, not re-litigated separately.
3. ~~Build the new Python Lambda~~ — **done, under GITIN-1874, not this ticket.** `grido-redacted-etl`, deployed, historical backfill complete (2026-05-01–2026-09-01), daily EventBridge schedule live since 2026-09-03. This ticket's own scope was bucket creation + access security only (per the 2026-08-31 user direction "first lets create bucket. 1880 scope") — the Lambda ended up built under 1874 instead, which is fine, just means nothing further is needed here on that front.
4. ~~Phase 2 access policy~~ — **applied (2026-09-16).** Block Public Access settings adjusted (`put-public-access-block`, all four flags `false`), then the policy applied (`put-bucket-policy`) and confirmed live via `get-bucket-policy` (`data/get_bucket_policy_confirm.json`) — matches the drafted policy exactly: public read on `grido/*`, denied outside `40.121.111.127/32`. **Functionally verified (2026-09-16):** anonymous request from a non-allowed IP returned `403` as expected — the `Deny`/`NotIpAddress` condition is genuinely enforcing, not just syntactically present. Phase 2 complete.
5. Review whether the bucket's current default (public-access-blocked) state is actually the desired "Phase 1: public" state — directly tied to item 4, resolve together.
6. Separately, still unresolved: the unredacted-PII exposure in the existing `smartfranbkp/news/` (different bucket, different Lambda, flagged but not this ticket's scope) — decide if/how that gets addressed, and by which ticket.

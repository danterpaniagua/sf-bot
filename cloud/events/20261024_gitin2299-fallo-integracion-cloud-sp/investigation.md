# Investigation: GITIN-2299 — [CLOUD] Fallo integración CLOUD - SP (new POS on franchise 5435)

**Status (2026-10-24): open, in progress.** Jira: https://smartit-ar.atlassian.net/browse/GITIN-2299 (title as given by the user; body not seen).

## Symptom
Integrating Cloud franchise 5435 to SmartPedidos fails with: "La cola ya se encuentra asignada a otra franquicia,no es posible asignar la misma ya que una cola no puede ser compartida."

## Source of the error (verified in code)
- `SmartFran.Cloud/Source/Services/Orders/SmartFran.Cloud.Orders.Application/Services/QueueServices.cs`, method `CheckStatusQueue` (~lines 176-190). Read on `main` @ `e00e8c467` (working tree of `cloud/repo/SmartFran.Cloud`).
- Looks up queue records by `BranchId` (SmartPedidos branch id). Returns the message with StatusCode 300 when the stored `FranchiseId` differs (case-insensitive) from the request's `FranchiseId` AND the stored record has `Active == true`.
- Not found in the SmartPedidos repos (platformsService, concentradorService, backOffice); the message is Cloud-side.
- `AddUpdateQueue` (same file) keys on `BranchId` too; QueueName = BranchId + configured suffix.

## Hypotheses (none verified)
- H1: the BranchId in the payload is shared with / reused from another franchise.
- H2: FranchiseId in the request differs in value/format from the stored one.
- H3: a stale active queue record for that branch was never deactivated.

## Needed (user to run and paste; save to `data/`)
- Cosmos query on the Orders queue container: `SELECT c.id, c.BranchId, c.FranchiseId, c.FranchiseeId, c.QueueName, c.Active, c.Checked FROM c WHERE c.BranchId = "<BRANCHID>"`
- The failing request payload (FranchiseId, BranchId), sensitive values masked.

## Update 2026-10-24 (code reading, `main` @ `e00e8c467`)
- Request built in `SalePoint.razor.cs` `CheckStatusQueue`: `BranchId` = value of the SmartPedidos integration "user"/"usuario" property of the sale point; `FranchiseId` = `model.CloudCode`. So 5435 is probably the `FranchiseId` (Cloud code), not the BranchId — not confirmed.
- `QueueDirectoryRepository` reads container `Queues` using `OwnerProvider.GetSettings("platform")` = config `ConnectionSettings:Tenant_platform:OrderCosmosSettings`. Account and database are therefore config values, not visible in code. `smartfran-cloud-cosmos-platform-pro` is a guess from the name.
- Entity `AwsSQSQueue` has no JSON name attributes: stored properties are `BranchId`, `FranchiseId`, `Active`, etc. (PascalCase; `id` lowercase), so the query field names are correct.
- Cosmos query `WHERE BranchId = "<SP user>" OR FranchiseId = "5435"` returned empty (user-reported, no file). That contradicts the error, so one assumption is wrong: account/database/container, the value queried (exact, case-sensitive match needed), or environment (error seen in another env).
- Next: obtain the `AccountEndpoint` and `DataBaseName` of Tenant_platform (never the key), the exact SP user string, and the environment where the error appeared.

- 216 documents in the `Queues` container queried (data/queues-count.json; account/db used by the user not recorded). Small directory, consistent with one record per branch, so the container is plausibly the right one; the earlier empty result then points at the filter value. Not confirmed.

## Finding 2026-10-24: queue record for 5435 (data/queues-5435-loose.json, user-pasted, container `Queues`)
- One record: `BranchId` = `5435` (so 5435 is the SmartPedidos user/BranchId, not the Cloud franchise code), `FranchiseId` = `914ef6053ea441b38ce756d7de7d17ff` (32 hex, no dashes), `Active` = true, `Checked` = 2025-12-17, queue `5435PRD_PlatformMessages.fifo`.
- With `Active` true, `CheckStatusQueue` returns the error whenever the request's `FranchiseId` (`model.CloudCode` of the franchise being integrated) differs, ignoring case, from that stored value. Dashes are not ignored.
- Still unknown: what `CloudCode` the franchise being integrated has, and which Cloud franchise `914ef605...` is. Possibilities: (a) another franchise really holds branch 5435 (reused/duplicated SP user, or the branch moved between franchises); (b) same franchise but `CloudCode` is in another format (e.g. with dashes). Not distinguished yet.
- Do not edit or deactivate the record until (a) vs (b) is known.

## Code reading 2026-10-24: format of CloudCode (`main` @ `e00e8c467`)
- `BusinessEntity.CloudCodeId` is a Guid; `GetCloudId()` returns it lowercase without dashes, the same format as the stored `FranchiseId` (`914ef605...`). A pure format mismatch (hypothesis b) is therefore unlikely, but not excluded: the value actually sent is `model.CloudCode` and was not seen.
- `Franchise` is an EF entity in the tenant SQL Server `Business_<TENANT>` database (not Cosmos). The queue directory is platform-wide, so a cross-tenant clash (same SP user in two tenants) is possible. Dashed form of the stored id: `914ef605-3ea4-41b3-8ce7-56d7de7d17ff`.
- Table/column names for the SQL lookup are assumed from EF conventions, not verified.

## Finding 2026-10-24: franchise lookup (data/franchise-lookup-business-pro.json, user-pasted, SmartFran.Cloud.Business_PRO; server not recorded)
- Query matched `Franchise.CloudCodeId = 914ef605-...` OR `Franchisee.CloudCodeId = 84EEE278-...`. Only one row came back: Franchise Id 54, `CodeSmartLogicId` 5435, `CloudCodeId` 040fdf5d-61c6-46cb-9b39-465291971e5d, franchisee 84eee278-... (same as the `FranchiseeId` in the queue record).
- So the franchise being integrated (code 5435) has a different `CloudCodeId` (`040fdf5d61c646cb9b39465291971e5d` without dashes) from the `FranchiseId` stored in the queue record (`914ef605...`), and no franchise with `914ef605...` exists in that database (neither as hard row; soft-delete not checked).
- Inference, not confirmed: the franchise was deleted and recreated (new CloudCodeId) and the queue record kept the old id while staying Active. `AddUpdateQueue` keeps the existing record's `FranchiseId` on update (QueueServices.cs), so it does not self-heal.
- Not yet checked: whether the franchise was recreated (history), whether other `Queues` records carry `914ef605...`, and which server (GRIDO/WEISS) was queried.

## Finding 2026-10-24: Queues filtered by both FranchiseId values (data/queues-by-franchiseid.json, user-pasted)
- Query `FranchiseId = 914ef605... OR 040fdf5d...` on `Queues` returned only the 5435 record (stored `914ef605...`). No record carries `040fdf5d...` and no other record carries `914ef605...`.
- Consistent with a stale `FranchiseId` on a single record. Still unverified: franchise recreation history, and whether `914ef605...` exists in the other tenant's database.
- Proposed fix (not applied): set that record's `FranchiseId` to `040fdf5d61c646cb9b39465291971e5d`; rollback value `914ef6053ea441b38ce756d7de7d17ff`.

## Correction 2026-10-24 (user): scope is a NEW POS (sale point) on existing franchise 5435, not a franchise integration
- The error comes from the sale point save in the Cloud UI (`SalePoint.razor.cs` `ValidateSmartPedidos` -> `CheckStatusQueue`), which sends the SP "usuario" typed on the new POS as `BranchId` and the franchise's `CloudCode` as `FranchiseId`. The earlier findings still apply, but the typed SP user was never seen: record `BranchId` 5435 was found by a loose search on "5435", not by the typed value.
- If the new POS uses SP user `5435` (same as the franchise's existing POS), the stale `FranchiseId` explains the block. If it uses another user, this record is not the cause. Unverified.
- The check only runs when saving a sale point, so an existing POS on 5435 can keep working with the stale record; whether orders flow for 5435 today was not checked.
- Fix NOT applied; wait for the typed SP user and request body.

## Confirmed 2026-10-24 (user-reported): the "usuario" typed on the new POS is `5435`
- The typed SP user equals `BranchId` 5435, so the blocking record is `5fdb3cfa-...` (stored `FranchiseId` `914ef605...`, Active) and the sent `FranchiseId` is the franchise's `CloudCodeId` `040fdf5d...` (Business_PRO, Franchise Id 54). The request body itself was not captured.
- Local clone fetched 2026-10-24: `origin/main` = `651507880` (PRO v02.50.00); `QueueServices.cs`, `SalePoint.razor.cs`, `QueueDirectoryRepository.cs`, `OwnerProvider.cs` identical to the clone's `e00e8c467`; `origin/dev` equals `origin/main` for the first two.
- Cause of the stale id (franchise recreated) remains an inference. Fix proposed, pending execution: update `FranchiseId` on the record to `040fdf5d61c646cb9b39465291971e5d`; rollback `914ef6053ea441b38ce756d7de7d17ff`.

## Revalidation 2026-10-24 (ids recomputed from data/*.json; WEISS lookup)
- Ids recomputed: stored `914ef6053ea441b38ce756d7de7d17ff` = `914ef605-3ea4-41b3-8ce7-56d7de7d17ff` (the value used in the SQL lookups); franchise 54 `040fdf5d-61c6-46cb-9b39-465291971e5d` = `040fdf5d61c646cb9b39465291971e5d` (the proposed fix value). Stored and sent ids differ.
- `Franchise.CloudCodeId = 914ef605-...` on `t102-smartfran-cloud-weiss / SmartFran.Cloud.Business_WEISS`: empty (data/franchise-914ef605-weiss.txt). The earlier lookup (franchise 54) was run on a database named `SmartFran.Cloud.Business_PRO`, which appeared in the t101 (GRIDO) database list, so it was most likely GRIDO; the user did not state the server explicitly.
- Result: `914ef605-...` found in neither tenant's business database as a `Franchise.CloudCodeId`. Not checked: soft-deleted rows, other tables referencing the id, the actual request body.

## 2026-10-24 (user-reported): the same error happens with SP user/BranchId 3717
- Not yet checked. If `Queues` record 3717 also has a `FranchiseId` that exists in no business database, the stale id is systemic (many records), which weakens the "single franchise recreated" explanation. Fix for 5435 on hold until the bulk comparison (all `Queues` FranchiseIds vs all `Franchise.CloudCodeId`) is done.

## Finding 2026-10-24: Queues record for 3717 (data/queues-3717.json, user-pasted)
- `BranchId` 3717, `FranchiseId` `25ddc5e35be7484e816ec3fba020f0b0`, franchisee `73A6CE8B-...`, Active, queue `3717PRD_PlatformMessages.fifo`, `Checked` 2025-12-17T01:41:41.44Z.
- `Checked` of 5435 is 2025-12-17T01:41:41.94Z: same second, 0.5 s apart. Suggests one bulk process touched several records at that moment. Source of that process not identified; only two records seen.
- Not yet checked: whether `25ddc5e3-5be7-484e-816e-c3fba020f0b0` exists as `Franchise.CloudCodeId` in either tenant, and which `CloudCodeId` the franchise with `CodeSmartLogicId` 3717 has.

## Finding 2026-10-24: Queues GROUP BY FranchiseId, Active (data/queues-all-franchiseids.json, user-pasted, transcribed to compact JSON by line)
- 100 groups, 153 documents in the result vs 216 in the container (data/queues-count.json): 63 documents are not in the GROUP BY output. Cause not verified; likely documents where `FranchiseId` is absent (undefined) rather than null, which Cosmos GROUP BY may drop. Check with `WHERE NOT IS_DEFINED(c.FranchiseId)`.
- 51 documents have `FranchiseId` = null and Active = true. 102 documents have a non-null id (98 distinct ids ignoring case): 3 ids appear on 2 records each (plausible: franchise with two branches), 1 id is uppercase (`D0D1EDC2...`), 2 documents are inactive (one of them shares its id with an active one).
- Code reading (QueueServices.cs `CheckStatusQueue`, main @ 651507880 identical): the comparison is `queue?.FranchiseId?.ToLower() != queueMap.FranchiseId?.ToLower() && queue?.Active == true`. For a stored null and a non-null sent value this is true, so by reading the code an Active record with null `FranchiseId` would block any POS save sent with a FranchiseId. Not tested. `AddUpdateQueue` keeps the stored `FranchiseId`, so it would not repair it.
- Still not done: comparing the 98 non-null ids to the real `Franchise.CloudCodeId` lists of both tenants (SQL query still pending).

## Finding 2026-10-24: franchise list from a tenant database (data/franchises-weiss.json, moved from out.txt; tenant inferred from the franchise names, not stated by the user)
- 20 franchises (names such as Tigre, Canning, Punta del Este, Mendoza, Caballito, a Weiss test store) — looks like WEISS. None of the 98 distinct non-null `FranchiseId` values in `Queues` is in this list; neither are `914ef605...` (5435), `25ddc5e3...` (3717) or `040fdf5d...` (5435's current id), which fits: 5435/3717 are in the other tenant.
- So the WEISS list confirms nothing about 5435/3717. Still needed: the same query on the GRIDO database (`t101`, `SmartFran.Cloud.Business_PRO`).

## Finding 2026-10-24: GRIDO franchise list (data/franchises-grido.json, moved from out.txt; user said "from t101", database not named — assumed SmartFran.Cloud.Business_PRO)
- 478 franchises. Comparison with the 98 distinct non-null `FranchiseId` in `Queues` (data/queues-all-franchiseids.json): 62 are in the GRIDO list, 36 are not (none of the 36 is in the WEISS list either).
- `914ef605...` (5435) and `25ddc5e3...` (3717) are among the 36 absent; `040fdf5d...` (5435's current id) is in the list.
- 38 active documents carry a non-null id absent from the GRIDO list (this counts documents, not branches; the 51 null-id documents and the 63 documents missing from the GROUP BY are separate).
- Not yet done: mapping each queue's `BranchId` to the current franchise via `CodeSmartLogicId` (5435 matches `BranchId` 5435), which needs a full dump of the 216 `Queues` documents (GROUP BY did not return `BranchId`).

## Finding 2026-10-24: first page of the full dump (data/queues-full-page1.json, 100 of 216 documents; Data Explorer page limit)
- Classification of the 100 (franchise lists: data/franchises-grido.json + data/franchises-weiss.json; join by `BranchId` = `CodeSmartLogicId`, which holds for 5435):
  - 51 active, stored id exists (GRIDO); 2 inactive with existing id.
  - 38 active, stored id in neither list: 34 map to exactly 1 current GRIDO franchise by code, 3 to none, 1 to 2 franchises (ambiguous).
  - 9 active with `FranchiseId` null.
- `Checked` dates: 33 of the 38 stale-id records have 2025-12-17 (same day as 5435/3717); the 9 nulls are spread (6 on 2025-12-17, others 2026-03 / 2026-09). This points to a bulk event on 2025-12-17 that coincides with the stale ids; the nature of that event is not identified.
- Only 100 of 216 documents seen; 116 remain. Counts above are not for the whole container.
- Not tested: the join assumption `BranchId` = `CodeSmartLogicId` beyond 5435; 4 records with an existing id have a franchise whose code differs from their BranchId.

## 2026-10-24: second dump (data/queues-full-page2.json) overlaps the first
- `SELECT ... FROM c ORDER BY c.BranchId OFFSET 0 LIMIT 300` returned only 100 rows (Data Explorer page size), the first 100 by BranchId; 73 are the same documents as `queues-full-page1.json`. Union of both files: 127 distinct documents of 216. Need pages with OFFSET 100 / 200 (or "Load more") and dedupe by `id`.

## 2026-10-24: third dump (data/queues-full-page3.json, OFFSET 100)
- 100 rows, BranchId 5516..5671, no overlap with page2 (BranchId 1..5515). Union of pages 1-3 deduped by `id`: 200 of 216 documents. Remaining 16 expected from `OFFSET 200 LIMIT 100`.

## Complete dump of `Queues` (216 documents; data/queues-full-merged.json from pages 1-4, deduped by `id`; page4 file holds two arrays: a repeat of page 3 + the last 16 rows)
- Classification (franchise lists data/franchises-grido.json + data/franchises-weiss.json; mapping CSV in outputs/queues-franchiseid-mapping.csv): 122 stored id exists (111 GRIDO active, 6 WEISS active, 5 GRIDO inactive); 52 `FranchiseId` null (51 active, 1 inactive); 42 stale (id in neither list): 38 active (34 map to exactly 1 GRIDO franchise by `CodeSmartLogicId` = `BranchId`, 3 to none, 1 to 2) and 4 inactive.
- CORRECTION to the earlier GROUP BY analysis: the pasted GROUP BY result had only 100 groups (153 documents) because Data Explorer pages at 100; the dump has 163 groups. The "63 documents missing" was truncation, not undefined properties, and the earlier "98 distinct ids / 36 absent / 38 active" figures came from that truncated page. The 38 active stale documents coincidentally match the full count. No record lacks the `FranchiseId` key.
- Dates: 33 of the stale records have `Checked` 2025-12-17; of the null ones, 13 have 2025-12-17 and 2 have 2025-12-30. The event of 2025-12-17 is not identified.
- By reading `CheckStatusQueue`: 38 active stale + 51 active null = 89 active records would block a POS save that sends a (different) `FranchiseId`. Not tested beyond 5435 reproducing the error.
- Join `BranchId` = `CodeSmartLogicId` is unverified except for 5435; GRIDO `CodeSmartLogicId` is not unique (some codes map to several franchises).

## Correction 2026-10-24 (user-reported): no change was made; a CaC colleague is the one trying to add the SmartPedidos integration
- The user did not edit any `Queues` record. The previous note ("after the change ... refreshed") rested on a wrong reading and is replaced by this one.
- The two POS (5435, and 3717) show no integration because, by the code, the sale point save is blocked by `ValidateSmartPedidos` before the integration is stored; consistent with the error, not verified against the Business database.
- State of the `Queues` records is unchanged as far as known: last reads were 5435 (data/queues-5435-loose.json) and 3717 (data/queues-3717.json), both Active with the stale ids. No read after the CaC attempts.
- Fix still pending (5435: `FranchiseId` -> `040fdf5d61c646cb9b39465291971e5d`; 3717: candidate `043e7848525d41618478be4f61ee51ef`, from the `CodeSmartLogicId` join, franchise "Quines", not yet confirmed to be the franchise being edited).

## Finding 2026-10-24: franchise for code 3717 (data/franchise-3717-check.json, Business_PRO on t101 assumed)
- Exactly one franchise: Id 15, "Quines", `CodeSmartLogicId` 3717, `CloudCodeId` 043e7848-525d-4161-8478-be4f61ee51ef (hex `043e7848525d41618478be4f61ee51ef`), matching the candidate from the code join. That the CaC is saving the POS under this franchise was not stated.

## 2026-10-24: editing `FranchiseId` in Data Explorer failed — "Entity with the specified id does not exist" (user-reported)
- Code reading (`QueueDirectoryRepository.cs` UpdateCheckedAsync/UpdateActiveAsync, callers in `AmazonServices.cs` lines ~175/196/224, main @ 651507880 same as local): the `Queues` container is addressed with a two-level partition key built as (`FranchiseId`, `BranchId`). Inferred from code, not confirmed in the container settings.
- If so, `FranchiseId` is part of the partition key and a partition key value cannot be changed with an in-place update: the replace looks for the item under the new key and returns not found. Fix needs create-new-item + delete-old-item.
- Consequence for the bulk cleanup: every stale/null-`FranchiseId` record would need the same create+delete, not an update.

## 2026-10-24 17:06 (local): second failure, same message (data/cosmos-replace-error-5435.txt, trimmed)
- OperationType is `Replace` (not `Create`), 404 NotFound, on account `smartfran-cloud-cosmos-platform-pro` (East US endpoint in the trace). This confirms the account that holds `Queues` for the user's session; the container's partition key is still unconfirmed.
- A Replace of the existing item with a changed `FranchiseId` returning 404 is consistent with `FranchiseId` being part of the partition key (inference). It is not known whether the user used "New Item" or edited the existing item.

## 2026-10-24: same "Update document failed" message again (user-reported, no trace this time)
- The message "Update document failed" belongs to the update (Replace) path of Data Explorer, so the edit may still have been made on the existing item rather than through New Item (not confirmed).
- Next attempt: Create with a NEW `id` (outputs/queues-5435-new-item-newid.json) so it cannot be treated as an update of the old item; then delete the old item. Whether anything depends on the old `id` was not checked (the consumer reads `id` from the directory records, `IdCosmos`).

## 2026-10-24: 5435 queue record after the change (data/queues-5435-after-fix.json, user-pasted)
- One record for `BranchId` 5435: new `id` `4f1a186f-205f-42a8-ab19-c6d72a0e7a94`, `FranchiseId` `040fdf5d61c646cb9b39465291971e5d`, Active true, Deleted false. The old record (`5fdb3cfa-...`, `914ef605...`) no longer appears, so it was deleted (the user's actions were not described; backup in data/queues-5435-before-fix.json).
- Not yet known: whether the CaC colleague's POS save now passes, and whether the queue consumer keeps reading `5435PRD_PlatformMessages.fifo`.

## 2026-10-24 (user-reported): "we've lost one SP order"
- No details yet (order id, branch, timestamps, whether it is branch 5435). Not established whether it relates to the 5435 record change (create new item + delete old, ~17:0x local).
- Code reading (`AmazonServices.cs`, clone `main` @ e00e8c467; this file was not diffed against origin/main): the consumer keeps an in-memory `QueueConfiguration` per queue (`Id` = QueueName, `Queue` URL, `TenantId`, `IdCosmos`, `FranchiseId`); polling uses the queue URL and tenant, not `FranchiseId`. On any exception in a worker the queue is removed from `_knownQueues` and `UpdateActiveAsync(q.IdCosmos, ..., q.FranchiseId, q.BranchId)` is tried; with the old `id`/`FranchiseId` of 5435 that update would not find the (deleted) item (logged as warning). `RefreshQueues` re-adds Active, non-deleted queues that are not known; its interval was not read.
- Hypothesis only: `Checked` 2025-12-17 on ~90 records may be the date those queue records were created/added (RefreshQueues sets `Checked` when a queue is added), i.e. a bulk creation, not a later modification. Unverified.

## The "lost" SP order (data/sp-order-2340698376.txt, user-pasted)
- Order 2340698376, PedidosYa, Peru, branch 5435, created 24/10/2026 16:54:01, updated 16:57:30, status Rechazada, reason "Orden rechazada por local cerrado", S/13.19. So the order exists in SmartPedidos and was rejected 3.5 minutes after creation; it is not missing from SP.
- Timeline vs the Cosmos change: the Replace error trace is 2026-10-24T20:06:16Z, and the user's local files carry UTC-3 times (17:05-17:06 local). The new queue record was created after that. If the SP screen shows UTC-3 (16:54 = 19:54Z), the order was created and rejected BEFORE any change. If it shows Peru time (UTC-5, 16:54 = 21:54Z), it falls AFTER the change. The timezone of the screen is not known.
- "Rechazada por local cerrado" is a reason set on the SP/platform side; nothing seen so far connects it to the queue record. Not established why the branch counted as closed.

## Caveat 2026-10-24: `Checked` of the new 5435 record changed after the update (data/queues-5435-after-fix-item.json, user-pasted full item)
- The new item (`id` 4f1a186f-...) now shows `Checked` = 2026-10-24T20:14:40.5Z (before: 2025-12-17T01:41:41.9Z, copied into the new item). `UpdatedAt`, `DisabledAt`, `DisabledReason` still null; `Active` true, `Deleted` false. `_ts` 1792872880 = 2026-10-24T20:14:40Z, same second as `Checked`.
- By code reading (`AmazonServices.cs` `RefreshQueues`, clone `main` @ e00e8c467, file not diffed against origin/main): `Checked` is written when the consumer adds an Active, non-deleted queue that is not yet in its known-queues list, using (`FranchiseId`, `BranchId`) of the item as partition key. So the write suggests the consumer read the new item and added the queue to polling. Not confirmed with logs.
- It also implies the queue was not in the consumer's known list at that refresh. Why is unknown: it may have been dropped before the change (e.g. a worker error), or the service restarted. The previous `Checked` (2025-12-17) alone does not show when the queue was last added.
- Nothing else in the record changed after the update, and the consumer evidence is indirect: `Checked` is the only post-change signal.

## 2026-10-24 (user-reported): branch 3293 gets the same error
- Already in the dump (outputs/queues-franchiseid-mapping.csv): record `319ab771-b672-402e-9283-e452f4eb0288`, stored `FranchiseId` `6077c8b0ac9d445f98f12896f893aba3` (in neither franchise list), Active, `Checked` 2026-05-13 (not 2025-12-17). GRIDO franchise with `CodeSmartLogicId` 3293: Id 11, "Santa Fe VIII", `CloudCodeId` hex `7a56840b3ace4a2d83912a407f42cd38`. Which franchise the user is saving under was not stated.
- It is one of the stale records not dated 2025-12-17, so the stale ids are not all from that date; the 2025-12-17 grouping is a pattern in 33 of 38 stale records, not the whole set.
- No change made to 3293.

- 3293, live read (data/queues-3293-projection.json, user-pasted): fields `id`, `BranchId`, `FranchiseId`, `Active`, `Deleted`, `Checked` only (a projection, not the full item, so not a usable backup). Same values as the dump: stored `6077c8b0...`, Active true, Deleted false, `Checked` 2026-05-13T13:01:30Z. Missing for a rebuild: `FranchiseeId`, `QueueName`, `QueueUrl`, `TenantId`.

- 3293, franchise lookup (data/franchise-3293-check.json, user-pasted, database not stated): one franchise, Id 11, "Santa Fe VIII", `CodeSmartLogicId` 3293, `CloudCodeId` 7a56840b-3ace-4a2d-8391-2a407f42cd38 (hex `7a56840b3ace4a2d83912a407f42cd38`); matches the entry in data/franchises-grido.json. Still not stated which franchise the user is saving the POS under.

- 3293 full item saved (data/queues-3293-before-fix.json, user-pasted `SELECT *`): queue `3293PRD_PlatformMessages.fifo`, `TenantId` same as 5435's, `FranchiseeId` `14CC4707-...`, Active true, Deleted false, `Checked` 2026-05-13. Replacement item with a new `id` and `FranchiseId` `7a56840b3ace4a2d83912a407f42cd38` prepared in outputs/queues-3293-new-item.json; not applied. Pending: confirmation that the POS is saved under Santa Fe VIII, and the open items of 5435.

## Deliverable 2026-10-24: CSV of active queue records that can hit the same error (outputs/queues-franchiseid-problem.csv, 89 rows)
- Source: data/queues-full-merged.json (216 documents, read earlier today) + data/franchises-grido.json + data/franchises-weiss.json; join `BranchId` = GRIDO `CodeSmartLogicId`. Filters: Active, and `FranchiseId` either not in any list (38) or null (51). Inactive records are excluded.
- 34 stale + all 51 null have exactly one GRIDO franchise with that code ("candidato unico por codigo", unconfirmed: the join was only checked for 5435, 3717 and 3293); 3 stale have none; 1 stale is ambiguous (two franchises with the code).
- The 5435 row is marked "corregido en esta sesion" (its stored id was replaced); 3717 and 3293 are listed unmarked (not applied).
- The dump is a snapshot of today's read; records changed after it are not reflected. The null case blocking a save rests on code reading only.

- 3293 (user-reported): checked and it has the same problem. How it was checked (POS save error vs the Cosmos record) was not stated. Together with 3717 (reported earlier as the same error) and 5435 (reproduced), the error is reported in three branches; for 3717 and 3293 the stored id is absent from both franchise lists.

- 3293 (user-reported): "confirmed branch configuration". The franchise name was not given; read as confirmation that the POS is configured under Santa Fe VIII (Id 11), which is what the replacement item assumes. Not applied yet as far as recorded.

## Scope clarification 2026-10-24 (user): 3293 is out of scope and was NOT changed
- 3293 was read only to validate the hypothesis (stale `FranchiseId`); no fix is to be applied there. Same for 3717: it was reported as showing the error, but only 5435 (the ticket's POS) has been changed. The prepared items outputs/queues-3293-new-item.json and the 3717 candidate id are not to be applied within this ticket unless the scope changes.
- The earlier lines saying the 3293 fix is "pending" mean "prepared, not applied, out of scope". email_ops.md was edited accordingly (5435 only changed; 3717 reported; 3293 used to validate).

## Re-read of the 5435 record at about 17:40 local / 20:40Z (data/queues-5435-read-1740.json, user-pasted `SELECT *`; read time inferred from the file time)
- Same content as data/queues-5435-after-fix-item.json: same `_etag` and `_ts` (1792872880 = 20:14:40Z), `Checked` 2026-10-24T20:14:40Z, Active true, Deleted false. The record was not written again between 20:14:40Z and the read.
- By code reading (clone `main` @ e00e8c467), the sale point screen only prepares the queue object; `AddUpdateQueue` is called from the franchise screen (`Franchise.razor.cs`). So an unchanged record does not show whether a POS save was attempted or succeeded. The POS save result remains unreported.

## Result 2026-10-24 (user-reported): the 5435 POS now saves with the SmartPedidos integration
- The user reports that the POS save works after the queue record was recreated with `FranchiseId` `040fdf5d61c646cb9b39465291971e5d`, and that `Checked` was updated. The only `Checked` value seen in the data is 2026-10-24T20:14:40Z (data/queues-5435-after-fix-item.json and data/queues-5435-read-1740.json); if the user means a newer value, it was not pasted. No error text or screenshot of the save was saved.
- This confirms the fix for 5435 at the symptom level (the validation no longer blocks). Not established: the root cause of the stale ids, the other stale/null records (not changed), and any link between the change and order 2340698376 (timezone of that list still unknown).
- Open items: root cause of the stale `FranchiseId` values; bulk cleanup (needs the create-new/delete-old procedure per record, scope decision); the 51 null-`FranchiseId` records (blocking is from code reading only).

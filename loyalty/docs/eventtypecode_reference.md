# `sml.CustomerPointsLog.EventTypeCode` — Full Reference

**Source:** `SELECT DISTINCT EventTypeCode FROM sml.CustomerPointsLog` (confirmed 2026-07-22) — 36 values total.

Authoritative full list. `.claude/commands/loyalty-fraud-points.md` keeps only the "Confirmed" subset inline for fast lookup during an investigation — read this file when a query returns a code not covered there, or before promoting a "Named only" row to "Confirmed".

| EventTypeCode | Meaning | Status |
|---|---|---|
| `PointsByTransferSent` | Points leaving the account — sender side | Confirmed |
| `PointsByTransferReceived` | Points arriving at the account — receiver side | Confirmed |
| `EarnPointsByBuying` | Points earned from a POS purchase (`SaleId` + `ArticleId` populated) | Confirmed |
| `EarnPointsByPromotion` | Promotional bonus tied to a purchase (`PromotionId` + `SaleId` populated; can be 0 pts) | Confirmed |
| `Article99999WithoutPoints` | Purchase of a zero-point article (`SaleId` populated, always 0 pts) | Confirmed |
| `CompensationalPoints` | Manual administrative compensation (`ManualAssignPointsId` populated, no `SaleId`) — also an `AssignmentConcept` value | Confirmed |
| `DiscountPointsByExchange` | Points deducted in a redemption/exchange event (negative value) | Confirmed |
| `NewCustomer` | Welcome grant on account creation (typically 0 pts) | Confirmed |
| `RemovePointsBySaleInvalidation` | Points reversed due to cancelled sale (negative value) | Confirmed |
| `PrizePoints` | Manual grant, contest/prize channel (`ManualAssignPointsId` populated) — also an `AssignmentConcept` value. Root-cause of the 2026-07-22 mass-duplication incident (`events/20260722_puntos_duplicados_masivos_waf504/`) | Confirmed |
| `HumanResourcesPoints` | Grido HR manual grant — also an `AssignmentConcept` value | Confirmed |
| `InstitutionalPoints` | Institutional/internal manual grant — also an `AssignmentConcept` value | Confirmed |
| `DiscountPointsByPromotion` | Deduction tied to a promotion (distinct from `DiscountPointsByExchange`) | Named only — observed once in `actor_notes.md`; its literal also exists in the application source (searched in `loyalty/repo/dev-src-sol-smartloyalty` during `GITIN-1654`, together with `DiscountPointsByExchange`, `RemovePointsBySaleInvalidation`, `PointsByTransferSent`/`Received`); meaning not confirmed by query |
| `ManualPrizePoints` | Prize grant written by a manual SQL re-run of a campaign (`GITIN-1654`: 7,940 rows of 10,000, `Note = 'Puntos por visita frecuente'`); not in the 2026-07-22 `DISTINCT` list, which predates it | Confirmed (created by that remediation) |
| `SpecialPointsAssingment` | — | Named only (2026-07-22), not investigated |
| `ReturnPointsByExchageInvalidation` | Likely the reversal counterpart to `DiscountPointsByExchange` when a redemption is invalidated | Named only (2026-07-22), not investigated |
| `PointsDeactivated` | — | Named only (2026-07-22), not investigated |
| `PointsByUpdateData` | — | Named only (2026-07-22), not investigated |
| `PointsByCustomerIncentive` | — | Named only (2026-07-22), not investigated |
| `PointsAdjustmentbyScript` | — | Named only (2026-07-22), not investigated |
| `PointsAdjustmentBahiaBlanca` | Branch/region-specific adjustment (Bahía Blanca) | Named only (2026-07-22), not investigated |
| `PointsAdjustment-{uid}` | Dynamic suffix pattern — the literal `EventTypeCode` string carries a numeric uid (e.g. `PointsAdjustment-208414786`), not a fixed enum value. Do not `GROUP BY EventTypeCode` directly if these rows matter; strip the suffix first (`LEFT(EventTypeCode, CHARINDEX('-', EventTypeCode + '-') - 1)`) or filter with `LIKE 'PointsAdjustment-%'` | Named only (2026-07-22), not investigated |
| `PointsAdjustment` | — | Named only (2026-07-22), not investigated |
| `PointsAdjustmentBatchError-{batchid}` | Reversal rows written by the 2026-07-22 mass-duplication remediation: one negative-`Points` row per original row (`CustomerId` + `ManualAssignPointsId`), `Note = 'Ajustamos tu saldo por un error de asignacion de puntos'`; 37,645 rows that day (`events/20260722_puntos_duplicados_masivos_waf504/`). Same dynamic-suffix pattern as `PointsAdjustment-{uid}` | Confirmed (created by that remediation; not in the 2026-07-22 `DISTINCT` list, which predates it) |
| `NegativePointsAdjustment` | — | Named only (2026-07-22), not investigated |
| `GiftToSpecialCustomer` | — | Named only (2026-07-22), not investigated |
| `GiftToCustomer` | — | Named only (2026-07-22), not investigated |
| `GiftPointsNewMember` | Possibly overlaps with `NewCustomer` welcome grant | Named only (2026-07-22), not investigated |
| `FixErrorAssingment` | — | Named only (2026-07-22), not investigated |
| `ExpiredPoints` | Points removed on expiration (negative, presumed) | Named only (2026-07-22), not investigated |
| `BonusByWebData` | — | Named only (2026-07-22), not investigated |
| `BonusByExtraDataFormSelfManagement` | — | Named only (2026-07-22), not investigated |
| `BonusByExtraDataFormLimited` | — | Named only (2026-07-22), not investigated |
| `BonusByExtraDataForm` | — | Named only (2026-07-22), not investigated |
| `BonusByComplementaryDataForm` | — | Named only (2026-07-22), not investigated |
| `BonusByCampaignPromotionalCode` | — | Named only (2026-07-22), not investigated |
| `AsignPointsToEmployee` | Possibly overlaps with `HumanResourcesPoints` | Named only (2026-07-22), not investigated |
| `AddPointsCustomerBirthday` | — | Named only (2026-07-22), not investigated |

> **Inserting several rows for one customer in a single `INSERT`** (e.g. a bulk reversal): the trigger `[Sml].[CustomerPointsLogAfterInsert]` recomputes the cached balance in `SmlSt.CustomerPointsLog` by joining `inserted` to the customer's whole history, so a customer with N rows in the same statement has the recalculated balance multiplied by N (fan-out). The 2026-07-22 reversal avoided it by checking that its customers had 1 to 6 rows each before choosing the insert shape; check this before any bulk write to `Sml.CustomerPointsLog`.

> **Mass-duplication incident, 2026-07-22 (`GITIN-1654`, `events/20260722_puntos_duplicados_masivos_waf504/`):** a campaign sent through `MassivePointsAssignment` (`PrizePoints`, 10,000 per member) returned a WAF 504 to the browser, but the server-side process is not cancelled by the 504 (11 min to 1.5 h per run), and the operator re-sent the same lists, so concurrent runs wrote the same members several times (4 `Note` lists with overlapping members: 37,645 rows, 376,450,000 points, 7,940 members, 7,930 with `TotalPoints` over 10,000). The assignment is not idempotent (no `RequestId` or list hash). The fix was to reverse 100 % of the rows (one negative row per original row, `PointsAdjustmentBatchError-{batchid}`, in 6 passes of at most one row per customer to avoid the trigger fan-out above, `@@ROWCOUNT` checked before each `COMMIT`) and to re-assign by plain SQL (7,940 rows, a single `INSERT` because each customer appears once). At reversal time 99.96 % of the points were still active balance; 15 members had spent 48,100 points (`DiscountPointsByExchange`) and 17 had transferred 104,970 (`PointsByTransferSent`); no deactivated accounts. Recommendations made, not implemented: an idempotency key on `MassivePointsAssignment`/`AssignmentPointsCatalog`, a longer WAF timeout for that operation or an asynchronous flow. The `Login` of that investigation had `SELECT` on `Sml.CustomerPointsLog` and no permission on `Sml.ManualAssignPoints`. In the output of `GITIN-1654`'s own scripts `UidCode` is the document type and `UidSerie` the number (an inverted alias was corrected).

> **Manual grants without limits (`events/20260602_compensaciones_manuales_gsfernandez/`):** `Sml.ManualAssignPoints` accepts any `Points` value, sets `Status = Approved` automatically and has no `CHECK`, trigger, approver or mandatory `Catalog_Id`; nothing compares a grant with the daily/weekly/monthly caps (3,000 / 5,000 / 10,000). In that event 1,333 grants (22.2 %) exceeded 10,000 in one grant and 1,346 customer-month combinations received more than 10,000. The mechanism of a routine grant (`ManualAssignPoints` parent row, then `CustomerPointsLog` child with `ManualAssignPointsId`, as `CreateManualAssignPoints` + `NewGiftPointsToCustomer` do in `AssignmentPointsService.cs`/`CustomerService.cs`) was reproduced by hand in `20260805_asignacion_manual_puntos_serpa` (a legitimate `PrizePoints` request, no fraud angle): fill `RegisterByUser` with the real operator; a first run left the placeholder in it and a confirmation query (`NOLOCK`) caught it before the commit.

> When a "Named only" code becomes relevant to an investigation, confirm its actual meaning via query (sample rows, join to `ManualAssignPoints`/`Sale`/`PointsTransference` as applicable) before promoting it to "Confirmed" here — do not promote a row based on the name alone. Update this file in place when that happens; do not duplicate the row back into the skill file.

## Related

- `.claude/commands/loyalty-fraud-points.md` — keeps the 12 Confirmed codes inline, points here for the rest.
- `loyalty/memory/actor_notes.md` — where an unconfirmed code was last observed in the wild (e.g. `DiscountPointsByPromotion`).

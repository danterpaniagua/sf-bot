# `sml.CustomerPointsLog.EventTypeCode` — Full Reference

**Last updated:** 2026-07-30
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
| `DiscountPointsByPromotion` | Deduction tied to a promotion (distinct from `DiscountPointsByExchange`) | Named only — observed once in `actor_notes.md` (Bruno Mdm), not yet investigated |
| `SpecialPointsAssingment` | — | Named only (2026-07-22), not investigated |
| `ReturnPointsByExchageInvalidation` | Likely the reversal counterpart to `DiscountPointsByExchange` when a redemption is invalidated | Named only (2026-07-22), not investigated |
| `PointsDeactivated` | — | Named only (2026-07-22), not investigated |
| `PointsByUpdateData` | — | Named only (2026-07-22), not investigated |
| `PointsByCustomerIncentive` | — | Named only (2026-07-22), not investigated |
| `PointsAdjustmentbyScript` | — | Named only (2026-07-22), not investigated |
| `PointsAdjustmentBahiaBlanca` | Branch/region-specific adjustment (Bahía Blanca) | Named only (2026-07-22), not investigated |
| `PointsAdjustment-{uid}` | Dynamic suffix pattern — the literal `EventTypeCode` string carries a numeric uid (e.g. `PointsAdjustment-208414786`), not a fixed enum value. Do not `GROUP BY EventTypeCode` directly if these rows matter; strip the suffix first (`LEFT(EventTypeCode, CHARINDEX('-', EventTypeCode + '-') - 1)`) or filter with `LIKE 'PointsAdjustment-%'` | Named only (2026-07-22), not investigated |
| `PointsAdjustment` | — | Named only (2026-07-22), not investigated |
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

> When a "Named only" code becomes relevant to an investigation, confirm its actual meaning via query (sample rows, join to `ManualAssignPoints`/`Sale`/`PointsTransference` as applicable) before promoting it to "Confirmed" here — do not promote a row based on the name alone. Update this file in place when that happens; do not duplicate the row back into the skill file.

## Related

- `.claude/commands/loyalty-fraud-points.md` — keeps the 12 Confirmed codes inline, points here for the rest.
- `loyalty/memory/actor_notes.md` — where an unconfirmed code was last observed in the wild (e.g. `DiscountPointsByPromotion`).

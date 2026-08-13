# Investigation — 20260805_asignacion_manual_puntos_serpa

**Status:** converged — ready for ticket

## Confirmed facts

- Jacky requested a manual grant of 63,580 points, motivo "Puntos por Premio", for CustomerId `561BEF0E-3CE9-C29C-36D2-08DDF9361945`, DNI 16762109 (Q1).
- Verified CustomerId matches the given DNI: `sml.Person` → Claudia Serpa, DNI 16762109 (Q1).
- Motivo "Puntos por Premio" maps to `EventTypeCode`/`AssignmentConcept` = `PrizePoints` (`docs/eventtypecode_reference.md`).
- Insert built as a two-step transaction: `sml.ManualAssignPoints` (parent) then `sml.CustomerPointsLog` (child, `ManualAssignPointsId` FK), matching the app's own `CreateManualAssignPoints` + `NewGiftPointsToCustomer` pattern (`Core/Domain/Domain/AssignmentPointsContext/AssignmentPointsService.cs:196`, `Core/Domain/Domain/CustomerContext/CustomerService.cs:1208`).
- First execution left `RegisterByUser` as the unreplaced placeholder (`<usuario_que_ejecuta>`) — caught before commit via a `NOLOCK` confirmation query (Q3).
- Rerun with `RegisterByUser = 'dantep'`, committed. Final state confirmed via Q3 (Q4 rerun): `ManualAssignPointsId` 9835, `CustomerPointsLogId` 390056929, `Status = Approved`, `Points = 63580`, `AssignDate`/`LogDate` = 2026-08-05 19:32:07.19 UTC.

## Current working theory

N/A — routine, legitimate manual grant requested by Jacky. No fraud or anomaly angle; distinct in intent from `20260602_compensaciones_manuales_gsfernandez`, which used the same mechanism (`ManualAssignPoints`) for an exploit.

## Ruled out

- N/A.

## Open questions / next steps

- None. Grant is committed and confirmed.

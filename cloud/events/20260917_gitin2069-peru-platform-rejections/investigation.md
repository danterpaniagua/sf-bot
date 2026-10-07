# Investigation — 20260917_gitin2069-peru-platform-rejections

**Status:** converged — closed 2026-09-17 as an isolated event, probable derivative of GITIN-2068 (user's determination; not independently verified from the actual per-order rejection detail — see "Not yet done" below, left unresolved since the ticket closed before reaching it).

**Jira ticket:** [GITIN-2069](https://smartit-ar.atlassian.net/browse/GITIN-2069) ("Guardia 17-9-2026")

**Cross-project:** this may span SmartPedidos (where the rejection motive/state lives, `orders`/`news` collections) and SmartCloud (Orders API, where the pasted report data likely comes from). Placed under `cloud/` provisionally — project scope for this ticket not yet confirmed with the user.

**Related but distinct from GITIN-2068:** discovered while verifying the GITIN-2068 fix (Peru TimeZoneNotFoundException, already resolved ~16:11 ART today). Noticed a cluster of Peru orders (branch 5396, Pueblo Libre I) reaching state "Recibida" with motivo "Orden rechazada por plataforma Grido" in a report the user pasted. User's follow-up: "too many occurrences of 'Orden rechazada por plataforma' in Peru" — flagging this as its own real problem, not just normal/expected platform-level rejections.

## Reported symptom

An unusually high count of Peru orders being rejected by the Grido platform itself (motivo: "Orden rechazada por plataforma Grido" / "Orden rechazada por plataforma"), reaching final state "Recibida" (state 10, RECEIVED) rather than completing normally. Not yet confirmed whether this is isolated to branch 5396 (Pueblo Libre I) or spread across other Peru branches, nor whether the rate is actually anomalous compared to non-Peru branches or Peru's own historical baseline.

## Open questions

1. What is the actual rejection rate (count/percentage) for Peru vs. a baseline (other countries, or Peru historically before today)?
2. Is this isolated to branch 5396, or fleet-wide across the 35 Peru branches?
3. What does "rechazada por plataforma Grido" actually mean mechanically — a specific rejection reason code, and where is it set (SmartPedidos' `RejectedMessagesSingleton`, or a real response from Grido's platform API)?
4. Is this related to GITIN-2068's fix at all, or a fully separate, coincidentally-discovered issue?

## Real data, 2026-09-17

Two query mistakes caught before trusting the result (both silent-empty traps): first attempt queried the `orders` collection (rejection `extraData` actually lives in `news`, confirmed via `platformRejectStrategy.js`'s `news.find()`/`updateNew()` calls); second attempt then used a `timestamp` field that doesn't exist on `news` docs (they use `createdAt`). Fixed both, verified against a real sample doc before trusting the count.

**Peru overall, last 7 days:** 3071 `news` docs, 17 with `extraData.rejected.rejectMessageDescription` containing "rechazada por plataforma" — **0.55%**, spread across 12 of the 35 branches, mostly 1 each.

**Branch 5396 (Pueblo Libre I) is the outlier:** 4 rejections / 87 orders = **4.60%** — 4-8x every other Peru branch's rate (next highest: 1.18%, branches 5440/5423/5667). This is the same branch that had one of the original 12 GITIN-2068 historic stuck orders (`5507077`).

**Not yet confirmed:** whether this is genuinely anomalous (no fleet-wide non-Peru baseline pulled yet — the expensive unscoped query was abandoned) or within normal per-branch variance at this volume (87 orders is a small sample; 4 vs. an expected ~1 could plausibly be noise). Also not yet checked: what's actually causing branch 5396's rejections specifically — a menu/availability/config issue on the Grido platform side for that branch, unrelated to GITIN-2068.

## Not yet done

- Confirm whether 4.60% at n=87 is statistically meaningful or plausible noise, ideally against a same-branch historical baseline (prior weeks) rather than a fleet-wide one.
- Investigate the actual rejection reason/detail for branch 5396's 4 cases specifically.
- Confirm which project (`cloud/` vs `operations/`) and scope (just this rejection pattern vs. broader "Guardia" shift log) this ticket should actually live under — not yet confirmed with the user.

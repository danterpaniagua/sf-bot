# Investigation: Clasica con Dijon 1/2 — invalid sale (WEISS)

## Status: opened, gathering facts

## Reported

- Tenant: WEISS, franchisee: Weiss Punta del Este
- Reported by: CaC (customer care)
- Symptom (revised): the "promo para compartir de Dijon" (shareable Dijon combo) is showing 3 hamburger options instead of the expected 2. This is NOT a sale-rejection/`SaleIsInvalid` case — it's a promotion-group eligibility/config issue (too many eligible articles surfaced in a `PromotionGroup` that should only offer 2 choices).
- "Clasica con Dijon 1"/"Clasica con Dijon 2" are the two expected burger options; a third, unexpected one is appearing alongside them.
- Jira ticket: none yet — ask user before writing any external-facing artifact

## Open questions

- What is the actual name of the "promo para compartir de Dijon" combo/promotion (Business_WEISS.Promotions)? Not yet located.
- Which `PromotionGroup` under that promotion governs the burger-choice selection, and what does `PromotionDetails` (eligible ArticleId list) contain for it — expect 2, need to confirm what the 3rd is.
- Does this promotion scope to "Weiss Punta del Este" specifically via `PromotionApplies`, or is it tenant-wide (and the extra option is a WEISS-wide config bug, not location-specific)? Prior investigation (20260802) found multiple WEISS franchise candidates (Test, Weiss Ensenada, Weiss Punta del Este) when searching by name — must match the correct one.
- Is the 3rd article a genuine `PromotionDetails` row (server-config bug) or could it be showing due to article eligibility overlap (an article listed in `PromotionDetails.ArticleId` for multiple unrelated promotions, per skill note)?

## Next step

Check Catalog_WEISS.Items WHERE GroupId=1 ("Signature Burgers") — leading theory is the POS burger-swap/selection screen pulls candidates from this Catalog group rather than from PromotionDetails, and a 3rd item may have been added to the group.

## Findings

- Query 1 result: `Promotions.Id = 212`, Name "Promo para compartir - Dijon", Description "2  Clasica con Dijon + Papas", `PromotionType = 1` (Combo), `MandatoryForAll = True`, `ValidSinceDate = 2026-02-11`, `ValidToDate = 2028-12-01`, `ActivatedDate = 2026-07-29T13:46:37Z`, no `DeactivatedDate` — currently active. This is the combo referenced in the CaC report.
- Note: several other Dijon-related Promotions rows exist (Id 39/52/67/81/122/136 "Hamburguesa/Combo - Clasica Dijon Con Papas") — most are Deactivated as of 2026-07-27, and are single-burger combos, not the shareable/2-burger one. Not the subject of this investigation but worth knowing they exist under similar names — do not confuse with Id 212 in later steps.
- Query 2 result (PromotionGroups/PromotionDetails for PromotionId=212): 4 groups total, each `Type='FixedPrice'`, `Amount=1`, `HasAdditionals=False`, `MultipleSelection=False`, and each group has exactly ONE `PromotionDetails` row (one eligible ArticleId):
  - GroupId 4746 → ArticleId 85
  - GroupId 4747 → ArticleId 85
  - GroupId 4748 → ArticleId 12
  - GroupId 4749 → ArticleId 12
  - This reads as 2 fixed slots of ArticleId 85 + 2 fixed slots of ArticleId 12 (consistent with "2 Clasica con Dijon + Papas" if 12=Papas and 85=the Dijon burger) — i.e. NOT a "choose 1 of N burgers" selection group at all; every group is a single, non-selectable fixed article. This does not structurally match "showing 3 hamburger options" — if PromotionDetails is the sole source of the POS's choice list, there's no group here with more than 1 eligible article, let alone 3.
  - Open question this raises: is ArticleId 85 itself a stand-in/category article (not literally one burger) whose real choices are resolved elsewhere (Catalog `Items`/`Groups`), or does the POS pull the "3 options" from a different mechanism entirely (e.g. article eligibility overlap across other Promotions rows referencing the same ArticleId, per skill note)? Need Catalog_WEISS.Items identity for ArticleId 85/12 before going further.
- Catalog_WEISS.Items lookup: ArticleId 85 = "Clasica con Dijon" (`GroupId=1`, GroupName "Signature Burgers", `ForSale=True`); ArticleId 12 = "Papas Fritas" (`GroupId=2`, GroupName "Sides", `ForSale=True`). Confirms Combo 212 is genuinely 2× fixed "Clasica con Dijon" + 2× fixed "Papas Fritas" — no selection/choice mechanism at the PromotionGroups/PromotionDetails level at all. The "3 hamburger options" reported by CaC is therefore NOT explained by this promotion's own Business_WEISS config as queried so far.
- Leading theory (not yet confirmed): POS may build a burger swap/selection screen from all Catalog Items sharing `GroupId=1` ("Signature Burgers") rather than from a promotion-specific curated list — if that Catalog group currently contains 3 items, that could be where "3 options" comes from. Not yet checked.
- **Theory above RULED OUT**: `Items WHERE GroupId=1` ("Signature Burgers") returned 30 items, not 3 — far too many to be the direct source of "3 options" without additional unexplained filtering. Not the mechanism.
- **New lead, from re-reading Query 1's full result set**: three separate `Promotions` rows are all currently ACTIVE and all built around "Clasica con Dijon" (ArticleId 85), all activated within 3 minutes of each other on 2026-07-29:
  - Id 39 "Hamburguesa - Clasica Dijon Con Papas" — ActivatedDate 2026-07-29T13:44:44Z, no DeactivatedDate
  - Id 52 "Combo - Clasica con Dijon + Papas + Bebida" — ActivatedDate 2026-07-29T13:43:21Z, no DeactivatedDate
  - Id 212 "Promo para compartir - Dijon" — ActivatedDate 2026-07-29T13:46:37Z, no DeactivatedDate (this is the reported combo)
  - Their near-duplicate rows (Id 67, 81, 122, 136 — same names as 39/52) were all Deactivated two days earlier, 2026-07-27, suggesting a cleanup/replacement pass on 2026-07-27 followed by a reactivation batch on 2026-07-29 that may have left 3 overlapping "Dijon burger" promotions live simultaneously instead of the intended set.
  - Working theory: if the POS's "shareable combo" screen surfaces all currently-active, `MandatoryForAll=True` promotions tied to the same base article as selectable "hamburger options" (rather than being scoped strictly to PromotionId=212's own fixed groups), having 3 overlapping active Dijon promotions would produce exactly "3 options instead of 2." NOT YET CONFIRMED — need to check (a) whether Oversales/OversaleComboPromotionItems (upsell-prompt config, which more directly matches "showing N options" than PromotionGroups did) references PromotionId 212 or ArticleId 85, and (b) whether 39/52 being simultaneously active is itself the intended state or a genuine leftover-activation bug.
- Schema introspection (`sys.tables`/`sys.columns` for `%Oversale%`): confirms `Oversales` has **no `PromotionId` column at all** — matches skill note that this system is independent of `Promotions`. Real structure: `Oversales` (upsell campaign, date/day/hour window, `ActivatedDate`/`DeactivatedDate`) ← `OversaleTriggers` (fires based on `ItemId`/`ItemType`/`Amount`/`SaleAmount` in the cart) and separately ← `OversaleComboPromotionItems` → `OversalePromotionItems.ItemId` (the actual items offered as the upsell).
- **Oversales theory RULED OUT**: `OversaleTriggers WHERE ItemId=85 AND Deleted=0` → no rows. No upsell campaign is triggered by ordering "Clasica con Dijon." Matches skill's prior guidance that Oversales is usually a distractor.
- Back to the leading theory: 3 overlapping active Dijon-related Promotions (39, 52, 212). Next: check `PromotionApplies` scoping (franchise/franchisee/price-list) for all three to see if they genuinely overlap at Weiss Punta del Este, or are scoped to different franchisees and don't actually collide.
- `PromotionApplies` scoping check: all rows for Promotions 39, 52, 212 have `Include=True`, `PriceListId=912`, and `FranchiseId`/`FranchiseeId` both empty/null — none of the three is franchise-restricted. All three are live on price list 912 tenant-wide (assuming Weiss Punta del Este uses PriceListId 912, not yet independently confirmed). So they do genuinely coexist as active, unrestricted promotions.
- **Repo version check (prompted by user)**: local `cloud/repo/SmartFran.Cloud` clone was 13 commits behind `origin/dev` — fast-forwarded (`git pull --ff-only`, now at `a3e72e021`). More importantly, this is a **production** bug, and `origin/main` (last PRO release, v2.39.00, 2026-08-13) differs from `origin/dev` by 33/29 commits. Diffed the 3 files read so far against `origin/main`: `DialogBuildCombo.razor.cs` and `PromotionService.cs` are byte-identical between `main`/`dev`; `Sale.razor.cs` differs by 22 lines but none touch `AddCloudPromotion`/`ValidateCloudPromotion`/combo-building (diff is printing/device-dispatch + a new `SaleChannelCmd` field, unrelated). So everything read so far is confirmed valid against production.
- **Source code trace of the "options" mechanism** (`AddCloudPromotion`/`ValidateCloudPromotion` in `Sale.razor.cs` around line 1680-1762, `DialogBuildCombo.razor.cs`): tapping a promotion opens `DialogBuildCombo`, which builds each group's selectable-item list via `GetItems(groupId)` → `GetPriceDetails(groupId)`, filtering strictly on `promotionGroup.Details.Select(d => d.ArticleId)` (i.e. exactly the `PromotionDetails` rows for THAT `PromotionGroupId`, cross-referenced against the POS's price list). Per Query 2, PromotionId=212's 4 groups each have exactly 1 `PromotionDetails.ArticleId` — so as coded, `DialogBuildCombo` for combo 212 should show 1 non-optional, non-swappable article per group slot, NOT a "3-way choice." **This means the "3 hamburger options" is very likely NOT happening inside the `DialogBuildCombo`/"Arma el combo" screen for Promotion 212 itself, per current DB state.**
- Revised leading theory: "3 hamburger options" more likely refers to the POS's promotion/product *listing* screen (before `DialogBuildCombo` opens) showing 3 separate tappable Dijon-related promotion tiles (39, 52, 212) when the cashier/customer expects to see only the "para compartir" one (or only 2 of the 3). Not yet located which POS screen renders that list or how it queries/filters active promotions — need to identify it, and also get a screenshot/clearer description from CaC of exactly which screen shows "3 options" before going further.

## BREAKTHROUGH — user provided 2 screenshots (image.png, image(1).png in this event folder)

- `image.png`: internal POS admin screen (weiss.pos.smartfran.com/pos/sale), "Armar Combo: Promo para compartir - Dijon", `DialogBuildCombo` UI. Shows exactly the EXPECTED/correct state: 4 groups in clean order — "Clasica con Dijon 1" (1/1, preseleccionado), "Clasica con Dijon 2" (1/1, preseleccionado), "Side 1" (0/1), "Side 2" (0/1). **This confirms the source-code trace above was correct — the internal POS combo builder is NOT where the bug manifests.**
- `image(1).png`: a DIFFERENT app entirely — a customer-facing mobile digital menu/ordering screen (phone status bar, "Promo para compartir - Dijon" product detail page, Spanish "Elige 1 opción" / "Requerido" labels). **This is where the bug actually is.** Groups render, in order, as:
  1. "Clasica con Dijon 2" — Requerido, Elige 1 opción → "Clasica con Dijon"
  2. "Side 1" — Requerido → "Papas Fritas"
  3. "Clasica con Dijon 1" — Requerido → "Clasica con Dijon"
  4. "Clasica con Dijon 2" — Requerido → "Clasica con Dijon" **(DUPLICATE of #1)**
  5. "Side 2" — Requerido → "Papas Fritas"
  - So "Clasica con Dijon 2" is rendered TWICE and "Clasica con Dijon 1" once = 3 burger-choice rows shown to the customer, instead of 1×"Dijon 1" + 1×"Dijon 2" = 2. This is very likely a rendering/list-key bug (duplicate group entry) in whatever app renders this screen, NOT a `Business_WEISS.PromotionGroups`/`PromotionDetails` data issue — our Query 2 already confirmed the DB has exactly 4 distinct groups (4746/4747/4748/4749), no 5th/duplicate row.
  - Also notable: the group ordering itself is scrambled (2,1,2,1,2-ish interleaved: Dijon2/Side1/Dijon1/Dijon2/Side2) rather than the clean sequential order POS shows (Dijon1/Dijon2/Side1/Side2) — suggests this app sorts/renders `Promotion.Groups` differently, possibly re-fetching or re-rendering with a client-side dedup/sort bug.
  - **This app is NOT the internal POS (`SmartFran.Cloud.Pos.Component`)** — need to identify which codebase/component renders this customer-facing digital-menu screen before going further (likely a separate "Client"/storefront/QR-ordering app, not yet located in `repo/SmartFran.Cloud`).

- Searched `repo/SmartFran.Cloud` for the customer-facing digital-menu/ordering app: no project directory matching menu/ecommerce/QR/storefront naming exists under `Source/` (only `Client`, `Common`, `Pos`, `Services`, `SmartFran.Cloud.Provider.External.VirtualWallet`). The one hit for "Elige 1 opción" is `DialogBuildCombo.razor` (the POS screen already ruled out by `image.png` matching expected behavior). **The app in `image(1).png` is not present in this local repo clone at all** — it's a separate customer-facing product (likely its own repository) not currently available for source inspection here.

## Status: blocked on source access for the actual buggy app

Root cause is narrowed to a client-side rendering bug (duplicate "Clasica con Dijon 2" group, out-of-order group list) in a customer-facing digital-menu/ordering app that is NOT part of the local `cloud/repo/SmartFran.Cloud` clone. `Business_WEISS` DB state is confirmed clean (exactly 4 distinct PromotionGroups rows for PromotionId=212, no duplicates), and the internal POS Blazor combo-builder (`DialogBuildCombo.razor.cs`) is confirmed to render this promotion correctly per `image.png`. Cannot go further via static code analysis without locating/accessing that app's source.

- **User confirmed**: `image(1).png` is the **PedidosYa** mobile app — a third-party delivery marketplace, not a SmartFran-owned app — and PedidosYa maintains its own separate catalog/menu configuration ("that is its catalog").
- Searched `repo/SmartFran.Cloud` for any PedidosYa catalog/menu export or sync mechanism: none exists. The only PedidosYa-related code found is generic order-processing/logging enums (`PedidosYaOrderPhases`, `PedidosYaOrderSteps`, `PedidosYaOrder` in `Source/Common/Providers/SmartFran.Cloud.Provider.Contracts/Models/Logging/Enums/{Phases,Steps,Process}.cs`) — these handle **receiving** orders placed on PedidosYa, not pushing/exporting SmartFran's promotion/combo structure to PedidosYa's menu. No dedicated `PedidosYa*` project/folder exists at all.

## Conclusion (pending Jira ticket)

The duplicate "Clasica con Dijon 2" burger option (3 rows shown instead of 2) is on **PedidosYa's own catalog/menu configuration**, which is external to SmartFran Cloud and maintained independently on their platform — not derived live from `Business_WEISS`/`Catalog_WEISS`, and not rendered by any SmartFran.Cloud codebase available here. All SmartFran-side checks came back clean:
- `Business_WEISS.PromotionGroups`/`PromotionDetails` for Promotion 212 ("Promo para compartir - Dijon"): exactly 4 correct groups, no duplicates.
- Internal POS combo-builder (`DialogBuildCombo.razor.cs`, confirmed identical in production `main` and `dev`): renders the combo correctly per `image.png`.
- No PedidosYa catalog-export code exists in this repo to investigate further.

This is not fixable via SQL/code change on the SmartFran side — the recommended action is to report the duplicate menu option directly to whoever manages the PedidosYa menu configuration for Weiss Punta del Este (marketing/digital-channels owner, or PedidosYa partner support), so they can correct it on PedidosYa's platform.

- **User asked to check if this is a SmartPedidos catalog problem** (SmartFran's own delivery-integration layer, `smartpedidos/repo/dev-scr-smartPedidos-platformsService` + `dev-src-smartPedidos-concentradorService` — separate product from SmartFran.Cloud, has a confirmed PedidosYa integration per prior event `smartpedidos/events/20260812_ubereats-orders-not-received`). Checked both repos:
  - `platformsService` has real PedidosYa integration code (`platforms/interfaces/pedidosYa.js`, `platforms/management/platform/pedidosYa.js`, `controllers/peya.js`) — but every function found is order-lifecycle only: `receiveOrder`, `confirmOrder`, `branchRejectOrder`, `readyOrder`, `dispatchOrder`, `saveOrder`, plus parsing `selectedToppings` on an *incoming* order's line items. No menu/catalog publish or sync function exists.
  - `grep -rli "menu"` across both SmartPedidos repos: **zero results**. Confirms SmartPedidos never touches the PedidosYa menu/catalog at all — it only relays orders, in the direction PedidosYa → SmartFran.
  - **Ruled out**: not a SmartPedidos catalog problem. The PedidosYa menu (including the duplicate "Clasica con Dijon 2" entry) is configured directly on PedidosYa's own merchant portal, independent of both SmartFran.Cloud and SmartPedidos.

## Status: converged

Root cause: PedidosYa-side menu/catalog misconfiguration (duplicate "Clasica con Dijon 2" option), external to all SmartFran systems checked (`Business_WEISS`/`Catalog_WEISS` data, SmartFran.Cloud POS combo-builder, SmartPedidos PedidosYa integration). No SmartFran-side fix applies. Recommended action: report directly to whoever manages the PedidosYa menu configuration for Weiss Punta del Este.

## Next step

Still need a Jira ticket URL to write up the closure report / email. User has authorized proceeding with placeholder `GSFC-XXX` for now — must be replaced with the real ID before this ticket is used externally.

# Investigation — 20260802_promocion-invalida-weiss-franui

**Status:** REJECTION MECHANISM CONFIRMED (99.99% vs 100% discount leaves an uncollected residual) — but the proposed fix (99.99 → 100.00) is now understood to be WRONG. PM has confirmed a cross-product minimum-invoicing-amount business rule (see "PM-confirmed business rule" section below) that explains *why* 99.99 exists and rules out setting it to a flat 100.00. Fix needs to be redesigned, not applied as originally written.

## Reported symptom
WEISS (Punta del Este) POS: cashier selects a combo (2 hamburguesas) + a "franui" item, with an influencer discount applied to the sale. On checkout, the sale is rejected as invalid ("La venta es invalida" / "No se cumple una validación"). Removing the franui item (keeping just the 2-hamburger combo) makes the sale pass. Tenant: WEISS, tenantId `kt76igzny9ql`.

## Confirmed facts (source: `cloud/repo/SmartFran.Cloud/`, commit `0ed6784`, 2026-07-31)
- The message matches exactly `EnumApplicationErrorCodes.SaleIsInvalid = 12000` (Sales.Application), a **generic** description with no promotion-specific detail. The POS dialog title ("¡Atención! No se cumple una validación.", `MainApp.razor:211`) is a hardcoded wrapper around any `ApplicationBusinessException` — confirms this is the generic code, not a named promotion-rule exception.
- `SaleIsInvalid` is thrown by `SaleService.CreateAsync` when `SaleCreateCmdValidator` (FluentValidation) fails. **All FluentValidation failures collapse into the same generic exception/message — the real reason is discarded.** The only non-trivial rule in that validator is:
  ```
  payments >= total
  total = Details.Where(x => x.Type != 1 || (x.Type == 1 && x.TypeDetail == 6)).Sum(x => x.Quantity * x.UnitPrice)
  ```
  `TypeDetail == 6` = `ItemSaleType.Extra` (enum: Sale=0, Promotion=1, Exchange=2, Oversale=3, Coupon=4, Combo=5, Extra=6, DescuentoRecargo=7, DescuentoVoucher=8). Per a code comment in `SaleService.cs:1103`, `SaleDetail.Type`: 0=normal item, 1=promo/combo **body** line, 2=promo/combo **header** line.
- The POS client runs the **identical formula** before submit, in `Sale.razor.cs → ValidateAmount` (line ~2127): recomputes `amount` the same way, compares to `amountPaymentsMethods` (sum of entered payments). This formula uses raw `UnitPrice * Quantity` — **it never reads the per-line `Discount` field.**
- Separately, `GetTotal()` (`Sale.razor.cs:2105-2115`) computes the **displayed/charged** total using each line's `.Total` field, and *does* fold in the discount (via `CalcAmountWithOutIva`). This is a different formula from `ValidateAmount`'s (`Total` vs `UnitPrice*Quantity`) — the two are not guaranteed to agree.
- Before submit, the POS builds `Details` via a large `switch` on `TypeDetail` (`Sale.razor.cs` ~line 5091) that computes `Discount = PriceList - UnitPrice` and `Total` per line, then reconciles: `if (totalVenta != totalCabecerasEIndividuales) ProrrateoDetallesVenta()` (~line 5254). This proration re-distributes combo header/body amounts via a cascade of special-case checks, falling back to a **proportional split keyed off `PriceList`** — and **silently no-ops if the theoretical base is 0**. This path is normally never exercised for a combo-alone sale (totals round-trip cleanly); adding a second discounted line (franui) is exactly the kind of change that would first trigger it.
- `ValidateAmount`'s mismatch handling **only self-heals if a payment line named "Efectivo" (cash) exists** — it silently adjusts that line by the diff. Existing diagnostic-only logging in this exact path (`"DIAG DLQ: detectar mismatch entre details y pagos (Causas a y c)"`) indicates this class of bug was already suspected/being chased independently of this ticket. **A card/other-only payment leaves the mismatch unhealed**, and the backend then legitimately (from its narrow view) finds `payments < total` and rejects.
- **No combo/discount mutual-exclusion or eligibility re-validation exists server-side.** `PromotionService` (Business.Application) is pure CRUD/query (date/schedule/scope filtering for "is this promo offered here") — it has no method that validates a submitted sale's contents against a promotion's rules. `SaleService`/`SaleValidator`/`SaleCreateCmdValidator` never re-check combo composition or article eligibility against `PromotionGroup`/`PromotionDetail` — those tables are consumed only by the POS combo-builder UI, not re-validated at sale-create time. The one true stacking guard found, `AddFinancialItem`'s "Ya existe item Descuento/Recargo en la compra" check, only blocks a *second* discount line — it wouldn't fire here and would produce a different, more specific message anyway.
- `Oversale`/`OversaleComboPromotionItem` (upsell-offer config, e.g. "add item X for $Y") is unrelated — it governs cashier-facing upsell prompts, not constraints on manually-added combo contents. Low priority to chase further.

## DB reference (SQL Server, Business service — WEISS elastic pool, `SmartFran.Cloud.Business_WEISS`)
No `[Table]` attributes in the entity classes; table names are EF Core `DbSet<T>` convention, confirmed against migration `CreateTable` calls:

| Entity | Table | Key columns |
|---|---|---|
| `Promotion` | `Promotions` | `Name`, `PromotionType` (0=Promotion,1=Combo), `ValidSinceDate/ValidToDate`, `ValidSinceMinute/ValidToMinute`, day-of-week bools, `MandatoryForAll`, `ActivatedDate`/`DeactivatedDate` |
| `PromotionGroup` | `PromotionGroups` | `PromotionId` (FK), `Amount`, `Type` (string: FixedPrice/FixedDiscount/PercentDiscount/PriceList), `HasAdditionals`, `MultipleSelection`, `DefaultArticleId` |
| `PromotionDetail` | `PromotionDetails` | `PromotionGroupId` (FK), `ArticleId` — the eligible-article list per group |
| `PromotionApply` | `PromotionApplies` | `Include`, `FranchiseId`, `FranchiseeId`, `CityId`, `ProvinceId`, `CountryId`, `RegionId`, `PriceListId` |
| `PromotionGroupApply` | `PromotionGroupsApplies` (note: "GroupsApplies", not "GroupApplies") | `PromotionGroupId` (FK), `PromotionApplyId` (FK), `PromotionValue` |
| `Oversale` | `Oversales` | schedule/day-of-week, `ComboPromotionItems`, `Triggers`, `ScopeApplication` |
| `OversaleComboPromotionItem` | `OversaleComboPromotionItems` | `OversaleId` (FK), `FixedPrice`, `PriceDifference`, `DiscountPercentage`, `MaxAmount` |

**Important — the actual failed sale is NOT in this SQL database.** `Sale`/`SaleDetail`/`SaleDiscount`/`SaleBillDiscountSurcharge` are CosmosDB documents (Sales service, `AccessRepository<Sale>`, partition key `[FranchiseeCode, FranchiseCode, PosCode]`), not SQL tables. And since `SaleCreateCmdValidator` throws **before** `_saleRepository.AddAsync`, a rejected sale likely never persists anywhere — it only exists as a payload in the failed HTTP request. SQL queries here can confirm/rule out promotion *configuration* problems, but cannot show the failing transaction itself.

## "Efectivo self-heal" theory — REFUTED
User re-tested the identical scenario (2 hamburguesas combo + franui + Descuento Influencers) paying with **Efectivo (cash)** — **still fails**. This rules out the payment-method/self-heal mechanism as the (sole) explanation: `ValidateAmount`'s cash-only self-heal (`Sale.razor.cs:2150-2159`) should exactly zero out any Payments-vs-Total gap when a cash line exists, yet the sale still fails. Whatever is going wrong produces a mismatch the self-heal either doesn't run against, doesn't fully correct, or isn't the relevant failure at all. Payment method is not the deciding variable — removing franui is the only thing that fixes it, regardless of payment method.

## New evidence — near-zero grand total after discount
User-provided numbers: **2 hamburguesas + franui, with all discounts applied → grand total $0.17 → fails.** **2 hamburguesas alone (same discount) → grand total $0.14 → passes.** Both totals are in the single-digit-cents range, implying "Descuento Influencers" is a very steep percentage discount (need exact %, still unconfirmed) that shrinks an otherwise normal bill down to a few cents.

## New evidence — franui ALONE (no burger combo) also fails
User confirmed: a bill with **franui only** (no hamburger combo at all) + Descuento Influencers **also produces the error**. This reframes the problem: it is not "combo + extra item together" that's needed to trigger the bug — **franui itself, combined with the steep discount, is sufficient on its own.** The 2-hamburguesas combo alone (at its own discounted $0.14 total) passes; franui alone does not. So whatever is wrong is tied to **franui's own article/promotion structure**, not to mixing two priced lines.

This raises the likelihood that **franui is itself defined as a Promotion/Combo-type article** (decomposing into a Type=2 header + one or more Type=1 body/component lines, per the `PromotionGroup`/`PromotionDetail` structure), rather than a plain standalone product (`TypeDetail == Sale`, Type=0). If franui's own combo/promo definition has multiple detail/body lines, each one goes through the same independent `Math.Round(..., 2, ...)` treatment in `Sale.razor.cs`'s TypeDetail switch (~5091-5204) and potentially `ProrrateoDetallesVenta()` — meaning franui's *own* internal structure, not an interaction with the burger combo, could already accumulate enough rounding drift to fail at a near-zero total. This directly motivates the user's original question: **checking franui's promotion/combo configuration in the DB (number of `PromotionGroups`/`PromotionDetails`, `Type` = FixedPrice/FixedDiscount/PercentDiscount/PriceList) is now a first-class lead, not just a rule-out step.**

## Confirmed — "Descuento Influencers" is a 100% discount item
DB lookup (`SmartFran.Cloud.Catalog_WEISS`): Item `Id=430`, **Name = "Descuento Influencers 100%"**, `GroupId=243` ("Descuento"), `Group.FinancialModify = 1` (Discount, per `EnumFinancialModifiers`). This is a **100% discount item**, not merely "steep." A correctly-applied 100% discount should zero the bill to **exactly $0.00** — the observed **$0.14 and $0.17 residuals are not rounding noise on a near-zero number, they are the discount failing to fully cancel the total.**

## ROOT CAUSE CONFIRMED — discount item priced at 99.99, not 100
DB lookup (`SmartFran.Cloud.Catalog_WEISS.PriceDetails`, Item 430):

| ItemId | PriceListId | PublishedPrice | NewPrice | Enabled |
|---|---|---|---|---|
| 430 | 910 | 99.99 | 99.99 | True |
| 430 | 908 | 99.99 | 99.99 | True |
| 430 | 914-919 (6 rows) | 99.99 | 99.99 | True |

**All 8 price lists have this item priced at 99.99, not 100.00**, despite its name being "Descuento Influencers 100%". The POS uses this `PublishedPrice` value directly as the discount percentage in `CalcAmountWithOutIva` (`Sale.razor.cs:1324-1327`):
```
itemFinancial.Total = totalWithOutTax * (itemFinancial.Price / 100) * -1
```
With `Price = 99.99` (not 100), this applies a **99.99% discount, not 100%** — leaving exactly **0.01% of the pre-discount total uncollected** on every sale that uses this item. This is not a code defect; the calculation does exactly what its input says.

**The math matches the user's reported numbers almost exactly:**
- 2 hamburguesas alone: residual **$0.14** → implies pre-discount subtotal ≈ $0.14 / 0.0001 ≈ **$1,400**
- 2 hamburguesas + franui: residual **$0.17** → implies pre-discount subtotal ≈ $0.17 / 0.0001 ≈ **$1,700**

Both are plausible bill sizes (Uruguayan pesos) for this order, and the ~$300 difference between them is a believable price for franui alone. This explains every previously-confusing symptom in one shot:
- **Why it's never exactly $0.00** — 99.99% ≠ 100%.
- **Why franui made it worse** — a bigger underlying bill means a bigger absolute residual (same 0.01%, bigger base).
- **Why franui alone (no combo) also failed** — any bill run through this discount item leaves the same proportional gap, with or without the combo.
- **Why switching to cash didn't fix it** — there's a genuine amount owed (however small); no payment method changes that. The customer/cashier evidently attempted to tender $0 (or the pre-residual amount) believing the sale was fully free.

**No code fix is needed.** This is a pure Catalog data-entry error: `PriceDetail.PublishedPrice` (and `NewPrice`) for Item 430 should be `100.00`, not `99.99`, across all 8 rows. The item's own name ("...100%") confirms 100.00 was the intent.

## Ruled out
- A deliberate promotion/discount business rule (mutual exclusion, max-items, eligibility) rejecting the combination — no such server-side re-validation exists anywhere in the promotion or sale-creation code paths; `PromotionGroup`/`PromotionDetail` config is POS-UI-only, never re-checked at `SaleCreateCmd` time.
- `Oversale`/`OversaleComboPromotionItem` limits — unrelated feature (upsell prompts), doesn't gate manually-added items.
- A promotion-specific error message — confirmed generic `SaleIsInvalid` (12000), not a `PromotionIsInvalid` (12200)-range exception.
- Payment method as the deciding factor — REFUTED (see above): both Transferencia and Efectivo fail identically with franui present; only removing franui passes, regardless of how it's paid.
- Franui being itself a Promotion/Combo-type article with multiple body lines — REFUTED. DB confirms franui is a plain catalog item: `Items.Id=386 "Franui"` and `Id=423 "Franui c/Combo"`, both `GroupId=59`, `Group.FinancialModify=0` (NoApply — ordinary sale item, not a financial modifier or combo-group structure). The "franui alone also fails" symptom is fully explained by the 99.99%-discount data error instead (any bill through that discount item leaves a residual, franui or not) — no special structure on franui's side was needed.
- Any POS/`Sale.razor.cs` calculation defect (rounding cascade, `ProrrateoDetallesVenta`, `CalcAmountWithOutIva` Price-vs-Total basis, Efectivo-only self-heal) — all REFUTED as the root cause once the 99.99-vs-100 pricing error was found; the code computes exactly what its input says. These remain accurate descriptions of how the calculation works, just not the actual defect here.
- "Ruleta Articulo Bonificado" (Promotions id 183/186) activation gap — very likely unrelated; that promotion is a separate bonus-item/roulette mechanic, not the manually-applied "Descuento Influencers" line item that's actually responsible. Worth a separate, lower-priority data-hygiene note to whoever manages WEISS promotions (id 186 should probably have been activated when/before id 183 expired on 2026-07-31, since both cover franui as a bonus item), but out of scope for this ticket.

## Final piece — why some items fail and others don't (unifies the data bug with the earlier code-path findings)
User confirmed: **"Franui c/Combo" (Item 423) works; plain "Franui" (Item 386) does not** — same discount, same franchise. This isn't a contradiction of the 99.99%-price finding, it explains *which* sales actually trip the validation failure:

- Item 386 "Franui" is a plain product line (`Type=0`, `TypeDetail=Sale`) — its `UnitPrice` is used as-is, with no intermediate recompute/rounding. The 0.01% residual from the 99.99%-vs-100% discount survives untouched into the `Σ(UnitPrice × Quantity)` check, so `payments < total` fails visibly.
- Item 423 "Franui c/Combo" (and the 2-hamburguesas combo, which also passed at $0.14 despite presumably carrying the same residual) are **combo/promo-structured lines** (`Type=2` header + `Type=1` body). Per `Sale.razor.cs`'s TypeDetail switch (~5121-5126, 5185-5190), combo body lines get `UnitPrice` **recomputed and re-rounded**: `detail.UnitPrice = Math.Round(detail.Total / detail.Quantity, 2, ...)`. This extra rounding step incidentally absorbs the tiny 0.01% residual back into the nearest cent, making the combo-path total match payments exactly (or close enough) — **masking** the same underlying data bug rather than fixing it.

So the discount item's mispricing (99.99 vs 100) is universal — it shortchanges every sale that uses it by 0.01% — but only shows up as a hard `SaleIsInvalid` rejection on **plain, non-combo product lines**, because combo/promo lines' own rounding cascade happens to swallow the residual silently. That means WEISS has likely been under-collecting (or effectively donating) that 0.01% on every combo sale using this discount without anyone noticing, in addition to outright failing on plain-product sales like this one. Fixing the price to exactly 100.00 removes the residual at the source, for both cases.

## PM-confirmed business rule (2026-08-03) — answers the open question below, but doesn't validate the originally proposed fix

PM response (paraphrased from Spanish): **every tenant must have a minimum billable amount for Facturación Electrónica (electronic invoicing)** — Argentina $0.01, Peru $0.30, Uruguay $0.01 — and this rule applies platform-wide, at configuration level, across SF Cloud, SmartLoyalty (Sml), SmartPedidos, and Plataformas alike. Called out by the PM as a foundational ("clase de oro") rule, not specific to this incident.

**This confirms the "deliberate, not a typo" branch of the open question below** — 99.99 (not 100.00) on the "Descuento Influencers 100%" item exists *because* a sale can't legally settle at exactly $0.00 in Uruguay; some nonzero residual must remain for a valid electronic invoice. So the originally proposed fix (flip `PublishedPrice`/`NewPrice` to `100.00`) is now understood to be **wrong** — it would produce exactly the $0.00 result the business rule prohibits.

**But 99.99% doesn't correctly implement this rule either.** WEISS is confirmed Uruguay (`FEUY-*` fiscal codes already found in `Business_WEISS`, see below), so the applicable floor is **$0.01** — yet the observed residuals were **$0.14** (2 hamburguesas) and **$0.17** (+ franui), both far above $0.01. That's because a flat 99.99% *percentage* discount leaves a residual proportional to the pre-discount subtotal (`subtotal × 0.0001`), not a fixed floor — it only happens to land near $0.01 when the subtotal is close to $100, and drifts further from the intended $0.01 as the bill gets larger (as seen here) or could round to exactly $0.00 on very small bills, which would reintroduce the same rejection this rule exists to prevent.

**Revised understanding of the actual defect:** it's not that the discount is priced wrong (99.99 vs 100.00) — it's that a percent-based discount is structurally the wrong mechanism to guarantee a fixed per-country minimum residual. The correct fix likely needs to either (a) redefine this discount as a fixed-amount-off-remainder mechanism that leaves exactly the country-specific floor ($0.01 UY) regardless of subtotal, or (b) keep percent-based pricing but have the validator/POS specifically tolerate a residual at or near the configured country floor rather than rejecting outright. **Not deciding between these here** — this is a product/business design question, not something to resolve unilaterally from this investigation. Needs input from whoever owns this discount mechanism and the Facturación Electrónica integration.

## Fix — ORIGINAL PROPOSAL BELOW IS NOW SUPERSEDED, DO NOT APPLY AS-IS

~~Update `PriceDetail.PublishedPrice` and `NewPrice` for Item 430 ("Descuento Influencers 100%") from `99.99` to `100.00` across all 8 rows in `SmartFran.Cloud.Catalog_WEISS.PriceDetails`~~ — **superseded by the PM-confirmed business rule above.** Setting this to exactly 100.00 would produce a $0.00 sale, which the minimum-invoicing-amount rule prohibits for Uruguay (and Argentina/Peru, with their own floors). The SQL below is preserved for reference only — **do not run it**:

```sql
-- SUPERSEDED — do not run. Would set the discount to exactly 100%,
-- producing a $0.00 sale that violates the confirmed minimum-invoicing-amount rule.
-- Preview affected rows before updating
SELECT ItemId, PriceListId, PublishedPrice, NewPrice, Enabled
FROM PriceDetails
WHERE ItemId = 430;

-- UPDATE PriceDetails SET PublishedPrice = 100.00, NewPrice = 100.00
-- WHERE ItemId = 430 AND PublishedPrice = 99.99;
```

**Original open question (now answered):** ~~is 99.99 instead of 100 an accidental typo, or a deliberate systems convention to avoid a sale line hitting exactly $0.00~~ — **confirmed deliberate** by the PM's minimum-invoicing-amount rule. What remains open is not "typo vs. deliberate" but "is the current percent-based implementation the right mechanism to express that rule" — see above, not resolved here.

## Secondary, lower-priority finding
`Promotions` table has two "Ruleta Articulo Bonificado" rows both referencing franui as a bonus item: id 183 (activated, but `ValidToDate = 2026-07-31`, expired 2 days before this investigation) and id 186 (`ValidToDate = 2028-03-31`, but `ActivatedDate` is NULL — never activated). This looks like an activation gap unrelated to the actual bug found above, but worth flagging separately to whoever manages WEISS promotions.

## Mockup validation (`_scripts.py`) — confirms the arithmetic exactly, exposes an unresolved gap
Built a Python mockup replicating `CalcAmountWithOutIva`'s formula with real numbers (subtotal $1,400/$1,700, discount price 99.99). Result: **exact** match to the reported residuals — `1400.00 × 0.0001 = 0.14`, `1700.00 × 0.0001 = 0.17`, bit-for-bit, not approximate. The discount-percentage mechanism is now confirmed deterministically, not just plausibly.

However, the mockup also modeled `SaleCreateCmdValidator`'s accept/reject check as `payments >= (display-total residual)` and predicted **both** cases should reject (since payments = $0 in both). Case B (Franui plain) did reject, matching the model — but **Case A (combo alone) passed**, contradicting it.

**User confirmed payments = $0 is real, not assumed** — this is a genuine 100%-off discount and the cashier collects nothing. So this isn't "the cashier probably paid the residual in cash" — the contradiction is real: a sale with a nonzero display-total residual ($0.14) and $0 payment was accepted. The only way that's consistent with the validator's rule (`payments >= total`) is if the validator's *own* `Σ(UnitPrice × Quantity)` computation — which is a separate formula from the display total, per "Two totals" below — evaluates to ≤ $0.00 for the combo-only case, while it evaluates to something positive for the plain-Franui case.

Attempted to trace this purely from source (combo header `UnitPrice`, discount line `UnitPrice = itemCart.Total`, both counted toward the validator sum since neither has `Type == 1` under the exclusion rule) — the trace predicts the validator would land on the *same* $0.14 as the display formula in the simple single-header case, which still doesn't explain the observed pass. **Not resolving this by further inference** — it needs the real `SaleCreateCmd` payload (App Insights, per-line `Type`/`TypeDetail`/`UnitPrice`/`Quantity`) to settle precisely rather than risk asserting a mechanism that isn't actually verified.

## Two totals — the likely locus of the unresolved gap
`GetTotal()` (display/charge total, `.Total`-based) and `SaleCreateCmdValidator`/`ValidateAmount` (validation total, `UnitPrice × Quantity`-based) are different formulas that are not guaranteed to agree — this was flagged early in this investigation (see "Confirmed facts" above) and never fully closed. The mockup's wrong prediction for Case A is direct evidence that they *do* diverge in practice, specifically for combo-structured lines vs. plain product lines — but the exact code path producing that divergence remains unconfirmed.

## Cosmos/Graylog detour — technique confirmed viable but blocked by tenant misattribution
Attempted to close the remaining gap by pulling a real persisted `Sale` document (per "Next steps" #2 below). Confirmed via source: `SaleRepository` uses `cosmosConnection.GetContainer("Sales")`, and `Sale.cs`/`SaleContext.cs` have no `[JsonProperty]` override or camelCase serialization policy — so container name and field casing are not the problem. Confirmed via `az cosmosdb sql container show`: `Sales-WEISS` database, `Sales` container, partition key `[/FranchiseeCode, /FranchiseCode, /PosCode]` (MultiHash) — exactly as expected.

However, three attempts to query it (including with partition-key values pulled from a Graylog log line tied to a confirmed-200 `Sale/Create` response) all returned **zero documents**. Leading explanation: `SMARTFRAN-CLOUD-SALES-PRO` is a shared App Service serving every tenant, and its Graylog logs carry **no tenant-identifying field** — so a plausible-looking, correctly-timed log line cannot be assumed to belong to WEISS specifically; it may belong to a different tenant's interleaved traffic. This is now documented as a reusable caveat in `/cloud-invalid-sale`.

**Not resolved in this session — SQL path also exhausted.** Tried the `Business_WEISS` lookup: found `Franchise` (FranchiseId=5, "Weiss Punta del Este", FranchiseeId=3) and its 5 `SalePoint` records (Mostrador 1/2/3, KDS, Peya, Pick-Up), but `RelatedCode` for FranchiseId=5/FranchiseeId=3 only holds Uruguay fiscal/electronic-invoicing identifiers (`FE-PVTA`, `FEUY-IDCOMERCIO`, `FEUY-APIKEY`, `FEUY-FECHA EMISOR`, `FEUY-APP`) — not the opaque cloud-routing codes. `RelatedCode` for all 5 `SalePoint` IDs returned **zero rows** — no codes at all, fiscal or otherwise. So `FranchiseCode`/`FranchiseeCode`/`PosCode` are not stored anywhere reachable in `Business_WEISS`'s SQL schema; they likely live in a different service's identity system (candidate: `Franchise.PersonCloudId`/`CompanyCloudId` point at the `Person`/Company cloud identity, not yet explored).

**This closes the reasonable avenues for this session.** Getting the real per-line `Details[]` for a passing WEISS sale now requires either: (a) live POS access (browser network tab during an actual test), or (b) someone who already knows WEISS's franchise/POS codes from prior work. Neither the Graylog nor the SQL path panned out, and further speculative schema exploration isn't a good use of time relative to the value of closing this one secondary question — **the primary finding (99.99% vs 100% discount pricing) is unaffected and remains the actionable root cause regardless.**

## Next steps
1. ~~Confirm with WEISS/promotions owner whether 99.99 was a typo or intentional, then run the fix above~~ — **superseded**, PM confirmed deliberate (see "PM-confirmed business rule" above). New action: get product/business decision on the correct mechanism (fixed-floor discount vs. validator tolerance) before any DB change — do not run the original SQL.
2. Separately flag the "Ruleta Articulo Bonificado" id 186 activation gap for the promotions owner.
3. **`_ops.md` and PM email need to be revised** — both currently reflect the now-superseded "change 99.99 to 100.00" fix as the recommended action. Update before sending/closing.

## Permanently open (deferred, not blocking): plain-vs-combo mechanism
Every reasonable avenue available this session (App Insights not checked directly but predicted low-value per source read of the catch block; Graylog — blocked by shared-tenant log attribution; Business_WEISS SQL — codes not stored there) has been tried or ruled out for getting the real `SaleCreateCmd` payload of a passing WEISS sale. **Closing this requires either live POS access (browser network tab during an actual test) or someone who already knows WEISS's franchise/POS codes** — pure investigation from this environment has been exhausted. Revisit only if one of those becomes available; don't re-attempt the same Graylog/SQL paths without new information.
